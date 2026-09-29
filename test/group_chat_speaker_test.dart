import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/blocs/group_chat/group_chat_speaker.dart';
import 'package:solace/models/group_chat_message.dart';
import 'package:solace/models/group_chat_session.dart';

GroupChatMessage _ai(String id, String characterId, {bool system = false}) {
  return GroupChatMessage(
    id: id,
    groupId: 'g1',
    senderId: 'ai_$characterId',
    senderName: characterId,
    content: 'hi',
    isUser: false,
    isSystem: system,
  );
}

GroupChatMessage _user(String id) {
  return GroupChatMessage(
    id: id,
    groupId: 'g1',
    senderId: 'local_user',
    senderName: '我',
    content: 'hello',
    isUser: true,
  );
}

void main() {
  final members = ['c1', 'c2', 'c3'];
  final talk = {'c1': 1.0, 'c2': 0.0, 'c3': 0.5};
  final fixedRandom = Random(42);

  test('LIST 按成员顺序全员激活', () {
    final result = selectSpeakers(
      strategy: GroupActivationStrategy.list,
      ctx: SpeakerContext(
        memberIds: members,
        disabledMemberIds: [],
        historySpeakerIds: [],
        lastMessageSpeakerId: 'c3',
        talkativeness: talk,
        allowSelfResponses: false,
        userInput: '',
        isUserInput: true,
        forceCharacterId: null,
        random: fixedRandom,
      ),
    );
    expect(result, ['c1', 'c2', 'c3']);
  });

  test('LIST 排除禁言成员', () {
    final result = selectSpeakers(
      strategy: GroupActivationStrategy.list,
      ctx: SpeakerContext(
        memberIds: members,
        disabledMemberIds: ['c2'],
        historySpeakerIds: [],
        lastMessageSpeakerId: null,
        talkativeness: talk,
        allowSelfResponses: false,
        userInput: '',
        isUserInput: true,
        forceCharacterId: null,
        random: fixedRandom,
      ),
    );
    expect(result, ['c1', 'c3']);
  });

  test('POOLED 优先选用户消息后未发言者', () {
    final result = selectSpeakers(
      strategy: GroupActivationStrategy.pooled,
      ctx: SpeakerContext(
        memberIds: members,
        disabledMemberIds: [],
        historySpeakerIds: ['c1', 'c2'],
        lastMessageSpeakerId: 'c2',
        talkativeness: talk,
        allowSelfResponses: false,
        userInput: '大家好',
        isUserInput: true,
        forceCharacterId: null,
        random: fixedRandom,
      ),
    );
    // c1、c2 已发言，只剩 c3
    expect(result, ['c3']);
  });

  test('POOLED 全部说过时排除最后发言者', () {
    final result = selectSpeakers(
      strategy: GroupActivationStrategy.pooled,
      ctx: SpeakerContext(
        memberIds: members,
        disabledMemberIds: [],
        historySpeakerIds: ['c1', 'c2', 'c3'],
        lastMessageSpeakerId: 'c3',
        talkativeness: talk,
        allowSelfResponses: false,
        userInput: '继续聊',
        isUserInput: true,
        forceCharacterId: null,
        random: fixedRandom,
      ),
    );
    expect(result.length, 1);
    expect(result.first, isNot('c3'));
  });

  test('NATURAL 提及检测：输入含角色名则激活该角色', () {
    final result = selectSpeakers(
      strategy: GroupActivationStrategy.natural,
      ctx: SpeakerContext(
        memberIds: members,
        disabledMemberIds: [],
        historySpeakerIds: [],
        lastMessageSpeakerId: null,
        talkativeness: {'c1': 0.0, 'c2': 0.0, 'c3': 0.0},
        allowSelfResponses: false,
        userInput: '我觉得小美说得对',
        isUserInput: true,
        forceCharacterId: null,
        random: fixedRandom,
        memberNames: {'c1': '小美', 'c2': '阿强', 'c3': '小芳'},
      ),
    );
    expect(result, ['c1']);
  });

  test('NATURAL 无提及无高话痨时随机兜底（talkativeness>0 池）', () {
    final result = selectSpeakers(
      strategy: GroupActivationStrategy.natural,
      ctx: SpeakerContext(
        memberIds: members,
        disabledMemberIds: [],
        historySpeakerIds: [],
        lastMessageSpeakerId: 'c2',
        talkativeness: {'c1': 0.0, 'c2': 0.0, 'c3': 0.0},
        allowSelfResponses: false,
        userInput: '',
        isUserInput: false,
        forceCharacterId: null,
        random: fixedRandom,
      ),
    );
    expect(result.length, 1);
    expect(result.first, isNot('c2')); // 排除上一条发言者
  });

  test('NATURAL allowSelfResponses 允许连续发言', () {
    final result = selectSpeakers(
      strategy: GroupActivationStrategy.natural,
      ctx: SpeakerContext(
        memberIds: ['c1'],
        disabledMemberIds: [],
        historySpeakerIds: [],
        lastMessageSpeakerId: 'c1',
        talkativeness: {'c1': 1.0},
        allowSelfResponses: true,
        userInput: '',
        isUserInput: false,
        forceCharacterId: null,
        random: fixedRandom,
      ),
    );
    expect(result, ['c1']);
  });

  test('MANUAL 指定角色', () {
    final result = selectSpeakers(
      strategy: GroupActivationStrategy.manual,
      ctx: SpeakerContext(
        memberIds: members,
        disabledMemberIds: [],
        historySpeakerIds: [],
        lastMessageSpeakerId: null,
        talkativeness: talk,
        allowSelfResponses: false,
        userInput: '',
        isUserInput: false,
        forceCharacterId: 'c2',
        random: fixedRandom,
      ),
    );
    expect(result, ['c2']);
  });

  test('speakersSinceLastUser 从末尾回溯，遇到用户消息停止（ST spokenSinceUser）', () {
    final history = [
      _ai('m1', 'c1'),
      _ai('m2', 'c2'),
      _user('m3'),
      _ai('m4', 'c3'),
      _ai('m5', 'c2'),
    ];
    // 旧实现从前往后扫会返回 [c1, c2]；ST 语义应为用户消息之后的 [c2, c3]
    expect(speakersSinceLastUser(history), ['c2', 'c3']);
  });

  test('speakersSinceLastUser 全部都是 AI 时返回全部', () {
    final history = [
      _user('m1'),
      _ai('m2', 'c1'),
      _ai('m3', 'c2'),
    ];
    expect(speakersSinceLastUser(history), ['c2', 'c1']);
  });

  test('speakersSinceLastUser 跳过系统消息并跨过它继续回溯', () {
    final history = [
      _user('m1'),
      _ai('m2', 'c1'),
      _ai('m3', 'c2', system: true),
      _ai('m4', 'c3'),
    ];
    expect(speakersSinceLastUser(history), ['c3', 'c1']);
  });
}
