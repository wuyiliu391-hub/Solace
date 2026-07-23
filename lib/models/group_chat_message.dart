// 群聊消息模型（对标 ChatMessage 模式）
import 'dart:convert';

/// 群聊消息类型枚举
enum GroupChatMessageType {
  text,
  image,
  audio,
  file,
  system,
  sticker,
}

/// 群聊消息状态枚举
enum GroupChatMessageStatus {
  sending,
  sent,
  delivered,
  read,
  error,
  failed,
}

/// AI 群聊消息
class GroupChatMessage {
  /// 消息唯一 ID
  final String id;

  /// 群聊会话 ID
  final String groupId;

  /// 发送者 ID
  final String senderId;

  /// 发送者名称
  final String senderName;

  /// 消息内容
  final String content;

  /// 是否用户消息
  final bool isUser;

  /// 是否系统消息
  final bool isSystem;

  /// 消息类型
  final GroupChatMessageType type;

  /// 时间戳
  final DateTime timestamp;

  /// 元数据（扩展字段）
  final Map<String, dynamic>? metadata;

  /// 消息状态
  final GroupChatMessageStatus status;

  GroupChatMessage({
    required this.id,
    this.groupId = '',
    required this.senderId,
    this.senderName = '',
    this.content = '',
    this.isUser = false,
    this.isSystem = false,
    this.type = GroupChatMessageType.text,
    DateTime? timestamp,
    this.metadata,
    this.status = GroupChatMessageStatus.sent,
  }) : timestamp = timestamp ?? DateTime.now();

  /// 复制并修改
  GroupChatMessage copyWith({
    String? id,
    String? groupId,
    String? senderId,
    String? senderName,
    String? content,
    bool? isUser,
    bool? isSystem,
    GroupChatMessageType? type,
    DateTime? timestamp,
    Map<String, dynamic>? metadata,
    GroupChatMessageStatus? status,
  }) {
    return GroupChatMessage(
      id: id ?? this.id,
      groupId: groupId ?? this.groupId,
      senderId: senderId ?? this.senderId,
      senderName: senderName ?? this.senderName,
      content: content ?? this.content,
      isUser: isUser ?? this.isUser,
      isSystem: isSystem ?? this.isSystem,
      type: type ?? this.type,
      timestamp: timestamp ?? this.timestamp,
      metadata: metadata ?? this.metadata,
      status: status ?? this.status,
    );
  }

  /// 转为 Map（兼容 SQLite 存储）
  Map<String, dynamic> toMap() => {
        'id': id,
        'groupId': groupId,
        'senderId': senderId,
        'senderName': senderName,
        'content': content,
        'isUser': isUser ? 1 : 0,
        'isSystem': isSystem ? 1 : 0,
        'type': type.name,
        'createdAt': timestamp.toIso8601String(),
        'status': status.name,
        'metadata': metadata != null ? _encodeMetadata(metadata!) : null,
      };

  factory GroupChatMessage.fromMap(Map<String, dynamic> map) {
    DateTime parsedTimestamp;
    final tsVal = map['timestamp'] ?? map['createdAt'];
    if (tsVal is String) {
      parsedTimestamp = DateTime.tryParse(tsVal) ?? DateTime.now();
    } else if (tsVal is int) {
      parsedTimestamp = DateTime.fromMillisecondsSinceEpoch(tsVal);
    } else {
      parsedTimestamp = DateTime.now();
    }

    return GroupChatMessage(
      id: (map['id'] as String?) ?? '',
      groupId: (map['groupId'] as String?) ?? '',
      senderId: (map['senderId'] as String?) ?? '',
      senderName: (map['senderName'] as String?) ?? '',
      content: (map['content'] as String?) ?? '',
      isUser: _parseBool(map['isUser']),
      isSystem: _parseBool(map['isSystem']),
      type: map['type'] != null
          ? GroupChatMessageType.values.firstWhere(
              (e) => e.name == map['type'],
              orElse: () => GroupChatMessageType.text,
            )
          : GroupChatMessageType.text,
      timestamp: parsedTimestamp,
      metadata: map['metadata'] != null
          ? _decodeMetadata(map['metadata']?.toString() ?? '{}')
          : null,
      status: map['status'] != null
          ? GroupChatMessageStatus.values.firstWhere(
              (e) => e.name == map['status'],
              orElse: () => GroupChatMessageStatus.sent,
            )
          : GroupChatMessageStatus.sent,
    );
  }

  static bool _parseBool(dynamic value) {
    if (value is int) return value == 1;
    if (value is bool) return value;
    return false;
  }

  static String _encodeMetadata(Map<String, dynamic> meta) {
    try {
      return jsonEncode(meta);
    } catch (_) {
      return '{}';
    }
  }

  static Map<String, dynamic> _decodeMetadata(String encoded) {
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    final map = <String, dynamic>{};
    for (final pair in encoded.split('|')) {
      final idx = pair.indexOf('=');
      if (idx > 0) {
        map[pair.substring(0, idx)] = pair.substring(idx + 1);
      }
    }
    return map;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'groupId': groupId,
        'senderId': senderId,
        'senderName': senderName,
        'content': content,
        'isUser': isUser,
        'isSystem': isSystem,
        'type': type.name,
        'timestamp': timestamp.toIso8601String(),
        'status': status.name,
        'metadata': metadata,
      };

  factory GroupChatMessage.fromJson(Map<String, dynamic> json) {
    return GroupChatMessage(
      id: json['id'] as String? ?? '',
      groupId: json['groupId'] as String? ?? '',
      senderId: json['senderId'] as String? ?? '',
      senderName: json['senderName'] as String? ?? '',
      content: json['content'] as String? ?? '',
      isUser: json['isUser'] as bool? ?? false,
      isSystem: json['isSystem'] as bool? ?? false,
      type: json['type'] != null
          ? GroupChatMessageType.values.firstWhere(
              (e) => e.name == json['type'],
              orElse: () => GroupChatMessageType.text,
            )
          : GroupChatMessageType.text,
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'] as String)
          : DateTime.now(),
      metadata: json['metadata'] as Map<String, dynamic>?,
      status: json['status'] != null
          ? GroupChatMessageStatus.values.firstWhere(
              (e) => e.name == json['status'],
              orElse: () => GroupChatMessageStatus.sent,
            )
          : GroupChatMessageStatus.sent,
    );
  }
}
