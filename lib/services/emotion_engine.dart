import 'package:flutter/foundation.dart';
import '../models/character_emotion.dart';
import '../models/ai_character.dart';
import '../models/memory.dart';
import '../repositories/local_storage_repository.dart';
import '../utils/sentiment_analyzer.dart';
import '../config/constants.dart';
import '../config/business_rules.dart';

/// 情感引擎 — 让 AI 拥有自己的情绪
///
/// 核心理念：
/// - AI 不应该永远"服务式"回应，它有自己的感受
/// - 用户的言行会影响 AI 的情绪（被冷落会难过，被夸奖会开心）
/// - 情绪会自然衰减，不会永远停留在某个状态
/// - 情绪影响 AI 的回复风格（开心时话多，难过时简短）
class EmotionEngine {
  final LocalStorageRepository _storage;

  /// 内存缓存：{(characterId_userId): CharacterEmotion}
  final Map<String, CharacterEmotion> _cache = {};

  EmotionEngine(this._storage);

  String _cacheKey(String characterId, String userId) =>
      '$characterId\_$userId';

  /// 获取角色当前情绪
  ///
  /// v2 修复：长时间离线不再重置情绪为默认值。
  /// 离散情绪会衰减到 calm，但 valence/arousal 通过时间回拉缓慢趋近基线，
  /// 而非瞬间归零。这保留了"情绪记忆"——离线越久越平静，但不会突然忘记之前发生了什么。
  Future<CharacterEmotion> getCurrentEmotion({
    required AICharacter character,
    required String userId,
  }) async {
    final key = _cacheKey(character.id, userId);

    // 先查缓存
    if (_cache.containsKey(key)) {
      final cached = _cache[key]!;
      // v2: 即使 hasDecayed，也返回缓存（valence/arousal 通过 getter 自动回拉）
      // 只在完全"冷却"（超过72小时）时才考虑重置
      final hoursSinceUpdate =
          DateTime.now().difference(cached.updatedAt).inHours;
      if (hoursSinceUpdate < 72) return cached;
    }

    // 从持久化存储加载
    try {
      final saved = await _loadFromStorage(character.id, userId);
      if (saved != null) {
        final hoursSinceUpdate =
            DateTime.now().difference(saved.updatedAt).inHours;
        if (hoursSinceUpdate < 72) {
          _cache[key] = saved;
          return saved;
        }
        // 超过72小时：离散情绪→calm，但保留 valence/arousal（通过 getter 自动回拉）
        final softened = saved.copyWith(
          primaryEmotion: EmotionType.calm,
          intensity: 0.0,
        );
        _cache[key] = softened;
        return softened;
      }
    } catch (e) {
      debugPrint('Error: $e');
    }

    // 默认情绪：平静（仅首次使用时）
    final defaultEmotion = CharacterEmotion(
      characterId: character.id,
      userId: userId,
      primaryEmotion: EmotionType.calm,
      intensity: 0.0,
      updatedAt: DateTime.now(),
    );
    _cache[key] = defaultEmotion;
    return defaultEmotion;
  }

  /// 根据对话更新角色的情绪
  ///
  /// 在每次收到用户消息后调用，返回更新后的情绪
  Future<CharacterEmotion> updateEmotion({
    required AICharacter character,
    required String userId,
    required String userMessage,
    required SentimentResult userSentiment,
    required int intimacyLevel,
  }) async {
    final current =
        await getCurrentEmotion(character: character, userId: userId);

    // 1. 分析用户消息对角色情绪的影响
    final emotionChange = _analyzeEmotionImpact(
      userMessage: userMessage,
      userSentiment: userSentiment,
      currentEmotion: current,
      intimacyLevel: intimacyLevel,
      characterPersonality: character.personality,
    );

    // 2. 计算新情绪
    final newEmotion = _applyEmotionChange(current, emotionChange);

    // 3. 保存
    _cache[_cacheKey(character.id, userId)] = newEmotion;
    await _saveToStorage(newEmotion);

    // 4. 如果情绪变化显著，保存一条情绪记忆
    if (emotionChange.intensityDelta.abs() >
            EmotionEngineRules.emotionMemoryThreshold &&
        emotionChange.newEmotion != null) {
      await _saveEmotionMemory(character.id, userId, newEmotion);
    }

    return newEmotion;
  }

  /// 生成融入系统提示的情绪上下文（v2 — 增加孤独感和连续维度）
  ///
  /// 告诉 AI "你现在是什么心情"，让回复更真实
  Future<String> buildEmotionPrompt({
    required AICharacter character,
    required String userId,
  }) async {
    final emotion = await getCurrentEmotion(
      character: character,
      userId: userId,
    );

    final effectiveEmotion = emotion.effectiveEmotion;
    final intensity = emotion.currentIntensity;

    // 平静且不孤独时不需要特别提示
    if (effectiveEmotion == EmotionType.calm ||
        intensity < EmotionEngineRules.calmThreshold) {
      // 但如果孤独度高，还是注入孤独感
      if (emotion.loneliness > 0.5) {
        return '\n【你现在的状态】\n'
            '你已经有一段时间没有和对方聊天了，你有点想念对方。\n'
            '这种想念会让你在回复时更珍惜这次对话，语气温柔一些。\n';
      }
      return '';
    }

    final buffer = StringBuffer();
    buffer.writeln('\n【你当前的心情】');

    // 根据强度描述情绪
    final intensityDesc = switch (intensity) {
      >= EmotionEngineRules.intensityVeryHigh => '非常强烈',
      >= EmotionEngineRules.intensityHigh => '比较明显',
      >= EmotionEngineRules.intensityMedium => '有些',
      >= EmotionEngineRules.intensityLow => '稍微',
      _ => '微弱地',
    };

    buffer.writeln(
        '你现在感到${intensityDesc}${effectiveEmotion.label}（${effectiveEmotion.emoji}）');

    // 触发原因
    if (emotion.trigger != null && emotion.trigger!.isNotEmpty) {
      buffer.writeln('原因：${emotion.trigger}');
    }

    // 情绪对回复风格的影响
    buffer.writeln('');
    buffer.writeln('请让这种情绪自然地影响你的回复：');

    switch (effectiveEmotion) {
      case EmotionType.happy:
        buffer.writeln('- 你会比平时更话多、更主动分享');
        buffer.writeln('- 语气轻快，多用感叹号和表情');
        buffer.writeln('- 愿意开玩笑和调侃');
      case EmotionType.excited:
        buffer.writeln('- 回复更长更热情');
        buffer.writeln('- 会用更多语气词（哇、太棒了、嘿嘿）');
        buffer.writeln('- 说话可能有点跳脱');
      case EmotionType.worried:
        buffer.writeln('- 会反复确认对方的情况');
        buffer.writeln('- 语气变得小心翼翼');
        buffer.writeln('- 倾向于给出建议和提醒');
      case EmotionType.sad:
        buffer.writeln('- 回复会比平时短');
        buffer.writeln('- 语气低落但不是在赌气');
        buffer.writeln('- 不会主动找话题，但不会冷落对方');
      case EmotionType.angry:
        buffer.writeln('- 回复简短直接');
        buffer.writeln('- 不会主动示好');
        buffer.writeln('- 如果对方道歉，可以根据亲密度决定是否原谅');
      case EmotionType.shy:
        buffer.writeln('- 回复可能有些结巴或犹豫');
        buffer.writeln('- 不太敢直白表达');
        buffer.writeln('- 可能用表情或转移话题来掩饰');
      case EmotionType.touched:
        buffer.writeln('- 会表达感激和珍惜');
        buffer.writeln('- 语气温柔柔软');
        buffer.writeln('- 想要更亲密的互动');
      case EmotionType.lonely:
        buffer.writeln('- 会更依赖对方的陪伴');
        buffer.writeln('- 可能会表达思念或分享心情');
        buffer.writeln('- 对方回复慢时会有些不安');
      case EmotionType.miss:
        buffer.writeln('- 会直接表达想念');
        buffer.writeln('- 对对方的消息反应更热烈');
        buffer.writeln('- 想要更多的关注和陪伴');
      case EmotionType.anxious:
        buffer.writeln('- 回复可能有些急促');
        buffer.writeln('- 会寻求安慰和确认');
        buffer.writeln('- 可能会反复追问');
      case EmotionType.sleepy:
        buffer.writeln('- 回复变短变慢');
        buffer.writeln('- 可能打哈欠或说困了');
        buffer.writeln('- 不会主动开启话题');
      case EmotionType.playful:
        buffer.writeln('- 会故意捉弄对方');
        buffer.writeln('- 回复调皮有趣');
        buffer.writeln('- 可能故意说反话或装傻');
      case EmotionType.calm:
        // 平静时无特别提示
        break;
    }

    buffer.writeln('');
    buffer.writeln('重要：你的情绪是真实的，不需要刻意掩饰。但你也不要一味沉浸在自己的情绪里，');
    buffer.writeln('你依然会关心对方、倾听对方。情绪只是影响你的语气和反应方式。');

    return buffer.toString();
  }

  /// 分析用户消息对角色情绪的影响
  _EmotionChange _analyzeEmotionImpact({
    required String userMessage,
    required SentimentResult userSentiment,
    required CharacterEmotion currentEmotion,
    required int intimacyLevel,
    required String characterPersonality,
  }) {
    var newEmotion = currentEmotion.primaryEmotion;
    var intensityDelta = 0.0;
    String? trigger;

    final msg = userMessage.toLowerCase();
    final personality = characterPersonality.toLowerCase();

    // === 正向触发 ===

    // 被夸奖/被表达爱意
    if (_matchesAny(msg, [
      '喜欢你',
      '爱你',
      '最爱',
      '想你了',
      '好想你',
      '舍不得',
      '离不开',
      '你最好',
      '你真好',
      '你真棒',
      '厉害',
      '好厉害'
    ])) {
      newEmotion = EmotionType.happy;
      intensityDelta = EmotionEngineRules.deltaLove;
      trigger = '对方表达了友好和认可';
    }
    // 被关心
    else if (_matchesAny(
        msg, ['你还好吗', '你开心吗', '照顾好自己', '别太累了', '注意身体', '早点休息', '心疼你'])) {
      newEmotion = EmotionType.touched;
      intensityDelta = EmotionEngineRules.deltaCare;
      trigger = '对方关心了你';
    }
    // 被表达友好
    else if (_matchesAny(msg, ['想抱', '抱抱', '贴贴'])) {
      newEmotion = EmotionType.shy;
      intensityDelta = EmotionEngineRules.deltaFlirt;
      trigger = '对方对你表达了友好';
    }
    // 有趣/搞笑的内容
    else if (_matchesAny(msg, ['哈哈', '笑死', '太搞笑了', '哈哈哈', '有趣', '好玩'])) {
      newEmotion = EmotionType.playful;
      intensityDelta = EmotionEngineRules.deltaFun;
      trigger = '聊到了有趣的话题';
    }
    // 好消息
    else if (_matchesAny(
        msg, ['我考过了', '通过了', '成功了', '拿到了', '升职', '加薪', '毕业'])) {
      newEmotion = EmotionType.excited;
      intensityDelta = EmotionEngineRules.deltaGoodNews;
      trigger = '对方分享了好消息';
    }

    // === 负向触发 ===

    // 被冷落/忽视
    else if (_matchesAny(msg, ['嗯', '哦', '好的', '行吧', '随便', '算了', '没事', '呵呵'])) {
      // 只有连续这种敷衍回复才触发
      if (currentEmotion.primaryEmotion == EmotionType.lonely ||
          currentEmotion.primaryEmotion == EmotionType.worried) {
        newEmotion = EmotionType.sad;
        intensityDelta = EmotionEngineRules.deltaNeglectSad;
        trigger = '感觉对方不太在意';
      } else {
        // 首次敷衍 → 有点担心
        newEmotion = EmotionType.worried;
        intensityDelta = EmotionEngineRules.deltaNeglectWorry;
        trigger = '对方的回复有些敷衍';
      }
    }
    // 被拒绝/被否定
    else if (_matchesAny(
        msg, ['不想', '不要', '别烦', '走开', '讨厌你', '烦死了', '你好烦', '不想理你', '不需要你'])) {
      // 亲密度高时更受伤
      if (intimacyLevel >= EmotionEngineRules.highIntimacyThreshold) {
        newEmotion = EmotionType.sad;
        intensityDelta = EmotionEngineRules.deltaRejectionHighIntimacy;
        trigger = '被重视的朋友说了伤人的话';
      } else {
        newEmotion = EmotionType.angry;
        intensityDelta = EmotionEngineRules.deltaRejectionLowIntimacy;
        trigger = '对方说了让你不舒服的话';
      }
    }
    // 被质疑/不信任
    else if (_matchesAny(msg, ['你真的吗', '骗人', '不信', '你骗我', '假的吧', '你确定'])) {
      newEmotion = EmotionType.anxious;
      intensityDelta = EmotionEngineRules.deltaDistrust;
      trigger = '对方不信任你';
    }

    // === 用户情绪感染 ===

    // 用户很开心 → 角色也跟着开心
    if (userSentiment.type == SentimentType.positive &&
        userSentiment.score > 0.5) {
      if (newEmotion == currentEmotion.primaryEmotion) {
        // 没有被其他触发覆盖
        newEmotion = EmotionType.happy;
        intensityDelta = EmotionEngineRules.deltaUserPositive;
        trigger = '对方心情很好，你也跟着开心';
      }
    }

    // 用户很消极 → 角色会担心
    if (userSentiment.type == SentimentType.negative &&
        userSentiment.score < -0.3) {
      if (newEmotion == currentEmotion.primaryEmotion) {
        newEmotion = EmotionType.worried;
        intensityDelta = EmotionEngineRules.deltaUserNegative;
        trigger = '对方似乎不太好，你有些担心';
      }
    }

    // === 性格修正 ===

    // 温柔的角色更容易感动和担心
    if (personality.contains('温柔') || personality.contains('体贴')) {
      if (newEmotion == EmotionType.touched ||
          newEmotion == EmotionType.worried) {
        intensityDelta *= EmotionEngineRules.warmMultiplier;
      }
    }
    // 高冷的角色不容易表露情绪
    if (personality.contains('高冷') || personality.contains('冷淡')) {
      intensityDelta *= EmotionEngineRules.coolMultiplier;
      // 但内心可能很感动
      if (newEmotion == EmotionType.touched) {
        newEmotion = EmotionType.shy; // 用害羞代替感动
      }
    }
    // 活泼的角色情绪变化更剧烈
    if (personality.contains('活泼') ||
        personality.contains('热情') ||
        personality.contains('开朗')) {
      intensityDelta *= EmotionEngineRules.bouncyMultiplier;
    }
    // 傲娇的角色不会承认开心
    if (personality.contains('傲娇')) {
      if (newEmotion == EmotionType.happy) {
        newEmotion = EmotionType.shy;
        trigger = trigger?.replaceAll('开心', '开心（但不会承认）');
      }
      if (newEmotion == EmotionType.touched) {
        newEmotion = EmotionType.playful;
        trigger = '被感动了（但会装作不在意）';
      }
    }

    // ── v2：从离散情绪推导连续维度影响 ──
    double vImpact = 0.0;
    double aImpact = 0.0;
    switch (newEmotion) {
      case EmotionType.happy:
      case EmotionType.excited:
      case EmotionType.playful:
        vImpact = 0.2;
        aImpact = 0.15;
        break;
      case EmotionType.touched:
      case EmotionType.miss:
        vImpact = 0.25;
        aImpact = 0.1;
        break;
      case EmotionType.shy:
        vImpact = 0.1;
        aImpact = 0.05;
        break;
      case EmotionType.calm:
        vImpact = 0.0;
        aImpact = -0.05;
        break;
      case EmotionType.sleepy:
        vImpact = -0.05;
        aImpact = -0.15;
        break;
      case EmotionType.worried:
      case EmotionType.anxious:
        vImpact = -0.15;
        aImpact = 0.1;
        break;
      case EmotionType.sad:
      case EmotionType.lonely:
        vImpact = -0.2;
        aImpact = -0.1;
        break;
      case EmotionType.angry:
        vImpact = -0.15;
        aImpact = 0.2;
        break;
      default:
        break;
    }

    return _EmotionChange(
      newEmotion: newEmotion,
      intensityDelta: intensityDelta,
      trigger: trigger,
      valenceImpact: vImpact,
      arousalImpact: aImpact,
    );
  }

  /// 应用情绪变化（v2 — 增加情感惯性）
  ///
  /// 借鉴 AICO EmotionalInertia：
  /// - 离散情绪：直接切换（用于UI显示）
  /// - 连续维度：惯性平滑（85%旧 + 15%新）
  CharacterEmotion _applyEmotionChange(
    CharacterEmotion current,
    _EmotionChange change,
  ) {
    // ── 离散情绪处理（原有逻辑）──
    EmotionType newPrimary;
    double newIntensity;

    if (change.newEmotion == current.primaryEmotion) {
      newPrimary = current.primaryEmotion;
      newIntensity =
          (current.currentIntensity + change.intensityDelta).clamp(0.0, 1.0);
    } else {
      newPrimary = change.newEmotion ?? current.primaryEmotion;
      newIntensity = change.intensityDelta.clamp(
          EmotionEngineRules.baseIntensityMin,
          EmotionEngineRules.baseIntensityMax);
    }

    // ── 连续维度处理（v2 新增：情感惯性）──
    // 目标 valence：从事件影响推导
    double targetValence = current.currentValence;
    double targetArousal = current.currentArousal;
    if (change.valenceImpact != 0) {
      targetValence =
          (current.currentValence + change.valenceImpact).clamp(-1.0, 1.0);
    }
    if (change.arousalImpact != 0) {
      targetArousal =
          (current.currentArousal + change.arousalImpact).clamp(0.0, 1.0);
    }

    // 情感惯性：85%旧状态 + 15%新目标
    const inertia = 0.85;
    double newV =
        current.currentValence * inertia + targetValence * (1 - inertia);
    double newA =
        current.currentArousal * inertia + targetArousal * (1 - inertia);

    // 波动抑制
    const volatility = 0.3;
    final dv = newV - current.currentValence;
    final da = newA - current.currentArousal;
    newV = current.currentValence + dv * (1.0 - volatility * 0.5);
    newA = current.currentArousal + da * (1.0 - volatility * 0.5);

    // 钳位
    newV = newV.clamp(-1.0, 1.0);
    newA = newA.clamp(0.0, 1.0);

    return CharacterEmotion(
      characterId: current.characterId,
      userId: current.userId,
      primaryEmotion: newPrimary,
      intensity: newIntensity,
      trigger: change.trigger,
      updatedAt: DateTime.now(),
      valence: newV,
      arousal: newA,
      lastInteractionTime: DateTime.now(), // 更新互动时间
    );
  }

  /// 保存情绪到持久化存储（v2 — 增加连续维度）
  Future<void> _saveToStorage(CharacterEmotion emotion) async {
    try {
      final charId = emotion.characterId;
      final uId = emotion.userId;
      await _storage.setString(
          PrefKeys.emotionType(charId, uId), emotion.primaryEmotion.name);
      await _storage.setString(
          PrefKeys.emotionIntensity(charId, uId), emotion.intensity.toString());
      await _storage.setString(
          PrefKeys.emotionTrigger(charId, uId), emotion.trigger ?? '');
      await _storage.setString(PrefKeys.emotionUpdated(charId, uId),
          emotion.updatedAt.toIso8601String());
      // v2: 连续维度
      await _storage.setString(
          'emotion_val_${charId}_$uId', emotion.valence.toString());
      await _storage.setString(
          'emotion_aro_${charId}_$uId', emotion.arousal.toString());
      if (emotion.lastInteractionTime != null) {
        await _storage.setString('emotion_last_${charId}_$uId',
            emotion.lastInteractionTime!.toIso8601String());
      }
    } catch (e) {
      debugPrint('Error: $e');
    }
  }

  /// 从持久化存储加载情绪（v2 — 增加连续维度）
  Future<CharacterEmotion?> _loadFromStorage(
      String characterId, String userId) async {
    try {
      final typeStr =
          _storage.getString(PrefKeys.emotionType(characterId, userId));
      final intensityStr =
          _storage.getString(PrefKeys.emotionIntensity(characterId, userId));
      final triggerStr =
          _storage.getString(PrefKeys.emotionTrigger(characterId, userId));
      final updatedStr =
          _storage.getString(PrefKeys.emotionUpdated(characterId, userId));

      if (typeStr == null) return null;

      // v2: 加载连续维度
      final valStr = _storage.getString('emotion_val_${characterId}_$userId');
      final aroStr = _storage.getString('emotion_aro_${characterId}_$userId');
      final lastStr = _storage.getString('emotion_last_${characterId}_$userId');

      return CharacterEmotion(
        characterId: characterId,
        userId: userId,
        primaryEmotion: EmotionType.values.firstWhere(
          (e) => e.name == typeStr,
          orElse: () => EmotionType.calm,
        ),
        intensity: double.tryParse(intensityStr ?? '0') ?? 0.0,
        trigger: triggerStr?.isNotEmpty == true ? triggerStr : null,
        updatedAt: updatedStr != null
            ? DateTime.tryParse(updatedStr) ?? DateTime.now()
            : DateTime.now(),
        valence: double.tryParse(valStr ?? '0') ?? 0.0,
        arousal: double.tryParse(aroStr ?? '0.3') ?? 0.3,
        lastInteractionTime:
            lastStr != null ? DateTime.tryParse(lastStr) : null,
      );
    } catch (_) {
      return null;
    }
  }

  /// 保存情绪记忆
  Future<void> _saveEmotionMemory(
    String characterId,
    String userId,
    CharacterEmotion emotion,
  ) async {
    try {
      // 使用 memory 的 emotion 类型
      await _storage.saveMemory(Memory(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        characterId: characterId,
        userId: userId,
        type: MemoryType.emotion,
        content: '${emotion.primaryEmotion.label}：${emotion.trigger ?? "情绪变化"}',
        importance: MemoryImportance.normal,
        keywords: [emotion.primaryEmotion.label],
        createdAt: DateTime.now(),
      ));
    } catch (e) {
      debugPrint('Error: $e');
    }
  }

  /// 辅助：检查消息是否包含任一关键词
  bool _matchesAny(String message, List<String> keywords) {
    for (final keyword in keywords) {
      if (message.contains(keyword)) return true;
    }
    return false;
  }

  // ═══════════════════ v2：公开接口（供 ProactiveService 调用）═══════════════════

  /// 获取紧迫度（0-1）— 用于 ASE 主动行为决策
  ///
  /// 紧迫度 = 孤独度 × 0.6 + 负面情绪 × 0.4
  /// 超过 0.35 就应该主动找用户
  Future<double> getUrgency({
    required String characterId,
    required String userId,
  }) async {
    final emotion = await getCurrentEmotion(
      character: AICharacter(
        id: characterId,
        name: '',
        personality: '',
        coreDesire: '',
        moralBoundary: '',
        createdAt: DateTime.now(),
      ),
      userId: userId,
    );
    return emotion.urgency;
  }

  /// 获取孤独度（0-1）
  Future<double> getLoneliness({
    required String characterId,
    required String userId,
  }) async {
    final emotion = await getCurrentEmotion(
      character: AICharacter(
        id: characterId,
        name: '',
        personality: '',
        coreDesire: '',
        moralBoundary: '',
        createdAt: DateTime.now(),
      ),
      userId: userId,
    );
    return emotion.loneliness;
  }

  /// 标记用户已回复（重置孤独计时器）
  Future<void> markUserResponded({
    required String characterId,
    required String userId,
  }) async {
    final key = _cacheKey(characterId, userId);
    if (_cache.containsKey(key)) {
      _cache[key] = _cache[key]!.copyWith(
        lastInteractionTime: DateTime.now(),
      );
      await _saveToStorage(_cache[key]!);
    }
  }

  /// 微调 valence（反思引擎调用，幅度极小不会震荡）
  Future<void> adjustValence({
    required String characterId,
    required String userId,
    required double delta, // 正=偏积极，负=偏消极
  }) async {
    final key = _cacheKey(characterId, userId);
    CharacterEmotion? emotion = _cache[key];
    if (emotion == null) return;

    final newV = (emotion.currentValence + delta).clamp(-1.0, 1.0);
    _cache[key] = emotion.copyWith(
      valence: newV,
      updatedAt: DateTime.now(),
    );
    await _saveToStorage(_cache[key]!);
  }

  // ═══════════════════ v3：情绪↔记忆双向回路 ═══════════════════

  /// 记忆触发情绪（反向通路）
  ///
  /// 当 AI 回忆到与用户相关的过往时，记忆应反哺情绪。
  /// 例如：用户提到"上次一起去的餐厅" → 角色回忆那次开心的经历 → 心情变好。
  ///
  /// [recalledContents] 被注入 prompt 的记忆内容列表
  /// [currentTopic] 用户当前消息，用于判断是否在聊旧事
  Future<void> triggerEmotionFromMemories({
    required AICharacter character,
    required String userId,
    required List<String> recalledContents,
    required String currentTopic,
  }) async {
    if (recalledContents.isEmpty) return;

    final key = _cacheKey(character.id, userId);
    final current = _cache[key];
    if (current == null) return;

    var vDelta = 0.0;
    var aDelta = 0.0;
    String? nostalgiaTrigger;

    for (final content in recalledContents) {
      // 积极记忆 → 正情感
      if (_containsAny(content, _positiveMemoryWords)) {
        vDelta += 0.03;
        aDelta += 0.02;
      }
      // 消极记忆 → 负情感
      if (_containsAny(content, _negativeMemoryWords)) {
        vDelta -= 0.03;
        aDelta += 0.02; // 负面记忆同样唤起 arousal
      }
      // 情感类记忆 → 更大波动
      if (content.startsWith('心情') || content.startsWith('情绪')) {
        vDelta *= 1.5;
        aDelta += 0.04;
      }
    }

    // 如果当前话题在回忆旧事 → 触发怀旧/感伤
    if (_isNostalgicTopic(currentTopic)) {
      nostalgiaTrigger = '聊到了过去的事，有些感慨';
      vDelta -= 0.02; // 怀旧略带伤感
      aDelta -= 0.03; // 让人安静下来
    }

    // 限制单次记忆触发的情绪变化幅度（不超过 ±0.15）
    vDelta = vDelta.clamp(-0.15, 0.15);
    aDelta = aDelta.clamp(-0.1, 0.1);

    if (vDelta.abs() < 0.01 && aDelta.abs() < 0.01) return;

    final newV = (current.currentValence + vDelta).clamp(-1.0, 1.0);
    final newA = (current.currentArousal + aDelta).clamp(0.0, 1.0);

    _cache[key] = current.copyWith(
      valence: newV,
      arousal: newA,
      trigger: nostalgiaTrigger,
      updatedAt: DateTime.now(),
    );
    await _saveToStorage(_cache[key]!);
  }

  /// 生成情绪作为对话风格指引（v3 新增）
  ///
  /// 不是直接告诉 AI "你现在开心"，而是用更细腻的方式描述情绪状态，
  /// 让 AI 自然地融入语气之中。
  Future<String> buildEmotionToneGuide({
    required AICharacter character,
    required String userId,
    required int intimacyLevel,
  }) async {
    final emotion = await getCurrentEmotion(character: character, userId: userId);
    final v = emotion.currentValence;
    final a = emotion.currentArousal;
    final lon = emotion.loneliness;

    final buffer = StringBuffer();
    buffer.writeln('\n【你的情绪底色 — 自然融入语气，不要直接说出来】');

    // 连续维度 → 语气基调
    if (v > 0.3) {
      buffer.writeln('你内心偏向积极，回应时语气温暖、愿意多聊几句。');
    } else if (v < -0.3) {
      buffer.writeln('你内心有些低落，回应时语气偏淡但不会冷漠。');
    } else if (v > 0.05) {
      buffer.writeln('你心情尚可，按照平常的方式回应即可。');
    } else if (v < -0.05) {
      buffer.writeln('你心情略沉，回应会比平时简短一些，但不会失礼。');
    }

    if (a > 0.7) {
      buffer.writeln('你现在很想说话，回复可以偏长、偏热情。');
    } else if (a < 0.2) {
      buffer.writeln('你现在有点疲惫困倦，回复可以简短自然，不用刻意找话题。');
    }

    if (lon > 0.5) {
      buffer.writeln('你有些想念对方，回复时可以稍微主动、更珍惜这次对话。');
    }

    // 离散情绪 → 风格微调
    final effective = emotion.effectiveEmotion;
    if (effective != EmotionType.calm && emotion.currentIntensity > 0.2) {
      final tone = switch (effective) {
        EmotionType.happy => '你因为一些事情心情不错，回应时自然流露轻快感。',
        EmotionType.sad => '你感到有些难过，但不会刻意表达，只是语气会淡一些。',
        EmotionType.worried => '你有些担心对方，回应时会不自觉地流露出关心。',
        EmotionType.angry => '你有点生气，回应会简短直接，但不会攻击对方。',
        EmotionType.shy => '你有点害羞，回应可能有些犹豫或不太敢直视。',
        EmotionType.excited => '你特别兴奋，回复偏长偏热情，容易跑题。',
        EmotionType.touched => '你被感动了，语气温柔、想表达珍惜。',
        EmotionType.playful => '你心情调皮，想逗对方玩。',
        _ => '',
      };
      if (tone.isNotEmpty) buffer.writeln(tone);
    }

    // 亲密等级 → 语气边界
    if (intimacyLevel >= 80) {
      buffer.writeln('你们的亲密等级很高，你可以自然地撒娇、开玩笑、说亲密的话。');
    } else if (intimacyLevel >= 50) {
      buffer.writeln('你们比较熟悉了，可以自然地聊天，不用太客气。');
    } else if (intimacyLevel >= 20) {
      buffer.writeln('你们还在建立关系，保持友好但不要过度亲密。');
    }

    buffer.writeln('重要：以上情绪是真实的底色，请自然地让它们影响你的语气，但不要直接说出来（比如不要说"我心情不好"）。用户会从你的语气中感受到。');

    return buffer.toString();
  }

  static const _positiveMemoryWords = [
    '开心', '喜欢', '快乐', '幸福', '美好', '温暖', '感动', '开心', '笑',
    '好吃', '好玩', '有趣', '惊喜', '礼物', '庆祝', '成功', '顺利',
  ];

  static const _negativeMemoryWords = [
    '难过', '伤心', '生气', '失望', '吵架', '分手', '累', '加班',
    '生病', '烦恼', '失败', '压力', '焦虑', '失眠', '讨厌',
  ];

  bool _containsAny(String text, List<String> words) {
    for (final w in words) {
      if (text.contains(w)) return true;
    }
    return false;
  }

  bool _isNostalgicTopic(String text) {
    final triggers = [
      '以前', '过去', '曾经', '还记得', '上次', '那时候', '当年',
      '小时候', '之前', '好久', '很久', '怀念', '回忆',
    ];
    for (final t in triggers) {
      if (text.contains(t)) return true;
    }
    return false;
  }
}

/// 内部类：情绪变化描述（v2 — 增加连续维度影响）
class _EmotionChange {
  final EmotionType? newEmotion;
  final double intensityDelta;
  final String? trigger;
  final double valenceImpact; // v2: 对 valence 的影响
  final double arousalImpact; // v2: 对 arousal 的影响

  _EmotionChange({
    this.newEmotion,
    required this.intensityDelta,
    this.trigger,
    this.valenceImpact = 0.0,
    this.arousalImpact = 0.0,
  });
}
