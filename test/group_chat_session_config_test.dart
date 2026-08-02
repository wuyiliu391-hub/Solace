import 'package:flutter_test/flutter_test.dart';
import 'package:solace/models/group_chat_session.dart';

void main() {
  final base = GroupChatSession(
    id: 'g1', name: '测试群', memberIds: ['local_user'],
    aiCharacterIds: ['c1', 'c2'], creatorId: 'local_user',
    createdAt: DateTime.now(),
  );

  test('引擎配置字段默认值对标 ST', () {
    expect(base.chatId, 'g1');
    expect(base.activationStrategy, GroupActivationStrategy.natural);
    expect(base.generationMode, GroupGenerationMode.swap);
    expect(base.allowSelfResponses, false);
    expect(base.disabledMemberIds, isEmpty);
    expect(base.autoModeDelay, 5);
    expect(base.autoModeEnabled, false);
    expect(base.joinPrefix, '');
    expect(base.joinSuffix, '');
  });

  test('toMap/fromMap 往返保留配置', () {
    final s = base.copyWith(
      chatId: 'b2',
      activationStrategy: GroupActivationStrategy.pooled,
      generationMode: GroupGenerationMode.append,
      allowSelfResponses: true,
      disabledMemberIds: ['c2'],
      autoModeDelay: 8,
      autoModeEnabled: true,
      joinPrefix: '【',
      joinSuffix: '】',
    );
    final restored = GroupChatSession.fromMap(s.toMap());
    expect(restored.chatId, 'b2');
    expect(restored.activationStrategy, GroupActivationStrategy.pooled);
    expect(restored.generationMode, GroupGenerationMode.append);
    expect(restored.allowSelfResponses, true);
    expect(restored.disabledMemberIds, ['c2']);
    expect(restored.autoModeDelay, 8);
    expect(restored.autoModeEnabled, true);
    expect(restored.joinPrefix, '【');
    expect(restored.joinSuffix, '】');
  });
}
