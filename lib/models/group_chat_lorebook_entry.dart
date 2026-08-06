import 'dart:convert';

/// A keyword-triggered lore entry scoped to a group chat.
class GroupChatLorebookEntry {
  final String id;
  final String groupId;
  final String? chatId;
  final String name;
  final String content;
  final List<String> keywords;
  final int priority;
  final int depth;
  final bool enabled;
  final bool recursive;

  const GroupChatLorebookEntry({
    required this.id,
    required this.groupId,
    this.chatId,
    this.name = '',
    required this.content,
    this.keywords = const [],
    this.priority = 0,
    this.depth = 2,
    this.enabled = true,
    this.recursive = false,
  });

  GroupChatLorebookEntry copyWith({
    String? id,
    String? groupId,
    String? chatId,
    String? name,
    String? content,
    List<String>? keywords,
    int? priority,
    int? depth,
    bool? enabled,
    bool? recursive,
  }) =>
      GroupChatLorebookEntry(
        id: id ?? this.id,
        groupId: groupId ?? this.groupId,
        chatId: chatId ?? this.chatId,
        name: name ?? this.name,
        content: content ?? this.content,
        keywords: keywords ?? this.keywords,
        priority: priority ?? this.priority,
        depth: depth ?? this.depth,
        enabled: enabled ?? this.enabled,
    recursive: recursive ?? this.recursive,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'groupId': groupId,
        'chatId': chatId,
        'name': name,
        'content': content,
        'keywords': jsonEncode(keywords),
        'priority': priority,
        'depth': depth,
        'enabled': enabled ? 1 : 0,
        'recursive': recursive ? 1 : 0,
      };

  factory GroupChatLorebookEntry.fromMap(Map<String, dynamic> map) {
    final rawKeywords = map['keywords'];
    final decoded = rawKeywords is String ? _decode(rawKeywords) : rawKeywords;
    return GroupChatLorebookEntry(
      id: map['id']?.toString() ?? '',
      groupId: map['groupId']?.toString() ?? '',
      chatId: map['chatId']?.toString(),
      name: map['name']?.toString() ?? '',
      content: map['content']?.toString() ?? '',
      keywords: decoded is List
          ? decoded.map((e) => e.toString()).toList()
          : const [],
      priority: int.tryParse(map['priority']?.toString() ?? '') ?? 0,
      depth: int.tryParse(map['depth']?.toString() ?? '') ?? 2,
      enabled: _bool(map['enabled'], true),
      recursive: _bool(map['recursive'], false),
    );
  }

  static dynamic _decode(String value) {
    try {
      return jsonDecode(value);
    } catch (_) {
      return const <String>[];
    }
  }

  static bool _bool(dynamic value, bool fallback) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    return value == null ? fallback : value.toString() == '1';
  }
}
