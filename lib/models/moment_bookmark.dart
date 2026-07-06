import 'package:equatable/equatable.dart';

class MomentBookmark extends Equatable {
  final String id;
  final String momentId;
  final String userId;
  final DateTime createdAt;

  const MomentBookmark({
    required this.id,
    required this.momentId,
    required this.userId,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'momentId': momentId,
      'userId': userId,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory MomentBookmark.fromMap(Map<String, dynamic> map) {
    return MomentBookmark(
      id: map['id'] as String,
      momentId: map['momentId'] as String,
      userId: map['userId'] as String,
      createdAt: DateTime.parse(map['createdAt'] as String),
    );
  }

  @override
  List<Object?> get props => [id, momentId, userId];
}
