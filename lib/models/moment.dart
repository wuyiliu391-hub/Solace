import 'dart:convert';
import 'package:equatable/equatable.dart';

enum MomentType {
  text,
  image,
  video,
  mixed,
}

enum MomentVisibility {
  public,
  private,
  intimate,
  normal,
}

enum MomentDisplayType {
  moment, // 信息流卡片
  detail, // 详情视图
  reply, // 回复（线程内）
  parentMoment, // 父帖预览
}

enum MomentSource {
  normal,
  x,
}

class MomentLike extends Equatable {
  final String userId;
  final String userName;
  final DateTime createdAt;

  const MomentLike({
    required this.userId,
    required this.userName,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'userName': userName,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory MomentLike.fromMap(Map<String, dynamic> map) {
    return MomentLike(
      userId: map['userId'] as String,
      userName: map['userName'] as String,
      createdAt: DateTime.parse(map['createdAt'] as String),
    );
  }

  @override
  List<Object?> get props => [userId, userName, createdAt];
}

class MomentComment extends Equatable {
  final String id;
  final String userId;
  final String userName;
  final String? replyToUserId;
  final String? replyToUserName;
  final String content;
  final DateTime createdAt;

  const MomentComment({
    required this.id,
    required this.userId,
    required this.userName,
    this.replyToUserId,
    this.replyToUserName,
    required this.content,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'userId': userId,
      'userName': userName,
      'replyToUserId': replyToUserId,
      'replyToUserName': replyToUserName,
      'content': content,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory MomentComment.fromMap(Map<String, dynamic> map) {
    return MomentComment(
      id: map['id'] as String,
      userId: map['userId'] as String,
      userName: map['userName'] as String,
      replyToUserId: map['replyToUserId'] as String?,
      replyToUserName: map['replyToUserName'] as String?,
      content: map['content'] as String,
      createdAt: DateTime.parse(map['createdAt'] as String),
    );
  }

  @override
  List<Object?> get props => [id, userId, content, createdAt];
}

class Moment extends Equatable {
  final String id;
  final String userId;
  final String userName;
  final String? userAvatar;
  final String content;
  final List<String> images;
  final MomentType type;
  final List<MomentLike> likes;
  final List<MomentComment> comments;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final bool isFromAI;
  final MomentVisibility visibility;
  final MomentSource source;
  final int syncSeq;

  // ─── X 推特风格新增字段 ───
  final String? parentKey; // 回复链：指向父帖 ID
  final String? retweetKey; // 纯转发：指向原帖 ID
  final String? quoteKey; // 引用转发：指向被引用帖 ID
  final int retweetCount; // 转发计数
  final int replyCount; // 回复计数
  final int bookmarkCount; // 书签计数
  final int viewCount; // 浏览量
  final List<String> tags; // 话题标签
  final String? userHandle; // @handle
  final String? userGender; // 性别标记
  final bool userVerified; // 蓝标认证
  final int customLikeCount; // 自定义点赞显示数（0=用 likes.length）

  const Moment({
    required this.id,
    required this.userId,
    required this.userName,
    this.userAvatar,
    required this.content,
    this.images = const [],
    this.type = MomentType.text,
    this.likes = const [],
    this.comments = const [],
    required this.createdAt,
    this.updatedAt,
    this.isFromAI = false,
    this.visibility = MomentVisibility.public,
    this.source = MomentSource.normal,
    this.syncSeq = 0,
    this.parentKey,
    this.retweetKey,
    this.quoteKey,
    this.retweetCount = 0,
    this.replyCount = 0,
    this.bookmarkCount = 0,
    this.viewCount = 0,
    this.tags = const [],
    this.userHandle,
    this.userGender,
    this.userVerified = false,
    this.customLikeCount = 0,
  });

  /// 点赞计数（自定义优先，否则用 likes.length）
  int get likeCount => customLikeCount > 0 ? customLikeCount : likes.length;

  /// 是否包含图片
  bool get hasImages => images.isNotEmpty;

  /// 是否为回复
  bool get isReply => parentKey != null && parentKey!.isNotEmpty;

  /// 是否为纯转发
  bool get isRetweet => retweetKey != null && retweetKey!.isNotEmpty;

  /// 是否为引用转发
  bool get isQuote => quoteKey != null && quoteKey!.isNotEmpty;

  Moment copyWith({
    String? id,
    String? userId,
    String? userName,
    String? userAvatar,
    String? content,
    List<String>? images,
    MomentType? type,
    List<MomentLike>? likes,
    List<MomentComment>? comments,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isFromAI,
    MomentVisibility? visibility,
    MomentSource? source,
    int? syncSeq,
    String? parentKey,
    String? retweetKey,
    String? quoteKey,
    int? retweetCount,
    int? replyCount,
    int? bookmarkCount,
    int? viewCount,
    List<String>? tags,
    String? userHandle,
    String? userGender,
    bool? userVerified,
    int? customLikeCount,
  }) {
    return Moment(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      userAvatar: userAvatar ?? this.userAvatar,
      content: content ?? this.content,
      images: images ?? this.images,
      type: type ?? this.type,
      likes: likes ?? this.likes,
      comments: comments ?? this.comments,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isFromAI: isFromAI ?? this.isFromAI,
      visibility: visibility ?? this.visibility,
      source: source ?? this.source,
      syncSeq: syncSeq ?? this.syncSeq,
      parentKey: parentKey ?? this.parentKey,
      retweetKey: retweetKey ?? this.retweetKey,
      quoteKey: quoteKey ?? this.quoteKey,
      retweetCount: retweetCount ?? this.retweetCount,
      replyCount: replyCount ?? this.replyCount,
      bookmarkCount: bookmarkCount ?? this.bookmarkCount,
      viewCount: viewCount ?? this.viewCount,
      tags: tags ?? this.tags,
      userHandle: userHandle ?? this.userHandle,
      userGender: userGender ?? this.userGender,
      userVerified: userVerified ?? this.userVerified,
      customLikeCount: customLikeCount ?? this.customLikeCount,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'userId': userId,
      'userName': userName,
      'userAvatar': userAvatar,
      'content': content,
      'images': images.join(','),
      'type': type.index,
      'likes': jsonEncode(likes.map((l) => l.toMap()).toList()),
      'comments': jsonEncode(comments.map((c) => c.toMap()).toList()),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'isFromAI': isFromAI ? 1 : 0,
      'visibility': visibility.index,
      'source': source.index,
      'sync_seq': syncSeq,
      'parentKey': parentKey,
      'retweetKey': retweetKey,
      'quoteKey': quoteKey,
      'retweetCount': retweetCount,
      'replyCount': replyCount,
      'bookmarkCount': bookmarkCount,
      'viewCount': viewCount,
      'tags': jsonEncode(tags),
      'userHandle': userHandle,
      'userGender': userGender,
      'userVerified': userVerified ? 1 : 0,
      'customLikeCount': customLikeCount,
    };
  }

  factory Moment.fromMap(Map<String, dynamic> map) {
    List<MomentLike> parseLikes(dynamic likesData) {
      if (likesData == null ||
          likesData.toString().isEmpty ||
          likesData.toString() == '[]') {
        return [];
      }
      try {
        final List<dynamic> list = jsonDecode(likesData.toString());
        return list
            .map((l) => MomentLike.fromMap(l as Map<String, dynamic>))
            .toList();
      } catch (e) {
        return [];
      }
    }

    List<MomentComment> parseComments(dynamic commentsData) {
      if (commentsData == null ||
          commentsData.toString().isEmpty ||
          commentsData.toString() == '[]') {
        return [];
      }
      try {
        final List<dynamic> list = jsonDecode(commentsData.toString());
        return list
            .map((c) => MomentComment.fromMap(c as Map<String, dynamic>))
            .toList();
      } catch (e) {
        return [];
      }
    }

    List<String> parseImages(String? imagesStr) {
      if (imagesStr == null || imagesStr.isEmpty) {
        return [];
      }
      return imagesStr.split(',').where((s) => s.isNotEmpty).toList();
    }

    List<String> parseTags(dynamic tagsData) {
      if (tagsData == null ||
          tagsData.toString().isEmpty ||
          tagsData.toString() == '[]') {
        return [];
      }
      try {
        final List<dynamic> list = jsonDecode(tagsData.toString());
        return list.map((t) => t.toString()).toList();
      } catch (e) {
        return [];
      }
    }

    MomentSource parseSource(dynamic sourceData) {
      if (sourceData is int &&
          sourceData >= 0 &&
          sourceData < MomentSource.values.length) {
        return MomentSource.values[sourceData];
      }
      final sourceText = sourceData?.toString().toLowerCase();
      if (sourceText == 'x' || sourceText == '1') {
        return MomentSource.x;
      }
      return MomentSource.normal;
    }

    return Moment(
      id: map['id'] as String,
      userId: map['userId'] as String,
      userName: map['userName'] as String,
      userAvatar: map['userAvatar'] as String?,
      content: map['content'] as String,
      images: parseImages(map['images'] as String?),
      type: MomentType.values[(map['type'] as int?) ?? 0],
      likes: parseLikes(map['likes']),
      comments: parseComments(map['comments']),
      createdAt: DateTime.parse(map['createdAt'] as String),
      updatedAt: map['updatedAt'] != null
          ? DateTime.parse(map['updatedAt'] as String)
          : null,
      isFromAI: map['isFromAI'] == 1 || map['isFromAI'] == true,
      visibility: MomentVisibility.values[(map['visibility'] as int?) ?? 0],
      source: parseSource(map['source']),
      syncSeq: (map['sync_seq'] ?? map['syncSeq']) as int? ?? 0,
      parentKey: map['parentKey'] as String?,
      retweetKey: map['retweetKey'] as String?,
      quoteKey: map['quoteKey'] as String?,
      retweetCount: (map['retweetCount'] as int?) ?? 0,
      replyCount: (map['replyCount'] as int?) ?? 0,
      bookmarkCount: (map['bookmarkCount'] as int?) ?? 0,
      viewCount: (map['viewCount'] as int?) ?? 0,
      tags: parseTags(map['tags']),
      userHandle: map['userHandle'] as String?,
      userGender: map['userGender'] as String?,
      userVerified: map['userVerified'] == 1 || map['userVerified'] == true,
      customLikeCount: (map['customLikeCount'] as int?) ?? 0,
    );
  }

  @override
  List<Object?> get props => [
        id,
        userId,
        userName,
        content,
        images,
        type,
        likes,
        comments,
        createdAt,
        isFromAI,
        visibility,
        source,
        syncSeq,
        parentKey,
        retweetKey,
        quoteKey,
        retweetCount,
        replyCount,
        bookmarkCount,
        viewCount,
        tags,
        userHandle,
        userGender,
        userVerified,
        customLikeCount,
      ];
}
