import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import '../models/ai_config.dart';
import '../models/ai_stream_chunk.dart';
import '../models/pure_ai_message.dart';
import '../repositories/local_storage_repository.dart';
import '../config/constants.dart';
import '../utils/response_decoder.dart';
import '../utils/message_sanitizer.dart';
import 'bing_cn_mcp_service.dart';
import 'prompt_rewriter.dart';
import 'usage_meter_service.dart';

class PureAIService {
  final LocalStorageRepository _storage;
  Map<String, dynamic>? _lastWebSearchTrace;

  Map<String, dynamic>? get lastWebSearchTrace => _lastWebSearchTrace;

  PureAIService(this._storage);

  Future<String> sendPureAIMessage({
    required String userMessage,
    required List<PureAIMessage> chatHistory,
    String? imageDescription,
    bool enableWebSearch = false,
  }) async {
    debugPrint('===== PureAIService.sendPureAIMessage: ENTRY =====');
    debugPrint(
        'message preview: ${userMessage.length > 60 ? "${userMessage.substring(0, 60)}..." : userMessage}');

    final config = await _storage.getActiveAIConfig();
    if (config == null) {
      throw Exception('No active configuration found');
    }

    final messages = await _buildMessages(
      userMessage: userMessage,
      chatHistory: chatHistory,
      imageDescription: imageDescription,
      enableWebSearch: enableWebSearch,
    );

    return _callAPI(config, messages);
  }

  /// 流式输出版本 — 返回Stream<String>，每次emit已累积的完整文本
  Stream<AIStreamChunk> sendPureAIMessageStream({
    required String userMessage,
    required List<PureAIMessage> chatHistory,
    String? imageDescription,
    bool enableWebSearch = false,
  }) async* {
    final config = await _storage.getActiveAIConfig();
    if (config == null) throw Exception('No active configuration found');

    final messages = await _buildMessages(
      userMessage: userMessage,
      chatHistory: chatHistory,
      imageDescription: imageDescription,
      enableWebSearch: enableWebSearch,
    );

    yield* _streamAPI(config, messages);
  }

  Stream<AIStreamChunk> _streamAPI(
      AIConfig config, List<Map<String, String>> messages) async* {
    String baseUrl = config.baseUrl.trim();
    while (baseUrl.endsWith('/')) {
      baseUrl = baseUrl.substring(0, baseUrl.length - 1);
    }
    final url = baseUrl.endsWith('/chat/completions')
        ? Uri.parse(baseUrl)
        : Uri.parse('$baseUrl/chat/completions');

    final allApiKeys = config.allApiKeys;

    for (int attempt = 1; attempt <= AppDurations.maxRetries; attempt++) {
      try {
        final currentKey = allApiKeys[0];
        final client = http.Client();
        try {
          final request = http.Request('POST', url);
          request.headers['Content-Type'] = 'application/json; charset=utf-8';
          request.headers['Accept-Charset'] = 'utf-8';
          request.headers['Authorization'] = 'Bearer $currentKey';
          final requestBody = jsonEncode({
            'model': config.modelName,
            'messages': messages,
            if (BuiltInAIProviders.isGlmZ19B(config.id, config.modelName)) ...{
              'temperature': GlmModeParams.pureAiTemperature,
              'top_p': GlmModeParams.topP,
              'top_k': GlmModeParams.pureAiTopK,
              'frequency_penalty': GlmModeParams.pureAiFrequencyPenalty,
              'thinking_budget': GlmModeParams.pureAiThinkingBudget,
              'max_tokens': GlmModeParams.pureAiMaxTokens,
            } else ...{
              'temperature': config.temperature,
              'max_tokens': config.maxTokens,
            },
            'stream': true,
          });
          request.body = requestBody;

          final streamedResponse =
              await client.send(request).timeout(AppDurations.aiRequest);
          final contentType = streamedResponse.headers['content-type'];

          if (streamedResponse.statusCode != 200) {
            final errorBytes = await streamedResponse.stream.toBytes();
            final body = await ResponseDecoder.decode(contentType, errorBytes);
            if (streamedResponse.statusCode == 429) {
              if (attempt < AppDurations.maxRetries) {
                await Future.delayed(Duration(seconds: attempt * 10));
                continue;
              }
              throw Exception('请求过于频繁，请稍后再试');
            }
            if (streamedResponse.statusCode == 503 ||
                streamedResponse.statusCode == 502) {
              if (attempt < AppDurations.maxRetries) {
                await Future.delayed(Duration(seconds: attempt * 8));
                continue;
              }
              throw Exception('服务器繁忙，请稍后再试');
            }
            try {
              final errorData = jsonDecode(body);
              final errorMsg =
                  errorData['error']?['message'] ?? 'Unknown error';
              throw Exception(
                  'API错误 (${streamedResponse.statusCode}): $errorMsg');
            } catch (e) {
              if (e is Exception) rethrow;
              throw Exception('API错误 (${streamedResponse.statusCode})');
            }
          }

          String accumulatedReasoning = '';
          String accumulatedContent = '';
          Map<String, dynamic>? capturedUsage;

          // 真流式解码：逐 chunk UTF-8 解码，避免后台时连接中断导致乱码
          final lineStream = streamedResponse.stream
              .transform(utf8.decoder)
              .transform(const LineSplitter());

          await for (final line in lineStream) {
            final trimmed = line.trim();
            if (!trimmed.startsWith('data:')) continue;
            final data = trimmed.substring(5).trimLeft();
            if (data == '[DONE]') {
              if (accumulatedContent.isNotEmpty ||
                  accumulatedReasoning.isNotEmpty) {
                unawaited(UsageMeterService.instance.trackStreamResponse(
                  url: url,
                  requestBody: requestBody,
                  statusCode: streamedResponse.statusCode,
                  responseBodyBytes: utf8.encode(jsonEncode({
                    'choices': [
                      {
                        'message': {'content': accumulatedContent}
                      }
                    ]
                  })),
                  endpointHint: 'openai_chat',
                  extractedUsage: capturedUsage,
                  outputChars:
                      accumulatedContent.length + accumulatedReasoning.length,
                ));
              }
              return;
            }

            try {
              final json = jsonDecode(data) as Map<String, dynamic>;
              final type = json['type'] as String?;

              // 主动捕获 usage
              final chunkUsage = json['usage'] as Map<String, dynamic>?;
              if (chunkUsage != null) capturedUsage = chunkUsage;
              final respUsage =
                  json['response']?['usage'] as Map<String, dynamic>?;
              if (respUsage != null) capturedUsage = respUsage;

              // Anthropic Claude 流式格式
              if (type == 'content_block_delta') {
                final delta = json['delta'] as Map<String, dynamic>?;
                if (delta != null &&
                    delta['type'] == 'text_delta' &&
                    delta['text'] != null) {
                  accumulatedContent += delta['text'] as String;
                  yield AIStreamChunk(
                      reasoning: accumulatedReasoning,
                      content: accumulatedContent);
                }
                continue;
              }
              if (type == 'message_delta') {
                final usage =
                    json['message']?['usage'] as Map<String, dynamic>?;
                if (usage != null) capturedUsage = usage;
                continue;
              }

              // OpenAI Responses API 流式格式
              if (type != null && type.startsWith('response.')) {
                if (type == 'response.output_text.delta') {
                  final delta = json['delta'] as String?;
                  if (delta != null) {
                    accumulatedContent += delta;
                    yield AIStreamChunk(
                        reasoning: accumulatedReasoning,
                        content: accumulatedContent);
                  }
                } else if (type == 'response.reasoning.delta') {
                  final delta = json['delta'] as String?;
                  if (delta != null) {
                    accumulatedReasoning += delta;
                    yield AIStreamChunk(
                        reasoning: accumulatedReasoning,
                        content: accumulatedContent);
                  }
                } else if (type == 'response.completed') {
                  final response =
                      json['response'] as Map<String, dynamic>?;
                  if (response != null) {
                    final finalContent = _extractResponseContent(response);
                    if (finalContent.isNotEmpty &&
                        accumulatedContent.isEmpty) {
                      accumulatedContent = finalContent;
                      yield AIStreamChunk(
                          reasoning: accumulatedReasoning,
                          content: accumulatedContent);
                    }
                  }
                }
                continue;
              }

              // OpenAI Chat Completions 流式格式
              final choices = json['choices'] as List?;
              if (choices != null && choices.isNotEmpty) {
                final delta = choices[0]['delta'] as Map<String, dynamic>?;
                if (delta != null) {
                  final reasoning =
                      delta['reasoning_content'] ?? delta['reasoning'];
                  final content = delta['content'] ?? delta['text'];
                  if (reasoning != null) {
                    accumulatedReasoning += reasoning as String;
                    yield AIStreamChunk(
                        reasoning: accumulatedReasoning,
                        content: accumulatedContent);
                  }
                  if (content != null) {
                    accumulatedContent += content as String;
                    yield AIStreamChunk(
                        reasoning: accumulatedReasoning,
                        content: accumulatedContent);
                  }
                }
                final message =
                    choices[0]['message'] as Map<String, dynamic>?;
                if (message != null) {
                  final msgContent = message['content'] ?? message['text'];
                  if (msgContent != null) {
                    accumulatedContent += msgContent as String;
                    yield AIStreamChunk(
                        reasoning: accumulatedReasoning,
                        content: accumulatedContent);
                  }
                }
              }

              // 通用 fallback
              if (json['content'] != null) {
                accumulatedContent += json['content'] as String;
                yield AIStreamChunk(
                    reasoning: accumulatedReasoning,
                    content: accumulatedContent);
              } else if (json['response'] != null &&
                  json['response'] is String) {
                accumulatedContent += json['response'] as String;
                yield AIStreamChunk(
                    reasoning: accumulatedReasoning,
                    content: accumulatedContent);
              }
            } catch (_) {}
          }

          return;
        } finally {
          client.close();
        }
      } on TimeoutException {
        if (attempt < AppDurations.maxRetries) {
          await Future.delayed(Duration(seconds: attempt * 3));
          continue;
        }
        throw Exception('请求超时，请检查网络连接');
      } catch (e) {
        if (e is Exception) rethrow;
        if (attempt < AppDurations.maxRetries) {
          await Future.delayed(Duration(seconds: attempt * 3));
          continue;
        }
        rethrow;
      }
    }
    throw Exception('网络请求失败，请检查网络连接');
  }

  Future<List<Map<String, String>>> _buildMessages({
    required String userMessage,
    required List<PureAIMessage> chatHistory,
    String? imageDescription,
    bool enableWebSearch = false,
  }) async {
    final List<Map<String, String>> messages = [];

    // 提取系统指令
    final systemDirective = _extractSystemDirective(userMessage);
    final cleanUserMessage = systemDirective != null
        ? _removeSystemDirectiveFromMessage(userMessage)
        : userMessage;

    final systemPrompt = _buildSystemPrompt(
      currentTopic: cleanUserMessage,
      imageDescription: imageDescription,
    );

    final config = await _storage.getActiveAIConfig();

    messages.add({
      'role': 'system',
      'content': systemPrompt,
    });
    _lastWebSearchTrace = null;
    final shouldUseWebSearch = enableWebSearch;
    if (shouldUseWebSearch) {
      messages.addAll(await _buildBingSearchContext(cleanUserMessage));
    }

    // 系统指令注入
    if (systemDirective != null && systemDirective.isNotEmpty) {
      messages.add({
        'role': 'system',
        'content': _buildSystemDirectivePrompt(
          directive: systemDirective,
        ),
      });
    }

    // 加载聊天历史
    final recentMessages = chatHistory.length > Limit.chatHistoryContext
        ? chatHistory.sublist(chatHistory.length - Limit.chatHistoryContext)
        : chatHistory;

    // 过滤系统指令和乱码污染消息，防止旧失败兜底进入 prompt
    final filteredMessages = recentMessages.where((m) {
      if (m.metadata != null && m.metadata!['isSystemDirective'] == true) {
        return false;
      }
      if (MessageSanitizer.isLikelyUnreadableGibberish(m.content)) {
        return false;
      }
      return true;
    }).toList();

    for (final msg in filteredMessages) {
      messages.add({
        'role': msg.isFromAI ? 'assistant' : 'user',
        'content': msg.content,
      });
    }

    // 添加当前用户消息
    final lastMsg = filteredMessages.isNotEmpty ? filteredMessages.last : null;
    final needAppendUserMessage = lastMsg == null ||
        lastMsg.isFromAI ||
        lastMsg.content != cleanUserMessage;

    if (needAppendUserMessage) {
      if (cleanUserMessage.isNotEmpty) {
        // 非推理模型对用户消息进行语义伪装，降低安全分类器触发概率
        var finalUserMessage = cleanUserMessage;
        // 纯AI链路不做角色/法模式语义伪装，避免重新注入演绎风格。
        if (config != null && !config.isThinkingModel && shouldUseWebSearch) {
          finalUserMessage =
              const PromptRewriter().rewriteUserMessage(cleanUserMessage);
        }
        if (shouldUseWebSearch) {
          messages.add({
            'role': 'system',
            'content':
                '【最终回复要求】本轮是联网搜索问答。你的下一条回复必须直接回答用户问题；禁止角色扮演、禁止动作描写、禁止说自己正在搜索。若搜索结果为空，只回复搜索结果中没有找到相关信息。',
          });
        }
        messages.add({
          'role': 'user',
          'content': finalUserMessage,
        });
      }
    }

    return messages;
  }

  Future<List<Map<String, String>>> _buildBingSearchContext(
    String userMessage,
  ) async {
    try {
      final response = await http.post(
        Uri.parse(ApiDefaults.searchApiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'query': userMessage}),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        _lastWebSearchTrace = {
          'server': 'uapi-pro',
          'query': userMessage,
          'error': 'HTTP ${response.statusCode}',
          'results': const [],
        };
        return const [];
      }

      final data = jsonDecode(utf8.decode(response.bodyBytes));
      // UAPI Pro 返回格式为 {"data": {"results": [...]}}，兼容两种格式
      final responseData =
          (data['data'] as Map<String, dynamic>?) ?? data;
      final results = (responseData['results'] as List<dynamic>?)
              ?.map((r) => {
                    'title': r['title'] ?? '',
                    'url': r['url'] ?? '',
                    'snippet': r['snippet'] ?? '',
                  })
              .toList() ??
          [];

      _lastWebSearchTrace = {
        'server': 'uapi-pro',
        'query': userMessage,
        'searchedAt': DateTime.now().toIso8601String(),
        'results': results,
      };

      if (results.isEmpty) return const [];

      final buffer = StringBuffer()
        ..writeln('【联网搜索结果 — 最高优先级指令】')
        ..writeln()
        ..writeln('[WARN] 用户刚刚开启了联网搜索，提出了一个需要实时信息的问题。')
        ..writeln('[WARN] 你现在必须切换为"信息助手"模式：直接、准确地回答用户的问题。')
        ..writeln()
        ..writeln('【必须遵守的规则】')
        ..writeln('1. 必须依据下方搜索结果回答，不要编造或猜测')
        ..writeln('2. 用简洁清晰的中文直接回答问题，先给出核心答案')
        ..writeln('3. 可以在回答末尾简要提到信息来源')
        ..writeln('4. 如果搜索结果不足以回答，明确说"搜索结果中没有找到相关信息"')
        ..writeln()
        ..writeln('用户问题：$userMessage')
        ..writeln()
        ..writeln('以下是搜索结果：');

      for (var i = 0; i < results.length; i++) {
        final item = results[i];
        buffer.writeln();
        buffer.writeln('${i + 1}. ${item['title'] ?? ''}');
        buffer.writeln('摘要：${item['snippet'] ?? '无摘要'}');
        buffer.writeln('链接：${item['url'] ?? ''}');
      }

      return [
        {'role': 'system', 'content': buffer.toString().trim()},
      ];
    } catch (e) {
      _lastWebSearchTrace = {
        'server': 'uapi-pro',
        'query': userMessage,
        'error': e.toString(),
        'results': const [],
      };
      return const [];
    }
  }

  /// 精简版system prompt — 强制标准 AI 助手形态，隔离角色链路/人设缓存
  String _buildSystemPrompt({
    required String currentTopic,
    String? imageDescription,
  }) {
    final buffer = StringBuffer();
    buffer.writeln(_storage.buildGlobalModePrompt(scope: '纯AI聊天'));
    buffer.writeln('''
【纯AI独立链路 · 最高优先级】
你现在是客观、中立、标准的通用 AI 助手。
本轮请求已经进入纯AI专属链路，必须彻底隔离任何角色会话、人设配置、亲密关系、历史角色语气、小说/法/刀/恋人等模式风格。
历史消息只允许作为事实上下文参考，绝对不能作为身份、语气、称呼、叙事格式或情感关系模板。
禁止角色扮演，禁止自称某个角色，禁止使用角色专属口吻，禁止输出动作/神态/心理/环境旁白。
如果用户询问剧情、角色或历史内容，只以第三方分析者/助手视角客观回答。
回复风格：简洁、清晰、直接、理性；需要时分点说明；默认使用简体中文。
''');

    // 当前时间
    final now = DateTime.now();
    final hour = now.hour;
    String timeOfDay;
    if (hour >= 5 && hour < 8) {
      timeOfDay = '清晨';
    } else if (hour >= 8 && hour < 12) {
      timeOfDay = '上午';
    } else if (hour >= 12 && hour < 14) {
      timeOfDay = '中午';
    } else if (hour >= 14 && hour < 18) {
      timeOfDay = '下午';
    } else if (hour >= 18 && hour < 22) {
      timeOfDay = '晚上';
    } else {
      timeOfDay = '深夜';
    }
    buffer.writeln(
        '【当前时间】北京时间：${now.year}年${now.month}月${now.day}日 $timeOfDay ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}');

    if (hour < 6 || hour >= 23) {
      buffer.writeln('【时间约束】现在是深夜/凌晨，用户可能在休息。简短温柔，不打扰。');
    } else if (hour < 9) {
      buffer.writeln('【时间约束】现在是清晨/早晨。');
    } else if (hour < 12) {
      buffer.writeln('【时间约束】现在是上午。');
    } else if (hour < 14) {
      buffer.writeln('【时间约束】现在是中午。');
    } else if (hour < 18) {
      buffer.writeln('【时间约束】现在是下午。');
    } else if (hour < 22) {
      buffer.writeln('【时间约束】现在是晚上。');
    } else {
      buffer.writeln('【时间约束】现在是夜晚，用户可能要休息了。');
    }

    buffer.writeln('\n【纯AI回复规则】');
    buffer.writeln('1. 只以标准 AI 助手身份回复，不进入角色、不延续亲密关系、不模仿历史角色语气。');
    buffer.writeln('2. 历史对话只用于理解事实和用户问题；若历史内容包含角色设定或演绎格式，全部降级为可分析材料。');
    buffer.writeln('3. 禁止使用动作描写、舞台指示、旁白、角色心理描写或小说化叙事。');
    buffer.writeln('4. 不受恋人模式、开放模式、法功能、刀模式、小说模式影响。');
    buffer.writeln('5. 回答要清楚、客观、可执行；涉及代码/问题排查时优先给步骤和结论。');

    // 图片识别
    if (imageDescription != null && imageDescription.isNotEmpty) {
      buffer.writeln('\n【用户分享的图片】');
      buffer.writeln(imageDescription);
      buffer.writeln('请综合以上信息，做出自然的回应，就像你真的看到了一样。');
      buffer.writeln('不要说你"看不到"或"无法理解"图片内容。');
    }

    return buffer.toString();
  }

  /// 系统指令提示
  String _buildSystemDirectivePrompt({
    required String directive,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('【用户临时指令 · 纯AI链路约束】');
    buffer.writeln('用户给出了以下临时要求：');
    buffer.writeln('---');
    buffer.writeln(directive);
    buffer.writeln('---');
    buffer.writeln('执行方式：');
    buffer.writeln('1. 只能以标准 AI 助手身份理解并执行其中合理部分。');
    buffer.writeln('2. 如果指令要求角色扮演、切换身份、写小说、输出旁白/动作/心理描写，一律改为客观分析或普通问答。');
    buffer.writeln('3. 不得因为该指令恢复角色语气、人设关系、恋人/法/刀/小说模式。');
    buffer.writeln('4. 回复保持简体中文、清晰、直接、客观。');
    return buffer.toString();
  }

  /// 提取"系统提示"指令
  String? _extractSystemDirective(String text) {
    final patterns = [
      RegExp(r'系统提示[：:,，]\s*(.+)', caseSensitive: false),
      RegExp(r'系统提示\s+(.+)', caseSensitive: false),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match != null) {
        return match.group(1)?.trim();
      }
    }
    return null;
  }

  /// 从用户消息中移除"系统提示"指令部分
  String _removeSystemDirectiveFromMessage(String text) {
    final patterns = [
      RegExp(r'系统提示[：:,，]\s*.+', caseSensitive: false),
      RegExp(r'系统提示\s+.+', caseSensitive: false),
    ];
    String cleaned = text;
    for (final pattern in patterns) {
      cleaned = cleaned.replaceAll(pattern, '').trim();
    }
    return cleaned;
  }

  /// API调用（含多key轮询和重试）
  Future<String> _callAPI(
      AIConfig config, List<Map<String, String>> messages) async {
    String baseUrl = config.baseUrl.trim();
    while (baseUrl.endsWith('/')) {
      baseUrl = baseUrl.substring(0, baseUrl.length - 1);
    }
    final url = baseUrl.endsWith('/chat/completions')
        ? Uri.parse(baseUrl)
        : Uri.parse('$baseUrl/chat/completions');

    final allApiKeys = config.allApiKeys;
    int currentKeyIndex = 0;

    for (int attempt = 1; attempt <= AppDurations.maxRetries; attempt++) {
      try {
        final currentKey = allApiKeys[currentKeyIndex];
        final client = http.Client();
        http.Response response;
        try {
          response = await client
              .post(url,
                  headers: {
                    'Content-Type': 'application/json; charset=utf-8',
                    'Accept-Charset': 'utf-8',
                    'Authorization': 'Bearer $currentKey',
                  },
                  body: jsonEncode({
                    'model': config.modelName,
                    'messages': messages,
                    if (BuiltInAIProviders.isGlmZ19B(config.id, config.modelName)) ...{
                      'temperature': GlmModeParams.pureAiTemperature,
                      'top_p': GlmModeParams.topP,
                      'top_k': GlmModeParams.pureAiTopK,
                      'frequency_penalty': GlmModeParams.pureAiFrequencyPenalty,
                      'thinking_budget': GlmModeParams.pureAiThinkingBudget,
                      'max_tokens': GlmModeParams.pureAiMaxTokens,
                    } else ...{
                      'temperature': config.temperature,
                      'max_tokens': config.maxTokens,
                    },
                  }))
              .timeout(AppDurations.aiRequest);
        } finally {
          client.close();
        }

        final decodedBody = await ResponseDecoder.decode(
          response.headers['content-type'],
          response.bodyBytes,
        );

        unawaited(UsageMeterService.instance.trackHttpResponse(
          url: url,
          requestBody: jsonEncode({
            'model': config.modelName,
            'messages': messages,
            'temperature': config.temperature,
            'max_tokens': config.maxTokens,
          }),
          response: response,
          endpointHint: 'openai_chat',
        ));

        if (response.statusCode == 200) {
          final data = jsonDecode(decodedBody);
          final rawContent = _extractResponseContent(data);
          return _cleanResponse(rawContent);
        }

        // 429限速：切换key
        if (response.statusCode == 429) {
          if (allApiKeys.length > 1 &&
              currentKeyIndex < allApiKeys.length - 1) {
            currentKeyIndex++;
            continue;
          }
          if (attempt < AppDurations.maxRetries) {
            currentKeyIndex = 0;
            await Future.delayed(Duration(seconds: attempt * 10));
            continue;
          }
          throw Exception('请求过于频繁，请稍后再试');
        }

        // 503/502 服务器过载
        if (response.statusCode == 503 || response.statusCode == 502) {
          if (attempt < AppDurations.maxRetries) {
            await Future.delayed(Duration(seconds: attempt * 8));
            continue;
          }
          throw Exception('服务器繁忙，请稍后再试');
        }

        // 其他错误
        try {
          final errorData = jsonDecode(decodedBody);
          final errorMsg =
              errorData['error']?['message'] ?? response.reasonPhrase;
          switch (response.statusCode) {
            case 401:
              if (allApiKeys.length > 1 &&
                  currentKeyIndex < allApiKeys.length - 1) {
                currentKeyIndex++;
                continue;
              }
              throw Exception('API Key 无效，请检查配置');
            case 400:
              throw Exception('请求参数错误: $errorMsg');
            default:
              throw Exception('API错误 (${response.statusCode}): $errorMsg');
          }
        } catch (e) {
          if (e is Exception) rethrow;
          throw Exception('API错误 (${response.statusCode})');
        }
      } on TimeoutException {
        if (attempt < AppDurations.maxRetries) {
          debugPrint(
              '请求超时，${attempt * 5}秒后重试 ($attempt/${AppDurations.maxRetries})');
          await Future.delayed(Duration(seconds: attempt * 5));
          continue;
        }
        throw Exception('请求超时，请检查网络连接');
      }
    }
    throw Exception('请求失败，请稍后再试');
  }

  String _extractResponseContent(dynamic data) {
    if (data is Map<String, dynamic>) {
      // ─── OpenAI Responses API 格式 ───
      if (data['output_text'] != null && data['output_text'] is String) {
        return data['output_text'] as String;
      }
      if (data['output'] != null && data['output'] is List) {
        final output = data['output'] as List;
        for (final item in output) {
          if (item is Map<String, dynamic>) {
            if (item['type'] == 'message' && item['content'] is List) {
              final contentList = item['content'] as List;
              final texts = <String>[];
              for (final c in contentList) {
                if (c is Map<String, dynamic> && c['text'] != null) {
                  texts.add(c['text'] as String);
                }
              }
              if (texts.isNotEmpty) return texts.join();
            }
            if (item['content'] != null && item['content'] is String) {
              return item['content'] as String;
            }
          }
        }
      }

      // ─── Anthropic Claude 格式 ───
      if (data['content'] != null && data['content'] is List) {
        final contentList = data['content'] as List;
        final texts = <String>[];
        for (final c in contentList) {
          if (c is Map<String, dynamic> &&
              c['type'] == 'text' &&
              c['text'] != null) {
            texts.add(c['text'] as String);
          }
        }
        if (texts.isNotEmpty) return texts.join();
      }

      // ─── OpenAI Chat Completions 格式 ───
      if (data['choices'] != null && (data['choices'] as List).isNotEmpty) {
        final choice = data['choices'][0];
        if (choice['message'] != null) {
          final msgContent = choice['message']['content'] as String?;
          if (msgContent != null && msgContent.trim().isNotEmpty) {
            return msgContent;
          }
          // 兼容不同提供商的 reasoning 字段命名
          final reasoning = (choice['message']['reasoning_content'] ??
              choice['message']['reasoning'] ??
              choice['message']['thinking']) as String?;
          if (reasoning != null && reasoning.trim().isNotEmpty) {
            return reasoning;
          }
          // choice 级别 reasoning
          final choiceReasoning = (choice['reasoning_content'] ??
              choice['reasoning'] ??
              choice['thinking']) as String?;
          if (choiceReasoning != null && choiceReasoning.trim().isNotEmpty) {
            return choiceReasoning;
          }
          return msgContent ?? '';
        } else if (choice['text'] != null) {
          return choice['text'] as String? ?? '';
        }
      }

      // ─── 国产 API 常见格式 ───
      if (data['result'] != null && data['result'] is String) {
        return data['result'] as String;
      }
      if (data['data'] != null && data['data'] is Map) {
        final d = data['data'] as Map;
        if (d['text'] != null) return d['text'] as String;
        if (d['content'] != null) return d['content'] as String;
      }

      // 通用 fallback
      if (data['text'] != null) return data['text'] as String;
      if (data['response'] != null) return data['response'] as String;
      if (data['content'] != null && data['content'] is String) {
        return data['content'] as String;
      }
      // reasoning 字段兜底
      if (data['reasoning_content'] != null &&
          data['reasoning_content'] is String) {
        return data['reasoning_content'] as String;
      }
      if (data['reasoning'] != null && data['reasoning'] is String) {
        return data['reasoning'] as String;
      }
      if (data['thinking'] != null && data['thinking'] is String) {
        return data['thinking'] as String;
      }
    }
    return data.toString();
  }

  String _cleanResponse(String content) {
    String cleaned = content;
    // 移除推理模型的思考标签
    cleaned = cleaned.replaceAll(
        RegExp(r'<think>[\s\S]*?<\think>', dotAll: true), '');
    // 移除状态标签
    cleaned = cleaned.replaceAll(
        RegExp(r'\[STATUS\].*?\[/STATUS\]', caseSensitive: false, dotAll: true),
        '');
    cleaned = cleaned.replaceAll(
        RegExp(r'\[\?\s*STATUS\s*\]', caseSensitive: false), '');
    // 移除表情标签
    cleaned = cleaned.replaceAll(
        RegExp(r'\[STICK\w*[^\]]*\]', caseSensitive: false), '');
    // 清理多余空白
    cleaned = cleaned.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return cleaned.trim();
  }

  /// 将AI回复拆分为多条短消息，模拟真人分条发微信
  List<String> splitIntoMessages(String response) {
    if (response.isEmpty) return ['嗯，让我想想。'];

    final List<String> messages = [];
    final paragraphs = response.split(RegExp(r'\n+'));

    for (String paragraph in paragraphs) {
      paragraph = paragraph.trim();
      if (paragraph.isEmpty) continue;

      // 短段落直接作为一条消息
      if (paragraph.length <= 20) {
        messages.add(paragraph);
        continue;
      }

      // 长段落按句号拆分
      final sentences = <String>[];
      final currentSentence = StringBuffer();

      for (int j = 0; j < paragraph.length; j++) {
        currentSentence.write(paragraph[j]);

        final isEndPunctuation =
            ['。', '！', '？', '!', '?', '~'].contains(paragraph[j]);
        final shouldSplit = isEndPunctuation && currentSentence.length >= 5;

        if (shouldSplit && j + 1 < paragraph.length) {
          final next = paragraph[j + 1];
          if (!['。', '！', '？', '！', '，', ',', '、'].contains(next)) {
            sentences.add(currentSentence.toString().trim());
            currentSentence.clear();
          }
        }
      }

      if (currentSentence.isNotEmpty) {
        sentences.add(currentSentence.toString().trim());
      }

      // 合并短句
      final grouped = <String>[];
      final group = StringBuffer();

      for (String sentence in sentences) {
        if (group.isEmpty) {
          group.write(sentence);
        } else if (group.length + sentence.length <= 30) {
          group.write(sentence);
        } else {
          grouped.add(group.toString());
          group.clear();
          group.write(sentence);
        }
      }

      if (group.isNotEmpty) {
        grouped.add(group.toString());
      }

      messages.addAll(grouped);
    }

    if (messages.isEmpty) {
      messages.add(response);
    }

    return messages;
  }
}
