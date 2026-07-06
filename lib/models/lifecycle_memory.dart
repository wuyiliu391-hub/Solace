// ============================================================
// 全生命周期数字生命世界 — Phase 3
// 生命周期记忆模型：遗忘曲线系统的核心数据结构
// ============================================================

import 'dart:convert';
import 'package:equatable/equatable.dart';

/// 记忆类型 — 覆盖数字生命全生命周期的记忆分类
enum LifecycleMemoryType {
  event,        // 事件记忆：经历过的具体事件
  relationship, // 关系记忆：与他人的互动和关系
  trauma,       // 创伤记忆：重大负面经历（受保护，永不完全遗忘）
  reflection,   // 反思记忆：对经历的内省和领悟
  identity,     // 身份记忆：自我认知和身份认同
  skill,        // 技能记忆：习得的能力和知识
  sensory,      // 感官记忆：感官体验和印象
}

/// 生命周期记忆 — 遗忘曲线系统的核心模型
///
/// 基于 Ebbinghaus 遗忘曲线，记忆会随时间自然衰减。
/// 情感权重和回忆次数可以延缓遗忘。
/// 创伤记忆受特殊保护，永不完全遗忘。
class LifecycleMemory extends Equatable {
  final String id;
  final String ownerId;           // 所属生命体 ID
  final LifecycleMemoryType type;
  final String content;
  final DateTime timestamp;
  final double emotionalWeight;   // 0.0 ~ 1.0，情感强度
  final double importance;        // 0.0 ~ 1.0，重要程度
  final List<String> tags;
  final String? relatedPersonId;  // 关联的人物 ID

  // ── 遗忘系统字段 ──
  final double initialStrength;   // 初始强度（创建时固定）
  double currentStrength;         // 当前强度（随时间衰减）
  int recallCount;                // 被回忆的次数
  DateTime? lastRecallTime;       // 上次被回忆的时间
  bool archived;                  // 是否已归档（保留率过低时归档，不删除）

  LifecycleMemory({
    required this.id,
    required this.ownerId,
    required this.type,
    required this.content,
    required this.timestamp,
    this.emotionalWeight = 0.0,
    this.importance = 0.5,
    this.tags = const [],
    this.relatedPersonId,
    double? initialStrength,
    double? currentStrength,
    this.recallCount = 0,
    this.lastRecallTime,
    this.archived = false,
  })  : initialStrength = initialStrength ?? 1.0,
        currentStrength = currentStrength ?? 1.0;

  /// 是否为创伤记忆
  bool get isTrauma => type == LifecycleMemoryType.trauma;

  /// 记忆年龄（小时）
  double ageInHours(DateTime now) {
    return now.difference(timestamp).inMinutes / 60.0;
  }

  // ── 序列化 ──

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'ownerId': ownerId,
      'type': type.index,
      'content': content,
      'timestamp': timestamp.toIso8601String(),
      'emotionalWeight': emotionalWeight,
      'importance': importance,
      'tags': tags,
      'relatedPersonId': relatedPersonId,
      'initialStrength': initialStrength,
      'currentStrength': currentStrength,
      'recallCount': recallCount,
      'lastRecallTime': lastRecallTime?.toIso8601String(),
      'archived': archived,
    };
  }

  factory LifecycleMemory.fromJson(Map<String, dynamic> json) {
    return LifecycleMemory(
      id: json['id'] as String? ?? '',
      ownerId: json['ownerId'] as String? ?? '',
      type: _safeEnumIndex(
        json['type'] as int?,
        LifecycleMemoryType.values,
        LifecycleMemoryType.event,
      ),
      content: json['content'] as String? ?? '',
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.now(),
      emotionalWeight:
          (json['emotionalWeight'] as num?)?.toDouble() ?? 0.0,
      importance: (json['importance'] as num?)?.toDouble() ?? 0.5,
      tags: (json['tags'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      relatedPersonId: json['relatedPersonId'] as String?,
      initialStrength:
          (json['initialStrength'] as num?)?.toDouble() ?? 1.0,
      currentStrength:
          (json['currentStrength'] as num?)?.toDouble() ?? 1.0,
      recallCount: json['recallCount'] as int? ?? 0,
      lastRecallTime: json['lastRecallTime'] != null
          ? DateTime.tryParse(json['lastRecallTime'] as String? ?? '')
          : null,
      archived: json['archived'] as bool? ?? false,
    );
  }

  String toJsonString() => jsonEncode(toJson());

  factory LifecycleMemory.fromJsonString(String source) =>
      LifecycleMemory.fromJson(jsonDecode(source) as Map<String, dynamic>);

  // ── copyWith ──

  LifecycleMemory copyWith({
    String? id,
    String? ownerId,
    LifecycleMemoryType? type,
    String? content,
    DateTime? timestamp,
    double? emotionalWeight,
    double? importance,
    List<String>? tags,
    String? relatedPersonId,
    double? initialStrength,
    double? currentStrength,
    int? recallCount,
    DateTime? lastRecallTime,
    bool? archived,
  }) {
    return LifecycleMemory(
      id: id ?? this.id,
      ownerId: ownerId ?? this.ownerId,
      type: type ?? this.type,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      emotionalWeight: emotionalWeight ?? this.emotionalWeight,
      importance: importance ?? this.importance,
      tags: tags ?? this.tags,
      relatedPersonId: relatedPersonId ?? this.relatedPersonId,
      initialStrength: initialStrength ?? this.initialStrength,
      currentStrength: currentStrength ?? this.currentStrength,
      recallCount: recallCount ?? this.recallCount,
      lastRecallTime: lastRecallTime ?? this.lastRecallTime,
      archived: archived ?? this.archived,
    );
  }

  // ── Equatable ──

  @override
  List<Object?> get props => [
        id,
        ownerId,
        type,
        content,
        timestamp,
        emotionalWeight,
        importance,
        tags,
        relatedPersonId,
        initialStrength,
        currentStrength,
        recallCount,
        lastRecallTime,
        archived,
      ];

  // ── 工具方法 ──

  static T _safeEnumIndex<T>(int? index, List<T> values, T fallback) {
    if (index == null || index < 0 || index >= values.length) return fallback;
    return values[index];
  }

  @override
  String toString() =>
      'LifecycleMemory(id: $id, type: ${type.name}, '
      'strength: ${currentStrength.toStringAsFixed(3)}, '
      'recalls: $recallCount, archived: $archived)';
}
