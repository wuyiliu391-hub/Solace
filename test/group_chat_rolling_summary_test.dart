import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solace/models/group_chat_summary.dart';
import 'package:solace/models/group_chat_message.dart';
import 'package:solace/services/group_chat_rolling_summary.dart';
import 'package:solace/repositories/local_storage_repository.dart';

void main() {
  test('only triggers after fifteen new messages', () {
    expect(shouldRefreshGroupSummary(messageCount: 14, summarizedCount: 0),
        isFalse);
    expect(shouldRefreshGroupSummary(messageCount: 15, summarizedCount: 0),
        isTrue);
    expect(shouldRefreshGroupSummary(messageCount: 29, summarizedCount: 15),
        isFalse);
    expect(shouldRefreshGroupSummary(messageCount: 30, summarizedCount: 15),
        isTrue);
  });

  test('new group message schema includes user and system flags', () {
    expect(LocalStorageRepository.expectedColumns['group_chat_messages'],
        containsPair('isUser', anything));
    expect(LocalStorageRepository.expectedColumns['group_chat_messages'],
        containsPair('isSystem', anything));
  });

  test('refreshes from the current history when messages were deleted', () {
    expect(
      shouldResetGroupSummary(messageCount: 10, summarizedCount: 15),
      isTrue,
    );
  });

  test('summary keys isolate chat branches', () {
    expect(groupSummaryKey('group-1', 'branch-a'),
        isNot(groupSummaryKey('group-1', 'branch-b')));
    expect(groupSummaryKey('group-1', 'branch-a'),
        groupSummaryKey('group-1', 'branch-a'));
  });

  test('summary input preserves every speaker name', () {
    expect(
      formatGroupSummaryMessages([
        (speaker: '用户', content: '我们周末去看展'),
        (speaker: '小美', content: '我记住了'),
        (speaker: '阿强', content: '我也想去'),
      ]),
      '用户：我们周末去看展\n小美：我记住了\n阿强：我也想去',
    );
  });

  test('reads summary fields from legacy scalar and date values', () {
    final summary = GroupChatSummary.fromMap({
      'groupId': 42,
      'chatId': true,
      'summary': 123,
      'messageCount': '15',
      'updatedAt': 1770000000000,
    });

    expect(summary.groupId, '42');
    expect(summary.chatId, 'true');
    expect(summary.summary, '123');
    expect(summary.messageCount, 15);
    expect(summary.updatedAt.millisecondsSinceEpoch, 1770000000000);
  });

  test('web message reads use groupId as chat branch fallback for legacy rows',
      () async {
    SharedPreferences.setMockInitialValues({
      'gc_msg_legacy': jsonEncode(GroupChatMessage(
        id: 'legacy',
        groupId: 'group-1',
        senderId: 'sender',
        content: '旧消息',
        timestamp: DateTime(2026, 8, 4),
      ).toJson()),
    });
    final repository = LocalStorageRepository(isWeb: true);
    await repository.initialize();

    final messages = await repository.getGroupChatMessages(
      'group-1',
      chatId: 'group-1',
    );

    expect(messages.map((message) => message.id), contains('legacy'));
  });

  test('serializes refreshes for the same group chat branch', () async {
    final coordinator = GroupSummaryRefreshCoordinator();
    final order = <String>[];

    final first = coordinator.run('group-1', 'chat-1', () async {
      order.add('first-start');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      order.add('first-end');
    });
    final second = coordinator.run('group-1', 'chat-1', () async {
      order.add('second-start');
      order.add('second-end');
    });

    await Future.wait([first, second]);
    expect(order, ['first-start', 'first-end', 'second-start', 'second-end']);
  });

  test('persists group summaries on web with isolated group and chat keys',
      () async {
    SharedPreferences.setMockInitialValues({});
    final repository = LocalStorageRepository(isWeb: true);
    await repository.initialize();
    final summary = GroupChatSummary(
      groupId: 'group-1',
      chatId: 'chat-1',
      summary: '周末看展',
      messageCount: 15,
      updatedAt: DateTime(2026, 8, 4),
    );

    await repository.saveGroupChatSummary(summary);

    final restored = await repository.getGroupChatSummary('group-1', 'chat-1');
    expect(restored?.groupId, summary.groupId);
    expect(restored?.chatId, summary.chatId);
    expect(restored?.summary, summary.summary);
    expect(restored?.messageCount, summary.messageCount);
    expect(restored?.updatedAt, summary.updatedAt);
    expect(await repository.getGroupChatSummary('group-1', 'chat-2'), isNull);

    final first = GroupChatSummary(
      groupId: 'group',
      chatId: '1::chat',
      summary: 'first',
      messageCount: 1,
      updatedAt: summary.updatedAt,
    );
    final second = GroupChatSummary(
      groupId: 'group::1',
      chatId: 'chat',
      summary: 'second',
      messageCount: 2,
      updatedAt: summary.updatedAt,
    );
    await repository.saveGroupChatSummary(first);
    await repository.saveGroupChatSummary(second);
    expect(
      (await repository.getGroupChatSummary('group', '1::chat'))?.summary,
      'first',
    );
    expect(
      (await repository.getGroupChatSummary('group::1', 'chat'))?.summary,
      'second',
    );

    await repository.deleteGroupChatSummary('group-1', 'chat-1');
    expect(await repository.getGroupChatSummary('group-1', 'chat-1'), isNull);
  });

  test('deleting a group session removes every web summary for that group',
      () async {
    SharedPreferences.setMockInitialValues({});
    final repository = LocalStorageRepository(isWeb: true);
    await repository.initialize();
    final summary = (String groupId, String chatId) => GroupChatSummary(
          groupId: groupId,
          chatId: chatId,
          summary: chatId,
          messageCount: 15,
          updatedAt: DateTime(2026, 8, 4),
        );
    await repository.saveGroupChatSummary(summary('group-1', 'chat-1'));
    await repository.saveGroupChatSummary(summary('group-1', 'chat-2'));
    await repository.saveGroupChatSummary(summary('group-2', 'other-chat'));

    await repository.deleteGroupChatSession('group-1');

    expect(await repository.getGroupChatSummary('group-1', 'chat-1'), isNull);
    expect(await repository.getGroupChatSummary('group-1', 'chat-2'), isNull);
    expect(
      (await repository.getGroupChatSummary('group-2', 'other-chat'))?.summary,
      'other-chat',
    );
  });

  test('deleting a branch removes only its matching web summary', () async {
    SharedPreferences.setMockInitialValues({});
    final repository = LocalStorageRepository(isWeb: true);
    await repository.initialize();
    final summary = (String chatId) => GroupChatSummary(
          groupId: 'group-1',
          chatId: chatId,
          summary: chatId,
          messageCount: 15,
          updatedAt: DateTime(2026, 8, 4),
        );
    await repository.saveGroupChatSummary(summary('branch-1'));
    await repository.saveGroupChatSummary(summary('branch-2'));

    await repository.deleteGroupChatBranch('group-1', 'branch-1');

    expect(await repository.getGroupChatSummary('group-1', 'branch-1'), isNull);
    expect(
      (await repository.getGroupChatSummary('group-1', 'branch-2'))?.summary,
      'branch-2',
    );
  });
}
