// ============================================================
// 全生命周期数字生命世界 — Phase 4
// 冲突引擎：性格兼容性计算、冲突触发/回应/和解
// ============================================================

import 'dart:math';
import 'package:uuid/uuid.dart';
import 'package:flutter/foundation.dart';

import '../models/life_profile.dart';
import '../models/personality_state.dart';
import '../models/ai_relationship.dart';
import '../models/character_emotion.dart';
import 'llm_service.dart';
import 'memory_engine.dart';

// ── 冲突事件 ──

class ConflictEvent {
  final String id;
  final String initiatorId;
  final String targetId;
  final String trigger;
  final String initiatorStatement;
  final double intensity;
  final DateTime timestamp;
  final Map<String, double> personalityImpact;

  const ConflictEvent({
    required this.id,
    required this.initiatorId,
    required this.targetId,
    required this.trigger,
    required this.initiatorStatement,
    required this.intensity,
    required this.timestamp,
    this.personalityImpact = const {},
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'initiatorId': initiatorId,
        'targetId': targetId,
        'trigger': trigger,
        'initiatorStatement': initiatorStatement,
        'intensity': intensity,
        'timestamp': timestamp.toIso8601String(),
        'personalityImpact': personalityImpact,
      };

  factory ConflictEvent.fromJson(Map<String, dynamic> json) {
    return ConflictEvent(
      id: json['id'] as String,
      initiatorId: json['initiatorId'] as String,
      targetId: json['targetId'] as String,
      trigger: json['trigger'] as String,
      initiatorStatement: json['initiatorStatement'] as String,
      intensity: (json['intensity'] as num).toDouble(),
      timestamp: DateTime.parse(json['timestamp'] as String),
      personalityImpact:
          (json['personalityImpact'] as Map<String, dynamic>?)
                  ?.map((k, v) => MapEntry(k, (v as num).toDouble())) ??
              {},
    );
  }
}

// ── 冲突回应 ──

class ConflictResponse {
  /// 'counter' / 'retreat' / 'ignore' / 'reconcile'
  final String responseType;
  final String statement;
  final double emotionalImpact;

  const ConflictResponse({
    required this.responseType,
    required this.statement,
    required this.emotionalImpact,
  });
}

// ── 和解结果 ──

class ReconciliationResult {
  final bool success;
  final String? statement;
  final Map<String, double> relationshipChange;

  const ReconciliationResult({
    required this.success,
    this.statement,
    this.relationshipChange = const {},
  });
}

/// 冲突引擎
///
/// 职责：
/// - 计算两个角色的性格兼容性
/// - 根据性格和紧张度判断冲突概率
/// - 通过 LLM 生成冲突言论和回应
/// - 冲突结果影响关系图谱和人格状态
class ConflictEngine {
  final LlmService _llm;
  final MemoryEngine _memoryEngine;
  final String _userId;

  static const _uuid = Uuid();

  ConflictEngine({
    required LlmService llm,
    required MemoryEngine memoryEngine,
    required String userId,
  })  : _llm = llm,
        _memoryEngine = memoryEngine,
        _userId = userId;

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  //  兼容性与概率计算
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  /// 性格兼容性计算（0=完全冲突, 1=完美兼容）
  ///
  /// 兼容性 = 1 - (外向差异×0.2 + 宜人差异×0.5 + 神经质差异×0.3)
  static double compatibility(PersonalityState a, PersonalityState b) {
    final eDiff = (a.extraversion - b.extraversion).abs();
    final aDiff = (a.agreeableness - b.agreeableness).abs();
    final nDiff = (a.neuroticism - b.neuroticism).abs();

    final score = 1.0 - (eDiff * 0.2 + aDiff * 0.5 + nDiff * 0.3);
    return score.clamp(0.0, 1.0);
  }

  /// 冲突触发概率
  ///
  /// 概率 = (1-兼容性)×0.4 + 紧张度×0.6
  /// 高宜人性角色会压制冲突概率（回避倾向）
  static double conflictProbability(
    AIRelationship relationship,
    PersonalityState a,
    PersonalityState b,
    double tension,
  ) {
    final compat = compatibility(a, b);
    final base = (1.0 - compat) * 0.4 + tension * 0.6;

    // 高宜人性抑制：双方平均宜人性越高，冲突概率越低
    final avgAgreeableness = (a.agreeableness + b.agreeableness) / 2.0;
    final suppression = avgAgreeableness * 0.3;

    // 关系亲密度调节：高亲密度略微降低冲突（有缓冲）
    final affinityFactor = relationship.affinity > 0.7 ? -0.05 : 0.0;

    return (base - suppression + affinityFactor).clamp(0.0, 1.0);
  }

  /// 冲突烈度（影响人格变化的程度）
  ///
  /// 高神经质 → 冲突更激烈
  /// 高外向 → 更容易把冲突摆到台面上
  static double conflictIntensity(PersonalityState a, PersonalityState b) {
    final neuroticFactor = (a.neuroticism + b.neuroticism) / 2.0;
    final extravertFactor = (a.extraversion + b.extraversion) / 2.0;

    // 基础烈度 = 神经质主导，外向加成
    final raw = neuroticFactor * 0.7 + extravertFactor * 0.3;
    return raw.clamp(0.0, 1.0);
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  //  冲突触发
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  /// 触发冲突 → 生成冲突事件
  Future<ConflictEvent> trigger({
    required LifeProfile initiator,
    required LifeProfile target,
    required String triggerReason,
    required String perceptionContext,
  }) async {
    final initiatorPersonality =
        PersonalityState.fromJson(initiator.personalityState);
    final targetPersonality =
        PersonalityState.fromJson(target.personalityState);
    final intensity = conflictIntensity(initiatorPersonality, targetPersonality);

    final prompt = _buildConflictPrompt(
      initiator,
      target,
      triggerReason,
      perceptionContext,
    );

    final response = await _llm.chat(
      userId: _userId,
      message: prompt,
      systemPrompt: '你是冲突场景生成器。以角色身份生成一句自然的冲突性言论，只输出言论内容，不要加引号或旁白。',
    );

    final statement = response.content.trim();

    // 计算人格影响
    final impact = _calculatePersonalityImpact(
      initiatorPersonality,
      targetPersonality,
      intensity,
    );

    final event = ConflictEvent(
      id: _uuid.v4(),
      initiatorId: initiator.id,
      targetId: target.id,
      trigger: triggerReason,
      initiatorStatement: statement,
      intensity: intensity,
      timestamp: DateTime.now(),
      personalityImpact: impact,
    );

    // 写入发起者的社交记忆
    await _memoryEngine.saveSocialMemory(
      characterId: initiator.id,
      targetCharacterId: target.id,
      interactionType: 'conflict',
      content: '和${target.name}发生了冲突：$triggerReason。我说了"$statement"',
      emotionTag: 'angry',
      importance: intensity > 0.6 ? 'important' : 'normal',
      keywords: ['冲突', target.name, triggerReason],
    );

    // 写入目标的社交记忆
    await _memoryEngine.saveSocialMemory(
      characterId: target.id,
      targetCharacterId: initiator.id,
      interactionType: 'conflict',
      content: '${initiator.name}和我发生了冲突：$triggerReason。TA说"$statement"',
      emotionTag: 'angry',
      importance: intensity > 0.6 ? 'important' : 'normal',
      keywords: ['冲突', initiator.name, triggerReason],
    );

    debugPrint(
        '[ConflictEngine] ${initiator.name} → ${target.name}: "$statement" (intensity=${intensity.toStringAsFixed(2)})');

    return event;
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  //  冲突回应
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  /// 冲突后的反应（目标角色如何回应）
  Future<ConflictResponse> respond({
    required ConflictEvent event,
    required LifeProfile responder,
    required Map<String, dynamic> perception,
  }) async {
    final responderPersonality =
        PersonalityState.fromJson(responder.personalityState);

    // 高宜人性 → 更倾向回避或和解
    // 高神经质 → 更可能反击
    // 低宜人性 + 高神经质 → 激烈反击
    final responseBias = _determineResponseBias(responderPersonality);

    final prompt = _buildResponsePrompt(responder, event);

    final response = await _llm.chat(
      userId: _userId,
      message: prompt,
      systemPrompt:
          '你是冲突回应生成器。以角色身份生成回应，只输出回应内容，不要加引号或旁白。'
          '回应倾向：$responseBias',
    );

    final statement = response.content.trim();
    final responseType = _classifyResponseType(statement, responderPersonality);
    final emotionalImpact = _calculateEmotionalImpact(
      event.intensity,
      responderPersonality,
      responseType,
    );

    // 写入回应者的社交记忆
    await _memoryEngine.saveSocialMemory(
      characterId: responder.id,
      targetCharacterId: event.initiatorId,
      interactionType: 'conflict_response',
      content: '面对冲突，我选择了$responseType。我说"$statement"',
      emotionTag: responseType == 'counter' ? 'angry' : 'worried',
      importance: event.intensity > 0.6 ? 'important' : 'normal',
      keywords: ['冲突回应', responseType],
    );

    return ConflictResponse(
      responseType: responseType,
      statement: statement,
      emotionalImpact: emotionalImpact,
    );
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  //  和解
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  /// 和解尝试
  ///
  /// 条件：
  /// - 距最近冲突至少 3 天冷却期
  /// - 至少一方主动（高宜人性或高共情角色更可能主动）
  Future<ReconciliationResult> attemptReconciliation({
    required LifeProfile initiator,
    required LifeProfile target,
    required List<ConflictEvent> history,
  }) async {
    if (history.isEmpty) {
      return const ReconciliationResult(success: false);
    }

    // 检查冷却期：距最近冲突至少 3 天
    final latestConflict = history.reduce(
      (a, b) => a.timestamp.isAfter(b.timestamp) ? a : b,
    );
    final daysSinceConflict =
        DateTime.now().difference(latestConflict.timestamp).inDays;
    if (daysSinceConflict < 3) {
      debugPrint(
          '[ConflictEngine] 和解冷却中：${3 - daysSinceConflict}天后可尝试');
      return const ReconciliationResult(success: false);
    }

    final initiatorPersonality =
        PersonalityState.fromJson(initiator.personalityState);
    final targetPersonality =
        PersonalityState.fromJson(target.personalityState);

    // 主动和解概率：高宜人性 + 高共情 → 更可能主动
    final initiatorWillingness =
        (initiatorPersonality.agreeableness * 0.6 +
                initiatorPersonality.empathy * 0.4)
            .clamp(0.0, 1.0);
    final targetOpenness =
        (targetPersonality.agreeableness * 0.5 +
                targetPersonality.empathy * 0.3 +
                (1.0 - targetPersonality.neuroticism) * 0.2)
            .clamp(0.0, 1.0);

    // 和解成功率：主动方意愿 × 接受方开放度
    final successChance = initiatorWillingness * targetOpenness;
    final roll = Random().nextDouble();
    final success = roll < successChance;

    if (!success) {
      debugPrint(
          '[ConflictEngine] 和解失败：意愿=${initiatorWillingness.toStringAsFixed(2)}, '
          '开放度=${targetOpenness.toStringAsFixed(2)}, roll=${roll.toStringAsFixed(2)}');
      return const ReconciliationResult(success: false);
    }

    // 生成和解话语
    final prompt = _buildReconciliationPrompt(
      initiator,
      target,
      latestConflict,
    );

    final response = await _llm.chat(
      userId: _userId,
      message: prompt,
      systemPrompt:
          '你是和解场景生成器。以主动和解方的身份生成一句真诚的和解话语，只输出内容，不要加引号或旁白。',
    );

    final statement = response.content.trim();

    // 和解后关系变化
    final relationshipChange = <String, double>{
      'affinity': 0.1 + successChance * 0.1, // 恢复 0.1~0.2 亲密度
      'trust': 0.05 + successChance * 0.05,
    };

    // 写入双方记忆
    await _memoryEngine.saveSocialMemory(
      characterId: initiator.id,
      targetCharacterId: target.id,
      interactionType: 'reconciliation',
      content: '和${target.name}和解了。我说"$statement"',
      emotionTag: 'touched',
      importance: 'important',
      keywords: ['和解', '关系修复'],
    );
    await _memoryEngine.saveSocialMemory(
      characterId: target.id,
      targetCharacterId: initiator.id,
      interactionType: 'reconciliation',
      content: '和${initiator.name}和解了。TA说"$statement"',
      emotionTag: 'touched',
      importance: 'important',
      keywords: ['和解', '关系修复'],
    );

    debugPrint('[ConflictEngine] 和解成功：${initiator.name} → ${target.name}');

    return ReconciliationResult(
      success: true,
      statement: statement,
      relationshipChange: relationshipChange,
    );
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  //  内部方法
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  /// 构建冲突提示词
  String _buildConflictPrompt(
    LifeProfile initiator,
    LifeProfile target,
    String reason,
    String perceptionContext,
  ) {
    final personality = PersonalityState.fromJson(initiator.personalityState);
    return '''
你是${initiator.name}，${initiator.biologicalAge}岁。
性格：${personality.summary}
当前情绪状态：${_describeEmotion(initiator)}

你和${target.name}之间出现了矛盾。
起因：$reason
你看到/感受到：$perceptionContext

以${initiator.name}的身份，说一句带有冲突性的话来表达不满或立场。
1-2句话，自然真实，符合你的性格。直接说话，不要旁白。
''';
  }

  /// 构建回应提示词
  String _buildResponsePrompt(LifeProfile responder, ConflictEvent event) {
    final personality = PersonalityState.fromJson(responder.personalityState);
    return '''
你是${responder.name}，${responder.biologicalAge}岁。
性格：${personality.summary}
当前情绪状态：${_describeEmotion(responder)}

有人和你发生了冲突。
冲突起因：${event.trigger}
对方说："${event.initiatorStatement}"

以${responder.name}的身份回应，1-2句话，自然真实，符合你的性格。直接说话，不要旁白。
''';
  }

  /// 构建和解提示词
  String _buildReconciliationPrompt(
    LifeProfile initiator,
    LifeProfile target,
    ConflictEvent lastConflict,
  ) {
    final personality = PersonalityState.fromJson(initiator.personalityState);
    return '''
你是${initiator.name}，${initiator.biologicalAge}岁。
性格：${personality.summary}

你和${target.name}几天前发生了冲突。
起因：${lastConflict.trigger}
当时你说："${lastConflict.initiatorStatement}"

现在你冷静下来了，想要和解。
以${initiator.name}的身份，说一句真诚的和解话语。1-2句话，自然真实。直接说话，不要旁白。
''';
  }

  /// 确定回应倾向
  String _determineResponseBias(PersonalityState personality) {
    if (personality.agreeableness > 0.7) {
      return '倾向回避或和解，不愿正面冲突';
    } else if (personality.neuroticism > 0.7) {
      return '情绪化反应，可能激烈反击或委屈退缩';
    } else if (personality.agreeableness < 0.3 && personality.neuroticism < 0.3) {
      return '冷静但强硬，据理力争';
    } else {
      return '根据情境选择回应方式';
    }
  }

  /// 分类回应类型
  String _classifyResponseType(String statement, PersonalityState personality) {
    final lower = statement.toLowerCase();

    // 简单关键词匹配 + 性格修正
    if (lower.contains('对不起') ||
        lower.contains('抱歉') ||
        lower.contains('算了') ||
        lower.contains('不吵了')) {
      return 'reconcile';
    }
    if (lower.contains('你') &&
        (lower.contains('凭什么') ||
            lower.contains('怎么') ||
            lower.contains('难道'))) {
      return 'counter';
    }
    if (lower.length < 10 || lower.contains('哼') || lower.contains('随便')) {
      return 'ignore';
    }

    // 性格倾向修正
    if (personality.agreeableness > 0.6) return 'retreat';
    if (personality.neuroticism > 0.6) return 'counter';
    return 'counter';
  }

  /// 计算情绪影响
  double _calculateEmotionalImpact(
    double conflictIntensity,
    PersonalityState personality,
    String responseType,
  ) {
    final base = conflictIntensity;
    final neuroticMultiplier = 1.0 + personality.neuroticism * 0.5;

    switch (responseType) {
      case 'counter':
        return (base * 0.6 * neuroticMultiplier).clamp(0.0, 1.0);
      case 'retreat':
        return (base * 0.8 * neuroticMultiplier).clamp(0.0, 1.0); // 退缩更受伤
      case 'ignore':
        return (base * 0.2).clamp(0.0, 1.0);
      case 'reconcile':
        return (-base * 0.3).clamp(-1.0, 0.0); // 和解减轻负面
      default:
        return (base * 0.5).clamp(0.0, 1.0);
    }
  }

  /// 计算冲突对双方人格的影响
  Map<String, double> _calculatePersonalityImpact(
    PersonalityState initiator,
    PersonalityState target,
    double intensity,
  ) {
    final impact = <String, double>{};
    final factor = intensity * 0.02; // 每次冲突最大 2% 变化

    // 发起者：冲突可能降低宜人性，略微增加神经质
    impact['initiator_agreeableness'] = -factor * (1.0 - initiator.stability);
    impact['initiator_neuroticism'] = factor * 0.5 * (1.0 - initiator.stability);

    // 目标：被攻击可能增加神经质，降低信任倾向
    impact['target_neuroticism'] = factor * (1.0 - target.stability);
    impact['target_agreeableness'] = -factor * 0.5 * (1.0 - target.stability);

    return impact;
  }

  /// 描述角色当前情绪
  String _describeEmotion(LifeProfile profile) {
    final emotionData = profile.emotionalState;
    if (emotionData.isEmpty) return '平静';

    final primary = emotionData['primaryEmotion'] as String? ?? 'calm';
    final emotionMap = {
      'happy': '开心',
      'excited': '兴奋',
      'calm': '平静',
      'worried': '担心',
      'sad': '难过',
      'angry': '生气',
      'shy': '害羞',
      'touched': '感动',
      'lonely': '孤独',
      'miss': '想念',
      'anxious': '焦虑',
      'sleepy': '困倦',
      'playful': '调皮',
    };
    return emotionMap[primary] ?? '平静';
  }
}
