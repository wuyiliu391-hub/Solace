import 'package:flutter_test/flutter_test.dart';
import 'package:solace/models/group_chat_branch.dart';
import 'package:solace/models/group_chat_message.dart';

void main() {
  test('分支模型 toMap/fromMap 往返', () {
    final b = GroupChatBranch(
      branchId: 'b1', groupId: 'g1', name: '深夜话题',
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
      id: 'm1', groupId: 'g1', senderId: 'ai_c1',
      senderName: 'A', content: 'hi', isUser: false,
    );
    expect(m.chatId, '');
    final restored = GroupChatMessage.fromMap(m.toMap());
    expect(restored.chatId, '');
    final m2 = m.copyWith(chatId: 'b2');
    expect(GroupChatMessage.fromMap(m2.toMap()).chatId, 'b2');
  });
}
