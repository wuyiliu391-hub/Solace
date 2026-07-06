// ============================================================
// 全生命周期数字生命世界 — Phase 1
// 基因档案模型：先天基因、原生家庭、潜在特质
// ============================================================

import 'dart:convert';
import 'dart:math';
import 'package:equatable/equatable.dart';

/// 原生家庭背景
class FamilyBackground extends Equatable {
  final String description;
  final double wealth; // 0-1 经济水平
  final double warmth; // 0-1 家庭温暖度
  final double strictness; // 0-1 管教严格度
  final List<String> familyEvents;

  const FamilyBackground({
    required this.description,
    required this.wealth,
    required this.warmth,
    required this.strictness,
    this.familyEvents = const [],
  });

  FamilyBackground copyWith({
    String? description,
    double? wealth,
    double? warmth,
    double? strictness,
    List<String>? familyEvents,
  }) {
    return FamilyBackground(
      description: description ?? this.description,
      wealth: wealth ?? this.wealth,
      warmth: warmth ?? this.warmth,
      strictness: strictness ?? this.strictness,
      familyEvents: familyEvents ?? this.familyEvents,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'description': description,
      'wealth': wealth,
      'warmth': warmth,
      'strictness': strictness,
      'familyEvents': familyEvents,
    };
  }

  factory FamilyBackground.fromJson(Map<String, dynamic> json) {
    return FamilyBackground(
      description: json['description'] as String? ?? '',
      wealth: (json['wealth'] as num?)?.toDouble() ?? 0.5,
      warmth: (json['warmth'] as num?)?.toDouble() ?? 0.5,
      strictness: (json['strictness'] as num?)?.toDouble() ?? 0.5,
      familyEvents: (json['familyEvents'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
    );
  }

  /// 随机生成原生家庭
  factory FamilyBackground.random(Random rng) {
    const descriptions = [
      '普通工薪家庭',
      '书香门第',
      '经商世家',
      '单亲家庭',
      '艺术家庭',
      '农村家庭',
      '知识分子家庭',
      '公务员家庭',
    ];
    return FamilyBackground(
      description: descriptions[rng.nextInt(descriptions.length)],
      wealth: rng.nextDouble(),
      warmth: rng.nextDouble(),
      strictness: rng.nextDouble(),
    );
  }

  @override
  List<Object?> get props => [description, wealth, warmth, strictness, familyEvents];
}

/// 潜在特质 — 在特定条件下可被激活
class LatentTrait extends Equatable {
  final String name;
  final String description;
  final double triggerProbability; // 被激活的概率 0-1
  final bool isActivated;
  final Map<String, double> effect; // 激活后对人格的影响

  const LatentTrait({
    required this.name,
    required this.description,
    required this.triggerProbability,
    this.isActivated = false,
    this.effect = const {},
  });

  LatentTrait copyWith({
    String? name,
    String? description,
    double? triggerProbability,
    bool? isActivated,
    Map<String, double>? effect,
  }) {
    return LatentTrait(
      name: name ?? this.name,
      description: description ?? this.description,
      triggerProbability: triggerProbability ?? this.triggerProbability,
      isActivated: isActivated ?? this.isActivated,
      effect: effect ?? this.effect,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'description': description,
      'triggerProbability': triggerProbability,
      'isActivated': isActivated,
      'effect': effect,
    };
  }

  factory LatentTrait.fromJson(Map<String, dynamic> json) {
    return LatentTrait(
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      triggerProbability: (json['triggerProbability'] as num?)?.toDouble() ?? 0.5,
      isActivated: json['isActivated'] as bool? ?? false,
      effect: (json['effect'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, (v as num).toDouble())) ??
          {},
    );
  }

  @override
  List<Object?> get props => [name, description, triggerProbability, isActivated, effect];
}

/// 基因档案 — 先天决定的底层参数
class GeneProfile extends Equatable {
  // ── 人格五因子（先天基线 0.0-1.0）──
  final double openness; // 开放性
  final double conscientiousness; // 尽责性
  final double extraversion; // 外向性
  final double agreeableness; // 宜人性
  final double neuroticism; // 神经质

  // ── 天赋 ──
  final Map<String, double> talents; // {"语言": 0.9, "音乐": 0.3}

  // ── 体质 ──
  final double vitality; // 生命力
  final double resilience; // 韧性
  final double sensitivity; // 敏感度

  // ── 原生家庭 ──
  final FamilyBackground family;

  // ── 潜在特质 ──
  final List<LatentTrait> latentTraits;

  const GeneProfile({
    required this.openness,
    required this.conscientiousness,
    required this.extraversion,
    required this.agreeableness,
    required this.neuroticism,
    this.talents = const {},
    required this.vitality,
    required this.resilience,
    required this.sensitivity,
    required this.family,
    this.latentTraits = const [],
  });

  /// 随机生成基因档案
  factory GeneProfile.random() {
    final rng = Random();

    // 人格五因子
    double r() => rng.nextDouble();

    // 随机天赋池
    const talentPool = [
      '语言',
      '音乐',
      '数学',
      '运动',
      '绘画',
      '编程',
      '社交',
      '写作',
      '记忆',
      '直觉',
      '领导力',
      '共情',
    ];
    final talentCount = 2 + rng.nextInt(4); // 2~5 个天赋
    final shuffled = List.of(talentPool)..shuffle(rng);
    final talents = <String, double>{
      for (final t in shuffled.take(talentCount)) t: rng.nextDouble(),
    };

    // 随机潜在特质
    const traitPool = [
      ('绝对音感', '天生拥有辨别音高的能力', {'openness': 0.1, 'sensitivity': 0.2}),
      ('超强记忆', '对细节有近乎照相般的记忆力', {'conscientiousness': 0.15}),
      ('高敏感体质', '对外界刺激的感知阈值极低', {'neuroticism': 0.2, 'sensitivity': 0.3}),
      ('领导魅力', '天然的领袖气质与感染力', {'extraversion': 0.2, 'agreeableness': 0.1}),
      ('反叛精神', '对权威与规则天然抵触', {'openness': 0.15, 'agreeableness': -0.2}),
      ('创造性疯狂', '在极端思维中诞生灵感', {'openness': 0.25, 'neuroticism': 0.15}),
      ('社交变色龙', '能无缝融入任何社交环境', {'extraversion': 0.15, 'agreeableness': 0.15}),
      ('内省深度', '超常的自我反思与觉察能力', {'conscientiousness': 0.1, 'openness': 0.1}),
    ];
    final traitCount = 1 + rng.nextInt(3); // 1~3 个潜在特质
    final shuffledTraits = List.of(traitPool)..shuffle(rng);
    final latentTraits = shuffledTraits.take(traitCount).map((t) {
      return LatentTrait(
        name: t.$1,
        description: t.$2,
        triggerProbability: 0.1 + rng.nextDouble() * 0.4, // 0.1~0.5
        effect: t.$3.map((k, v) => MapEntry(k, v + (rng.nextDouble() - 0.5) * 0.1)),
      );
    }).toList();

    return GeneProfile(
      openness: r(),
      conscientiousness: r(),
      extraversion: r(),
      agreeableness: r(),
      neuroticism: r(),
      talents: talents,
      vitality: r(),
      resilience: r(),
      sensitivity: r(),
      family: FamilyBackground.random(rng),
      latentTraits: latentTraits,
    );
  }

  GeneProfile copyWith({
    double? openness,
    double? conscientiousness,
    double? extraversion,
    double? agreeableness,
    double? neuroticism,
    Map<String, double>? talents,
    double? vitality,
    double? resilience,
    double? sensitivity,
    FamilyBackground? family,
    List<LatentTrait>? latentTraits,
  }) {
    return GeneProfile(
      openness: openness ?? this.openness,
      conscientiousness: conscientiousness ?? this.conscientiousness,
      extraversion: extraversion ?? this.extraversion,
      agreeableness: agreeableness ?? this.agreeableness,
      neuroticism: neuroticism ?? this.neuroticism,
      talents: talents ?? this.talents,
      vitality: vitality ?? this.vitality,
      resilience: resilience ?? this.resilience,
      sensitivity: sensitivity ?? this.sensitivity,
      family: family ?? this.family,
      latentTraits: latentTraits ?? this.latentTraits,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'openness': openness,
      'conscientiousness': conscientiousness,
      'extraversion': extraversion,
      'agreeableness': agreeableness,
      'neuroticism': neuroticism,
      'talents': talents,
      'vitality': vitality,
      'resilience': resilience,
      'sensitivity': sensitivity,
      'family': family.toJson(),
      'latentTraits': latentTraits.map((t) => t.toJson()).toList(),
    };
  }

  factory GeneProfile.fromJson(Map<String, dynamic> json) {
    return GeneProfile(
      openness: (json['openness'] as num?)?.toDouble() ?? 0.5,
      conscientiousness: (json['conscientiousness'] as num?)?.toDouble() ?? 0.5,
      extraversion: (json['extraversion'] as num?)?.toDouble() ?? 0.5,
      agreeableness: (json['agreeableness'] as num?)?.toDouble() ?? 0.5,
      neuroticism: (json['neuroticism'] as num?)?.toDouble() ?? 0.5,
      talents: (json['talents'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, (v as num).toDouble())) ??
          {},
      vitality: (json['vitality'] as num?)?.toDouble() ?? 0.5,
      resilience: (json['resilience'] as num?)?.toDouble() ?? 0.5,
      sensitivity: (json['sensitivity'] as num?)?.toDouble() ?? 0.5,
      family: json['family'] != null
          ? FamilyBackground.fromJson(json['family'] as Map<String, dynamic>)
          : const FamilyBackground(description: '', wealth: 0.5, warmth: 0.5, strictness: 0.5),
      latentTraits: (json['latentTraits'] as List<dynamic>?)
              ?.map((t) => LatentTrait.fromJson(t as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  String toJsonString() => jsonEncode(toJson());

  factory GeneProfile.fromJsonString(String source) =>
      GeneProfile.fromJson(jsonDecode(source) as Map<String, dynamic>);

  @override
  List<Object?> get props => [
        openness,
        conscientiousness,
        extraversion,
        agreeableness,
        neuroticism,
        talents,
        vitality,
        resilience,
        sensitivity,
        family,
        latentTraits,
      ];
}
