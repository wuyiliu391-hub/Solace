import 'dart:convert';

/// 小说状态
enum NovelStatus {
  draft, // 草稿
  writing, // 创作中
  completed, // 已完结
}

extension NovelStatusX on NovelStatus {
  String get label => switch (this) {
        NovelStatus.draft => '草稿',
        NovelStatus.writing => '连载中',
        NovelStatus.completed => '已完结',
      };
}

/// 小说类型
enum NovelGenre {
  romance, // 言情
  fantasy, // 奇幻
  urban, // 都市
  suspense, // 悬疑
  historical, // 历史
  scifi, // 科幻
  horror, // 恐怖
  free, // 自由
}

extension NovelGenreX on NovelGenre {
  String get label => switch (this) {
        NovelGenre.romance => '言情',
        NovelGenre.fantasy => '奇幻',
        NovelGenre.urban => '都市',
        NovelGenre.suspense => '悬疑',
        NovelGenre.historical => '历史',
        NovelGenre.scifi => '科幻',
        NovelGenre.horror => '恐怖',
        NovelGenre.free => '自由',
      };
}

/// 小说章节
class NovelChapter {
  final String id;
  final String novelId;
  final int sortOrder; // 章节顺序（从0开始）
  final String title; // 章节标题，如"第一章 初遇"
  final String content; // 正文内容
  final int wordCount; // 字数统计
  final bool isAiGenerated; // 是否由 AI 生成
  final DateTime createdAt;
  final DateTime updatedAt;

  const NovelChapter({
    required this.id,
    required this.novelId,
    required this.sortOrder,
    required this.title,
    this.content = '',
    this.wordCount = 0,
    this.isAiGenerated = false,
    required this.createdAt,
    required this.updatedAt,
  });

  NovelChapter copyWith({
    String? id,
    String? novelId,
    int? sortOrder,
    String? title,
    String? content,
    int? wordCount,
    bool? isAiGenerated,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return NovelChapter(
      id: id ?? this.id,
      novelId: novelId ?? this.novelId,
      sortOrder: sortOrder ?? this.sortOrder,
      title: title ?? this.title,
      content: content ?? this.content,
      wordCount: wordCount ?? this.wordCount,
      isAiGenerated: isAiGenerated ?? this.isAiGenerated,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'novelId': novelId,
        'sortOrder': sortOrder,
        'title': title,
        'content': content,
        'wordCount': wordCount,
        'isAiGenerated': isAiGenerated ? 1 : 0,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory NovelChapter.fromMap(Map<String, dynamic> map) {
    return NovelChapter(
      id: map['id'] as String,
      novelId: map['novelId'] as String? ?? '',
      sortOrder: map['sortOrder'] as int? ?? 0,
      title: map['title'] as String? ?? '',
      content: map['content'] as String? ?? '',
      wordCount: map['wordCount'] as int? ?? 0,
      isAiGenerated: (map['isAiGenerated'] as int?) == 1,
      createdAt:
          DateTime.tryParse(map['createdAt'] as String? ?? '') ?? DateTime.now(),
      updatedAt:
          DateTime.tryParse(map['updatedAt'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

/// 小说元数据（书架展示用，不含正文）
class Novel {
  final String id;
  final String userId;
  final String title;
  final String? coverUrl;
  final String synopsis; // 简介
  final String worldSetting; // 世界观/背景设定（供 AI 生成时参考）
  final String characters; // 主要人物设定（供 AI 生成时参考）
  final NovelGenre genre;
  final NovelStatus status;
  final int totalWords; // 全书字数
  final int chapterCount; // 章节数
  final bool isArchived;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? lastChapterPreview; // 书架卡片最近章节预览文字

  const Novel({
    required this.id,
    required this.userId,
    required this.title,
    this.coverUrl,
    this.synopsis = '',
    this.worldSetting = '',
    this.characters = '',
    this.genre = NovelGenre.free,
    this.status = NovelStatus.writing,
    this.totalWords = 0,
    this.chapterCount = 0,
    this.isArchived = false,
    required this.createdAt,
    required this.updatedAt,
    this.lastChapterPreview,
  });

  Novel copyWith({
    String? id,
    String? userId,
    String? title,
    String? coverUrl,
    String? synopsis,
    String? worldSetting,
    String? characters,
    NovelGenre? genre,
    NovelStatus? status,
    int? totalWords,
    int? chapterCount,
    bool? isArchived,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? lastChapterPreview,
  }) {
    return Novel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      coverUrl: coverUrl ?? this.coverUrl,
      synopsis: synopsis ?? this.synopsis,
      worldSetting: worldSetting ?? this.worldSetting,
      characters: characters ?? this.characters,
      genre: genre ?? this.genre,
      status: status ?? this.status,
      totalWords: totalWords ?? this.totalWords,
      chapterCount: chapterCount ?? this.chapterCount,
      isArchived: isArchived ?? this.isArchived,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastChapterPreview: lastChapterPreview ?? this.lastChapterPreview,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'userId': userId,
        'title': title,
        'coverUrl': coverUrl,
        'synopsis': synopsis,
        'worldSetting': worldSetting,
        'characters': characters,
        'genre': genre.index,
        'status': status.index,
        'totalWords': totalWords,
        'chapterCount': chapterCount,
        'isArchived': isArchived ? 1 : 0,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'lastChapterPreview': lastChapterPreview,
      };

  factory Novel.fromMap(Map<String, dynamic> map) {
    return Novel(
      id: map['id'] as String,
      userId: map['userId'] as String? ?? '',
      title: map['title'] as String? ?? '',
      coverUrl: map['coverUrl'] as String?,
      synopsis: map['synopsis'] as String? ?? '',
      worldSetting: map['worldSetting'] as String? ?? '',
      characters: map['characters'] as String? ?? '',
      genre: _safeEnum(
          map['genre'] as int?, NovelGenre.values, NovelGenre.free),
      status: _safeEnum(
          map['status'] as int?, NovelStatus.values, NovelStatus.writing),
      totalWords: map['totalWords'] as int? ?? 0,
      chapterCount: map['chapterCount'] as int? ?? 0,
      isArchived: (map['isArchived'] as int?) == 1,
      createdAt:
          DateTime.tryParse(map['createdAt'] as String? ?? '') ?? DateTime.now(),
      updatedAt:
          DateTime.tryParse(map['updatedAt'] as String? ?? '') ?? DateTime.now(),
      lastChapterPreview: map['lastChapterPreview'] as String?,
    );
  }

  static T _safeEnum<T>(int? index, List<T> values, T fallback) {
    if (index == null || index < 0 || index >= values.length) return fallback;
    return values[index];
  }
}