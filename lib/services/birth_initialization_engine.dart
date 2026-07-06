// ============================================================
// 全生命周期数字生命世界 — Phase 1
// 降生初始化引擎：负责新生命的诞生流程
// ============================================================

import 'dart:math';
import 'dart:io';
import 'package:uuid/uuid.dart';
import 'package:yaml/yaml.dart';
import '../models/life_profile.dart';
import '../models/gene_profile.dart';

/// 烙印事件类型
enum ImprintType {
  trauma, // 创伤类
  warmth, // 温暖类
}

/// 烙印事件定义
class ImprintEvent {
  final String id;
  final String name;
  final String description;
  final ImprintType type;
  final double weight; // 影响权重 0-1
  final Map<String, double> personalityEffect; // 对人格维度的影响
  final Map<String, double> emotionalEffect; // 对情绪状态的影响
  final bool Function(Map<String, dynamic> family, GeneProfile genes)?
      triggerCondition; // 触发条件

  const ImprintEvent({
    required this.id,
    required this.name,
    required this.description,
    required this.type,
    required this.weight,
    this.personalityEffect = const {},
    this.emotionalEffect = const {},
    this.triggerCondition,
  });
}

/// 降生初始化引擎
///
/// 负责创建新生命的完整流程：
/// 1. 遗传基因配比（父母各50% + 随机突变）
/// 2. 生成原生家庭
/// 3. 生成幼年烙印事件
/// 4. 应用烙印效果到人格
class BirthInitializationEngine {
  static const _uuid = Uuid();
  static final _rng = Random();

  // ── 配置缓存 ──
  Map<String, dynamic>? _birthRules;

  /// 烙印事件池
  static const List<ImprintEvent> _imprintPool = [
    // ── 创伤类 ──
    ImprintEvent(
      id: 'abandoned_by_parents',
      name: '被父母短暂抛弃',
      description: '在幼年时期经历被父母短暂遗弃的恐惧，留下深刻的不安全感。',
      type: ImprintType.trauma,
      weight: 0.8,
      personalityEffect: {
        'neuroticism': 0.15,
        'agreeableness': -0.1,
        'openness': -0.05,
      },
      emotionalEffect: {
        'fear': 0.3,
        'trust': -0.2,
        'security': -0.25,
      },
    ),
    ImprintEvent(
      id: 'extreme_fear_event',
      name: '极度恐惧事件',
      description: '经历一次极度恐惧的事件（如火灾、地震、暴力目睹），形成创伤记忆。',
      type: ImprintType.trauma,
      weight: 0.7,
      personalityEffect: {
        'neuroticism': 0.2,
        'extraversion': -0.1,
        'sensitivity': 0.15,
      },
      emotionalEffect: {
        'fear': 0.4,
        'stability': -0.3,
      },
    ),
    ImprintEvent(
      id: 'excluded_by_peers',
      name: '被同龄人排挤',
      description: '在幼儿园或邻里中被同龄孩子排挤，产生社交恐惧和自卑感。',
      type: ImprintType.trauma,
      weight: 0.6,
      personalityEffect: {
        'extraversion': -0.15,
        'agreeableness': -0.05,
        'neuroticism': 0.1,
      },
      emotionalEffect: {
        'social_confidence': -0.2,
        'loneliness': 0.15,
      },
    ),

    // ── 温暖类 ──
    ImprintEvent(
      id: 'unconditional_love',
      name: '无条件的爱',
      description: '感受到来自家人无条件的爱与接纳，建立起安全型依恋。',
      type: ImprintType.warmth,
      weight: 0.8,
      personalityEffect: {
        'agreeableness': 0.15,
        'neuroticism': -0.1,
        'extraversion': 0.1,
      },
      emotionalEffect: {
        'security': 0.3,
        'trust': 0.25,
        'happiness': 0.2,
      },
    ),
    ImprintEvent(
      id: 'favored_child',
      name: '被偏爱的孩子',
      description: '在家庭中被特别偏爱，获得额外的关注和资源，但也可能产生内疚。',
      type: ImprintType.warmth,
      weight: 0.6,
      personalityEffect: {
        'extraversion': 0.1,
        'conscientiousness': 0.1,
        'neuroticism': 0.05, // 轻微内疚
      },
      emotionalEffect: {
        'self_worth': 0.2,
        'happiness': 0.15,
      },
    ),
    ImprintEvent(
      id: 'long_term_companionship',
      name: '长期陪伴',
      description: '有一位稳定的陪伴者（祖父母、保姆等），提供持续的情感支持。',
      type: ImprintType.warmth,
      weight: 0.7,
      personalityEffect: {
        'agreeableness': 0.1,
        'extraversion': 0.1,
        'neuroticism': -0.1,
      },
      emotionalEffect: {
        'security': 0.2,
        'trust': 0.2,
        'loneliness': -0.15,
      },
    ),
  ];

  /// 加载降生规则配置
  Future<Map<String, dynamic>> _loadBirthRules() async {
    if (_birthRules != null) return _birthRules!;

    try {
      final file = File('world/birth_rules.yaml');
      if (await file.exists()) {
        final content = await file.readAsString();
        final yaml = loadYaml(content);
        _birthRules = Map<String, dynamic>.from(yaml as Map);
      } else {
        // 使用默认配置
        _birthRules = {
          'birth': {
            'genetics': {
              'mutationRange': 0.1,
              'dualTalentInheritance': 0.15,
              'latentTraitCount': [2, 3],
            },
            'childhood': {
              'imprintCount': [1, 3],
              'imprintAgeRange': [0, 6],
              'traumaticWeightThreshold': 0.7,
            },
            'family': {
              'wealthyColdProbability': 0.15,
              'poorWarmProbability': 0.15,
              'strictFamilyProbability': 0.2,
              'neglectFamilyProbability': 0.1,
              'normalFamilyProbability': 0.4,
            },
            'naming': {'style': 'random'},
          },
        };
      }
    } catch (e) {
      // 配置加载失败时使用默认值
      _birthRules = {
        'birth': {
          'genetics': {'mutationRange': 0.1},
          'childhood': {
            'imprintCount': [1, 3],
            'imprintAgeRange': [0, 6],
          },
        },
      };
    }

    return _birthRules!;
  }

  /// 创建新生命
  ///
  /// [parentGenesA] 父/母A的基因（可选）
  /// [parentGenesB] 父/母B的基因（可选）
  /// [familyOverride] 家庭背景覆盖（可选）
  /// [nameOverride] 名字覆盖（可选）
  Future<LifeProfile> createLife({
    GeneProfile? parentGenesA,
    GeneProfile? parentGenesB,
    Map<String, dynamic>? familyOverride,
    String? nameOverride,
  }) async {
    final rules = await _loadBirthRules();
    final birthConfig = rules['birth'] as Map<String, dynamic>? ?? {};

    // 1. 遗传基因配比
    final genes = _inheritGenes(parentGenesA, parentGenesB);

    // 2. 生成原生家庭（如果没有覆盖）
    final family = familyOverride ?? _generateFamily(genes);

    // 3. 生成名字
    final name = nameOverride ?? _generateName(birthConfig);

    // 4. 创建生命档案
    final now = DateTime.now();
    final profile = LifeProfile(
      id: _uuid.v4(),
      name: name,
      birthTime: now,
      genes: genes.copyWith(
        family: familyOverride != null
            ? FamilyBackground.fromJson(familyOverride)
            : genes.family,
      ),
      personalityState: _initializePersonalityState(genes),
      emotionalState: _initializeEmotionalState(genes),
      physicalState: _initializePhysicalState(genes),
      maslowState: _initializeMaslowState(genes, family),
      lifeEvents: [
        {
          'type': 'birth',
          'timestamp': now.toIso8601String(),
          'description': '$name 降临这个世界',
          'stage': 'infant',
        },
      ],
      identity: {
        'selfConcept': '刚出生的婴儿，对世界充满好奇',
        'values': [],
        'beliefs': [],
      },
    );

    // 5. 生成幼年烙印事件
    final imprints = await _generateChildhoodImprints(profile, family);

    // 6. 应用烙印效果
    var updatedProfile = profile;
    for (final imprint in imprints) {
      updatedProfile = _applyImprintEffect(updatedProfile, imprint);
    }

    return updatedProfile;
  }

  /// 遗传基因配比（父母各50% + 随机突变 ±0.1）
  GeneProfile _inheritGenes(GeneProfile? parentA, GeneProfile? parentB) {
    // 无父母基因时随机生成
    if (parentA == null && parentB == null) {
      return GeneProfile.random();
    }

    // 只有一方基因时，以该方为基础
    if (parentA == null) return _mutateGeneProfile(parentB!);
    if (parentB == null) return _mutateGeneProfile(parentA);

    // 双亲基因配比：各50% + 突变
    final mutationRange =
        _birthRules?['birth']?['genetics']?['mutationRange'] ?? 0.1;

    return GeneProfile(
      openness: _mutate(
        (parentA.openness + parentB.openness) / 2,
        mutationRange,
      ),
      conscientiousness: _mutate(
        (parentA.conscientiousness + parentB.conscientiousness) / 2,
        mutationRange,
      ),
      extraversion: _mutate(
        (parentA.extraversion + parentB.extraversion) / 2,
        mutationRange,
      ),
      agreeableness: _mutate(
        (parentA.agreeableness + parentB.agreeableness) / 2,
        mutationRange,
      ),
      neuroticism: _mutate(
        (parentA.neuroticism + parentB.neuroticism) / 2,
        mutationRange,
      ),
      talents: _inheritTalents(parentA.talents, parentB.talents),
      vitality: _mutate(
        (parentA.vitality + parentB.vitality) / 2,
        mutationRange,
      ),
      resilience: _mutate(
        (parentA.resilience + parentB.resilience) / 2,
        mutationRange,
      ),
      sensitivity: _mutate(
        (parentA.sensitivity + parentB.sensitivity) / 2,
        mutationRange,
      ),
      family: FamilyBackground.fromJson(_generateFamily(null)),
      latentTraits: _inheritLatentTraits(
        parentA.latentTraits,
        parentB.latentTraits,
      ),
    );
  }

  /// 基因突变：在基础值上叠加 ±range 的随机偏移，结果限制在 [0, 1]
  double _mutate(double base, double range) {
    final delta = (_rng.nextDouble() * 2 - 1) * range;
    return (base + delta).clamp(0.0, 1.0);
  }

  /// 对整个基因档案施加突变
  GeneProfile _mutateGeneProfile(GeneProfile parent) {
    final mutationRange =
        _birthRules?['birth']?['genetics']?['mutationRange'] ?? 0.1;

    return GeneProfile(
      openness: _mutate(parent.openness, mutationRange),
      conscientiousness: _mutate(parent.conscientiousness, mutationRange),
      extraversion: _mutate(parent.extraversion, mutationRange),
      agreeableness: _mutate(parent.agreeableness, mutationRange),
      neuroticism: _mutate(parent.neuroticism, mutationRange),
      talents: parent.talents.map(
        (k, v) => MapEntry(k, _mutate(v, mutationRange)),
      ),
      vitality: _mutate(parent.vitality, mutationRange),
      resilience: _mutate(parent.resilience, mutationRange),
      sensitivity: _mutate(parent.sensitivity, mutationRange),
      family: FamilyBackground.fromJson(_generateFamily(null)),
      latentTraits: parent.latentTraits
          .map((t) => t.copyWith(
                triggerProbability:
                    _mutate(t.triggerProbability, mutationRange),
              ))
          .toList(),
    );
  }

  /// 天赋遗传：父母天赋取较高值，15%概率同时继承双方天赋
  Map<String, double> _inheritTalents(
    Map<String, double> talentsA,
    Map<String, double> talentsB,
  ) {
    final dualInheritanceProb =
        _birthRules?['birth']?['genetics']?['dualTalentInheritance'] ?? 0.15;
    final allKeys = {...talentsA.keys, ...talentsB.keys};
    final result = <String, double>{};

    for (final key in allKeys) {
      final a = talentsA[key] ?? 0.0;
      final b = talentsB[key] ?? 0.0;

      if (talentsA.containsKey(key) && talentsB.containsKey(key)) {
        // 双方都有：取较高值 + 突变
        final higher = max(a, b);
        result[key] = _mutate(higher, 0.05);
      } else if (_rng.nextDouble() < dualInheritanceProb) {
        // 15% 概率继承单方天赋
        result[key] = _mutate(talentsA[key] ?? talentsB[key]!, 0.05);
      }
    }

    // 确保至少有1个天赋
    if (result.isEmpty) {
      const fallback = ['语言', '直觉', '共情'];
      final pick = fallback[_rng.nextInt(fallback.length)];
      result[pick] = 0.3 + _rng.nextDouble() * 0.4;
    }

    return result;
  }

  /// 潜在特质遗传：随机继承 + 突变
  List<LatentTrait> _inheritLatentTraits(
    List<LatentTrait> traitsA,
    List<LatentTrait> traitsB,
  ) {
    final traitCountRange =
        _birthRules?['birth']?['genetics']?['latentTraitCount'] ?? [2, 3];
    final minCount = traitCountRange[0] as int;
    final maxCount = traitCountRange[1] as int;
    final targetCount = minCount + _rng.nextInt(maxCount - minCount + 1);

    // 合并双方特质池
    final pool = [...traitsA, ...traitsB];
    pool.shuffle(_rng);

    // 取前 N 个，轻微突变
    return pool.take(targetCount).map((t) {
      return t.copyWith(
        triggerProbability: _mutate(t.triggerProbability, 0.05),
        effect: t.effect.map((k, v) => MapEntry(k, _mutate(v, 0.03))),
      );
    }).toList();
  }

  /// 生成原生家庭
  Map<String, dynamic> _generateFamily(GeneProfile? genes) {
    final familyConfig =
        _birthRules?['birth']?['family'] as Map<String, dynamic>? ?? {};

    // 概率加权选择家庭类型
    final roll = _rng.nextDouble();
    double cumulative = 0.0;

    final wealthyCold = (familyConfig['wealthyColdProbability'] ?? 0.15) as num;
    final poorWarm = (familyConfig['poorWarmProbability'] ?? 0.15) as num;
    final strict = (familyConfig['strictFamilyProbability'] ?? 0.2) as num;
    final neglect = (familyConfig['neglectFamilyProbability'] ?? 0.1) as num;

    String type;
    double wealth, warmth, strictness;

    cumulative += wealthyCold.toDouble();
    if (roll < cumulative) {
      type = 'wealthy_cold';
      wealth = 0.7 + _rng.nextDouble() * 0.3;
      warmth = _rng.nextDouble() * 0.3;
      strictness = 0.5 + _rng.nextDouble() * 0.3;
    } else {
      cumulative += poorWarm.toDouble();
      if (roll < cumulative) {
        type = 'poor_warm';
        wealth = _rng.nextDouble() * 0.3;
        warmth = 0.7 + _rng.nextDouble() * 0.3;
        strictness = _rng.nextDouble() * 0.4;
      } else {
        cumulative += strict.toDouble();
        if (roll < cumulative) {
          type = 'strict';
          wealth = 0.3 + _rng.nextDouble() * 0.5;
          warmth = 0.3 + _rng.nextDouble() * 0.4;
          strictness = 0.7 + _rng.nextDouble() * 0.3;
        } else {
          cumulative += neglect.toDouble();
          if (roll < cumulative) {
            type = 'neglect';
            wealth = _rng.nextDouble() * 0.5;
            warmth = _rng.nextDouble() * 0.3;
            strictness = _rng.nextDouble() * 0.3;
          } else {
            type = 'normal';
            wealth = 0.3 + _rng.nextDouble() * 0.4;
            warmth = 0.4 + _rng.nextDouble() * 0.4;
            strictness = 0.3 + _rng.nextDouble() * 0.4;
          }
        }
      }
    }

    final descriptions = {
      'wealthy_cold': '富裕但冷漠的家庭',
      'poor_warm': '清贫但温暖的家庭',
      'strict': '严格管教的家庭',
      'neglect': '被忽视的家庭',
      'normal': '普通工薪家庭',
    };

    return {
      'type': type,
      'description': descriptions[type] ?? '普通家庭',
      'wealth': wealth,
      'warmth': warmth,
      'strictness': strictness,
      'familyEvents': <String>[],
    };
  }

  /// 生成幼年烙印事件（1~3件童年关键事件）
  Future<List<Map<String, dynamic>>> _generateChildhoodImprints(
    LifeProfile profile,
    Map<String, dynamic> family,
  ) async {
    final config =
        _birthRules?['birth']?['childhood'] as Map<String, dynamic>? ?? {};
    final imprintCountRange = config['imprintCount'] ?? [1, 3];
    final minCount = imprintCountRange[0] as int;
    final maxCount = imprintCountRange[1] as int;
    final count = minCount + _rng.nextInt(maxCount - minCount + 1);
    final traumaThreshold =
        (config['traumaticWeightThreshold'] ?? 0.7) as num;

    final available = List<ImprintEvent>.from(_imprintPool);
    available.shuffle(_rng);

    final selected = <Map<String, dynamic>>[];

    for (final event in available) {
      if (selected.length >= count) break;

      // 检查触发条件
      bool canTrigger = true;

      // 创伤类事件需要特定家庭条件
      if (event.type == ImprintType.trauma) {
        final warmth = (family['warmth'] as num?)?.toDouble() ?? 0.5;

        // 被抛弃需要家庭温暖 < 0.4
        if (event.id == 'abandoned_by_parents' && warmth >= 0.4) {
          canTrigger = false;
        }
        // 被排挤需要外向性较低
        if (event.id == 'excluded_by_peers' &&
            profile.genes.extraversion > 0.6) {
          canTrigger = false;
        }
        // 高创伤权重事件受阈值限制
        if (event.weight > traumaThreshold.toDouble() &&
            _rng.nextDouble() > 0.5) {
          canTrigger = false;
        }
      }

      // 温暖类事件需要特定家庭条件
      if (event.type == ImprintType.warmth) {
        final warmth = (family['warmth'] as num?)?.toDouble() ?? 0.5;

        // 无条件的爱需要家庭温暖 > 0.5
        if (event.id == 'unconditional_love' && warmth < 0.5) {
          canTrigger = false;
        }
        // 被偏爱需要家庭非严格
        if (event.id == 'favored_child') {
          final strictness =
              (family['strictness'] as num?)?.toDouble() ?? 0.5;
          if (strictness > 0.7) canTrigger = false;
        }
      }

      if (canTrigger) {
        // 随机确定烙印发生年龄
        final ageRange = config['imprintAgeRange'] ?? [0, 6];
        final imprintAge =
            (ageRange[0] as int) + _rng.nextInt((ageRange[1] as int) - (ageRange[0] as int));

        selected.add({
          'imprint': event,
          'age': imprintAge,
          'timestamp': DateTime.now()
              .subtract(Duration(days: (imprintAge * 365).toInt()))
              .toIso8601String(),
        });
      }
    }

    // 确保至少有1个事件
    if (selected.isEmpty && available.isNotEmpty) {
      final fallback = available.first;
      selected.add({
        'imprint': fallback,
        'age': _rng.nextInt(6),
        'timestamp': DateTime.now().toIso8601String(),
      });
    }

    return selected;
  }

  /// 应用烙印效果到人格
  LifeProfile _applyImprintEffect(
    LifeProfile profile,
    Map<String, dynamic> imprintData,
  ) {
    final imprint = imprintData['imprint'] as ImprintEvent;
    final age = imprintData['age'] as int;

    // 更新人格状态
    final currentPersonality =
        Map<String, dynamic>.from(profile.personalityState);
    for (final entry in imprint.personalityEffect.entries) {
      final current = (currentPersonality[entry.key] as num?)?.toDouble() ?? 0.5;
      currentPersonality[entry.key] = (current + entry.value).clamp(0.0, 1.0);
    }

    // 更新情绪状态
    final currentEmotional =
        Map<String, dynamic>.from(profile.emotionalState);
    for (final entry in imprint.emotionalEffect.entries) {
      final current = (currentEmotional[entry.key] as num?)?.toDouble() ?? 0.5;
      currentEmotional[entry.key] = (current + entry.value).clamp(0.0, 1.0);
    }

    // 记录生命事件
    final events = List<Map<String, dynamic>>.from(profile.lifeEvents);
    events.add({
      'type': 'imprint',
      'imprintId': imprint.id,
      'imprintType': imprint.type == ImprintType.trauma ? 'trauma' : 'warmth',
      'name': imprint.name,
      'description': imprint.description,
      'age': age,
      'weight': imprint.weight,
      'timestamp': imprintData['timestamp'] as String,
    });

    return profile.copyWith(
      personalityState: currentPersonality,
      emotionalState: currentEmotional,
      lifeEvents: events,
    );
  }

  /// 生成名字
  String _generateName(Map<String, dynamic> birthConfig) {
    final naming = birthConfig['naming'] as Map<String, dynamic>? ?? {};
    final style = naming['style'] as String? ?? 'random';

    switch (style) {
      case 'cultural':
        return _generateCulturalName();
      case 'user_defined':
        return '未命名'; // 等待用户输入
      case 'random':
      default:
        return _generateRandomName();
    }
  }

  /// 随机生成名字
  String _generateRandomName() {
    const surnames = [
      '林', '陈', '张', '李', '王', '刘', '赵', '周', '吴', '徐',
      '孙', '马', '朱', '胡', '郭', '何', '高', '罗', '郑', '梁',
    ];
    const givenNames = [
      '小雨', '小风', '小雪', '小晴', '小星',
      '小月', '小云', '小溪', '小竹', '小兰',
      '小梅', '小荷', '小松', '小柏', '小楠',
      '安然', '乐天', '思远', '知秋', '念夏',
    ];

    final surname = surnames[_rng.nextInt(surnames.length)];
    final given = givenNames[_rng.nextInt(givenNames.length)];
    return '$surname$given';
  }

  /// 有文化背景的名字生成
  String _generateCulturalName() {
    const names = [
      '清风', '明月', '知行', '致远', '若水',
      '怀瑾', '握瑜', '思齐', '观澜', '听雨',
      '望舒', '扶摇', '凌霄', '栖桐', '采薇',
    ];
    return names[_rng.nextInt(names.length)];
  }

  /// 初始化人格状态
  Map<String, dynamic> _initializePersonalityState(GeneProfile genes) {
    return {
      'openness': genes.openness,
      'conscientiousness': genes.conscientiousness,
      'extraversion': genes.extraversion,
      'agreeableness': genes.agreeableness,
      'neuroticism': genes.neuroticism,
      'mood': 0.6, // 初始心情偏积极
      'energy': 0.8, // 初始精力充沛
    };
  }

  /// 初始化情绪状态
  Map<String, dynamic> _initializeEmotionalState(GeneProfile genes) {
    return {
      'happiness': 0.5,
      'sadness': 0.1,
      'anger': 0.05,
      'fear': 0.1,
      'surprise': 0.2,
      'trust': 0.4,
      'security': 0.5 + (genes.family.warmth * 0.3),
      'loneliness': 0.2,
      'self_worth': 0.5,
      'social_confidence': genes.extraversion * 0.7,
    };
  }

  /// 初始化身体状态
  Map<String, dynamic> _initializePhysicalState(GeneProfile genes) {
    return {
      'health': 0.9 + (genes.vitality * 0.1),
      'stamina': 0.7 + (genes.vitality * 0.3),
      'appearance': _rng.nextDouble(), // 天生外貌随机
      'constitution': genes.vitality,
    };
  }

  /// 初始化马斯洛需求状态
  Map<String, dynamic> _initializeMaslowState(
    GeneProfile genes,
    Map<String, dynamic> family,
  ) {
    final warmth = (family['warmth'] as num?)?.toDouble() ?? 0.5;
    final wealth = (family['wealth'] as num?)?.toDouble() ?? 0.5;

    return {
      'physiological': 0.8 + (wealth * 0.2), // 基本生理需求
      'safety': 0.6 + (warmth * 0.3), // 安全需求
      'belonging': 0.5 + (warmth * 0.4), // 归属需求
      'esteem': 0.4, // 尊重需求（后天发展）
      'selfActualization': 0.1, // 自我实现（需长期成长）
    };
  }
}
