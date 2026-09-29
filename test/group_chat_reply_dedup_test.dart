import 'package:flutter_test/flutter_test.dart';
import 'package:solace/blocs/group_chat/group_chat_prompts.dart';

void main() {
  test('normalizes punctuation and detects exact duplicate replies', () {
    expect(isDuplicateGroupReply('好！我也这么觉得。', '好，我也这么觉得'), isTrue);
  });

  test('detects highly similar long replies', () {
    expect(
      isDuplicateGroupReply(
        '这件事确实很奇怪，我觉得我们应该先把具体情况弄清楚。',
        '这件事真的很奇怪，我觉得我们应该先把具体情况弄清楚。',
      ),
      isTrue,
    );
  });

  test('does not reject ordinary short acknowledgements or different content',
      () {
    expect(isDuplicateGroupReply('好', '好的'), isFalse);
    expect(isDuplicateGroupReply('我想吃面', '明天一起看电影吧'), isFalse);
  });
}
