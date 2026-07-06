import 'package:equatable/equatable.dart';

enum MemoryType {
  conversation,
  reflection,
  milestone,
  emotion,
  preference,
  state,
  rollingSummary,
}

enum MemoryImportance {
  trivial,
  normal,
  important,
  crucial,
}

class Memory extends Equatable {
  final String id;
  final String characterId;
  final String userId;
  final MemoryType type;
  final String content;
  final MemoryImportance importance;
  final List<String> keywords;
  final DateTime createdAt;
  final DateTime? lastAccessedAt;
  final int accessCount;
  final int syncSeq;

  // ── v2 艾宾浩斯热度系统 ──
  final double weight; // 0.0~2.0，热度权重，1.0=默认
  final bool pinned; // 是否锁定（不衰减）
  final DateTime? lastRecalledAt; // 上次被回忆的时间（注入prompt时更新）

  const Memory({
    required this.id,
    required this.characterId,
    required this.userId,
    required this.type,
    required this.content,
    this.importance = MemoryImportance.normal,
    this.keywords = const [],
    required this.createdAt,
    this.lastAccessedAt,
    this.accessCount = 0,
    this.syncSeq = 0,
    this.weight = 1.0,
    this.pinned = false,
    this.lastRecalledAt,
  });

  Memory copyWith({
    String? id,
    String? characterId,
    String? userId,
    MemoryType? type,
    String? content,
    MemoryImportance? importance,
    List<String>? keywords,
    DateTime? createdAt,
    DateTime? lastAccessedAt,
    int? accessCount,
    int? syncSeq,
    double? weight,
    bool? pinned,
    DateTime? lastRecalledAt,
  }) {
    return Memory(
      id: id ?? this.id,
      characterId: characterId ?? this.characterId,
      userId: userId ?? this.userId,
      type: type ?? this.type,
      content: content ?? this.content,
      importance: importance ?? this.importance,
      keywords: keywords ?? this.keywords,
      createdAt: createdAt ?? this.createdAt,
      lastAccessedAt: lastAccessedAt ?? this.lastAccessedAt,
      accessCount: accessCount ?? this.accessCount,
      syncSeq: syncSeq ?? this.syncSeq,
      weight: weight ?? this.weight,
      pinned: pinned ?? this.pinned,
      lastRecalledAt: lastRecalledAt ?? this.lastRecalledAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'characterId': characterId,
      'userId': userId,
      'type': type.index,
      'content': content,
      'importance': importance.index,
      'keywords': keywords.join(','),
      'createdAt': createdAt.toIso8601String(),
      'lastAccessedAt': lastAccessedAt?.toIso8601String(),
      'accessCount': accessCount,
      'sync_seq': syncSeq,
      'weight': weight,
      'pinned': pinned ? 1 : 0,
      'lastRecalledAt': lastRecalledAt?.toIso8601String(),
    };
  }

  factory Memory.fromMap(Map<String, dynamic> map) {
    return Memory(
      id: map['id'] as String,
      characterId: map['characterId'] as String,
      userId: map['userId'] as String,
      type: _safeEnumIndex(map['type'] as int?, MemoryType.values, MemoryType.conversation),
      content: map['content'] as String,
      importance: _safeEnumIndex(map['importance'] as int?, MemoryImportance.values, MemoryImportance.normal),
      keywords: (map['keywords'] as String?)?.isNotEmpty == true
          ? (map['keywords'] as String).split(',').where((k) => k.isNotEmpty).toList()
          : [],
      createdAt: DateTime.tryParse(map['createdAt'] as String? ?? '') ?? DateTime.now(),
      lastAccessedAt: map['lastAccessedAt'] != null
          ? DateTime.tryParse(map['lastAccessedAt'] as String? ?? '')
          : null,
      accessCount: map['accessCount'] as int? ?? 0,
      syncSeq: (map['sync_seq'] ?? map['syncSeq']) as int? ?? 0,
      weight: (map['weight'] as num?)?.toDouble() ?? 1.0,
      pinned: (map['pinned'] as int?) == 1,
      lastRecalledAt: map['lastRecalledAt'] != null
          ? DateTime.tryParse(map['lastRecalledAt'] as String? ?? '')
          : null,
    );
  }

  @override
  List<Object?> get props => [
        id,
        characterId,
        userId,
        type,
        content,
        importance,
        keywords,
        createdAt,
        lastAccessedAt,
        accessCount,
        syncSeq,
        weight,
        pinned,
        lastRecalledAt,
      ];

  static T _safeEnumIndex<T>(int? index, List<T> values, T fallback) {
    if (index == null || index < 0 || index >= values.length) return fallback;
    return values[index];
  }
}
