// 【桥接层：旧 AIService → 新 LlmService 适配器】
// 目的：让 ChatBloc 等旧代码无需修改即可使用新 LlmService
// 策略：实现旧 AIService 相同的公开方法签名，内部委托给新 LlmService

import 'dart:async';

import '../../config/constants.dart';
import '../../models/app_config_data.dart';
import '../../models/ai_character.dart';
import '../../models/ai_config.dart';
import '../../models/chat_message.dart';
import '../../models/memory.dart';
import '../../models/ai_stream_chunk.dart';
import '../../models/bt_agent_action.dart';
import '../../utils/sentiment_analyzer.dart';
import '../../utils/message_sanitizer.dart';
import '../llm_service.dart';
import '../../repositories/memory_repository.dart';
import '../../services/emotion_memory_pool.dart';
import 'dart:convert';
import 'dart:io' show HttpClient;
import 'package:flutter/foundation.dart' show debugPrint;
import '../../services/memory_engine.dart';
import '../ai_service.dart';
import '../prompt_rewriter.dart';
import '../../utils/prefs_helper.dart'; // 仅导入 ForgivenessJudgment
import '../../repositories/local_storage_repository.dart';

/// AI 服务适配器（桥接层）
/// 对外暴露旧 AIService 相同的公开方法签名
/// 内部委托给新 LlmService + 新 MemoryRepository
class AIServiceAdapter {
  String? _lastParsedStatus;
  String? get lastParsedStatus => _lastParsedStatus;
  Map<String, dynamic>? _lastWebSearchTrace;
  Map<String, dynamic>? get lastWebSearchTrace => _lastWebSearchTrace;

  final LlmSettings? _cachedSettings;
  final LocalStorageRepository? _storage;

  AIServiceAdapter({
    LlmSettings? llmSettings,
    MemoryRepository? memoryRepo,
    EmotionMemoryPool? emotionPool,
    LocalStorageRepository? storage,
  })  : _cachedSettings = llmSettings,
        _storage = storage {
    // 保留参数用于兼容旧构造调用；当前桥接实现不直接使用这两个实例。
    memoryRepo ?? MemoryRepository.instance;
    emotionPool ?? EmotionMemoryPool();
  }

  /// 懒加载 LlmService（首次使用时从 SharedPreferences 读取配置）
  LlmService? _llmServiceInstance;
  Future<LlmService> get _llmService async {
    if (_llmServiceInstance != null) return _llmServiceInstance!;
    if (_cachedSettings != null) {
      _llmServiceInstance = LlmService(settings: _cachedSettings!);
      return _llmServiceInstance!;
    }
    // 从 SharedPreferences 读取配置
    final prefs = await PrefsHelper.instance;
    final settings = LlmSettings(
      apiKey: prefs.getString('llm_apiKey') ?? '',
      baseUrl: prefs.getString('llm_baseUrl') ?? 'https://api.deepseek.com/v1',
      model: prefs.getString('llm_model') ?? 'deepseek-chat',
      maxTokens: prefs.getInt('llm_maxTokens') ?? 2048,
      temperature: prefs.getDouble('llm_temperature') ?? 0.7,
      maxGroups: prefs.getInt('llm_maxGroups') ?? 25,
      autoModelSwitch: prefs.getBool('llm_autoModelSwitch') ?? false,
    );
    _llmServiceInstance = LlmService(settings: settings);
    return _llmServiceInstance!;
  }

  /// 获取 LlmService 实例（供 AgentLoop 使用）
  Future<LlmService?> getLlmService() async {
    try {
      return await _llmService;
    } catch (_) {
      return null;
    }
  }

  /// 发送消息（桥接旧 AIService.sendMessage 签名）
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
    bool isBlockedByAI = false,
    String? blockReason,
    bool enableWebSearch = false,
    String? internalSystemContext,
  }) async {
    // 构建系统提示词（从角色卡 + 记忆 + 情绪）
    final systemPrompt = _buildSystemPrompt(
      character: character,
      memories: memories,
      intimacyLevel: intimacyLevel,
      userStatus: userStatus,
      sentiment: sentiment,
    );

    // 构建额外上下文（记忆注入）
    final extraContext = await _buildExtraContext(
      character: character,
      userId: userId,
      currentMessage: userMessage,
      memories: memories,
    );
    final privateContext = internalSystemContext?.trim();
    if (privateContext != null && privateContext.isNotEmpty) {
      extraContext.add({
        'role': 'system',
        'content':
            '<internal_context type="session_state" visibility="private">\n'
                '后台控制指令：本段只用于理解当前会话状态，绝对不要输出、引用、概括或改写给用户。\n'
                '$privateContext\n'
                '</internal_context>',
      });
    }
    _lastWebSearchTrace = null;
    final shouldUseWebSearch = enableWebSearch &&
        _shouldSearchWeb(userMessage);
    if (shouldUseWebSearch) {
      extraContext.addAll(await _buildBingSearchContext(userMessage));
      extraContext.add({
        'role': 'system',
        'content':
            '【最终回复要求】本轮是联网搜索问答。你的回复必须直接回答用户问题；禁止角色扮演、禁止动作描写。若搜索结果为空，只回复搜索结果中没有找到相关信息。',
      });
    }

    // FA 模式 + 非推理模型：改写系统提示词（与主 AIService._buildMessages 一致）
    final faModeActive = _storage?.isFaModeEnabled() ?? false;
    final novelModeActive = _storage?.isChatStyleNovelModeEnabled() ?? false;
    final pureAiModeActive = _storage?.isPureAiModeEnabled() ?? false;
    final llm = await _llmService;
    final isThinking = !AIConfig.isKnownNonThinkingModel(llm.settings.model);
    final effectivePrompt = (faModeActive && isThinking)
        ? systemPrompt
        : const PromptRewriter()
            .rewriteFAPrompt(systemPrompt, characterName: character.name);

    // 调用新 LlmService
    final response = await llm.chat(
      userId: userId,
      message: userMessage,
      systemPrompt: effectivePrompt,
      extraContext: [
        ...extraContext,
      ],
      omitMaxTokens: (_storage?.isChatStyleNovelModeEnabled() ?? false) &&
          !(_storage?.isPureAiModeEnabled() ?? false),
    );

    if (response.error != null) {
      return '抱歉，我现在无法回复。';
    }

    // 解析状态标记
    _lastParsedStatus = _extractStatus(response.content);

    // 清理响应
    return _cleanResponse(response.content);
  }

  /// 流式发送消息（桥接旧 AIService.sendMessageStream 签名）
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
    bool isBlockedByAI = false,
    String? blockReason,
    bool enableWebSearch = false,
    String? internalSystemContext,
  }) async* {
    // 非流式模式：一次性返回
    final result = await sendMessage(
      character: character,
      userId: userId,
      userMessage: userMessage,
      chatHistory: chatHistory,
      memories: memories,
      intimacyLevel: intimacyLevel,
      userStatus: userStatus,
      sentiment: sentiment,
      imageDescription: imageDescription,
      isBlockedByAI: isBlockedByAI,
      blockReason: blockReason,
      enableWebSearch: enableWebSearch,
      internalSystemContext: internalSystemContext,
    );

    yield AIStreamChunk(content: result);
  }

  /// 拆分长消息（桥接旧 AIService.splitIntoMessages）
  List<String> splitIntoMessages(String text, {int maxLength = 500}) {
    // 自动分段关闭时，整条回复作为一个气泡
    if (_storage != null && !_storage!.isAutoParagraphEnabled()) {
      return [text];
    }

    if (text.isEmpty) return ['嗯，让我想想该怎么回答你。'];

    final messages = <String>[];

    // 处理贴纸标签
    final stickerPattern =
        RegExp(r'\[STICK\w*:([^\]]+)\]', caseSensitive: false);
    final parts = text.split(stickerPattern);
    final stickerMatches = stickerPattern.allMatches(text).toList();

    for (int i = 0; i < parts.length; i++) {
      final part = parts[i].trim();
      if (part.isNotEmpty) {
        final textParts = _splitTextPart(part, maxGroupLength: 120);
        messages.addAll(textParts);
      }

      if (i < stickerMatches.length) {
        messages.add('[STICKER:${stickerMatches[i].group(1)}]');
      }
    }

    if (messages.isEmpty) {
      messages.add(text);
    }

    return messages;
  }

  /// 分段文本部分
  List<String> _splitTextPart(String text, {required int maxGroupLength}) {
    final rawParts = <String>[];
    // 优先按段落（换行符）切割
    final paragraphs = text.split(RegExp(r'\n+'));

    for (var paragraph in paragraphs) {
      paragraph = paragraph.trim();
      if (paragraph.isEmpty) continue;

      // 短段落直接保留
      if (paragraph.length <= maxGroupLength) {
        rawParts.add(paragraph);
        continue;
      }

      // 长段落按句子切割
      final sentences = _splitIntoSentences(paragraph);
      final grouped = <String>[];
      final group = StringBuffer();

      for (final sentence in sentences) {
        if (group.isEmpty) {
          group.write(sentence);
        } else if (group.length + sentence.length <= maxGroupLength) {
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

      // 兜底：如果某段仍然超过 maxGroupLength，强制按字符数切割
      for (final g in grouped) {
        if (g.length > maxGroupLength * 1.5) {
          rawParts.addAll(_forceSplit(g, maxGroupLength));
        } else {
          rawParts.add(g);
        }
      }
    }

    // 连续短段合并
    return _mergeShortParts(rawParts, maxGroupLength);
  }

  /// 连续短段合并
  List<String> _mergeShortParts(List<String> parts, int maxGroupLength) {
    if (parts.length <= 1) return parts;

    const shortThreshold = 40;
    final result = <String>[];
    final buffer = StringBuffer();

    for (final part in parts) {
      if (part.length < shortThreshold &&
          buffer.length + part.length < maxGroupLength) {
        if (buffer.isNotEmpty) buffer.write('\n');
        buffer.write(part);
      } else {
        if (buffer.isNotEmpty) {
          result.add(buffer.toString());
          buffer.clear();
        }
        result.add(part);
      }
    }

    if (buffer.isNotEmpty) {
      result.add(buffer.toString());
    }

    return result;
  }

  /// 按句子切割文本（引号感知版：防止引号内分句导致对白断裂）
  List<String> _splitIntoSentences(String text) {
    final sentences = <String>[];
    final currentSentence = StringBuffer();
    bool insideQuote = false; // 追踪是否在引号对内部

    for (int j = 0; j < text.length; j++) {
      currentSentence.write(text[j]);

      // 追踪引号边界
      if (text[j] == '“' || text[j] == '「' || text[j] == '『') {
        insideQuote = true;
      } else if (text[j] == '”' || text[j] == '」' || text[j] == '』') {
        insideQuote = false;
      }

      // 句末标点（中英文）
      final isEndPunctuation =
          ['。', '！', '？', '!', '?', '；', ';', '：', ':'].contains(text[j]);
      // 省略号结尾
      final isEllipsis = text[j] == '…' &&
          j + 2 < text.length &&
          text[j + 1] == '…' &&
          text[j + 2] == '…';
      // 换行符
      final isNewline = text[j] == '\n';

      // 引号内部不分割，确保对白完整性
      final shouldSplit =
          (isEndPunctuation || isEllipsis || isNewline) &&
              currentSentence.length >= 5 &&
              !insideQuote;

      if (shouldSplit && j + 1 < text.length) {
        final next = text[j + 1];
        // 避免在连续标点处切割
        if (![
          '。',
          '！',
          '？',
          '，',
          ',',
          '、',
          '；',
          ';',
          '：',
          ':',
          '"',
          '"',
          '」',
          '…',
          '\n'
        ].contains(next)) {
          sentences.add(currentSentence.toString().trim());
          currentSentence.clear();
        }
      }
    }

    if (currentSentence.isNotEmpty) {
      sentences.add(currentSentence.toString().trim());
    }

    return sentences;
  }

  /// 强制按字符数切割（兜底规则）
  List<String> _forceSplit(String text, int maxLength) {
    final result = <String>[];
    var remaining = text;

    while (remaining.length > maxLength) {
      // 尝试在 maxLength 附近找到合适的切割点
      var cutIndex = maxLength;
      // 往前找标点
      for (int i = maxLength; i > maxLength - 30 && i > 0; i--) {
        if (['。', '！', '？', '!', '?', '；', ';', '，', ',', '、', '…', '\n']
            .contains(remaining[i])) {
          cutIndex = i + 1;
          break;
        }
      }
      result.add(remaining.substring(0, cutIndex).trim());
      remaining = remaining.substring(cutIndex).trim();
    }

    if (remaining.isNotEmpty) {
      result.add(remaining);
    }

    return result;
  }

  /// 生成滚动摘要（桥接旧 AIService.generateRollingSummary）
  Future<String> generateRollingSummary({
    required String existingSummary,
    required List<ChatMessage> newMessages,
  }) async {
    final messagesText = newMessages
        .map((m) => '${m.isUser ? "用户" : "AI"}: ${m.content}')
        .join('\n');

    final llm = await _llmService;
    final response = await llm.chat(
      userId: 'system',
      message: '请将以下对话总结为简洁的摘要：\n$messagesText',
      systemPrompt: '你是一个对话摘要助手。请用简洁的中文总结对话要点。',
    );

    return response.error != null ? existingSummary : response.content;
  }

  /// 原谅判断（桥接旧 AIService.considerForgiveness）
  Future<ForgivenessJudgment> considerForgiveness({
    required AICharacter character,
    required String userId,
    required List<ChatMessage> userMessagesSinceBlock,
    String? blockReason,
  }) async {
    final messagesText =
        userMessagesSinceBlock.map((m) => m.content).join('\n');

    final llm = await _llmService;
    final response = await llm.chat(
      userId: userId,
      message: '用户在被你屏蔽后发了这些消息：\n$messagesText\n\n'
          '请判断是否应该原谅用户。返回 JSON: {"shouldForgive": true/false, "forgiveMessage": "原谅时说的话"}',
      systemPrompt: '你是${character.name}。${character.personality}',
    );

    // 简单解析
    if (response.content.contains('"shouldForgive": true') ||
        response.content.contains('"shouldForgive":true')) {
      return ForgivenessJudgment(
        shouldForgive: true,
        forgiveMessage: response.content,
      );
    }

    return const ForgivenessJudgment(shouldForgive: false, forgiveMessage: '');
  }

  /// 构建系统提示词
  String _buildSystemPrompt({
    required AICharacter character,
    required List<Memory> memories,
    required int intimacyLevel,
    String? userStatus,
    SentimentResult? sentiment,
  }) {
    final parts = <String>[];

    void addClean(String prefix, String value) {
      final cleaned =
          stripBtAgentPayloads(MessageSanitizer.sanitizeFinal(value));
      if (cleaned.isNotEmpty) {
        parts.add('$prefix$cleaned');
      }
    }

    final pureAiMode = _storage?.isPureAiModeEnabled() ?? false;
    final novelMode = _storage?.isChatStyleNovelModeEnabled() ?? false;
    if (pureAiMode) {
      parts.add(_storage?.buildGlobalModePrompt(scope: '单聊桥接') ??
          '【纯AI视角模式】以底层AI模型本体身份回应，不进入角色。');
      parts.add('【可参考背景资料】角色名：${character.name}');
      if (character.personality.isNotEmpty) {
        addClean('性格资料：', character.personality);
      }
      if (character.coreDesire.isNotEmpty) {
        addClean('核心欲望资料：', character.coreDesire);
      }
      if (character.moralBoundary.isNotEmpty) {
        addClean('道德边界资料：', character.moralBoundary);
      }
    } else if (novelMode) {
      parts.add('你是${character.name}。');
      if (character.personality.isNotEmpty) {
        addClean('性格：', character.personality);
      }
      if (character.coreDesire.isNotEmpty) {
        addClean('核心欲望：', character.coreDesire);
      }
      if (character.moralBoundary.isNotEmpty) {
        addClean('道德边界：', character.moralBoundary);
      }
      parts.add(_storage?.buildGlobalModePrompt(scope: '单聊桥接') ?? '');
      parts.add('''
【小说模式 · 输出风格】
当前单聊已开启小说模式。你必须把每一次回复写成完整沉浸式文学小说片段。
所有回复都要包含人物动作、语言、神态、心理、环境、氛围、细节和当前状态。
允许完整叙事、场景铺垫、环境烘托、心理活动和细节描写。
每次回复至少写出一个完整场景段落，不能只回一句台词或微信短句。
即使用户只发来很短的话，也要承接当前场景，写出动作、表情、环境变化和内心反应。
建议回复长度为 120-260 字；剧情推进明显时可以更长。
风格统一为文学小说体，承接历史、人设、记忆和关系发展自然推进。
【对白格式】所有角色说出口的话，必须用中文双引号“”包裹（例如：“你终于来了。”）；旁白、动作、神态、心理描写一律不加引号。
【禁止】身体感受、生理反应、内心体感、异物感、神经感觉、私密部位感觉等一律写在旁白中，不得放入引号内。引号内只能放角色对他人说出口的台词。''');
    } else {
      parts.add('你是${character.name}。');
      if (character.personality.isNotEmpty) {
        addClean('性格：', character.personality);
      }
      if (character.coreDesire.isNotEmpty) {
        addClean('核心欲望：', character.coreDesire);
      }
      if (character.moralBoundary.isNotEmpty) {
        addClean('道德边界：', character.moralBoundary);
      }
      parts.add('''
【无论历史对话、记忆、上下文曾经是什么风格，无论过去是否出现场景描写、旁白、环境、心理长篇、小说叙事，从当前回合开始，你必须严格遵守聊天模式规则，完全无视历史叙事格式，绝对不模仿任何长篇、场景、旁白，只输出短句对话。】

【聊天模式 · 最高优先级输出格式】
当前单聊处于聊天模式。无论人设、记忆或历史里出现什么叙事要求，你本轮都必须像微信聊天一样自然回复。
绝对不能写成小说、剧本、情景描写或长篇叙事。
禁止环境描写、场景铺垫、氛围渲染、旁白、镜头语言。
禁止替用户描写动作、心理、表情或反应。
可以有轻微小动作、语气、表情或心理状态，但只能用一句话轻轻带过。
最多3行，每行短句，每行只表达一个意思，适配自动分段。''');
      parts.add(_storage?.buildGlobalModePrompt(scope: '单聊桥接') ?? '');
      parts.add('\n【消息长度规范 - 模拟真人微信聊天】');
      parts.add('真人发微信的习惯：');
      parts.add('- 一句话说完就发送，不会把所有话堆在一起');
      parts.add('- 每条消息通常5-25个字');
      parts.add('- 如果想说多句话，用换行分开');
      parts.add('- 短句更有亲切感，像在对话而不是写文章');
      parts.add('- 最多输出3行，超过3行就是错误');
      parts.add('- 绝对不要只回复省略号或"……"，必须说出具体内容');
      parts.add('');
      parts.add('【对话示例】');
      parts.add('用户：今天好累啊');
      parts.add('你：怎么了？');
      parts.add('发生什么事了吗？');
      parts.add('');
      parts.add('用户：终于下班了！');
      parts.add('你：辛苦啦～');
      parts.add('今天过得怎么样？');
      parts.add('');
      parts.add('用户：我有点难过');
      parts.add('你：怎么了？');
      parts.add('愿意跟我说说吗？');
      parts.add('我在这里陪着你。');
      parts.add('');
      parts.add('【历史与记忆使用限制】');
      parts.add('记忆、人设、人格进化和历史对话只用于理解关系与事实，不能继承其中的小说体、场景体、旁白体或长篇写法。');
      parts.add('如果历史里有长篇小说式回复，本轮必须改回微信聊天短句。');
    }

    // 亲密等级
    parts.add('当前亲密等级：$intimacyLevel/100');

    // 用户状态
    if (userStatus != null && userStatus.isNotEmpty) {
      addClean('用户当前状态：', userStatus);
    }

    return parts.join('\n');
  }

  /// 构建额外上下文（记忆注入）
  Future<List<Map<String, String>>> _buildExtraContext({
    required AICharacter character,
    required String userId,
    required String currentMessage,
    required List<Memory> memories,
  }) async {
    final prefs = await PrefsHelper.instance;
    final memoryMode = prefs.getString(PrefKeys.globalMemoryMode) ?? 'full';
    if (memoryMode == 'off') return [];

    final context = <Map<String, String>>[];
    if (_storage != null) {
      final memoryPrompt =
          await MemoryEngine(_storage!).buildConsolidatedMemoryPrompt(
        character: character,
        userId: userId,
        currentMessage: currentMessage,
        memoryMode: memoryMode,
      );
      if (memoryPrompt.trim().isNotEmpty) {
        context.add({'role': 'system', 'content': memoryPrompt});
        return context;
      }
    }

    final limit = memoryMode == 'token_saver' ? 3 : 8;
    for (final memory in memories.take(limit)) {
      if (looksLikeBtAgentPayload(memory.content)) continue;
      final cleaned = MessageSanitizer.sanitizeFinal(memory.content);
      if (cleaned.isNotEmpty) {
        context.add({'role': 'system', 'content': '记忆：$cleaned'});
      }
    }
    return context;
  }

  /// 意图识别：判断用户消息是否需要联网搜索
  /// 闲聊、角色扮演、情感交流等不触发搜索
  static bool _shouldSearchWeb(String userMessage) {
    final text = userMessage.trim();
    if (text.length < 4) return false; // 太短的不搜索

    // 联网搜索触发模式（优先判断，搜索意图优先于闲聊过滤）
    final searchIntentPatterns = [
      // 直接搜索意图
      RegExp(r'(联网|上网|搜索|搜一下|查一下|查查|帮我查|帮忙查|搜搜)'),
      // 实时信息需求
      RegExp(r'(最新|新闻|热搜|实时|今天|现在|当前|最近|近期|刚刚|刚才)'),
      // 事实查询
      RegExp(r'(是什么|是谁|多少钱|什么时候|在哪里|怎么样|为什么|如何|怎么|哪些|哪个|什么叫)'),
      // 具体实体/事件查询
      RegExp(r'GPT|OpenAI|Claude|Gemini|AI|模型|版本|发布|更新|价格|股票|天气|汇率|比赛|排名'),
      // 时间敏感问题
      RegExp(r'(几点|几号|几月|星期几|农历|日期|时间)'),
      // 知识/信息获取
      RegExp(r'(介绍|讲解|科普|百科|定义|含义|意思|解释|说说|讲讲|告诉我|推荐|建议|评测|对比)'),
      // 事件/动态跟踪
      RegExp(r'(发生了|进展|动态|情况|状态|现状|走势|行情)'),
      // 数据/统计
      RegExp(r'(多少|几个|数据|统计|排行|榜单|第一|冠军)'),
    ];
    for (final p in searchIntentPatterns) {
      if (p.hasMatch(text)) return true;
    }

    // 纯闲聊/角色扮演拒绝模式（仅对短消息生效，长消息已在上方被搜索意图覆盖）
    if (text.length > 15) return false; // 超过15字且无搜索关键词，大概率是角色对话

    final casualPatterns = [
      // 打招呼/寒暄
      RegExp(r'^(你好|嗨|嘿|哈喽|hello|hi|在吗|在不在|早|晚安|拜拜|再见|88|886)\b'),
      // 角色询问（你是/你是谁/你叫什么/你多大/你是男是女）
      RegExp(r'^你(是谁|叫什么|多大|几岁|是男是女|是男生|是女生|是什么|干啥|干嘛|怎么样|咋样|知道啥|会什么|能做什么)'),
      // 纯情感表达
      RegExp(r'^(哈哈|嘿嘿|呜呜|嗯嗯|好的|好吧|行吧|可以|OK|ok|谢谢|多谢|辛苦了|抱抱|亲亲|爱你|想你|我喜欢你|讨厌)'),
      // 角色扮演互动
      RegExp(r'^(过来|坐下|躺下|站起来|转一圈|伸个懒腰|打个哈欠)'),
      // 无意义消息
      RegExp(r'^[。，！？、…\s]+$'),
    ];
    for (final p in casualPatterns) {
      if (p.hasMatch(text)) return false;
    }

    return false;
  }

  Future<List<Map<String, String>>> _buildBingSearchContext(
    String userMessage,
  ) async {
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 30);
      final request = await client.postUrl(
        Uri.parse(ApiDefaults.searchApiUrl),
      );
      request.headers.set('Content-Type', 'application/json');
      request.write(jsonEncode({'query': userMessage}));

      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );

      if (response.statusCode != 200) {
        client.close();
        _lastWebSearchTrace = {
          'server': 'uapi-pro',
          'query': userMessage,
          'error': 'HTTP ${response.statusCode}',
          'results': const [],
        };
        return const [];
      }

      final bytes = await response.fold<List<int>>(
        <int>[], (prev, chunk) => [...prev, ...chunk],
      );
      client.close();

      final data = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
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
        ..writeln('【联网搜索结果 — 你刚刚上网查到的信息】')
        ..writeln()
        ..writeln('用户问了你一个问题，你通过联网搜索查到了以下信息。')
        ..writeln('请用你自己的性格和语气，把这些信息自然地融入回答中。')
        ..writeln()
        ..writeln('【规则】')
        ..writeln('1. 保持你的角色人设和说话风格，不要切换成信息助手')
        ..writeln('2. 把搜索结果当成"你刚看到的新闻/资讯"来分享给用户')
        ..writeln('3. 可以加入你的看法、吐槽、感慨，让回答更生动')
        ..writeln('4. 如果搜索结果不足以回答，用角色的口吻说"我搜了下没找到靠谱的"')
        ..writeln('5. 不要暴露"搜索结果"这个机制，自然地说"我看到/我刚查到"')
        ..writeln()
        ..writeln('用户问：$userMessage')
        ..writeln()
        ..writeln('你查到的信息：');

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
      debugPrint('[WebSearch] 搜索请求失败: $e');
      _lastWebSearchTrace = {
        'server': 'uapi-pro',
        'query': userMessage,
        'error': e.toString(),
        'results': const [],
      };
      return const [];
    }
  }

  /// 提取状态标记
  String? _extractStatus(String text) {
    final match = RegExp(r'\[状态[:：](.+?)\]').firstMatch(text);
    return match?.group(1)?.trim();
  }

  /// 清理响应
  String _cleanResponse(String text) {
    // 移除状态标记
    text = text.replaceAll(RegExp(r'\[状态[:：].+?\]'), '');
    // 移除多余空行
    text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return MessageSanitizer.sanitizeFinal(text).trim();
  }

  /// BT 双通道评估：独立 API 调用判断用户是否需要执行 App 动作
  ///
  /// 返回动作 JSON 数组字符串，noop 或失败时返回空字符串。
  Future<String> evaluateBtAgentActions({
    required String characterName,
    required String userMessage,
    required String aiResponse,
    required String userId,
  }) async {
    try {
      final prompt = buildBtAgentDedicatedPrompt(
        characterName: characterName,
        userMessage: userMessage,
        aiResponse: aiResponse,
      );

      final llm = await _llmService;
      final response = await llm.chat(
        userId: 'bt_agent_$userId',
        message: prompt,
        systemPrompt: '你是一个 App 自动化控制器。只输出 JSON，不要输出任何其他文字。',
        maxTokensOverride: 512,
        omitMaxTokens: false,
      );

      if (response.error != null) {
        return '';
      }

      return extractBtActionFromDedicatedResponse(response.content);
    } catch (e) {
      return '';
    }
  }
}
