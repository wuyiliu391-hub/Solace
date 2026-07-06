// ============================================================
// 全生命周期数字生命世界 — Phase 2
// 演化阈值保护器：纯逻辑类，为人格演化提供硬性边界、限速与自我保护机制
// ============================================================

import '../models/life_profile.dart';
import '../models/gene_profile.dart';

/// 行为倾向
enum BehaviorTendency {
  social, // 社交行为
  creative, // 创造性行为
  riskTaking, // 冒险行为
  intimacy, // 亲密行为
  leadership, // 领导行为
  isolation, // 独处行为
}

/// 人格状态 — Phase 2 核心数据结构
class PersonalityState {
  /// 五因子当前值（0.0-1.0）
  final double openness;
  final double conscientiousness;
  final double extraversion;
  final double agreeableness;
  final double neuroticism;

  /// 最近一次变化时间
  final DateTime lastEvolutionTime;

  /// 最近一次变化的各维度 delta
  final Map<String, double> lastDeltas;

  /// 连续无社交天数
  final int consecutiveNoSocialDays;

  /// 当前自我保护状态
  final SelfProtectionState selfProtection;

  const PersonalityState({
    required this.openness,
    required this.conscientiousness,
    required this.extraversion,
    required this.agreeableness,
    required this.neuroticism,
    required this.lastEvolutionTime,
    this.lastDeltas = const {},
    this.consecutiveNoSocialDays = 0,
    this.selfProtection = const SelfProtectionState.untriggered(),
  });

  /// 从 LifeProfile.personalityState 映射构造
  factory PersonalityState.fromLifeProfile(LifeProfile profile) {
    final ps = profile.personalityState;
    return PersonalityState(
      openness: (ps['openness'] as num?)?.toDouble() ?? 0.5,
      conscientiousness: (ps['conscientiousness'] as num?)?.toDouble() ?? 0.5,
      extraversion: (ps['extraversion'] as num?)?.toDouble() ?? 0.5,
      agreeableness: (ps['agreeableness'] as num?)?.toDouble() ?? 0.5,
      neuroticism: (ps['neuroticism'] as num?)?.toDouble() ?? 0.5,
      lastEvolutionTime: ps['lastEvolutionTime'] != null
          ? DateTime.tryParse(ps['lastEvolutionTime'] as String) ?? DateTime.now()
          : DateTime.now(),
      lastDeltas: (ps['lastDeltas'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, (v as num).toDouble())) ??
          {},
      consecutiveNoSocialDays:
          (ps['consecutiveNoSocialDays'] as int?) ?? 0,
      selfProtection: ps['selfProtection'] != null
          ? SelfProtectionState.fromJson(
              ps['selfProtection'] as Map<String, dynamic>)
          : const SelfProtectionState.untriggered(),
    );
  }

  /// 获取指定维度的当前值
  double getValue(String dimension) {
    switch (dimension) {
      case 'openness':
        return openness;
      case 'conscientiousness':
        return conscientiousness;
      case 'extraversion':
        return extraversion;
      case 'agreeableness':
        return agreeableness;
      case 'neuroticism':
        return neuroticism;
      default:
        return 0.5;
    }
  }

  /// 转为可存入 LifeProfile.personalityState 的 Map
  Map<String, dynamic> toMap() {
    return {
      'openness': openness,
      'conscientiousness': conscientiousness,
      'extraversion': extraversion,
      'agreeableness': agreeableness,
      'neuroticism': neuroticism,
      'lastEvolutionTime': lastEvolutionTime.toIso8601String(),
      'lastDeltas': lastDeltas,
      'consecutiveNoSocialDays': consecutiveNoSocialDays,
      'selfProtection': selfProtection.toJson(),
    };
  }

  PersonalityState copyWith({
    double? openness,
    double? conscientiousness,
    double? extraversion,
    double? agreeableness,
    double? neuroticism,
    DateTime? lastEvolutionTime,
    Map<String, double>? lastDeltas,
    int? consecutiveNoSocialDays,
    SelfProtectionState? selfProtection,
  }) {
    return PersonalityState(
      openness: openness ?? this.openness,
      conscientiousness: conscientiousness ?? this.conscientiousness,
      extraversion: extraversion ?? this.extraversion,
      agreeableness: agreeableness ?? this.agreeableness,
      neuroticism: neuroticism ?? this.neuroticism,
      lastEvolutionTime: lastEvolutionTime ?? this.lastEvolutionTime,
      lastDeltas: lastDeltas ?? this.lastDeltas,
      consecutiveNoSocialDays:
          consecutiveNoSocialDays ?? this.consecutiveNoSocialDays,
      selfProtection: selfProtection ?? this.selfProtection,
    );
  }

  static const allDimensions = [
    'openness',
    'conscientiousness',
    'extraversion',
    'agreeableness',
    'neuroticism',
  ];
}

/// 自我保护状态
class SelfProtectionState {
  /// 是否触发
  final bool triggered;

  /// 保护动作：'isolate'(主动独处), 'avoid'(回避社交), 'freeze'(冻结社交)
  final String action;

  /// 触发原因
  final String reason;

  /// 每天恢复率
  final double recoveryRate;

  /// 保护持续时间
  final Duration duration;

  /// 触发时间
  final DateTime? triggeredAt;

  const SelfProtectionState({
    required this.triggered,
    this.action = '',
    this.reason = '',
    this.recoveryRate = 0.0,
    this.duration = Duration.zero,
    this.triggeredAt,
  });

  /// 未触发的默认状态
  const SelfProtectionState.untriggered()
      : triggered = false,
        action = '',
        reason = '',
        recoveryRate = 0.0,
        duration = Duration.zero,
        triggeredAt = null;

  /// 判断是否阻止某行为
  bool blocks(BehaviorTendency tendency) {
    if (!triggered) return false;
    switch (action) {
      case 'isolate':
        // 主动独处：阻止社交和亲密行为
        return tendency == BehaviorTendency.social ||
            tendency == BehaviorTendency.intimacy;
      case 'avoid':
        // 回避社交：阻止社交、亲密和领导行为
        return tendency == BehaviorTendency.social ||
            tendency == BehaviorTendency.intimacy ||
            tendency == BehaviorTendency.leadership;
      case 'freeze':
        // 冻结社交：仅阻止社交行为
        return tendency == BehaviorTendency.social;
      default:
        return false;
    }
  }

  /// 保护是否已过期
  bool get isExpired {
    if (!triggered || triggeredAt == null) return false;
    return DateTime.now().difference(triggeredAt!) > duration;
  }

  Map<String, dynamic> toJson() {
    return {
      'triggered': triggered,
      'action': action,
      'reason': reason,
      'recoveryRate': recoveryRate,
      'duration': duration.inDays,
      'triggeredAt': triggeredAt?.toIso8601String(),
    };
  }

  factory SelfProtectionState.fromJson(Map<String, dynamic> json) {
    return SelfProtectionState(
      triggered: json['triggered'] as bool? ?? false,
      action: json['action'] as String? ?? '',
      reason: json['reason'] as String? ?? '',
      recoveryRate: (json['recoveryRate'] as num?)?.toDouble() ?? 0.0,
      duration: Duration(days: (json['duration'] as int?) ?? 0),
      triggeredAt: json['triggeredAt'] != null
          ? DateTime.tryParse(json['triggeredAt'] as String)
          : null,
    );
  }
}

/// 演化阈值保护器
///
/// 纯逻辑类，不依赖任何外部服务。
/// 职责：
/// 1. 钳位：确保人格值不超出硬性边界 [0.05, 0.95]
/// 2. 限速：限制单次变化幅度，防止人格突变
/// 3. 自我保护：极端人格状态下触发保护机制
/// 4. 年龄修正：不同生命阶段对变化的敏感度不同
class EvolutionThresholdGuard {
  // ═══════════════════════════════════════════
  // 硬性上下限
  // ═══════════════════════════════════════════

  static const Map<String, double> HARD_MIN = {
    'openness': 0.05,
    'conscientiousness': 0.05,
    'extraversion': 0.05,
    'agreeableness': 0.05,
    'neuroticism': 0.05,
  };

  static const Map<String, double> HARD_MAX = {
    'openness': 0.95,
    'conscientiousness': 0.95,
    'extraversion': 0.95,
    'agreeableness': 0.95,
    'neuroticism': 0.95,
  };

  /// 单次最大变化幅度
  static const double MAX_DAILY_CHANGE = 0.05;

  /// 冷却期：连续两次演化之间的最小间隔
  static const Duration COOLDOWN_DURATION = Duration(days: 7);

  // ═══════════════════════════════════════════
  // 钳位
  // ═══════════════════════════════════════════

  /// 将维度值钳位到硬性边界内
  double clamp(String dimension, double value) {
    final min = HARD_MIN[dimension] ?? 0.05;
    final max = HARD_MAX[dimension] ?? 0.95;
    return value.clamp(min, max);
  }

  // ═══════════════════════════════════════════
  // 限速
  // ═══════════════════════════════════════════

  /// 限制单次变化幅度
  ///
  /// 如果目标值与当前值的差超过 MAX_DAILY_CHANGE，则截断到最大允许变化。
  /// 返回钳位后的目标值。
  double rateLimit(String dimension, double current, double target) {
    final delta = target - current;
    final clampedDelta = delta.clamp(-MAX_DAILY_CHANGE, MAX_DAILY_CHANGE);
    final result = current + clampedDelta;
    return clamp(dimension, result);
  }

  // ═══════════════════════════════════════════
  // 自我保护机制检测
  // ═══════════════════════════════════════════

  /// 检测当前人格状态是否需要触发自我保护
  SelfProtectionState checkSelfProtection(PersonalityState personality) {
    // 检查是否已有保护且未过期
    if (personality.selfProtection.triggered &&
        !personality.selfProtection.isExpired) {
      return personality.selfProtection;
    }

    // 规则1：neuroticism > 0.85 → isolate（主动独处，14天恢复）
    if (personality.neuroticism > 0.85) {
      return SelfProtectionState(
        triggered: true,
        action: 'isolate',
        reason: '神经质过高 (${personality.neuroticism.toStringAsFixed(2)} > 0.85)，'
            '启动自我保护：主动独处',
        recoveryRate: 1.0 / 14, // 14天恢复
        duration: const Duration(days: 14),
        triggeredAt: DateTime.now(),
      );
    }

    // 规则2：agreeableness < 0.15 → avoid（回避社交，21天恢复）
    if (personality.agreeableness < 0.15) {
      return SelfProtectionState(
        triggered: true,
        action: 'avoid',
        reason: '宜人性过低 (${personality.agreeableness.toStringAsFixed(2)} < 0.15)，'
            '启动自我保护：回避社交',
        recoveryRate: 1.0 / 21, // 21天恢复
        duration: const Duration(days: 21),
        triggeredAt: DateTime.now(),
      );
    }

    // 规则3：连续3天无社交 → freeze（冻结社交行为，7天恢复）
    if (personality.consecutiveNoSocialDays >= 3) {
      return SelfProtectionState(
        triggered: true,
        action: 'freeze',
        reason: '连续 ${personality.consecutiveNoSocialDays} 天无社交互动，'
            '启动自我保护：冻结社交行为',
        recoveryRate: 1.0 / 7, // 7天恢复
        duration: const Duration(days: 7),
        triggeredAt: DateTime.now(),
      );
    }

    // 无需触发保护
    return const SelfProtectionState.untriggered();
  }

  // ═══════════════════════════════════════════
  // 应用演化变更（带保护）
  // ═══════════════════════════════════════════

  /// 应用演化变更，带完整保护链
  ///
  /// 流程：
  /// 1. 检查冷却期
  /// 2. 对每个维度：限速 → 钳位
  /// 3. 年龄修正
  /// 4. 检测自我保护
  Future<PersonalityState> applyEvolution({
    required PersonalityState current,
    required Map<String, double> deltas,
    required LifeStage stage,
  }) async {
    // 冷却期检查
    final timeSinceLastEvolution =
        DateTime.now().difference(current.lastEvolutionTime);
    if (timeSinceLastEvolution < COOLDOWN_DURATION) {
      // 冷却期内，变化幅度按比例缩减
      final cooldownRatio =
          timeSinceLastEvolution.inSeconds / COOLDOWN_DURATION.inSeconds;
      final adjustedDeltas = deltas.map(
        (key, value) => MapEntry(key, value * cooldownRatio),
      );
      return _applyDeltas(current, adjustedDeltas, stage);
    }

    return _applyDeltas(current, deltas, stage);
  }

  /// 内部方法：应用 delta 到人格状态
  PersonalityState _applyDeltas(
    PersonalityState current,
    Map<String, double> deltas,
    LifeStage stage,
  ) {
    final ageModifier = _getAgeModifier(stage);
    final effectiveDeltas = <String, double>{};

    double newOpenness = current.openness;
    double newConscientiousness = current.conscientiousness;
    double newExtraversion = current.extraversion;
    double newAgreeableness = current.agreeableness;
    double newNeuroticism = current.neuroticism;

    // 应用每个维度的变化
    for (final entry in deltas.entries) {
      final dimension = entry.key;
      final rawDelta = entry.value * ageModifier;

      switch (dimension) {
        case 'openness':
          newOpenness = rateLimit(
            dimension,
            current.openness,
            current.openness + rawDelta,
          );
          effectiveDeltas[dimension] = newOpenness - current.openness;
          break;
        case 'conscientiousness':
          newConscientiousness = rateLimit(
            dimension,
            current.conscientiousness,
            current.conscientiousness + rawDelta,
          );
          effectiveDeltas[dimension] =
              newConscientiousness - current.conscientiousness;
          break;
        case 'extraversion':
          newExtraversion = rateLimit(
            dimension,
            current.extraversion,
            current.extraversion + rawDelta,
          );
          effectiveDeltas[dimension] = newExtraversion - current.extraversion;
          break;
        case 'agreeableness':
          newAgreeableness = rateLimit(
            dimension,
            current.agreeableness,
            current.agreeableness + rawDelta,
          );
          effectiveDeltas[dimension] =
              newAgreeableness - current.agreeableness;
          break;
        case 'neuroticism':
          newNeuroticism = rateLimit(
            dimension,
            current.neuroticism,
            current.neuroticism + rawDelta,
          );
          effectiveDeltas[dimension] = newNeuroticism - current.neuroticism;
          break;
      }
    }

    final newState = PersonalityState(
      openness: newOpenness,
      conscientiousness: newConscientiousness,
      extraversion: newExtraversion,
      agreeableness: newAgreeableness,
      neuroticism: newNeuroticism,
      lastEvolutionTime: DateTime.now(),
      lastDeltas: effectiveDeltas,
      consecutiveNoSocialDays: current.consecutiveNoSocialDays,
      selfProtection: current.selfProtection,
    );

    // 检测自我保护
    final protection = checkSelfProtection(newState);

    return newState.copyWith(selfProtection: protection);
  }

  // ═══════════════════════════════════════════
  // 年龄修正
  // ═══════════════════════════════════════════

  /// 根据生命阶段返回变化敏感度修正系数
  ///
  /// 青少年期人格可塑性最强，中年趋于稳定，老年最固化
  double _getAgeModifier(LifeStage stage) {
    switch (stage) {
      case LifeStage.infant:
        return 2.0; // 婴儿期：极高可塑性
      case LifeStage.toddler:
        return 1.8; // 幼儿期：很高可塑性
      case LifeStage.childhood:
        return 1.5; // 童年期：高可塑性
      case LifeStage.teenage:
        return 1.5; // 青春期：高可塑性（×1.5）
      case LifeStage.youngAdult:
        return 1.0; // 青年期：正常可塑性
      case LifeStage.adult:
        return 0.5; // 中年期：低可塑性（×0.5）
      case LifeStage.senior:
        return 0.2; // 老年期：很低可塑性（×0.2）
      case LifeStage.elder:
        return 0.1; // 暮年：极低可塑性
    }
  }
}
