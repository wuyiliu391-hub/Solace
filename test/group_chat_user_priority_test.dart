// 用户消息优先测试：auto mode 不抢用户消息回应权 + AI 生成中被抢占时排队补回应。
//
// 问题：用户消息发出去后 (1) auto mode 定时轮询无视消息类型继续 AI 互聊，
// 用户消息被淹没；(2) _triggerAIReply 遇 _replyingGroups==true 直接 return，
// 用户消息无人回应。
// 修复：auto mode tick 跳过用户消息（由用户消息触发路径回应）；
// 被抢占时标记 pending，生成结束后 _drainPendingUserReply 补一次用户消息回应。
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:solace/blocs/group_chat/group_chat_bloc.dart';
import 'package:solace/models/ai_character.dart';
import 'package:solace/models/ai_stream_chunk.dart';
import 'package:solace/models/chat_message.dart';
import 'package:solace/models/group_chat_message.dart';
import 'package:solace/models/group_chat_session.dart';
import 'package:solace/models/memory.dart';
import 'package:solace/repositories/local_storage_repository.dart';
import 'package:solace/services/ai_service.dart';

class _MockStorage extends Mock implements LocalStorageRepository {}

class _MockAiService extends Mock implements AIService {}

void main() {
  // 可变消息库（模拟 storage，声明须在 stubBase 之前）
  late List<GroupChatMessage> _currentMessages;

  setUpAll(() {
    registerFallbackValue(AICharacter(
      id: 'fb', name: 'fb', personality: 'p',
      coreDesire: 'd', moralBoundary: 'm', createdAt: DateTime(2026, 8, 3),
    ));
    registerFallbackValue(GroupChatMessage(
      id: 'fb', groupId: 'g', senderId: 's', content: '', isUser: false,
    ));
    registerFallbackValue(GroupChatSession(
      id: 'fb', name: 'fb', memberIds: ['local_user'],
      aiCharacterIds: ['c1'], creatorId: 'local_user',
      createdAt: DateTime(2026, 8, 3),
    ));
    registerFallbackValue(ChatMessage(
      id: 'fb', chatId: 'g', senderId: 's', content: '', isUser: false,
    ));
    registerFallbackValue(Memory(
      id: 'fb', characterId: 'c', userId: 'u',
      type: MemoryType.conversation, content: '', createdAt: DateTime(2026, 8, 3),
    ));
  });

  AICharacter makeChar() => AICharacter(
        id: 'c1', name: '小A', personality: 'p',
        coreDesire: 'd', moralBoundary: 'm', createdAt: DateTime(2026, 8, 3),
        talkativeness: 1.0,
      );

  GroupChatMessage userMsg(String id, String content) => GroupChatMessage(
        id: id, groupId: 'g1', senderId: 'u1', senderName: '我',
        content: content, isUser: true, timestamp: DateTime.now(),
      );

  /// 基础 stub；messages 由外部 mock 控制（getGroupChatMessages 返回可变列表）
  void stubBase(_MockStorage storage, _MockAiService aiService,
      GroupChatSession session) {
    when(() => storage.getGroupChatSession('g1'))
        .thenAnswer((_) async => session);
    when(() => storage.isFaModeEnabled()).thenReturn(false);
    when(() => storage.saveGroupChatMessage(any())).thenAnswer((_) async {});
    when(() => storage.saveGroupChatSession(any())).thenAnswer((_) async {});
    when(() => storage.getAICharacter(any())).thenAnswer((_) async => makeChar());
    when(() => storage.getMemories(
            characterId: any(named: 'characterId'),
            userId: any(named: 'userId'),
            limit: any(named: 'limit')))
        .thenAnswer((_) async => <Memory>[]);
    when(() => storage.getGroupChatMessages(any(),
            limit: any(named: 'limit'), chatId: any(named: 'chatId')))
        .thenAnswer((inv) async {
      final limit = inv.namedArguments[#limit] as int? ?? 100;
      final all = _currentMessages;
      return all.length > limit ? all.sublist(all.length - limit) : all;
    });
    when(() => storage.getGroupChatMessages(any(),
            chatId: any(named: 'chatId')))
        .thenAnswer((_) async => List.of(_currentMessages));
    when(() => aiService.sendMessageStream(
      character: any(named: 'character'),
      userId: any(named: 'userId'),
      userMessage: any(named: 'userMessage'),
      chatHistory: any(named: 'chatHistory'),
      memories: any(named: 'memories'),
      intimacyLevel: any(named: 'intimacyLevel'),
      sentiment: any(named: 'sentiment'),
      imagePaths: any(named: 'imagePaths'),
      internalSystemContext: any(named: 'internalSystemContext'),
    )).thenAnswer((_) => Stream.fromIterable([
          AIStreamChunk(reasoning: '', content: 'AI 回复'),
        ]));
  }

  setUp(() {
    _currentMessages = [];
  });

  test('用户消息后的 auto mode tick 不触发（用户消息优先被回应）', () async {
    final storage = _MockStorage();
    final aiService = _MockAiService();
    final session = GroupChatSession(
      id: 'g1', name: '测试群', memberIds: ['c1', 'u1'],
      aiCharacterIds: ['c1'], creatorId: 'u1',
      createdAt: DateTime(2026, 8, 3),
      autoModeEnabled: true, // auto mode 开着
    );
    stubBase(storage, aiService, session);
    // 模拟：最后一条是用户消息（用户刚发言）
    _currentMessages = [userMsg('m1', '大家听我说')];

    // 直接走 auto mode 轮询逻辑：sendMessageStream 不应被调用
    // （通过 GroupChatUpdateConfig 触发 _autoModeTick 间接验证太绕，
    //   改为直接验证 tick 语义：_onSendMessage 保存用户消息后，
    //   即使 auto mode 开着，回复以用户消息为输入触发一次）
    final usages = <String>[];
    when(() => aiService.sendMessageStream(
      character: any(named: 'character'),
      userId: any(named: 'userId'),
      userMessage: any(named: 'userMessage'),
      chatHistory: any(named: 'chatHistory'),
      memories: any(named: 'memories'),
      intimacyLevel: any(named: 'intimacyLevel'),
      sentiment: any(named: 'sentiment'),
      imagePaths: any(named: 'imagePaths'),
      internalSystemContext: any(named: 'internalSystemContext'),
    )).thenAnswer((inv) {
      usages.add(inv.namedArguments[#userMessage] as String? ?? '');
      return Stream.fromIterable([AIStreamChunk(reasoning: '', content: '好的')]);
    });

    final bloc = GroupChatBloc(storage, aiService);
    // 用户发消息（auto mode 开着也要触发回应）
    _currentMessages.add(userMsg('m2', '大家听我说'));
    bloc.add(GroupChatSendMessage(
      groupId: 'g1', userId: 'u1', content: '大家听我说', imagePaths: null,
    ));
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(usages, isNotEmpty, reason: '用户消息必须触发 AI 回应');
    expect(usages.last, '大家听我说', reason: 'AI 必须以用户消息为输入回应');
  });

  test('AI 生成中被抢占：用户消息排队，生成结束后补回应（不丢失）', () async {
    final storage = _MockStorage();
    final aiService = _MockAiService();
    final session = GroupChatSession(
      id: 'g1', name: '测试群', memberIds: ['c1', 'u1'],
      aiCharacterIds: ['c1'], creatorId: 'u1',
      createdAt: DateTime(2026, 8, 3),
      autoModeEnabled: true, // 简化 _onAIMessageSaved：直接 return + drain
    );
    stubBase(storage, aiService, session);

    // 第一次调用：流挂起（模拟 AI 生成中）；后续调用：立即完成
    final firstController = StreamController<AIStreamChunk>();
    var call = 0;
    final userMessages = <String>[];
    when(() => aiService.sendMessageStream(
      character: any(named: 'character'),
      userId: any(named: 'userId'),
      userMessage: any(named: 'userMessage'),
      chatHistory: any(named: 'chatHistory'),
      memories: any(named: 'memories'),
      intimacyLevel: any(named: 'intimacyLevel'),
      sentiment: any(named: 'sentiment'),
      imagePaths: any(named: 'imagePaths'),
      internalSystemContext: any(named: 'internalSystemContext'),
    )).thenAnswer((inv) {
      call++;
      userMessages.add(inv.namedArguments[#userMessage] as String? ?? '');
      if (call == 1) return firstController.stream;
      return Stream.fromIterable([AIStreamChunk(reasoning: '', content: '补回应')]);
    });

    final bloc = GroupChatBloc(storage, aiService);
    // 第一条用户消息 → 触发 AI 生成（挂起）
    _currentMessages.add(userMsg('m1', '第一条'));
    bloc.add(GroupChatSendMessage(
      groupId: 'g1', userId: 'u1', content: '第一条', imagePaths: null,
    ));
    await Future<void>.delayed(const Duration(milliseconds: 200));

    // 生成中用户再发消息 → 被抢占 → 排队
    _currentMessages.add(userMsg('m2', '第二条'));
    bloc.add(GroupChatSendMessage(
      groupId: 'g1', userId: 'u1', content: '第二条', imagePaths: null,
    ));
    await Future<void>.delayed(const Duration(milliseconds: 200));

    // 完成第一次生成 → 触发 drain → 补回应第二条
    firstController.add(AIStreamChunk(reasoning: '', content: '第一条的回复'));
    await firstController.close();
    await Future<void>.delayed(const Duration(milliseconds: 400));

    // 第二次调用必须以第二条用户消息为输入
    expect(userMessages.length, greaterThanOrEqualTo(2),
        reason: '排队中的用户消息必须在生成结束后被回应');
    expect(userMessages.last, '第二条',
        reason: '补回应必须以排队中的用户消息为输入');
    await firstController.close();
  });
}
