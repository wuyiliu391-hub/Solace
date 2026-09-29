import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/blocs/group_chat/group_chat_speaker.dart';
import 'package:solace/models/group_chat_session.dart';

void main() {
  test('引擎组合：NATURAL + allowSelfResponses 下多人可连发', () {
    final speakers = selectSpeakers(
      strategy: GroupActivationStrategy.natural,
      ctx: SpeakerContext(
        memberIds: ['c1', 'c2'],
        disabledMemberIds: [],
        historySpeakerIds: [],
        lastMessageSpeakerId: 'c1',
        talkativeness: {'c1': 0.5, 'c2': 0.5},
        allowSelfResponses: true,
        userInput: '',
        isUserInput: false,
        forceCharacterId: null,
        random: Random(1),
      ),
    );
    expect(speakers, isNotEmpty);
  });

  test('引擎组合：禁言成员永远不发言', () {
    for (final s in GroupActivationStrategy.values) {
      final speakers = selectSpeakers(
        strategy: s,
        ctx: SpeakerContext(
          memberIds: ['c1', 'c2'],
          disabledMemberIds: ['c2'],
          historySpeakerIds: [],
          lastMessageSpeakerId: null,
          talkativeness: {'c1': 1.0, 'c2': 1.0},
          allowSelfResponses: false,
          userInput: 'c2',
          isUserInput: true,
          forceCharacterId: 'c2',
          memberNames: {'c1': '甲', 'c2': '乙'},
          random: Random(1),
        ),
      );
      expect(speakers.contains('c2'), false);
    }
  });
}
