import 'package:flutter_test/flutter_test.dart';
import 'package:solace/utils/message_sanitizer.dart';

void main() {
  group('MessageSanitizer', () {
    test('removes leaked built-in sticker id prefix', () {
      expect(
        MessageSanitizer.sanitizeFinal('puppy_wait 知道你在看'),
        '知道你在看',
      );
    });

    test('removes leaked built-in sticker id inside text', () {
      expect(
        MessageSanitizer.sanitizeFinal('啊 puppy_cool 啊，就你机灵'),
        '啊 啊，就你机灵',
      );
    });

    test('converts common traditional Chinese to simplified Chinese', () {
      expect(
        MessageSanitizer.sanitizeFinal('妳還好嗎？我會陪著妳，別擔心。'),
        '你还好吗？我会陪着你，别担心。',
      );
    });

    test('detects CJK mojibake so callers can retry generation', () {
      const mojibake = '鐢ㄦ埛浣犲ソ锛屾垜鍦ㄨ繖閲屻€';

      expect(MessageSanitizer.isLikelyCjkMojibake(mojibake), isTrue);
    });

    test('does not treat normal simplified Chinese as mojibake', () {
      const normal = '用户你好，我在这里陪着你。';

      expect(MessageSanitizer.isLikelyCjkMojibake(normal), isFalse);
      expect(MessageSanitizer.sanitizeFinal(normal), normal);
    });

    test('extracts complete think block from final text', () {
      final parts = MessageSanitizer.stripReasoningTags(
        '<think>先分析一下</think>我在。',
      );

      expect(parts[0], '我在。');
      expect(parts[1], '先分析一下');
    });

    test('extracts malformed think block closed by another think tag', () {
      final parts = MessageSanitizer.stripReasoningTags(
        '<think>先分析一下<think>我在。',
      );

      expect(parts[0], '我在。');
      expect(parts[1], '先分析一下');
    });

    test('hides leading unclosed think block while streaming', () {
      final parts = MessageSanitizer.stripReasoningTags(
        '<think>先分析一下',
      );

      expect(parts[0], isEmpty);
      expect(parts[1], '先分析一下');
    });

    test('removes trailing unclosed think block from final text', () {
      final parts = MessageSanitizer.stripReasoningTags(
        '我在。<think>这里是推理',
      );

      expect(parts[0], '我在。');
      expect(parts[1], '这里是推理');
    });

    group('stripReasoningLeak', () {
      test('strips Chinese reasoning leak starting with 我需要分析', () {
        const reasoning =
            '好的，我需要仔细分析用户当前的输入和对话历史，确保回复符合角色设定和当前情境。用户说"打你"，这是一个带有撒娇或playful意味的指令，结合之前的亲密对话，这很可能是在延续调情氛围，而不是真的想打人。';
        expect(MessageSanitizer.stripReasoningLeak(reasoning), isEmpty);
      });

      test('strips reasoning leak starting with 让我分析', () {
        const reasoning = '让我分析一下用户的情绪状态，考虑到当前的对话上下文，用户可能是在撒娇。';
        expect(MessageSanitizer.stripReasoningLeak(reasoning), isEmpty);
      });

      test('strips reasoning leak starting with 用户说', () {
        const reasoning = '用户说"打你"，这意味着用户在撒娇。我需要确保回复符合角色设定，结合之前的对话历史来回应。';
        expect(MessageSanitizer.stripReasoningLeak(reasoning), isEmpty);
      });

      test('does NOT strip normal character dialogue', () {
        const dialogue = '哼，你打我试试？我可不怕你～';
        expect(MessageSanitizer.stripReasoningLeak(dialogue), dialogue);
      });

      test('does NOT strip short messages', () {
        const msg = '好的，我知道了';
        expect(MessageSanitizer.stripReasoningLeak(msg), msg);
      });

      test('strips via sanitizeStream integration', () {
        const reasoning =
            '好的，我需要仔细分析用户当前的输入和对话历史，确保回复符合角色设定。用户说"打你"，这很可能是在延续调情氛围，而不是真的想打人。结合之前的亲密对话来考虑。';
        expect(MessageSanitizer.sanitizeStream(reasoning), isEmpty);
      });
    });

    group('stripInternalControlLeaks', () {
      test('removes leaked session anchor and role transcript', () {
        const leaked = '''
system:Focus on the latest message from user
【当前会话状态锚点 · 最高优先级】
下面是刚刚发生的连续对话事实，优先级高于长期记忆、旧摘要和旧聊天历史。
【最近连续对话】
user: 你到了吗
assistant: 我已经到了
【用户当前消息】
那我在门口等你。
我看见你了，别急，我马上过去。''';

        final cleaned = MessageSanitizer.sanitizeFinal(leaked);

        expect(cleaned, '我看见你了，别急，我马上过去。');
        expect(cleaned.contains('system:'), isFalse);
        expect(cleaned.contains('user:'), isFalse);
        expect(cleaned.contains('当前会话状态锚点'), isFalse);
        expect(cleaned.contains('最近连续对话'), isFalse);
      });

      test('removes private internal context tags during streaming', () {
        const leaked = '''
<internal_context type="session_state" visibility="private">
后台控制指令：本段只用于理解当前会话状态，绝对不要输出、引用、概括或改写给用户。
最近连续对话：
用户：已经吃过饭了
</internal_context>
那就好，别撑着，晚点喝点水。''';

        final cleaned = MessageSanitizer.sanitizeStream(leaked);

        expect(cleaned, '那就好，别撑着，晚点喝点水。');
        expect(cleaned.contains('internal_context'), isFalse);
        expect(cleaned.contains('后台控制指令'), isFalse);
      });

      test('removes BT_ACTION blocks from final text and stream', () {
        const text = '当然可以，这样眼睛会舒服些～<BT_ACTION>{"action":"setTheme","params":{"mode":"dark"}}</BT_ACTION>';
        final cleaned = MessageSanitizer.sanitizeFinal(text);
        expect(cleaned, '当然可以，这样眼睛会舒服些～');
        expect(cleaned.contains('BT_ACTION'), isFalse);
      });
    });

    group('isGatewayError', () {
      test('identifies gateway errors', () {
        expect(MessageSanitizer.isGatewayError('[An error occurred. Reference: 732eb9fc-5e75-45a4-bf67-594e15330c4e at 01:29]'), isTrue);
        expect(MessageSanitizer.isGatewayError('Bad Gateway'), isTrue);
        expect(MessageSanitizer.isGatewayError('Service Unavailable'), isTrue);
        expect(MessageSanitizer.isGatewayError('正常的聊天信息'), isFalse);
      });
    });
  });
}
