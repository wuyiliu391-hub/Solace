import 'package:flutter_test/flutter_test.dart';
import 'package:solace/models/llm_request.dart';

void main() {
  group('LlmResponse', () {
    test('parses OpenAI compatible chat completion content', () {
      final response = LlmResponse.fromJson({
        'choices': [
          {
            'message': {'role': 'assistant', 'content': '你好，我在。'},
          }
        ],
        'usage': {'prompt_tokens': 10, 'completion_tokens': 5},
      });

      expect(response.content, '你好，我在。');
      expect(response.promptTokens, 10);
      expect(response.completionTokens, 5);
    });
  });

  group('LlmRequest', () {
    test('omits max_tokens when maxTokens is null', () {
      const request = LlmRequest(
        messages: [LlmMessage(role: 'user', content: '写一段小说')],
        model: 'test-model',
        maxTokens: null,
      );

      expect(request.toJson().containsKey('max_tokens'), isFalse);
    });
  });
}
