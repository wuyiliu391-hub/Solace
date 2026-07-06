class GroupMessage {
  final String characterName;
  final String content;

  const GroupMessage({
    required this.characterName,
    required this.content,
  });

  static List<GroupMessage> parseMultiCharacterResponse(String response) {
    final results = <GroupMessage>[];
    final pattern = RegExp(r'^(\S+?)[：:](.+)$', multiLine: true);
    final matches = pattern.allMatches(response);
    for (final m in matches) {
      final name = m.group(1)?.trim();
      final content = m.group(2)?.trim();
      if (name != null && content != null && content.isNotEmpty) {
        results.add(GroupMessage(characterName: name, content: content));
      }
    }
    return results;
  }
}
