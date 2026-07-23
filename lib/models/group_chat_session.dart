import 'package:equatable/equatable.dart';
import 'dart:convert';

/// AI 群聊会话（对标 ChatSession 模式）
class GroupChatSession extends Equatable {
  /// 会话唯一 ID
  final String id;

  /// 群名称
  final String name;

  /// 群头像 URL
  final String? avatarUrl;

  /// 成员 ID 列表（含用户 + AI）
  final List<String> memberIds;

  /// AI 角色 ID 列表
  final List<String> aiCharacterIds;

  /// 创建者 ID
  final String creatorId;

  /// 最后一条消息预览
  final String? lastMessage;

  /// 最后一条消息时间
  final DateTime? lastMessageTime;

  /// 未读消息数
  final int unreadCount;

  /// 创建时间
  final DateTime createdAt;

  /// 更新时间
  final DateTime? updatedAt;

  /// 是否静音
  final bool isMuted;

  /// 是否置顶
  final bool isPinned;

  /// 背景图 URL
  final String? backgroundImage;

  /// 同步序列号
  final int syncSeq;

  const GroupChatSession({
    required this.id,
    required this.name,
    this.avatarUrl,
    required this.memberIds,
    required this.aiCharacterIds,
    required this.creatorId,
    this.lastMessage,
    this.lastMessageTime,
    this.unreadCount = 0,
    required this.createdAt,
    this.updatedAt,
    this.isMuted = false,
    this.isPinned = false,
    this.backgroundImage,
    this.syncSeq = 0,
  });

  GroupChatSession copyWith({
    String? id,
    String? name,
    String? avatarUrl,
    List<String>? memberIds,
    List<String>? aiCharacterIds,
    String? creatorId,
    String? lastMessage,
    DateTime? lastMessageTime,
    int? unreadCount,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isMuted,
    bool? isPinned,
    String? backgroundImage,
    int? syncSeq,
  }) {
    return GroupChatSession(
      id: id ?? this.id,
      name: name ?? this.name,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      memberIds: memberIds ?? this.memberIds,
      aiCharacterIds: aiCharacterIds ?? this.aiCharacterIds,
      creatorId: creatorId ?? this.creatorId,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      unreadCount: unreadCount ?? this.unreadCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isMuted: isMuted ?? this.isMuted,
      isPinned: isPinned ?? this.isPinned,
      backgroundImage: backgroundImage ?? this.backgroundImage,
      syncSeq: syncSeq ?? this.syncSeq,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'avatarUrl': avatarUrl,
      'memberIds': jsonEncode(memberIds),
      'aiCharacterIds': jsonEncode(aiCharacterIds),
      'creatorId': creatorId,
      'lastMessage': lastMessage,
      'lastMessageTime': lastMessageTime?.toIso8601String(),
      'unreadCount': unreadCount,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'isMuted': isMuted ? 1 : 0,
      'isPinned': isPinned ? 1 : 0,
      'backgroundImage': backgroundImage,
      'sync_seq': syncSeq,
    };
  }

  factory GroupChatSession.fromMap(Map<String, dynamic> map) {
    DateTime? parsedLastMessageTime;
    final lmtVal = map['lastMessageTime'];
    if (lmtVal is String) {
      parsedLastMessageTime = DateTime.tryParse(lmtVal);
    } else if (lmtVal is int) {
      parsedLastMessageTime = DateTime.fromMillisecondsSinceEpoch(lmtVal);
    }

    DateTime? parsedCreatedAt;
    final caVal = map['createdAt'];
    if (caVal is String) {
      parsedCreatedAt = DateTime.tryParse(caVal);
    } else if (caVal is int) {
      parsedCreatedAt = DateTime.fromMillisecondsSinceEpoch(caVal);
    }

    DateTime? parsedUpdatedAt;
    final uaVal = map['updatedAt'];
    if (uaVal is String) {
      parsedUpdatedAt = DateTime.tryParse(uaVal);
    } else if (uaVal is int) {
      parsedUpdatedAt = DateTime.fromMillisecondsSinceEpoch(uaVal);
    }

    List<String> parseStringList(dynamic val) {
      if (val == null) return [];
      if (val is String) {
        try {
          final decoded = jsonDecode(val);
          if (decoded is List<dynamic>) return decoded.cast<String>();
        } catch (_) {}
        return val.split('||').where((s) => s.isNotEmpty).toList();
      }
      if (val is List<dynamic>) return val.cast<String>();
      return [];
    }

    return GroupChatSession(
      id: map['id'] as String,
      name: map['name'] as String? ?? '',
      avatarUrl: map['avatarUrl'] as String?,
      memberIds: parseStringList(map['memberIds']),
      aiCharacterIds: parseStringList(map['aiCharacterIds']),
      creatorId: map['creatorId'] as String? ?? '',
      lastMessage: map['lastMessage'] as String?,
      lastMessageTime: parsedLastMessageTime,
      unreadCount: map['unreadCount'] as int? ?? 0,
      createdAt: parsedCreatedAt ?? DateTime.now(),
      updatedAt: parsedUpdatedAt,
      isMuted: map['isMuted'] == 1 || map['isMuted'] == true,
      isPinned: map['isPinned'] == 1 || map['isPinned'] == true,
      backgroundImage: map['backgroundImage'] as String?,
      syncSeq: (map['sync_seq'] ?? map['syncSeq']) as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'avatarUrl': avatarUrl,
      'memberIds': memberIds,
      'aiCharacterIds': aiCharacterIds,
      'creatorId': creatorId,
      'lastMessage': lastMessage,
      'lastMessageTime': lastMessageTime?.toIso8601String(),
      'unreadCount': unreadCount,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'isMuted': isMuted,
      'isPinned': isPinned,
      'backgroundImage': backgroundImage,
      'syncSeq': syncSeq,
    };
  }

  factory GroupChatSession.fromJson(Map<String, dynamic> json) {
    return GroupChatSession(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      avatarUrl: json['avatarUrl'] as String?,
      memberIds: (json['memberIds'] as List<dynamic>?)?.cast<String>() ?? [],
      aiCharacterIds:
          (json['aiCharacterIds'] as List<dynamic>?)?.cast<String>() ?? [],
      creatorId: json['creatorId'] as String? ?? '',
      lastMessage: json['lastMessage'] as String?,
      lastMessageTime: json['lastMessageTime'] != null
          ? DateTime.parse(json['lastMessageTime'] as String)
          : null,
      unreadCount: json['unreadCount'] as int? ?? 0,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now(),
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'] as String? ?? '')
          : null,
      isMuted: json['isMuted'] as bool? ?? false,
      isPinned: json['isPinned'] as bool? ?? false,
      backgroundImage: json['backgroundImage'] as String?,
      syncSeq: json['syncSeq'] as int? ?? 0,
    );
  }

  @override
  List<Object?> get props => [
        id,
        name,
        avatarUrl,
        memberIds,
        aiCharacterIds,
        creatorId,
        lastMessage,
        lastMessageTime,
        unreadCount,
        createdAt,
        updatedAt,
        isMuted,
        isPinned,
        backgroundImage,
        syncSeq,
      ];
}
