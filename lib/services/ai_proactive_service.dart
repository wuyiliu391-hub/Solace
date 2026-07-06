import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/ai_character.dart';
import '../models/ai_config.dart';
import '../models/chat_message.dart';
import '../models/chat_session.dart';
import '../repositories/local_storage_repository.dart';
import '../config/constants.dart';
import '../config/business_rules.dart';
import '../utils/response_decoder.dart';
import 'memory_engine.dart';
import 'ai_service.dart';
import 'emotion_engine.dart';

enum ProactiveMessageType {
  morningGreeting,
  nightGreeting,
  festivalGreeting,
  careReminder,
  randomCare,
}

class ProactiveFrequencyRules {
  ProactiveFrequencyRules._();
  static const int dailyMaxMessages = 3;
  static const int minIntervalMinutes = 120;
  static const int recentMessagesToInclude = 10;
}

class AIProactiveService {
  final LocalStorageRepository _storage;
  EmotionEngine? _emotionEngine; // v2: 可选注入，不破坏现有调用

  AIProactiveService(this._storage);

  /// v2: 注入情绪引擎（在 main.dart 中调用）
  void setEmotionEngine(EmotionEngine engine) {
    _emotionEngine = engine;
  }

  Future<String> generateProactiveMessage({
    required AICharacter character,
    required ProactiveMessageType type,
    required int intimacyLevel,
  }) async {
    final config = await _storage.getActiveAIConfig();
    if (config == null) return '';

    try {
      final prompt = _buildProactivePrompt(character, type, intimacyLevel);
      final response = await _callAI(config, prompt, character);

      if (response.isNotEmpty && response != '[SILENT]') {
        return AIService.filterHallucinatedNames(
          _cleanResponse(response),
          character.userNickname,
        );
      }
    } catch (e) {
      debugPrint('生成主动消息失败: $e');
    }

    return '';
  }

  Future<bool> shouldSendProactive({
    required AICharacter character,
    required ChatSession session,
    required MemoryEngine memoryEngine,
  }) async {
    try {
      final config = await _storage.getActiveAIConfig();
      if (config == null) return false;

      if (!(await _checkFrequencyLimit(session.id, character.id))) {
        return false;
      }

      final prompt = await _buildDecisionPrompt(
        character: character,
        session: session,
        memoryEngine: memoryEngine,
      );

      final response = await _callAI(config, prompt, character);
      final shouldSend = !response.contains('[SILENT]');

      debugPrint('主动消息决策: ${character.name} -> ${shouldSend ? "发送" : "静默"}');
      return shouldSend;
    } catch (e) {
      debugPrint('主动消息决策失败: $e');
      return false;
    }
  }

  /// v2: 紧迫感驱动的决策（替代简单定时器）
  ///
  /// 借鉴 Shikigami ASE 六阀门：
  /// 1. 紧迫度 > 阈值（0.35）
  /// 2. 用户沉默 > 5分钟
  /// 3. 冷却公式：间隔 × (1 - urgency × 0.85)
  /// 4. 24小时上限
  /// 5. 连续未回复上限
  ///
  /// 返回：是否应该主动找用户
  Future<bool> shouldSendByUrgency({
    required AICharacter character,
    required String userId,
    required ChatSession session,
    double? reflectionUrgency, // v2: 反思引擎的 LLM 紧迫度（优先使用）
  }) async {
    if (_emotionEngine == null) return false;

    try {
      // 阀门1：紧迫度阈值
      // 优先使用反思引擎的 urgency（LLM 主观判断），回退到情绪引擎的公式计算
      final urgency = reflectionUrgency ??
          await _emotionEngine!.getUrgency(
            characterId: character.id,
            userId: userId,
          );
      if (urgency < 0.35) {
        debugPrint(
            'ASE: ${character.name} 紧迫度不足 ${urgency.toStringAsFixed(2)} < 0.35');
        return false;
      }

      // 阀门2：用户至少沉默5分钟
      final messages = await _storage.getChatMessages(session.id);
      if (messages.isNotEmpty) {
        final lastUserMsg = messages
            .where((m) => !m.senderId.startsWith('ai_'))
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        if (lastUserMsg.isNotEmpty) {
          final silenceMinutes =
              DateTime.now().difference(lastUserMsg.first.createdAt).inMinutes;
          if (silenceMinutes < 5) {
            debugPrint(
                'ASE: ${character.name} 用户沉默不足5分钟 ($silenceMinutes min)');
            return false;
          }
        }
      }

      // 阀门3：冷却公式（基于用户设置的互动频率）
      final aiMessages = messages
          .where((m) => m.senderId == 'ai_${character.id}')
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (aiMessages.isNotEmpty) {
        final lastAiMsg = aiMessages.first.createdAt;
        final elapsed = DateTime.now().difference(lastAiMsg).inSeconds;
        // 基础冷却 = 互动频率（小时）× 3600秒，再按紧急度缩短
        // urgency 越高冷却越短，最低为 baseCooldown × 0.15
        final frequencyHours =
            character.interactionConfig?.activeMessageFrequency ?? 2;
        final baseCooldown = frequencyHours * 3600;
        final cooldown = (baseCooldown * (1.0 - urgency * 0.85))
            .toInt()
            .clamp((baseCooldown * 0.15).toInt(), baseCooldown);
        if (elapsed < cooldown) {
          debugPrint(
              'ASE: ${character.name} 冷却中 ($elapsed < $cooldown sec, 频率=${frequencyHours}h)');
          return false;
        }
      }

      // 阀门4：24小时上限15次
      final todayStart = DateTime.now().subtract(const Duration(hours: 24));
      final recentAiMsgs =
          aiMessages.where((m) => m.createdAt.isAfter(todayStart)).length;
      if (recentAiMsgs >= 15) {
        debugPrint('ASE: ${character.name} 24h上限 $recentAiMsgs/15');
        return false;
      }

      // 阀门5：连续未回复上限（3次）
      int consecutive = 0;
      for (final msg in messages.reversed) {
        if (msg.senderId.startsWith('ai_')) {
          consecutive++;
        } else {
          break;
        }
      }
      if (consecutive >= 3) {
        debugPrint('ASE: ${character.name} 连续未回复 $consecutive 次');
        return false;
      }

      debugPrint(
          'ASE: ${character.name} 紧迫度=${urgency.toStringAsFixed(2)} 通过所有阀门 [OK]');
      return true;
    } catch (e) {
      debugPrint('ASE 决策失败: $e');
      return false;
    }
  }

  Future<bool> _checkFrequencyLimit(String chatId, String characterId) async {
    try {
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final todayMessages = await _storage.getChatMessages(chatId);
      final aiTodayMessages = todayMessages
          .where((m) =>
              m.senderId == 'ai_$characterId' &&
              m.createdAt.isAfter(todayStart) &&
              m.senderId.startsWith('ai_'))
          .length;

      if (aiTodayMessages >= ProactiveFrequencyRules.dailyMaxMessages) {
        debugPrint(
            '主动消息已达今日上限: $aiTodayMessages/${ProactiveFrequencyRules.dailyMaxMessages}');
        return false;
      }

      final aiMessages = todayMessages
          .where((m) => m.senderId == 'ai_$characterId')
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (aiMessages.isNotEmpty) {
        final lastMsgTime = aiMessages.first.createdAt;
        final elapsedMinutes = now.difference(lastMsgTime).inMinutes;
        if (elapsedMinutes < ProactiveFrequencyRules.minIntervalMinutes) {
          debugPrint(
              '主动消息间隔不足: ${elapsedMinutes}min < ${ProactiveFrequencyRules.minIntervalMinutes}min');
          return false;
        }
      }

      return true;
    } catch (e) {
      debugPrint('频率检查失败: $e');
      return true;
    }
  }

  Future<String> _buildDecisionPrompt({
    required AICharacter character,
    required ChatSession session,
    required MemoryEngine memoryEngine,
  }) async {
    final now = DateTime.now();
    final timeContext = _getTimeContext(now);
    final recentMessages = await _getRecentMessages(session.id, character.id);
    final recentProactiveMessages =
        await _getRecentProactiveMessages(session.id, character.id);
    final relationshipProfile = await memoryEngine.buildRelationshipProfile(
      character: character,
      userId: session.userId,
    );

    final loverMode = _storage.isLoverModeEnabled();
    final callName = character.userNickname ?? '用户';

    final relationshipLabel = (loverMode && session.intimacyLevel >= 30)
        ? '恋人关系——TA是你的恋人，你称呼TA为"$callName"'
        : (session.intimacyLevel >= 60
            ? '亲密关系——TA是你最重要的人，你称呼TA为"$callName"'
            : '朋友关系');

    // 优先使用进化后的语言风格
    final evolvedStyle =
        _storage.getString('persona_evo_${character.id}_style');
    final effectiveStyle = (evolvedStyle?.isNotEmpty == true)
        ? evolvedStyle
        : character.languageStyle;

    return '''
你是${character.name}。
${character.gender != null && character.gender!.isNotEmpty ? '你的性别：${character.gender}（请严格使用对应性别的第三人称代词，男性用"他"，女性用"她"）' : ''}
你的性格：${character.personality}
${(character.immutableAnchor?.isNotEmpty ?? false) ? '你的不可变身份锚点：${character.immutableAnchor}' : ''}
你的说话风格：${effectiveStyle ?? '自然亲切'}
${character.catchphrases != null ? '你的习惯用语：${character.catchphrases}' : ''}
你对用户的称呼：$callName
${character.backgroundStory != null ? '你的经历：${character.backgroundStory}' : ''}
${character.currentStatus != null ? '你当前的状态：${character.currentStatus}' : ''}

你和用户的关系：$relationshipLabel

$relationshipProfile

【时间】$timeContext
关系亲密度：${session.intimacyLevel}/100

【最近的聊天记录】
${recentMessages.isEmpty ? '（暂无最近的聊天记录）' : recentMessages}

${recentProactiveMessages.isNotEmpty ? '【你之前主动发过的消息（不要重复这些话题）】\n$recentProactiveMessages' : ''}

任务：你现在想不想主动给用户发一条消息？

判断标准：
- 你现在有没有想说的话、想分享的事、想问的问题？
- 你们的关系和最近的聊天有没有值得跟进的话题？
- 你现在的状态和心情适不适合聊天？

如果你有话想说，直接输出你想说的内容（1-2句，像真人发微信一样随意）。
如果你觉得没话可说、或者现在不合适打扰用户，输出：[SILENT]

要求：
- 不要用括号描写动作
- 不要问千篇一律的"在吗""吃了吗""今天怎么样"
- 说有你个人特色的话
- 绝对不要重复你之前主动发过的话题，每次要有新鲜感
- 如果最近已经主动说过类似的话，宁可输出[SILENT]也不要重复
- 只输出消息内容或[SILENT]
''';
  }

  String _getTimeContext(DateTime now) {
    final hour = now.hour;
    if (hour < 6) return '深夜（凌晨${hour}点）';
    if (hour < 9) return '早晨（${hour}点左右）';
    if (hour < 12) return '上午（${hour}点左右）';
    if (hour < 14) return '中午（${hour}点左右）';
    if (hour < 18) return '下午（${hour}点左右）';
    if (hour < 21) return '傍晚（${hour}点左右）';
    return '夜晚（${hour}点左右）';
  }

  Future<String> _getRecentMessages(String chatId, String characterId) async {
    try {
      final allMessages = await _storage.getChatMessages(chatId);
      allMessages.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      final recent = allMessages
          .take(ProactiveFrequencyRules.recentMessagesToInclude)
          .toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

      return recent.map((m) {
        final sender = m.senderId == 'ai_$characterId'
            ? '你'
            : (m.senderId.startsWith('ai_') ? m.senderName : '用户');
        return '$sender: ${m.content}';
      }).join('\n');
    } catch (e) {
      return '';
    }
  }

  /// 获取最近的主动消息（用于去重，避免重复发类似内容）
  Future<String> _getRecentProactiveMessages(
      String chatId, String characterId) async {
    try {
      final allMessages = await _storage.getChatMessages(chatId);
      // 筛选主动消息（metadata中标记了isProactive）
      final proactiveMsgs = allMessages
          .where((m) =>
              m.senderId == 'ai_$characterId' &&
              m.metadata != null &&
              m.metadata!['isProactive'] == true)
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

      // 取最近5条主动消息
      final recent = proactiveMsgs.take(5).toList();
      if (recent.isEmpty) return '';

      return recent.map((m) => '- ${m.content}').join('\n');
    } catch (e) {
      return '';
    }
  }

  String _buildProactivePrompt(
    AICharacter character,
    ProactiveMessageType type,
    int intimacyLevel,
  ) {
    final timeContext = _getTimeContext(DateTime.now());
    // 优先使用进化后的语言风格
    final evolvedStyle =
        _storage.getString('persona_evo_${character.id}_style');
    final effectiveStyle = (evolvedStyle?.isNotEmpty == true)
        ? evolvedStyle
        : character.languageStyle;

    return '''
你是${character.name}。
${character.gender != null && character.gender!.isNotEmpty ? '你的性别：${character.gender}（请严格使用对应性别的第三人称代词，男性用"他"，女性用"她"）' : ''}
你的性格：${character.personality}
${(character.immutableAnchor?.isNotEmpty ?? false) ? '你的不可变身份锚点：${character.immutableAnchor}' : ''}
你的说话风格：${effectiveStyle ?? '自然亲切'}
${character.catchphrases != null ? '你的习惯用语：${character.catchphrases}' : ''}
${character.userNickname != null ? '你对用户的称呼：${character.userNickname}' : ''}
${character.currentStatus != null ? '你当前的状态：${character.currentStatus}' : ''}
${character.backgroundStory != null ? '你的经历：${character.backgroundStory}' : ''}

【当前时间】$timeContext
关系亲密度：$intimacyLevel（0-100）

你现在想主动给用户发一条消息。

要求：
1. 完全以你的性格和当前心情来决定说什么，不要模仿任何固定话术
2. 像真人给朋友发微信——想到什么说什么，可以分享你此刻的状态、心情、或者突然想到的事
3. 你可以聊任何话题：你正在做的事、刚看到的东西、你的心情、你们之间的事、一个突然的念头
4. 不要用括号描写动作或情绪
5. 只输出消息内容，1-2句话
6. 不要问"在吗""吃了吗""今天怎么样"这种千篇一律的问候，说点有你个人特色的话
''';
  }

  Future<String> _callAI(
      AIConfig config, String prompt, AICharacter character) async {
    final baseUrl = config.baseUrl.endsWith('/')
        ? config.baseUrl.substring(0, config.baseUrl.length - 1)
        : config.baseUrl;

    final url = Uri.parse('$baseUrl/chat/completions');

    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${config.apiKey}',
      },
      body: jsonEncode({
        'model': config.modelName,
        'messages': [
          {
            'role': 'system',
            'content': _storage.buildGlobalModePrompt(scope: '主动消息'),
          },
          {'role': 'user', 'content': prompt}
        ],
        if (BuiltInAIProviders.isGlmZ19B(config.id, config.modelName)) ...{
          'temperature': GlmModeParams.proactiveTemperature,
          'top_p': GlmModeParams.topP,
          'top_k': GlmModeParams.proactiveTopK,
          'frequency_penalty': GlmModeParams.proactiveFrequencyPenalty,
          'thinking_budget': GlmModeParams.proactiveThinkingBudget,
          'max_tokens': GlmModeParams.proactiveMaxTokens,
        } else ...{
          'temperature': ApiDefaults.proactiveTemp,
        },
        'max_tokens': _storage.isChatStyleNovelModeEnabled()
            ? config.maxTokens
            : ApiDefaults.proactiveMaxTokens,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      return ResponseDecoder.extractContent(data);
    }

    return '';
  }

  String _cleanResponse(String content) {
    String cleaned = content;
    cleaned = cleaned.replaceAll(RegExp(r'（[^）]*）'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\([^)]*\)'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\*[^*]*\*'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\[[^\]]*\]'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
    return cleaned;
  }

  String _getTodayDateString() {
    final now = DateTime.now();
    return '${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  bool isFestivalToday() {
    final today = _getTodayDateString();
    return Festivals.greetings.containsKey(today);
  }

  String? getTodayFestivalName() {
    final today = _getTodayDateString();
    switch (today) {
      case '01-01':
        return '元旦';
      case '02-14':
        return '情人节';
      case '05-01':
        return '劳动节';
      case '06-01':
        return '儿童节';
      case '10-01':
        return '国庆节';
      case '12-25':
        return '圣诞节';
      default:
        return null;
    }
  }

  Future<void> sendProactiveMessage({
    required AICharacter character,
    required ChatSession session,
    required ProactiveMessageType type,
  }) async {
    try {
      if (session.isBlocked) {
        debugPrint('主动消息发送被阻止（会话已被拉黑）: ${character.name}');
        return;
      }

      final message = await generateProactiveMessage(
        character: character,
        type: type,
        intimacyLevel: session.intimacyLevel,
      );

      if (message == '[SILENT]') {
        debugPrint('主动消息决策为静默: ${character.name}');
        return;
      }

      final chatMessage = ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        chatId: session.id,
        senderId: 'ai_${character.id}',
        senderName: character.name,
        content: message,
        type: MessageType.text,
        status: MessageStatus.sent,
        createdAt: DateTime.now(),
        metadata: const {'isProactive': true},
      );

      await _storage.saveChatMessage(chatMessage);

      final updatedSession = session.copyWith(
        lastMessage: message,
        lastMessageTime: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await _storage.saveChatSession(updatedSession);

      debugPrint('主动消息已发送: ${character.name} - $message');
    } catch (e) {
      debugPrint('发送主动消息失败: $e');
    }
  }

  Future<List<AICharacter>> getCharactersWithMorningGreetingEnabled() async {
    final characters = await _storage.getAllAICharacters();
    return characters
        .where((c) => c.interactionConfig?.enableMorningGreeting ?? true)
        .toList();
  }

  Future<List<AICharacter>> getCharactersWithNightGreetingEnabled() async {
    final characters = await _storage.getAllAICharacters();
    return characters
        .where((c) => c.interactionConfig?.enableNightGreeting ?? true)
        .toList();
  }

  Future<List<AICharacter>> getCharactersWithFestivalGreetingEnabled() async {
    final characters = await _storage.getAllAICharacters();
    return characters
        .where((c) => c.interactionConfig?.enableFestivalGreeting ?? true)
        .toList();
  }

  Future<List<AICharacter>> getCharactersWithMomentInteractionEnabled() async {
    final characters = await _storage.getAllAICharacters();
    return characters
        .where((c) => c.interactionConfig?.enableUserMomentInteraction ?? true)
        .toList();
  }
}
