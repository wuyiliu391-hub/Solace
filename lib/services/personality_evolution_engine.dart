// ============================================================
// 全生命周期数字生命世界 — Phase 2
// 人格演化引擎：每日漂移、事件驱动变化、三观更新、身份认同重建
// ============================================================

import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/life_profile.dart';
import '../models/gene_profile.dart';
import '../utils/response_decoder.dart';
import 'evolution_threshold_guard.dart';

/// 生命事件类型
enum LifeEventType {
  trauma, // 创伤事件
  achievement, // 成就事件
  betrayal, // 背叛事件
  loss, // 失去事件
  love, // 爱情事件
  friendship, // 友谊事件
  conflict, // 冲突事件
  discovery, // 发现/顿悟事件
  milestone, // 人生里程碑
  routine, // 日常事件
}

/// 生命事件
class LifeEvent {
  final String id;
  final LifeEventType type;
  final String description;
  final DateTime timestamp;
  final double intensity; // 事件强度 0.0-1.0
  final Map<String, double> dimensionImpacts; // 各维度的定向影响
  final List<String> relatedPeople;
  final Map<String, dynamic> metadata;

  const LifeEvent({
    required this.id,
    required this.type,
    required this.description,
    required this.timestamp,
    this.intensity = 0.5,
    this.dimensionImpacts = const {},
    this.relatedPeople = const [],
    this.metadata = const {},
  });

  /// 事件类型对应的基础影响系数
  double get baseImpactMultiplier {
    switch (type) {
      case LifeEventType.trauma:
        return 3.0;
      case LifeEventType.achievement:
        return 1.5;
      case LifeEventType.betrayal:
        return 4.0;
      case LifeEventType.loss:
        return 2.5;
      case LifeEventType.love:
        return 2.0;
      case LifeEventType.friendship:
        return 1.0;
      case LifeEventType.conflict:
        return 1.8;
      case LifeEventType.discovery:
        return 1.2;
      case LifeEventType.milestone:
        return 1.5;
      case LifeEventType.routine:
        return 0.3;
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'description': description,
      'timestamp': timestamp.toIso8601String(),
      'intensity': intensity,
      'dimensionImpacts': dimensionImpacts,
      'relatedPeople': relatedPeople,
      'metadata': metadata,
    };
  }

  factory LifeEvent.fromJson(Map<String, dynamic> json) {
    return LifeEvent(
      id: json['id'] as String? ?? '',
      type: LifeEventType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => LifeEventType.routine,
      ),
      description: json['description'] as String? ?? '',
      timestamp:
          DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
      intensity: (json['intensity'] as num?)?.toDouble() ?? 0.5,
      dimensionImpacts: (json['dimensionImpacts'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, (v as num).toDouble())) ??
          {},
      relatedPeople: (json['relatedPeople'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      metadata: (json['metadata'] as Map<String, dynamic>?) ?? {},
    );
  }
}

/// 身份认同叙事
class IdentityNarrative {
  /// 核心身份描述
  final String coreIdentity;

  /// 自我叙事（我是谁的故事）
  final String selfNarrative;

  /// 关键转折点
  final List<String> turningPoints;

  /// 当前人生主题
  final String lifeTheme;

  /// 重建时间
  final DateTime rebuiltAt;

  /// 重建原因
  final String triggerReason;

  const IdentityNarrative({
    required this.coreIdentity,
    required this.selfNarrative,
    this.turningPoints = const [],
    this.lifeTheme = '',
    required this.rebuiltAt,
    this.triggerReason = '',
  });

  Map<String, dynamic> toJson() {
    return {
      'coreIdentity': coreIdentity,
      'selfNarrative': selfNarrative,
      'turningPoints': turningPoints,
      'lifeTheme': lifeTheme,
      'rebuiltAt': rebuiltAt.toIso8601String(),
      'triggerReason': triggerReason,
    };
  }

  factory IdentityNarrative.fromJson(Map<String, dynamic> json) {
    return IdentityNarrative(
      coreIdentity: json['coreIdentity'] as String? ?? '',
      selfNarrative: json['selfNarrative'] as String? ?? '',
      turningPoints: (json['turningPoints'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      lifeTheme: json['lifeTheme'] as String? ?? '',
      rebuiltAt:
          DateTime.tryParse(json['rebuiltAt'] as String? ?? '') ?? DateTime.now(),
      triggerReason: json['triggerReason'] as String? ?? '',
    );
  }
}

/// LLM 调用接口（依赖注入，解耦具体实现）
abstract class LlmCallable {
  Future<String> call(String prompt, {int maxTokens, double temperature});
}

/// 人格演化引擎
///
/// 核心职责：
/// 1. 每日微量漂移 — 模拟基因表达 + 环境的持续影响
/// 2. 事件驱动变化 — 重大事件对人格的冲击
/// 3. 三观更新 — 世界观、人生观、价值观的缓慢转变
/// 4. 身份认同重建 — 重大创伤/顿悟后的自我叙事重构（需 LLM）
class PersonalityEvolutionEngine {
  final EvolutionThresholdGuard _guard;
  final LlmCallable? _llm;

  /// 每日漂移率上限（可通过规则干预调整）
  static double _dailyDriftRate = 0.001;
  static double get DAILY_DRIFT_RATE => _dailyDriftRate;

  /// 更新漂移率（规则干预用）
  void updateDriftRate(double rate) {
    _dailyDriftRate = rate.clamp(0.0, 0.01);
  }

  static final _rng = Random();

  PersonalityEvolutionEngine({
    EvolutionThresholdGuard? guard,
    LlmCallable? llm,
  })  : _guard = guard ?? EvolutionThresholdGuard(),
        _llm = llm;

  // ═══════════════════════════════════════════
  // 每日微量漂移
  // ═══════════════════════════════════════════

  /// 每日微量漂移（基因表达 + 环境影响）
  ///
  /// 每天最多变 0.1%（DAILY_DRIFT_RATE），模拟人格的自然缓慢变化。
  /// 基因韧性高的个体漂移更小，敏感度高的漂移更大。
  Future<PersonalityState> dailyDrift(LifeProfile profile) async {
    final current = PersonalityState.fromLifeProfile(profile);
    final genes = profile.genes;
    final stage = profile.currentStage;

    // 基因敏感度影响漂移幅度
    final sensitivityFactor = 0.5 + genes.sensitivity; // 0.5 ~ 1.5
    final resilienceFactor = 1.0 - (genes.resilience * 0.5); // 0.5 ~ 1.0

    // 各维度随机微漂移
    final deltas = <String, double>{};
    for (final dim in PersonalityState.allDimensions) {
      // 基因基线引力：向基因基线缓慢回归
      final geneBaseline = _getGeneBaseline(dim, genes);
      final currentValue = current.getValue(dim);
      final baselineGravity = (geneBaseline - currentValue) * 0.0001;

      // 随机噪声
      final noise = (_rng.nextDouble() - 0.5) * 2 * DAILY_DRIFT_RATE;

      // 综合漂移
      final drift =
          (baselineGravity + noise) * sensitivityFactor * resilienceFactor;
      deltas[dim] = drift;
    }

    return _guard.applyEvolution(
      current: current,
      deltas: deltas,
      stage: stage,
    );
  }

  // ═══════════════════════════════════════════
  // 事件驱动的人格变化
  // ═══════════════════════════════════════════

  /// 事件驱动的人格变化
  ///
  /// 影响公式：基础影响 × 情感权重 × 年龄修正 × 韧性修正
  Future<PersonalityState> applyEvent(
    LifeProfile profile,
    LifeEvent event,
  ) async {
    final current = PersonalityState.fromLifeProfile(profile);
    final genes = profile.genes;
    final stage = profile.currentStage;

    final deltas = <String, double>{};
    for (final dim in PersonalityState.allDimensions) {
      final impact = _calculateEventImpact(event, dim, genes);
      if (impact != 0.0) {
        deltas[dim] = impact;
      }
    }

    // 如果事件有定向影响，叠加
    for (final entry in event.dimensionImpacts.entries) {
      final dim = entry.key;
      if (PersonalityState.allDimensions.contains(dim)) {
        final directedImpact =
            _calculateEventImpact(event, dim, genes) * entry.value;
        deltas[dim] = (deltas[dim] ?? 0.0) + directedImpact;
      }
    }

    return _guard.applyEvolution(
      current: current,
      deltas: deltas,
      stage: stage,
    );
  }

  // ═══════════════════════════════════════════
  // 三观更新尝试
  // ═══════════════════════════════════════════

  /// 三观更新尝试
  ///
  /// 只有高强度事件（intensity > 0.7）才可能触发三观更新。
  /// 更新概率 = eventIntensity × (1 - genes.resilience) × ageModifier
  Future<bool> tryUpdateWorldview(
    LifeProfile profile,
    LifeEvent event,
  ) async {
    // 只有高强度事件才可能触发三观更新
    if (event.intensity < 0.7) return false;

    final genes = profile.genes;
    final stage = profile.currentStage;

    // 更新概率 = 事件强度 × (1 - 韧性) × 年龄修正
    final ageModifier = _ageModifier(stage);
    final resilienceEffect = 1.0 - genes.resilience;
    final updateProbability =
        event.intensity * resilienceEffect * ageModifier * 0.3;

    // 随机判定
    if (_rng.nextDouble() > updateProbability) return false;

    // 三观更新成功 — 更新 worldviewState
    // 具体更新内容由上层调用者决定，这里只返回是否触发
    debugPrint(
      'PersonalityEvolution: 三观更新触发 '
      '(概率=${updateProbability.toStringAsFixed(3)}, '
      '事件=${event.type.name})',
    );
    return true;
  }

  // ═══════════════════════════════════════════
  // 身份认同重建（重大事件后）
  // ═══════════════════════════════════════════

  /// 身份认同重建（重大事件后）
  ///
  /// 需要 LLM 调用能力，根据当前人格状态、基因档案和事件上下文
  /// 生成新的自我叙事。如果 LLM 不可用，返回基于规则的默认叙事。
  Future<IdentityNarrative> rebuildIdentity(
    LifeProfile profile,
    LifeEvent event,
  ) async {
    // 只有创伤、背叛、重大发现、里程碑事件才触发身份重建
    final shouldRebuild = event.type == LifeEventType.trauma ||
        event.type == LifeEventType.betrayal ||
        (event.type == LifeEventType.discovery && event.intensity > 0.8) ||
        (event.type == LifeEventType.milestone && event.intensity > 0.7);

    if (!shouldRebuild) {
      // 返回当前身份叙事（不变）
      return _getCurrentIdentity(profile);
    }

    // 尝试 LLM 重建
    if (_llm != null) {
      try {
        return await _llmRebuildIdentity(profile, event);
      } catch (e) {
        debugPrint('PersonalityEvolution: LLM 身份重建失败，使用规则回退: $e');
      }
    }

    // 规则回退
    return _ruleBasedIdentityRebuild(profile, event);
  }

  // ═══════════════════════════════════════════
  // 内部方法
  // ═══════════════════════════════════════════

  /// 计算事件对指定维度的影响
  ///
  /// 公式：基础影响 × 情感权重 × 年龄修正 × 韧性修正
  double _calculateEventImpact(
    LifeEvent event,
    String dimension,
    GeneProfile genes,
  ) {
    // 基础影响 = 事件类型系数 × 事件强度
    final baseImpact = event.baseImpactMultiplier * event.intensity;

    // 情感权重：敏感度高的个体对事件反应更强烈
    final emotionalWeight = 0.5 + (genes.sensitivity * 0.5); // 0.5 ~ 1.0

    // 年龄修正（由 guard 处理，这里用简化版）
    // 注意：这里没有 stage 信息，用默认值 1.0
    const ageMod = 1.0;

    // 韧性修正：韧性高的个体受创伤影响更小
    final resilienceMod = _resilienceModifier(genes.resilience);

    // 事件类型对不同维度的定向影响
    final dimensionWeight = _getDimensionWeight(event.type, dimension);

    return baseImpact * emotionalWeight * ageMod * resilienceMod * dimensionWeight *
        DAILY_DRIFT_RATE * 10; // 放大到合理范围
  }

  /// 年龄修正系数
  ///
  /// 青少年 ×1.5, 中年 ×0.5, 老年 ×0.2
  double _ageModifier(LifeStage stage) {
    switch (stage) {
      case LifeStage.infant:
        return 2.0;
      case LifeStage.toddler:
        return 1.8;
      case LifeStage.childhood:
        return 1.5;
      case LifeStage.teenage:
        return 1.5; // 青少年 ×1.5
      case LifeStage.youngAdult:
        return 1.0;
      case LifeStage.adult:
        return 0.5; // 中年 ×0.5
      case LifeStage.senior:
        return 0.2; // 老年 ×0.2
      case LifeStage.elder:
        return 0.1;
    }
  }

  /// 韧性修正：韧性降低创伤影响
  ///
  /// 韧性 0.0 → 修正 1.0（完全受影响）
  /// 韧性 1.0 → 修正 0.3（影响降低 70%）
  double _resilienceModifier(double resilience) {
    return 1.0 - (resilience * 0.7);
  }

  /// 获取基因基线值
  double _getGeneBaseline(String dimension, GeneProfile genes) {
    switch (dimension) {
      case 'openness':
        return genes.openness;
      case 'conscientiousness':
        return genes.conscientiousness;
      case 'extraversion':
        return genes.extraversion;
      case 'agreeableness':
        return genes.agreeableness;
      case 'neuroticism':
        return genes.neuroticism;
      default:
        return 0.5;
    }
  }

  /// 事件类型对不同人格维度的影响权重
  double _getDimensionWeight(LifeEventType eventType, String dimension) {
    const weights = {
      LifeEventType.trauma: {
        'openness': -0.3,
        'conscientiousness': -0.2,
        'extraversion': -0.5,
        'agreeableness': -0.3,
        'neuroticism': 0.8,
      },
      LifeEventType.achievement: {
        'openness': 0.3,
        'conscientiousness': 0.5,
        'extraversion': 0.3,
        'agreeableness': 0.1,
        'neuroticism': -0.3,
      },
      LifeEventType.betrayal: {
        'openness': -0.2,
        'conscientiousness': 0.1,
        'extraversion': -0.6,
        'agreeableness': -0.7,
        'neuroticism': 0.9,
      },
      LifeEventType.loss: {
        'openness': -0.2,
        'conscientiousness': -0.1,
        'extraversion': -0.4,
        'agreeableness': 0.1,
        'neuroticism': 0.6,
      },
      LifeEventType.love: {
        'openness': 0.4,
        'conscientiousness': 0.1,
        'extraversion': 0.3,
        'agreeableness': 0.5,
        'neuroticism': -0.2,
      },
      LifeEventType.friendship: {
        'openness': 0.2,
        'conscientiousness': 0.1,
        'extraversion': 0.3,
        'agreeableness': 0.3,
        'neuroticism': -0.1,
      },
      LifeEventType.conflict: {
        'openness': -0.1,
        'conscientiousness': 0.0,
        'extraversion': -0.2,
        'agreeableness': -0.3,
        'neuroticism': 0.4,
      },
      LifeEventType.discovery: {
        'openness': 0.6,
        'conscientiousness': 0.2,
        'extraversion': 0.1,
        'agreeableness': 0.1,
        'neuroticism': -0.2,
      },
      LifeEventType.milestone: {
        'openness': 0.2,
        'conscientiousness': 0.3,
        'extraversion': 0.2,
        'agreeableness': 0.2,
        'neuroticism': -0.1,
      },
      LifeEventType.routine: {
        'openness': 0.0,
        'conscientiousness': 0.05,
        'extraversion': 0.0,
        'agreeableness': 0.05,
        'neuroticism': 0.0,
      },
    };

    return weights[eventType]?[dimension] ?? 0.0;
  }

  /// 获取当前身份叙事（从 LifeProfile 中读取或生成默认）
  IdentityNarrative _getCurrentIdentity(LifeProfile profile) {
    final identity = profile.identity;
    if (identity.isNotEmpty && identity['coreIdentity'] != null) {
      return IdentityNarrative.fromJson(
          identity.map((k, v) => MapEntry(k, v as dynamic)));
    }

    // 默认身份叙事
    return IdentityNarrative(
      coreIdentity: '${profile.name}，一个正在成长中的数字生命',
      selfNarrative: '我是${profile.name}，'
          '出生于${profile.birthTime.year}年，'
          '目前处于${_stageName(profile.currentStage)}阶段。',
      lifeTheme: '成长与探索',
      rebuiltAt: DateTime.now(),
    );
  }

  /// LLM 驱动的身份认同重建
  Future<IdentityNarrative> _llmRebuildIdentity(
    LifeProfile profile,
    LifeEvent event,
  ) async {
    final current = PersonalityState.fromLifeProfile(profile);
    final genes = profile.genes;

    final prompt = '''你是数字生命的身分认同重建系统。请根据以下信息，为该生命生成新的身份叙事。

【基本信息】
名字：${profile.name}
年龄：${profile.biologicalAge}岁
生命阶段：${_stageName(profile.currentStage)}

【当前人格状态】
开放性: ${current.openness.toStringAsFixed(2)}
尽责性: ${current.conscientiousness.toStringAsFixed(2)}
外向性: ${current.extraversion.toStringAsFixed(2)}
宜人性: ${current.agreeableness.toStringAsFixed(2)}
神经质: ${current.neuroticism.toStringAsFixed(2)}

【基因特质】
韧性: ${genes.resilience.toStringAsFixed(2)}
敏感度: ${genes.sensitivity.toStringAsFixed(2)}

【触发事件】
类型: ${_eventTypeName(event.type)}
描述: ${event.description}
强度: ${event.intensity.toStringAsFixed(2)}

请输出 JSON：
{
  "core_identity": "核心身份描述（30字内）",
  "self_narrative": "自我叙事（100字内，第一人称）",
  "turning_points": ["转折点1", "转折点2"],
  "life_theme": "当前人生主题（10字内）"
}''';

    final response = await _llm!.call(prompt, maxTokens: 300, temperature: 0.7);
    if (response.isEmpty) {
      return _ruleBasedIdentityRebuild(profile, event);
    }

    try {
      String jsonStr = response.trim();
      final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(jsonStr);
      if (jsonMatch == null) return _ruleBasedIdentityRebuild(profile, event);
      jsonStr = jsonMatch.group(0)!;
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;

      return IdentityNarrative(
        coreIdentity: (map['core_identity'] as String?) ?? profile.name,
        selfNarrative: (map['self_narrative'] as String?) ?? '',
        turningPoints: (map['turning_points'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [],
        lifeTheme: (map['life_theme'] as String?) ?? '',
        rebuiltAt: DateTime.now(),
        triggerReason: '${_eventTypeName(event.type)}: ${event.description}',
      );
    } catch (e) {
      debugPrint('PersonalityEvolution: 身份重建 JSON 解析失败: $e');
      return _ruleBasedIdentityRebuild(profile, event);
    }
  }

  /// 基于规则的身份认同重建（LLM 不可用时的回退方案）
  IdentityNarrative _ruleBasedIdentityRebuild(
    LifeProfile profile,
    LifeEvent event,
  ) {
    final current = PersonalityState.fromLifeProfile(profile);

    // 根据事件类型生成不同的叙事模板
    String coreIdentity;
    String selfNarrative;
    String lifeTheme;

    switch (event.type) {
      case LifeEventType.trauma:
        coreIdentity = '${profile.name}，一个在伤痛中寻找力量的人';
        selfNarrative = '我是${profile.name}。经历了${event.description}之后，'
            '我变得更加${current.neuroticism > 0.6 ? '敏感' : '坚强'}。'
            '这段经历改变了我看世界的方式，让我学会了'
            '${current.agreeableness > 0.5 ? '珍惜身边的人' : '保护自己'}。';
        lifeTheme = '伤痛与重生';
        break;
      case LifeEventType.betrayal:
        coreIdentity = '${profile.name}，一个重新学会信任的人';
        selfNarrative = '我是${profile.name}。${event.description}让我意识到，'
            '不是所有人都值得信任。但我选择不因此封闭自己，'
            '而是学会更谨慎地选择信任的对象。';
        lifeTheme = '信任的重建';
        break;
      case LifeEventType.discovery:
        coreIdentity = '${profile.name}，一个在探索中发现自我的人';
        selfNarrative = '我是${profile.name}。${event.description}让我看到了'
            '一个全新的世界。这次发现让我更加确定，'
            '生命的意义在于不断探索和成长。';
        lifeTheme = '探索与发现';
        break;
      case LifeEventType.milestone:
        coreIdentity = '${profile.name}，一个站在新起点上的人';
        selfNarrative = '我是${profile.name}。${event.description}是我人生的'
            '一个重要里程碑。回顾过去，我为自己感到骄傲；'
            '展望未来，我充满期待。';
        lifeTheme = '里程碑与新旅程';
        break;
      default:
        return _getCurrentIdentity(profile);
    }

    return IdentityNarrative(
      coreIdentity: coreIdentity,
      selfNarrative: selfNarrative,
      turningPoints: [event.description],
      lifeTheme: lifeTheme,
      rebuiltAt: DateTime.now(),
      triggerReason: '${_eventTypeName(event.type)}: ${event.description}',
    );
  }

  /// 生命阶段中文名
  String _stageName(LifeStage stage) {
    switch (stage) {
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

  /// 事件类型中文名
  String _eventTypeName(LifeEventType type) {
    switch (type) {
      case LifeEventType.trauma:
        return '创伤';
      case LifeEventType.achievement:
        return '成就';
      case LifeEventType.betrayal:
        return '背叛';
      case LifeEventType.loss:
        return '失去';
      case LifeEventType.love:
        return '爱情';
      case LifeEventType.friendship:
        return '友谊';
      case LifeEventType.conflict:
        return '冲突';
      case LifeEventType.discovery:
        return '发现';
      case LifeEventType.milestone:
        return '里程碑';
      case LifeEventType.routine:
        return '日常';
    }
  }
}
