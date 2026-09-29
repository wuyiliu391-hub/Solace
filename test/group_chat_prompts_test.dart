import 'package:flutter_test/flutter_test.dart';
import 'package:solace/blocs/group_chat/group_chat_prompts.dart';
import 'package:solace/models/ai_character.dart';

void main() {
  test('member voice prompt keeps each character distinct', () {
    final quiet = AICharacter(
      id: 'quiet',
      name: '林默',
      personality: '克制、观察细致，不轻易下结论',
      coreDesire: '理解事情的真相',
      moralBoundary: '',
      languageStyle: '短句，少用感叹号，喜欢先说具体细节',
      catchphrases: '先等等',
      createdAt: DateTime(2026, 8, 7),
    );
    final lively = AICharacter(
      id: 'lively',
      name: '周晴',
      personality: '直率、热情，想到什么就说什么',
      coreDesire: '让群里热闹起来',
      moralBoundary: '',
      languageStyle: '语速快，口语化，偶尔用夸张的感叹',
      createdAt: DateTime(2026, 8, 7),
    );

    final prompt = buildMemberVoicePrompt(
      self: quiet,
      otherMembers: [lively],
      recentReplies: const ['周晴：这也太离谱了吧！'],
    );

    expect(prompt, contains('你只能作为「林默」发言'));
    expect(prompt, contains('短句，少用感叹号'));
    expect(prompt, contains('周晴'));
    expect(prompt, contains('不得复用本轮其他角色的句式'));
    expect(prompt, contains('这也太离谱了吧！'));
  });
}
