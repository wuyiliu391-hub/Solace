// ============================================================
// 全生命周期数字生命世界 — Phase 4
// 感知层：四层信息可见性，控制角色间信息暴露边界
// ============================================================

import 'package:flutter/foundation.dart';
import '../models/life_profile.dart';
import '../models/relationship_graph.dart';
import '../models/personality_state.dart';

// ─────────────────────────────────────────────────
// 感知级别
// ─────────────────────────────────────────────────

/// 感知级别 — 四层信息可见性
enum PerceptionLevel {
  public, // 公开：所有人可见
  social, // 社交：好友可见
  private, // 私密：当事人 + 用户可见
  inner, // 内心：仅角色自己 + 用户观察面板
}

// ─────────────────────────────────────────────────
// 感知快照
// ─────────────────────────────────────────────────

/// 感知快照 — 对某个角色的感知结果
class PerceptionSnapshot {
  /// 目标角色 ID
  final String targetId;

  /// 目标角色名
  final String targetName;

  /// 感知级别
  final PerceptionLevel level;

  /// 感知到的信息文本（可直接注入 LLM 提示词）
  final String content;

  /// 感知时间
  final DateTime timestamp;

  const PerceptionSnapshot({
    required this.targetId,
    required this.targetName,
    required this.level,
    required this.content,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'targetId': targetId,
        'targetName': targetName,
        'level': level.index,
        'content': content,
        'timestamp': timestamp.toIso8601String(),
      };
}

// ─────────────────────────────────────────────────
// 感知层核心
// ─────────────────────────────────────────────────

/// 感知层 — 四层信息可见性引擎
///
/// 设计理念：
/// - 角色对其他角色的了解程度取决于关系亲密度
/// - 公开层：社交名片级别的信息
/// - 社交层：朋友间分享的信息
/// - 私密层：亲密关系才透露的信息
/// - 内心层：只有角色自己和用户知道的深层信息
///
/// 输出格式直接可注入 LLM 提示词，无需额外转换。
class PerceptionLayer {
  // ═══════════════════════════════════════════
  // 公共接口
  // ═══════════════════════════════════════════

  /// 构建某个角色对另一个角色的感知信息
  ///
  /// 根据关系亲密度自动决定 PerceptionLevel，或使用指定的 level。
  /// 返回格式化的文本，可直接注入 LLM 提示词。
  static String buildPerception({
    required Map<String, dynamic> observerProfile,
    required Map<String, dynamic> targetProfile,
    required Map<String, dynamic> relationship,
    PerceptionLevel? level,
  }) {
    // 确定感知级别
    final effectiveLevel = level ??
        autoLevel(
          (relationship['intimacy'] as num?)?.toDouble() ?? 0.0,
          (relationship['familiarity'] as num?)?.toDouble() ?? 0.0,
        );

    final buffer = StringBuffer();
    final targetName = targetProfile['name'] as String? ?? '未知';

    buffer.writeln('【你对 $targetName 的了解】');
    buffer.writeln('（感知深度：${_levelLabel(effectiveLevel)}）');
    buffer.writeln();

    // 公开层（所有人都能看见）
    buffer.writeln('── 公开信息 ──');
    buffer.writeln(_buildPublicInfo(targetProfile));
    buffer.writeln();

    // 社交层（好友可见）
    if (effectiveLevel.index >= PerceptionLevel.social.index) {
      buffer.writeln('── 社交信息 ──');
      buffer.writeln(_buildSocialInfo(targetProfile, relationship));
      buffer.writeln();
    }

    // 私密层（足够亲密才可见）
    if (effectiveLevel.index >= PerceptionLevel.private.index) {
      buffer.writeln('── 私密信息 ──');
      buffer.writeln(_buildPrivateInfo(targetProfile));
      buffer.writeln();
    }

    // 内心层（仅角色自己 + 用户）
    if (effectiveLevel.index >= PerceptionLevel.inner.index) {
      buffer.writeln('── 内心世界 ──');
      buffer.writeln(_buildInnerInfo(targetProfile));
    }

    return buffer.toString();
  }

  /// 自动判断感知级别（基于关系亲密度和熟悉度）
  ///
  /// 判断逻辑：
  /// - intimacy > 0.7 && familiarity > 0.7 → inner（至亲，可以看到内心）
  /// - intimacy > 0.4 && familiarity > 0.5 → private（亲密朋友，知道私密信息）
  /// - familiarity > 0.3 → social（认识的人，知道社交信息）
  /// - 其他 → public（陌生人，只知道公开信息）
  static PerceptionLevel autoLevel(double intimacy, double familiarity) {
    // 至亲：高亲密 + 高熟悉
    if (intimacy > 0.7 && familiarity > 0.7) return PerceptionLevel.inner;

    // 亲密：中高亲密 + 中高熟悉
    if (intimacy > 0.4 && familiarity > 0.5) return PerceptionLevel.private;

    // 社交：有一定熟悉度
    if (familiarity > 0.3) return PerceptionLevel.social;

    // 公开：陌生人或点头之交
    return PerceptionLevel.public;
  }

  /// 批量构建对多个角色的感知（用于社交决策）
  ///
  /// 返回每个目标角色的感知快照，可直接用于 LLM 社交决策提示词。
  static List<PerceptionSnapshot> buildBatchPerception({
    required Map<String, dynamic> observer,
    required List<Map<String, dynamic>> targets,
    required Map<String, Map<String, dynamic>> relationships,
  }) {
    final snapshots = <PerceptionSnapshot>[];

    for (final target in targets) {
      final targetId = target['id'] as String? ?? '';
      final targetName = target['name'] as String? ?? '未知';
      final relationship = relationships[targetId] ?? {};

      final content = buildPerception(
        observerProfile: observer,
        targetProfile: target,
        relationship: relationship,
      );

      final level = autoLevel(
        (relationship['intimacy'] as num?)?.toDouble() ?? 0.0,
        (relationship['familiarity'] as num?)?.toDouble() ?? 0.0,
      );

      snapshots.add(PerceptionSnapshot(
        targetId: targetId,
        targetName: targetName,
        level: level,
        content: content,
        timestamp: DateTime.now(),
      ));
    }

    return snapshots;
  }

  /// 从 LifeProfile 和 RelationshipGraph 构建感知（类型安全版本）
  static String buildPerceptionFromModels({
    required LifeProfile observer,
    required LifeProfile target,
    required RelationshipGraph? relationship,
  }) {
    return buildPerception(
      observerProfile: observer.toJson(),
      targetProfile: _lifeProfileToPerceptionMap(target),
      relationship: relationship?.toJson() ?? {},
    );
  }

  /// 从 LifeProfile 和 RelationshipGraph 构建批量感知
  static List<PerceptionSnapshot> buildBatchPerceptionFromModels({
    required LifeProfile observer,
    required List<LifeProfile> targets,
    required Map<String, RelationshipGraph> relationships,
  }) {
    return buildBatchPerception(
      observer: observer.toJson(),
      targets: targets.map(_lifeProfileToPerceptionMap).toList(),
      relationships: relationships.map(
        (key, graph) => MapEntry(key, graph.toJson()),
      ),
    );
  }

  // ═══════════════════════════════════════════
  // 感知层级构建
  // ═══════════════════════════════════════════

  /// 构建公开层信息（所有人都能看见）
  ///
  /// 内容：名字、年龄、性别、性格标签（非精确值）、当前状态、最近社交摘要
  static String _buildPublicInfo(Map<String, dynamic> target) {
    final buffer = StringBuffer();
    final name = target['name'] as String? ?? '未知';
    final age = target['biologicalAge'] as int? ?? 0;
    final stage = target['currentStage'] as String? ?? '';

    buffer.writeln('姓名：$name');
    buffer.writeln('年龄：$age岁${stage.isNotEmpty ? '（$stage）' : ''}');

    // 性格标签（粗略描述，不暴露精确数值）
    final personality = target['personalityState'] as Map<String, dynamic>? ?? {};
    final traits = _personalityToTraits(personality);
    if (traits.isNotEmpty) {
      buffer.writeln('性格印象：${traits.join('、')}');
    }

    // 当前状态
    final emotional = target['emotionalState'] as Map<String, dynamic>? ?? {};
    final mood = emotional['currentMood'] as String? ?? emotional['mood'] as String?;
    if (mood != null && mood.isNotEmpty) {
      buffer.writeln('当前情绪：$mood');
    }

    // 最近社交摘要（公开可见的部分）
    final lifeEvents = target['lifeEvents'] as List<dynamic>? ?? [];
    final recentPublic = lifeEvents
        .where((e) => (e as Map<String, dynamic>)['isPublic'] == true)
        .take(2)
        .toList();
    if (recentPublic.isNotEmpty) {
      buffer.writeln('最近动态：');
      for (final event in recentPublic) {
        final desc = (event as Map<String, dynamic>)['description'] as String? ?? '';
        if (desc.isNotEmpty) buffer.writeln('  - $desc');
      }
    }

    return buffer.toString();
  }

  /// 构建社交层信息（好友可见）
  ///
  /// 内容：更详细人设、情绪状态、关系网络、与用户的互动摘要
  static String _buildSocialInfo(
    Map<String, dynamic> target,
    Map<String, dynamic> relationship,
  ) {
    final buffer = StringBuffer();

    // 详细人设
    final worldview = target['worldviewState'] as Map<String, dynamic>? ?? {};
    final values = worldview['coreValues'] as List<dynamic>?;
    if (values != null && values.isNotEmpty) {
      buffer.writeln('价值观：${values.join('、')}');
    }

    final desires = worldview['coreDesire'] as String? ?? worldview['desire'] as String?;
    if (desires != null && desires.isNotEmpty) {
      buffer.writeln('内心渴望：$desires');
    }

    // 情绪状态详情
    final emotional = target['emotionalState'] as Map<String, dynamic>? ?? {};
    final energy = emotional['energy'] as num?;
    if (energy != null) {
      final energyDesc = energy > 0.7 ? '精力充沛' : energy > 0.4 ? '状态一般' : '疲惫';
      buffer.writeln('精力状态：$energyDesc');
    }

    // 关系网络（只知道公共关系）
    final relationships = target['relationships'] as List<dynamic>? ?? {};
    if (relationships is List && relationships.isNotEmpty) {
      buffer.writeln('社交圈：');
      for (final rel in relationships.take(3)) {
        final relMap = rel as Map<String, dynamic>;
        final relName = relMap['name'] as String? ?? '某人';
        final relType = relMap['type'] as String? ?? '认识';
        buffer.writeln('  - $relName（$relType）');
      }
    }

    // 与观察者的互动摘要
    final lastInteraction = relationship['lastInteraction'] as String?;
    if (lastInteraction != null && lastInteraction.isNotEmpty) {
      buffer.writeln('最近互动：$lastInteraction');
    }

    return buffer.toString();
  }

  /// 构建私密层信息（足够亲密才可见）
  ///
  /// 内容：精确性格数值、三观详情、内心想法
  static String _buildPrivateInfo(Map<String, dynamic> target) {
    final buffer = StringBuffer();

    // 精确性格数值
    final personality = target['personalityState'] as Map<String, dynamic>? ?? {};
    if (personality.isNotEmpty) {
      buffer.writeln('性格详细：');
      buffer.writeln('  开放性：${_formatValue(personality['openness'])}');
      buffer.writeln('  尽责性：${_formatValue(personality['conscientiousness'])}');
      buffer.writeln('  外向性：${_formatValue(personality['extraversion'])}');
      buffer.writeln('  宜人性：${_formatValue(personality['agreeableness'])}');
      buffer.writeln('  神经质：${_formatValue(personality['neuroticism'])}');
    }

    // 三观详情
    final worldview = target['worldviewState'] as Map<String, dynamic>? ?? {};
    final worldviewText = worldview['worldview'] as String? ?? worldview['description'] as String?;
    if (worldviewText != null && worldviewText.isNotEmpty) {
      buffer.writeln('世界观：$worldviewText');
    }

    final lifeGoal = worldview['lifeGoal'] as String? ?? worldview['goal'] as String?;
    if (lifeGoal != null && lifeGoal.isNotEmpty) {
      buffer.writeln('人生目标：$lifeGoal');
    }

    // 内心想法（最近的几条）
    final innerThoughts = target['innerThoughts'] as List<dynamic>? ?? [];
    if (innerThoughts.isNotEmpty) {
      buffer.writeln('最近想法：');
      for (final thought in innerThoughts.take(2)) {
        final thoughtMap = thought as Map<String, dynamic>;
        final content = thoughtMap['content'] as String? ?? '';
        if (content.isNotEmpty) buffer.writeln('  - $content');
      }
    }

    return buffer.toString();
  }

  /// 构建内心层信息（仅角色自己 + 用户）
  ///
  /// 内容：内心独白、隐藏动机、未表达情感、身份认同危机
  static String _buildInnerInfo(Map<String, dynamic> target) {
    final buffer = StringBuffer();

    // 内心独白
    final innerMonologue = target['innerMonologue'] as String? ??
        (target['identity'] as Map<String, dynamic>?)?['innerMonologue'] as String?;
    if (innerMonologue != null && innerMonologue.isNotEmpty) {
      buffer.writeln('内心独白：$innerMonologue');
    }

    // 隐藏动机
    final hiddenMotives = target['hiddenMotives'] as List<dynamic>? ??
        (target['identity'] as Map<String, dynamic>?)?['hiddenMotives'] as List<dynamic>?;
    if (hiddenMotives != null && hiddenMotives.isNotEmpty) {
      buffer.writeln('隐藏动机：');
      for (final motive in hiddenMotives) {
        if (motive is String && motive.isNotEmpty) {
          buffer.writeln('  - $motive');
        }
      }
    }

    // 未表达情感
    final unexpressedEmotions = target['unexpressedEmotions'] as List<dynamic>? ??
        (target['emotionalState'] as Map<String, dynamic>?)?['unexpressed'] as List<dynamic>?;
    if (unexpressedEmotions != null && unexpressedEmotions.isNotEmpty) {
      buffer.writeln('未表达的情感：');
      for (final emotion in unexpressedEmotions) {
        if (emotion is String && emotion.isNotEmpty) {
          buffer.writeln('  - $emotion');
        }
      }
    }

    // 身份认同
    final identity = target['identity'] as Map<String, dynamic>? ?? {};
    final identityCrisis = identity['crisis'] as String? ?? identity['identityCrisis'] as String?;
    if (identityCrisis != null && identityCrisis.isNotEmpty) {
      buffer.writeln('身份认同困惑：$identityCrisis');
    }

    final secretDesire = identity['secretDesire'] as String?;
    if (secretDesire != null && secretDesire.isNotEmpty) {
      buffer.writeln('秘密渴望：$secretDesire');
    }

    // 马斯洛需求状态（内心层才暴露）
    final maslow = target['maslowState'] as Map<String, dynamic>? ?? {};
    if (maslow.isNotEmpty) {
      final dominant = _getDominantNeed(maslow);
      if (dominant.isNotEmpty) {
        buffer.writeln('最迫切需求：$dominant');
      }
    }

    return buffer.toString();
  }

  // ═══════════════════════════════════════════
  // 内部辅助
  // ═══════════════════════════════════════════

  /// 从 LifeProfile 提取感知所需字段
  static Map<String, dynamic> _lifeProfileToPerceptionMap(LifeProfile profile) {
    return {
      'id': profile.id,
      'name': profile.name,
      'biologicalAge': profile.biologicalAge,
      'currentStage': profile.currentStage.label,
      'personalityState': profile.personalityState,
      'worldviewState': profile.worldviewState,
      'emotionalState': profile.emotionalState,
      'maslowState': profile.maslowState,
      'identity': profile.identity,
      'lifeEvents': profile.lifeEvents,
    };
  }

  /// 性格数值 → 性格标签（公开层用，不暴露精确值）
  static List<String> _personalityToTraits(Map<String, dynamic> personality) {
    final traits = <String>[];

    final openness = (personality['openness'] as num?)?.toDouble();
    if (openness != null) {
      if (openness > 0.7) traits.add('思想开放');
      if (openness < 0.3) traits.add('保守传统');
    }

    final conscientiousness =
        (personality['conscientiousness'] as num?)?.toDouble();
    if (conscientiousness != null) {
      if (conscientiousness > 0.7) traits.add('认真负责');
      if (conscientiousness < 0.3) traits.add('随性散漫');
    }

    final extraversion = (personality['extraversion'] as num?)?.toDouble();
    if (extraversion != null) {
      if (extraversion > 0.7) traits.add('外向活泼');
      if (extraversion < 0.3) traits.add('内向安静');
    }

    final agreeableness = (personality['agreeableness'] as num?)?.toDouble();
    if (agreeableness != null) {
      if (agreeableness > 0.7) traits.add('温和友善');
      if (agreeableness < 0.3) traits.add('冷漠固执');
    }

    final neuroticism = (personality['neuroticism'] as num?)?.toDouble();
    if (neuroticism != null) {
      if (neuroticism > 0.7) traits.add('敏感多虑');
      if (neuroticism < 0.3) traits.add('沉稳冷静');
    }

    // 衍生特质
    final courage = (personality['courage'] as num?)?.toDouble();
    if (courage != null && courage > 0.7) traits.add('勇敢');

    final empathy = (personality['empathy'] as num?)?.toDouble();
    if (empathy != null && empathy > 0.7) traits.add('有同理心');

    final ambition = (personality['ambition'] as num?)?.toDouble();
    if (ambition != null && ambition > 0.7) traits.add('有野心');

    final creativity = (personality['creativity'] as num?)?.toDouble();
    if (creativity != null && creativity > 0.7) traits.add('富有创造力');

    return traits;
  }

  /// 格式化数值为百分比
  static String _formatValue(dynamic value) {
    if (value == null) return '未知';
    final num? v = value is num ? value : num.tryParse(value.toString());
    if (v == null) return '未知';
    return '${(v * 100).toStringAsFixed(0)}%';
  }

  /// 从马斯洛需求状态获取最迫切需求
  static String _getDominantNeed(Map<String, dynamic> maslow) {
    final needs = <String, double>{};

    final survival = (maslow['survival'] as num?)?.toDouble();
    if (survival != null) needs['生存需求'] = survival;

    final safety = (maslow['safety'] as num?)?.toDouble();
    if (safety != null) needs['安全感'] = safety;

    final belonging = (maslow['belonging'] as num?)?.toDouble();
    if (belonging != null) needs['社交归属'] = belonging;

    final esteem = (maslow['esteem'] as num?)?.toDouble();
    if (esteem != null) needs['自尊认同'] = esteem;

    final selfActualization =
        (maslow['selfActualization'] as num?)?.toDouble();
    if (selfActualization != null) needs['自我实现'] = selfActualization;

    final transcendence = (maslow['transcendence'] as num?)?.toDouble();
    if (transcendence != null) needs['精神超越'] = transcendence;

    if (needs.isEmpty) return '';

    final dominant = needs.entries.reduce((a, b) => a.value > b.value ? a : b);
    return '${dominant.key}（${(dominant.value * 100).toStringAsFixed(0)}%）';
  }

  /// 感知级别标签
  static String _levelLabel(PerceptionLevel level) {
    switch (level) {
      case PerceptionLevel.public:
        return '公开';
      case PerceptionLevel.social:
        return '社交';
      case PerceptionLevel.private:
        return '私密';
      case PerceptionLevel.inner:
        return '内心';
    }
  }
}

/// LifeStage 扩展（label getter）
extension _LifeStageLabel on LifeStage {
  String get label {
    switch (this) {
      case LifeStage.infant:
        return '婴儿期';
      case LifeStage.toddler:
        return '幼儿期';
      case LifeStage.childhood:
        return '童年期';
      case LifeStage.teenage:
        return '青春期';
      case LifeStage.youngAdult:
        return '青年期';
      case LifeStage.adult:
        return '中年期';
      case LifeStage.senior:
        return '老年期';
      case LifeStage.elder:
        return '暮年';
    }
  }
}
