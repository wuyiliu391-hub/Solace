import 'package:flutter_test/flutter_test.dart';
import 'package:solace/models/group_chat_lorebook_entry.dart';
import 'package:solace/models/group_chat_message.dart';
import 'package:solace/services/group_chat_prompt_pipeline.dart';

void main() {
  const pipeline = GroupChatPromptPipeline();

  test('lorebook activates by keyword and respects priority', () {
    final entries = [
      const GroupChatLorebookEntry(
          id: 'low',
          groupId: 'g1',
          content: '低优先级',
          keywords: ['咖啡'],
          priority: 1),
      const GroupChatLorebookEntry(
          id: 'high',
          groupId: 'g1',
          content: '高优先级',
          keywords: ['咖啡'],
          priority: 10),
    ];
    final result = pipeline.build(
      segments: const [],
      lorebook: entries,
      history: [
        GroupChatMessage(
            id: 'm1', senderId: 'u', isUser: true, content: '去喝咖啡'),
      ],
    );
    expect(result.indexOf('高优先级'), lessThan(result.indexOf('低优先级')));
  });

  test('history is trimmed from the oldest side by token budget', () {
    final history = List.generate(
      20,
      (i) => GroupChatMessage(id: '$i', senderId: 'u', content: '消息 $i ' * 20),
    );
    final trimmed = pipeline.trimHistory(history, tokenBudget: 30);
    expect(trimmed, isNotEmpty);
    expect(trimmed.last.id, '19');
    expect(trimmed.length, lessThan(history.length));
  });

  test('history trimming keeps the newest complete messages within budget', () {
    const pipeline = GroupChatPromptPipeline();
    final messages = List.generate(
      8,
      (index) => GroupChatMessage(
        id: 'm$index',
        senderName: '成员',
        senderId: 'c$index',
        content: '消息 $index ' * 8,
      ),
    );
    final trimmed = pipeline.trimHistory(messages, tokenBudget: 20);
    expect(trimmed, isNotEmpty);
    expect(trimmed.last.content, contains('消息 7'));
    expect(trimmed, orderedEquals(trimmed.toList()));
  });

  test('disabled lorebook entries are excluded from generated context', () {
    const pipeline = GroupChatPromptPipeline();
    final context = pipeline.build(
      segments: const [
        GroupPromptSegment(id: 'base', content: '基础设定', priority: 10),
      ],
      lorebook: const [
        GroupChatLorebookEntry(
          id: 'disabled',
          groupId: 'g1',
          content: '不应出现',
          keywords: ['秘密'],
          enabled: false,
        ),
      ],
      history: [
        GroupChatMessage(
          id: 'm1',
          senderId: 'u1',
          senderName: '用户',
          content: '秘密',
        ),
      ],
    );
    expect(context, contains('基础设定'));
    expect(context, isNot(contains('不应出现')));
  });
}
