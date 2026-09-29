import 'package:flutter_test/flutter_test.dart';
import 'package:solace/models/chat_message.dart';

void main() {
  test('ChatMessage persists reasoning through map serialization', () {
    final message = ChatMessage(
      id: 'msg_1',
      chatId: 'chat_1',
      senderId: 'ai_char_1',
      content: '正文回复',
      reasoning: '思考过程',
      createdAt: DateTime(2026, 6, 4),
    );

    final map = message.toMap();
    expect(map['reasoning'], '思考过程');

    final restored = ChatMessage.fromMap(map);
    expect(restored.reasoning, '思考过程');
  });
}
