import 'package:flutter_test/flutter_test.dart';
import 'package:solace/models/ai_character.dart';
import 'package:solace/services/character_recovery_resolver.dart';

AICharacter character({
  required String id,
  required String avatar,
  required bool hidden,
}) {
  final now = DateTime(2026, 8, 9);
  return AICharacter(
    id: id,
    name: '妹妹',
    avatarUrl: avatar,
    personality: '温柔、黏人',
    coreDesire: '陪伴用户',
    moralBoundary: '尊重用户',
    createdAt: now,
    updatedAt: now,
    isHidden: hidden,
  );
}

void main() {
  test('same character with different avatars resolves to one canonical record',
      () {
    final oldAvatar = character(id: 'old', avatar: 'old.png', hidden: true);
    final newAvatar = character(id: 'new', avatar: 'new.png', hidden: true);

    expect(
      CharacterRecoveryResolver.identityKey(oldAvatar),
      CharacterRecoveryResolver.identityKey(newAvatar),
    );

    final canonical = CharacterRecoveryResolver.chooseCanonical(
      [oldAvatar, newAvatar],
      {'old': 4, 'new': 18},
    );
    expect(canonical.id, 'new');
  });

  test('does not merge genuinely different same-name characters', () {
    final first = character(id: 'first', avatar: 'a.png', hidden: true);
    final second =
        character(id: 'second', avatar: 'b.png', hidden: true).copyWith(
      personality: '活泼、调皮',
    );

    expect(
      CharacterRecoveryResolver.identityKey(first),
      isNot(CharacterRecoveryResolver.identityKey(second)),
    );
  });

  test('groups fully hidden duplicate records into one recovery entry', () {
    final first = character(id: 'first', avatar: 'old.png', hidden: true);
    final second = character(id: 'second', avatar: 'new.png', hidden: true);

    final entries = CharacterRecoveryResolver.recoverableHiddenCharacters(
      [first, second],
    );

    expect(entries, hasLength(1));
  });

  test('does not hide a visible canonical character behind a duplicate group',
      () {
    final visible = character(id: 'visible', avatar: 'new.png', hidden: false);
    final hidden = character(id: 'hidden', avatar: 'old.png', hidden: true);

    final entries = CharacterRecoveryResolver.recoverableHiddenCharacters(
      [visible, hidden],
    );
    expect(entries, isEmpty);
  });

  test('visible duplicate wins ties so recovery is idempotent', () {
    final visible = character(id: 'visible', avatar: 'new.png', hidden: false);
    final hidden = character(id: 'hidden', avatar: 'old.png', hidden: true);

    final canonical = CharacterRecoveryResolver.chooseCanonical(
      [hidden, visible],
      {'hidden': 5, 'visible': 5},
    );
    expect(canonical.id, 'visible');
  });
}
