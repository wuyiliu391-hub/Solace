import 'dart:convert';

import '../models/ai_character.dart';

/// 恢复隐藏角色时用于识别“同一角色的重复记录”。
///
/// 只比较角色设定本身，不比较 id、头像、时间和隐藏状态；这样可以把
/// “同一个妹妹只换过头像/被重复写入”的记录归为一组，同时保留真正不同
/// 设定的同名角色。
class CharacterRecoveryResolver {
  const CharacterRecoveryResolver._();

  static String identityKey(AICharacter character) {
    return jsonEncode([
      _normalize(character.name),
      _normalize(character.userAlias),
      _normalize(character.personality),
      _normalize(character.coreDesire),
      _normalize(character.moralBoundary),
      _normalize(character.backgroundStory),
      _normalize(character.gender),
      _normalize(character.worldSetting),
      _normalize(character.languageStyle),
      _normalize(character.tabooTopics),
      _normalize(character.userPersona),
      _normalize(character.catchphrases),
      _normalize(character.openingLine),
      _normalize(character.structuredTraits),
    ]);
  }

  static List<AICharacter> equivalents(
    AICharacter target,
    Iterable<AICharacter> characters,
  ) {
    final key = identityKey(target);
    return characters.where((item) => identityKey(item) == key).toList();
  }

  static List<AICharacter> recoverableHiddenCharacters(
    Iterable<AICharacter> characters,
  ) {
    final groups = <String, List<AICharacter>>{};
    for (final character in characters) {
      groups.putIfAbsent(identityKey(character), () => []).add(character);
    }
    return groups.values
        .where((group) => group.every((character) => character.isHidden))
        .map((group) => group.first)
        .toList();
  }

  /// 选择应该显示的 canonical 记录。
  ///
  /// 优先保留聊天消息最多的记录；消息数相同时优先保留当前已可见的记录，
  /// 再按更新时间和创建时间选择较新的记录。其它记录只继续隐藏，不删除，
  /// 防止恢复操作破坏用户数据。
  static AICharacter chooseCanonical(
    Iterable<AICharacter> candidates,
    Map<String, int> messageCounts,
  ) {
    final list = candidates.toList();
    if (list.isEmpty) {
      throw ArgumentError('角色候选列表不能为空');
    }
    list.sort((a, b) {
      final messageCompare =
          (messageCounts[b.id] ?? 0).compareTo(messageCounts[a.id] ?? 0);
      if (messageCompare != 0) return messageCompare;

      final visibleCompare = (a.isHidden ? 1 : 0).compareTo(b.isHidden ? 1 : 0);
      if (visibleCompare != 0) return visibleCompare;

      final updatedCompare =
          (b.updatedAt ?? b.createdAt).compareTo(a.updatedAt ?? a.createdAt);
      if (updatedCompare != 0) return updatedCompare;
      return b.createdAt.compareTo(a.createdAt);
    });
    return list.first;
  }

  static String _normalize(String? value) =>
      (value ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
}
