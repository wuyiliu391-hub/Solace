import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:solace/blocs/group_chat/group_chat_bloc.dart';
import 'package:solace/models/ai_character.dart';
import 'package:solace/models/group_chat_branch.dart';
import 'package:solace/models/group_chat_message.dart';
import 'package:solace/models/group_chat_session.dart';
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
}
