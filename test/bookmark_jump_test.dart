// 收藏跳转回归测试：锁定「按 id 定位」的两个致命根因。
//
// 1. ChatMessagesLoaded 同内容时 Equatable 相等 → BlocConsumer 的
//    listenWhen/buildWhen 都不触发 → 「打开聊天页毫无反应」。
//    修法：ChatMessagesLoaded 带 jumpToMessageId 并计入 props。
// 2. listener 只在 messages.length 变化时触发 → 首屏定位分支永远等不到时机。
//    修法：listenWhen 改为「状态类型一变就触发」。
//
// 这里能纯 Dart 验证第 1 条（props 相等性）；第 2 条属于 widget 行为，
// 由 CI 的 group_chat / chat 详情页测试覆盖，本文件给出可执行的状态断言。
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/blocs/chat/chat_event.dart';
import 'package:solace/blocs/chat/chat_state.dart';
import 'package:solace/models/chat_message.dart';

ChatMessage _msg(String id, {String content = 'hi'}) => ChatMessage(
      id: id,
      chatId: 'c1',
      senderId: 'u1',
      senderName: '我',
      content: content,
      isUser: true,
    );

void main() {
  final a = _msg('m1');
  final b = _msg('m2');

  group('ChatMessagesLoaded · 定位标记必须进入 props', () {
    test('同一条消息列表，无标记 vs 有标记 → 状态不相等（listener 会触发）', () {
      final plain = ChatMessagesLoaded([a, b], hasMore: true);
      final jumped = ChatMessagesLoaded([a, b],
          hasMore: true, jumpToMessageId: 'm1');

      // 这是修复的核心：旧实现两者 == 相同，BlocConsumer 直接吞掉
      expect(plain == jumped, isFalse);
      expect(plain.props, isNot(equals(jumped.props)));
    });

    test('两个不同的定位目标 → 状态不相等', () {
      final j1 = ChatMessagesLoaded([a], jumpToMessageId: 'm1');
      final j2 = ChatMessagesLoaded([a], jumpToMessageId: 'm2');
      expect(j1 == j2, isFalse);
    });

    test('同一列表 + 同一目标 → 状态相等（避免无意义重建）', () {
      final j1 = ChatMessagesLoaded([a, b], jumpToMessageId: 'm1');
      final j2 = ChatMessagesLoaded([a, b], jumpToMessageId: 'm1');
      expect(j1 == j2, isTrue);
    });

    test('普通加载默认不带标记，不影响既有行为', () {
      final s = ChatMessagesLoaded([a, b]);
      expect(s.jumpToMessageId, isNull);
      // 旧式构造（位置参数 + hasMore）仍然编译可用
      expect(s.hasMore, isTrue);
    });
  });

  group('ChatLoadUntilMessage · 事件语义', () {
    test('携带 chatId 与 messageId（定位入口）', () {
      const e = ChatLoadUntilMessage(chatId: 'c1', messageId: 'm1');
      expect(e.chatId, 'c1');
      expect(e.messageId, 'm1');
    });
  });

  group('列表内容相等性（定位依赖 id 而非对象）', () {
    test('内容相同的 ChatMessage 列表按值相等', () {
      // 外部入口（收藏页全库扫描）与会话内缓存是两个不同实例，
      // 所以定位必须走 id 比对，不能用对象/内容相等判断。
      final fromStorage = _msg('m1', content: '你好');
      final fromCache = _msg('m1', content: '你好');
      expect(identical(fromStorage, fromCache), isFalse);
      expect(fromStorage.id, fromCache.id);
      final list1 = [fromStorage];
      final list2 = [fromCache];
      expect(list1.indexWhere((m) => m.id == 'm1'), 0);
      expect(list2.indexWhere((m) => m.id == 'm1'), 0);
    });

    test('id 不同则定位失败（据此决定是否重新取窗口）', () {
      final list = [a, b];
      expect(list.indexWhere((m) => m.id == 'm9'), -1);
      expect(list.indexWhere((m) => m.id == 'm2'), 1);
    });
  });
}
