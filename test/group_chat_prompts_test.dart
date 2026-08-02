import 'package:flutter_test/flutter_test.dart';
import 'package:solace/blocs/group_chat/group_chat_prompts.dart';
import 'package:solace/models/ai_character.dart';

void main() {
  final charA = AICharacter(
    id: 'c1', name: '小美', personality: '温柔', coreDesire: '陪伴',
    moralBoundary: '不伤人', createdAt: DateTime.now(),
    backgroundStory: '咖啡店店员', openingLine: '你好呀',
    catchphrases: '好耶',
  );
  final charB = AICharacter(
    id: 'c2', name: '阿强', personality: '直爽', coreDesire: '热闹',
    moralBoundary: '不骗人', createdAt: DateTime.now(),
    backgroundStory: '程序员', openingLine: '哟',
    catchphrases: '整',
  );

  test('群成员名单 prompt（对标 new_group_chat_prompt）', () {
    final p = buildGroupIntroPrompt(
      selfName: '小美',
      memberNames: ['小美', '阿强', '你'],
      isNewChat: true,
    );
    expect(p, contains('群成员'));
    expect(p, contains('小美'));
    expect(p, contains('阿强'));
  });

  test('nudge prompt（对标 group_nudge_prompt）', () {
    expect(buildGroupNudge('小美'), '[请只以「小美」的身份继续发言。]');
  });

  test('消息格式化：自己发言不带前缀，他人带 名字: 内容', () {
    expect(formatGroupMessage(isSelf: true, senderName: '小美', content: '哈喽'), '哈喽');
    expect(formatGroupMessage(isSelf: false, senderName: '阿强', content: '整'), '阿强: 整');
  });

  test('合并角色卡（对标 getGroupCharacterCards）', () {
    final combined = buildCombinedCard(
      members: [charA, charB],
      joinPrefix: '',
      joinSuffix: '',
    );
    expect(combined.description, contains('咖啡店店员'));
    expect(combined.description, contains('程序员'));
    expect(combined.personality, contains('温柔'));
    expect(combined.personality, contains('直爽'));
  });

  test('合并卡 joinPrefix/joinSuffix 包字段', () {
    final combined = buildCombinedCard(
      members: [charA],
      joinPrefix: '【',
      joinSuffix: '】',
    );
    expect(combined.description, contains('【咖啡店店员】'));
  });
}
