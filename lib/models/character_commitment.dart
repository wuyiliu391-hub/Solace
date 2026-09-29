import 'dart:convert';

enum CharacterCommitmentStatus { active, fulfilled, expired, cancelled }

/// 一个由用户明确提及的近期事项，供角色在后续对话中自然跟进。
class CharacterCommitment {
  final String id;
  final String characterId;
  final String userId;
  final String chatId;
  final String content;
  final DateTime dueAt;
  final CharacterCommitmentStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;

  const CharacterCommitment({
    required this.id,
    required this.characterId,
    required this.userId,
    required this.chatId,
    required this.content,
    required this.dueAt,
    this.status = CharacterCommitmentStatus.active,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isActive => status == CharacterCommitmentStatus.active;

  bool get isDue => !DateTime.now().isBefore(dueAt);

  bool get isExpired =>
      DateTime.now().difference(dueAt) > const Duration(days: 7);

  CharacterCommitment copyWith({
    CharacterCommitmentStatus? status,
    DateTime? updatedAt,
  }) {
    return CharacterCommitment(
      id: id,
      characterId: characterId,
      userId: userId,
      chatId: chatId,
      content: content,
      dueAt: dueAt,
      status: status ?? this.status,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'characterId': characterId,
        'userId': userId,
        'chatId': chatId,
        'content': content,
        'dueAt': dueAt.toIso8601String(),
        'status': status.name,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory CharacterCommitment.fromMap(Map<String, dynamic> map) {
    return CharacterCommitment(
      id: map['id']?.toString() ?? '',
      characterId: map['characterId']?.toString() ?? '',
      userId: map['userId']?.toString() ?? '',
      chatId: map['chatId']?.toString() ?? '',
      content: map['content']?.toString() ?? '',
      dueAt:
          DateTime.tryParse(map['dueAt']?.toString() ?? '') ?? DateTime.now(),
      status: CharacterCommitmentStatus.values.firstWhere(
        (status) => status.name == map['status']?.toString(),
        orElse: () => CharacterCommitmentStatus.active,
      ),
      createdAt: DateTime.tryParse(map['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(map['updatedAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  String toJson() => jsonEncode(toMap());
}
