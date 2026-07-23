class IntimacyEvent {
  final String id;
  final String chatId;
  final String userId;
  final String characterId;
  final int oldLevel;
  final int newLevel;
  final int delta;
  final int dailyCount;
  final String source;
  final String? messagePreview;
  final String? sentimentLabel;
  final String? sentimentType;
  final DateTime createdAt;

  const IntimacyEvent({
    required this.id,
    required this.chatId,
    required this.userId,
    required this.characterId,
    required this.oldLevel,
    required this.newLevel,
    required this.delta,
    required this.dailyCount,
    required this.source,
    this.messagePreview,
    this.sentimentLabel,
    this.sentimentType,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'chatId': chatId,
      'userId': userId,
      'characterId': characterId,
      'oldLevel': oldLevel,
      'newLevel': newLevel,
      'delta': delta,
      'dailyCount': dailyCount,
      'source': source,
      'messagePreview': messagePreview,
      'sentimentLabel': sentimentLabel,
      'sentimentType': sentimentType,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory IntimacyEvent.fromMap(Map<String, dynamic> map) {
    DateTime? tryParseDateTime(dynamic val) {
      if (val == null || (val is String && val.trim().isEmpty)) return null;
      if (val is String) return DateTime.tryParse(val);
      if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
      return null;
    }
    return IntimacyEvent(
      id: (map['id'] as String?) ?? '',
      chatId: (map['chatId'] as String?) ?? '',
      userId: (map['userId'] as String?) ?? '',
      characterId: (map['characterId'] as String?) ?? '',
      oldLevel: (map['oldLevel'] as int?) ?? 0,
      newLevel: (map['newLevel'] as int?) ?? 0,
      delta: (map['delta'] as int?) ?? 0,
      dailyCount: (map['dailyCount'] as int?) ?? 0,
      source: (map['source'] as String?) ?? '',
      messagePreview: map['messagePreview'] as String?,
      sentimentLabel: map['sentimentLabel'] as String?,
      sentimentType: map['sentimentType'] as String?,
      createdAt: tryParseDateTime(map['createdAt']) ?? DateTime.now(),
    );
  }
}
