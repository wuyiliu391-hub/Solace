import 'package:flutter_test/flutter_test.dart';
import 'package:solace/services/tools/device_intent_router.dart';

void main() {
  group('DeviceIntentRouter real commands', () {
    test('recognizes direct app, system, and status requests', () {
      expect(DeviceIntentRouter.match('帮我打开微信').kind,
          DeviceIntentKind.deterministic);
      expect(
          DeviceIntentRouter.match('截个图').kind, DeviceIntentKind.deterministic);
      expect(DeviceIntentRouter.match('看看还有多少电').kind,
          DeviceIntentKind.deterministic);
      expect(DeviceIntentRouter.match('电量还有多少').kind,
          DeviceIntentKind.deterministic);
      expect(DeviceIntentRouter.match('电量还有多少啊作者').kind,
          DeviceIntentKind.deterministic);
      expect(DeviceIntentRouter.match('通知数量').kind,
          DeviceIntentKind.deterministic);
      expect(DeviceIntentRouter.match('查看进程').kind,
          DeviceIntentKind.deterministic);
      expect(DeviceIntentRouter.match('运行中的进程').kind,
          DeviceIntentKind.deterministic);
      expect(DeviceIntentRouter.match('当前应用').kind,
          DeviceIntentKind.deterministic);
    });

    test('recognizes multi-step requests for the agent path', () {
      expect(
          DeviceIntentRouter.match('帮我设置明早七点的闹钟').kind, DeviceIntentKind.agent);
      expect(DeviceIntentRouter.match('把短信发送给妈妈').kind, DeviceIntentKind.agent);
      expect(
          DeviceIntentRouter.match('拨打联系人小王的电话').kind, DeviceIntentKind.agent);
    });
  });

  group('DeviceIntentRouter narrative boundaries', () {
    test(
        'does not treat narration, quotes, conditions, or negation as commands',
        () {
      for (final text in [
        '她打开微信以后就再也没有回复我。',
        '他说“帮我打开微信”，听起来很着急。',
        '如果能打开微信就好了。',
        '别打开微信，我只是想和你聊聊。',
        '我今天心里像充满电一样。',
      ]) {
        expect(DeviceIntentRouter.match(text).kind, DeviceIntentKind.none,
            reason: text);
      }
    });

    test('does not route ordinary relationship conversation', () {
      for (final text in ['你好', '今天声音很大，我有点烦。', '你能打开话题吗？', '我想把心门关上。']) {
        expect(DeviceIntentRouter.match(text).kind, DeviceIntentKind.none,
            reason: text);
      }
    });

    test('only accepts text input requests with an explicit device target', () {
      expect(DeviceIntentRouter.match('输入文字 我想你了').kind, DeviceIntentKind.none);
      expect(
          DeviceIntentRouter.isExplicitTextInputRequest('输入文字 我想你了'), isFalse);
      expect(
        DeviceIntentRouter.match('在当前输入框输入：我想你了').kind,
        DeviceIntentKind.deterministic,
      );
      expect(
        DeviceIntentRouter.isExplicitTextInputRequest('在当前输入框输入：我想你了'),
        isTrue,
      );
    });

    test('rejects long conversational content', () {
      expect(
          DeviceIntentRouter.match('帮我打开微信。' * 30).kind, DeviceIntentKind.none);
    });
  });
}
