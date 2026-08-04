import 'package:solace/models/group_public_event_memory.dart';

bool eventMatchesQuery(GroupPublicEventMemory event, String query) {
  final normalizedQuery = query.trim().toLowerCase();
  if (normalizedQuery.isEmpty) return false;

  final searchableTerms = <String>[
    ...event.keywords,
    ...event.speakerNames,
  ].map((term) => term.trim().toLowerCase()).where((term) => term.isNotEmpty);
  if (searchableTerms.any(normalizedQuery.contains)) return true;

  final queryTerms = [
    ..._tokens(normalizedQuery),
    if (_containsCjk(normalizedQuery)) ..._bigrams(normalizedQuery),
  ].where((term) => term.length > 1).toList();
  final content = event.content.toLowerCase();
  if (queryTerms.any(content.contains)) return true;
  return _containsCjk(normalizedQuery) &&
      queryTerms.any((term) => _bigrams(term).any(content.contains));
}

List<GroupPublicEventMemory> buildRelevantGroupEventMemories({
  required String query,
  required Iterable<GroupPublicEventMemory> memories,
  int limit = 3,
}) {
  if (limit <= 0) return const [];
  final relevant =
      memories.where((memory) => eventMatchesQuery(memory, query)).toList();
  relevant.sort((a, b) {
    final pinned = (b.pinned ? 1 : 0).compareTo(a.pinned ? 1 : 0);
    if (pinned != 0) return pinned;
    final importance = (b.importance == GroupEventImportance.important ? 1 : 0)
        .compareTo(a.importance == GroupEventImportance.important ? 1 : 0);
    if (importance != 0) return importance;
    final weight = b.weight.compareTo(a.weight);
    if (weight != 0) return weight;
    final recalled = (b.lastRecalledAt ??
            DateTime.fromMillisecondsSinceEpoch(0))
        .compareTo(a.lastRecalledAt ?? DateTime.fromMillisecondsSinceEpoch(0));
    if (recalled != 0) return recalled;
    final created = b.createdAt.compareTo(a.createdAt);
    if (created != 0) return created;
    return a.id.compareTo(b.id);
  });
  return relevant.take(limit).toList();
}

bool canDecayGroupEvent({
  required GroupEventImportance importance,
  required bool pinned,
}) =>
    importance == GroupEventImportance.normal && !pinned;

List<String> _tokens(String value) => value
    .split(RegExp(r'[\s,，。！？!?、；;：:（）()「」“”"\[\]]+'))
    .where((token) => token.isNotEmpty)
    .toList();

List<String> _bigrams(String value) => [
      for (var i = 0; i < value.length - 1; i++) value.substring(i, i + 2),
    ];

bool _containsCjk(String value) => RegExp(r'[\u3400-\u9fff]').hasMatch(value);
