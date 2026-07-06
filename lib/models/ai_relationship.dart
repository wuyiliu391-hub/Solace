import 'package:equatable/equatable.dart';

/// AI关系类型
enum AIRelationshipType {
  stranger(0), friend(1), crush(2), rival(3), mentor(4),
  sibling(5), lover(6), enemy(7);

  final int value;
  const AIRelationshipType(this.value);
  static AIRelationshipType fromValue(int v) =>
      AIRelationshipType.values.firstWhere((e) => e.value == v, orElse: () => AIRelationshipType.stranger);

  String get label {
    switch (this) {
      case AIRelationshipType.stranger: return '陌生人';
      case AIRelationshipType.friend: return '好友';
      case AIRelationshipType.crush: return '暗恋';
      case AIRelationshipType.rival: return '对手';
      case AIRelationshipType.mentor: return '师徒';
      case AIRelationshipType.sibling: return '兄妹';
      case AIRelationshipType.lover: return '恋人';
      case AIRelationshipType.enemy: return '敌对';
    }
  }
}

/// AI关系网络模型
class AIRelationship extends Equatable {
  final String id;
  final String characterIdA;
  final String characterIdB;
  final AIRelationshipType relationshipType;
  final double affinity; // 0.0~1.0
  final String? description;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const AIRelationship({
    required this.id, required this.characterIdA, required this.characterIdB,
    this.relationshipType = AIRelationshipType.stranger,
    this.affinity = 0.5, this.description,
    required this.createdAt, this.updatedAt,
  });

  Map<String, dynamic> toMap() => {
    'id': id, 'characterIdA': characterIdA, 'characterIdB': characterIdB,
    'relationshipType': relationshipType.value, 'affinity': affinity,
    'description': description, 'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt?.toIso8601String(),
  };

  factory AIRelationship.fromMap(Map<String, dynamic> m) => AIRelationship(
    id: m['id'] as String, characterIdA: m['characterIdA'] as String,
    characterIdB: m['characterIdB'] as String,
    relationshipType: AIRelationshipType.fromValue(m['relationshipType'] as int? ?? 0),
    affinity: (m['affinity'] as num?)?.toDouble() ?? 0.5,
    description: m['description'] as String?,
    createdAt: DateTime.tryParse(m['createdAt'] as String? ?? '') ?? DateTime.now(),
    updatedAt: m['updatedAt'] != null ? DateTime.tryParse(m['updatedAt'] as String) : null,
  );

  AIRelationship copyWith({AIRelationshipType? relationshipType, double? affinity, String? description, DateTime? updatedAt}) =>
    AIRelationship(id: id, characterIdA: characterIdA, characterIdB: characterIdB,
      relationshipType: relationshipType ?? this.relationshipType,
      affinity: affinity ?? this.affinity, description: description ?? this.description,
      createdAt: createdAt, updatedAt: updatedAt ?? DateTime.now());

  @override
  List<Object?> get props => [id, characterIdA, characterIdB, relationshipType, affinity];
}
