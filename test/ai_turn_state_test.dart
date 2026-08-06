import 'package:flutter_test/flutter_test.dart';
import 'package:solace/models/ai_turn_state.dart';

void main() {
  test('parses a valid turn state payload', () {
    const content = '''
看到你回来我就安心了。
[TURN_STATE]{"emotion":"安心","intensity":0.72,"thought":"希望你今天别再一个人扛着。"}[/TURN_STATE]
''';

    final state = AiTurnState.parse(content);

    expect(state, isNotNull);
    expect(state!.emotion, '安心');
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
}
