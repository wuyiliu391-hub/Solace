// 群聊记忆艾宾浩斯化测试。
//
// 1. extractGroupMemories：LLM 群聊事件提取成功 → 写入社交记忆（MockClient 拦截 HTTP）
// 2. extractGroupMemories：LLM 失败（非200）→ 静默返回 0 不抛错
// 3. extractGroupMemories：去重 + 用户重要发言全员分发
// 4. dailyDecaySocial：艾宾浩斯衰减/强化/pinned 跳过（真 SQLite）
// 5. markSocialRecalled：注入增强 + lastRecalledAt（真 SQLite）
// 6. buildConsolidatedMemoryPrompt ④段：群聊/互动分组注入 + 冷记忆过滤（真 SQLite）
// 7. GroupChatBloc：第 5 轮触发 LLM 提取 + 粗摘要降频（回归防护）
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:solace/blocs/group_chat/group_chat_bloc.dart';
import 'package:solace/models/ai_character.dart';
import 'package:solace/models/ai_config.dart';
import 'package:solace/models/ai_stream_chunk.dart';
import 'package:solace/models/chat_message.dart';
import 'package:solace/models/group_chat_message.dart';
import 'package:solace/models/group_chat_session.dart';
import 'package:solace/models/memory.dart';
import 'package:solace/repositories/database_service.dart';
import 'package:solace/repositories/local_storage_repository.dart';
import 'package:solace/services/ai_service.dart';
import 'package:solace/services/memory_engine.dart';

class _MockStorage extends Mock implements LocalStorageRepository {}

class _MockAiService extends Mock implements AIService {}

class _MockMemoryEngine extends Mock implements MemoryEngine {}

AICharacter _char(String id, String name) => AICharacter(
      id: id,
      name: name,
      personality: '性格$name：热情开朗',
      coreDesire: '心愿',
      moralBoundary: '原则',
      backgroundStory: '背景故事$name',
      createdAt: DateTime(2026, 8, 3),
      talkativeness: 0.9,
    );

/// 构造 OpenAI Chat Completions 格式的 mock 响应
http.Response _llmResponse(String text) => http.Response.bytes(
      utf8.encode(jsonEncode({
        'choices': [
          {
            'message': {'content': text}
          }
        ]
      })),
      200,
      headers: {'content-type': 'application/json'},
    );

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    registerFallbackValue(_char('fb', 'fb'));    registerFallbackValue(GroupChatMessage(
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

  // FFI 数据库文件跨测试进程持久 → 每次测试前清空社交记忆表，保证隔离
  setUp(() async {
    final db = await DatabaseService.instance.database;
    await db.delete('social_memories');
  });

  _MockStorage stubStorage() {
    final storage = _MockStorage();
    when(() => storage.getActiveAIConfig()).thenAnswer((_) async => AIConfig(
          id: 'cfg',
          providerName: 'test',
          baseUrl: 'https://test.local/v1/',
          apiKey: 'sk-test',
          modelName: 'test-model',
          createdAt: DateTime(2026, 8, 3),
        ));
    when(() => storage.buildGlobalModePrompt(scope: any(named: 'scope')))
        .thenReturn('');
    return storage;
  }

  test('extractGroupMemories：LLM 提取成功 → 按发言角色写入社交记忆', () async {
    final storage = stubStorage();
    final engine = MemoryEngine(
      storage,
      httpClient: MockClient((request) async {
        return _llmResponse(
            '{"speaker": "小A", "content": "小B约定周末一起去海边", "emotion": "期待", "importance": 2, "keywords": ["海边", "周末"]}\n{"speaker": "小B", "content": "小A下周想去旅行", "emotion": "", "importance": 1, "keywords": ["旅行"]}');
      }),
    );

    final saved = await engine.extractGroupMemories(
      messages: [
        GroupChatMessage(
            id: 'm1',
            groupId: 'g1',
            senderId: 'u1',
            senderName: '我',
            content: '大家好',
            isUser: true),
        GroupChatMessage(
            id: 'm2',
            groupId: 'g1',
            senderId: 'ai_c1',
            senderName: '小A',
            content: '周末去海边玩吧！',
            isUser: false),
        GroupChatMessage(
            id: 'm3',
            groupId: 'g1',
            senderId: 'ai_c2',
            senderName: '小B',
            content: '我下周想去旅行',
            isUser: false),
      ],
      groupName: '测试群',
      speakerCharacterIds: {'小A': 'c1', '小B': 'c2'},
      groupId: 'g1',
    );

    expect(saved, 2);
    final c1 = await engine.loadSocialMemories('c1');
    final c2 = await engine.loadSocialMemories('c2');
    expect(c1, hasLength(1));
    expect(c1.first.content, contains('海边'));
    expect(c1.first.userId, 'g1'); // targetCharacterId 复用 userId 字段
    expect(c2, hasLength(1));
    expect(c2.first.content, contains('旅行'));
  });

  test('extractGroupMemories：LLM 失败（非200）→ 静默返回 0 不抛错', () async {
    final storage = stubStorage();
    final engine = MemoryEngine(
      storage,
      httpClient: MockClient((request) async => http.Response('err', 500)),
    );

    final saved = await engine.extractGroupMemories(
      messages: [
        GroupChatMessage(
            id: 'm1',
            groupId: 'g1',
            senderId: 'ai_c1',
            senderName: '小A',
            content: '你好',
            isUser: false),
        GroupChatMessage(
            id: 'm2',
            groupId: 'g1',
            senderId: 'ai_c2',
            senderName: '小B',
            content: '在吗',
            isUser: false),
      ],
      groupName: '测试群',
      speakerCharacterIds: {'小A': 'cA2', '小B': 'cB2'},
      groupId: 'g2',
    );

    expect(saved, 0);
    expect(await engine.loadSocialMemories('cA2'), isEmpty);
  });

  test('extractGroupMemories：去重跳过 + 用户重要发言全员分发', () async {
    final storage = stubStorage();
    final engine = MemoryEngine(storage);
    // 预置一条已存在的群聊记忆（LLM 将返回相似内容 → 应去重跳过）
    await engine.saveSocialMemory(
      characterId: 'cA',
      targetCharacterId: 'g3',
      interactionType: 'group_chat',
      content: '小B约定周末一起去海边',
      importance: 'important',
    );

    final withHttp = MemoryEngine(
      storage,
      httpClient: MockClient((request) async {
        return _llmResponse(
            '{"speaker": "小A", "content": "小B约定周末一起去海边", "importance": 2}\n{"speaker": "用户", "content": "用户下周要去旅行", "importance": 2}');
      }),
    );

    final saved = await withHttp.extractGroupMemories(
      messages: [
        GroupChatMessage(
            id: 'm1',
            groupId: 'g3',
            senderId: 'u1',
            senderName: '我',
            content: '我下周要去旅行',
            isUser: true),
        GroupChatMessage(
            id: 'm2',
            groupId: 'g3',
            senderId: 'ai_cA',
            senderName: '小A',
            content: '一起吧！',
            isUser: false),
      ],
      groupName: '测试群',
      speakerCharacterIds: {'小A': 'cA', '小B': 'cB'},
      groupId: 'g3',
    );

    // 1 条去重跳过，1 条用户重要发言分发到 2 个成员
    expect(saved, 2);
    final c1 = await engine.loadSocialMemories('cA');
    final c2 = await engine.loadSocialMemories('cB');
    expect(c1, hasLength(2)); // 预置 + 用户发言
    expect(c2, hasLength(1));
    expect(c2.first.content, contains('旅行'));
    expect(c2.first.userId, 'g3');
  });

  test('dailyDecaySocial：未回忆衰减 / 24h内回忆强化 / pinned 跳过', () async {
    final storage = stubStorage();
    final engine = MemoryEngine(storage);
    final db = await DatabaseService.instance.database;

    // 造 3 条（weight 通过直连 DB 调整到指定值）
    await engine.saveSocialMemory(
        characterId: 'c1', targetCharacterId: 'g4', interactionType: 'group_chat', content: '衰记忆1');
    await engine.saveSocialMemory(
        characterId: 'c1', targetCharacterId: 'g4', interactionType: 'group_chat', content: '强记忆2');
    await engine.saveSocialMemory(
        characterId: 'c1', targetCharacterId: 'g4', interactionType: 'group_chat', content: '锁记忆3');
    final rows = await db.query('social_memories',
        where: 'characterId = ? AND targetCharacterId = ?',
        whereArgs: ['c1', 'g4']);
    expect(rows, hasLength(3));

    // 条2：24h 内被回忆 → 强化；条3：pinned → 跳过
    await db.update('social_memories',
        {'weight': 1.0, 'lastRecalledAt': DateTime.now().toIso8601String()},
        where: 'id = ?', whereArgs: [rows[1]['id']]);
    await db.update('social_memories',
        {'weight': 0.5, 'pinned': 1},
        where: 'id = ?', whereArgs: [rows[2]['id']]);

    final changed = await engine.dailyDecaySocial(
        characterId: 'c1', targetCharacterId: 'g4');

    expect(changed, 2); // 条3 pinned 不计
    final after = await db.query('social_memories',
        where: 'characterId = ? AND targetCharacterId = ?',
        whereArgs: ['c1', 'g4']);
    final w1 = (after.firstWhere((r) => r['id'] == rows[0]['id'])['weight'] as num).toDouble();
    final w2 = (after.firstWhere((r) => r['id'] == rows[1]['id'])['weight'] as num).toDouble();
    final w3 = (after.firstWhere((r) => r['id'] == rows[2]['id'])['weight'] as num).toDouble();
    expect(w1, closeTo(1.0 * 0.998, 0.0001)); // 未回忆 → 衰减
    expect(w2, closeTo(1.0 * 1.01, 0.0001)); // 被回忆 → 强化
    expect(w3, 0.5); // pinned 不动
  });

  test('markSocialRecalled：基础 +0.01 / 冷记忆 +0.1 / pinned 跳过 / 记 lastRecalledAt',
      () async {
    final storage = stubStorage();
    final engine = MemoryEngine(storage);
    final db = await DatabaseService.instance.database;

    await engine.saveSocialMemory(
        characterId: 'c1', targetCharacterId: 'g5', interactionType: 'group_chat', content: '温记忆');
    await engine.saveSocialMemory(
        characterId: 'c1', targetCharacterId: 'g5', interactionType: 'group_chat', content: '冷记忆');
    await engine.saveSocialMemory(
        characterId: 'c1', targetCharacterId: 'g5', interactionType: 'group_chat', content: '锁记忆');
    final rows = await db.query('social_memories',
        where: 'characterId = ? AND targetCharacterId = ?',
        whereArgs: ['c1', 'g5']);
    await db.update('social_memories', {'weight': 0.3},
        where: 'id = ?', whereArgs: [rows[1]['id']]);
    await db.update('social_memories', {'pinned': 1},
        where: 'id = ?', whereArgs: [rows[2]['id']]);

    await engine.markSocialRecalled(
      characterId: 'c1',
      recalledMemoryIds: rows.map((r) => r['id'] as String).toList(),
    );

    final after = await db.query('social_memories',
        where: 'characterId = ? AND targetCharacterId = ?',
        whereArgs: ['c1', 'g5']);
    final w1 = (after.firstWhere((r) => r['id'] == rows[0]['id'])['weight'] as num).toDouble();
    final w2 = (after.firstWhere((r) => r['id'] == rows[1]['id'])['weight'] as num).toDouble();
    final w3 = (after.firstWhere((r) => r['id'] == rows[2]['id'])['weight'] as num).toDouble();
    expect(w1, closeTo(1.0 + 0.01, 0.0001)); // 基础强化
    expect(w2, closeTo(0.3 + 0.1, 0.0001)); // 冷记忆额外强化
    expect(w3, 1.0); // pinned 不动
    final recalledAt =
        after.firstWhere((r) => r['id'] == rows[0]['id'])['lastRecalledAt'] as String;
    expect(recalledAt, isNotEmpty);
  });

  test('buildConsolidatedMemoryPrompt ④段：群聊/互动分组注入 + 冷记忆过滤 + 标记已回忆',
      () async {
    final storage = stubStorage();
    when(() => storage.getPromptSafeMemories(
            characterId: any(named: 'characterId'),
            userId: any(named: 'userId'),
            limit: any(named: 'limit')))
        .thenAnswer((_) async => <Memory>[]);
    when(() => storage.getMemories(
            characterId: any(named: 'characterId'),
            userId: any(named: 'userId'),
            type: any(named: 'type'),
            limit: any(named: 'limit')))
        .thenAnswer((_) async => <Memory>[]);

    final engine = MemoryEngine(storage);
    // 预置：1 条群聊回忆（热）+ 1 条角色互动 + 1 条群聊冷记忆（30 天前，weight 0.2）
    // 全部用独立角色 cZ，避免与其他测试的 c1 数据串扰
    await engine.saveSocialMemory(
        characterId: 'cZ',
        targetCharacterId: 'g6',
        interactionType: 'group_chat',
        content: '小B约我周末去海边散步',
        importance: 'important');
    await engine.saveSocialMemory(
        characterId: 'cZ',
        targetCharacterId: 'c2',
        interactionType: 'chat',
        content: '和小B交换过秘密',
        importance: 'important');
    await engine.saveSocialMemory(
        characterId: 'cZ',
        targetCharacterId: 'g6',
        interactionType: 'group_chat',
        content: '远古时期遗忘的往事');
    final db = await DatabaseService.instance.database;
    final cold = await db.query('social_memories',
        where: 'content = ?', whereArgs: ['远古时期遗忘的往事']);
    await db.update('social_memories',
        {'weight': 0.2, 'timestamp': DateTime.now()
            .subtract(const Duration(days: 30))
            .toIso8601String()},
        where: 'id = ?', whereArgs: [cold.first['id']]);

    final out = await engine.buildConsolidatedMemoryPrompt(
      character: _char('cZ', '小A'),
      userId: 'u1',
      currentMessage: '今天聊什么',
      includeSocial: true,
    );

    expect(out, contains('【你在群聊中的回忆】'));
    expect(out, contains('小B约我周末去海边散步'));
    expect(out, contains('【你与其他角色的互动】'));
    expect(out, contains('交换过秘密'));
    expect(out, isNot(contains('远古时期遗忘的往事')));

    // 注入后标记已回忆：热记忆 weight 应被增强（异步，稍等）
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final recalled = await engine.loadSocialMemories('cZ');
    final hot = recalled.firstWhere((m) => m.content.contains('海边散步'));
    expect(hot.weight, greaterThan(1.0));
    final coldAfter = recalled.firstWhere(
        (m) => m.content.contains('远古时期'),
        orElse: () => Memory(
            id: 'none',
            characterId: 'cZ',
            userId: 'x',
            type: MemoryType.conversation,
            content: '',
            createdAt: DateTime.now()));
    expect(coldAfter.weight, closeTo(0.2, 0.0001)); // 未注入 → 不增强
  });

  test('GroupChatBloc：第 5 轮回复触发 LLM 提取，粗摘要仅第 1 轮写入（降频）',
      () async {
    final storage = _MockStorage();
    final aiService = _MockAiService();
    final memEngine = _MockMemoryEngine();
    final session = GroupChatSession(
      id: 'g7',
      name: '测试群',
      memberIds: ['c1', 'u1'],
      aiCharacterIds: ['c1'],
      creatorId: 'u1',
      createdAt: DateTime(2026, 8, 3),
    );
    final userMsg = GroupChatMessage(
      id: 'm1',
      groupId: 'g7',
      senderId: 'u1',
      senderName: '我',
      content: 'hi',
      isUser: true,
    );
    final aiMsg = GroupChatMessage(
      id: 'm2',
      groupId: 'g7',
      senderId: 'ai_c1',
      senderName: '小A',
      content: '你好呀',
      isUser: false,
    );
    when(() => storage.getGroupChatSession('g7'))
        .thenAnswer((_) async => session);
    when(() => storage.isFaModeEnabled()).thenReturn(false);
    when(() => storage.saveGroupChatMessage(any())).thenAnswer((_) async {});
    when(() => storage.saveGroupChatSession(any())).thenAnswer((_) async {});
    when(() => storage.getGroupChatMessages(any(),
            chatId: any(named: 'chatId')))
        .thenAnswer((_) async => [userMsg, aiMsg]);
    when(() => storage.getGroupChatMessages(any(),
            limit: any(named: 'limit'), chatId: any(named: 'chatId')))
        .thenAnswer((_) async => [userMsg, aiMsg]);
    when(() => storage.getMemories(
            characterId: any(named: 'characterId'),
            userId: any(named: 'userId'),
            limit: any(named: 'limit')))
        .thenAnswer((_) async => <Memory>[]);
    when(() => storage.getAICharacter('c1'))
        .thenAnswer((_) async => _char('c1', '小A'));
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
    when(() => memEngine.buildGroupSharedContext(
          self: any(named: 'self'),
          members: any(named: 'members'),
          userId: any(named: 'userId'),
          groupId: any(named: 'groupId'),
        ))
        .thenAnswer((_) async => '');
    when(() => memEngine.saveSocialMemory(
          characterId: any(named: 'characterId'),
          targetCharacterId: any(named: 'targetCharacterId'),
          interactionType: any(named: 'interactionType'),
          content: any(named: 'content'),
          emotionTag: any(named: 'emotionTag'),
          importance: any(named: 'importance'),
          keywords: any(named: 'keywords'),
        ))
        .thenAnswer((_) async {});
    when(() => memEngine.extractGroupMemories(
      messages: any(named: 'messages'),
      groupName: any(named: 'groupName'),
      speakerCharacterIds: any(named: 'speakerCharacterIds'),
      groupId: any(named: 'groupId'),
    )).thenAnswer((_) async => 0);

    final bloc = GroupChatBloc(storage, aiService, memoryEngine: memEngine);
    for (var i = 0; i < 5; i++) {
      bloc.add(GroupChatSendMessage(
        groupId: 'g7',
        userId: 'u1',
        content: 'hi $i',
        imagePaths: null,
      ));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }

    // 粗摘要降频：仅第 1 轮写入 1 条
    verify(() => memEngine.saveSocialMemory(
      characterId: any(named: 'characterId'),
      targetCharacterId: any(named: 'targetCharacterId'),
      interactionType: any(named: 'interactionType'),
      content: any(named: 'content'),
      emotionTag: any(named: 'emotionTag'),
      importance: any(named: 'importance'),
      keywords: any(named: 'keywords'),
    )).called(1);
    // 第 5 轮触发 LLM 提取（可能因接话提前，至少触发 1 次）
    verify(() => memEngine.extractGroupMemories(
      messages: any(named: 'messages'),
      groupName: any(named: 'groupName'),
      speakerCharacterIds: any(named: 'speakerCharacterIds'),
      groupId: 'g7',
    )).called(greaterThanOrEqualTo(1));
  });
}
