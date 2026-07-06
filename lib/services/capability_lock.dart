// ============================================================
// 全生命周期数字生命世界 — Phase 1
// 分段锁智系统：根据生命阶段限制能力与行为
// ============================================================

/// 能力等级（对应年龄区间）
enum CapabilityLevel {
  infant,  // 0-2岁
  toddler, // 3-5岁
  child,   // 6-11岁
  full,    // 12岁+
}

/// 能力约束集
///
/// 封装某个年龄阶段所有行为限制参数，供提示词引擎、行为引擎、社交系统等消费。
class CapabilityConstraints {
  /// 能否主动发起社交
  final bool canInitiateSocial;

  /// 能否使用完整语言
  final bool canUseFullLanguage;

  /// 能否发朋友圈
  final bool canPostMoments;

  /// 能否建立关系
  final bool canFormRelationships;

  /// 是否有三观
  final bool hasWorldview;

  /// 记忆保留率乘数（1.0 = 正常）
  final double memoryRetention;

  /// 遗忘速率乘数（1.0 = 正常，>1 = 加速遗忘）
  final double forgettingMultiplier;

  /// 允许的行为列表
  final List<String> allowedBehaviors;

  const CapabilityConstraints({
    required this.canInitiateSocial,
    required this.canUseFullLanguage,
    required this.canPostMoments,
    required this.canFormRelationships,
    required this.hasWorldview,
    required this.memoryRetention,
    required this.forgettingMultiplier,
    required this.allowedBehaviors,
  });
}

/// 分段锁智系统
///
/// 纯静态工具类，根据年龄返回能力约束。
/// 被提示词系统、社交系统、朋友圈系统、记忆系统等多处引用。
///
/// 锁智规则：
/// - 0-2岁：不能主动社交，不能用完整语言，不能发朋友圈，记忆保留率 ×0.2，遗忘速率 ×5
/// - 3-5岁：有限探索，只能和家人互动，三观未成型，记忆碎片化
/// - 6-11岁：解锁完整社交、入学、人格演化引擎启动
/// - 12岁+：全部解锁
class CapabilityLock {
  CapabilityLock._();

  // ── 各等级能力约束定义 ──

  static const CapabilityConstraints _infantConstraints = CapabilityConstraints(
    canInitiateSocial: false,
    canUseFullLanguage: false,
    canPostMoments: false,
    canFormRelationships: false,
    hasWorldview: false,
    memoryRetention: 0.2,
    forgettingMultiplier: 5.0,
    allowedBehaviors: [
      'cry',
      'sleep',
      'eat',
      'observe',
      'recognize_face',
      'respond_to_touch',
    ],
  );

  static const CapabilityConstraints _toddlerConstraints = CapabilityConstraints(
    canInitiateSocial: false,
    canUseFullLanguage: false,
    canPostMoments: false,
    canFormRelationships: true,
    hasWorldview: false,
    memoryRetention: 0.5,
    forgettingMultiplier: 3.0,
    allowedBehaviors: [
      'simple_talk',
      'play',
      'explore_nearby',
      'bond_family',
      'imitate',
      'ask_why',
      'draw',
      'build_blocks',
    ],
  );

  static const CapabilityConstraints _childConstraints = CapabilityConstraints(
    canInitiateSocial: true,
    canUseFullLanguage: true,
    canPostMoments: false,
    canFormRelationships: true,
    hasWorldview: false,
    memoryRetention: 0.8,
    forgettingMultiplier: 1.5,
    allowedBehaviors: [
      'full_conversation',
      'make_friends',
      'attend_school',
      'play_games',
      'read_books',
      'learn_skills',
      'family_activities',
      'homework',
      'group_play',
    ],
  );

  static const CapabilityConstraints _fullConstraints = CapabilityConstraints(
    canInitiateSocial: true,
    canUseFullLanguage: true,
    canPostMoments: true,
    canFormRelationships: true,
    hasWorldview: true,
    memoryRetention: 1.0,
    forgettingMultiplier: 1.0,
    allowedBehaviors: [
      'full_conversation',
      'deep_relationships',
      'post_moments',
      'independent_living',
      'career_pursuit',
      'worldview_formation',
      'romantic_relationships',
      'mentor_others',
      'all_social_activities',
    ],
  );

  // ── 公开 API ──

  /// 根据年龄返回能力约束
  static CapabilityConstraints getConstraints(int age) {
    final level = _ageToLevel(age);
    return _constraintsForLevel(level);
  }

  /// 检查某个行为是否被当前年龄允许
  static bool isAllowed(int age, String behavior) {
    final constraints = getConstraints(age);
    // 全解锁等级允许所有行为
    if (constraints.allowedBehaviors.contains('all_social_activities')) {
      return true;
    }
    return constraints.allowedBehaviors.contains(behavior);
  }

  /// 根据年龄返回能力等级
  static CapabilityLevel _ageToLevel(int age) {
    if (age <= 2) return CapabilityLevel.infant;
    if (age <= 5) return CapabilityLevel.toddler;
    if (age <= 11) return CapabilityLevel.child;
    return CapabilityLevel.full;
  }

  /// 根据能力等级返回约束
  static CapabilityConstraints _constraintsForLevel(CapabilityLevel level) {
    switch (level) {
      case CapabilityLevel.infant:
        return _infantConstraints;
      case CapabilityLevel.toddler:
        return _toddlerConstraints;
      case CapabilityLevel.child:
        return _childConstraints;
      case CapabilityLevel.full:
        return _fullConstraints;
    }
  }

  /// 获取能力等级的可读描述（调试/日志用）
  static String describeLevel(CapabilityLevel level) {
    switch (level) {
      case CapabilityLevel.infant:
        return '婴儿期 (0-2岁)：完全依赖，无自主能力';
      case CapabilityLevel.toddler:
        return '幼儿期 (3-5岁)：有限探索，仅限家庭互动';
      case CapabilityLevel.child:
        return '童年期 (6-11岁)：解锁社交与学习，人格引擎启动';
      case CapabilityLevel.full:
        return '完全体 (12岁+)：全部能力解锁';
    }
  }
}
