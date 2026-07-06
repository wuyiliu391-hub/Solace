// ============================================================
// 全生命周期数字生命世界 — Phase 2
// 生命事件模型：影响人格、三观、身份认同的事件
// ============================================================

import 'package:equatable/equatable.dart';

/// 事件影响维度
enum EventDimension {
  personality, // 影响人格
  worldview, // 影响三观
  identity, // 影响身份认同
  emotion, // 影响情绪
  relationship, // 影响关系
  physical, // 影响身体
}

/// 事件严重程度
enum EventSeverity {
  trivial, // 微不足道
  minor, // 轻微
  moderate, // 中等
  major, // 重大
  lifeChanging, // 改变人生
}

/// 生命事件 — 对数字生命产生影响的事件
class LifeEvent extends Equatable {
  final String id;
  final String description; // 事件描述
  final DateTime timestamp; // 发生时间
  final EventSeverity severity; // 严重程度
  final List<EventDimension> dimensions; // 影响维度
  final Map<String, double> impacts; // 具体影响值 {"openness": 0.1, "trustVsSuspicion": -0.2}
  final String? category; // 事件分类（如 "创伤", "成就", "关系"）
  final Map<String, dynamic> metadata; // 附加数据

  const LifeEvent({
    required this.id,
    required this.description,
    required this.timestamp,
    this.severity = EventSeverity.moderate,
    this.dimensions = const [],
    this.impacts = const {},
    this.category,
    this.metadata = const {},
  });

  /// 事件是否影响指定维度
  bool affects(EventDimension dimension) => dimensions.contains(dimension);

  /// 获取指定维度的影响值，不存在返回 0
  double impactOf(String key) => impacts[key] ?? 0.0;

  LifeEvent copyWith({
    String? id,
    String? description,
    DateTime? timestamp,
    EventSeverity? severity,
    List<EventDimension>? dimensions,
    Map<String, double>? impacts,
    String? category,
    Map<String, dynamic>? metadata,
  }) {
    return LifeEvent(
      id: id ?? this.id,
      description: description ?? this.description,
      timestamp: timestamp ?? this.timestamp,
      severity: severity ?? this.severity,
      dimensions: dimensions ?? this.dimensions,
      impacts: impacts ?? this.impacts,
      category: category ?? this.category,
      metadata: metadata ?? this.metadata,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'description': description,
      'timestamp': timestamp.toIso8601String(),
      'severity': severity.index,
      'dimensions': dimensions.map((d) => d.index).toList(),
      'impacts': impacts,
      'category': category,
      'metadata': metadata,
    };
  }

  factory LifeEvent.fromJson(Map<String, dynamic> json) {
    return LifeEvent(
      id: json['id'] as String? ?? '',
      description: json['description'] as String? ?? '',
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
      severity: _safeEnumIndex(
        json['severity'] as int?,
        EventSeverity.values,
        EventSeverity.moderate,
      ),
      dimensions: (json['dimensions'] as List<dynamic>?)
              ?.map((i) => _safeEnumIndex(
                    i as int?,
                    EventDimension.values,
                    EventDimension.personality,
                  ))
              .toList() ??
          [],
      impacts: (json['impacts'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, (v as num).toDouble())) ??
          {},
      category: json['category'] as String?,
      metadata: (json['metadata'] as Map<String, dynamic>?) ?? {},
    );
  }

  static T _safeEnumIndex<T>(int? index, List<T> values, T fallback) {
    if (index == null || index < 0 || index >= values.length) return fallback;
    return values[index];
  }

  @override
  List<Object?> get props => [
        id,
        description,
        timestamp,
        severity,
        dimensions,
        impacts,
        category,
        metadata,
      ];
}
