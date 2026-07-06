import 'dart:convert';
import 'package:equatable/equatable.dart';

class GroupMemberSettings extends Equatable {
  final String id;
  final String groupChatId;
  final String characterId;
  final int talkativeness;
  final bool isMuted;
  final int sortOrder;
  final List<String> triggerKeywords;
  final int syncSeq;
  final String? storyNickname;
  final String? storyPersonality;

  const GroupMemberSettings({
    required this.id,
    required this.groupChatId,
    required this.characterId,
    this.talkativeness = 50,
    this.isMuted = false,
    this.sortOrder = 0,
    this.triggerKeywords = const [],
    this.syncSeq = 0,
    this.storyNickname,
    this.storyPersonality,
  });

  GroupMemberSettings copyWith({
    String? id,
    String? groupChatId,
    String? characterId,
    int? talkativeness,
    bool? isMuted,
    int? sortOrder,
    List<String>? triggerKeywords,
    int? syncSeq,
    String? storyNickname,
    String? storyPersonality,
  }) {
    return GroupMemberSettings(
      id: id ?? this.id,
      groupChatId: groupChatId ?? this.groupChatId,
      characterId: characterId ?? this.characterId,
      talkativeness: talkativeness ?? this.talkativeness,
      isMuted: isMuted ?? this.isMuted,
      sortOrder: sortOrder ?? this.sortOrder,
      triggerKeywords: triggerKeywords ?? this.triggerKeywords,
      syncSeq: syncSeq ?? this.syncSeq,
      storyNickname: storyNickname ?? this.storyNickname,
      storyPersonality: storyPersonality ?? this.storyPersonality,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'groupChatId': groupChatId,
      'characterId': characterId,
      'talkativeness': talkativeness,
      'isMuted': isMuted ? 1 : 0,
      'sortOrder': sortOrder,
      'triggerKeywords': jsonEncode(triggerKeywords),
      'sync_seq': syncSeq,
      'storyNickname': storyNickname,
      'storyPersonality': storyPersonality,
    };
  }

  factory GroupMemberSettings.fromMap(Map<String, dynamic> map) {
    List<String> _parseKeywords(dynamic v) {
      if (v == null) return [];
      if (v is List) return v.cast<String>();
      if (v is String) {
        try {
          final decoded = jsonDecode(v);
          if (decoded is List) return decoded.cast<String>();
        } catch (_) {}
      }
      return [];
    }

    return GroupMemberSettings(
      id: map['id'] as String,
      groupChatId: map['groupChatId'] as String,
      characterId: map['characterId'] as String,
      talkativeness: map['talkativeness'] as int? ?? 50,
      isMuted: map['isMuted'] == 1 || map['isMuted'] == true,
      sortOrder: map['sortOrder'] as int? ?? 0,
      triggerKeywords: _parseKeywords(map['triggerKeywords']),
      syncSeq: (map['sync_seq'] ?? map['syncSeq']) as int? ?? 0,
      storyNickname: map['storyNickname'] as String?,
      storyPersonality: map['storyPersonality'] as String?,
    );
  }

  @override
  List<Object?> get props => [
        id,
        groupChatId,
        characterId,
        talkativeness,
        isMuted,
        sortOrder,
        triggerKeywords,
        syncSeq,
        storyNickname,
        storyPersonality,
      ];
}
