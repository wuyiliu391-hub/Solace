// 群聊成员事件测试：创建入场仪式 + 加成员/移除成员的系统消息。
//
// 对齐微信「xxx 加入了群聊 / xxx 离开了群聊」：系统消息只做 UI 展示，
// 不进 AI 上下文（_toChatHistory / speakersSinceLastUser 均跳过 isSystem）。
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:solace/blocs/group_chat/group_chat_bloc.dart';
import 'package:solace/models/ai_character.dart';
import 'package:solace/models/group_chat_message.dart';
import 'package:solace/models/group_chat_session.dart';
import 'package:solace/repositories/local_storage_repository.dart';
import 'package:solace/services/ai_service.dart';

class _MockStorage extends Mock implements LocalStorageRepository {}

class _MockAiService extends Mock implements AIService {}

void main() {
  setUpAll(() {
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
  });

  AICharacter makeChar(String id, String name) => AICharacter(
        id: id,
        name: name,
        personality: 'p',
        coreDesire: 'd',
        moralBoundary: 'm',
        createdAt: DateTime(2026, 8, 3),
      );

  /// 捕获所有 saveGroupChatMessage 的 system 消息内容
  List<String> captureSystemContents(_MockStorage storage) {
    final captured = verify(() => storage.saveGroupChatMessage(captureAny()))
        .captured
        .cast<GroupChatMessage>();
    return captured
        .where((m) => m.isSystem)
        .map((m) => m.content)
        .toList();
  }

  test('创建群聊：每个 AI 成员写「xxx 加入了群聊」系统消息', () async {
    final storage = _MockStorage();
    final aiService = _MockAiService();
    when(() => storage.saveGroupChatSession(any())).thenAnswer((_) async {});
    when(() => storage.saveGroupChatMessage(any())).thenAnswer((_) async {});
    when(() => storage.getAICharacter('c1'))
        .thenAnswer((_) async => makeChar('c1', '小A'));
    when(() => storage.getAICharacter('c2'))
        .thenAnswer((_) async => makeChar('c2', '小B'));

    final bloc = GroupChatBloc(storage, aiService);
    bloc.add(GroupChatCreate(
      userId: 'local_user',
      name: '我的群',
      avatarUrl: null,
      memberIds: ['c1', 'c2', 'local_user'],
      aiCharacterIds: ['c1', 'c2'],
    ));
    await Future<void>.delayed(const Duration(milliseconds: 150));

    final systemMessages = captureSystemContents(storage);
    expect(systemMessages, contains('小A 加入了群聊'));
    expect(systemMessages, contains('小B 加入了群聊'));
    expect(systemMessages.length, 2);
  });

  test('添加成员：写「xxx 加入了群聊」系统消息', () async {
    final storage = _MockStorage();
    final aiService = _MockAiService();
    final session = GroupChatSession(
      id: 'g1',
      name: '我的群',
      memberIds: ['c1', 'local_user'],
      aiCharacterIds: ['c1'],
      creatorId: 'local_user',
      createdAt: DateTime(2026, 8, 3),
    );
    when(() => storage.getGroupChatSession('g1'))
        .thenAnswer((_) async => session);
    when(() => storage.saveGroupChatSession(any())).thenAnswer((_) async {});
    when(() => storage.saveGroupChatMessage(any())).thenAnswer((_) async {});
    when(() => storage.getAICharacter('c2'))
        .thenAnswer((_) async => makeChar('c2', '小B'));
    when(() => storage.getGroupChatSessions(any()))
        .thenAnswer((_) async => [session]);

    final bloc = GroupChatBloc(storage, aiService);
    bloc.add(GroupChatAddMember('g1', 'c2'));
    await Future<void>.delayed(const Duration(milliseconds: 150));

    expect(captureSystemContents(storage), contains('小B 加入了群聊'));
  });

  test('移除成员：写「xxx 离开了群聊」系统消息', () async {
    final storage = _MockStorage();
    final aiService = _MockAiService();
    final session = GroupChatSession(
      id: 'g1',
      name: '我的群',
      memberIds: ['c1', 'c2', 'local_user'],
      aiCharacterIds: ['c1', 'c2'],
      creatorId: 'local_user',
      createdAt: DateTime(2026, 8, 3),
    );
    when(() => storage.getGroupChatSession('g1'))
        .thenAnswer((_) async => session);
    when(() => storage.saveGroupChatSession(any())).thenAnswer((_) async {});
    when(() => storage.saveGroupChatMessage(any())).thenAnswer((_) async {});
    when(() => storage.getAICharacter('c2'))
        .thenAnswer((_) async => makeChar('c2', '小B'));
    when(() => storage.getGroupChatSessions(any()))
        .thenAnswer((_) async => [session]);

    final bloc = GroupChatBloc(storage, aiService);
    bloc.add(GroupChatRemoveMember('g1', 'c2'));
    await Future<void>.delayed(const Duration(milliseconds: 150));

    expect(captureSystemContents(storage), contains('小B 离开了群聊'));
  });
}
