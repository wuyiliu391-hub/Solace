import 'package:equatable/equatable.dart';

/// 内心活动类型
enum InnerThoughtType {
  user(0), // 用户内心活动
  ai(1); // AI 内心独白（来自反思引擎）

  final int value;
  const InnerThoughtType(this.value);

  static InnerThoughtType fromValue(int v) =>
      InnerThoughtType.values.firstWhere((e) => e.value == v, orElse: () => InnerThoughtType.user);
}

/// 内心活动模型
class InnerThought extends Equatable {
  final String id;
  final String characterId;
  final String userId;
  final String content;
  final InnerThoughtType type;
  final double emotionValence;
  final double emotionArousal;
  final bool isRead;
  final DateTime createdAt;

  const InnerThought({
    required this.id,
    required this.characterId,
    required this.userId,
    required this.content,
    this.type = InnerThoughtType.user,
    this.emotionValence = 0,
    this.emotionArousal = 0,
    this.isRead = false,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
    'id': id, 'characterId': characterId, 'userId': userId,
    'content': content, 'type': type.value,
    'emotionValence': emotionValence, 'emotionArousal': emotionArousal,
    'isRead': isRead ? 1 : 0, 'createdAt': createdAt.toIso8601String(),
  };

  factory InnerThought.fromMap(Map<String, dynamic> m) => InnerThought(
    id: m['id'] as String, characterId: m['characterId'] as String,
    userId: m['userId'] as String, content: m['content'] as String,
    type: InnerThoughtType.fromValue(m['type'] as int? ?? 0),
    emotionValence: (m['emotionValence'] as num?)?.toDouble() ?? 0,
    emotionArousal: (m['emotionArousal'] as num?)?.toDouble() ?? 0,
    isRead: (m['isRead'] as int?) == 1,
    createdAt: DateTime.tryParse(m['createdAt'] as String? ?? '') ?? DateTime.now(),
  );

  InnerThought copyWith({
    String? content, bool? isRead, double? emotionValence, double? emotionArousal,
  }) => InnerThought(
    id: id, characterId: characterId, userId: userId,
    content: content ?? this.content, type: type,
    emotionValence: emotionValence ?? this.emotionValence,
    emotionArousal: emotionArousal ?? this.emotionArousal,
    isRead: isRead ?? this.isRead, createdAt: createdAt,
  );

  @override
  List<Object?> get props => [id, characterId, userId, content, type, isRead, createdAt];
}
