// ============================================================
// 全生命周期数字生命世界 — Phase 2
// 马斯洛需求动机内核：驱动数字生命的行为决策
// ============================================================

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:yaml/yaml.dart';
import '../models/life_profile.dart';
import '../models/gene_profile.dart';

// ─────────────────────────────────────────────────
// 数据模型
// ─────────────────────────────────────────────────

/// 马斯洛需求层级
enum MaslowLayer {
  survival,          // 生理需求
  safety,            // 安全需求
  belonging,         // 归属与爱
  esteem,            // 尊重需求
  selfActualization, // 自我实现
  transcendence,     // 精神超越
}

/// 社交上下文 — 描述角色当前的社交环境
class SocialContext {
  final int daysSinceLastSocial;     // 距上次社交的天数
  final bool hasIntimateRelation;    // 是否有亲密关系
  final bool recentlyIgnored;        // 最近是否被忽视
  final bool recentlyPraised;        // 最近是否被赞美
  final bool hasNewcomer;            // 社交圈是否有新人
  final bool inDanger;               // 是否处于危险中
  final bool hasShelter;             // 是否有庇护所
  final bool hasFood;                // 食物是否充足
  final bool recentlyLostSomeone;    // 最近是否失去某人
  final bool hasLifeGoal;            // 是否有人生目标
  final bool isExploring;            // 是否在探索中
  final double environmentalSafety;  // 环境安全度 0-1

  const SocialContext({
    this.daysSinceLastSocial = 0,
    this.hasIntimateRelation = false,
    this.recentlyIgnored = false,
    this.recentlyPraised = false,
    this.hasNewcomer = false,
    this.inDanger = false,
    this.hasShelter = true,
    this.hasFood = true,
    this.recentlyLostSomeone = false,
    this.hasLifeGoal = false,
    this.isExploring = false,
    this.environmentalSafety = 0.5,
  });

  Map<String, dynamic> toJson() => {
        'daysSinceLastSocial': daysSinceLastSocial,
        'hasIntimateRelation': hasIntimateRelation,
        'recentlyIgnored': recentlyIgnored,
        'recentlyPraised': recentlyPraised,
        'hasNewcomer': hasNewcomer,
        'inDanger': inDanger,
        'hasShelter': hasShelter,
        'hasFood': hasFood,
        'recentlyLostSomeone': recentlyLostSomeone,
        'hasLifeGoal': hasLifeGoal,
        'isExploring': isExploring,
        'environmentalSafety': environmentalSafety,
      };

  factory SocialContext.fromJson(Map<String, dynamic> json) => SocialContext(
        daysSinceLastSocial: json['daysSinceLastSocial'] as int? ?? 0,
        hasIntimateRelation: json['hasIntimateRelation'] as bool? ?? false,
        recentlyIgnored: json['recentlyIgnored'] as bool? ?? false,
        recentlyPraised: json['recentlyPraised'] as bool? ?? false,
        hasNewcomer: json['hasNewcomer'] as bool? ?? false,
        inDanger: json['inDanger'] as bool? ?? false,
        hasShelter: json['hasShelter'] as bool? ?? true,
        hasFood: json['hasFood'] as bool? ?? true,
        recentlyLostSomeone: json['recentlyLostSomeone'] as bool? ?? false,
        hasLifeGoal: json['hasLifeGoal'] as bool? ?? false,
        isExploring: json['isExploring'] as bool? ?? false,
        environmentalSafety:
            (json['environmentalSafety'] as num?)?.toDouble() ?? 0.5,
      );
}

/// 马斯洛需求状态 — 六层需求的当前值
class MaslowState {
  double survival;           // 生存需求 0-1
  double safety;             // 安全感 0-1
  double belonging;          // 社交归属 0-1
  double esteem;             // 自尊 0-1
  double selfActualization;  // 自我实现 0-1
  double transcendence;      // 精神超越 0-1

  MaslowState({
    this.survival = 0.5,
    this.safety = 0.5,
    this.belonging = 0.5,
    this.esteem = 0.5,
    this.selfActualization = 0.3,
    this.transcendence = 0.1,
  });

  /// 获取当前最强烈的需求层级
  MaslowLayer get dominantNeed {
    final values = {
      MaslowLayer.survival: survival,
      MaslowLayer.safety: safety,
      MaslowLayer.belonging: belonging,
      MaslowLayer.esteem: esteem,
      MaslowLayer.selfActualization: selfActualization,
      MaslowLayer.transcendence: transcendence,
    };
    // 返回值最高的需求（最迫切的未满足需求）
    return values.entries.reduce((a, b) => a.value > b.value ? a : b).key;
  }

  /// 获取某一层需求的当前值
  double layerValue(MaslowLayer layer) {
    switch (layer) {
      case MaslowLayer.survival:
        return survival;
      case MaslowLayer.safety:
        return safety;
      case MaslowLayer.belonging:
        return belonging;
      case MaslowLayer.esteem:
        return esteem;
      case MaslowLayer.selfActualization:
        return selfActualization;
      case MaslowLayer.transcendence:
        return transcendence;
    }
  }

  /// 设置某一层需求的值
  void setLayerValue(MaslowLayer layer, double value) {
    final clamped = value.clamp(0.0, 1.0);
    switch (layer) {
      case MaslowLayer.survival:
        survival = clamped;
        break;
      case MaslowLayer.safety:
        safety = clamped;
        break;
      case MaslowLayer.belonging:
        belonging = clamped;
        break;
      case MaslowLayer.esteem:
        esteem = clamped;
        break;
      case MaslowLayer.selfActualization:
        selfActualization = clamped;
        break;
      case MaslowLayer.transcendence:
        transcendence = clamped;
        break;
    }
  }

  Map<String, dynamic> toJson() => {
        'survival': survival,
        'safety': safety,
        'belonging': belonging,
        'esteem': esteem,
        'selfActualization': selfActualization,
        'transcendence': transcendence,
      };

  factory MaslowState.fromJson(Map<String, dynamic> json) => MaslowState(
        survival: (json['survival'] as num?)?.toDouble() ?? 0.5,
        safety: (json['safety'] as num?)?.toDouble() ?? 0.5,
        belonging: (json['belonging'] as num?)?.toDouble() ?? 0.5,
        esteem: (json['esteem'] as num?)?.toDouble() ?? 0.5,
        selfActualization:
            (json['selfActualization'] as num?)?.toDouble() ?? 0.3,
        transcendence: (json['transcendence'] as num?)?.toDouble() ?? 0.1,
      );

  @override
  String toString() =>
      'MaslowState(survival=$survival, safety=$safety, belonging=$belonging, '
      'esteem=$esteem, selfActualization=$selfActualization, transcendence=$transcendence)';
}

/// 行为倾向 — 需求驱动的具体行为
class BehaviorTendency {
  /// 行为类型: 'socialize', 'seek_comfort', 'prove_self',
  /// 'pursue_dream', 'philosophize', etc.
  final String type;

  /// 优先级 0-1
  final double priority;

  /// 触发原因描述
  final String reason;

  /// 来源需求层级
  final MaslowLayer sourceLayer;

  const BehaviorTendency({
    required this.type,
    required this.priority,
    required this.reason,
    required this.sourceLayer,
  });

  Map<String, dynamic> toJson() => {
        'type': type,
        'priority': priority,
        'reason': reason,
        'sourceLayer': sourceLayer.name,
      };
}

// ─────────────────────────────────────────────────
// 配置数据
// ─────────────────────────────────────────────────

/// 马斯洛需求配置
class _MaslowConfig {
  final Map<MaslowLayer, double> growthRate;
  final double decayRate;
  final Map<MaslowLayer, double> behaviorWeight;

  const _MaslowConfig({
    required this.growthRate,
    required this.decayRate,
    required this.behaviorWeight,
  });

  factory _MaslowConfig.defaults() => _MaslowConfig(
        growthRate: {
          MaslowLayer.survival: 0.1,
          MaslowLayer.safety: 0.08,
          MaslowLayer.belonging: 0.06,
          MaslowLayer.esteem: 0.05,
          MaslowLayer.selfActualization: 0.03,
          MaslowLayer.transcendence: 0.01,
        },
        decayRate: 0.05,
        behaviorWeight: {
          MaslowLayer.survival: 0.95,
          MaslowLayer.safety: 0.85,
          MaslowLayer.belonging: 0.70,
          MaslowLayer.esteem: 0.55,
          MaslowLayer.selfActualization: 0.40,
          MaslowLayer.transcendence: 0.25,
        },
      );
}

// ─────────────────────────────────────────────────
// 需求→行为映射表
// ─────────────────────────────────────────────────

const Map<MaslowLayer, List<String>> _needToBehaviors = {
  MaslowLayer.survival: ['seek_food', 'seek_rest', 'avoid_danger'],
  MaslowLayer.safety: ['seek_protection', 'avoid_conflict', 'heal_trauma'],
  MaslowLayer.belonging: ['socialize', 'seek_friendship', 'seek_romance'],
  MaslowLayer.esteem: ['prove_self', 'seek_recognition', 'compete'],
  MaslowLayer.selfActualization: [
    'pursue_dream',
    'help_others',
    'master_skill',
  ],
  MaslowLayer.transcendence: [
    'philosophize',
    'seek_meaning',
    'consider_immortality',
  ],
};

/// 各层级对应的需求描述（用于 reason 生成）
const Map<MaslowLayer, String> _needDescriptions = {
  MaslowLayer.survival: '生存需求',
  MaslowLayer.safety: '安全感',
  MaslowLayer.belonging: '社交归属',
  MaslowLayer.esteem: '自尊认同',
  MaslowLayer.selfActualization: '自我实现',
  MaslowLayer.transcendence: '精神超越',
};

// ─────────────────────────────────────────────────
// 核心内核
// ─────────────────────────────────────────────────

/// 马斯洛需求动机内核
///
/// 职责：
/// - 根据生命档案和社交环境评估当前需求状态
/// - 驱动行为倾向决策
/// - 每次心跳更新需求值
class MaslowMotivationKernel {
  _MaslowConfig _config = _MaslowConfig.defaults();


  // ─────────────────────────────────────────────────
  // 配置加载
  // ─────────────────────────────────────────────────

  /// 从配置文件加载参数
  ///
  /// 优先从 assets 加载，失败则使用默认值。
  Future<void> loadConfig() async {
    try {
      final yamlString = await rootBundle.loadString(
        'world/evolution_rules.yaml',
      );
      final yaml = loadYaml(yamlString);

      final maslowSection = yaml['maslow'];
      if (maslowSection == null) {
        debugPrint('MaslowKernel: 配置文件中未找到 maslow 段，使用默认值');
        return;
      }

      final growthRateMap = <MaslowLayer, double>{};
      final growthRate = maslowSection['growthRate'];
      if (growthRate is YamlMap) {
        growthRateMap[MaslowLayer.survival] =
            (growthRate['survival'] as num?)?.toDouble() ?? 0.1;
        growthRateMap[MaslowLayer.safety] =
            (growthRate['safety'] as num?)?.toDouble() ?? 0.08;
        growthRateMap[MaslowLayer.belonging] =
            (growthRate['belonging'] as num?)?.toDouble() ?? 0.06;
        growthRateMap[MaslowLayer.esteem] =
            (growthRate['esteem'] as num?)?.toDouble() ?? 0.05;
        growthRateMap[MaslowLayer.selfActualization] =
            (growthRate['selfActualization'] as num?)?.toDouble() ?? 0.03;
        growthRateMap[MaslowLayer.transcendence] =
            (growthRate['transcendence'] as num?)?.toDouble() ?? 0.01;
      }

      final behaviorWeightMap = <MaslowLayer, double>{};
      final behaviorWeight = maslowSection['behaviorWeight'];
      if (behaviorWeight is YamlMap) {
        behaviorWeightMap[MaslowLayer.survival] =
            (behaviorWeight['survival'] as num?)?.toDouble() ?? 0.95;
        behaviorWeightMap[MaslowLayer.safety] =
            (behaviorWeight['safety'] as num?)?.toDouble() ?? 0.85;
        behaviorWeightMap[MaslowLayer.belonging] =
            (behaviorWeight['belonging'] as num?)?.toDouble() ?? 0.70;
        behaviorWeightMap[MaslowLayer.esteem] =
            (behaviorWeight['esteem'] as num?)?.toDouble() ?? 0.55;
        behaviorWeightMap[MaslowLayer.selfActualization] =
            (behaviorWeight['selfActualization'] as num?)?.toDouble() ?? 0.40;
        behaviorWeightMap[MaslowLayer.transcendence] =
            (behaviorWeight['transcendence'] as num?)?.toDouble() ?? 0.25;
      }

      _config = _MaslowConfig(
        growthRate: growthRateMap.isNotEmpty
            ? growthRateMap
            : _MaslowConfig.defaults().growthRate,
        decayRate: (maslowSection['decayRate'] as num?)?.toDouble() ?? 0.05,
        behaviorWeight: behaviorWeightMap.isNotEmpty
            ? behaviorWeightMap
            : _MaslowConfig.defaults().behaviorWeight,
      );

      debugPrint('MaslowKernel: 配置加载完成');
    } catch (e) {
      debugPrint('MaslowKernel: 配置加载失败，使用默认值 — $e');
      _config = _MaslowConfig.defaults();
    }
  }

  // ─────────────────────────────────────────────────
  // 核心方法
  // ─────────────────────────────────────────────────

  /// 评估角色当前的马斯洛需求状态
  ///
  /// 综合生命档案（年龄、人格、身体状态）和社交环境，
  /// 生成当前的需求快照。
  MaslowState evaluate(LifeProfile profile, SocialContext context) {
    // 从已有状态恢复，或初始化默认值
    final state = profile.maslowState.isNotEmpty
        ? MaslowState.fromJson(profile.maslowState)
        : MaslowState();

    // 根据生命阶段调整基线
    _applyStageBaseline(state, profile.currentStage);

    // 根据社交上下文修正
    _applySocialContext(state, context);

    // 根据人格五因子微调
    _applyPersonalityBias(state, profile.genes);

    return state;
  }

  /// 获取最强烈需求对应的行为倾向
  ///
  /// 返回按优先级排序的行为列表。所有六层需求都会产生行为倾向，
  /// 但优先级 = 需求值 × 行为权重。
  List<BehaviorTendency> getBehaviorTendencies(
    MaslowState maslow,
    LifeProfile profile,
  ) {
    final tendencies = <BehaviorTendency>[];

    for (final layer in MaslowLayer.values) {
      final needValue = maslow.layerValue(layer);
      final weight = _config.behaviorWeight[layer] ?? 0.5;
      final priority = needValue * weight;

      // 只有需求值超过阈值才产生行为倾向
      if (priority < 0.15) continue;

      final behaviors = _needToBehaviors[layer] ?? [];
      final description = _needDescriptions[layer] ?? layer.name;

      for (final behavior in behaviors) {
        // 对每个行为附加微小随机偏移，避免完全同质化
        final adjustedPriority = priority.clamp(0.0, 1.0);

        tendencies.add(BehaviorTendency(
          type: behavior,
          priority: adjustedPriority,
          reason: '$description未满足（${(needValue * 100).toStringAsFixed(0)}%）',
          sourceLayer: layer,
        ));
      }
    }

    // 按优先级降序排列
    tendencies.sort((a, b) => b.priority.compareTo(a.priority));

    return tendencies;
  }

  /// 每次心跳更新需求值
  ///
  /// 核心逻辑：
  /// 1. 未满足的需求自然增长
  /// 2. 已满足的需求自然衰减
  /// 3. 社交上下文实时修正
  /// 4. 年龄阶段修正增长速率
  void tick(
    MaslowState maslow,
    LifeProfile profile,
    SocialContext context,
  ) {
    final growthRate = _config.growthRate;
    final decayRate = _config.decayRate;

    // 年龄修正系数（年轻时变化更快）
    final ageModifier = _ageVolatilityModifier(profile.currentStage);

    for (final layer in MaslowLayer.values) {
      final current = maslow.layerValue(layer);
      final rate = (growthRate[layer] ?? 0.05) * ageModifier;

      double delta;

      if (_isNeedSatisfied(layer, context)) {
        // 需求被满足 → 衰减（需求值降低 = 更满足）
        delta = -decayRate * ageModifier;
      } else {
        // 需求未被满足 → 增长（需求值升高 = 更迫切）
        delta = rate;
      }

      // 社交上下文实时修正
      delta += _contextualDelta(layer, context, current);

      // 应用变化，钳制到 [0, 1]
      final newValue = (current + delta).clamp(0.0, 1.0);
      maslow.setLayerValue(layer, newValue);
    }
  }

  // ─────────────────────────────────────────────────
  // 内部方法
  // ─────────────────────────────────────────────────

  /// 根据生命阶段调整需求基线
  void _applyStageBaseline(MaslowState state, LifeStage stage) {
    switch (stage) {
      case LifeStage.infant:
        // 婴儿：生存和安全需求极高
        state.survival = _nudge(state.survival, 0.8);
        state.safety = _nudge(state.safety, 0.7);
        break;
      case LifeStage.toddler:
        state.survival = _nudge(state.survival, 0.6);
        state.safety = _nudge(state.safety, 0.6);
        state.belonging = _nudge(state.belonging, 0.5);
        break;
      case LifeStage.childhood:
        state.belonging = _nudge(state.belonging, 0.6);
        state.esteem = _nudge(state.esteem, 0.4);
        break;
      case LifeStage.teenage:
        // 青春期：归属感和自尊需求突出
        state.belonging = _nudge(state.belonging, 0.7);
        state.esteem = _nudge(state.esteem, 0.7);
        state.selfActualization = _nudge(state.selfActualization, 0.3);
        break;
      case LifeStage.youngAdult:
        state.esteem = _nudge(state.esteem, 0.6);
        state.selfActualization = _nudge(state.selfActualization, 0.5);
        break;
      case LifeStage.adult:
        state.selfActualization = _nudge(state.selfActualization, 0.6);
        state.transcendence = _nudge(state.transcendence, 0.3);
        break;
      case LifeStage.senior:
        state.transcendence = _nudge(state.transcendence, 0.5);
        state.belonging = _nudge(state.belonging, 0.5);
        break;
      case LifeStage.elder:
        // 暮年：精神超越需求凸显
        state.transcendence = _nudge(state.transcendence, 0.7);
        state.belonging = _nudge(state.belonging, 0.6);
        break;
    }
  }

  /// 根据社交上下文修正需求
  void _applySocialContext(MaslowState state, SocialContext context) {
    // 危险环境 → 安全需求飙升
    if (context.inDanger) {
      state.survival = _nudge(state.survival, 0.9);
      state.safety = _nudge(state.safety, 0.85);
    }

    // 缺少食物/住所 → 生存需求飙升
    if (!context.hasFood) {
      state.survival = _nudge(state.survival, 0.85);
    }
    if (!context.hasShelter) {
      state.safety = _nudge(state.safety, 0.75);
    }

    // 长期无社交 → 归属需求飙升
    if (context.daysSinceLastSocial > 3) {
      final boost = (context.daysSinceLastSocial * 0.05).clamp(0.0, 0.4);
      state.belonging = _nudge(state.belonging, state.belonging + boost);
    }

    // 被忽视 → 自尊需求上升
    if (context.recentlyIgnored) {
      state.esteem = _nudge(state.esteem, state.esteem + 0.15);
    }

    // 被赞美 → 自尊需求下降（被满足）
    if (context.recentlyPraised) {
      state.esteem = _nudge(state.esteem, state.esteem - 0.1);
    }

    // 失去某人 → 归属需求飙升
    if (context.recentlyLostSomeone) {
      state.belonging = _nudge(state.belonging, 0.8);
    }

    // 有新人加入 → 归属需求略微下降
    if (context.hasNewcomer) {
      state.belonging = _nudge(state.belonging, state.belonging - 0.05);
    }

    // 有人生目标 → 自我实现需求上升
    if (context.hasLifeGoal) {
      state.selfActualization =
          _nudge(state.selfActualization, state.selfActualization + 0.1);
    }

    // 在探索中 → 精神超越需求上升
    if (context.isExploring) {
      state.transcendence =
          _nudge(state.transcendence, state.transcendence + 0.05);
    }
  }

  /// 根据人格五因子微调需求
  void _applyPersonalityBias(MaslowState state, GeneProfile genes) {
    // 高神经质 → 安全需求偏高
    if (genes.neuroticism > 0.7) {
      state.safety = _nudge(state.safety, state.safety + 0.1);
    }

    // 高外向性 → 归属需求偏高
    if (genes.extraversion > 0.7) {
      state.belonging = _nudge(state.belonging, state.belonging + 0.1);
    }

    // 高开放性 → 自我实现和精神超越偏高
    if (genes.openness > 0.7) {
      state.selfActualization =
          _nudge(state.selfActualization, state.selfActualization + 0.08);
      state.transcendence =
          _nudge(state.transcendence, state.transcendence + 0.05);
    }

    // 高宜人性 → 归属需求偏高，自尊竞争需求偏低
    if (genes.agreeableness > 0.7) {
      state.belonging = _nudge(state.belonging, state.belonging + 0.08);
      state.esteem = _nudge(state.esteem, state.esteem - 0.05);
    }

    // 高尽责性 → 自尊需求偏高
    if (genes.conscientiousness > 0.7) {
      state.esteem = _nudge(state.esteem, state.esteem + 0.08);
    }
  }

  /// 判断某层需求是否已被满足
  bool _isNeedSatisfied(MaslowLayer layer, SocialContext context) {
    switch (layer) {
      case MaslowLayer.survival:
        return context.hasFood && !context.inDanger;
      case MaslowLayer.safety:
        return context.hasShelter &&
            !context.inDanger &&
            context.environmentalSafety > 0.6;
      case MaslowLayer.belonging:
        return context.hasIntimateRelation && context.daysSinceLastSocial <= 1;
      case MaslowLayer.esteem:
        return context.recentlyPraised && !context.recentlyIgnored;
      case MaslowLayer.selfActualization:
        return context.hasLifeGoal;
      case MaslowLayer.transcendence:
        return context.isExploring;
    }
  }

  /// 计算社交上下文对某层需求的增量修正
  double _contextualDelta(
    MaslowLayer layer,
    SocialContext context,
    double current,
  ) {
    double delta = 0.0;

    switch (layer) {
      case MaslowLayer.survival:
        if (!context.hasFood) delta += 0.02;
        if (context.inDanger) delta += 0.03;
        break;
      case MaslowLayer.safety:
        if (!context.hasShelter) delta += 0.015;
        if (context.environmentalSafety < 0.3) delta += 0.02;
        break;
      case MaslowLayer.belonging:
        if (context.daysSinceLastSocial > 5) delta += 0.01;
        if (context.recentlyLostSomeone) delta += 0.02;
        if (context.hasIntimateRelation) delta -= 0.01;
        break;
      case MaslowLayer.esteem:
        if (context.recentlyIgnored) delta += 0.01;
        if (context.recentlyPraised) delta -= 0.015;
        break;
      case MaslowLayer.selfActualization:
        if (context.hasLifeGoal) delta -= 0.005;
        break;
      case MaslowLayer.transcendence:
        if (context.isExploring) delta -= 0.003;
        break;
    }

    return delta;
  }

  /// 年龄阶段的情绪波动修正系数
  ///
  /// 年轻时需求变化更快，年老时趋于稳定。
  double _ageVolatilityModifier(LifeStage stage) {
    switch (stage) {
      case LifeStage.infant:
        return 0.5;
      case LifeStage.toddler:
        return 0.8;
      case LifeStage.childhood:
        return 1.0;
      case LifeStage.teenage:
        return 1.5; // 青春期需求波动最剧烈
      case LifeStage.youngAdult:
        return 1.0;
      case LifeStage.adult:
        return 0.5;
      case LifeStage.senior:
        return 0.2;
      case LifeStage.elder:
        return 0.1;
    }
  }

  /// 将值向目标方向轻推，保持在 [0, 1] 范围内
  double _nudge(double current, double target) {
    return ((current + target) / 2).clamp(0.0, 1.0);
  }
}
