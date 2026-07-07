import 'dart:convert';

/// 叙事视角
enum NarratorRole {
  protagonist, // 主角视角
  supporting, // 配角视角
}

extension NarratorRoleX on NarratorRole {
  String get label => switch (this) {
        NarratorRole.protagonist => '主角',
        NarratorRole.supporting => '配角',
      };
}

/// 剧情风格
enum StoryGenre {
  romance, // 现实情感
  yandere, // 病娇向
  darkArt, // 暗黑文艺
  free, // 自由
}

extension StoryGenreX on StoryGenre {
  String get label => switch (this) {
        StoryGenre.romance => '现实情感',
        StoryGenre.yandere => '病娇向',
        StoryGenre.darkArt => '暗黑文艺',
        StoryGenre.free => '自由创作',
      };
}

/// 故事书 — 书架上的一本独立剧情，自带专属存档，与其他模块完全隔离
class StoryBook {
  final String id;
  final String userId;
  final String title;
  final String? coverUrl;
  final String synopsis; // 简介
  final String worldSetting; // 世界观设定
  final StoryGenre genre;
  final NarratorRole narratorRole; // 当前叙事视角
  final List<String> participantCharacterIds; // 导入的通讯录角色 id
  final String? currentSaveId; // 当前激活存档
  final bool isArchived;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? lastSegmentPreview; // 书架卡片上的最近剧情预览
  final int syncSeq;

  const StoryBook({
    required this.id,
    required this.userId,
    required this.title,
    this.coverUrl,
    this.synopsis = '',
    this.worldSetting = '',
    this.genre = StoryGenre.free,
    this.narratorRole = NarratorRole.protagonist,
    this.participantCharacterIds = const [],
    this.currentSaveId,
    this.isArchived = false,
    required this.createdAt,
    required this.updatedAt,
    this.lastSegmentPreview,
    this.syncSeq = 0,
  });

  StoryBook copyWith({
    String? id,
    String? userId,
    String? title,
    String? coverUrl,
    String? synopsis,
    String? worldSetting,
    StoryGenre? genre,
    NarratorRole? narratorRole,
    List<String>? participantCharacterIds,
    String? currentSaveId,
    bool? isArchived,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? lastSegmentPreview,
    int? syncSeq,
  }) {
    return StoryBook(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      coverUrl: coverUrl ?? this.coverUrl,
      synopsis: synopsis ?? this.synopsis,
      worldSetting: worldSetting ?? this.worldSetting,
      genre: genre ?? this.genre,
      narratorRole: narratorRole ?? this.narratorRole,
      participantCharacterIds:
          participantCharacterIds ?? this.participantCharacterIds,
      currentSaveId: currentSaveId ?? this.currentSaveId,
      isArchived: isArchived ?? this.isArchived,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastSegmentPreview: lastSegmentPreview ?? this.lastSegmentPreview,
      syncSeq: syncSeq ?? this.syncSeq,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'userId': userId,
        'title': title,
        'coverUrl': coverUrl,
        'synopsis': synopsis,
        'worldSetting': worldSetting,
        'genre': genre.index,
        'narratorRole': narratorRole.index,
        'participantCharacterIds': jsonEncode(participantCharacterIds),
        'currentSaveId': currentSaveId,
        'isArchived': isArchived ? 1 : 0,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'lastSegmentPreview': lastSegmentPreview,
        'sync_seq': syncSeq,
      };

  factory StoryBook.fromMap(Map<String, dynamic> map) {
    List<String> ids = [];
    final raw = map['participantCharacterIds'];
    if (raw is String && raw.isNotEmpty) {
      try {
        ids = (jsonDecode(raw) as List<dynamic>).map((e) => e.toString()).toList();
      } catch (_) {}
    }
    return StoryBook(
      id: map['id'] as String,
      userId: map['userId'] as String? ?? '',
      title: map['title'] as String? ?? '',
      coverUrl: map['coverUrl'] as String?,
      synopsis: map['synopsis'] as String? ?? '',
      worldSetting: map['worldSetting'] as String? ?? '',
      genre: _safeEnum(map['genre'] as int?, StoryGenre.values, StoryGenre.free),
      narratorRole: _safeEnum(
          map['narratorRole'] as int?, NarratorRole.values, NarratorRole.protagonist),
      participantCharacterIds: ids,
      currentSaveId: map['currentSaveId'] as String?,
      isArchived: (map['isArchived'] as int?) == 1,
      createdAt:
          DateTime.tryParse(map['createdAt'] as String? ?? '') ?? DateTime.now(),
      updatedAt:
          DateTime.tryParse(map['updatedAt'] as String? ?? '') ?? DateTime.now(),
      lastSegmentPreview: map['lastSegmentPreview'] as String?,
      syncSeq: (map['sync_seq'] ?? map['syncSeq']) as int? ?? 0,
    );
  }

  static T _safeEnum<T>(int? index, List<T> values, T fallback) {
    if (index == null || index < 0 || index >= values.length) return fallback;
    return values[index];
  }
}
