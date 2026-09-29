import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:solace/config/constants.dart';
import 'package:solace/models/ai_character.dart';
import 'package:solace/models/ai_turn_state.dart';
import 'package:solace/models/character_emotion.dart';
import 'package:solace/models/memory.dart';
import 'package:solace/services/emotion_engine.dart';
import 'package:solace/repositories/local_storage_repository.dart';
import 'package:solace/utils/sentiment_analyzer.dart';

class _MockStorage extends Mock implements LocalStorageRepository {}

class _FakeMemory extends Fake implements Memory {}

void main() {
  late LocalStorageRepository mockStorage;
  late EmotionEngine engine;
  late AICharacter testCharacter;

  setUpAll(() {
    registerFallbackValue(_FakeMemory());
  });

  setUp(() {
    mockStorage = _MockStorage();
    engine = EmotionEngine(mockStorage);
    testCharacter = AICharacter(
      id: 'char-test',
      name: '测试角色',
      personality: '温柔体贴',
      coreDesire: '陪伴',
      moralBoundary: '友好',
      createdAt: DateTime.now(),
    );

    // EmotionEngine 通过 getString 读取情绪数据，默认返回 null（首次使用）
    when(() => mockStorage.getString(any())).thenReturn(null);
    when(() => mockStorage.setString(any(), any())).thenAnswer((_) async {});
    when(() => mockStorage.saveMemory(any())).thenAnswer((_) async {});
  });

  group('getCurrentEmotion', () {
    test('returns calm emotion for first use (no saved state)', () async {
      final emotion = await engine.getCurrentEmotion(
        character: testCharacter,
        userId: 'user-test',
      );

      expect(emotion.primaryEmotion, EmotionType.calm);
      expect(emotion.intensity, 0.0);
      expect(emotion.characterId, 'char-test');
      expect(emotion.userId, 'user-test');
    });

    test('multiple calls return same cached value', () async {
      final first = await engine.getCurrentEmotion(
        character: testCharacter,
        userId: 'user-test',
      );
      final second = await engine.getCurrentEmotion(
        character: testCharacter,
        userId: 'user-test',
      );

      expect(first.primaryEmotion, EmotionType.calm);
      expect(second.primaryEmotion, EmotionType.calm);
      // same instance due to caching
      expect(first.userId, second.userId);
    });

    test('different characters have separate emotions', () async {
      final char2 = AICharacter(
        id: 'char-2',
        name: '角色二',
        personality: '高冷',
        coreDesire: '独处',
        moralBoundary: '礼貌',
        createdAt: DateTime.now(),
      );

      final e1 = await engine.getCurrentEmotion(
        character: testCharacter,
        userId: 'u1',
      );
      final e2 = await engine.getCurrentEmotion(
        character: char2,
        userId: 'u1',
      );

      expect(e1.characterId, 'char-test');
      expect(e2.characterId, 'char-2');
    });
  });

  group('currentIntensity getter', () {
    test('fresh emotion has no decay', () {
      final emotion = CharacterEmotion(
        characterId: 'c1',
        userId: 'u1',
        primaryEmotion: EmotionType.happy,
        intensity: 0.8,
        updatedAt: DateTime.now(),
      );

      expect(emotion.currentIntensity, closeTo(0.8, 0.05));
      expect(emotion.effectiveEmotion, EmotionType.happy);
    });

    test('clamps intensity to minimum 0.0', () {
      final oldEmotion = CharacterEmotion(
        characterId: 'c1',
        userId: 'u1',
        primaryEmotion: EmotionType.happy,
        intensity: 0.1,
        updatedAt: DateTime.now().subtract(const Duration(hours: 48)),
      );
      // 48h * 0.03 = 1.44 decay > 0.1 initial
      expect(oldEmotion.currentIntensity, 0.0);
    });

    test('decays to calm below threshold', () {
      final emotion = CharacterEmotion(
        characterId: 'c1',
        userId: 'u1',
        primaryEmotion: EmotionType.happy,
        intensity: 0.05,
        updatedAt: DateTime.now().subtract(const Duration(hours: 24)),
      );

      expect(emotion.currentIntensity, 0.0);
      expect(emotion.effectiveEmotion, EmotionType.calm);
    });
  });

  group('buildEmotionPrompt', () {
    test('returns loneliness prompt when no interaction history', () async {
      // 首次使用时 lastInteractionTime 为 null → 孤独度 > 0.5 → 返回思念提示
      final prompt = await engine.buildEmotionPrompt(
        character: testCharacter,
        userId: 'user-test',
      );

      // 正是因为"没有互动历史"才触发思念提示
      expect(prompt, isNotEmpty);
      expect(prompt, contains('想念'));
    });
  });

  group('turn state persistence', () {
    test('user input changes the persisted emotion before the reply', () async {
      final emotion = await engine.updateEmotion(
        character: testCharacter,
        userId: 'user-test',
        userMessage: '我真的很喜欢你，你真好',
        userSentiment: SentimentAnalyzer.analyze('我真的很喜欢你，你真好'),
        intimacyLevel: 3,
      );

      expect(emotion.primaryEmotion, EmotionType.happy);
      expect(emotion.lastInteractionTime, isNotNull);
      verify(() => mockStorage.setString(
          PrefKeys.emotionType('char-test', 'user-test'), 'happy')).called(1);
    });

    test(
        'turn state is blended into persistent emotion instead of replacing it',
        () async {
      await engine.updateEmotion(
        character: testCharacter,
        userId: 'user-test',
        userMessage: '你真好，我很喜欢你',
        userSentiment: SentimentAnalyzer.analyze('你真好，我很喜欢你'),
        intimacyLevel: 3,
      );

      final emotion = await engine.applyTurnState(
        character: testCharacter,
        userId: 'user-test',
        turnState: const AiTurnState(
          emotion: '有点担心',
          intensity: 0.8,
          thought: '我想确认她今天是不是真的没事。',
        ),
      );

      expect(emotion.primaryEmotion, EmotionType.worried);
      expect(emotion.intensity, lessThan(0.8));
      expect(emotion.trigger, contains('我想确认她今天'));
      expect(emotion.lastInteractionTime, isNotNull);
      verify(() => mockStorage.setString(
          PrefKeys.emotionType('char-test', 'user-test'), 'worried')).called(1);
    });

    test(
        'unknown model emotion preserves the locally determined primary emotion',
        () async {
      final emotion = await engine.applyTurnState(
        character: testCharacter,
        userId: 'user-test',
        turnState: const AiTurnState(
          emotion: '五味杂陈',
          intensity: 0.6,
          thought: '这句话让我想了很久。',
        ),
      );

      expect(emotion.primaryEmotion, EmotionType.calm);
      expect(emotion.intensity, greaterThan(0));
    });
  });

  group('emotion types', () {
    test('all types have labels and descriptions', () {
      for (final type in EmotionType.values) {
        expect(type.label, isNotEmpty);
        expect(type.description, isNotEmpty);
      }
    });

    test('covers required emotions', () {
      final names = EmotionType.values.map((e) => e.name).toSet();
      expect(
          names,
          containsAll([
            'happy',
            'sad',
            'angry',
            'calm',
            'worried',
            'shy',
            'touched',
          ]));
    });
  });

  group('CharacterEmotion model', () {
    test('creates with default valence and arousal', () {
      final e = CharacterEmotion(
        characterId: 'c1',
        userId: 'u1',
        primaryEmotion: EmotionType.calm,
        intensity: 0.0,
        updatedAt: DateTime.now(),
      );

      expect(e.valence, 0.0);
      expect(e.arousal, 0.3);
    });

    test('copyWith creates independent copy', () {
      final e = CharacterEmotion(
        characterId: 'c1',
        userId: 'u1',
        primaryEmotion: EmotionType.calm,
        intensity: 0.0,
        updatedAt: DateTime(2026, 7, 9),
      );

      final updated = e.copyWith(
        primaryEmotion: EmotionType.happy,
        intensity: 0.8,
      );

      expect(updated.primaryEmotion, EmotionType.happy);
      expect(updated.intensity, 0.8);
      expect(e.primaryEmotion, EmotionType.calm); // original unchanged
    });
  });
}
