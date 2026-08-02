import 'package:flutter_test/flutter_test.dart';
import 'package:solace/blocs/group_chat/group_chat_speaker.dart';

void main() {
  test('锁定列表 = 强制 id 过滤禁言与不存在成员', () {
    final result = resolveForcedSpeakers(
      forcedIds: ['c1', 'c2', 'ghost'],
      memberIds: ['c1', 'c2', 'c3'],
      disabledMemberIds: ['c2'],
    );
    expect(result, ['c1']);
  });

  test('锁定空列表返回空', () {
    expect(
      resolveForcedSpeakers(
          forcedIds: [], memberIds: ['c1'], disabledMemberIds: []),
      isEmpty,
    );
  });

  test('全员禁言时锁定结果为空', () {
    expect(
      resolveForcedSpeakers(
          forcedIds: ['c1'], memberIds: ['c1'], disabledMemberIds: ['c1']),
      isEmpty,
    );
  });
}
