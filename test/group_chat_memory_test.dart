// 群聊记忆互通测试。
//
// 1. buildGroupSharedContext：全员设定压缩 + 成员与用户记忆（全共享）
// 2. AI 回复后沉淀社交记忆（互相干涉的数据源）
// 3. 群聊 memories 聚合全部成员（APPEND 模式的 members.first bug 回归防护）
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:solace/blocs/group_chat/group_chat_bloc.dart';
import 'package:solace/models/ai_character.dart';
import 'package:solace/models/ai_stream_chunk.dart';
import 'package:solace/models/chat_message.dart';
import 'package:solace/models/group_chat_message.dart';
import 'package:solace/models/group_chat_session.dart';
import 'package:solace/models/group_chat_summary.dart';
import 'package:solace/models/memory.dart';
import 'package:solace/repositories/local_storage_repository.dart';
import 'package:solace/services/ai_service.dart';
import 'package:solace/services/memory_engine.dart';

class _MockStorage extends Mock implements LocalStorageRepository {}

class _MockAiService extends Mock implements AIService {}

class _MockMemoryEngine extends Mock implements MemoryEngine {}

AICharacter _char(String id, String name) => AICharacter(
      id: id,
      name: name,
      personality: '性格${name}：热情开朗',
      coreDesire: '心愿',
      moralBoundary: '原则',
      backgroundStory: '背景故事${name}',
      createdAt: DateTime(2026, 8, 3),
      talkativeness: 0.9,
    );

void main() {
  setUpAll(() {
    registerFallbackValue(_char('fb', 'fb'));
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
    registerFallbackValue(GroupChatSummary(
      groupId: 'g',
      chatId: 'chat',
      summary: '',
      messageCount: 0,
      updatedAt: DateTime(2026, 8, 3),
    ));
  });

  test('buildGroupSharedContext 输出全员档案 + 成员与用户记忆段落', () async {
    final storage = _MockStorage();
    final engine = MemoryEngine(storage);
    when(() =>
        storage.getMemories(
            characterId: any(named: 'characterId'),
            userId: any(named: 'userId'),
            limit: any(named: 'limit'))).thenAnswer((inv) async => [
          Memory(
            id: 'm1',
            characterId: inv.namedArguments[#characterId] as String,
            userId: 'u',
            type: MemoryType.conversation,
            content: '${inv.namedArguments[#characterId]}和用户一起去过海边',
            createdAt: DateTime(2026, 8, 3),
          ),
        ]);

    final out = await engine.buildGroupSharedContext(
      self: _char('c1', '小A'),
      members: [_char('c2', '小B')],
      userId: 'u',
      groupId: 'g1',
    );

    expect(out, contains('群成员共享信息'));
    expect(out, contains('── 成员：小B ──'));
    expect(out, contains('性格：性格小B'));
    expect(out, contains('背景：背景故事小B'));
    expect(out, contains('小B与用户相关记忆'));
    expect(out, contains('c2和用户一起去过海边'));
    // 身份隔离：自己是说话人，不能注入自己的档案
    expect(out, isNot(contains('── 成员：小A ──')));
  });

  void stubCommon(_MockStorage storage, _MockAiService aiService,
      GroupChatSession session, GroupChatMessage userMsg) {
    when(() => storage.getGroupChatSession('g1'))
        .thenAnswer((_) async => session);
    when(() => storage.isFaModeEnabled()).thenReturn(false);
    when(() => storage.saveGroupChatMessage(any())).thenAnswer((_) async {});
    when(() => storage.saveGroupChatSession(any())).thenAnswer((_) async {});
    when(() =>
            storage.getGroupChatMessages(any(), chatId: any(named: 'chatId')))
        .thenAnswer((_) async => [userMsg]);
    when(() => storage.getGroupChatMessages(any(),
        limit: any(named: 'limit'),
        chatId: any(named: 'chatId'))).thenAnswer((_) async => [userMsg]);
    when(() => storage.getMemories(
        characterId: any(named: 'characterId'),
        userId: any(named: 'userId'),
        limit: any(named: 'limit'))).thenAnswer((_) async => <Memory>[]);
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
          AIStreamChunk(reasoning: '', content: '你好呀'),
        ]));
  }

  test('群聊 AI 回复后沉淀社交记忆（互相干涉数据源）', () async {
    final storage = _MockStorage();
    final aiService = _MockAiService();
    final memEngine = _MockMemoryEngine();
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
    stubCommon(storage, aiService, session, userMsg);
    when(() => storage.getAICharacter('c1'))
        .thenAnswer((_) async => _char('c1', '小A'));
    when(() => memEngine.buildGroupSharedContext(
          self: any(named: 'self'),
          members: any(named: 'members'),
          userId: any(named: 'userId'),
          groupId: any(named: 'groupId'),
          chatId: any(named: 'chatId'),
        )).thenAnswer((_) async => '');
    when(() => memEngine.saveSocialMemory(
          characterId: any(named: 'characterId'),
          targetCharacterId: any(named: 'targetCharacterId'),
          interactionType: any(named: 'interactionType'),
          content: any(named: 'content'),
          emotionTag: any(named: 'emotionTag'),
          importance: any(named: 'importance'),
          keywords: any(named: 'keywords'),
        )).thenAnswer((_) async {});

    final bloc = GroupChatBloc(storage, aiService, memoryEngine: memEngine);
    bloc.add(GroupChatSendMessage(
      groupId: 'g1',
      userId: 'u1',
      content: 'hi',
      imagePaths: null,
    ));
    await Future<void>.delayed(const Duration(milliseconds: 400));

    verify(() => memEngine.saveSocialMemory(
          characterId: 'c1',
          targetCharacterId: 'g1',
          interactionType: 'group_chat',
          content: any(named: 'content'),
          emotionTag: any(named: 'emotionTag'),
          importance: any(named: 'importance'),
          keywords: any(named: 'keywords'),
        )).called(1);
  });

  test('群聊记忆全共享：memories 聚合全部成员（APPEND members.first 回归防护）', () async {
    final storage = _MockStorage();
    final aiService = _MockAiService();
    final memEngine = _MockMemoryEngine();
    final session = GroupChatSession(
      id: 'g1',
      name: '测试群',
      memberIds: ['c1', 'c2', 'u1'],
      aiCharacterIds: ['c1', 'c2'],
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
    stubCommon(storage, aiService, session, userMsg);
    when(() => storage.getAICharacter('c1'))
        .thenAnswer((_) async => _char('c1', '小A'));
    when(() => storage.getAICharacter('c2'))
        .thenAnswer((_) async => _char('c2', '小B'));
    when(() =>
        storage.getMemories(
            characterId: any(named: 'characterId'),
            userId: any(named: 'userId'),
            limit: any(named: 'limit'))).thenAnswer((inv) async => [
          Memory(
            id: 'mem_${inv.namedArguments[#characterId]}',
            characterId: inv.namedArguments[#characterId] as String,
            userId: 'u1',
            type: MemoryType.conversation,
            content: '${inv.namedArguments[#characterId]}的秘密记忆',
            createdAt: DateTime(2026, 8, 3),
          ),
        ]);
    when(() => memEngine.buildGroupSharedContext(
          self: any(named: 'self'),
          members: any(named: 'members'),
          userId: any(named: 'userId'),
          groupId: any(named: 'groupId'),
          chatId: any(named: 'chatId'),
        )).thenAnswer((_) async => '');
    when(() => memEngine.saveSocialMemory(
          characterId: any(named: 'characterId'),
          targetCharacterId: any(named: 'targetCharacterId'),
          interactionType: any(named: 'interactionType'),
          content: any(named: 'content'),
          emotionTag: any(named: 'emotionTag'),
          importance: any(named: 'importance'),
          keywords: any(named: 'keywords'),
        )).thenAnswer((_) async {});

    List<Memory>? capturedMemories;
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
      capturedMemories = inv.namedArguments[#memories] as List<Memory>?;
      return Stream.fromIterable([
        AIStreamChunk(reasoning: '', content: '你好呀'),
      ]);
    });

    final bloc = GroupChatBloc(storage, aiService, memoryEngine: memEngine);
    bloc.add(GroupChatSendMessage(
      groupId: 'g1',
      userId: 'u1',
      content: 'hi',
      imagePaths: null,
    ));
    await Future<void>.delayed(const Duration(milliseconds: 400));

    expect(capturedMemories, isNotNull,
        reason: 'sendMessageStream 应收到聚合后的 memories');
    final contents = capturedMemories!.map((m) => m.content).toList();
    expect(contents, contains('c1的秘密记忆'));
    expect(contents, contains('c2的秘密记忆'));
  });

  test('APPEND 使用消息 chatId 且保存后刷新对应分支总结', () async {
    final storage = _MockStorage();
    final aiService = _MockAiService();
    final memEngine = _MockMemoryEngine();
    final session = GroupChatSession(
      id: 'g1',
      name: '测试群',
      chatId: 'branch-2',
      memberIds: ['c1', 'u1'],
      aiCharacterIds: ['c1'],
      creatorId: 'u1',
      generationMode: GroupGenerationMode.append,
      createdAt: DateTime(2026, 8, 3),
    );
    final messages = List.generate(
      16,
      (i) => GroupChatMessage(
        id: 'm$i',
        groupId: 'g1',
        chatId: 'branch-2',
        senderId: 'u1',
        senderName: '我',
        content: '消息$i',
        isUser: true,
      ),
    );
    when(() => storage.getGroupChatSession('g1'))
        .thenAnswer((_) async => session);
    when(() => storage.isFaModeEnabled()).thenReturn(false);
    when(() => storage.getAICharacter('c1'))
        .thenAnswer((_) async => _char('c1', '小A'));
    when(() => storage.getGroupChatMessages('g1',
        limit: any(named: 'limit'),
        chatId: 'branch-2')).thenAnswer((_) async => messages);
    when(() => storage.getGroupChatMessages('g1', chatId: 'branch-2'))
        .thenAnswer((_) async => messages);
    when(() => storage.getGroupChatMessages('g1', chatId: any(named: 'chatId')))
        .thenAnswer((_) async => messages);
    when(() => storage.getMemories(
        characterId: any(named: 'characterId'),
        userId: any(named: 'userId'),
        limit: any(named: 'limit'))).thenAnswer((_) async => <Memory>[]);
    when(() => storage.getGroupChatSummary('g1', 'branch-2'))
        .thenAnswer((_) async => null);
    when(() => storage.saveGroupChatMessage(any())).thenAnswer((_) async {});
    when(() => storage.saveGroupChatSummary(any())).thenAnswer((_) async {});
    when(() => storage.saveGroupChatSession(any())).thenAnswer((_) async {});
    when(() => storage.getGroupChatSession('g1'))
        .thenAnswer((_) async => session);
    when(() => aiService.generateGroupRollingSummary(
          existingSummary: any(named: 'existingSummary'),
          newMessages: any(named: 'newMessages'),
        )).thenAnswer((_) async => null);
    when(() => memEngine.buildGroupSharedContext(
          self: any(named: 'self'),
          members: any(named: 'members'),
          userId: any(named: 'userId'),
          groupId: any(named: 'groupId'),
          chatId: any(named: 'chatId'),
        )).thenAnswer((_) async => '');
    when(() => memEngine.saveSocialMemory(
          characterId: any(named: 'characterId'),
          targetCharacterId: any(named: 'targetCharacterId'),
          interactionType: any(named: 'interactionType'),
          content: any(named: 'content'),
          emotionTag: any(named: 'emotionTag'),
          importance: any(named: 'importance'),
          keywords: any(named: 'keywords'),
        )).thenAnswer((_) async {});
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
            ))
        .thenAnswer((_) =>
            Stream.fromIterable([AIStreamChunk(reasoning: '', content: '回复')]));

    final bloc = GroupChatBloc(storage, aiService, memoryEngine: memEngine);
    bloc.add(GroupChatSendMessage(groupId: 'g1', userId: 'u1', content: 'hi'));
    await Future<void>.delayed(const Duration(milliseconds: 400));

    final verification = verify(() => aiService.sendMessageStream(
          character: any(named: 'character'),
          userId: any(named: 'userId'),
          userMessage: any(named: 'userMessage'),
          chatHistory: captureAny(named: 'chatHistory'),
          memories: any(named: 'memories'),
          intimacyLevel: any(named: 'intimacyLevel'),
          sentiment: any(named: 'sentiment'),
          imagePaths: any(named: 'imagePaths'),
          internalSystemContext: any(named: 'internalSystemContext'),
        ));
    final captured = verification.captured.first as List<ChatMessage>;
    expect(captured, isNotEmpty);
    expect(captured.every((message) => message.chatId == 'branch-2'), isTrue);
    verify(() => aiService.generateGroupRollingSummary(
          existingSummary: any(named: 'existingSummary'),
          newMessages: any(named: 'newMessages'),
        )).called(1);
    verifyNever(() => storage.saveGroupChatSummary(any()));
  });
}
