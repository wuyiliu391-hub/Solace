import 'dart:convert';

/// Returns whether the branch has enough unsummarized messages for a refresh.
bool shouldRefreshGroupSummary({
  required int messageCount,
  required int summarizedCount,
  int threshold = 15,
}) =>
    shouldResetGroupSummary(
      messageCount: messageCount,
      summarizedCount: summarizedCount,
    ) ||
    messageCount - summarizedCount >= threshold;

bool shouldResetGroupSummary({
  required int messageCount,
  required int summarizedCount,
}) =>
    summarizedCount > messageCount;

/// Stable logical key for a group chat branch summary.
String groupSummaryKey(String groupId, String chatId) =>
    base64UrlEncode(utf8.encode(jsonEncode([groupId, chatId])));

String formatGroupSummaryMessages(
        Iterable<({String speaker, String content})> messages) =>
    messages.map((m) => '${m.speaker}：${m.content}').join('\n');

class GroupSummaryRefreshCoordinator {
  final Map<String, Future<void>> _tails = {};

  Future<void> run(
      String groupId, String chatId, Future<void> Function() action) {
    final key = groupSummaryKey(groupId, chatId);
    final previous = _tails[key] ?? Future<void>.value();
    final current = previous.then((_) => action());
    _tails[key] = current.catchError((_) {});
    current.whenComplete(() {
      if (identical(_tails[key], current)) _tails.remove(key);
    });
    return current;
  }
}
