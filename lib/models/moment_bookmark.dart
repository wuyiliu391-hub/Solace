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
    DateTime? tryParseDateTime(dynamic val) {
      if (val == null || (val is String && val.trim().isEmpty)) return null;
      if (val is String) return DateTime.tryParse(val);
      if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
      return null;
    }
    return MomentBookmark(
      id: (map['id'] as String?) ?? '',
      momentId: (map['momentId'] as String?) ?? '',
      userId: (map['userId'] as String?) ?? '',
      createdAt: tryParseDateTime(map['createdAt']) ?? DateTime.now(),
    );
  }

  @override
  List<Object?> get props => [id, momentId, userId];
}
