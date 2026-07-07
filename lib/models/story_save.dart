/// 故事书独立存档 — 记录某一进度点，读档可完整恢复当时的全部剧情与参数
class StorySave {
  final String id;
  final String storyId;
  final String name;
  final int segmentCount; // 存档时的剧情段落数
  final int narratorRole; // 存档时的叙事视角
  final DateTime createdAt;
  final DateTime updatedAt;
  final int syncSeq;

  const StorySave({
    required this.id,
    required this.storyId,
    this.name = '',
    this.segmentCount = 0,
    this.narratorRole = 0,
    required this.createdAt,
    required this.updatedAt,
    this.syncSeq = 0,
  });

  StorySave copyWith({
    String? id,
    String? storyId,
    String? name,
    int? segmentCount,
    int? narratorRole,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? syncSeq,
  }) {
    return StorySave(
      id: id ?? this.id,
      storyId: storyId ?? this.storyId,
      name: name ?? this.name,
      segmentCount: segmentCount ?? this.segmentCount,
      narratorRole: narratorRole ?? this.narratorRole,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncSeq: syncSeq ?? this.syncSeq,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'storyId': storyId,
        'name': name,
        'segmentCount': segmentCount,
        'narratorRole': narratorRole,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'sync_seq': syncSeq,
      };

  factory StorySave.fromMap(Map<String, dynamic> map) {
    return StorySave(
      id: map['id'] as String,
      storyId: map['storyId'] as String? ?? '',
      name: map['name'] as String? ?? '',
      segmentCount: (map['segmentCount'] as num?)?.toInt() ?? 0,
      narratorRole: (map['narratorRole'] as num?)?.toInt() ?? 0,
      createdAt:
          DateTime.tryParse(map['createdAt'] as String? ?? '') ?? DateTime.now(),
      updatedAt:
          DateTime.tryParse(map['updatedAt'] as String? ?? '') ?? DateTime.now(),
      syncSeq: (map['sync_seq'] ?? map['syncSeq']) as int? ?? 0,
    );
  }
}
