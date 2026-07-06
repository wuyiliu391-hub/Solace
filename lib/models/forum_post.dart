import 'package:equatable/equatable.dart';

/// 日记帖子模型
class ForumPost extends Equatable {
  final String id;
  final String authorId;
  final String authorName;
  final String? authorAvatar;
  final bool isFromAI;
  final String? characterId;
  final String title;
  final String content;
  final List<String> images;
  final List<String> tags;
  final List<String> likes;
  final bool isAnonymous;
  final int visibility; // 0=公开, 1=仅高好感可见
  final DateTime createdAt;
  final DateTime? updatedAt;

  const ForumPost({
    required this.id, required this.authorId, required this.authorName,
    this.authorAvatar, this.isFromAI = false, this.characterId,
    required this.title, required this.content, this.images = const [],
    this.tags = const [], this.likes = const [], this.isAnonymous = false,
    this.visibility = 0, required this.createdAt, this.updatedAt,
  });

  Map<String, dynamic> toMap() => {
    'id': id, 'authorId': authorId, 'authorName': authorName,
    'authorAvatar': authorAvatar, 'isFromAI': isFromAI ? 1 : 0,
    'characterId': characterId, 'title': title, 'content': content,
    'images': images.join('|'), 'tags': tags.join('|'),
    'likes': '[]', 'isAnonymous': isAnonymous ? 1 : 0,
    'visibility': visibility, 'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt?.toIso8601String(),
  };

  factory ForumPost.fromMap(Map<String, dynamic> m) => ForumPost(
    id: m['id'] as String, authorId: m['authorId'] as String,
    authorName: m['authorName'] as String, authorAvatar: m['authorAvatar'] as String?,
    isFromAI: (m['isFromAI'] as int?) == 1, characterId: m['characterId'] as String?,
    title: m['title'] as String, content: m['content'] as String,
    images: (m['images'] as String? ?? '').split('|').where((s) => s.isNotEmpty).toList(),
    tags: (m['tags'] as String? ?? '').split('|').where((s) => s.isNotEmpty).toList(),
    likes: const [], isAnonymous: (m['isAnonymous'] as int?) == 1,
    visibility: m['visibility'] as int? ?? 0,
    createdAt: DateTime.tryParse(m['createdAt'] as String? ?? '') ?? DateTime.now(),
    updatedAt: m['updatedAt'] != null ? DateTime.tryParse(m['updatedAt'] as String) : null,
  );

  @override
  List<Object?> get props => [id, authorId, title, content, createdAt];
}

/// 日记评论模型
class ForumComment extends Equatable {
  final String id;
  final String postId;
  final String authorId;
  final String authorName;
  final String? authorAvatar;
  final bool isFromAI;
  final String? characterId;
  final String content;
  final String? replyToId;
  final String? replyToName;
  final bool isAnonymous;
  final DateTime createdAt;

  const ForumComment({
    required this.id, required this.postId, required this.authorId,
    required this.authorName, this.authorAvatar, this.isFromAI = false,
    this.characterId, required this.content, this.replyToId, this.replyToName,
    this.isAnonymous = false, required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
    'id': id, 'postId': postId, 'authorId': authorId,
    'authorName': authorName, 'authorAvatar': authorAvatar,
    'isFromAI': isFromAI ? 1 : 0, 'characterId': characterId,
    'content': content, 'replyToId': replyToId, 'replyToName': replyToName,
    'isAnonymous': isAnonymous ? 1 : 0, 'createdAt': createdAt.toIso8601String(),
  };

  factory ForumComment.fromMap(Map<String, dynamic> m) => ForumComment(
    id: m['id'] as String, postId: m['postId'] as String,
    authorId: m['authorId'] as String, authorName: m['authorName'] as String,
    authorAvatar: m['authorAvatar'] as String?,
    isFromAI: (m['isFromAI'] as int?) == 1, characterId: m['characterId'] as String?,
    content: m['content'] as String, replyToId: m['replyToId'] as String?,
    replyToName: m['replyToName'] as String?,
    isAnonymous: (m['isAnonymous'] as int?) == 1,
    createdAt: DateTime.tryParse(m['createdAt'] as String? ?? '') ?? DateTime.now(),
  );

  @override
  List<Object?> get props => [id, postId, content, createdAt];
}
