// ============================================================
// 全生命周期数字生命世界 — Phase 2
// 动态人格状态：五因子 + 衍生特质 + 性格标记
// ============================================================

import 'dart:convert';
import 'package:equatable/equatable.dart';
import 'gene_profile.dart';
import 'life_event.dart';

/// 动态人格状态 — 受经历影响，在基因基线上波动
class PersonalityState extends Equatable {
  // ── 动态五因子（受经历影响，在基因基线上波动） ──
  final double openness;
  final double conscientiousness;
  final double extraversion;
  final double agreeableness;
  final double neuroticism;

  // ── 衍生特质（由五因子组合 + 经历产生） ──
  final double courage;
  final double empathy;
  final double ambition;
  final double creativity;

  // ── 性格标记（经历产生的特殊标签） ──
  final List<String> traits;

  // ── 波动率（青春期高，中年低） ──
  final double volatility;

  // ── 稳定度（随年龄增长，性格趋于稳定） ──
  final double stability;

  // ── 情绪基调 ──
  final double emotionalBaseline; // 正值=乐观，负值=悲观

  const PersonalityState({
    required this.openness,
    required this.conscientiousness,
    required this.extraversion,
    required this.agreeableness,
    required this.neuroticism,
    required this.courage,
    required this.empathy,
    required this.ambition,
    required this.creativity,
    this.traits = const [],
    required this.volatility,
    required this.stability,
    required this.emotionalBaseline,
  });

  /// 从基因档案初始化人格状态
  factory PersonalityState.fromGenes(GeneProfile genes) {
    final o = genes.openness;
    final c = genes.conscientiousness;
    final e = genes.extraversion;
    final a = genes.agreeableness;
    final n = genes.neuroticism;
    final s = genes.sensitivity;

    // 计算天赋对创造力的贡献
    final talentCreativity = genes.talents.isEmpty
        ? 0.5
        : genes.talents.values.reduce((a, b) => a + b) / genes.talents.length;

    return PersonalityState(
      openness: o,
      conscientiousness: c,
      extraversion: e,
      agreeableness: a,
      neuroticism: n,
      courage: o * 0.3 + (1 - n) * 0.7,
      empathy: a * 0.6 + s * 0.4,
      ambition: c * 0.5 + e * 0.3,
      creativity: o * 0.7 + talentCreativity * 0.3,
      traits: const [],
      volatility: 0.5, // 默认中等波动
      stability: 0.3, // 新生儿不稳定
      emotionalBaseline: 0.0, // 中性
    );
  }

  /// 按维度名获取值
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
      case 'courage':
        return courage;
      case 'empathy':
        return empathy;
      case 'ambition':
        return ambition;
      case 'creativity':
        return creativity;
      case 'volatility':
        return volatility;
      case 'stability':
        return stability;
      case 'emotionalBaseline':
        return emotionalBaseline;
      default:
        return 0.0;
    }
  }

  /// 按维度名设置值，返回新的 PersonalityState
  PersonalityState setValue(String dimension, double value) {
    final v = value.clamp(0.0, 1.0);
    switch (dimension) {
      case 'openness':
        return copyWith(openness: v);
      case 'conscientiousness':
        return copyWith(conscientiousness: v);
      case 'extraversion':
        return copyWith(extraversion: v);
      case 'agreeableness':
        return copyWith(agreeableness: v);
      case 'neuroticism':
        return copyWith(neuroticism: v);
      case 'volatility':
        return copyWith(volatility: v);
      case 'stability':
        return copyWith(stability: v);
      case 'emotionalBaseline':
        return copyWith(emotionalBaseline: (value).clamp(-1.0, 1.0));
      default:
        return this;
    }
  }

  /// 根据五因子计算衍生特质
  PersonalityState deriveTraits() {
    return copyWith(
      courage: openness * 0.3 + (1 - neuroticism) * 0.7,
      empathy: agreeableness * 0.6 + _estimateSensitivity() * 0.4,
      ambition: conscientiousness * 0.5 + extraversion * 0.3,
      creativity: openness * 0.7 + _estimateTalentCreativity() * 0.3,
    );
  }

  /// 从五因子推断敏感度（无基因时的近似值）
  double _estimateSensitivity() {
    return neuroticism * 0.5 + openness * 0.3 + (1 - extraversion) * 0.2;
  }

  /// 从五因子推断天赋创造力（无基因时的近似值）
  double _estimateTalentCreativity() {
    return openness * 0.6 + (1 - conscientiousness) * 0.2 + extraversion * 0.2;
  }

  /// 生成性格描述文本
  String get summary {
    final parts = <String>[];

    // 五因子描述
    if (openness > 0.7) {
      parts.add('极具好奇心');
    } else if (openness < 0.3) {
      parts.add('偏好稳定与传统');
    }

    if (conscientiousness > 0.7) {
      parts.add('自律严谨');
    } else if (conscientiousness < 0.3) {
      parts.add('随性自由');
    }

    if (extraversion > 0.7) {
      parts.add('热情外向');
    } else if (extraversion < 0.3) {
      parts.add('安静内敛');
    }

    if (agreeableness > 0.7) {
      parts.add('温和善良');
    } else if (agreeableness < 0.3) {
      parts.add('独立果断');
    }

    if (neuroticism > 0.7) {
      parts.add('情感丰富敏感');
    } else if (neuroticism < 0.3) {
      parts.add('情绪稳定');
    }

    // 衍生特质
    if (courage > 0.7) parts.add('勇敢');
    if (empathy > 0.7) parts.add('富有同理心');
    if (ambition > 0.7) parts.add('有抱负');
    if (creativity > 0.7) parts.add('创造力丰富');

    // 情绪基调
    if (emotionalBaseline > 0.3) {
      parts.add('天性乐观');
    } else if (emotionalBaseline < -0.3) {
      parts.add('偏向悲观');
    }

    // 性格标记
    if (traits.isNotEmpty) {
      parts.add('经历塑造了"${traits.join('、')}"的特质');
    }

    return parts.isEmpty ? '性格尚在形成中' : parts.join('，');
  }

  /// 应用生命事件对人格的影响
  PersonalityState applyEvent(LifeEvent event) {
    if (!event.affects(EventDimension.personality)) return this;

    double clamp01(double v) => v.clamp(0.0, 1.0);

    var result = copyWith(
      openness: clamp01(openness + event.impactOf('openness')),
      conscientiousness: clamp01(conscientiousness + event.impactOf('conscientiousness')),
      extraversion: clamp01(extraversion + event.impactOf('extraversion')),
      agreeableness: clamp01(agreeableness + event.impactOf('agreeableness')),
      neuroticism: clamp01(neuroticism + event.impactOf('neuroticism')),
      emotionalBaseline:
          (emotionalBaseline + event.impactOf('emotionalBaseline')).clamp(-1.0, 1.0),
    );

    // 自动添加性格标记
    final newTraits = List<String>.from(traits);
    if (event.severity == EventSeverity.lifeChanging) {
      if (event.category == '创伤') {
        if (!newTraits.contains('曾经沧海')) newTraits.add('曾经沧海');
      }
      if (event.category == '成长') {
        if (!newTraits.contains('创伤后成长')) newTraits.add('创伤后成长');
      }
    }

    result = result.copyWith(traits: newTraits);
    return result.deriveTraits();
  }

  PersonalityState copyWith({
    double? openness,
    double? conscientiousness,
    double? extraversion,
    double? agreeableness,
    double? neuroticism,
    double? courage,
    double? empathy,
    double? ambition,
    double? creativity,
    List<String>? traits,
    double? volatility,
    double? stability,
    double? emotionalBaseline,
  }) {
    return PersonalityState(
      openness: openness ?? this.openness,
      conscientiousness: conscientiousness ?? this.conscientiousness,
      extraversion: extraversion ?? this.extraversion,
      agreeableness: agreeableness ?? this.agreeableness,
      neuroticism: neuroticism ?? this.neuroticism,
      courage: courage ?? this.courage,
      empathy: empathy ?? this.empathy,
      ambition: ambition ?? this.ambition,
      creativity: creativity ?? this.creativity,
      traits: traits ?? this.traits,
      volatility: volatility ?? this.volatility,
      stability: stability ?? this.stability,
      emotionalBaseline: emotionalBaseline ?? this.emotionalBaseline,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'openness': openness,
      'conscientiousness': conscientiousness,
      'extraversion': extraversion,
      'agreeableness': agreeableness,
      'neuroticism': neuroticism,
      'courage': courage,
      'empathy': empathy,
      'ambition': ambition,
      'creativity': creativity,
      'traits': traits,
      'volatility': volatility,
      'stability': stability,
      'emotionalBaseline': emotionalBaseline,
    };
  }

  factory PersonalityState.fromJson(Map<String, dynamic> json) {
    return PersonalityState(
      openness: (json['openness'] as num?)?.toDouble() ?? 0.5,
      conscientiousness: (json['conscientiousness'] as num?)?.toDouble() ?? 0.5,
      extraversion: (json['extraversion'] as num?)?.toDouble() ?? 0.5,
      agreeableness: (json['agreeableness'] as num?)?.toDouble() ?? 0.5,
      neuroticism: (json['neuroticism'] as num?)?.toDouble() ?? 0.5,
      courage: (json['courage'] as num?)?.toDouble() ?? 0.5,
      empathy: (json['empathy'] as num?)?.toDouble() ?? 0.5,
      ambition: (json['ambition'] as num?)?.toDouble() ?? 0.5,
      creativity: (json['creativity'] as num?)?.toDouble() ?? 0.5,
      traits: (json['traits'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      volatility: (json['volatility'] as num?)?.toDouble() ?? 0.5,
      stability: (json['stability'] as num?)?.toDouble() ?? 0.3,
      emotionalBaseline: (json['emotionalBaseline'] as num?)?.toDouble() ?? 0.0,
    );
  }

  String toJsonString() => jsonEncode(toJson());

  factory PersonalityState.fromJsonString(String source) =>
      PersonalityState.fromJson(jsonDecode(source) as Map<String, dynamic>);

  @override
  List<Object?> get props => [
        openness,
        conscientiousness,
        extraversion,
        agreeableness,
        neuroticism,
        courage,
        empathy,
        ambition,
        creativity,
        traits,
        volatility,
        stability,
        emotionalBaseline,
      ];
}
