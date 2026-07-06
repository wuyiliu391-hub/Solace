// ============================================================
// 全生命周期数字生命世界 — Phase 4
// 关系图谱模型：多维关系光谱 + 动态事件链
// 修复 — 编码重建，结构保留
// ============================================================

import 'dart:convert';
import 'package:equatable/equatable.dart';

/// 关系类型
enum RelationshipType {
  stranger,
  friend,
  bestFriend,
  crush,
  lover,
  rival,
  enemy,
  sibling,
  mentor,
  follower;

  String get label {
    switch (this) {
      case RelationshipType.stranger:
        return '陌生人';
      case RelationshipType.friend:
        return '朋友';
      case RelationshipType.bestFriend:
        return '挚友';
      case RelationshipType.crush:
        return '暗恋';
      case RelationshipType.lover:
        return '恋人';
      case RelationshipType.rival:
        return '对手';
      case RelationshipType.enemy:
        return '敌人';
      case RelationshipType.sibling:
        return '兄弟姐妹';
      case RelationshipType.mentor:
        return '师徒';
      case RelationshipType.follower:
        return '追随者';
    }
  }

  /// 从数值索引获取
  static RelationshipType fromIndex(int index) {
    return RelationshipType.values[
        index.clamp(0, RelationshipType.values.length - 1)];
  }
}

/// 关系事件类型
enum RelationshipEventType {
  conflict,
  reconciliation,
  betrayal,
  kindness,
  gift,
  argument,
  support,
  abandonment,
  revelation,
  sharedExperience,
  misunderstanding,
  forgiveness;

  String get label {
    switch (this) {
      case RelationshipEventType.conflict:
        return '冲突';
      case RelationshipEventType.reconciliation:
        return '和解';
      case RelationshipEventType.betrayal:
        return '背叛';
      case RelationshipEventType.kindness:
        return '善意';
      case RelationshipEventType.gift:
        return '赠礼';
      case RelationshipEventType.argument:
        return '争吵';
      case RelationshipEventType.support:
        return '支持';
      case RelationshipEventType.abandonment:
        return '抛弃';
      case RelationshipEventType.revelation:
        return '秘密揭露';
      case RelationshipEventType.sharedExperience:
        return '共同经历';
      case RelationshipEventType.misunderstanding:
        return '误会';
      case RelationshipEventType.forgiveness:
        return '原谅';
    }
  }

  /// 默认影响值（正值改善关系，负值恶化关系）
  double get defaultImpact {
    switch (this) {
      case RelationshipEventType.conflict:
        return -15;
      case RelationshipEventType.reconciliation:
        return 20;
      case RelationshipEventType.betrayal:
        return -30;
      case RelationshipEventType.kindness:
        return 10;
      case RelationshipEventType.gift:
        return 8;
      case RelationshipEventType.argument:
        return -10;
      case RelationshipEventType.support:
        return 15;
      case RelationshipEventType.abandonment:
        return -25;
      case RelationshipEventType.revelation:
        return 0; // variable impact
      case RelationshipEventType.sharedExperience:
        return 12;
      case RelationshipEventType.misunderstanding:
        return -8;
      case RelationshipEventType.forgiveness:
        return 18;
    }
  }
}

/// 关系事件：单次交互记录
class RelationshipEvent extends Equatable {
  final String id;
  final DateTime timestamp;
  final String description;
  final double impact;
  final RelationshipEventType type;
  final double intensity;
  final bool isPublic;

  const RelationshipEvent({
    required this.id,
    required this.timestamp,
    required this.description,
    required this.impact,
    required this.type,
    this.intensity = 0.5,
    this.isPublic = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'description': description,
        'impact': impact,
        'type': type.index,
        'intensity': intensity,
        'isPublic': isPublic,
      };

  factory RelationshipEvent.fromJson(Map<String, dynamic> json) =>
      RelationshipEvent(
        id: json['id'] as String? ?? '',
        timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ??
            DateTime.now(),
        description: json['description'] as String? ?? '',
        impact: (json['impact'] as num?)?.toDouble() ?? 0.0,
        type: _safeEnumIndex(
          json['type'] as int?,
          RelationshipEventType.values,
          RelationshipEventType.kindness,
        ),
        intensity: (json['intensity'] as num?)?.toDouble() ?? 0.5,
        isPublic: json['isPublic'] as bool? ?? false,
      );

  @override
  List<Object?> get props => [id, timestamp, description, impact, type];
}

/// 关系（两人之间）：包含多维关系光谱 + 动态事件链
class RelationshipGraph extends Equatable {
  final String id;
  final String personIdA;
  final String personIdB;
  double intimacy;
  double trust;
  double respect;
  double familiarity;
  List<String> tags;
  double tension;
  double passion;
  double commitment;
  List<RelationshipEvent> events;
  final DateTime createdAt;
  DateTime updatedAt;

  RelationshipGraph({
    required this.id,
    required this.personIdA,
    required this.personIdB,
    this.intimacy = 0.0,
    this.trust = 0.0,
    this.respect = 0.0,
    this.familiarity = 0.0,
    this.tags = const [],
    this.tension = 0.0,
    this.passion = 0.0,
    this.commitment = 0.0,
    this.events = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  /// 根据多维数值推断关系类型
  RelationshipType get inferredType {
    if (intimacy > 0.6 && passion > 0.4) return RelationshipType.lover;
    if (intimacy > 0.4 && trust < 0.2) return RelationshipType.crush;
    if (intimacy > 0.5 && trust > 0.5) return RelationshipType.bestFriend;
    if (familiarity > 0.6 && trust > 0.4 && intimacy > 0.3) {
      return RelationshipType.sibling;
    }
    if (respect > 0.4 && trust > 0.3) return RelationshipType.mentor;
    if (respect > 0.5 && intimacy < 0.3) return RelationshipType.follower;
    if (respect > 0.2 && intimacy < -0.2) return RelationshipType.rival;
    if (intimacy < -0.4 && tension > 0.5) return RelationshipType.enemy;
    if (intimacy > 0.2 && trust > 0.2) return RelationshipType.friend;
    return RelationshipType.stranger;
  }

  /// 关系稳定性因子（用于衰减计算）
  double get stabilityFactor {
    // High trust and low tension = stable relationship, decays slower
    return (1.0 - (trust.clamp(0.0, 1.0) * 0.5) +
            tension.clamp(0.0, 1.0) * 0.3)
        .clamp(0.1, 1.0);
  }

  /// 综合亲和度
  double get compositeAffinity =>
      intimacy * 0.4 + trust * 0.3 + familiarity * 0.2 + respect * 0.1;

  /// 是否亲密关系
  bool get isIntimate => intimacy > 0.5 && trust > 0.3;

  /// 是否处于冲突中
  bool get isInConflict => tension > 0.5 || intimacy < -0.3;

  /// 应用一个事件到关系
  void applyEvent(RelationshipEvent event) {
    events.add(event);
    switch (event.type) {
      case RelationshipEventType.kindness:
      case RelationshipEventType.gift:
        intimacy += event.impact * 0.3;
        trust += event.impact * 0.2;
        familiarity += event.intensity * 0.1;
        tension = (tension - event.intensity * 0.1).clamp(0.0, 1.0);
        break;
      case RelationshipEventType.support:
        intimacy += event.impact * 0.2;
        trust += event.impact * 0.3;
        respect += event.impact * 0.1;
        commitment += event.intensity * 0.1;
        break;
      case RelationshipEventType.conflict:
      case RelationshipEventType.argument:
        intimacy += event.impact * 0.3;
        tension = (tension + event.intensity * 0.3).clamp(0.0, 1.0);
        break;
      case RelationshipEventType.betrayal:
        trust += event.impact * 0.5;
        intimacy += event.impact * 0.3;
        respect += event.impact * 0.2;
        tension = (tension + event.intensity * 0.4).clamp(0.0, 1.0);
        if (!tags.contains('betrayed')) tags.add('betrayed');
        break;
      case RelationshipEventType.abandonment:
        intimacy += event.impact * 0.4;
        trust += event.impact * 0.4;
        commitment = (commitment + event.impact * 0.3).clamp(-1.0, 1.0);
        break;
      case RelationshipEventType.reconciliation:
        tension = (tension - event.intensity * 0.4).clamp(0.0, 1.0);
        trust += event.impact * 0.2;
        intimacy += event.impact * 0.1;
        break;
      case RelationshipEventType.forgiveness:
        trust += event.impact * 0.3;
        tension = (tension - event.intensity * 0.3).clamp(0.0, 1.0);
        tags.remove('betrayed');
        break;
      case RelationshipEventType.revelation:
        familiarity += event.intensity * 0.3;
        break;
      case RelationshipEventType.sharedExperience:
        familiarity += event.intensity * 0.2;
        intimacy += event.impact * 0.15;
        break;
      case RelationshipEventType.misunderstanding:
        trust += event.impact * 0.2;
        break;
    }
    intimacy = intimacy.clamp(-1.0, 1.0);
    trust = trust.clamp(-1.0, 1.0);
    respect = respect.clamp(-1.0, 1.0);
    familiarity = familiarity.clamp(0.0, 1.0);
    tension = tension.clamp(0.0, 1.0);
    passion = passion.clamp(0.0, 1.0);
    commitment = commitment.clamp(-1.0, 1.0);
    updatedAt = DateTime.now();
  }

  /// 时间衰减
  void decay(int daysElapsed) {
    if (daysElapsed <= 0) return;
    final decayRate = 0.01 * daysElapsed;
    passion = (passion - decayRate * 0.2).clamp(0.0, 1.0);
    intimacy =
        (intimacy - decayRate * 0.1 * stabilityFactor).clamp(-1.0, 1.0);
    trust = (trust - decayRate * 0.1 * stabilityFactor).clamp(-1.0, 1.0);
    updatedAt = DateTime.now();
  }

  /// 关系维度文本描述
  static String _spectrumDesc(
      double value, String negLabel, String midLabel, String posLabel) {
    if (value < -0.3) return '$negLabel${(value * 100).toStringAsFixed(0)}%';
    if (value > 0.3) return '$posLabel${(value * 100).toStringAsFixed(0)}%';
    return '$midLabel${(value * 100).toStringAsFixed(0)}%';
  }

  static String _familiarityDesc(double value) {
    if (value < 0.2) return '${(value * 100).toStringAsFixed(0)}%';
    if (value < 0.4) return '${(value * 100).toStringAsFixed(0)}%';
    if (value < 0.6) return '${(value * 100).toStringAsFixed(0)}%';
    if (value < 0.8) return '${(value * 100).toStringAsFixed(0)}%';
    return '${(value * 100).toStringAsFixed(0)}%';
  }

  @override
  String toString() {
    final buffer = StringBuffer();
    buffer.writeln('$personIdA <-> $personIdB');
    buffer.writeln('Type: ${inferredType.label}');
    if (tags.isNotEmpty) {
      buffer.writeln('Tags: ${tags.join(', ')}');
    }
    buffer.writeln(
        'Intimacy: ${_spectrumDesc(intimacy, 'low-', 'mid-', 'high-')}');
    buffer.writeln(
        'Trust: ${_spectrumDesc(trust, 'low-', 'mid-', 'high-')}');
    buffer.writeln(
        'Respect: ${_spectrumDesc(respect, 'low-', 'mid-', 'high-')}');
    buffer.writeln('Familiarity: ${_familiarityDesc(familiarity)}');
    if (tension > 0.3 || passion > 0.3 || commitment.abs() > 0.3) {
      buffer.writeln('-- Additional --');
      if (tension > 0.3) {
        buffer.writeln('  Tension: ${(tension * 100).toStringAsFixed(0)}%');
      }
      if (passion > 0.3) {
        buffer.writeln('  Passion: ${(passion * 100).toStringAsFixed(0)}%');
      }
      if (commitment > 0.3) {
        buffer.writeln(
            '  Commitment: ${(commitment * 100).toStringAsFixed(0)}%');
      }
    }
    final recentEvents = events.take(3).toList();
    if (recentEvents.isNotEmpty) {
      buffer.writeln('Recent events:');
      for (final event in recentEvents) {
        buffer.writeln(
            '  - ${event.description} (${event.type.label}) ${event.impact > 0 ? '+' : ''}${event.impact.toStringAsFixed(2)}');
      }
    }
    return buffer.toString();
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'personIdA': personIdA,
        'personIdB': personIdB,
        'intimacy': intimacy,
        'trust': trust,
        'respect': respect,
        'familiarity': familiarity,
        'tags': tags,
        'tension': tension,
        'passion': passion,
        'commitment': commitment,
        'events': events.map((e) => e.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory RelationshipGraph.fromJson(Map<String, dynamic> json) =>
      RelationshipGraph(
        id: json['id'] as String? ?? '',
        personIdA: json['personIdA'] as String? ?? '',
        personIdB: json['personIdB'] as String? ?? '',
        intimacy: (json['intimacy'] as num?)?.toDouble() ?? 0.0,
        trust: (json['trust'] as num?)?.toDouble() ?? 0.0,
        respect: (json['respect'] as num?)?.toDouble() ?? 0.0,
        familiarity: (json['familiarity'] as num?)?.toDouble() ?? 0.0,
        tags: (json['tags'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [],
        tension: (json['tension'] as num?)?.toDouble() ?? 0.0,
        passion: (json['passion'] as num?)?.toDouble() ?? 0.0,
        commitment: (json['commitment'] as num?)?.toDouble() ?? 0.0,
        events: (json['events'] as List<dynamic>?)
                ?.map(
                    (e) => RelationshipEvent.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
            DateTime.now(),
      );

  String toJsonString() => jsonEncode(toJson());

  factory RelationshipGraph.fromJsonString(String source) =>
      RelationshipGraph.fromJson(jsonDecode(source) as Map<String, dynamic>);

  RelationshipGraph copyWith({
    String? id,
    String? personIdA,
    String? personIdB,
    double? intimacy,
    double? trust,
    double? respect,
    double? familiarity,
    List<String>? tags,
    double? tension,
    double? passion,
    double? commitment,
    List<RelationshipEvent>? events,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return RelationshipGraph(
      id: id ?? this.id,
      personIdA: personIdA ?? this.personIdA,
      personIdB: personIdB ?? this.personIdB,
      intimacy: intimacy ?? this.intimacy,
      trust: trust ?? this.trust,
      respect: respect ?? this.respect,
      familiarity: familiarity ?? this.familiarity,
      tags: tags ?? List.from(this.tags),
      tension: tension ?? this.tension,
      passion: passion ?? this.passion,
      commitment: commitment ?? this.commitment,
      events: events ?? List.from(this.events),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        personIdA,
        personIdB,
        intimacy,
        trust,
        respect,
        familiarity,
        tags,
        tension,
        passion,
        commitment,
        events,
        createdAt,
        updatedAt,
      ];
}

/// 关系图谱管理器：管理多对角色之间关系的增删改查
class RelationshipGraphManager {
  final Map<String, RelationshipGraph> _graphs = {};

  RelationshipGraphManager();

  /// 获取两个角色之间的关系
  RelationshipGraph? getGraph(String personIdA, String personIdB) {
    final key = _sortedPairKey(personIdA, personIdB);
    return _graphs[key];
  }

  /// 获取或创建两个角色之间的关系
  RelationshipGraph getOrCreateGraph(String personIdA, String personIdB) {
    final key = _sortedPairKey(personIdA, personIdB);
    if (_graphs.containsKey(key)) return _graphs[key]!;
    final graph = RelationshipGraph(
      id: key,
      personIdA: personIdA,
      personIdB: personIdB,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    _graphs[key] = graph;
    return graph;
  }

  /// 获取某个角色的所有关系
  List<RelationshipGraph> getRelationships(String personId) {
    return _graphs.values
        .where((g) => g.personIdA == personId || g.personIdB == personId)
        .toList();
  }

  /// 获取某个角色的亲密关系
  List<RelationshipGraph> getIntimateRelationships(String personId) {
    return getRelationships(personId).where((g) => g.isIntimate).toList();
  }

  /// 添加事件到两个角色的关系中
  void addEvent(
    String personIdA,
    String personIdB,
    RelationshipEvent event,
  ) {
    final graph = getOrCreateGraph(personIdA, personIdB);
    graph.applyEvent(event);
  }

  /// 对所有关系应用时间衰减
  void applyDecay(int daysElapsed) {
    for (final graph in _graphs.values) {
      graph.decay(daysElapsed);
    }
  }

  /// 删除两个角色之间的关系
  void removeRelationship(String personIdA, String personIdB) {
    final key = _sortedPairKey(personIdA, personIdB);
    _graphs.remove(key);
  }

  /// 删除某个角色的所有关系
  void removeAllRelationships(String personId) {
    _graphs.removeWhere(
        (key, graph) => graph.personIdA == personId || graph.personIdB == personId);
  }

  /// 获取所有关系
  List<RelationshipGraph> getAllGraphs() => _graphs.values.toList();

  /// 关系数量
  int get count => _graphs.length;

  Map<String, dynamic> toJson() {
    return {
      'graphs': _graphs.map((key, graph) => MapEntry(key, graph.toJson())),
    };
  }

  factory RelationshipGraphManager.fromJson(Map<String, dynamic> json) {
    final manager = RelationshipGraphManager();
    final graphs = json['graphs'] as Map<String, dynamic>? ?? {};
    for (final entry in graphs.entries) {
      manager._graphs[entry.key] =
          RelationshipGraph.fromJson(entry.value as Map<String, dynamic>);
    }
    return manager;
  }

  /// 生成排序后的对偶键
  static String _sortedPairKey(String a, String b) {
    return a.compareTo(b) < 0 ? '${a}_$b' : '${b}_$a';
  }
}

/// 安全地获取枚举实例（应对 JSON 索引越界）
T _safeEnumIndex<T>(int? index, List<T> values, T fallback) {
  if (index == null || index < 0 || index >= values.length) return fallback;
  return values[index];
}
