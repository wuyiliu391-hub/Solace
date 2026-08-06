import 'package:flutter_test/flutter_test.dart';
import 'package:solace/models/group_chat_branch.dart';
import 'package:solace/models/group_chat_message.dart';

void main() {
  test('分支模型 toMap/fromMap 往返', () {
    final b = GroupChatBranch(
      branchId: 'b1',
      groupId: 'g1',
      name: '深夜话题',
      createdAt: DateTime(2026, 8, 2),
    );
    final restored = GroupChatBranch.fromMap(b.toMap());
    expect(restored.branchId, 'b1');
    expect(restored.groupId, 'g1');
    expect(restored.name, '深夜话题');
    expect(restored.createdAt, DateTime(2026, 8, 2));
  });

  test('消息模型 chatId 默认与往返', () {
    final m = GroupChatMessage(
      id: 'm1',
      groupId: 'g1',
      senderId: 'ai_c1',
      senderName: 'A',
      content: 'hi',
      isUser: false,
    );
    expect(m.chatId, '');
    final restored = GroupChatMessage.fromMap(m.toMap());
    expect(restored.chatId, '');
    final m2 = m.copyWith(chatId: 'b2');
    expect(GroupChatMessage.fromMap(m2.toMap()).chatId, 'b2');
  });

  test('消息候选和父节点字段可往返', () {
    final m = GroupChatMessage(
      id: 'm1',
      groupId: 'g1',
      senderId: 'ai_c1',
      content: '当前',
      swipeHistory: const ['旧', '当前'],
      swipeIndex: 1,
      parentMessageId: 'parent',
    );
    final restored = GroupChatMessage.fromMap(m.toMap());
    expect(restored.swipeHistory, ['旧', '当前']);
    expect(restored.swipeIndex, 1);
    expect(restored.parentMessageId, 'parent');
  });

  test('消息树分支保存父分支和分叉节点', () {
    final b = GroupChatBranch(
      branchId: 'b2',
      groupId: 'g1',
      name: '分支',
      createdAt: DateTime(2026),
      parentBranchId: 'b1',
      forkMessageId: 'm3',
      checkpointMessageId: 'm3',
    );
    final restored = GroupChatBranch.fromMap(b.toMap());
    expect(restored.parentBranchId, 'b1');
    expect(restored.forkMessageId, 'm3');
    expect(restored.checkpointMessageId, 'm3');
  });

  test('Swipe 候选去重并保留当前候选索引', () {
    final message = GroupChatMessage(
      id: 'm1',
      groupId: 'g1',
      chatId: 'g1',
      senderId: 'ai_c1',
      content: '第二版',
      swipeHistory: const ['第一版', '第二版'],
      swipeIndex: 1,
      metadata: const {
        'generationId': 'gen-1',
        'finishReason': 'stop',
        'usage': {'prompt_tokens': 20, 'completion_tokens': 8},
      },
    );
    final restored = GroupChatMessage.fromJson(message.toJson());
    expect(restored.content, '第二版');
    expect(restored.swipeHistory, ['第一版', '第二版']);
    expect(restored.swipeIndex, 1);
    expect(restored.metadata?['generationId'], 'gen-1');
    expect(restored.metadata?['usage']['completion_tokens'], 8);
  });
}
