// 群聊思考型模型流式回归测试。
//
// 问题：群聊 _generateOneReply 原来只按 chunk.content 是否非空决定 emit
// GroupChatStreaming。思考型模型（reasoning_content 或 content 内嵌 <think>）
// 在思考阶段 content 为空、reasoning 非空 → 一直不 emit → 表现为
// 「AI 无气泡但背后已在准备回复，思考完才一次性蹦出正文」。
// 修复：思考阶段（reasoning 非空）也 emit 流式状态，UI 可显示「思考中…」。
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
  setUpAll(() {
    registerFallbackValue(AICharacter(
      id: 'fallback',
      name: 'fb',
      personality: 'p',
      coreDesire: 'd',
      moralBoundary: 'm',
      createdAt: DateTime(2026, 8, 3),
    ));
    registerFallbackValue(GroupChatMessage(
      id: 'fb',
      groupId: 'g',
      senderId: 's',
      content: '',
      isUser: false,
    ));
    registerFallbackValue(GroupChatSession(
      id: 'fb',
      name: 'fb',
      memberIds: ['local_user'],
      aiCharacterIds: ['c1'],
      creatorId: 'local_user',
      createdAt: DateTime(2026, 8, 3),
    ));
    registerFallbackValue(ChatMessage(
      id: 'fb',
      chatId: 'g',
      senderId: 's',
      content: '',
      isUser: false,
    ));
    registerFallbackValue(Memory(
      id: 'fb',
      characterId: 'c',
      userId: 'u',
      type: MemoryType.conversation,
      content: '',
      createdAt: DateTime(2026, 8, 3),
    ));
  });

  void stubCommon(_MockStorage storage, _MockAiService aiService,
      GroupChatSession session, GroupChatMessage userMsg, AICharacter char,
      {Stream<AIStreamChunk> Function()? streamFactory}) {
    when(() => storage.getGroupChatSession('g1')).thenAnswer((_) async => session);
    when(() => storage.isFaModeEnabled()).thenReturn(false);
    when(() => storage.saveGroupChatMessage(any())).thenAnswer((_) async {});
    when(() => storage.saveGroupChatSession(any())).thenAnswer((_) async {});
    when(() => storage.getGroupChatMessages(any(), chatId: any(named: 'chatId')))
        .thenAnswer((_) async => [userMsg]);
    when(() => storage.getGroupChatMessages(any(),
            limit: any(named: 'limit'), chatId: any(named: 'chatId')))
        .thenAnswer((_) async => [userMsg]);
    when(() => storage.getAICharacter(any())).thenAnswer((_) async => char);
    when(() => storage.getMemories(
            characterId: any(named: 'characterId'),
            userId: any(named: 'userId'),
            limit: any(named: 'limit')))
        .thenAnswer((_) async => <Memory>[]);
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
    )).thenAnswer((_) => streamFactory?.call() ?? Stream<AIStreamChunk>.empty());
  }

  test('思考型模型：reasoning-only chunk 也 emit GroupChatStreaming（无气泡修复）',
      () async {
    final storage = _MockStorage();
    final aiService = _MockAiService();
    final session = GroupChatSession(
      id: 'g1',
      name: '测试群',
      memberIds: ['c1', 'u1'],
      aiCharacterIds: ['c1'],
      creatorId: 'u1',
      createdAt: DateTime(2026, 8, 3),
    );
    final userMsg = GroupChatMessage(
      id: 'm1',
      groupId: 'g1',
      senderId: 'u1',
      senderName: '我',
      content: 'hi',
      isUser: true,
    );
    final char = AICharacter(
      id: 'c1',
      name: '小美',
      personality: 'p',
      coreDesire: 'd',
      moralBoundary: 'm',
      createdAt: DateTime(2026, 8, 3),
    );
    // 先产出思考（content 空、reasoning 非空），再产出正文
    stubCommon(storage, aiService, session, userMsg, char, streamFactory: () {
      return Stream.fromIterable([
        AIStreamChunk(reasoning: '她在回忆上次聊天的约定…', content: ''),
        AIStreamChunk(reasoning: '她在回忆上次聊天的约定…', content: '记得的！'),
      ]);
    });

    final bloc = GroupChatBloc(storage, aiService);
    final streamed = <GroupChatStreaming>[];
    final sub = bloc.stream.listen((s) {
      if (s is GroupChatStreaming) streamed.add(s);
    });

    bloc.add(GroupChatSendMessage(
      groupId: 'g1',
      userId: 'u1',
      content: 'hi',
      imagePaths: null,
    ));
    await Future<void>.delayed(const Duration(milliseconds: 200));

    // 关键：思考阶段必须 emit 出「正文为空但 reasoning 非空」的流式状态，
    // UI 才能据此显示「思考中…」，而不是干等到思考完才蹦出正文
    expect(
      streamed.any((s) => s.streamingText.isEmpty && s.reasoning.isNotEmpty),
      isTrue,
      reason: '思考阶段必须 emit 流式状态（reasoning-only chunk）',
    );
    // 正文阶段正常流式
    expect(
      streamed.any((s) => s.streamingText.contains('记得的')),
      isTrue,
      reason: '正文 chunk 应正常流式显示',
    );

    await sub.cancel();
  });

  test('普通模型：无 reasoning 时按正文正常流式（不回归）', () async {
    final storage = _MockStorage();
    final aiService = _MockAiService();
    final session = GroupChatSession(
      id: 'g1',
      name: '测试群',
      memberIds: ['c1', 'u1'],
      aiCharacterIds: ['c1'],
      creatorId: 'u1',
      createdAt: DateTime(2026, 8, 3),
    );
    final userMsg = GroupChatMessage(
      id: 'm1',
      groupId: 'g1',
      senderId: 'u1',
      senderName: '我',
      content: 'hi',
      isUser: true,
    );
    final char = AICharacter(
      id: 'c1',
      name: '小美',
      personality: 'p',
      coreDesire: 'd',
      moralBoundary: 'm',
      createdAt: DateTime(2026, 8, 3),
    );
    stubCommon(storage, aiService, session, userMsg, char, streamFactory: () {
      return Stream.fromIterable([
        AIStreamChunk(reasoning: '', content: '你'),
        AIStreamChunk(reasoning: '', content: '你好呀'),
      ]);
    });

    final bloc = GroupChatBloc(storage, aiService);
    final streamed = <GroupChatStreaming>[];
    final sub = bloc.stream.listen((s) {
      if (s is GroupChatStreaming) streamed.add(s);
    });

    bloc.add(GroupChatSendMessage(
      groupId: 'g1',
      userId: 'u1',
      content: 'hi',
      imagePaths: null,
    ));
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(streamed.isNotEmpty, isTrue);
    expect(streamed.last.streamingText, contains('你好呀'));

    await sub.cancel();
  });
}
