// 收藏搜索回归测试（web 模式 = SharedPreferences 后端，无需文件库）。
//
// 锁定的三个真实隐患：
// 1. 群聊收藏存在 metadata['bookmarked']=true 里，不是独立列。
//    任何按独立列查询的写法都会漏掉全部群聊收藏（表现为「搜不到群聊收藏」）。
// 2. LIKE 通配符不转义时，用户搜 "%" 会命中所有收藏（表现为「搜索失灵」）。
// 3. 搜索结果必须带 sessionId / characterId，收藏页跳转全靠这两个字段。
//
// 参考 test/group_chat_rolling_summary_test.dart 的 web 模式写法。
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solace/models/chat_message.dart';
import 'package:solace/models/chat_session.dart';
import 'package:solace/models/group_chat_message.dart';
import 'package:solace/models/group_chat_session.dart';
import 'package:solace/repositories/local_storage_repository.dart';

ChatMessage _msg(
  String id,
  String chatId,
  String content, {
  bool bookmark = true,
}) =>
    ChatMessage(
      id: id,
      chatId: chatId,
      senderId: 'u1',
      senderName: '我',
      content: content,
      isUser: true,
      createdAt: DateTime(2026, 1, 1),
      isBookmark: bookmark,
    );

GroupChatMessage _gmsg(
  String id,
  String groupId,
  String content, {
  bool bookmark = true,
  String sender = '小A',
}) =>
    GroupChatMessage(
      id: id,
      groupId: groupId,
      senderId: 'ai_c1',
      senderName: sender,
      content: content,
      isUser: false,
      timestamp: DateTime(2026, 1, 1),
      metadata: bookmark ? {'bookmarked': true} : null,
    );

void main() {
  group('群聊收藏标记格式（决定搜索能否查到）', () {
    test('isBookmarked 只认 metadata.bookmarked == true', () {
      expect(_gmsg('x', 'g', 'c', bookmark: false).isBookmarked, isFalse,
          reason: 'metadata 为 null');
      expect(
        GroupChatMessage(
          id: 'x',
          groupId: 'g',
          senderId: 'ai_c1',
          senderName: '小A',
          content: 'c',
          timestamp: DateTime(2026, 1, 1),
          metadata: const {},
        ).isBookmarked,
        isFalse,
        reason: '空 metadata',
      );
      expect(
        GroupChatMessage(
          id: 'x',
          groupId: 'g',
          senderId: 'ai_c1',
          senderName: '小A',
          content: 'c',
          timestamp: DateTime(2026, 1, 1),
          metadata: const {'bookmarked': false},
        ).isBookmarked,
        isFalse,
      );
      expect(_gmsg('x', 'g', 'c').isBookmarked, isTrue);
    });
  });

  group('单聊收藏搜索', () {
    late LocalStorageRepository repo;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      repo = LocalStorageRepository(isWeb: true);
      await repo.initialize();
      await repo.saveChatSession(ChatSessionFixture.session);
    });

    test('空查询直接返回空列表（不查库）', () async {
      await repo.saveChatMessage(_msg('m1', 'c1', '任意内容'));
      expect(await repo.searchBookmarkedMessages(''), isEmpty);
      expect(await repo.searchBookmarkedMessages('   '), isEmpty);
    });

    test('命中内容；未收藏的不返回', () async {
      await repo.saveChatMessage(_msg('m1', 'c1', '今晚一起看星星吗'));
      await repo.saveChatMessage(_msg('m2', 'c1', '未收藏的秘密',
          bookmark: false));

      final r = await repo.searchBookmarkedMessages('星星');
      expect(r.length, 1);
      expect((r.first['message'] as ChatMessage).id, 'm1');

      expect(await repo.searchBookmarkedMessages('未收藏'), isEmpty,
          reason: '未收藏的消息不能被搜出来');
    });

    test('按会话名/角色名命中', () async {
      await repo.saveChatMessage(_msg('m1', 'c1', '普通消息'));
      final r = await repo.searchBookmarkedMessages('林晚晚');
      expect(r.length, 1, reason: '角色名应可作为搜索维度');
    });

    test('结果带跳转所需字段', () async {
      await repo.saveChatMessage(_msg('m1', 'c1', '带跳转信息'));
      final r = await repo.searchBookmarkedMessages('跳转');
      expect(r.first['sessionId'], isNotEmpty);
      expect(r.first['characterId'], isNotEmpty);
      expect(r.first['sessionName'], isNotEmpty);
    });

    test('LIKE 通配符按字面量处理：搜 % 不返回全部', () async {
      await repo.saveChatMessage(_msg('m1', 'c1', '普通消息'));
      await repo.saveChatMessage(_msg('m2', 'c1', '带百分号 100% 的消息'));
      await repo.saveChatMessage(_msg('m3', 'c1', '带下划线 a_b 的消息'));

      final pct = await repo.searchBookmarkedMessages('%');
      expect(pct.length, 1, reason: '"%" 必须当字面量，不能当通配符');
      expect((pct.first['message'] as ChatMessage).id, 'm2');

      final under = await repo.searchBookmarkedMessages('_');
      expect(under.length, 1);
      expect((under.first['message'] as ChatMessage).id, 'm3');
    });

    test('limit 生效', () async {
      for (var i = 1; i <= 8; i++) {
        await repo.saveChatMessage(_msg('m$i', 'c1', '批量消息'));
      }
      final r = await repo.searchBookmarkedMessages('批量', limit: 3);
      expect(r.length, 3);
    });
  });

  group('群聊收藏搜索', () {
    late LocalStorageRepository repo;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      repo = LocalStorageRepository(isWeb: true);
      await repo.initialize();
      await repo.saveGroupChatSession(GroupChatSessionFixture.session);
    });

    test('命中群聊收藏（bookmarked 在 metadata 里）', () async {
      await repo.saveGroupChatMessage(_gmsg('g1', 'g1', '群里的悄悄话'));
      await repo
          .saveGroupChatMessage(_gmsg('g2', 'g1', '未收藏那句', bookmark: false));

      final r = await repo.searchGroupBookmarkedMessages('悄悄话');
      expect(r.length, 1);
      expect(r.first.id, 'g1');

      expect(await repo.searchGroupBookmarkedMessages('未收藏那句'), isEmpty);
    });

    test('按发言者名命中', () async {
      await repo.saveGroupChatMessage(
          _gmsg('g1', 'g1', '随便说点什么', sender: '沈砚清'));
      expect((await repo.searchGroupBookmarkedMessages('沈砚清')).length, 1);
    });

    test('空查询返回空列表', () async {
      await repo.saveGroupChatMessage(_gmsg('g1', 'g1', 'x'));
      expect(await repo.searchGroupBookmarkedMessages(''), isEmpty);
      expect(await repo.searchGroupBookmarkedMessages(' '), isEmpty);
    });

    test('LIKE 通配符按字面量处理', () async {
      await repo.saveGroupChatMessage(_gmsg('g1', 'g1', '普通消息'));
      await repo.saveGroupChatMessage(_gmsg('g2', 'g1', '含百分号 50%'));
      final r = await repo.searchGroupBookmarkedMessages('%');
      expect(r.length, 1);
      expect(r.first.id, 'g2');
    });
  });
}

/// ChatSession 固定夹具（角色名用于验证「按会话名搜索」）。
class ChatSessionFixture {
  static final session = ChatSession(
    id: 'c1',
    userId: 'u1',
    aiCharacterId: 'char1',
    aiCharacterName: '林晚晚',
    createdAt: DateTime(2026, 1, 1),
  );
}

class GroupChatSessionFixture {
  static final session = GroupChatSession(
    id: 'g1',
    name: '测试群',
    memberIds: const ['u1'],
    aiCharacterIds: const ['c1'],
    creatorId: 'u1',
    createdAt: DateTime(2026, 1, 1),
  );
}
