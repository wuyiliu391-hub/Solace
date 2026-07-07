// 【对标来源：SillyTavern-1.18.0 — script.js 消息结构 + chats.js 消息操作】
// 1:1 转译自 SillyTavern 消息数据结构
// 参考文件：public/script.js:addOneMessage()、public/scripts/chats.js

import 'dart:convert';

/// 消息状态枚举
enum MessageStatus {
  sending,
  sent,
  delivered,
  read,
  error,
  failed,
  cancelled,
}

/// 聊天消息（对标 SillyTavern 消息结构）
class ChatMessage {
  /// 消息唯一 ID
  final String id;

  /// 会话 ID
  final String chatId;

  /// 发送者 ID（用户ID 或 ai_{characterId}）
  final String senderId;

  /// 发送者名称（对标 .ch_name > .name_text）
  final String senderName;

  /// 消息内容（对标 .mes_text，Markdown 格式）
  final String content;

  /// 是否用户消息（对标 is_user 属性）
  final bool isUser;

  /// 是否系统消息（对标 is_system 属性）
  final bool isSystem;

  /// 是否隐藏（对标 .mes_hide / .mes_unhide）
  /// 隐藏的消息对 AI 不可见
  final bool isHidden;

  /// 是否幽灵消息（对标 .mes_ghost）
  /// 幽灵消息完全不可见
  final bool isGhost;

  /// 消息类型（文本/图片/音频/文件/系统）
  final MessageType type;

  /// 时间戳
  final DateTime timestamp;

  /// 生成耗时毫秒（对标 .mes_timer）
  final int? generationTime;

  /// Token 数量（对标 .tokenCounterDisplay）
  final int? tokenCount;

  /// 附件路径（对标 .mes_file_wrapper / .mes_media_wrapper）
  final String? attachmentPath;

  /// 滑动历史：同一位置的多条备选回复（对标 swipe_left/right）
  final List<String> swipeHistory;

  /// 当前滑动索引
  final int swipeIndex;

  /// 是否书签/检查点（对标 .mes_bookmark）
  final bool isBookmark;

  /// 推理/思考内容（对标 .mes_reasoning_details）
  final String? reasoning;

  /// 消息状态（发送中/已发送/已送达/错误/已取消）
  final MessageStatus status;

  /// 消息已读时间
  final DateTime? readAt;

  /// 元数据（扩展字段）
  final Map<String, dynamic>? metadata;

  ChatMessage({
    required this.id,
    this.chatId = '',
    required this.senderId,
    this.senderName = '',
    this.content = '',
    this.isUser = false,
    this.isSystem = false,
    this.isHidden = false,
    this.isGhost = false,
    this.type = MessageType.text,
    DateTime? timestamp,
    DateTime? createdAt,
    this.generationTime,
    this.tokenCount,
    this.attachmentPath,
    this.swipeHistory = const [],
    this.swipeIndex = 0,
    this.isBookmark = false,
    this.reasoning,
    this.status = MessageStatus.sent,
    this.readAt,
    this.metadata,
  }) : timestamp = timestamp ?? createdAt ?? DateTime.now();

  /// 是否来自 AI（兼容旧代码）
  bool get isFromAI => !isUser;

  /// 是否来自用户（兼容旧代码）
  bool get isFromUser => isUser;

  /// 创建时间（兼容旧代码，等同于 timestamp）
  DateTime get createdAt => timestamp;

  /// 复制并修改（兼容旧代码）
  ChatMessage copyWith({
    String? id,
    String? chatId,
    String? senderId,
    String? senderName,
    String? content,
    bool? isUser,
    bool? isSystem,
    bool? isHidden,
    bool? isGhost,
    MessageType? type,
    DateTime? timestamp,
    int? generationTime,
    int? tokenCount,
    String? attachmentPath,
    List<String>? swipeHistory,
    int? swipeIndex,
    bool? isBookmark,
    String? reasoning,
    MessageStatus? status,
    DateTime? readAt,
    Map<String, dynamic>? metadata,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      chatId: chatId ?? this.chatId,
      senderId: senderId ?? this.senderId,
      senderName: senderName ?? this.senderName,
      content: content ?? this.content,
      isUser: isUser ?? this.isUser,
      isSystem: isSystem ?? this.isSystem,
      isHidden: isHidden ?? this.isHidden,
      isGhost: isGhost ?? this.isGhost,
      type: type ?? this.type,
      timestamp: timestamp ?? this.timestamp,
      generationTime: generationTime ?? this.generationTime,
      tokenCount: tokenCount ?? this.tokenCount,
      attachmentPath: attachmentPath ?? this.attachmentPath,
      swipeHistory: swipeHistory ?? this.swipeHistory,
      swipeIndex: swipeIndex ?? this.swipeIndex,
      isBookmark: isBookmark ?? this.isBookmark,
      reasoning: reasoning ?? this.reasoning,
      status: status ?? this.status,
      readAt: readAt ?? this.readAt,
      metadata: metadata ?? this.metadata,
    );
  }

  /// 转为 Map（兼容 SQLite 存储）
  Map<String, dynamic> toMap() => {
        'id': id,
        'chatId': chatId,
        'senderId': senderId,
        'senderName': senderName,
        'content': content,
        'isUser': isUser ? 1 : 0,
        'isSystem': isSystem ? 1 : 0,
        'isHidden': isHidden ? 1 : 0,
        'isGhost': isGhost ? 1 : 0,
        'type': type.name,
        'createdAt': timestamp.toIso8601String(),
        'status': status.name,
        'readAt': readAt?.toIso8601String(),
        'reasoning': reasoning,
        'metadata': metadata != null ? _encodeMetadata(metadata!) : null,
      };

  /// 从 Map 创建（兼容 SQLite 存储）
  /// 安全解析布尔字段（兼容 SQLite int 和 JSON bool）
  static bool _parseBool(dynamic value) {
    if (value is int) return value == 1;
    if (value is bool) return value;
    return false;
  }

  factory ChatMessage.fromMap(Map<String, dynamic> map) {
    return ChatMessage(
      id: (map['id'] as String?) ?? '',
      chatId: (map['chatId'] as String?) ?? '',
      senderId: (map['senderId'] as String?) ?? '',
      senderName: (map['senderName'] as String?) ?? '',
      content: (map['content'] as String?) ?? '',
      isUser: _parseBool(map['isUser']),
      isSystem: _parseBool(map['isSystem']),
      isHidden: _parseBool(map['isHidden']),
      isGhost: _parseBool(map['isGhost']),
      type: map['type'] != null
          ? MessageType.values.firstWhere(
              (e) => e.name == map['type'],
              orElse: () => MessageType.text,
            )
          : MessageType.text,
      timestamp: (map['timestamp'] ?? map['createdAt']) != null
          ? DateTime.parse((map['timestamp'] ?? map['createdAt']) as String)
          : DateTime.now(),
      generationTime: map['generationTime'] as int?,
      tokenCount: map['tokenCount'] as int?,
      attachmentPath: map['attachmentPath'] as String?,
      swipeHistory: map['swipeHistory'] != null
          ? (map['swipeHistory'] as String)
              .split('||')
              .where((s) => s.isNotEmpty)
              .toList()
          : [],
      swipeIndex: (map['swipeIndex'] as int?) ?? 0,
      isBookmark: _parseBool(map['isBookmark']),
      reasoning: map['reasoning'] as String?,
      status: map['status'] != null
          ? MessageStatus.values.firstWhere(
              (e) => e.name == map['status'],
              orElse: () => MessageStatus.sent,
            )
          : MessageStatus.sent,
      readAt: map['readAt'] != null
          ? DateTime.tryParse(map['readAt'] as String? ?? '')
          : null,
      metadata: map['metadata'] != null
          ? _decodeMetadata(map['metadata'] as String)
          : null,
    );
  }

  static String _encodeMetadata(Map<String, dynamic> meta) {
    try {
      return jsonEncode(meta);
    } catch (_) {
      return '{}';
    }
  }

  static Map<String, dynamic> _decodeMetadata(String encoded) {
    // 优先尝试 JSON 格式（新格式）
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    // 回退到旧格式 key=value|key=value
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
        'chatId': chatId,
        'senderId': senderId,
        'senderName': senderName,
        'content': content,
        'isUser': isUser,
        'isSystem': isSystem,
        'isHidden': isHidden,
        'isGhost': isGhost,
        'type': type.name,
        'timestamp': timestamp.toIso8601String(),
        'generationTime': generationTime,
        'tokenCount': tokenCount,
        'attachmentPath': attachmentPath,
        'swipeHistory': swipeHistory,
        'swipeIndex': swipeIndex,
        'isBookmark': isBookmark,
        'reasoning': reasoning,
        'status': status.name,
        'readAt': readAt?.toIso8601String(),
        'metadata': metadata,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String? ?? '',
      chatId: json['chatId'] as String? ?? '',
      senderId: json['senderId'] as String? ?? '',
      senderName: json['senderName'] as String? ?? '',
      content: json['content'] as String? ?? '',
      isUser: json['isUser'] as bool? ?? false,
      isSystem: json['isSystem'] as bool? ?? false,
      isHidden: json['isHidden'] as bool? ?? false,
      isGhost: json['isGhost'] as bool? ?? false,
      type: json['type'] != null
          ? MessageType.values.firstWhere(
              (e) => e.name == json['type'],
              orElse: () => MessageType.text,
            )
          : MessageType.text,
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'] as String)
          : DateTime.now(),
      generationTime: json['generationTime'] as int?,
      tokenCount: json['tokenCount'] as int?,
      attachmentPath: json['attachmentPath'] as String?,
      swipeHistory:
          (json['swipeHistory'] as List<dynamic>?)?.cast<String>() ?? [],
      swipeIndex: json['swipeIndex'] as int? ?? 0,
      isBookmark: json['isBookmark'] as bool? ?? false,
      reasoning: json['reasoning'] as String?,
      status: json['status'] != null
          ? MessageStatus.values.firstWhere(
              (e) => e.name == json['status'],
              orElse: () => MessageStatus.sent,
            )
          : MessageStatus.sent,
      readAt: json['readAt'] != null
          ? DateTime.tryParse(json['readAt'] as String? ?? '')
          : null,
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }
}

/// 消息类型枚举
enum MessageType {
  text,
  image,
  audio,
  file,
  system,
  sticker,
  voice,
}
