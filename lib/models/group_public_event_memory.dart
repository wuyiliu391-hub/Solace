import 'dart:convert';

enum GroupEventImportance { normal, important }

class GroupPublicEventMemory {
  final String id;
  final String characterId;
  final String groupId;
  final String chatId;
  final String content;
  final List<String> keywords;
  final List<String> sourceMessageIds;
  final List<String> speakerNames;
  final String? sourceGroupName;
  final GroupEventImportance importance;
  final bool pinned;
  final double weight;
  final DateTime createdAt;
  final DateTime? lastRecalledAt;

  const GroupPublicEventMemory({
    required this.id,
    required this.characterId,
    required this.groupId,
    required this.chatId,
    required this.content,
    this.keywords = const [],
    this.sourceMessageIds = const [],
    this.speakerNames = const [],
    this.sourceGroupName,
    this.importance = GroupEventImportance.normal,
    this.pinned = false,
    this.weight = 1.0,
    required this.createdAt,
    this.lastRecalledAt,
  });

  Map<String, dynamic> get metadata => {
        'sourceMessageIds': sourceMessageIds,
        'speakerNames': speakerNames,
        if (sourceGroupName != null) 'sourceGroupName': sourceGroupName,
      };

  GroupPublicEventMemory copyWith({
    String? id,
    String? characterId,
    String? groupId,
    String? chatId,
    String? content,
    List<String>? keywords,
    List<String>? sourceMessageIds,
    List<String>? speakerNames,
    String? sourceGroupName,
    GroupEventImportance? importance,
    bool? pinned,
    double? weight,
    DateTime? createdAt,
    DateTime? lastRecalledAt,
  }) =>
      GroupPublicEventMemory(
        id: id ?? this.id,
        characterId: characterId ?? this.characterId,
        groupId: groupId ?? this.groupId,
        chatId: chatId ?? this.chatId,
        content: content ?? this.content,
        keywords: keywords ?? this.keywords,
        sourceMessageIds: sourceMessageIds ?? this.sourceMessageIds,
        speakerNames: speakerNames ?? this.speakerNames,
        sourceGroupName: sourceGroupName ?? this.sourceGroupName,
        importance: importance ?? this.importance,
        pinned: pinned ?? this.pinned,
        weight: weight ?? this.weight,
        createdAt: createdAt ?? this.createdAt,
        lastRecalledAt: lastRecalledAt ?? this.lastRecalledAt,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'characterId': characterId,
        'groupId': groupId,
        'chatId': chatId,
        'content': content,
        'keywords': jsonEncode(keywords),
        'sourceMessageIds': jsonEncode(sourceMessageIds),
        'speakerNames': jsonEncode(speakerNames),
        'metadata': jsonEncode(metadata),
        'sourceGroupName': sourceGroupName,
        'importance': importance.name,
        'pinned': pinned ? 1 : 0,
        'weight': weight,
        'createdAt': createdAt.toIso8601String(),
        'lastRecalledAt': lastRecalledAt?.toIso8601String(),
      };

  factory GroupPublicEventMemory.fromMap(Map<String, dynamic> map) {
    final metadata = _asMap(map['metadata']);
    final metadataSourceMessageIds =
        _asStringList(metadata['sourceMessageIds']);
    final metadataSpeakerNames = _asStringList(metadata['speakerNames']);
    final topSourceMessageIds = _asStringList(map['sourceMessageIds']);
    final topSpeakerNames = _asStringList(map['speakerNames']);
    final metadataGroupName = _asNonEmptyString(metadata['sourceGroupName']);
    return GroupPublicEventMemory(
      id: _asString(map['id']),
      characterId: _asString(map['characterId']),
      groupId: _asString(map['groupId']),
      chatId: _asString(map['chatId']),
      content: _asString(map['content']),
      keywords: _asStringList(map['keywords']),
      sourceMessageIds: metadataSourceMessageIds.isNotEmpty
          ? metadataSourceMessageIds
          : topSourceMessageIds,
      speakerNames: metadataSpeakerNames.isNotEmpty
          ? metadataSpeakerNames
          : topSpeakerNames,
      sourceGroupName:
          metadataGroupName ?? _asNonEmptyString(map['sourceGroupName']),
      importance: _importance(map['importance']),
      pinned: _asBool(map['pinned']),
      weight: _asDouble(map['weight']) ?? 1.0,
      createdAt: _asDateTime(map['createdAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      lastRecalledAt: _asDateTime(map['lastRecalledAt']),
    );
  }

  static GroupEventImportance _importance(Object? value) {
    if (value == GroupEventImportance.important.name ||
        value?.toString().trim().toLowerCase() == 'important') {
      return GroupEventImportance.important;
    }
    final numeric =
        value is num ? value : num.tryParse(value?.toString() ?? '');
    if (numeric == 1 || numeric == 2) return GroupEventImportance.important;
    return GroupEventImportance.normal;
  }

  static Map<String, dynamic> _asMap(Object? value) {
    if (value is Map) {
      return <String, dynamic>{
        for (final entry in value.entries)
          if (entry.key is String) entry.key as String: entry.value,
      };
    }
    if (value is String) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map) {
          return <String, dynamic>{
            for (final entry in decoded.entries)
              if (entry.key is String) entry.key as String: entry.value,
          };
        }
      } catch (_) {}
    }
    return const {};
  }

  static String _asString(Object? value) => value?.toString() ?? '';

  static String? _asNonEmptyString(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static List<String> _asStringList(Object? value) {
    if (value is List) return value.whereType<String>().toList();
    if (value is String && value.isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is List) return decoded.whereType<String>().toList();
      } catch (_) {
        return value.split(',').where((item) => item.isNotEmpty).toList();
      }
    }
    return const [];
  }

  static bool _asBool(Object? value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String)
      return value.trim().toLowerCase() == 'true' || value == '1';
    return false;
  }

  static double? _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
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
}
