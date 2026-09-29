import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:solace/models/ai_character.dart';
import 'package:solace/models/memory.dart';
import 'package:solace/services/memory_engine.dart';
import 'package:solace/repositories/local_storage_repository.dart';

class _MockStorage extends Mock implements LocalStorageRepository {}

/// 可用的 AICharacter 构造函数（必填字段）
AICharacter _makeChar(String id, String name) {
  return AICharacter(
    id: id,
    name: name,
    personality: '温柔',
    coreDesire: '陪伴',
    moralBoundary: '友好',
    createdAt: DateTime.now(),
  );
}

Memory _makeMemory(String id, String content) {
  return Memory(
    id: id,
    characterId: 'char-test',
    userId: 'user-test',
    type: MemoryType.conversation,
    content: content,
    createdAt: DateTime.now(),
  );
}

void main() {
  late LocalStorageRepository mockStorage;
  late MemoryEngine engine;
  late AICharacter testCharacter;

  setUp(() {
    mockStorage = _MockStorage();
    engine = MemoryEngine(mockStorage);
    testCharacter = _makeChar('char-test', '测试角色');

    when(() => mockStorage.getString(any())).thenReturn(null);
    when(() => mockStorage.getBool(any())).thenReturn(false);
    when(() => mockStorage.getInt(any())).thenReturn(0);
  });

  group('buildConsolidatedMemoryPrompt', () {
    test('returns empty for memoryMode=off', () async {
      final result = await engine.buildConsolidatedMemoryPrompt(
        character: testCharacter,
        userId: 'user-test',
        currentMessage: '你好',
        memoryMode: 'off',
      );

      expect(result, isEmpty);
    });

    test('works without storage data (no crash)', () async {
      when(() => mockStorage.getMemories(
        characterId: any(named: 'characterId'),
        userId: any(named: 'userId'),
        type: any(named: 'type'),
        limit: any(named: 'limit'),
      )).thenAnswer((_) async => []);

      final result = await engine.buildConsolidatedMemoryPrompt(
        character: testCharacter,
        userId: 'user-test',
        currentMessage: '你好',
        memoryMode: 'full',
      );

      // Even with no data, should return something (heading content)
      expect(result, isA<String>());
    });
  });

  group('loadPrivateMemories', () {
    test('returns empty list when no memories', () async {
      when(() => mockStorage.getMemories(
        characterId: any(named: 'characterId'),
        userId: any(named: 'userId'),
      )).thenAnswer((_) async => []);

      final result = await engine.loadPrivateMemories('char-test', 'user-test');

      expect(result, isEmpty);
    });

    test('returns all conversation-type memories', () async {
      when(() => mockStorage.getMemories(
        characterId: any(named: 'characterId'),
        userId: any(named: 'userId'),
      )).thenAnswer((_) async => [
        _makeMemory('m1', '用户喜欢吃苹果'),
        _makeMemory('m2', '用户讨厌下雨'),
      ]);

      final result = await engine.loadPrivateMemories('char-test', 'user-test');

      expect(result.length, 2);
      expect(result[0].content, '用户喜欢吃苹果');
    });
  });

  group('getRollingSummary', () {
    test('returns null when no rolling summary', () async {
      when(() => mockStorage.getMemories(
        characterId: any(named: 'characterId'),
        userId: any(named: 'userId'),
        type: any(named: 'type'),
        limit: any(named: 'limit'),
      )).thenAnswer((_) async => []);

      final result = await engine.getRollingSummary(
        characterId: 'char-test',
        userId: 'user-test',
      );

      expect(result, isNull);
    });

    test('returns first rolling summary content', () async {
      when(() => mockStorage.getMemories(
        characterId: any(named: 'characterId'),
        userId: any(named: 'userId'),
        type: any(named: 'type'),
        limit: any(named: 'limit'),
      )).thenAnswer((_) async => [
        Memory(
          id: 'rs-1',
          characterId: 'char-test',
          userId: 'user-test',
          type: MemoryType.rollingSummary,
          content: '用户热爱旅行，去过5个国家',
          createdAt: DateTime.now(),
        ),
      ]);

      final result = await engine.getRollingSummary(
        characterId: 'char-test',
        userId: 'user-test',
      );

      expect(result, '用户热爱旅行，去过5个国家');
    });
  });

  group('Memory model', () {
    test('creates with default values', () {
      final m = Memory(
        id: 'm1',
        characterId: 'c1',
        userId: 'u1',
        type: MemoryType.conversation,
        content: 'test',
        createdAt: DateTime(2026, 7, 9),
      );

      expect(m.importance, MemoryImportance.normal);
      expect(m.weight, 1.0);
      expect(m.pinned, false);
      expect(m.accessCount, 0);
    });

    test('copyWith overrides selected fields', () {
      final m = Memory(
        id: 'm1',
        characterId: 'c1',
        userId: 'u1',
        type: MemoryType.conversation,
        content: '旧内容',
        createdAt: DateTime(2026, 7, 9),
      );

      final updated = m.copyWith(
        content: '新内容',
        importance: MemoryImportance.important,
      );

      expect(updated.id, 'm1');
      expect(updated.content, '新内容');
      expect(updated.importance, MemoryImportance.important);
    });

    test('equatable - same fields are equal', () {
      final t = DateTime(2026, 7, 9);
      expect(
        Memory(id: 'm1', characterId: 'c1', userId: 'u1', type: MemoryType.conversation, content: 'x', createdAt: t),
        Memory(id: 'm1', characterId: 'c1', userId: 'u1', type: MemoryType.conversation, content: 'x', createdAt: t),
      );
    });

    test('equatable - different IDs are not equal', () {
      final t = DateTime(2026, 7, 9);
      expect(
        Memory(id: 'm1', characterId: 'c1', userId: 'u1', type: MemoryType.conversation, content: 'x', createdAt: t),
        isNot(Memory(id: 'm2', characterId: 'c1', userId: 'u1', type: MemoryType.conversation, content: 'x', createdAt: t)),
      );
    });
  });

  group('MemoryImportance', () {
    test('has correct ordinal order', () {
      expect(MemoryImportance.values, [
        MemoryImportance.trivial,
        MemoryImportance.normal,
        MemoryImportance.important,
        MemoryImportance.crucial,
      ]);
    });
  });
}
