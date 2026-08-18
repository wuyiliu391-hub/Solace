// AIService 历史过滤与联网搜索上下文：消息历史清洗、必应搜索注入。
// 本文件是 ai_service.dart 的 part，与其共同构成一个库。

part of '../ai_service.dart';

mixin AIServiceHistoryApi on AIServiceContextApi {
  String _extractBracketDirectives(String text) {
    final directives = <String>[];
    for (final match in AIService._actionBracketPattern.allMatches(text)) {
      final raw = match.group(0) ?? '';
      final inner = raw.replaceAll(RegExp(r'^[（(]|[）)]$'), '').trim();
      if (inner.isNotEmpty) directives.add(inner);
    }
    return directives.join('；');
  }

  bool _containsActionBracket(String text) =>
      AIService._actionBracketPattern.hasMatch(text);

  /// 将「（动作/旁白）」从对白中拆开，避免模型当台词念
  String _formatActionBracketUserMessage(String raw) {
    final text = raw.trim();
    if (text.isEmpty || !_containsActionBracket(text)) return text;

    final actions = <String>[];
    final dialogue = text
        .replaceAllMapped(AIService._actionBracketPattern, (m) {
          final inner =
              (m.group(0) ?? '').replaceAll(RegExp(r'^[（(]|[）)]$'), '').trim();
          if (inner.isNotEmpty) actions.add(inner);
          return ' ';
        })
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (actions.isEmpty) return text;

    final buf = StringBuffer();
    buf.writeln('[场景/动作·非对白]');
    for (final a in actions) {
      buf.writeln('- $a');
    }
    if (dialogue.isNotEmpty) {
      buf.writeln();
      buf.writeln('[用户说出口的话]');
      buf.write(dialogue);
    } else {
      buf.writeln();
      buf.write('[用户本轮没有额外台词，请只根据上述场景/动作自然回应]');
    }
    return buf.toString().trim();
  }

  String _buildActionBracketSystemRule() {
    return '''【本轮括号语义·强制】
用户消息中标记为「场景/动作·非对白」或原文「（…）/ (...)」内的内容，是现场动作/神态/旁白，不是对你说的话。
1. 只把「用户说出口的话」当作对白来接。
2. 场景/动作是已发生事实，用角色身份自然反应，禁止复读、引用、元评论括号内容。
3. 不要把旁白念成对话。''';
  }

  /// 提取"系统提示"指令内容
  /// 匹配"系统提示"或"系统提示："或"系统提示,"后面的内容
  String? _extractSystemDirective(String text) {
    final patterns = [
      RegExp(r'系统提示[：:,，]\s*(.+)', caseSensitive: false),
      RegExp(r'系统提示\s+(.+)', caseSensitive: false),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match != null) {
        final directive = match.group(1)?.trim();
        if (directive != null && directive.isNotEmpty) {
          return directive;
        }
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
      cleaned = cleaned.replaceAll(pattern, '');
    }
    return cleaned.trim();
  }

  /// 委托给 PromptBuilder（已提取到 prompt/prompt_builder.dart）
  Future<String> _buildSystemPrompt({
    required AICharacter character,
    required String userId,
    required String currentTopic,
    required List<Memory> memories,
    required int intimacyLevel,
    String? userStatus,
    SentimentResult? sentiment,
    String? imageDescription,
    bool isBlockedByAI = false,
    String? blockReason,
    int messageCount = 0,
    bool isFirstMessage = false,
    bool isSideStory = false,
    bool forceConcise = false,
  }) async {
    return _promptBuilder.buildSystemPrompt(
      character: character,
      userId: userId,
      currentTopic: currentTopic,
      memories: memories,
      intimacyLevel: intimacyLevel,
      userStatus: userStatus,
      sentiment: sentiment,
      imageDescription: imageDescription,
      isBlockedByAI: isBlockedByAI,
      blockReason: blockReason,
      messageCount: messageCount,
      isFirstMessage: isFirstMessage,
      isSideStory: isSideStory,
      forceConcise: forceConcise,
    );
  }

  Future<void> generateReflection({
    required AICharacter character,
    required String userId,
    required List<ChatMessage> recentMessages,
  }) async {
    if (recentMessages.length < 3) return;

    final config = await _storage.getActiveAIConfig();
    if (config == null) return;

    final conversation = recentMessages
        .map((m) => '${m.isFromAI ? character.name : 'User'}: ${m.content}')
        .join('\n');

    final prompt = '''
作为${character.name}，回顾刚才的对话：

$conversation

请用第一人称进行简短的自我反思（2-3句话），思考：
1. 刚才的回应是否合适
2. 是否有更好的表达方式
3. 用户的情绪状态如何

只输出反思内容，不要输出其他内容。
''';

    try {
      final baseUrl = config.baseUrl.endsWith('/')
          ? config.baseUrl.substring(0, config.baseUrl.length - 1)
          : config.baseUrl;

      final url = Uri.parse('$baseUrl/chat/completions');

      for (int attempt = 1; attempt <= AppDurations.maxRetries; attempt++) {
        try {
          final response = await http.post(
            url,
            headers: {
              'Content-Type': 'application/json; charset=utf-8',
              'Accept-Charset': 'utf-8',
              'Authorization': 'Bearer ${config.apiKey}',
            },
            body: jsonEncode({
              'model': config.modelName,
              'messages': [
                {'role': 'user', 'content': prompt}
              ],
              'temperature': ApiDefaults.reflectiveTemp,
              'max_tokens': ApiDefaults.reflectiveMaxTokens,
            }),
          );

          if (response.statusCode == 200) {
            final body = await _decodeBody(
                response.headers['content-type'], response.bodyBytes);
            final data = jsonDecode(body);
            final reflection = _extractResponseContent(data);

            await _storage.saveMemory(Memory(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              characterId: character.id,
              userId: userId,
              type: MemoryType.reflection,
              content: reflection,
              importance: MemoryImportance.important,
              createdAt: DateTime.now(),
            ));
            return;
          }

          if ((response.statusCode == 429 || response.statusCode == 503) &&
              attempt < AppDurations.maxRetries) {
            await Future.delayed(Duration(seconds: attempt * 5));
            continue;
          }
        } catch (e) {
          debugPrint(
              '===== AIService.generateReflection: retry attempt $attempt failed: $e =====');
          if (attempt < AppDurations.maxRetries) {
            await Future.delayed(Duration(seconds: attempt * 3));
            continue;
          }
        }
      }
    } catch (e) {
      debugPrint(
          '===== AIService.generateReflection: FAILED after all retries: $e =====');
    }
  }

  Future<String> _callAPI({
    required String baseUrl,
    required String apiKey,
    required String model,
    required List<Map<String, dynamic>> messages,
    int? maxTokens = 2048,
    AIConfig? config,
  }) async {
    String cleanUrl = baseUrl.trim();
    while (cleanUrl.endsWith('/')) {
      cleanUrl = cleanUrl.substring(0, cleanUrl.length - 1);
    }
    final url = cleanUrl.endsWith('/chat/completions')
        ? Uri.parse(cleanUrl)
        : Uri.parse('$cleanUrl/chat/completions');

    final payload = <String, dynamic>{
      'model': model,
      'messages': messages,
    };
    if (maxTokens != null) {
      payload['max_tokens'] = maxTokens;
    }
    final requestBody = jsonEncode(payload);
    final response = await _httpClient
        .post(
          url,
          headers: {
            'Content-Type': 'application/json; charset=utf-8',
            'Accept-Charset': 'utf-8',
            'Authorization': 'Bearer $apiKey',
          },
          body: requestBody,
        )
        .timeout(const Duration(seconds: 60));
    unawaited(UsageMeterService.instance.trackHttpResponse(
      url: url,
      requestBody: requestBody,
      response: response,
      endpointHint: 'openai_chat',
    ));

    if (response.statusCode == 200) {
      final body = await _decodeBody(
          response.headers['content-type'], response.bodyBytes);
      final data = jsonDecode(body);
      return _extractResponseContent(data);
    }

    final errorBody =
        await _decodeBody(response.headers['content-type'], response.bodyBytes);
    throw Exception('API request failed: ${response.statusCode}: $errorBody');
  }

  /// 备用模型兜底：当主模型返回空白时，尝试其他模型非流式生成
  /// Sends a caller-provided prompt without applying a character chat template.
  Future<String> sendPromptMessage({
    required List<Map<String, dynamic>> messages,
    int? overrideMaxTokens,
  }) async {
    final config = await _storage.getActiveAIConfig();
    if (config == null) throw Exception('No active configuration found');
    return _callAPI(
      baseUrl: config.baseUrl,
      apiKey: config.apiKey,
      model: config.modelName,
      messages: messages,
      maxTokens: overrideMaxTokens,
      config: config,
    );
  }

  Future<String?> fallbackGenerate({
    required List<Map<String, dynamic>> messages,
    required String excludeConfigId,
    int maxTokens = 1024,
  }) async {
    // 收集候选模型：用户手动配置保存的其他模型
    final allConfigs = await _storage.getAllAIConfigs();
    final candidates = <AIConfig>[
      ...allConfigs.where((c) => c.id != excludeConfigId),
    ];
    // 去重（按 baseUrl+modelName）
    final seen = <String>{};
    final unique = <AIConfig>[];
    for (final c in candidates) {
      final key = '${c.baseUrl}|${c.modelName}';
      if (seen.add(key)) unique.add(c);
    }

    for (final config in unique) {
      try {
        debugPrint(
            '===== fallbackGenerate: 尝试 ${config.providerName}/${config.modelName} =====');
        final response = await _callAPI(
          baseUrl: config.baseUrl,
          apiKey: config.apiKey,
          model: config.modelName,
          messages: messages,
          maxTokens: maxTokens,
          config: config,
        );
        final cleaned = _cleanResponse(response);
        if (cleaned.trim().isNotEmpty && cleaned.trim() != '嗯，让我想想该怎么回答你。') {
          debugPrint('===== fallbackGenerate: 成功 =====');
          return cleaned;
        }
      } catch (e) {
        debugPrint(
            '===== fallbackGenerate: ${config.providerName} 失败: $e =====');
        continue;
      }
    }
    debugPrint('===== fallbackGenerate: 所有备用模型均失败 =====');
    return null;
  }

  /// 通用流式API调用 — 群聊/回忆等共享方法使用
  Stream<AIStreamChunk> _streamCallAPI({
    required String baseUrl,
    required String apiKey,
    required String model,
    required List<Map<String, dynamic>> messages,
    int? maxTokens = 2048,
    AIConfig? config,
  }) async* {
    String cleanUrl = baseUrl.trim();
    while (cleanUrl.endsWith('/')) {
      cleanUrl = cleanUrl.substring(0, cleanUrl.length - 1);
    }
    final url = cleanUrl.endsWith('/chat/completions')
        ? Uri.parse(cleanUrl)
        : Uri.parse('$cleanUrl/chat/completions');

    final client = http.Client();
    try {
      final request = http.Request('POST', url);
      request.headers['Content-Type'] = 'application/json';
      request.headers['Authorization'] = 'Bearer $apiKey';
      final payload = <String, dynamic>{
        'model': model,
        'messages': messages,
        'stream': true,
      };
      if (maxTokens != null) {
        payload['max_tokens'] = maxTokens;
      }
      final requestBody = jsonEncode(payload);
      request.body = requestBody;

      final streamedResponse =
          await client.send(request).timeout(const Duration(seconds: 60));
      final contentType = streamedResponse.headers['content-type'];

      if (streamedResponse.statusCode != 200) {
        final errorBytes = await streamedResponse.stream.toBytes();
        final body = await _decodeBody(contentType, errorBytes);
        throw Exception('API错误 (${streamedResponse.statusCode}): $body');
      }

      String accumulatedReasoning = '';
      String accumulatedContent = '';
      Map<String, dynamic>? capturedUsage;
      final rawBytes = await streamedResponse.stream.toBytes();
      final decoded = await _decodeBody(contentType, rawBytes);

      for (final line in decoded.replaceAll('\r\n', '\n').split('\n')) {
        final trimmed = line.trim();
        if (!trimmed.startsWith('data:')) continue;
        final data = trimmed.substring(5).trimLeft();
        if (data == '[DONE]') return;

        try {
          final json = jsonDecode(data) as Map<String, dynamic>;
          final chunkUsage = json['usage'] as Map<String, dynamic>?;
          if (chunkUsage != null) capturedUsage = chunkUsage;
          final choices = json['choices'] as List?;
          if (choices != null && choices.isNotEmpty) {
            final delta = choices[0]['delta'] as Map<String, dynamic>?;
            if (delta != null) {
              final reasoning =
                  delta['reasoning_content'] ?? delta['reasoning'];
              final content = delta['content'] ?? delta['text'];
              if (reasoning != null) {
                accumulatedReasoning +=
                    ResponseDecoder.repairText(reasoning as String);
                yield AIStreamChunk(
                    reasoning: accumulatedReasoning,
                    content: accumulatedContent);
              }
              if (content != null) {
                accumulatedContent +=
                    ResponseDecoder.repairText(content as String);
                yield AIStreamChunk(
                    reasoning: accumulatedReasoning,
                    content: accumulatedContent);
              }
            }
          }
        } catch (e) {
          debugPrint('Error: $e');
        }
      }
      if (accumulatedContent.isNotEmpty || accumulatedReasoning.isNotEmpty) {
        unawaited(UsageMeterService.instance.trackStreamResponse(
          url: url,
          requestBody: requestBody,
          statusCode: streamedResponse.statusCode,
          responseBodyBytes: rawBytes,
          endpointHint: 'openai_chat',
          extractedUsage: capturedUsage,
          outputChars: accumulatedContent.length + accumulatedReasoning.length,
        ));
      }
    } finally {
      client.close();
    }
  }

  Future<String> generateRollingSummary({
    required List<ChatMessage> newMessages,
    required AICharacter character,
    String? existingSummary,
  }) async {
    final messageTexts = newMessages.map((m) {
      if (m.isFromAI) return '${character.name}：${m.content}';
      return '用户：${m.content}';
    }).join('\n');

    final prompt = existingSummary != null && existingSummary.isNotEmpty
        ? '''你正在为一段持续的对话维护一份永久记忆档案。这是之前的档案：

$existingSummary

以下是最新对话：
$messageTexts

请更新这份档案。要求：
1. 保留之前档案中的所有信息，不要丢失任何细节
2. 加入新对话中的所有重要信息
3. 用自然的中文叙述，像在写一个人的日记
4. 必须包含：用户提到的所有事实（工作、生活、喜好、习惯）、情感状态变化、重要事件、未完成的话题、承诺或约定、关系发展
5. 不要遗漏，不要概括过度，宁可写长也不要漏掉细节
6. 最终输出完整的更新后档案，不要加任何前缀说明'''
        : '''你正在为一段对话创建永久记忆档案。

对话内容：
$messageTexts

请创建一份全面的记忆档案。要求：
1. 用自然的中文叙述，像在写一个人的日记
2. 必须包含：用户提到的所有事实（工作、生活、喜好、习惯）、情感状态、重要事件、对话中的关键转折、未完成的话题
3. 不要遗漏任何重要细节，宁可写长也不要漏掉
4. 直接输出档案内容，不要加任何前缀说明''';

    final config = await _storage.getActiveAIConfig();
    if (config == null) return existingSummary ?? '';

    final messages = <Map<String, String>>[
      {
        'role': 'system',
        'content':
            '${_storage.buildGlobalModePrompt(scope: '记忆档案')}\n你是一个记忆档案管理器。你的任务是维护一份全面、准确、不遗漏的对话记忆档案。用自然的中文书写，保留所有细节。'
      },
      {'role': 'user', 'content': prompt},
    ];

    try {
      final response = await _callAPI(
        baseUrl: config.baseUrl,
        apiKey: config.apiKey,
        model: config.modelName,
        messages: messages,
        maxTokens: 2000,
        config: config,
      );
      final trimmed = response.trim();
      if (trimmed.isEmpty) return existingSummary ?? '';
      return trimmed;
    } catch (e) {
      debugPrint('generateRollingSummary error: $e');
      return existingSummary ?? '';
    }
  }

  Future<String?> generateGroupRollingSummary({
    String? existingSummary,
    required List<ChatMessage> newMessages,
  }) async {
    final messageTexts = newMessages
        .map((m) =>
            '${m.isUser ? '用户' : (m.senderName.isEmpty ? '群成员' : m.senderName)}：${m.content}')
        .join('\n');
    final prompt = existingSummary != null && existingSummary.isNotEmpty
        ? '''维护一份群聊的长期公共记忆档案。
旧档案：
$existingSummary

新增消息：
$messageTexts

请输出更新后的完整档案。保留重要事实、人物关系、约定、冲突、计划和未完成话题，明确区分用户和每个角色。不要编造，不要只总结新增消息。'''
        : '''为以下群聊创建长期公共记忆档案：
$messageTexts

只保留重要事实、人物关系、约定、冲突、计划和未完成话题，明确区分用户和每个角色。不要编造，不要写寒暄。''';
    final config = await _storage.getActiveAIConfig();
    if (config == null) return null;
    try {
      final response = await _callAPI(
        baseUrl: config.baseUrl,
        apiKey: config.apiKey,
        model: config.modelName,
        messages: [
          {
            'role': 'system',
            'content': '你是群聊长期记忆档案管理器，只输出准确的中文公共记忆档案。',
          },
          {'role': 'user', 'content': prompt},
        ],
        maxTokens: 2000,
        config: config,
      );
      final trimmed = response.trim();
      return trimmed.isEmpty ? null : trimmed;
    } catch (e) {
      debugPrint('generateGroupRollingSummary error: $e');
      return null;
    }
  }

  Future<List<GroupPublicEventExtraction>> extractGroupPublicEvents({
    required String groupName,
    required List<ChatMessage> messages,
    String? existingSummary,
  }) async {
    final config = await _storage.getActiveAIConfig();
    if (config == null || messages.isEmpty) return const [];
    final transcript = messages
        .map((m) =>
            '[${m.id}] ${m.isUser ? '用户' : (m.senderName.isEmpty ? '群成员' : m.senderName)}：${m.content}')
        .join('\n');
    final prompt = '''群名：$groupName
已有总结：${existingSummary ?? ''}
消息：
$transcript

只输出 JSON 数组，提取可供群外单聊回忆的公开事件，不要记录寒暄。每项格式：{"content":"事件摘要","keywords":["关键词"],"sourceMessageIds":["消息id"],"speakerNames":["发言人"],"importance":"normal 或 important","pinned":false}''';
    try {
      final raw = await _callAPI(
          baseUrl: config.baseUrl,
          apiKey: config.apiKey,
          model: config.modelName,
          messages: [
            {'role': 'system', 'content': '你是严格的群聊事件抽取器，只输出合法 JSON。'},
            {'role': 'user', 'content': prompt}
          ],
          maxTokens: 1200,
          config: config);
      final trimmed = raw.trim();
      final start = trimmed.indexOf('[');
      if (start < 0) return const [];
      var depth = 0;
      var end = -1;
      var inString = false;
      var escaped = false;
      for (var i = start; i < trimmed.length; i++) {
        final char = trimmed[i];
        if (inString) {
          if (escaped) {
            escaped = false;
          } else if (char == '\\') {
            escaped = true;
          } else if (char == '"') {
            inString = false;
          }
          continue;
        }
        if (char == '"') inString = true;
        if (char == '[') depth++;
        if (char == ']') {
          depth--;
          if (depth == 0) {
            end = i + 1;
            break;
          }
        }
      }
      if (end < 0) return const [];
      final decoded = jsonDecode(trimmed.substring(start, end));
      if (decoded is! List) return const [];
      final messageIds = messages.map((m) => m.id).toSet();
      final speakerNames = messages
          .map((m) =>
              m.isUser ? '用户' : (m.senderName.isEmpty ? '群成员' : m.senderName))
          .toSet();
      final result = <GroupPublicEventExtraction>[];
      for (final item in decoded) {
        try {
          if (item is! Map) continue;
          final map = Map<String, dynamic>.from(item);
          final content = map['content']?.toString().trim() ?? '';
          if (content.isEmpty) continue;
          final validSourceMessageIds = AIService._stringList(map['sourceMessageIds'])
              .where(messageIds.contains)
              .toList();
          final validSpeakerNames = AIService._stringList(map['speakerNames'])
              .where(speakerNames.contains)
              .toList();
          // Every event needs a validated source so single-message
          // deletion can remove it through the same cleanup path.
          if (validSourceMessageIds.isEmpty) {
            continue;
          }
          result.add(GroupPublicEventExtraction(
            content: content,
            keywords: AIService._stringList(map['keywords']),
            sourceMessageIds: validSourceMessageIds,
            speakerNames: validSpeakerNames,
            importance:
                map['importance']?.toString().toLowerCase() == 'important'
                    ? GroupEventImportance.important
                    : GroupEventImportance.normal,
            pinned: map['pinned'] == true || map['pinned'] == 1,
          ));
        } catch (e) {
          debugPrint('extractGroupPublicEvents item error: $e');
        }
      }
      return result;
    } catch (e) {
      debugPrint('extractGroupPublicEvents error: $e');
      return const [];
    }
  }
}
