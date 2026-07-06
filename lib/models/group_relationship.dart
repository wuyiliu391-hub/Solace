import 'package:equatable/equatable.dart';

enum CharacterRelationship {
  ally,
  enemy,
  rival,
  friend,
  stranger,
  lover,
  subordinate,
  superior,
}

extension CharacterRelationshipX on CharacterRelationship {
  double get interactionMultiplier {
    switch (this) {
      case CharacterRelationship.enemy:
        return 2.5;
      case CharacterRelationship.rival:
        return 1.8;
      case CharacterRelationship.ally:
        return 1.5;
      case CharacterRelationship.lover:
        return 1.5;
      case CharacterRelationship.friend:
        return 1.2;
      case CharacterRelationship.stranger:
        return 0.5;
      case CharacterRelationship.superior:
        return 0.8;
      case CharacterRelationship.subordinate:
        return 1.0;
    }
  }

  String get label {
    switch (this) {
      case CharacterRelationship.ally:
        return '盟友';
      case CharacterRelationship.enemy:
        return '仇敌';
      case CharacterRelationship.rival:
        return '竞争对手';
      case CharacterRelationship.friend:
        return '朋友';
      case CharacterRelationship.stranger:
        return '陌生人';
      case CharacterRelationship.lover:
        return '恋人';
      case CharacterRelationship.subordinate:
        return '下属';
      case CharacterRelationship.superior:
        return '上级';
    }
  }

  String get dialogueStyle {
    switch (this) {
      case CharacterRelationship.enemy:
        return '保持敌意和对抗，有机会就反驳或嘲讽';
      case CharacterRelationship.rival:
        return '暗中较劲，不放过任何炫耀或贬低的机会';
      case CharacterRelationship.ally:
        return '倾向支持和配合，互相声援';
      case CharacterRelationship.lover:
        return '亲密暧昧，关心和保护对方';
      case CharacterRelationship.friend:
        return '轻松友好，可以开玩笑和调侃';
      case CharacterRelationship.stranger:
        return '礼貌但疏远，保持距离';
      case CharacterRelationship.subordinate:
        return '恭敬服从，不敢越界';
      case CharacterRelationship.superior:
        return '居高临下，简洁回应';
    }
  }

  String get emotionTendency {
    switch (this) {
      case CharacterRelationship.enemy:
        return '负面/对抗';
      case CharacterRelationship.rival:
        return '竞争/暗讽';
      case CharacterRelationship.ally:
        return '正面/支持';
      case CharacterRelationship.lover:
        return '亲密/保护';
      case CharacterRelationship.friend:
        return '友好/轻松';
      case CharacterRelationship.stranger:
        return '中性/疏远';
      case CharacterRelationship.subordinate:
        return '恭敬/谨慎';
      case CharacterRelationship.superior:
        return '尊重/威严';
    }
  }
}

class GroupRelationship extends Equatable {
  final String id;
  final String groupChatId;
  final String characterIdA;
  final String characterIdB;
  final CharacterRelationship relationship;
  final int syncSeq;

  const GroupRelationship({
    required this.id,
    required this.groupChatId,
    required this.characterIdA,
    required this.characterIdB,
    this.relationship = CharacterRelationship.stranger,
    this.syncSeq = 0,
  });

  GroupRelationship copyWith({
    String? id,
    String? groupChatId,
    String? characterIdA,
    String? characterIdB,
    CharacterRelationship? relationship,
    int? syncSeq,
  }) {
    return GroupRelationship(
      id: id ?? this.id,
      groupChatId: groupChatId ?? this.groupChatId,
      characterIdA: characterIdA ?? this.characterIdA,
      characterIdB: characterIdB ?? this.characterIdB,
      relationship: relationship ?? this.relationship,
      syncSeq: syncSeq ?? this.syncSeq,
    );
  }

  bool pairContains(String id1, String id2) {
    return (characterIdA == id1 && characterIdB == id2) ||
        (characterIdA == id2 && characterIdB == id1);
  }

  CharacterRelationship getRelationshipFor(String fromId, String toId) {
    if (characterIdA == fromId && characterIdB == toId) return relationship;
    if (characterIdB == fromId && characterIdA == toId) return relationship;
    return CharacterRelationship.stranger;
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'groupChatId': groupChatId,
      'characterIdA': characterIdA,
      'characterIdB': characterIdB,
      'relationship': relationship.index,
      'sync_seq': syncSeq,
    };
  }

  factory GroupRelationship.fromMap(Map<String, dynamic> map) {
    final relIdx = map['relationship'] as int? ?? 4;
    return GroupRelationship(
      id: map['id'] as String,
      groupChatId: map['groupChatId'] as String,
      characterIdA: map['characterIdA'] as String,
      characterIdB: map['characterIdB'] as String,
      relationship: relIdx < CharacterRelationship.values.length
          ? CharacterRelationship.values[relIdx]
          : CharacterRelationship.stranger,
      syncSeq: (map['sync_seq'] ?? map['syncSeq']) as int? ?? 0,
    );
  }

  @override
  List<Object?> get props => [
        id,
        groupChatId,
        characterIdA,
        characterIdB,
        relationship,
        syncSeq,
      ];
}
