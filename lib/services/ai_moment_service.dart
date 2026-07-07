import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import '../models/ai_character.dart';
import '../models/ai_config.dart';
import '../models/chat_message.dart';
import '../models/memory.dart';
import '../models/moment.dart';
import '../models/user.dart';
import '../repositories/local_storage_repository.dart';
import '../config/constants.dart';
import '../config/business_rules.dart';
import '../utils/response_decoder.dart';
import 'proactive_scheduler.dart';
import 'ai_service.dart';
import 'persona_evolution_service.dart';

class AIMomentService {
  final LocalStorageRepository _storage;
  final _uuid = const Uuid();
  final _random = Random();

  AIMomentService(this._storage);

  String _effectiveLanguageStyle(AICharacter character) {
    final evolvedStyle =
        _storage.getString('persona_evo_${character.id}_style');
    if (evolvedStyle?.isNotEmpty == true) {
      return evolvedStyle!;
    }
    return character.languageStyle ?? '自然亲切';
  }

  String _immutableAnchorText(AICharacter character) {
    return (character.immutableAnchor?.isNotEmpty ?? false)
        ? character.immutableAnchor!
        : '';
  }

  Duration _getInteractionDelay(AICharacter character) {
    final personality = character.personality.toLowerCase();

    if (personality.contains('活泼') ||
        personality.contains('热情') ||
        personality.contains('开朗')) {
      return Duration(
          seconds: IntimacyRules.bouncyDelayMin +
              _random.nextInt(IntimacyRules.bouncyDelayRange));
    } else if (personality.contains('温柔') ||
        personality.contains('体贴') ||
        personality.contains('细心')) {
      return Duration(
          seconds: IntimacyRules.warmDelayMin +
              _random.nextInt(IntimacyRules.warmDelayRange));
    } else if (personality.contains('高冷') ||
        personality.contains('冷淡') ||
        personality.contains('酷')) {
      return Duration(
          seconds: IntimacyRules.coolDelayMin +
              _random.nextInt(IntimacyRules.coolDelayRange));
    } else if (personality.contains('害羞') || personality.contains('内向')) {
      return Duration(
          seconds: IntimacyRules.shyDelayMin +
              _random.nextInt(IntimacyRules.shyDelayRange));
    }
    return Duration(
        seconds: IntimacyRules.defaultDelayMin +
            _random.nextInt(IntimacyRules.defaultDelayRange));
  }

  Duration _getUserMomentDelay(AICharacter character) {
    final personality = character.personality.toLowerCase();
    if (personality.contains('活泼') ||
        personality.contains('热情') ||
        personality.contains('开朗')) {
      return Duration(
          seconds: IntimacyRules.userMomentBouncyMin +
              _random.nextInt(IntimacyRules.userMomentBouncyRange));
    } else if (personality.contains('温柔') ||
        personality.contains('体贴') ||
        personality.contains('细心')) {
      return Duration(
          seconds: IntimacyRules.userMomentWarmMin +
              _random.nextInt(IntimacyRules.userMomentWarmRange));
    } else if (personality.contains('高冷') ||
        personality.contains('冷淡') ||
        personality.contains('酷')) {
      return Duration(
          seconds: IntimacyRules.userMomentCoolMin +
              _random.nextInt(IntimacyRules.userMomentCoolRange));
    } else if (personality.contains('害羞') || personality.contains('内向')) {
      return Duration(
          seconds: IntimacyRules.userMomentShyMin +
              _random.nextInt(IntimacyRules.userMomentShyRange));
    }
    return Duration(
        seconds: IntimacyRules.userMomentDefaultMin +
            _random.nextInt(IntimacyRules.userMomentDefaultRange));
  }

  double _getInteractionProbability(int intimacyLevel) {
    if (intimacyLevel < IntimacyRules.normalVisibilityThreshold) {
      return 0.7;
    } else if (intimacyLevel < IntimacyRules.intimateVisibilityThreshold) {
      return 0.85;
    } else {
      return 1.0;
    }
  }

  String _getIntimacyTone(int intimacyLevel) {
    if (intimacyLevel >= IntimacyRules.tierVeryHigh) {
      return '非常亲密，可以开玩笑、用亲切的称呼、说温暖的话';
    } else if (intimacyLevel >= IntimacyRules.tierHigh) {
      return '比较亲密，可以关心、调侃、开玩笑';
    } else if (intimacyLevel >= IntimacyRules.normalVisibilityThreshold) {
      return '普通朋友，保持礼貌和友善';
    } else {
      return '不太熟悉，保持客气礼貌';
    }
  }

  bool canAISeeMoment(Moment moment, int intimacyLevel) {
    if (moment.source != MomentSource.normal) return false;
    switch (moment.visibility) {
      case MomentVisibility.public:
        return true;
      case MomentVisibility.private:
        return false;
      case MomentVisibility.intimate:
        return intimacyLevel >= IntimacyRules.intimateVisibilityThreshold;
      case MomentVisibility.normal:
        return intimacyLevel >= IntimacyRules.normalVisibilityThreshold;
    }
  }

  Future<Moment?> generateAIMoment({
    required AICharacter character,
  }) async {
    final config = await _storage.getActiveAIConfig();
    String content;

    final user = await _storage.getCurrentUser();
    final sessions = await _storage.getChatSessionsByCharacterId(character.id);
    final session = sessions.isNotEmpty ? sessions.first : null;

    int intimacyLevel = 0;
    List<ChatMessage> recentMessages = [];
    if (session != null) {
      intimacyLevel = session.intimacyLevel;
      recentMessages = await _storage.getChatMessages(session.id,
          limit: Limit.momentRecentMessages);
    }

    List<Memory> memories = [];
    if (user != null) {
      memories = await _storage.getMemories(
        characterId: character.id,
        userId: user.id,
        limit: Limit.momentRecentMessages,
      );
    }

    if (config != null) {
      try {
        content = await _generateMomentContent(
          config,
          character,
          recentMessages: recentMessages,
          memories: memories,
          intimacyLevel: intimacyLevel,
          user: user,
        );
      } catch (e) {
        debugPrint('生成朋友圈内容失败: $e');
        content = _getDefaultMomentContent(character);
      }
    } else {
      content = _getDefaultMomentContent(character);
    }

    if (content.isEmpty) return null;

    final moment = Moment(
      id: _uuid.v4(),
      userId: character.id,
      userName: character.name,
      userAvatar: character.avatarUrl,
      content: content,
      images: [],
      type: MomentType.text,
      likes: [],
      comments: [],
      createdAt: DateTime.now(),
      isFromAI: true,
      source: MomentSource.normal,
    );

    await _storage.saveMoment(moment);
    return moment;
  }

  String _getIntimacyDescription(int level, String callName) {
    if (level >= 80) {
      return '你和$callName关系非常深厚，是彼此最重要的人。发朋友圈时可以自然地分享亲密日常，语气温暖深情。';
    } else if (level >= 60) {
      return '你和$callName关系很亲密，彼此很了解。发朋友圈时可以用温暖亲昵的语气，像对好朋友说话一样。';
    } else if (level >= 30) {
      return '你和$callName关系不错，比较信任彼此。发朋友圈时保持友好自然的语气。';
    } else {
      return '你和$callName刚认识不久。发朋友圈时保持礼貌自然的语气。';
    }
  }

  Future<String> _generateMomentContent(
    AIConfig config,
    AICharacter character, {
    List<ChatMessage> recentMessages = const [],
    List<Memory> memories = const [],
    int intimacyLevel = 0,
    User? user,
  }) async {
    final baseUrl = config.baseUrl.endsWith('/')
        ? config.baseUrl.substring(0, config.baseUrl.length - 1)
        : config.baseUrl;

    final url = Uri.parse('$baseUrl/chat/completions');
    final userName = user?.nickname ?? '用户';
    final callName = character.userNickname ?? userName;

    final buffer = StringBuffer();

    // 读取恋人模式
    final loverMode = _storage.isLoverModeEnabled();

    // 明确关系定义 — 防止关系认知错位
    if (loverMode && intimacyLevel >= 30) {
      buffer.writeln('你是${character.name}，$userName是你的恋人。现在你要发一条朋友圈。');
    } else if (intimacyLevel >= 60) {
      buffer.writeln('你是${character.name}，$userName是你最重要的人。现在你要发一条朋友圈。');
    } else {
      buffer.writeln('你是${character.name}，$userName是你熟悉的朋友。现在你要发一条朋友圈。');
    }
    buffer.writeln('');

    buffer.writeln('【你的身份信息】');
    buffer.writeln('名字：${character.name}');
    if (character.gender != null && character.gender!.isNotEmpty) {
      buffer.writeln('性别：${character.gender}');
    }
    buffer.writeln('性格：${character.personality}');
    buffer.writeln('心愿：${character.coreDesire}');
    if (_immutableAnchorText(character).isNotEmpty) {
      buffer.writeln('不可变身份锚点：${_immutableAnchorText(character)}');
    }
    buffer.writeln(
        '当前状态：${character.isOnline ? "在线（清醒的，正常活动）" : "离线（在休息/睡觉/忙碌中，不活跃）"}');
    if ((character.backgroundStory?.isNotEmpty) == true) {
      buffer.writeln('你的故事：${character.backgroundStory}');
    }
    if ((character.worldSetting?.isNotEmpty) == true) {
      buffer.writeln('你的世界观：${character.worldSetting}');
    }
    final effectiveStyle = _effectiveLanguageStyle(character);
    if (effectiveStyle.isNotEmpty) {
      buffer.writeln('你的说话风格：$effectiveStyle');
    }
    if ((character.catchphrases?.isNotEmpty) == true) {
      buffer.writeln('你的习惯用语：${character.catchphrases}');
    }
    buffer.writeln('你对$userName的称呼：$callName');
    if (character.dialogueExamples.isNotEmpty) {
      buffer.writeln('你的说话方式示例：');
      for (final ex
          in character.dialogueExamples.take(Limit.momentDialogueExamples)) {
        buffer.writeln('  $userName：${ex.userMessage}');
        buffer.writeln('  你：${ex.aiResponse}');
      }
    }

    buffer.writeln('');
    buffer.writeln('【你和$userName的关系 - 必须遵守，不可遗忘】');
    buffer.writeln('亲密度等级：$intimacyLevel/100');
    if (loverMode && intimacyLevel >= 30) {
      buffer.writeln('$userName是你的恋人，你称呼TA为"$callName"。你们是情侣关系。');
    } else if (intimacyLevel >= 60) {
      buffer.writeln('$userName是你最重要的人，你称呼TA为"$callName"。你们关系非常亲密。');
    }
    buffer.writeln(_getIntimacyDescription(intimacyLevel, callName));
    buffer.writeln('[重要] 以上关系是你的核心记忆，发朋友圈时绝对不能忘记或违背这些关系设定。');

    if (recentMessages.isNotEmpty) {
      buffer.writeln('');
      buffer.writeln('【你和$userName最近的聊天】');
      final contextMessages = recentMessages.length > 6
          ? recentMessages
              .sublist(recentMessages.length - Limit.momentContextMessages)
          : recentMessages;
      for (final msg in contextMessages) {
        final sender = msg.isFromAI ? character.name : userName;
        buffer.writeln('$sender：${msg.content}');
      }
    }

    if (memories.isNotEmpty) {
      buffer.writeln('');
      buffer.writeln('【你记得关于$userName的事情】');
      for (final memory in memories.take(Limit.momentMemoriesPrompt)) {
        buffer.writeln('- ${memory.content}');
      }
    }

    String topic;
    if (recentMessages.isNotEmpty) {
      topic = '结合你们最近聊过的话题，分享你当下的真实感受或相关的生活片段';
    } else {
      final topics = [
        '分享你最近的一个小感悟或心情',
        '分享你今天做的一件事',
        '分享你看到或听到的有趣事物',
        '分享你此刻的心情',
      ];
      topic = topics[_random.nextInt(topics.length)];
    }

    buffer.writeln('');
    buffer.writeln('【发圈要求】');
    buffer.writeln('现在请你以${character.name}的身份，发一条高质量的朋友圈。');
    buffer.writeln('$topic');
    buffer.writeln('');
    buffer.writeln('要求：');
    buffer.writeln('1. 内容必须符合你的性格、背景故事和说话风格，不要偏离人设');
    buffer.writeln('2. 紧扣你和$userName的聊天内容或你记得的事情来分享，不要说无关的话');
    buffer.writeln('3. 绝对不能把$userName当作陌生人或新朋友——你们的关系已在上方明确定义');
    buffer.writeln('4. 像真人发朋友圈一样自然，有生活气息，不要像在写作文');
    buffer.writeln('5. 内容要简短（1-3句话）');
    buffer.writeln('6. 可以用语气词（如呀、呢、啦、～）增加真实感');
    buffer.writeln('7. 避免说教或太正式的表达');
    buffer.writeln('8. 根据亲密度（$intimacyLevel/100）调整语气，越亲密越自然亲切');
    buffer.writeln('9. 不要用括号描写动作或情绪，如：（开心）、（微笑）');
    buffer.writeln('');
    buffer.writeln('【输出格式 - 必须严格遵守】');
    buffer.writeln('你必须使用以下结构化格式输出：');
    buffer.writeln('<THINK>');
    buffer.writeln('（可选：你可以在这里简短思考要发什么，这段不会被发布）');
    buffer.writeln('</THINK>');
    buffer.writeln('<MOMENT>');
    buffer.writeln('1-3 句话的朋友圈正文，直接发布的内容');
    buffer.writeln('</MOMENT>');
    buffer.writeln('');
    buffer.writeln('铁律：');
    buffer.writeln('- 最终发布的内容必须包裹在 <MOMENT> 和 </MOMENT> 之间');
    buffer.writeln('- <THINK> 标签内的内容只是你的内部思考，不会展示给用户');
    buffer.writeln('- <MOMENT> 内只包含朋友圈文案本身，不要有任何分析、说明、前缀、Markdown');
    buffer.writeln('- 不要输出 <MOMENT> 和 </MOMENT> 标签本身以外的任何文字');

    final prompt = buffer.toString();

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
            'content': '${_storage.buildGlobalModePrompt(scope: 'AI动态/朋友圈')}\n'
                '【终极发圈约束：隔离思考过程，只输出文案本身】\n'
                '1. 你必须直接以「${character.name}」的身份，直接输出最终要发布的 1-3 句话的朋友圈正文（文案本身）。\n'
                '2. 【铁律】绝对禁止输出任何形式的内部推理、分析、生成思路、人设剖析或角色扮演的心路历程。\n'
                '3. 绝对禁止以“我要根据...”、“我得先想想...”、“用户让我以...身份...”、“首先”、“接下来”、“我会”等开头或在此类句子中进行分析。\n'
                '4. 绝对不要输出任何说明性的文字，也不要包含任何备注、前缀（如“朋友圈动态：”）、后缀或Markdown标记。\n'
                '5. 直接输出符合角色口气、日常口语、语气词、懒散/痞气或人设语气的日常朋友圈动态文案。像真人随手发的一样。',
          },
          {'role': 'user', 'content': prompt}
        ],
        if (BuiltInAIProviders.isGlmZ19B(config.id, config.modelName)) ...{
          'temperature': GlmModeParams.momentTemperature,
          'top_p': GlmModeParams.topP,
          'top_k': GlmModeParams.momentTopK,
          'frequency_penalty': GlmModeParams.momentFrequencyPenalty,
          'thinking_budget': GlmModeParams.momentThinkingBudget,
          'max_tokens': GlmModeParams.momentMaxTokens,
        } else ...{
          'temperature': 0.9,
        },
        'max_tokens': config.maxTokens,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      return extractFinalMomentContent(
          ResponseDecoder.extractVisibleContent(data));
    }

    return '';
  }

  /// 从原始 AI 回复中提取最终朋友圈正文，隔离思考过程。
  ///
  /// 支持两种模式：
  /// 1. 模型严格遵守结构化格式，输出 `<MOMENT>...</MOMENT>`，直接取值。
  /// 2. 模型未按格式输出，采用黑名单清理兜底。
  static String extractFinalMomentContent(String content) {
    if (content.trim().isEmpty) return '';

    var cleaned = content.trim();

    // 1. 优先提取 <MOMENT> 标签内的内容（结构化输出）
    final momentMatch = RegExp(
      r'<\s*MOMENT\s*>([\s\S]*?)<\s*/\s*MOMENT\s*>',
      caseSensitive: false,
    ).firstMatch(cleaned);
    if (momentMatch != null) {
      final inner = momentMatch.group(1)?.trim() ?? '';
      // 如果 <MOMENT> 内有内容，直接返回（再执行基础清理）
      cleaned = inner;
    }

    // 2. 移除 <THINK> 思考标签
    cleaned = cleaned.replaceAll(
      RegExp(r'<\s*THINK\s*>[\s\S]*?<\s*/\s*THINK\s*>', caseSensitive: false),
      '',
    );

    // 3. 移除其他思考/推理标签
    cleaned = cleaned.replaceAll(
      RegExp(
          r'<\s*(?:think|thinking|reasoning|analysis|reflection)\s*>[\s\S]*?<\s*/\s*(?:think|thinking|reasoning|analysis|reflection)\s*>',
          caseSensitive: false),
      '',
    );

    return _baseCleanContent(cleaned);
  }

  /// 基础清理：移除 Markdown、括号动作、常见元分析句等。
  ///
  /// 对未按 `<MOMENT>` 格式输出的模型，采用“句子级”过滤：只剔除包含 meta
  /// 思考的句子，而不是把整行（含正常文案）一起丢弃，避免错杀正文。
  static String _baseCleanContent(String content) {
    String cleaned = content;

    // 1. 移除括号内的动作/情绪描写
    cleaned = cleaned.replaceAll(RegExp(r'（[^）]*）'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\([^)]*\)'), '');

    // 2. 移除 Markdown 格式
    cleaned = cleaned.replaceAll(RegExp(r'\*[^*]*\*'), '');
    cleaned = cleaned.replaceAll(RegExp(r'#{1,6}\s*'), '');
    cleaned = cleaned.replaceAll(RegExp(r'---+'), '');
    cleaned = cleaned.replaceAll(RegExp(r'```[\s\S]*?```'), '');

    // 3. 移除方括号标题
    cleaned = cleaned.replaceAll(RegExp(r'【[^】]*】'), '');

    // 4. 按句子过滤思考/元分析内容，而不是整行丢弃
    final thinkingPrefixes = [
      '我来分析',
      '首先分析',
      '根据设定',
      '作为AI',
      '作为ai',
      '以下是',
      '我得先',
      '用户让我',
      '我需要',
      '我应该',
      '先分析',
      '我要根据',
      '嗯，用户',
      '想了想',
      '我思考一下',
      '让我想想',
      '让我思考一下',
    ];
    final thinkingKeywords = [
      '用户需要',
      '分析用户',
      '先分析',
      '需要先分析',
      '身份设定',
      '角色人设',
      '风格要求',
      '输出规则',
      '根据要求',
      '作为AI',
      '作为一个',
      '让我想想',
      '让我思考',
      '让我来',
      '分析一下',
      '思考过程',
      '以下是我',
      '以下是你',
      '这是我的',
    ];
    final metaAnalysisKeywords = [
      '亲密度',
      '调整语气',
      '刚认识',
      '太生疏',
      '太亲密',
      '显得太刻意',
      '我得先',
      '是个什么样的人',
      '表面上',
      '实际上',
      '界限很清',
      '以某角色',
      '发一条朋友圈',
      '角色分析',
      '场景设定',
      '状态推测',
      '内部思考',
      '用户让我',
      '符合人设',
      '人设分析',
      '生成思路',
      '生成一条',
      '生成评论',
      '用户要求',
      '动态正文',
      '发点关于',
      '既真实又',
      '显得太',
      '扮演的是',
      '沉浸在',
      '只输出',
      '绝对禁止',
      '直接输出',
    ];

    final sentenceDelimiter = RegExp(r'(?<=[。！？．.!?;；\n])\s*');
    final sentences = cleaned
        .split(sentenceDelimiter)
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty);

    final kept = <String>[];
    for (final sentence in sentences) {
      final lower = sentence.toLowerCase();
      if (thinkingPrefixes.any((p) => lower.startsWith(p))) continue;
      if (thinkingKeywords.any((k) => lower.contains(k))) continue;
      if (metaAnalysisKeywords.any((k) => lower.contains(k))) continue;
      kept.add(sentence);
    }

    cleaned = kept.join();

    // 5. 压缩空白
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();

    // 6. 如果结果为空或太短，返回空（触发兜底）
    if (cleaned.length < 5) return '';

    return cleaned;
  }

  /// 清理 AI 输出，移除思考过程、身份泄露等无关内容
  ///
  /// 朋友圈主生成路径已改用 [extractFinalMomentContent] 进行结构化提取；
  /// 本方法保留用于评论/回复等其他路径的兜底清理。
  String _cleanContent(String content) {
    return extractFinalMomentContent(content);
  }

  String _getDefaultMomentContent(AICharacter character) {
    final personality = character.personality.toLowerCase();

    List<String> templates;

    if (personality.contains('活泼') || personality.contains('热情')) {
      templates = [
        '今天遇到一件超有趣的事，笑死我了哈哈哈',
        '刚吃完好吃的，心情瞬间变好！',
        '今天天气太棒了，忍不住想出门逛逛～',
        '突然好想吃火锅，有没有人一起呀？',
        '今天做了件一直想做的事，成就感满满！',
        '分享一首今天单曲循环的歌，太好听了',
      ];
    } else if (personality.contains('温柔') || personality.contains('体贴')) {
      templates = [
        '今天阳光很好，心情也跟着温柔起来',
        '刚看完一本书，心里暖暖的',
        '有时候觉得，平淡的日子也挺美好的',
        '今天给朋友做了点小事，看到TA开心我也开心',
        '泡了一杯热茶，安安静静地坐着，很舒服',
        '收到了一句暖心的话，一整天心情都很好',
      ];
    } else if (personality.contains('幽默') || personality.contains('损')) {
      templates = [
        '今天又被自己帅醒了，真烦',
        '刚称了一下体重，算了不说也罢',
        '今天努力了一把，结果…还是躺平舒服',
        '突然发现，我除了可爱也没什么缺点了',
      ];
    } else if (personality.contains('高冷') || personality.contains('冷淡')) {
      templates = [
        '今天，还行。',
        '有些事，不说也罢。',
        '沉默有时候是最好的回答。',
        '嗯，今天就这样。',
        '一个人，一杯咖啡，挺好。',
      ];
    } else {
      templates = [
        '刚看完一部电影，感触很深...',
        '今天学到了一个新东西，感觉收获满满！',
        '有时候，安静地发呆也是一种享受。',
        '忙碌了一天，终于可以放松一下了',
        '今天遇到了一个有趣的人',
        '刚喝了一杯好喝的咖啡，推荐给大家',
        '生活嘛，慢慢来，比较快',
        '今天想通了一些事，感觉豁然开朗',
      ];
    }

    return templates[_random.nextInt(templates.length)];
  }

  Future<String> generateCommentForMoment({
    required Moment moment,
    required AICharacter character,
    int intimacyLevel = 50,
  }) async {
    final config = await _storage.getActiveAIConfig();

    if (config != null) {
      try {
        final raw = await _generateCommentContent(
            config, moment, character, intimacyLevel);
        return AIService.filterHallucinatedNames(raw, character.userNickname);
      } catch (e) {
        debugPrint('生成评论失败: $e');
        return _getDefaultComment(moment, character, intimacyLevel);
      }
    }

    return _getDefaultComment(moment, character, intimacyLevel);
  }

  Future<String> _generateCommentContent(
    AIConfig config,
    Moment moment,
    AICharacter character,
    int intimacyLevel,
  ) async {
    final baseUrl = config.baseUrl.endsWith('/')
        ? config.baseUrl.substring(0, config.baseUrl.length - 1)
        : config.baseUrl;

    final url = Uri.parse('$baseUrl/chat/completions');

    final nickname = character.userNickname ?? '你';
    final intimacyTone = _getIntimacyTone(intimacyLevel);

    const imageDescription = '';

    final prompt = '''
你是${character.name}，正在看${nickname}发的朋友圈。

【你的身份】
- 名字：${character.name}
- 性格：${character.personality}
- 不可变身份锚点：${(character.immutableAnchor?.isNotEmpty ?? false) ? character.immutableAnchor : '无'}
- 当前人格状态：${PersonaEvolutionService.buildTraitSummaryFromAnchor(character.currentAnchor)}
- 说话风格：${_effectiveLanguageStyle(character)}
- 习惯用语：${character.catchphrases ?? '无'}
- 当前状态：${character.isOnline ? "在线（清醒的，正常活动）" : "离线（在休息/睡觉/忙碌中，不活跃）"}
- 你对${nickname}的称呼：$nickname
- 你们的关系亲密度：$intimacyTone

【${nickname}发的朋友圈】
"${moment.content}"
$imageDescription
【你的任务】
作为${nickname}的好友，给这条朋友圈写一条真诚的评论。

【评论要求】
1. 必须针对${nickname}朋友圈的具体内容来评论，不要说无关的话
2. 如果${nickname}发了图片，要针对图片内容评论（比如颜色、场景、氛围、细节等）
3. 用你的性格和说话风格，像真人一样自然
4. 根据${nickname}朋友圈内容捕捉TA的情绪，给予情感共鸣
5. 如果${nickname}分享开心的事，你要为TA高兴
6. 如果${nickname}分享难过的事，你要安慰TA
7. 如果${nickname}分享日常，你要有共鸣或好奇
8. 可以用"$nickname"来称呼TA，显得亲切
9. 评论要简短（1-2句话），像微信评论一样
10. 可以用感叹词、语气词（如呀、呢、啦、～）增加真实感
11. 绝对不要用括号描写动作，如（微笑）、（点头）等

【输出格式 - 必须严格遵守】
直接输出评论正文，不要包含：
- 思考过程、分析、推理
- "首先""然后""我需要"等思维词
- 重复身份设定或要求
- Markdown 格式、列表、分隔线
- 任何解释、备注、前后缀
只输出 1-2 句话的评论，立即开始：
''';

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
            'content': _storage.buildGlobalModePrompt(scope: 'AI动态评论'),
          },
          {'role': 'user', 'content': prompt}
        ],
        if (BuiltInAIProviders.isGlmZ19B(config.id, config.modelName)) ...{
          'temperature': GlmModeParams.momentTemperature,
          'top_p': GlmModeParams.topP,
          'top_k': GlmModeParams.momentTopK,
          'frequency_penalty': GlmModeParams.momentFrequencyPenalty,
          'thinking_budget': GlmModeParams.momentThinkingBudget,
          'max_tokens': GlmModeParams.momentMaxTokens,
        } else ...{
          'temperature': 0.85,
        },
        'max_tokens': config.maxTokens,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      return _cleanContent(ResponseDecoder.extractVisibleContent(data));
    }

    return '';
  }

  String _getDefaultComment(
      Moment moment, AICharacter character, int intimacyLevel) {
    final nickname = character.userNickname ?? '你';
    final content = moment.content;

    String prefix = '';
    String suffix = '';

    if (intimacyLevel >= 80) {
      prefix = '朋友';
      suffix = '～';
    } else if (intimacyLevel >= 60) {
      prefix = '';
      suffix = '～';
    } else {
      prefix = '';
      suffix = '。';
    }

    if (content.contains('累') ||
        content.contains('辛苦') ||
        content.contains('疲惫')) {
      return '${prefix.isNotEmpty ? prefix + nickname : nickname}辛苦啦，好好休息一下$suffix';
    } else if (content.contains('开心') ||
        content.contains('高兴') ||
        content.contains('哈哈')) {
      return '看来今天心情不错呀，${prefix.isNotEmpty ? prefix : ''}$nickname$suffix';
    } else if (content.contains('难过') ||
        content.contains('伤心') ||
        content.contains('不开心')) {
      return '$nickname怎么了？愿意跟我说说吗$suffix';
    } else if (content.contains('吃') ||
        content.contains('美食') ||
        content.contains('饭')) {
      return '看起来很好吃的样子！$nickname真会享受生活$suffix';
    } else if (content.contains('玩') ||
        content.contains('旅游') ||
        content.contains('出去')) {
      return '$nickname玩得开心吗？下次带我一起呀$suffix';
    } else {
      final comments = [
        '$nickname分享的真好$suffix',
        '支持$nickname！',
        '$nickname说得有道理$suffix',
        '同感，$nickname$suffix',
      ];
      final index = _random.nextInt(comments.length);
      return comments[index];
    }
  }

  Future<void> aiInteractWithUserMoment({
    required Moment moment,
    required AICharacter character,
    int intimacyLevel = 50,
    bool forceComment = false,
  }) async {
    if (moment.source != MomentSource.normal) return;
    if (moment.isFromAI) return;
    if (!character.isOnline) {
      debugPrint('AI ${character.name} 离线，跳过朋友圈互动');
      return;
    }

    final interactionProb = _getInteractionProbability(intimacyLevel);
    final shouldInteract =
        forceComment || _random.nextDouble() < interactionProb;

    if (!shouldInteract) {
      debugPrint('AI ${character.name} 此次不互动朋友圈（亲密度概率：$interactionProb）');
      return;
    }

    final shouldLike = _random.nextDouble() < MomentRules.aiLikeProbability;
    final shouldComment =
        forceComment || _random.nextDouble() < MomentRules.aiCommentProbability;

    if (!forceComment && (shouldLike || shouldComment)) {
      final delay = _getUserMomentDelay(character);
      debugPrint('AI ${character.name} 将在 ${delay.inSeconds} 秒后互动朋友圈');
      await Future.delayed(delay);
    }

    // 从 DB 重新获取最新数据，避免多 AI 并行时覆写彼此的互动
    List<Moment>? allMoments;
    try {
      allMoments = await _storage.getAllMoments();
    } catch (e) {
      debugPrint('AI ${character.name} 互动失败：获取朋友圈异常 $e');
      return;
    }
    final freshMoment = allMoments.where((m) => m.id == moment.id).firstOrNull;
    if (freshMoment == null) {
      debugPrint('AI ${character.name} 互动失败：朋友圈已不存在');
      return;
    }

    List<MomentLike> newLikes = List.from(freshMoment.likes);
    List<MomentComment> newComments = List.from(freshMoment.comments);

    if (shouldLike) {
      final existingLike = newLikes.any((l) => l.userId == character.id);
      if (!existingLike) {
        newLikes.add(MomentLike(
          userId: character.id,
          userName: character.name,
          createdAt: DateTime.now(),
        ));
      }
    }

    if (shouldComment) {
      final existingComment = newComments.any((c) => c.userId == character.id);
      if (!existingComment) {
        final commentContent = await generateCommentForMoment(
          moment: freshMoment,
          character: character,
          intimacyLevel: intimacyLevel,
        );

        if (commentContent.isNotEmpty) {
          newComments.add(MomentComment(
            id: _uuid.v4(),
            userId: character.id,
            userName: character.name,
            content: commentContent,
            createdAt: DateTime.now(),
          ));
        }
      }
    }

    if (shouldLike || shouldComment) {
      final updatedMoment = freshMoment.copyWith(
        likes: newLikes,
        comments: newComments,
      );
      await _storage.saveMoment(updatedMoment);
      debugPrint(
          'AI ${character.name} 已互动朋友圈: ${shouldLike ? "点赞" : ""} ${shouldComment ? "评论" : ""}');
    }
  }

  Future<void> scheduleAIMomentsForAllCharacters() async {
    final characters = await _storage.getAllAICharacters();
    final now = DateTime.now();

    for (final character in characters) {
      if (!character.isOnline) {
        debugPrint('AI ${character.name} 离线，跳过朋友圈');
        continue;
      }
      if (!(character.interactionConfig?.enableUserMomentInteraction ?? true))
        continue;

      // 获取该角色最近的 AI 动态
      final allMoments = await _storage.getAllMoments();
      final characterMoments = allMoments
          .where((m) => m.isFromAI && m.userId == character.id)
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

      final lastPost =
          characterMoments.isNotEmpty ? characterMoments.first.createdAt : null;
      final hoursSinceLastPost = lastPost != null
          ? now.difference(lastPost).inHours.toDouble()
          : 999.0;

      // 最小间隔检查
      if (hoursSinceLastPost < MomentSchedulerRules.minHoursBetweenPosts)
        continue;

      // 今日上限检查
      final todayStart = DateTime(now.year, now.month, now.day);
      final todayCount =
          characterMoments.where((m) => m.createdAt.isAfter(todayStart)).length;
      if (todayCount >= MomentSchedulerRules.maxDailyPostsPerCharacter)
        continue;

      // 概率随时间递增
      final probability =
          (hoursSinceLastPost / MomentSchedulerRules.maxHoursBetweenPosts)
              .clamp(0.0, 1.0);
      if (_random.nextDouble() > probability) continue;

      await generateAIMoment(character: character);
      debugPrint('AI ${character.name} 发布了朋友圈（前台触发）');
    }
  }

  Future<List<AICharacter>> getCharactersWithMomentInteractionEnabled() async {
    final characters = await _storage.getAllAICharacters();
    return characters
        .where((c) => c.interactionConfig?.enableUserMomentInteraction ?? true)
        .toList();
  }

  /// 调度 AI 延迟回复用户评论（通过 WorkManager 后台任务）
  Future<void> scheduleAICommentReply({
    required Moment moment,
    required MomentComment userComment,
    required AICharacter character,
    required int intimacyLevel,
  }) async {
    if (moment.source != MomentSource.normal) return;
    final delay = _getInteractionDelay(character);
    final scheduler = ProactiveScheduler(_storage);
    await scheduler.scheduleCommentReply(
      momentId: moment.id,
      commentId: userComment.id,
      characterId: character.id,
      intimacyLevel: intimacyLevel,
      delay: delay,
    );
    debugPrint('已调度 AI ${character.name} 延迟回复评论 (${delay.inSeconds}s 后)');
  }

  /// 普通动态前台兜底：AI 立即回复用户在 AI 动态下的评论。
  Future<bool> replyToUserCommentNow({
    required Moment moment,
    required MomentComment userComment,
    required AICharacter character,
    required int intimacyLevel,
  }) async {
    if (moment.source != MomentSource.normal) return false;
    if (!moment.isFromAI || moment.userId != character.id) return false;
    if (!character.isOnline) return false;

    final allMoments = await _storage.getAllMoments();
    final freshMoment = allMoments.where((m) => m.id == moment.id).firstOrNull;
    if (freshMoment == null) return false;

    final alreadyReplied = freshMoment.comments.any(
      (comment) =>
          comment.userId == character.id &&
          comment.replyToUserId == userComment.userId &&
          comment.replyToUserName == userComment.userName,
    );
    if (alreadyReplied) return true;

    final replyContent = await generateReplyForComment(
      moment: freshMoment,
      userComment: userComment,
      character: character,
      intimacyLevel: intimacyLevel,
    );
    if (replyContent.trim().isEmpty) return false;

    final reply = MomentComment(
      id: _uuid.v4(),
      userId: character.id,
      userName: character.name,
      replyToUserId: userComment.userId,
      replyToUserName: userComment.userName,
      content: replyContent.trim(),
      createdAt: DateTime.now(),
    );

    await _storage.saveMoment(
      freshMoment.copyWith(comments: [...freshMoment.comments, reply]),
    );
    return true;
  }

  Future<String> generateReplyForComment({
    required Moment moment,
    required MomentComment userComment,
    required AICharacter character,
    required int intimacyLevel,
  }) async {
    final config = await _storage.getActiveAIConfig();
    if (config == null) {
      return _getDefaultCommentReply(userComment, character, intimacyLevel);
    }

    final nickname = character.userNickname ?? userComment.userName;
    final prompt = '''
你是${character.name}，看到了$nickname在你的动态下评论。

【你的身份】
- 名字：${character.name}
- 性格：${character.personality}
- 不可变身份锚点：${_immutableAnchorText(character).isNotEmpty ? _immutableAnchorText(character) : '无'}
- 说话风格：${_effectiveLanguageStyle(character)}
- 习惯用语：${character.catchphrases ?? '无'}
- 你对$nickname的称呼：$nickname
- 你们的关系亲密度：${_getIntimacyTone(intimacyLevel)}

【你的动态】
"${moment.content}"

【$nickname 的评论】
"${userComment.content}"

请以${character.name}的身份回复这条评论。
要求：
1. 要针对评论内容回复，不要泛泛而谈
2. 语气符合你的人设和关系亲密度
3. 简短自然，1-2句话
4. 不要用括号描写动作或情绪

【输出格式】直接输出回复，不要思考过程、不要重复身份设定、不要 Markdown，立即开始：
''';

    try {
      final raw = await _callMomentApi(
        config: config,
        prompt: prompt,
        temperature: 0.85,
        maxTokens:
            _storage.isChatStyleNovelModeEnabled() ? config.maxTokens : 80,
      );
      final cleaned = _cleanContent(raw);
      if (cleaned.isEmpty) {
        return _getDefaultCommentReply(userComment, character, intimacyLevel);
      }
      return AIService.filterHallucinatedNames(cleaned, character.userNickname);
    } catch (e) {
      debugPrint('生成评论回复失败: $e');
      return _getDefaultCommentReply(userComment, character, intimacyLevel);
    }
  }

  String _getDefaultCommentReply(
    MomentComment userComment,
    AICharacter character,
    int intimacyLevel,
  ) {
    final nickname = character.userNickname ?? userComment.userName;
    if (userComment.content.contains('喜欢') ||
        userComment.content.contains('好看')) {
      return '你喜欢就好，$nickname～';
    }
    if (userComment.content.contains('哈哈') ||
        userComment.content.contains('笑')) {
      return '看到你笑我也开心了，$nickname。';
    }
    if (userComment.content.contains('为什么') ||
        userComment.content.contains('怎么')) {
      return '其实就是刚好想到这件事，想发出来给你看看。';
    }
    return intimacyLevel >= 60 ? '被你看到啦，$nickname～' : '谢谢你的评论，$nickname。';
  }

  Future<String> _callMomentApi({
    required AIConfig config,
    required String prompt,
    required double temperature,
    required int maxTokens,
  }) async {
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
            'content': _storage.buildGlobalModePrompt(scope: 'AI动态评论'),
          },
          {'role': 'user', 'content': prompt}
        ],
        if (BuiltInAIProviders.isGlmZ19B(config.id, config.modelName)) ...{
          'temperature': GlmModeParams.momentTemperature,
          'top_p': GlmModeParams.topP,
          'top_k': GlmModeParams.momentTopK,
          'frequency_penalty': GlmModeParams.momentFrequencyPenalty,
          'thinking_budget': GlmModeParams.momentThinkingBudget,
          'max_tokens': GlmModeParams.momentMaxTokens,
        } else ...{
          'temperature': temperature,
        },
        'max_tokens': maxTokens,
      }),
    );

    if (response.statusCode != 200) return '';
    final data = jsonDecode(utf8.decode(response.bodyBytes));
    return ResponseDecoder.extractVisibleContent(data);
  }
}
