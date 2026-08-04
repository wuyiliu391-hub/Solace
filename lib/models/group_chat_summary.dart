class GroupChatSummary {
  final String groupId;
  final String chatId;
  final String summary;
  final int messageCount;
  final DateTime updatedAt;

  const GroupChatSummary({
    required this.groupId,
    required this.chatId,
    required this.summary,
    required this.messageCount,
    required this.updatedAt,
  });

  factory GroupChatSummary.fromMap(Map<String, dynamic> map) {
    return GroupChatSummary(
      groupId: _asString(map['groupId']),
      chatId: _asString(map['chatId']),
      summary: _asString(map['summary']),
      messageCount: _asInt(map['messageCount']),
      updatedAt: _asDateTime(map['updatedAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  static String _asString(Object? value) => value?.toString() ?? '';

  static int _asInt(Object? value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static DateTime? _asDateTime(Object? value) {
    if (value is num) return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    final text = value?.toString();
    if (text == null || text.isEmpty) return null;
    final milliseconds = int.tryParse(text);
    if (milliseconds != null) {
      return DateTime.fromMillisecondsSinceEpoch(milliseconds);
    }
    return DateTime.tryParse(text);
  }

  Map<String, dynamic> toMap() => {
        'groupId': groupId,
        'chatId': chatId,
        'summary': summary,
        'messageCount': messageCount,
        'updatedAt': updatedAt.toIso8601String(),
      };
}
