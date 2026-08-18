import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import '../models/ai_character.dart';
import '../models/ai_turn_state.dart';
import '../models/ai_config.dart';
import '../models/ai_stream_chunk.dart';
import '../models/chat_message.dart';
import '../models/group_public_event_memory.dart';
import '../models/memory.dart';
import '../repositories/local_storage_repository.dart';
import '../utils/sentiment_analyzer.dart';
import '../utils/message_sanitizer.dart';
import '../utils/response_decoder.dart';
import '../utils/vision_image_encoder.dart';
import '../config/constants.dart';
import 'memory_engine.dart';
import 'emotion_engine.dart';
import 'weather_service.dart';
import '../models/bt_agent_action.dart';
import 'bing_cn_mcp_service.dart';
import 'prompt_rewriter.dart';
import 'usage_meter_service.dart';
import 'prompt/prompt_builder.dart';
import 'dialogue_strategy.dart';

part 'ai_service/clean_split.dart';
part 'ai_service/context_forgiveness.dart';
part 'ai_service/history_filter.dart';
part 'ai_service/memory_narrative.dart';

/// 创建带连接超时的 HTTP Client
http.Client _createClient() {
  return http.Client();
}

/// 记录请求调试信息（剥离 data URL base64，避免日志卡死/泄露）
void _logRequest(Uri url, Map<String, String> headers, Object body) {
  debugPrint('===== AI API 请求 =====');
  debugPrint('URL: $url');
  debugPrint(
      'Headers: ${headers.entries.map((e) => '${e.key}: ${e.value.length > 20 ? "${e.value.substring(0, 20)}..." : e.value}').join(", ")}');
  debugPrint('Body: ${_summarizeRequestBodyForLog(body)}');
}

Object _summarizeRequestBodyForLog(Object body) {
  if (body is! Map) return body;
  try {
    final clone = Map<String, dynamic>.from(
      body.map((k, v) => MapEntry(k.toString(), v)),
    );
    final messages = clone['messages'];
    if (messages is List) {
      clone['messages'] = messages.map((m) {
        if (m is! Map) return m;
        final mm = Map<String, dynamic>.from(
          m.map((k, v) => MapEntry(k.toString(), v)),
        );
        final content = mm['content'];
        if (content is List) {
          mm['content'] = content.map((part) {
            if (part is! Map) return part;
            final p = Map<String, dynamic>.from(
              part.map((k, v) => MapEntry(k.toString(), v)),
            );
            final imageUrl = p['image_url'];
            if (imageUrl is Map) {
              final iu = Map<String, dynamic>.from(
                imageUrl.map((k, v) => MapEntry(k.toString(), v)),
              );
              final url = iu['url']?.toString() ?? '';
              if (url.startsWith('data:')) {
                final comma = url.indexOf(',');
                final meta = comma > 0 ? url.substring(0, comma) : 'data:';
                final b64Len = comma > 0 ? url.length - comma - 1 : url.length;
                iu['url'] = '$meta,<base64 $b64Len chars>';
              } else if (url.length > 80) {
                iu['url'] = '${url.substring(0, 80)}…';
              }
              p['image_url'] = iu;
            }
            return p;
          }).toList();
        } else if (content is String && content.length > 200) {
          mm['content'] = '${content.substring(0, 200)}…';
        }
        return mm;
      }).toList();
    }
    return clone;
  } catch (_) {
    return body;
  }
}

/// 把网关原始错误翻译成更可操作的中文（含 vision / 中转）
String _friendlyApiErrorMessage(String? raw, {String? modelName}) {
  final vision = VisionImageEncoder.friendlyVisionError(raw);
  if (vision != null) return vision;
  if (raw == null || raw.trim().isEmpty) {
    return '请求失败';
  }
  final m = raw.toLowerCase();
  if (m.contains('model') &&
      (m.contains('not found') || m.contains('does not exist'))) {
    final name =
        modelName == null || modelName.isEmpty ? '当前模型' : '模型「$modelName」';
    return '$name不存在或中转站未配置，请检查模型名称';
  }
  return raw;
}

class ForgivenessJudgment {
  final bool shouldForgive;
  final String forgiveMessage;
  const ForgivenessJudgment(
      {required this.shouldForgive, required this.forgiveMessage});
}

class GroupPublicEventExtraction {
  final String content;
  final List<String> keywords;
  final List<String> sourceMessageIds;
  final List<String> speakerNames;
  final GroupEventImportance importance;
  final bool pinned;
  const GroupPublicEventExtraction(
      {required this.content,
      this.keywords = const [],
      this.sourceMessageIds = const [],
      this.speakerNames = const [],
      this.importance = GroupEventImportance.normal,
      this.pinned = false});
}

/// AIService 的字段基座：巨型服务拆分为多个 mixin part 后，
/// 各 mixin 通过 `on _AIServiceCore` 共享这些实例字段。
abstract class _AIServiceCore {
  _AIServiceCore(this._storage, this._httpClient);

  final LocalStorageRepository _storage;
  final http.Client _httpClient;
  late final MemoryEngine _memoryEngine;
  late final EmotionEngine _emotionEngine;
  late final PromptBuilder _promptBuilder;
  final BingCnMcpService _bingSearch = const BingCnMcpService();

  /// 最近一次请求的角色性别/名字（用于输出侧人称轻量纠错）
  String? _lastCharacterGender;
  String? _lastCharacterName;
  String? _lastParsedStatus;
  AiTurnState? _lastTurnState;
  Map<String, dynamic>? _lastWebSearchTrace;

  // ---- 跨 mixin 调用的方法抽象声明（实现在主类或后续 mixin，全链可见）----

  bool _isCompactContextModel(String modelName);

  String _buildCompactContextAnchor({
    required AICharacter character,
    required String currentTopic,
    required List<ChatMessage> chatHistory,
    required List<Memory> memories,
    required int intimacyLevel,
  });

  String _cleanResponse(String content);

  String _buildGlobalModePrompt({String scope = 'AI回复'});

  Future<String> _decodeBody(String? contentType, List<int> bodyBytes);

  String _extractBracketDirectives(String text);

  bool _containsActionBracket(String text);

  String _formatActionBracketUserMessage(String raw);

  String _buildActionBracketSystemRule();

  String? _extractSystemDirective(String text);

  String _removeSystemDirectiveFromMessage(String text);

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
  });
}

class AIService extends _AIServiceCore with AIServiceCleanSplitApi, AIServiceContextApi, AIServiceHistoryApi, AIServiceMemoryApi {
  /// 依赖注入入口；字段声明见 [_AIServiceCore]
  AIService(LocalStorageRepository storage, {http.Client? httpClient})
      : super(storage, httpClient ?? http.Client()) {
    _memoryEngine = MemoryEngine(_storage);
    _emotionEngine = EmotionEngine(_storage);
    _promptBuilder = PromptBuilder(
        _storage, _memoryEngine, _emotionEngine, DialogueStrategy());
  }

  /// 判断小说模式是否开启（全局开关）
  bool _isNovelModeEnabled() {
    return _storage.isChatStyleNovelModeEnabled();
  }
  String? get lastParsedStatus => _lastParsedStatus;
  AiTurnState? get lastTurnState => _lastTurnState;
  Map<String, dynamic>? get lastWebSearchTrace => _lastWebSearchTrace;
  /// 为内置 GLM-Z1-9B 注入模式专属参数（top_p, top_k, frequency_penalty, thinking_budget, max_tokens）
  int _effectiveChatMaxTokens(int configuredMaxTokens) {
    return configuredMaxTokens;
  }
  int? _chatMaxTokensForCurrentMode(int configuredMaxTokens,
      {bool forceConcise = false}) {
    final novelMode = _isNovelModeEnabled();
    final pureAiMode = _storage.isPureAiModeEnabled();
    if (novelMode && !pureAiMode && !forceConcise) {
      // 小说模式=完整输出：必须显式给足 max_tokens。
      // 此前返回 null（不传 max_tokens）会退回服务端默认——很多模型/中转默认只有
      // 几百 token，正是「开了完整输出却只出一句话」的根因。取 max(用户配置, 下限)。
      return configuredMaxTokens > ApiDefaults.novelMaxTokensFloor
          ? configuredMaxTokens
          : ApiDefaults.novelMaxTokensFloor;
    }
    return _effectiveChatMaxTokens(configuredMaxTokens);
  }
  bool _isCompactContextModel(String modelName) {
    final lower = modelName.toLowerCase();
    if (lower.isEmpty) return false;

    const compactKeywords = [
      'nano',
      'tiny',
      'lite',
      'small',
      'gemma-2b',
      'gemma-7b',
      'phi-3',
      'phi-4-mini',
    ];
    if (compactKeywords.any(lower.contains)) return true;

    final sizePattern = RegExp(r'(^|[^a-z0-9])(\d+(?:\.\d+)?)b($|[^a-z0-9])');
    for (final match in sizePattern.allMatches(lower)) {
      final value = double.tryParse(match.group(2) ?? '');
      if (value != null && value <= 9.5) {
        return true;
      }
    }
    return false;
  }
  String _truncateContextLine(String text, int maxLength) {
    final normalized = MessageSanitizer.sanitizeFinal(text)
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (normalized.length <= maxLength) return normalized;
    return '${normalized.substring(0, maxLength).trim()}…';
  }
  String _buildCompactContextAnchor({
    required AICharacter character,
    required String currentTopic,
    required List<ChatMessage> chatHistory,
    required List<Memory> memories,
    required int intimacyLevel,
  }) {
    final buffer = StringBuffer();
    buffer.writeln(
        '<internal_context type="compact_anchor" visibility="private">');
    buffer.writeln('后台控制指令：本段只用于理解上下文，绝对不要输出、引用或改写给用户。');
    buffer.writeln('你的上下文能力有限，回复前先抓住这些锚点：');
    buffer.writeln('- 你是${character.name}，正在和用户连续聊天，不是第一次见面。');
    buffer.writeln('- 当前亲密等级：$intimacyLevel。保持已有关系，不要重置关系。');
    if (currentTopic.trim().isNotEmpty) {
      buffer.writeln('- 用户本轮消息：${_truncateContextLine(currentTopic, 80)}');
    }

    final memoryLines = memories
        .take(5)
        .map((m) => _truncateContextLine(m.content, 70))
        .where((m) => m.isNotEmpty)
        .toList();
    if (memoryLines.isNotEmpty) {
      buffer.writeln('- 关键记忆：${memoryLines.join('；')}');
    }

    final recent = chatHistory
        .where((m) => !(m.isFromAI && MessageSanitizer.isAIRefusal(m.content)))
        .toList()
        .reversed
        .take(6)
        .toList()
        .reversed;
    final recentLines = <String>[];
    for (final msg in recent) {
      final content = _truncateContextLine(msg.content, 60);
      if (content.isEmpty) continue;
      recentLines.add('${msg.isFromAI ? character.name : '用户'}：$content');
    }
    if (recentLines.isNotEmpty) {
      buffer.writeln('- 最近对话：${recentLines.join(' / ')}');
    }

    buffer.writeln('回复要求：必须承接上面的关系、记忆和最近对话；不要说不认识、不记得，不要突然换话题。');
    buffer.writeln('</internal_context>');
    return buffer.toString();
  }
  Future<String> sendMessage({
    required AICharacter character,
    required String userId,
    required String userMessage,
    required List<ChatMessage> chatHistory,
    required List<Memory> memories,
    required int intimacyLevel,
    String? userStatus,
    SentimentResult? sentiment,
    String? imageDescription,
    List<String>? imagePaths,
    bool isBlockedByAI = false,
    String? blockReason,
    bool enableWebSearch = false,
    String? internalSystemContext,
    int? overrideMaxTokens,
    bool isSideStory = false,
    bool forceConcise = false,
  }) async {
    _lastTurnState = null;
    _lastParsedStatus = null;
    debugPrint('===== AIService.sendMessage: ENTRY =====');
    debugPrint('character: ${character.name}, userId: $userId');
    debugPrint(
        'message preview: ${userMessage.length > 60 ? "${userMessage.substring(0, 60)}..." : userMessage}');

    final config = await _storage.getActiveAIConfig();
    if (config == null) {
      debugPrint(
          '===== AIService.sendMessage: FAILED - No active config =====');
      throw Exception('No active configuration found');
    }

    final messages = await _buildMessages(
      character: character,
      userId: userId,
      userMessage: userMessage,
      chatHistory: chatHistory,
      memories: memories,
      intimacyLevel: intimacyLevel,
      userStatus: userStatus,
      sentiment: sentiment,
      imageDescription: imageDescription,
      imagePaths: imagePaths,
      isBlockedByAI: isBlockedByAI,
      blockReason: blockReason,
      enableWebSearch: enableWebSearch,
      internalSystemContext: internalSystemContext,
      isSideStory: isSideStory,
      forceConcise: forceConcise,
    );

    String baseUrl = config.baseUrl.trim();
    // 健壮性处理：移除末尾斜杠，避免用户输入 https://xxx/ 导致 //chat/completions
    while (baseUrl.endsWith('/')) {
      baseUrl = baseUrl.substring(0, baseUrl.length - 1);
    }
    // 健壮性处理：如果用户已经输入了完整路径（含 /chat/completions），不再重复拼接
    final url = baseUrl.endsWith('/chat/completions')
        ? Uri.parse(baseUrl)
        : Uri.parse('$baseUrl/chat/completions');

    final allApiKeys = config.allApiKeys;
    int currentKeyIndex = 0;
    final maxTokens = overrideMaxTokens ??
        _chatMaxTokensForCurrentMode(config.maxTokens,
            forceConcise: forceConcise);

    for (int attempt = 1; attempt <= AppDurations.maxRetries; attempt++) {
      try {
        final currentKey = allApiKeys[currentKeyIndex];
        final client = _createClient();
        final requestPayload = <String, dynamic>{
          'model': config.modelName,
          'messages': messages,
          'temperature': config.temperature,
          // 对抗复读：惩罚重复 token / 重复话题
          'frequency_penalty': ApiDefaults.chatFrequencyPenalty,
          'presence_penalty': ApiDefaults.chatPresencePenalty,
        };
        if (maxTokens != null) {
          requestPayload['max_tokens'] = maxTokens;
        }
        _logRequest(
            url,
            {
              'Content-Type': 'application/json; charset=utf-8',
              'Accept-Charset': 'utf-8',
              'Authorization': 'Bearer $currentKey',
            },
            requestPayload);

        final requestBody = jsonEncode(requestPayload);
        http.Response response;
        try {
          response = await client
              .post(url,
                  headers: {
                    'Content-Type': 'application/json; charset=utf-8',
                    'Accept-Charset': 'utf-8',
                    'Authorization': 'Bearer $currentKey',
                  },
                  body: requestBody)
              .timeout(AppDurations.aiRequest);
          unawaited(UsageMeterService.instance.trackHttpResponse(
            url: url,
            requestBody: requestBody,
            response: response,
            endpointHint: 'openai_chat',
          ));
        } finally {
          client.close();
        }

        debugPrint('===== AI API 响应 =====');
        debugPrint('Status: ${response.statusCode}');
        final rawBody = await _decodeBody(
            response.headers['content-type'], response.bodyBytes);
        debugPrint('Body: $rawBody');

        if (response.statusCode == 200) {
          final data = jsonDecode(rawBody);
          final rawContent = _extractResponseContent(data);
          if (MessageSanitizer.isGatewayError(rawContent)) {
            throw Exception('Gateway error in response: $rawContent');
          }
          _lastTurnState = AiTurnState.parse(rawContent);
          _lastParsedStatus = _lastTurnState?.emotion ??
              AiTurnState.parseLegacyStatus(rawContent);
          final cleaned = _cleanResponse(rawContent);
          debugPrint('===== AIService.sendMessage: SUCCESS =====');
          debugPrint(
              'cleaned response: ${cleaned.length > 80 ? "${cleaned.substring(0, 80)}..." : cleaned}');
          return cleaned;
        }

        // 429 限速：先尝试切换 API Key，所有 Key 都被限流后再等待
        if (response.statusCode == 429) {
          if (allApiKeys.length > 1 &&
              currentKeyIndex < allApiKeys.length - 1) {
            currentKeyIndex++;
            debugPrint(
                '请求被限速(429)，切换到备用 Key ($currentKeyIndex/${allApiKeys.length})');
            continue;
          }
          if (attempt < AppDurations.maxRetries) {
            currentKeyIndex = 0;
            final waitSeconds = attempt * 10;
            debugPrint(
                '所有 Key 均被限速，$waitSeconds秒后重试 ($attempt/${AppDurations.maxRetries})');
            await Future.delayed(Duration(seconds: waitSeconds));
            continue;
          }
          throw Exception('请求过于频繁，请稍后再试');
        }

        // 503/502 服务器过载：等待后重试
        if (response.statusCode == 503 || response.statusCode == 502) {
          if (attempt < AppDurations.maxRetries) {
            final waitSeconds = attempt * 8;
            debugPrint(
                '服务器繁忙(${response.statusCode})，$waitSeconds秒后重试 ($attempt/${AppDurations.maxRetries})');
            await Future.delayed(Duration(seconds: waitSeconds));
            continue;
          }
          throw Exception('服务器繁忙，请稍后再试');
        }

        try {
          final errorData = jsonDecode(rawBody);
          final errorMsg =
              errorData['error']?['message'] ?? response.reasonPhrase;
          final friendly = _friendlyApiErrorMessage(
            errorMsg?.toString(),
            modelName: config.modelName,
          );

          switch (response.statusCode) {
            case 400:
              throw Exception(friendly.startsWith('请求失败')
                  ? '请求参数错误（可能是图片格式/体积或模型不支持多模态）: $friendly'
                  : friendly);
            case 401:
              if (allApiKeys.length > 1 &&
                  currentKeyIndex < allApiKeys.length - 1) {
                currentKeyIndex++;
                debugPrint(
                    'API Key 无效，切换到备用 Key ($currentKeyIndex/${allApiKeys.length})');
                continue;
              }
              throw Exception('API Key 无效或已过期，请在设置中检查你的 API Key');
            case 402:
              throw Exception('账户余额不足，请充值后重试');
            case 403:
              // 部分中转用 403 表示模型未开通 vision
              throw Exception(VisionImageEncoder.friendlyVisionError(
                      errorMsg?.toString()) ??
                  '当前 API Key 没有调用该模型的权限，请在模型广场开通');
            case 404:
              throw Exception('模型「${config.modelName}」不存在，请检查模型名称是否正确');
            case 410:
              throw Exception(
                  '模型「${config.modelName}」已被弃用，请在「设置助手」中更换为最新模型（如 minimax-m2.7、gpt-4o-mini 等）');
            case 413:
              throw Exception('图片请求体积过大，中转站拒绝。请少发几张或换更清晰的压缩后再试。');
          }

          throw Exception(
              friendly.startsWith('请求') ? friendly : '请求失败: $friendly');
        } catch (e) {
          if (e is Exception) rethrow;
          throw Exception(
              '请求失败: ${response.statusCode} - ${response.reasonPhrase}');
        }
      } catch (e) {
        // 致命错误：直接抛出，不再重试
        if (e.toString().contains('请求过于频繁') ||
            e.toString().contains('服务器繁忙') ||
            e.toString().contains('已被弃用') ||
            e.toString().contains('API Key 无效') ||
            e.toString().contains('余额不足') ||
            e.toString().contains('没有调用权限') ||
            e.toString().contains('模型不存在')) {
          rethrow;
        }

        // 可恢复错误（超时、网络抖动等）：重试
        if (attempt < AppDurations.maxRetries) {
          final waitSeconds = attempt * 3;
          debugPrint(
              '请求失败(${e.runtimeType})，$waitSeconds秒后重试 ($attempt/${AppDurations.maxRetries})');
          await Future.delayed(Duration(seconds: waitSeconds));
          continue;
        }

        // 所有重试耗尽
        rethrow;
      }
    }

    debugPrint('===== AIService.sendMessage: FAILED - 所有重试耗尽 =====');
    throw Exception('网络请求失败，请检查网络连接');
  }
  /// 流式输出版本的sendMessage — 返回Stream<AIStreamChunk>
  Stream<AIStreamChunk> sendMessageStream({
    required AICharacter character,
    required String userId,
    required String userMessage,
    required List<ChatMessage> chatHistory,
    required List<Memory> memories,
    required int intimacyLevel,
    String? userStatus,
    SentimentResult? sentiment,
    String? imageDescription,
    List<String>? imagePaths,
    bool isBlockedByAI = false,
    String? blockReason,
    bool enableWebSearch = false,
    String? internalSystemContext,
    bool isSideStory = false,
    bool forceConcise = false,
  }) async* {
    _lastTurnState = null;
    _lastParsedStatus = null;
    final config = await _storage.getActiveAIConfig();
    if (config == null) throw Exception('No active configuration found');

    final messages = await _buildMessages(
      character: character,
      userId: userId,
      userMessage: userMessage,
      chatHistory: chatHistory,
      memories: memories,
      intimacyLevel: intimacyLevel,
      userStatus: userStatus,
      sentiment: sentiment,
      imageDescription: imageDescription,
      imagePaths: imagePaths,
      isBlockedByAI: isBlockedByAI,
      blockReason: blockReason,
      enableWebSearch: enableWebSearch,
      internalSystemContext: internalSystemContext,
      isSideStory: isSideStory,
      forceConcise: forceConcise,
    );

    yield* _streamAPI(config, messages, forceConcise: forceConcise);
  }
  /// 核心流式API调用 — 解析SSE，yield AIStreamChunk（思考+正文）
  Stream<AIStreamChunk> _streamAPI(AIConfig config,
      List<Map<String, dynamic>> messages,
      {bool forceConcise = false}) async* {
    String baseUrl = config.baseUrl.trim();
    while (baseUrl.endsWith('/')) {
      baseUrl = baseUrl.substring(0, baseUrl.length - 1);
    }
    final url = baseUrl.endsWith('/chat/completions')
        ? Uri.parse(baseUrl)
        : Uri.parse('$baseUrl/chat/completions');

    final allApiKeys = config.allApiKeys;
    int currentKeyIndex = 0;
    final maxTokens =
        _chatMaxTokensForCurrentMode(config.maxTokens, forceConcise: forceConcise);

    for (int attempt = 1; attempt <= AppDurations.maxRetries; attempt++) {
      try {
        final currentKey = allApiKeys[currentKeyIndex % allApiKeys.length];
        final client = http.Client();
        try {
          final request = http.Request('POST', url);
          request.headers['Content-Type'] = 'application/json; charset=utf-8';
          request.headers['Accept-Charset'] = 'utf-8';
          request.headers['Authorization'] = 'Bearer $currentKey';
          final requestPayload = <String, dynamic>{
            'model': config.modelName,
            'messages': messages,
            'temperature': config.temperature,
            'stream': true,
            // 对抗复读：惩罚重复 token / 重复话题
            'frequency_penalty': ApiDefaults.chatFrequencyPenalty,
            'presence_penalty': ApiDefaults.chatPresencePenalty,
          };
          if (maxTokens != null) {
            requestPayload['max_tokens'] = maxTokens;
          }
          final requestBody = jsonEncode(requestPayload);
          request.body = requestBody;

          final streamedResponse =
              await client.send(request).timeout(AppDurations.aiRequest);
          final contentType = streamedResponse.headers['content-type'];

          if (streamedResponse.statusCode != 200) {
            final errorBytes = await streamedResponse.stream.toBytes();
            final body = await _decodeBody(contentType, errorBytes);
            if (streamedResponse.statusCode == 429) {
              // 先尝试切换备用 Key（与 sendMessage 非流式路径一致）
              if (allApiKeys.length > 1 &&
                  currentKeyIndex < allApiKeys.length - 1) {
                currentKeyIndex++;
                debugPrint(
                    '流式请求被限速(429)，切换到备用 Key ($currentKeyIndex/${allApiKeys.length})');
                continue;
              }
              if (attempt < AppDurations.maxRetries) {
                currentKeyIndex = 0; // 全部 key 重试完毕，重置索引后等待
                final waitSeconds = attempt * 10;
                debugPrint(
                    '所有 Key 均被限流(流式)，$waitSeconds秒后重试 ($attempt/${AppDurations.maxRetries})');
                await Future.delayed(Duration(seconds: waitSeconds));
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
              final friendly = _friendlyApiErrorMessage(
                errorMsg?.toString(),
                modelName: config.modelName,
              );
              final code = streamedResponse.statusCode;
              if (code == 400 || code == 413) {
                throw Exception(friendly);
              }
              if (code == 403) {
                throw Exception(VisionImageEncoder.friendlyVisionError(
                        errorMsg?.toString()) ??
                    friendly);
              }
              throw Exception('API错误 ($code): $friendly');
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

          // P4: 逐 chunk 超时保护 — 切换模型后若流式连接挂起，
          // 60s 内无新数据则中断，避免无限等待。
          DateTime lastChunkTime = DateTime.now();
          final perChunkTimeout = const Duration(seconds: 60);
          final timedLineStream =
              lineStream.timeout(perChunkTimeout, onTimeout: (sink) {
            if (accumulatedContent.isNotEmpty ||
                accumulatedReasoning.isNotEmpty) {
              // 已有部分内容，正常结束流
              sink.close();
            } else {
              sink.addError(TimeoutException('流式响应超时，60秒未收到新数据'));
            }
          });

          try {
            await for (final line in timedLineStream) {
              lastChunkTime = DateTime.now();
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
                // 流式路径空内容兜底：非流式有 _cleanResponse 兜底，流式缺失
                if (accumulatedContent.isEmpty &&
                    accumulatedReasoning.isEmpty) {
                  const fallback = '嗯，让我想想该怎么回答你。';
                  yield AIStreamChunk(reasoning: '', content: fallback);
                }
                return;
              }

              try {
                final json = jsonDecode(data) as Map<String, dynamic>;
                final type = json['type'] as String?;

                // 主动捕获 usage（OpenAI 非流式最终 chunk / Anthropic message_delta / Responses API）
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
                        content: accumulatedContent,
                        usage: chunkUsage);
                  }
                  continue;
                }
                // Anthropic message_delta 可能包含 usage
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
                      accumulatedContent += ResponseDecoder.repairText(delta);
                      yield AIStreamChunk(
                          reasoning: accumulatedReasoning,
                          content: accumulatedContent,
                          usage: chunkUsage);
                    }
                  } else if (type == 'response.reasoning.delta') {
                    final delta = json['delta'] as String?;
                    if (delta != null) {
                      accumulatedReasoning += ResponseDecoder.repairText(delta);
                      yield AIStreamChunk(
                          reasoning: accumulatedReasoning,
                          content: accumulatedContent,
                          usage: chunkUsage);
                    }
                  } else if (type == 'response.completed') {
                    final response = json['response'] as Map<String, dynamic>?;
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
                  final choice = choices[0] as Map<String, dynamic>;
                  final finishReason = choice['finish_reason']?.toString();
                  final delta = choice['delta'] as Map<String, dynamic>?;
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
                  final message = choice['message'] as Map<String, dynamic>?;
                  if (message != null) {
                    final msgContent = message['content'] ?? message['text'];
                    if (msgContent != null) {
                      accumulatedContent +=
                          ResponseDecoder.repairText(msgContent as String);
                      yield AIStreamChunk(
                          reasoning: accumulatedReasoning,
                          content: accumulatedContent);
                    }
                  }
                  if (finishReason != null && finishReason.isNotEmpty) {
                    yield AIStreamChunk(
                      reasoning: accumulatedReasoning,
                      content: accumulatedContent,
                      finishReason: finishReason,
                      usage: chunkUsage,
                    );
                  }
                }

                if (json['content'] != null) {
                  accumulatedContent +=
                      ResponseDecoder.repairText(json['content'] as String);
                  yield AIStreamChunk(
                      reasoning: accumulatedReasoning,
                      content: accumulatedContent);
                } else if (json['response'] != null &&
                    json['response'] is String) {
                  accumulatedContent +=
                      ResponseDecoder.repairText(json['response'] as String);
                  yield AIStreamChunk(
                      reasoning: accumulatedReasoning,
                      content: accumulatedContent);
                }
              } catch (e) {
                debugPrint('SSE parse error: $e, data: $data');
              }
            }

            // 流式结束但无内容（未收到 [DONE] 或 API 直接关闭连接）
            if (accumulatedContent.isEmpty && accumulatedReasoning.isEmpty) {
              const fallback = '嗯，让我想想该怎么回答你。';
              yield AIStreamChunk(reasoning: '', content: fallback);
            }
            return;
          } on TimeoutException {
            // P4: 流式超时 — 已有部分内容时正常结束，否则抛出异常触发兜底
            debugPrint(
                '[AIService] 流式 chunk 超时，已累积 ${accumulatedContent.length} 字符');
            if (accumulatedContent.isNotEmpty ||
                accumulatedReasoning.isNotEmpty) {
              yield AIStreamChunk(
                  reasoning: accumulatedReasoning, content: accumulatedContent);
              return;
            }
            throw Exception('流式响应超时，请重试');
          }
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
  String? _extractStatus(String content) {
    try {
      final regex = RegExp(r'\[STATUS\](.*?)\[/STATUS\]', dotAll: true);
      final match = regex.firstMatch(content);
      if (match != null) {
        return match.group(1)?.trim();
      }
    } catch (e) {
      debugPrint('提取状态标记失败: $e');
    }
    return null;
  }
  /// 智能解码 HTTP 响应体，处理不同编码的 API 响应
  Future<String> _decodeBody(String? contentType, List<int> bodyBytes) {
    return ResponseDecoder.decode(contentType, bodyBytes);
  }
  String _cleanResponse(String content) {
    String cleaned = MessageSanitizer.stripReasoningTags(content)[0];
    cleaned = MessageSanitizer.stripInternalControlLeaks(cleaned);

    // 剥离 BT Agent payload（防止污染聊天历史和记忆）
    cleaned = stripBtAgentPayloads(cleaned, preserveVisibleText: true);

    // 无标签推理过程泄漏检测
    cleaned = MessageSanitizer.stripReasoningLeak(cleaned);

    cleaned = cleaned.replaceAll(
        RegExp(r'\[STATUS\].*?\[/STATUS\]', caseSensitive: false, dotAll: true),
        '');
    cleaned = cleaned.replaceAll(
        RegExp(r'\[/?\s*STATUS\s*\]', caseSensitive: false), '');
    cleaned = cleaned.replaceAll(
        RegExp(r'\[TURN_STATE\].*?\[/TURN_STATE\]',
            caseSensitive: false, dotAll: true),
        '');
    cleaned = cleaned.replaceAll(
        RegExp(r'\[TURN_STATE\].*?\[/TURN_STATE\]',
            caseSensitive: false, dotAll: true),
        '');
    cleaned = cleaned.replaceAll(
        RegExp(r'\[STICK\w*[^\]]*\]', caseSensitive: false), '');
    // 过滤内部上下文标签泄漏 — 某些模型会把 <internal_context> 当正文输出
    cleaned = cleaned.replaceAll(
        RegExp(r'<internal_context[\s\S]*?</internal_context>',
            caseSensitive: false, dotAll: true),
        '');
    cleaned = cleaned.replaceAll(
        RegExp(r'internal_context[\s\S]{0,200}visibility[\s\S]{0,100}private',
            caseSensitive: false, dotAll: true),
        '');

    final faMode = _storage.isFaModeEnabled();

    if (!faMode) {
      cleaned = cleaned.replaceAll(RegExp(r'\*[^*]*\*'), '');
      cleaned = cleaned.replaceAll(RegExp(r'\[[^\]]*\]'), '');
      cleaned = cleaned.replaceAll(RegExp(r'\([a-zA-Z\s]+\)'), '');
    }

    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ');
    cleaned = cleaned.trim();
    cleaned = MessageSanitizer.stripInternalControlLeaks(cleaned);
    // 只清理开头的逗号/顿号/空白，保留句末标点（。！？等）
    cleaned = cleaned.replaceAll(RegExp(r'^[，,、；;\s]+'), '');
    cleaned = cleaned.replaceAll(RegExp(r'[，,、；;\s]+$'), '');
    cleaned = _convertToSimplifiedChinese(cleaned);
    cleaned = cleaned.replaceAll(
        RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F-\x9F]'), '');

    // 人称代词轻量纠错（依赖最近一次 build 时缓存的角色性别）
    if (_lastCharacterGender != null || _lastCharacterName != null) {
      cleaned = MessageSanitizer.fixGenderPronouns(
        cleaned,
        characterGender: _lastCharacterGender,
        characterName: _lastCharacterName,
      );
    }

    if (MessageSanitizer.isLikelyUnreadableGibberish(cleaned)) {
      cleaned = '';
    }

    if (cleaned.isEmpty) {
      cleaned = '嗯，让我想想该怎么回答你。';
    }

    return cleaned;
  }
  String _buildGlobalModePrompt({String scope = 'AI回复'}) {
    return _storage.buildGlobalModePrompt(scope: scope);
  }

  /// 过滤 AI 回复中可能幻觉出的错误名字
  ///
  /// 当 AI 错误地使用了不属于用户的名字时，替换为用户的昵称
  static String filterHallucinatedNames(String content, String? userNickname) {
    if (content.isEmpty || userNickname == null || userNickname.isEmpty) {
      return content;
    }

    // 常见的中文名字模式（2-4个汉字的名字）
    // 匹配 "我是XX"、"我叫XX" 等自我介绍模式中的错误名字
    final namePatterns = [
      RegExp(r'(?:我是|我叫|我的名字是)([^\s，。！？,\.!?]{2,4})'),
    ];

    String result = content;
    for (final pattern in namePatterns) {
      result = result.replaceAllMapped(pattern, (match) {
        final hallucinatedName = match.group(1)!;
        // 如果匹配到的名字不是用户昵称，替换为用户昵称
        if (hallucinatedName != userNickname &&
            !userNickname.contains(hallucinatedName)) {
          return match.group(0)!.replaceFirst(hallucinatedName, userNickname);
        }
        return match.group(0)!;
      });
    }

    return result;
  }
  /// 简洁模式硬截断：在句末标点处截断，不超过 maxLength
  /// 流式显示用清洗：去除非STICKER标签，保留STICKER标签给UI处理
  /// 返回 [cleanedText, extractedReasoning?]
  static List<String> cleanForStreamDisplay(String content) {
    final reasoningParts = MessageSanitizer.stripReasoningTags(content);
    String cleaned =
        MessageSanitizer.stripInternalControlLeaks(reasoningParts[0]);
    final extractedReasoning = reasoningParts[1];

    // 去除STATUS标签
    cleaned = cleaned.replaceAll(
        RegExp(r'\[STATUS\].*?\[/STATUS\]', caseSensitive: false, dotAll: true),
        '');
    cleaned = cleaned.replaceAll(
        RegExp(r'\[/?\s*STATUS\s*\]', caseSensitive: false), '');
    // 去除BT_ACTION标签（流式展示净化）
    cleaned = cleaned.replaceAll(
        RegExp(r'<BT_ACTION>.*?</BT_ACTION>',
            caseSensitive: false, dotAll: true),
        '');
    // 过滤internal_context标签泄漏
    cleaned = cleaned.replaceAll(
        RegExp(r'<internal_context[\s\S]*?</internal_context>',
            caseSensitive: false, dotAll: true),
        '');
    // 去除控制字符
    cleaned = cleaned.replaceAll(
        RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F-\x9F]'), '');
    cleaned = cleaned.trim();
    // 繁体→简体转换（流式路径也需要）
    cleaned = _convertToSimplifiedChinese(cleaned);

    return [cleaned, extractedReasoning];
  }
  static String _convertToSimplifiedChinese(String text) {
    // 常见繁体到简体映射（修复了原版本中的错误映射）
    final map = {
      '愛': '爱',
      '們': '们',
      '個': '个',
      '時': '时',
      '說': '说',
      '話': '话',
      '為': '为',
      '會': '会',
      '對': '对',
      '來': '来',
      '國': '国',
      '過': '过',
      '後': '后',
      '開': '开',
      '見': '见',
      '問': '问',
      '題': '题',
      '點': '点',
      '這': '这',
      '麼': '么',
      '著': '着',
      '還': '还',
      '沒': '没',
      '聽': '听',
      '覺': '觉',
      '請': '请',
      '讓': '让',
      '給': '给',
      '與': '与',
      '嘆': '叹',
      '嘩': '哗',
      '嘰': '叽',
      '嘵': '哓',
      '嘷': '嗥',
      '嘸': '呒',
      '當': '当',
      '應': '应',
      '該': '该',
      '夠': '够',
      '須': '须',
      '並': '并',
      '經': '经',
      '壞': '坏',
      '錯': '错',
      '實': '实',
      '際': '际',
      '現': '现',
      '裡': '里',
      '內': '内',
      '東': '东',
      '邊': '边',
      '間': '间',
      '處': '处',
      '體': '体',
      '統': '统',
      '組': '组',
      '織': '织',
      '結': '结',
      '構': '构',
      '機': '机',
      '設': '设',
      '計': '计',
      '劃': '划',
      '圖': '图',
      '書': '书',
      '學': '学',
      '習': '习',
      '業': '业',
      '較': '较',
      '長': '长',
      '舊': '旧',
      '種': '种',
      '類': '类',
      '別': '别',
      '號': '号',
      '稱': '称',
      '親': '亲',
      '鄰': '邻',
      '師': '师',
      '級': '级',
      '週': '周',
      '鐘': '钟',
      '頭': '头',
      '腳': '脚',
      '憶': '忆',
      '識': '识',
      '訴': '诉',
      '講': '讲',
      '談': '谈',
      '樂': '乐',
      '傷': '伤',
      '閒': '闲',
      '滿': '满',
      '節': '节',
      '頁': '页',
      '錄': '录',
      '誰': '谁',
      '於': '于',
      '從': '从',
      '進': '进',
      '歸': '归',
      '離': '离',
      '關': '关',
      '閉': '闭',
      '買': '买',
      '賣': '卖',
      '價': '价',
      '錢': '钱',
      '費': '费',
      '報': '报',
      '風': '风',
      '雲': '云',
      '霧': '雾',
      '電': '电',
      '氣': '气',
      '聲': '声',
      '畫': '画',
      '戲': '戏',
      '劇': '剧',
      '視': '视',
      '頻': '频',
      '網': '网',
      '絡': '络',
      '線': '线',
      '車': '车',
      '飛': '飞',
      '場': '场',
      '樓': '楼',
      '門': '门',
      '牆': '墙',
      '階': '阶',
      '層': '层',
      '頂': '顶',
      '緣': '缘',
      '圍': '围',
      '圓': '圆',
      '狀': '状',
      '態': '态',
      '況': '况',
      '虛': '虚',
      '確': '确',
      '誤': '误',
      '斷': '断',
      '釋': '释',
      '顯': '显',
      '隱': '隐',
      '藏': '藏',
      '觀': '观',
      '檢': '检',
      '驗': '验',
      '測': '测',
      '試': '试',
      '尋': '寻',
      '趕': '赶',
      '達': '达',
      '極': '极',
      '數': '数',
      '減': '减',
      '變': '变',
      '轉': '转',
      '換': '换',
      '動': '动',
      '繼': '继',
      '續': '续',
      '連': '连',
      '補': '补',
      '歲': '岁',
      '紀': '纪',
      '廣': '广',
      '廳': '厅',
      '廚': '厨',
      '衛': '卫',
      '臥': '卧',
      '陽': '阳',
      '陰': '阴',
      '麵': '面',
      '裏': '里',
      '鬆': '松',
      '膩': '腻',
      '軟': '软',
      '緊': '紧',
      '細': '细',
      '淺': '浅',
      '寬': '宽',
      '遠': '远',
      '醜': '丑',
      '惡': '恶',
      '鹹': '咸',
      '豐': '丰',
    };

    String result = text;
    for (final entry in map.entries) {
      result = result.replaceAll(entry.key, entry.value);
    }
    return result;
  }
  static const _visionEncoder = VisionImageEncoder();
  /// 检测AI消息是否为拒绝/说教回复（用于FA模式过滤历史中的旧拒绝消息）
  static bool _isRefusalMessage(String content) {
    return MessageSanitizer.isAIRefusal(content);
  }
  static final RegExp _actionBracketPattern = RegExp(r'（[^（）]+）|\([^()]+\)');
  static List<String> _stringList(Object? value) => value is List
      ? value
          .map((v) => v.toString())
          .where((v) => v.trim().isNotEmpty)
          .toList()
      : const [];
}

