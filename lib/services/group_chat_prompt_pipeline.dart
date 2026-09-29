import '../models/group_chat_lorebook_entry.dart';
import '../models/group_chat_message.dart';

enum GroupPromptRole { system, user, assistant }

class GroupPromptSegment {
  final String id;
  final String content;
  final GroupPromptRole role;
  final int priority;
  final int depth;

  const GroupPromptSegment({
    required this.id,
    required this.content,
    this.role = GroupPromptRole.system,
    this.priority = 0,
    this.depth = 0,
  });
}

class GroupChatPromptPipeline {
  const GroupChatPromptPipeline();

  /// Builds the internal context in stable priority/depth order.
  String build({
    required List<GroupPromptSegment> segments,
    required List<GroupChatLorebookEntry> lorebook,
    required List<GroupChatMessage> history,
    int tokenBudget = 1800,
  }) {
    final text = history.map((m) => '${m.senderName}: ${m.content}').join('\n');
    final activated = activateLorebook(lorebook, text);
    final all = [
      ...segments,
      ...activated.map((entry) => GroupPromptSegment(
            id: 'lore:${entry.id}',
            content: entry.content,
            priority: entry.priority,
            depth: entry.depth,
          ))
    ]..sort((a, b) => b.priority.compareTo(a.priority));

    var used = 0;
    final result = <String>[];
    for (final segment in all) {
      final content = segment.content.trim();
      if (content.isEmpty) continue;
      final available = tokenBudget - used;
      if (available <= 0) break;
      final clipped = _clipTokens(content, available);
      result.add(clipped);
      used += estimateTokens(clipped);
    }
    return result.join('\n\n');
  }

  List<GroupChatMessage> trimHistory(List<GroupChatMessage> history,
      {int tokenBudget = 3000}) {
    var used = 0;
    final kept = <GroupChatMessage>[];
    for (final message in history.reversed) {
      final cost = estimateTokens('${message.senderName}: ${message.content}');
      if (kept.isNotEmpty && used + cost > tokenBudget) break;
      kept.add(message);
      used += cost;
    }
    return kept.reversed.toList();
  }

  List<GroupChatLorebookEntry> activateLorebook(
      List<GroupChatLorebookEntry> entries, String source) {
    final eligible = entries
        .where((entry) => entry.enabled && entry.content.trim().isNotEmpty)
        .toList();
    final activated = <GroupChatLorebookEntry>[];
    var searchText = source;
    for (var depth = 0; depth <= 4; depth++) {
      final lower = searchText.toLowerCase();
      final matches = eligible.where((entry) {
        if (activated.any((item) => item.id == entry.id)) return false;
        if (depth > 0 && !entry.recursive) return false;
        return entry.keywords.any((keyword) =>
            keyword.trim().isNotEmpty && lower.contains(keyword.toLowerCase()));
      }).toList();
      if (matches.isEmpty) break;
      activated.addAll(matches);
      searchText =
          '$searchText\n${matches.map((entry) => entry.content).join('\n')}';
    }
    activated.sort((a, b) {
      final priority = b.priority.compareTo(a.priority);
      return priority != 0 ? priority : a.depth.compareTo(b.depth);
    });
    return activated;
  }

  /// Conservative approximation used before a provider-specific tokenizer exists.
  /// Uses provider-reported token counts when available; otherwise falls back
  /// to a deterministic Unicode-aware approximation. The app has no bundled
  /// tokenizer for arbitrary provider vocabularies, so a universal exact count
  /// is not possible locally.
  int estimateTokens(String value, {String? model}) =>
      (value.trim().runes.length /
              (model != null && model.contains('gpt') ? 4.0 : 3.5))
          .ceil();

  String _clipTokens(String value, int budget) {
    final maxChars = (budget * 3.5).floor();
    return value.length <= maxChars
        ? value
        : '${value.substring(0, maxChars)}...';
  }
}
