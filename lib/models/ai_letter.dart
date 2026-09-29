import 'package:equatable/equatable.dart';

class AILetter extends Equatable {
  final String id;
  final String userId;
  final String characterId;
  final String characterName;
  final String? characterAvatar;
  final String recipientName;
  final String title;
  final String content;
  final bool isRead;
  final bool isFromUser;
  final bool needsReply;
  final String? sourceChatId;
  final DateTime createdAt;
  final DateTime? readAt;
  final int syncSeq;

  const AILetter({
    required this.id,
    required this.userId,
    required this.characterId,
    required this.characterName,
    this.characterAvatar,
    required this.recipientName,
    required this.title,
    required this.content,
    this.isRead = false,
    this.isFromUser = false,
    this.needsReply = false,
    this.sourceChatId,
    required this.createdAt,
    this.readAt,
    this.syncSeq = 0,
  });

  AILetter copyWith({
    String? id,
    String? userId,
    String? characterId,
    String? characterName,
    String? characterAvatar,
    String? recipientName,
    String? title,
    String? content,
    bool? isRead,
    bool? isFromUser,
    bool? needsReply,
    String? sourceChatId,
    DateTime? createdAt,
    DateTime? readAt,
    int? syncSeq,
  }) {
    return AILetter(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      characterId: characterId ?? this.characterId,
      characterName: characterName ?? this.characterName,
      characterAvatar: characterAvatar ?? this.characterAvatar,
      recipientName: recipientName ?? this.recipientName,
      title: title ?? this.title,
      content: content ?? this.content,
      isRead: isRead ?? this.isRead,
      isFromUser: isFromUser ?? this.isFromUser,
      needsReply: needsReply ?? this.needsReply,
      sourceChatId: sourceChatId ?? this.sourceChatId,
      createdAt: createdAt ?? this.createdAt,
      readAt: readAt ?? this.readAt,
      syncSeq: syncSeq ?? this.syncSeq,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'userId': userId,
      'characterId': characterId,
      'characterName': characterName,
      'characterAvatar': characterAvatar,
      'recipientName': recipientName,
      'title': title,
      'content': content,
      'isRead': isRead ? 1 : 0,
      'isFromUser': isFromUser ? 1 : 0,
      'needsReply': needsReply ? 1 : 0,
      'sourceChatId': sourceChatId,
      'createdAt': createdAt.toIso8601String(),
      'readAt': readAt?.toIso8601String(),
      'sync_seq': syncSeq,
    };
  }

  factory AILetter.fromMap(Map<String, dynamic> map) {
    return AILetter(
      id: map['id'] as String,
      userId: map['userId'] as String? ?? '',
      characterId: map['characterId'] as String? ?? '',
      characterName: map['characterName'] as String? ?? '',
      characterAvatar: map['characterAvatar'] as String?,
      recipientName: map['recipientName'] as String? ?? '',
      title: map['title'] as String? ?? '给你的一封信',
      content: map['content'] as String? ?? '',
      isRead: map['isRead'] == 1 || map['isRead'] == true,
      isFromUser: map['isFromUser'] == 1 || map['isFromUser'] == true,
      needsReply: map['needsReply'] == 1 || map['needsReply'] == true,
      sourceChatId: map['sourceChatId'] as String?,
      createdAt: DateTime.tryParse(map['createdAt'] as String? ?? '') ??
          DateTime.now(),
      readAt: map['readAt'] != null
          ? DateTime.tryParse(map['readAt'] as String)
          : null,
      syncSeq: (map['sync_seq'] ?? map['syncSeq']) as int? ?? 0,
    );
  }

  @override
  List<Object?> get props => [
        id,
        userId,
        characterId,
        characterName,
        characterAvatar,
        recipientName,
        title,
        content,
        isRead,
        isFromUser,
        needsReply,
        sourceChatId,
        createdAt,
        readAt,
        syncSeq,
      ];
}
