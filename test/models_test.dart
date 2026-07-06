import 'package:flutter_test/flutter_test.dart';
import 'package:solace/models/user.dart';
import 'package:solace/models/chat_session.dart';
import 'package:solace/models/chat_message.dart';
import 'package:solace/models/ai_character.dart';
import 'package:solace/models/ai_config.dart';

void main() {
  group('User Model', () {
    late User testUser;

    setUp(() {
      testUser = User(
        id: 'user_1',
        nickname: '测试用户',
        createdAt: DateTime(2026, 1, 1),
      );
    });

    test('创建 User 实例', () {
      expect(testUser.id, 'user_1');
      expect(testUser.nickname, '测试用户');
      expect(testUser.coins, 100);
      expect(testUser.totalCoinsEarned, 100);
      expect(testUser.totalCoinsSpent, 0);
    });

    test('copyWith 正确更新字段', () {
      final updated = testUser.copyWith(nickname: '新名字', coins: 200);
      expect(updated.nickname, '新名字');
      expect(updated.coins, 200);
      expect(updated.id, 'user_1');
    });

    test('toMap 和 fromMap 往返一致', () {
      final map = testUser.toMap();
      final fromMap = User.fromMap(map);
      expect(fromMap.id, testUser.id);
      expect(fromMap.nickname, testUser.nickname);
      expect(fromMap.coins, testUser.coins);
    });

    test('Equatable 比较相同对象', () {
      final user2 = User(
        id: 'user_1',
        nickname: '测试用户',
        createdAt: DateTime(2026, 1, 1),
      );
      expect(testUser, user2);
    });

    test('Equatable 比较不同对象', () {
      final user2 = User(
        id: 'user_2',
        nickname: '其他用户',
        createdAt: DateTime(2026, 1, 1),
      );
      expect(testUser == user2, false);
    });
  });

  group('ChatSession Model', () {
    late ChatSession testSession;

    setUp(() {
      testSession = ChatSession(
        id: 'session_1',
        userId: 'user_1',
        aiCharacterId: 'char_1',
        aiCharacterName: '小助手',
        createdAt: DateTime(2026, 1, 1),
      );
    });

    test('创建 ChatSession 实例', () {
      expect(testSession.id, 'session_1');
      expect(testSession.aiCharacterName, '小助手');
      expect(testSession.intimacyLevel, 0);
      expect(testSession.unreadCount, 0);
      expect(testSession.isBlocked, false);
      expect(testSession.blockedBy, BlockedBy.none);
    });

    test('copyWith 正确更新字段', () {
      final updated = testSession.copyWith(
        intimacyLevel: 50,
        lastMessage: '你好',
        unreadCount: 3,
      );
      expect(updated.intimacyLevel, 50);
      expect(updated.lastMessage, '你好');
      expect(updated.unreadCount, 3);
      expect(updated.id, 'session_1');
    });

    test('copyWith clearBlock 重置封禁状态', () {
      final blocked = testSession.copyWith(
        isBlocked: true,
        blockedBy: BlockedBy.user,
        blockReason: '测试',
      );
      expect(blocked.isBlocked, true);

      final unblocked = blocked.copyWith(clearBlock: true);
      expect(unblocked.isBlocked, false);
      expect(unblocked.blockedBy, BlockedBy.none);
      expect(unblocked.blockReason, null);
    });

    test('toMap 和 fromMap 往返一致', () {
      final map = testSession.toMap();
      final fromMap = ChatSession.fromMap(map);
      expect(fromMap.id, testSession.id);
      expect(fromMap.aiCharacterName, testSession.aiCharacterName);
      expect(fromMap.intimacyLevel, testSession.intimacyLevel);
    });

    test('BlockedBy 枚举值正确', () {
      expect(BlockedBy.values.length, 3);
      expect(BlockedBy.none.index, 0);
      expect(BlockedBy.user.index, 1);
      expect(BlockedBy.ai.index, 2);
    });
  });

  group('ChatMessage Model', () {
    test('创建 ChatMessage 实例', () {
      final msg = ChatMessage(
        id: 'msg_1',
        chatId: 'session_1',
        senderId: 'user_1',
        content: '你好',
        createdAt: DateTime(2026, 1, 1),
      );
      expect(msg.id, 'msg_1');
      expect(msg.content, '你好');
      expect(msg.senderId, 'user_1');
      expect(msg.type, MessageType.text);
      expect(msg.status, MessageStatus.sent);
    });

    test('MessageType 枚举值正确', () {
      expect(MessageType.values.length, 8);
      expect(MessageType.text.index, 0);
      expect(MessageType.image.index, 1);
      expect(MessageType.audio.index, 2);
      expect(MessageType.file.index, 3);
      expect(MessageType.system.index, 4);
      expect(MessageType.narration.index, 5);
      expect(MessageType.sticker.index, 6);
      expect(MessageType.voice.index, 7);
    });

    test('MessageStatus 枚举值正确', () {
      expect(MessageStatus.values.length, 7);
      expect(MessageStatus.sending.index, 0);
      expect(MessageStatus.sent.index, 1);
      expect(MessageStatus.delivered.index, 2);
      expect(MessageStatus.read.index, 3);
      expect(MessageStatus.error.index, 4);
      expect(MessageStatus.failed.index, 5);
      expect(MessageStatus.cancelled.index, 6);
    });
  });

  group('AICharacter Model', () {
    test('ReplyMode 枚举值正确', () {
      expect(ReplyMode.values.length, 4);
      expect(ReplyMode.instant.index, 0);
      expect(ReplyMode.normal.index, 1);
      expect(ReplyMode.delayed.index, 2);
      expect(ReplyMode.manual.index, 3);
    });
  });

  group('AIConfig Model', () {
    test('创建 AIConfig 实例', () {
      final config = AIConfig(
        id: 'config_1',
        providerName: 'openai',
        baseUrl: 'https://api.openai.com/v1',
        apiKey: 'sk-test',
        modelName: 'gpt-4',
        createdAt: DateTime(2026, 1, 1),
      );
      expect(config.id, 'config_1');
      expect(config.providerName, 'openai');
      expect(config.modelName, 'gpt-4');
      expect(config.temperature, 0.7);
      expect(config.maxTokens, 2000);
      expect(config.isActive, true);
    });

    test('allApiKeys 返回所有密钥', () {
      final config = AIConfig(
        id: 'config_1',
        providerName: 'openai',
        baseUrl: 'https://api.openai.com/v1',
        apiKey: 'sk-main',
        extraApiKeys: ['sk-extra1', 'sk-extra2'],
        modelName: 'gpt-4',
        createdAt: DateTime(2026, 1, 1),
      );
      expect(config.allApiKeys.length, 3);
      expect(config.allApiKeys[0], 'sk-main');
      expect(config.allApiKeys[1], 'sk-extra1');
    });

    test('copyWith 正确更新字段', () {
      final config = AIConfig(
        id: 'config_1',
        providerName: 'openai',
        baseUrl: 'https://api.openai.com/v1',
        apiKey: 'sk-test',
        modelName: 'gpt-4',
        createdAt: DateTime(2026, 1, 1),
      );
      final updated = config.copyWith(
        modelName: 'gpt-4-turbo',
        temperature: 0.9,
      );
      expect(updated.modelName, 'gpt-4-turbo');
      expect(updated.temperature, 0.9);
      expect(updated.id, 'config_1');
    });
  });
}
