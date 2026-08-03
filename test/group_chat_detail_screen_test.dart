import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:solace/blocs/group_chat/group_chat_bloc.dart';
import 'package:solace/models/ai_character.dart';
import 'package:solace/models/ai_stream_chunk.dart';
import 'package:solace/models/chat_message.dart';
import 'package:solace/models/group_chat_branch.dart';
import 'package:solace/models/group_chat_message.dart';
import 'package:solace/models/group_chat_session.dart';
import 'package:solace/models/memory.dart';
import 'package:solace/repositories/local_storage_repository.dart';
import 'package:solace/screens/group_chat/group_chat_detail_screen.dart';
import 'package:solace/services/ai_service.dart';

class _MockStorage extends Mock implements LocalStorageRepository {}

class _MockAiService extends Mock implements AIService {}

/// 新空白群聊无限转圈回归测试。
///
/// 复现实况：GroupChatBloc 是全局共享单例，`_onLoadMessages` 的最后一次
/// emit 是 GroupChatBranchesLoaded（而非 MessagesLoaded），加上列表页
/// GroupChatLoadSessions 刷新会随时把状态切到 Loading/SessionsLoaded。
/// 若详情页缺少「已加载（含空列表）不再回到转圈」的终止分支，
/// 页面会永远停在居中加载圈。
void main() {
  late _MockStorage storage;
  late _MockAiService aiService;
  late GroupChatSession session;

  setUpAll(() {
    // mocktail 对非空复杂类型 any() 匹配需要 fallback 值
    registerFallbackValue(AICharacter(
      id: 'fallback',
      name: 'fb',
      personality: 'p',
      coreDesire: 'd',
      moralBoundary: 'm',
      createdAt: DateTime(2026, 8, 3),
    ));
    registerFallbackValue(ChatMessage(
      id: 'fb',
      chatId: 'g',
      senderId: 's',
      content: '',
      isUser: false,
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
    registerFallbackValue(Memory(
      id: 'fb',
      characterId: 'c',
      userId: 'u',
      type: MemoryType.conversation,
      content: '',
      createdAt: DateTime(2026, 8, 3),
    ));
  });

  setUp(() {
    storage = _MockStorage();
    aiService = _MockAiService();

    session = GroupChatSession(
      id: 'g1',
      name: '测试群',
      memberIds: ['c1', 'c2', 'u1'],
      aiCharacterIds: ['c1', 'c2'],
      creatorId: 'u1',
      createdAt: DateTime(2026, 8, 3),
    );

    when(() => storage.getGroupChatSession('g1'))
        .thenAnswer((_) async => session);
    when(() => storage.getGroupChatMessages(any(), chatId: any(named: 'chatId')))
        .thenAnswer((_) async => <GroupChatMessage>[]);
    when(() => storage.getGroupChatBranches('g1'))
        .thenAnswer((_) async => <GroupChatBranch>[]);
    when(() => storage.getAllAICharacters())
        .thenAnswer((_) async => <AICharacter>[]);
    when(() => storage.getGroupChatSessions('local_user'))
        .thenAnswer((_) async => <GroupChatSession>[session]);
  });

  Future<void> pumpDetail(WidgetTester tester, GroupChatBloc bloc) async {
    await tester.pumpWidget(MaterialApp(
      home: RepositoryProvider<LocalStorageRepository>.value(
        value: storage,
        child: BlocProvider<GroupChatBloc>.value(
          value: bloc,
          child: GroupChatDetailScreen(session: session),
        ),
      ),
    ));
  }

  testWidgets('空群聊加载完成后：分支/列表刷新等全局状态不再回到转圈', (tester) async {
    // 注意：bloc 必须在 testWidgets 的 FakeAsync zone 内创建，事件才会被驱动
    final bloc = GroupChatBloc(storage, aiService);

    await pumpDetail(tester, bloc);
    await tester.pumpAndSettle();

    // 空消息列表应渲染空态，而非居中加载圈
    expect(find.text('暂无消息'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    // 模拟列表页/主页刷新：共享 bloc 状态切到 Loading → SessionsLoaded
    bloc.add(const GroupChatLoadSessions('local_user'));
    await tester.pumpAndSettle();

    // 已加载完成的消息区/空态必须保持，不能被 Loading 顶回转圈
    expect(find.text('暂无消息'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('首次加载期间显示加载圈（不误伤正常 loading）', (tester) async {
    // 挂起消息查询：模拟加载进行中
    final gate = Completer<List<GroupChatMessage>>();
    when(() => storage.getGroupChatMessages(any(), chatId: any(named: 'chatId')))
        .thenAnswer((_) => gate.future);

    final bloc = GroupChatBloc(storage, aiService);
    await pumpDetail(tester, bloc);
    await tester.pump();

    // 查询未返回前应显示加载圈
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // 返回空列表后应切换为空态
    gate.complete(<GroupChatMessage>[]);
    await tester.pumpAndSettle();
    expect(find.text('暂无消息'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('发送后同帧 Typing 吞掉 MessagesLoaded：用户消息不消失（回归）', (tester) async {
    final bloc = GroupChatBloc(storage, aiService);
    await pumpDetail(tester, bloc);
    await tester.pumpAndSettle();
    // 初始空态（setUp 默认桩返回 []）
    expect(find.text('暂无消息'), findsOneWidget);

    // 发送阶段：覆盖桩，模拟本地 SQLite 链同帧完成
    final userMsg = GroupChatMessage(
      id: 'm_user',
      groupId: 'g1',
      senderId: 'u1',
      senderName: '我',
      content: '大家好',
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

    // LIST 策略：确定性激活全部成员，走到 _generateOneReply 的 Typing emit
    when(() => storage.isFaModeEnabled()).thenReturn(false);
    when(() => storage.saveGroupChatMessage(any())).thenAnswer((_) async {});
    when(() => storage.saveGroupChatSession(any())).thenAnswer((_) async {});
    when(() => storage.getGroupChatSession('g1')).thenAnswer((_) async =>
        session.copyWith(activationStrategy: GroupActivationStrategy.list));
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
    )).thenAnswer((_) => Stream<AIStreamChunk>.empty());

    bloc.add(GroupChatSendMessage(
      groupId: 'g1',
      userId: 'u1',
      content: '大家好',
      imagePaths: null,
    ));
    // 发送链完成 → 状态停在 GroupChatTyping（空流提前返回，无后续 MessagesLoaded）。
    // 这正是「AI 回复期间」：用户消息必须已经可见，不能等到 AI 回复后才出现。
    await tester.pumpAndSettle();

    expect(bloc.state, isA<GroupChatTyping>());
    expect(find.text('大家好'), findsOneWidget);
    expect(find.text('暂无消息'), findsNothing);
  });
}
