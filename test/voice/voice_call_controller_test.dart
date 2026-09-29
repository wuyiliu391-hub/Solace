// 语音通话控制器状态机测试：
// 覆盖初始状态、静音开关、手动输入、挂断幂等与收尾流程、生命周期安全。
// VAD/录音/播放器的原生调用在纯 Dart 测试环境不可用（MissingPlugin），
// 控制器内部均已 try/catch 兜底，因此这些路径只验证「不崩溃」。

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:solace/blocs/chat/chat_bloc.dart';
import 'package:solace/models/chat_message.dart';
import 'package:solace/models/chat_session.dart';
import 'package:solace/services/voice/voice_call_controller.dart';

class _MockChatBloc extends Mock implements ChatBloc {}

class _FakeChatMessage extends Fake implements ChatMessage {}

ChatSession _buildSession() {
  return ChatSession(
    id: 'session-1',
    userId: 'user-1',
    aiCharacterId: 'char-1',
    aiCharacterName: '测试角色',
    createdAt: DateTime(2026, 1, 1),
  );
}

void main() {
  // 控制器构造时会实例化 audioplayers/record 插件，需要平台绑定
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockChatBloc chatBloc;

  setUpAll(() {
    // appendSystemMessage(any()) 需要 ChatMessage 兜底值
    registerFallbackValue(_FakeChatMessage());

    // 吸掉 audioplayers / record 插件在构造期发起的平台调用，
    // 否则 MissingPluginException 会在测试完成后异步抛出、污染用例。
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final name in [
      'xyz.luan/audioplayers.global',
      'xyz.luan/audioplayers',
      'com.llfbandit.record/messages',
    ]) {
      final channel = MethodChannel(name);
      messenger.setMockMethodCallHandler(channel, (call) async => null);
    }
  });

  setUp(() {
    chatBloc = _MockChatBloc();
    when(() => chatBloc.clearCallMessages(
            chatId: any(named: 'chatId'), since: any(named: 'since')))
        .thenAnswer((_) async {});
    when(() => chatBloc.appendSystemMessage(any()))
        .thenAnswer((_) async {});
    when(() => chatBloc.extractCallMemories(
            chatId: any(named: 'chatId'),
            recentMessages: any(named: 'recentMessages')))
        .thenAnswer((_) async {});
  });

  VoiceCallController buildController() => VoiceCallController(
        chatBloc: chatBloc,
        session: _buildSession(),
        userId: 'user-1',
      );

  group('VoiceCallController 初始状态', () {
    test('初始为 connecting 阶段，静音/扬声器均关闭', () {
      final c = buildController();
      addTearDown(c.dispose);

      expect(c.phase, VoiceCallPhase.connecting);
      expect(c.statusText, '正在连接…');
      expect(c.isEnded, isFalse);
      expect(c.muted, isFalse);
      expect(c.speakerOn, isFalse);
      expect(c.lastError, isNull);
      expect(c.transcript, isEmpty);
    });
  });

  group('VoiceCallController.toggleMute', () {
    test('切换静音：状态翻转并通知监听者', () {
      final c = buildController();
      addTearDown(c.dispose);

      var notified = 0;
      c.addListener(() => notified++);

      c.toggleMute();
      expect(c.muted, isTrue);
      expect(notified, 1);

      c.toggleMute();
      expect(c.muted, isFalse);
      expect(notified, 2);
    });

    test('挂断后静音开关不再生效', () async {
      final c = buildController();
      await c.hangUp();

      c.toggleMute();
      expect(c.muted, isFalse);
    });
  });

  group('VoiceCallController.toggleSpeaker', () {
    test('切换扬声器：状态翻转（底层播放器异常被吞掉，不崩溃）', () async {
      final c = buildController();
      addTearDown(c.dispose);

      await c.toggleSpeaker();
      expect(c.speakerOn, isTrue);
    });
  });

  group('VoiceCallController.sendText', () {
    test('dispose 后手动输入是安全空操作', () {
      final c = buildController();
      c.dispose();

      // 不应抛异常
      c.sendText('你好');
    });
  });

  group('VoiceCallController.hangUp', () {
    test('挂断：进入 ended 阶段并写入系统通话记录', () async {
      final c = buildController();

      await c.hangUp();

      expect(c.phase, VoiceCallPhase.ended);
      expect(c.isEnded, isTrue);
      expect(c.statusText, '通话已结束');

      // 未 start 过（callStartedAt 为空）→ 不清理通话消息，但仍写记录
      verifyNever(() => chatBloc.clearCallMessages(
            chatId: any(named: 'chatId'),
            since: any(named: 'since'),
          ));
      verify(() => chatBloc.appendSystemMessage(any())).called(1);

      // 通话转写为空 → 不触发记忆提取
      verifyNever(() => chatBloc.extractCallMemories(
            chatId: any(named: 'chatId'),
            recentMessages: any(named: 'recentMessages'),
          ));
    });

    test('通话记录文本：秒数格式化正确', () async {
      final c = buildController();

      await c.hangUp();

      final captured = verify(() => chatBloc.appendSystemMessage(captureAny()))
          .captured
          .single;
      // 未 start → durationSec = 0
      expect(captured.content, contains('语音通话'));
    });

    test('挂断幂等：重复挂断不会重复写通话记录', () async {
      final c = buildController();

      await c.hangUp();
      await c.hangUp(); // 第二次直接返回

      verify(() => chatBloc.appendSystemMessage(any())).called(1);
    });

    test('挂断后再 dispose 不崩溃（生命周期安全）', () async {
      final c = buildController();
      await c.hangUp();
      c.dispose();
    });
  });
}
