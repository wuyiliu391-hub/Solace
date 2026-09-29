import 'package:equatable/equatable.dart';

class PureAISession extends Equatable {
  final String id;
  final String userId;
  final String title;
  final String? lastMessage;
  final DateTime? lastMessageTime;
  final bool isPinned;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const PureAISession({
    required this.id,
    required this.userId,
    this.title = 'AI助手',
    this.lastMessage,
    this.lastMessageTime,
    this.isPinned = false,
    required this.createdAt,
    this.updatedAt,
  });

  PureAISession copyWith({
    String? id,
    String? userId,
    String? title,
    String? lastMessage,
    DateTime? lastMessageTime,
    bool? isPinned,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PureAISession(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      isPinned: isPinned ?? this.isPinned,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'userId': userId,
      'title': title,
      'lastMessage': lastMessage,
      'lastMessageTime': lastMessageTime?.toIso8601String(),
      'isPinned': isPinned ? 1 : 0,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }

  factory PureAISession.fromMap(Map<String, dynamic> map) {
    DateTime? tryParseDateTime(dynamic val) {
      if (val == null || (val is String && val.trim().isEmpty)) return null;
      if (val is String) return DateTime.tryParse(val);
      if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
      return null;
    }
    final createdAt = tryParseDateTime(map['createdAt']);
    return PureAISession(
      id: (map['id'] as String?) ?? '',
      userId: (map['userId'] as String?) ?? '',
      title: (map['title'] as String?) ?? 'AI助手',
      lastMessage: map['lastMessage'] as String?,
      lastMessageTime: tryParseDateTime(map['lastMessageTime']),
      isPinned: (map['isPinned'] as int?) == 1,
      createdAt: createdAt ?? DateTime.now(),
      updatedAt: tryParseDateTime(map['updatedAt']),
    );
  }

  @override
  List<Object?> get props => [
        id,
        userId,
        title,
        lastMessage,
        lastMessageTime,
        isPinned,
        createdAt,
        updatedAt,
      ];
}
