import 'package:flutter_test/flutter_test.dart';
import 'package:solace/utils/response_decoder.dart';

void main() {
  group('ResponseDecoder', () {
    test('extractVisibleContent ignores reasoning-only chat completions', () {
      final data = {
        'choices': [
          {
            'message': {
              'role': 'assistant',
              'content': '',
              'reasoning_content': '我需要先分析用户要什么，然后再生成评论。',
            },
          },
        ],
      };

      expect(ResponseDecoder.extractContent(data), contains('分析'));
      expect(ResponseDecoder.extractVisibleContent(data), isEmpty);
    });

    test('extractVisibleContent keeps assistant content over reasoning', () {
      final data = {
        'choices': [
          {
            'message': {
              'role': 'assistant',
              'content': '<think>内部分析</think><MOMENT>今天想早点休息。</MOMENT>',
              'reasoning_content': '我需要分析人设。',
            },
          },
        ],
      };

      expect(
        ResponseDecoder.extractVisibleContent(data),
        '<think>内部分析</think><MOMENT>今天想早点休息。</MOMENT>',
      );
    });

    test('extractVisibleContent skips Responses API reasoning items', () {
      final data = {
        'output': [
          {
            'type': 'reasoning',
            'content': '我需要先分析角色和用户关系。',
          },
          {
            'type': 'message',
            'content': [
              {'type': 'text', 'text': '今天想早点休息。'},
            ],
          },
        ],
      };

      expect(ResponseDecoder.extractVisibleContent(data), '今天想早点休息。');
    });

    test('repairs common GBK mojibake phrases', () {
      expect(
        ResponseDecoder.repairText('鐢ㄦ埛鍙戦€佷簡涓€寮犲浘鐗'),
        '用户发送了一张图片',
      );
      // 验证 repairText 能识别并修复 GBK mojibake 片段
      final repaired = ResponseDecoder.repairText('鍥炲锛氫綘濂�');
      expect(repaired.contains('回复'), isTrue);
    });
  });
}
