import 'dart:convert';
import 'package:equatable/equatable.dart';
import 'chat_message.dart';

class PureAIMessage extends Equatable {
  final String id;
  final String sessionId;
  final String senderId;
  final String? senderName;
  final String content;
  final MessageType type;
  final MessageStatus status;
  final DateTime createdAt;
  final Map<String, dynamic>? metadata;

  const PureAIMessage({
    required this.id,
    required this.sessionId,
    required this.senderId,
    this.senderName,
    required this.content,
    this.type = MessageType.text,
    this.status = MessageStatus.sent,
    required this.createdAt,
    this.metadata,
  });

  bool get isFromAI => senderId == 'ai';

  PureAIMessage copyWith({
    String? id,
    String? sessionId,
    String? senderId,
    String? senderName,
    String? content,
    MessageType? type,
    MessageStatus? status,
    DateTime? createdAt,
    Map<String, dynamic>? metadata,
  }) {
    return PureAIMessage(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      senderId: senderId ?? this.senderId,
      senderName: senderName ?? this.senderName,
      content: content ?? this.content,
      type: type ?? this.type,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      metadata: metadata ?? this.metadata,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'sessionId': sessionId,
      'senderId': senderId,
      'senderName': senderName,
      'content': content,
      'type': type.index,
      'status': status.index,
      'createdAt': createdAt.toIso8601String(),
      'metadata': metadata != null ? jsonEncode(metadata) : null,
    };
  }

  factory PureAIMessage.fromMap(Map<String, dynamic> map) {
    return PureAIMessage(
      id: map['id'] as String,
      sessionId: map['sessionId'] as String,
      senderId: map['senderId'] as String,
      senderName: map['senderName'] as String?,
      content: map['content'] as String,
      type: MessageType.values[map['type'] as int? ?? 0],
      status: MessageStatus.values[map['status'] as int? ?? 1],
      createdAt: DateTime.parse(map['createdAt'] as String),
      metadata: map['metadata'] != null
          ? jsonDecode(map['metadata'] as String) as Map<String, dynamic>
          : null,
    );
  }

  @override
  List<Object?> get props => [
        id,
        sessionId,
        senderId,
        senderName,
        content,
        type,
        status,
        createdAt,
        metadata,
      ];
}
