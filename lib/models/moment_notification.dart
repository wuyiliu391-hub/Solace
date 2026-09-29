import 'package:equatable/equatable.dart';

enum MomentNotificationType {
  like,
  reply,
  retweet,
  mention,
}

class MomentNotification extends Equatable {
  final String id;
  final String momentId;
  final String actorId;
  final String actorName;
  final String? actorAvatar;
  final MomentNotificationType type;
  final String? content;
  final DateTime createdAt;
  final bool isRead;
  final bool isFromAI;

  const MomentNotification({
    required this.id,
    required this.momentId,
    required this.actorId,
    required this.actorName,
    this.actorAvatar,
    required this.type,
    this.content,
    required this.createdAt,
    this.isRead = false,
    this.isFromAI = false,
  });

  MomentNotification copyWith({
    String? id,
    String? momentId,
    String? actorId,
    String? actorName,
    String? actorAvatar,
    MomentNotificationType? type,
    String? content,
    DateTime? createdAt,
    bool? isRead,
    bool? isFromAI,
  }) {
    return MomentNotification(
      id: id ?? this.id,
      momentId: momentId ?? this.momentId,
      actorId: actorId ?? this.actorId,
      actorName: actorName ?? this.actorName,
      actorAvatar: actorAvatar ?? this.actorAvatar,
      type: type ?? this.type,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      isRead: isRead ?? this.isRead,
      isFromAI: isFromAI ?? this.isFromAI,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'momentId': momentId,
      'actorId': actorId,
      'actorName': actorName,
      'actorAvatar': actorAvatar,
      'type': type.index,
      'content': content,
      'createdAt': createdAt.toIso8601String(),
      'isRead': isRead ? 1 : 0,
      'isFromAI': isFromAI ? 1 : 0,
    };
  }

  factory MomentNotification.fromMap(Map<String, dynamic> map) {
    DateTime? tryParseDateTime(dynamic val) {
      if (val == null || (val is String && val.trim().isEmpty)) return null;
      if (val is String) return DateTime.tryParse(val);
      if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
      return null;
    }
    return MomentNotification(
      id: (map['id'] as String?) ?? '',
      momentId: (map['momentId'] as String?) ?? '',
      actorId: (map['actorId'] as String?) ?? '',
      actorName: (map['actorName'] as String?) ?? '',
      actorAvatar: map['actorAvatar'] as String?,
      type: MomentNotificationType.values[(map['type'] as int?) ?? 0],
      content: map['content'] as String?,
      createdAt: tryParseDateTime(map['createdAt']) ?? DateTime.now(),
      isRead: map['isRead'] == 1 || map['isRead'] == true,
      isFromAI: map['isFromAI'] == 1 || map['isFromAI'] == true,
    );
  }

  @override
  List<Object?> get props =>
      [id, momentId, actorId, type, createdAt, isRead];
}
