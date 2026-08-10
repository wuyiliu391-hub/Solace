import 'package:flutter_test/flutter_test.dart';
import 'package:solace/models/ai_turn_state.dart';

void main() {
  test('parses a valid turn state payload', () {
    const content = '''
看到你回来我就安心了。
[TURN_STATE]{"emoji":"🥹","emotion":"安心","intensity":0.72,"thought":"希望你今天别再一个人扛着。"}[/TURN_STATE]
''';

    final state = AiTurnState.parse(content);

    expect(state, isNotNull);
    expect(state!.emoji, '🥹');
    expect(state.emotion, '安心');
    expect(state.intensity, .72);
    expect(state.thought, '希望你今天别再一个人扛着。');
    expect(state.isValid, isTrue);
  });

  test('does not accept missing or malformed turn state payloads', () {
    expect(AiTurnState.parse('普通回复'), isNull);
    expect(AiTurnState.parse('[TURN_STATE]not-json[/TURN_STATE]'), isNull);
    expect(
      AiTurnState.parse('[TURN_STATE]{"emotion":"","thought":""}[/TURN_STATE]')
          ?.isValid,
      isFalse,
    );
  });

  test('creates a fresh state when the model omits the turn state tag', () {
    const previous = AiTurnState(
      emotion: '平静',
      intensity: 0.2,
      thought: '我正在等你继续说。',
    );

    final state = AiTurnState.fallbackForTurn(
      userMessage: '我今天终于把这件事做完了。',
      aiReply: '那太好了，我就知道你可以的。',
      sentimentLabel: '开心',
      previous: previous,
    );

    expect(state.isValid, isTrue);
    expect(state.emotion, '开心');
    expect(state.thought, isNot(previous.thought));
    expect(state.thought, contains('把这件事做完了'));
  });

  test('parses an emoji and fallback changes it every turn', () {
    const previous = AiTurnState(
      emoji: '🙂',
      emotion: '平静',
      intensity: 0.2,
      thought: '旧状态',
    );

    final parsed = AiTurnState.parse(
      '[TURN_STATE]{"emoji":"😂","emotion":"开心","intensity":0.8,"thought":"笑死我了"}[/TURN_STATE]',
    );
    final fallback = AiTurnState.fallbackForTurn(
      userMessage: '这也太好笑了吧。',
      aiReply: '哈哈哈。',
      sentimentLabel: '开心',
      previous: previous,
    );

    expect(parsed?.emoji, '😂');
    expect(fallback.emoji, isNot(previous.emoji));
  });
}
