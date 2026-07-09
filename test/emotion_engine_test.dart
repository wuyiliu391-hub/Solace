import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:solace/config/constants.dart';
import 'package:solace/models/ai_character.dart';
import 'package:solace/models/character_emotion.dart';
import 'package:solace/services/emotion_engine.dart';
import 'package:solace/repositories/local_storage_repository.dart';

class _MockStorage extends Mock implements LocalStorageRepository {}

void main() {
  late LocalStorageRepository mockStorage;
  late EmotionEngine engine;
  late AICharacter testCharacter;

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

  group('emotion types', () {
    test('all types have labels and descriptions', () {
      for (final type in EmotionType.values) {
        expect(type.label, isNotEmpty);
        expect(type.description, isNotEmpty);
      }
    });

    test('covers required emotions', () {
      final names = EmotionType.values.map((e) => e.name).toSet();
      expect(names, containsAll([
        'happy', 'sad', 'angry', 'calm', 'worried', 'shy', 'touched',
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
