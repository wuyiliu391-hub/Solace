import 'package:flutter_test/flutter_test.dart';
import 'package:solace/models/ai_character.dart';

void main() {
  test('AICharacter.copyWith can clear nullable persona fields', () {
    final character = AICharacter(
      id: 'char_1',
      name: '阿助',
      personality: '温柔',
      coreDesire: '陪伴',
      moralBoundary: '真诚',
      backgroundStory: '旧故事',
      worldSetting: '旧世界观',
      languageStyle: '旧语言风格',
      tabooTopics: '旧禁忌话题',
      userNickname: '旧称呼',
      userAlias: '旧备注',
      createdAt: DateTime(2026, 6, 4),
    );

    final updated = character.copyWith(
      clearBackgroundStory: true,
      clearWorldSetting: true,
      clearLanguageStyle: true,
      clearTabooTopics: true,
      clearUserNickname: true,
      clearUserAlias: true,
    );

    expect(updated.backgroundStory, isNull);
    expect(updated.worldSetting, isNull);
    expect(updated.languageStyle, isNull);
    expect(updated.tabooTopics, isNull);
    expect(updated.userNickname, isNull);
    expect(updated.userAlias, isNull);
  });
}
