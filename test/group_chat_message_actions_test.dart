// 群聊消息操作测试：删除 / 收藏 / 编辑 / 撤回 / 重生成 / 引用传递。
//
// 对齐单聊 7 项操作语义（引用/复制/编辑/重生成/收藏/删除/撤回），
// 复制为纯 UI（Clipboard），此处覆盖 6 个走 GroupChatBloc 事件的操作。
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
      id: 'fb',
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

  GroupChatSession makeSession({List<String> aiIds = const ['c1']}) =>
      GroupChatSession(
        id: 'g1',
        name: '测试群',
        memberIds: [...aiIds, 'u1'],
        aiCharacterIds: aiIds,
        creatorId: 'u1',
        createdAt: DateTime(2026, 8, 3),
      );

  AICharacter makeChar(String id) => AICharacter(
        id: id,
        name: id == 'c1' ? '小A' : '小B',
        personality: 'p',
        coreDesire: 'd',
        moralBoundary: 'm',
        createdAt: DateTime(2026, 8, 3),
        talkativeness: 0.9,
      );

  GroupChatMessage aiMsg(String id, String content, {String sender = 'ai_c1'}) =>
      GroupChatMessage(
        id: id,
        groupId: 'g1',
        senderId: sender,
        senderName: sender == 'ai_c1' ? '小A' : '小B',
        content: content,
        isUser: false,
        timestamp: DateTime.now(),
      );

  GroupChatMessage userMsg(String id, String content,
          {DateTime? timestamp}) =>
      GroupChatMessage(
        id: id,
        groupId: 'g1',
        senderId: 'u1',
        senderName: '我',
        content: content,
        isUser: true,
        timestamp: timestamp ?? DateTime.now(),
      );

  void stubBase(_MockStorage storage, _MockAiService aiService,
      GroupChatSession session, List<GroupChatMessage> history) {
    when(() => storage.getGroupChatSession('g1'))
        .thenAnswer((_) async => session);
    when(() => storage.isFaModeEnabled()).thenReturn(false);
    when(() => storage.saveGroupChatMessage(any())).thenAnswer((_) async {});
    when(() => storage.deleteGroupChatMessage(any())).thenAnswer((_) async {});
    when(() => storage.saveGroupChatSession(any())).thenAnswer((_) async {});
    when(() => storage.getGroupChatMessages(any(),
            chatId: any(named: 'chatId')))
        .thenAnswer((_) async => List.of(history));
    when(() => storage.getGroupChatMessages(any(),
            limit: any(named: 'limit'), chatId: any(named: 'chatId')))
        .thenAnswer((_) async => List.of(history));
    when(() => storage.getAICharacter(any()))
        .thenAnswer((inv) async => makeChar(inv.positionalArguments.first as String));
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
    )).thenAnswer((_) => Stream.fromIterable([
          AIStreamChunk(reasoning: '', content: '新的回复'),
        ]));
  }

  test('删除消息：调用 deleteGroupChatMessage', () async {
    final storage = _MockStorage();
    final aiService = _MockAiService();
    stubBase(storage, aiService, makeSession(), [userMsg('m0', 'hi')]);

    final bloc = GroupChatBloc(storage, aiService);
    bloc.add(GroupChatDeleteMessage(groupId: 'g1', messageId: 'm0'));
    await Future<void>.delayed(const Duration(milliseconds: 150));

    verify(() => storage.deleteGroupChatMessage('m0')).called(1);
  });

  test('收藏翻转：saveGroupChatMessage 写入 bookmarked=true', () async {
    final storage = _MockStorage();
    final aiService = _MockAiService();
    final msg = aiMsg('m1', '回复内容');
    stubBase(storage, aiService, makeSession(), [msg, userMsg('m0', 'hi')]);

    final bloc = GroupChatBloc(storage, aiService);
    bloc.add(GroupChatToggleBookmark(groupId: 'g1', messageId: 'm1'));
    await Future<void>.delayed(const Duration(milliseconds: 150));

    final captured = verify(() => storage.saveGroupChatMessage(captureAny()))
        .captured
        .cast<GroupChatMessage>();
    expect(captured.any((m) => m.id == 'm1' && m.isBookmarked), isTrue);
  });

  test('编辑AI回复：保存新内容并打 editedAt 标记', () async {
    final storage = _MockStorage();
    final aiService = _MockAiService();
    final msg = aiMsg('m1', '旧回复');
    stubBase(storage, aiService, makeSession(), [msg, userMsg('m0', 'hi')]);

    final bloc = GroupChatBloc(storage, aiService);
    bloc.add(GroupChatEditAIReply(
        groupId: 'g1', messageId: 'm1', newContent: '编辑后的回复'));
    await Future<void>.delayed(const Duration(milliseconds: 150));

    final captured = verify(() => storage.saveGroupChatMessage(captureAny()))
        .captured
        .cast<GroupChatMessage>();
    final edited =
        captured.firstWhere((m) => m.id == 'm1', orElse: () => msg);
    expect(edited.content, '编辑后的回复');
    expect(edited.metadata?['editedAt'], isNotNull);
  });

  test('撤回用户消息：2 分钟内 → 已撤回占位', () async {
    final storage = _MockStorage();
    final aiService = _MockAiService();
    final msg = userMsg('m0', '要撤回的话');
    stubBase(storage, aiService, makeSession(), [msg]);

    final bloc = GroupChatBloc(storage, aiService);
    bloc.add(GroupChatRecallMessage(groupId: 'g1', messageId: 'm0'));
    await Future<void>.delayed(const Duration(milliseconds: 150));

    final captured = verify(() => storage.saveGroupChatMessage(captureAny()))
        .captured
        .cast<GroupChatMessage>();
    final recalled =
        captured.firstWhere((m) => m.id == 'm0', orElse: () => msg);
    expect(recalled.content, '已撤回');
    expect(recalled.metadata?['recalled'], isTrue);
  });

  test('撤回超过 2 分钟的消息：不生效', () async {
    final storage = _MockStorage();
    final aiService = _MockAiService();
    final old = userMsg(
      'm0',
      '太久以前的话',
      timestamp: DateTime.now().subtract(const Duration(minutes: 10)),
    );
    stubBase(storage, aiService, makeSession(), [old]);

    final bloc = GroupChatBloc(storage, aiService);
    bloc.add(GroupChatRecallMessage(groupId: 'g1', messageId: 'm0'));
    await Future<void>.delayed(const Duration(milliseconds: 150));

    // 不应有任何 saveGroupChatMessage 调用（撤回被拒绝）
    verifyNever(() => storage.saveGroupChatMessage(any()));
  });

  test('重新生成AI回复：删除旧消息并以该角色重新生成', () async {
    final storage = _MockStorage();
    final aiService = _MockAiService();
    final ai = aiMsg('m1', '旧AI回复');
    final usr = userMsg('m0', 'hi');
    // DESC 序：index 0 = 最新 = AI 消息
    stubBase(storage, aiService, makeSession(), [ai, usr]);

    final bloc = GroupChatBloc(storage, aiService);
    bloc.add(GroupChatRegenerateMessage(groupId: 'g1', messageId: 'm1'));
    await Future<void>.delayed(const Duration(milliseconds: 300));

    verify(() => storage.deleteGroupChatMessage('m1')).called(1);
    verify(() => aiService.sendMessageStream(
      character: any(named: 'character'),
      userId: any(named: 'userId'),
      userMessage: any(named: 'userMessage'),
      chatHistory: any(named: 'chatHistory'),
      memories: any(named: 'memories'),
      intimacyLevel: any(named: 'intimacyLevel'),
      sentiment: any(named: 'sentiment'),
      imagePaths: any(named: 'imagePaths'),
      internalSystemContext: any(named: 'internalSystemContext'),
    )).called(1);
  });

  test('发送带引用：metadata replyTo 随消息保存', () async {
    final storage = _MockStorage();
    final aiService = _MockAiService();
    stubBase(storage, aiService, makeSession(), [userMsg('m0', 'hi')]);

    final bloc = GroupChatBloc(storage, aiService);
    bloc.add(GroupChatSendMessage(
      groupId: 'g1',
      userId: 'u1',
      content: '回复引用',
      metadata: {
        'replyTo': {
          'messageId': 'm0',
          'senderName': '小A',
          'contentPreview': '被引用的内容',
        },
      },
    ));
    await Future<void>.delayed(const Duration(milliseconds: 200));

    final captured = verify(() => storage.saveGroupChatMessage(captureAny()))
        .captured
        .cast<GroupChatMessage>();
    final withReply = captured.where((m) => m.metadata?['replyTo'] != null);
    expect(withReply, isNotEmpty, reason: '用户消息应携带 replyTo metadata');
    final replyTo = withReply.first.metadata!['replyTo'] as Map;
    expect(replyTo['messageId'], 'm0');
    expect(replyTo['senderName'], '小A');
  });

  // ─── 旧群聊数据兼容性（无 DB 迁移，metadata 列自 v56 起就存在）───

  test('旧格式消息（无 metadata 列值）：新 getter 安全且不误判', () {
    // 模拟 v56 时代写入的行：无 metadata 字段
    final old = GroupChatMessage.fromMap({
      'id': 'm_old',
      'groupId': 'g1',
      'chatId': 'g1',
      'senderId': 'ai_c1',
      'senderName': '小A',
      'content': '老消息',
      'isUser': 0,
      'isSystem': 0,
      'type': 'text',
      'createdAt': '2026-07-01T10:00:00.000',
      'status': 'sent',
    });
    expect(old.isRecalled, isFalse);
    expect(old.isBookmarked, isFalse);
    expect(old.replyTo, isNull);
    expect(old.content, '老消息');
  });

  test('旧消息经撤回/收藏/编辑后 round-trip 可读', () {
    final old = GroupChatMessage.fromMap({
      'id': 'm_old',
      'groupId': 'g1',
      'chatId': 'g1',
      'senderId': 'u1',
      'senderName': '我',
      'content': '要撤回的老消息',
      'isUser': 1,
      'isSystem': 0,
      'type': 'text',
      'createdAt': DateTime.now().toIso8601String(),
      'status': 'sent',
    });

    // 撤回 → 落库 → 读回（模拟 saveGroupChatMessage + fromMap）
    final recalled = old.copyWith(
      content: '已撤回',
      status: GroupChatMessageStatus.failed,
      metadata: {...?old.metadata, 'recalled': true, 'originalContent': old.content},
    );
    final roundTrip = GroupChatMessage.fromMap(recalled.toMap());
    expect(roundTrip.isRecalled, isTrue);
    expect(roundTrip.content, '已撤回');

    // 收藏 → 落库 → 读回
    final bookmarked = old.copyWith(
        metadata: {...?old.metadata, 'bookmarked': true});
    expect(GroupChatMessage.fromMap(bookmarked.toMap()).isBookmarked, isTrue);

    // 编辑标记 → 落库 → 读回
    final edited = old.copyWith(
      content: '新内容',
      metadata: {...?old.metadata, 'editedAt': DateTime.now().toIso8601String()},
    );
    final editedRT = GroupChatMessage.fromMap(edited.toMap());
    expect(editedRT.content, '新内容');
    expect(editedRT.metadata?['editedAt'], isNotNull);

    // 引用 → 落库 → 读回
    final quoted = old.copyWith(metadata: {
      ...?old.metadata,
      'replyTo': {'messageId': 'm0', 'senderName': '小A', 'contentPreview': '引用摘要'},
    });
    expect(GroupChatMessage.fromMap(quoted.toMap()).replyTo?['messageId'], 'm0');
  });
}
