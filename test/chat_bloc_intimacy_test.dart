import 'package:flutter_test/flutter_test.dart';
import 'package:solace/blocs/chat/chat_bloc_intimacy.dart';
import 'package:solace/models/chat_message.dart';
import 'package:solace/models/chat_session.dart';
import 'package:solace/models/character_emotion.dart';
import 'package:solace/utils/sentiment_analyzer.dart';

class _TestIntimacy with ChatBlocIntimacy {}

void main() {
  late _TestIntimacy intimacy;

  setUp(() {
    intimacy = _TestIntimacy();
  });

  ChatSession _makeSession({
    int intimacyLevel = 0,
    int dailyIntimacyCount = 0,
    String? lastIntimacyDate,
    DateTime? lastMessageTime,
  }) {
    return ChatSession(
      id: 'test-session',
      userId: 'user1',
      aiCharacterId: 'char1',
      aiCharacterName: '测试角色',
      intimacyLevel: intimacyLevel,
      dailyIntimacyCount: dailyIntimacyCount,
      lastIntimacyDate: lastIntimacyDate,
      lastMessageTime: lastMessageTime,
      createdAt: DateTime.now(),
    );
  }

  group('calculateIntimacy', () {
    test('does not increase for very short messages', () {
      final session = _makeSession(intimacyLevel: 10);
      final result = intimacy.calculateIntimacy(
        session: session,
        messageContent: '嗯',
        sentiment: SentimentResult(
            score: 0, label: 'neutral', type: SentimentType.neutral),
        faModeActive: false,
      );
      expect(result.newLevel, 10);
    });

    test('increases for meaningful messages', () {
      final today = DateTime.now().toIso8601String().substring(0, 10);
      final session = _makeSession(
        intimacyLevel: 10,
        dailyIntimacyCount: 0,
        lastIntimacyDate: today,
      );
      final result = intimacy.calculateIntimacy(
        session: session,
        messageContent: '今天天气真好，我们出去走走吧',
        sentiment: SentimentResult(
            score: 1, label: 'positive', type: SentimentType.positive),
        faModeActive: false,
      );
      expect(result.newLevel, greaterThanOrEqualTo(10));
    });

    test('respects daily cap', () {
      final today = DateTime.now().toIso8601String().substring(0, 10);
      final session = _makeSession(
        intimacyLevel: 10,
        dailyIntimacyCount: 5, // at cap
        lastIntimacyDate: today,
      );
      final result = intimacy.calculateIntimacy(
        session: session,
        messageContent: '这是一条足够长的消息',
        sentiment: SentimentResult(
            score: 1, label: 'positive', type: SentimentType.positive),
        faModeActive: false,
      );
      expect(result.newLevel, 10); // no increase
    });

    test('negative sentiment deducts points when faMode is off', () {
      final session = _makeSession(intimacyLevel: 50);
      final result = intimacy.calculateIntimacy(
        session: session,
        messageContent: '讨厌你这个混蛋',
        sentiment: SentimentResult(
            score: -2, label: 'negative', type: SentimentType.negative),
        faModeActive: false,
      );
      expect(result.newLevel, lessThan(50));
    });

    test('negative sentiment does NOT deduct when faMode is on', () {
      final session = _makeSession(intimacyLevel: 50);
      final result = intimacy.calculateIntimacy(
        session: session,
        messageContent: '讨厌你这个混蛋',
        sentiment: SentimentResult(
            score: -2, label: 'negative', type: SentimentType.negative),
        faModeActive: true,
      );
      expect(result.newLevel, greaterThanOrEqualTo(50)); // no deduction
    });

    test('decay after 48 hours of inactivity', () {
      final twoDaysAgo = DateTime.now().subtract(const Duration(hours: 50));
      final session = _makeSession(
        intimacyLevel: 50,
        lastMessageTime: twoDaysAgo,
      );
      final result = intimacy.calculateIntimacy(
        session: session,
        messageContent: '好久不见，想你了',
        sentiment: SentimentResult(
            score: 1, label: 'positive', type: SentimentType.positive),
        faModeActive: false,
      );
      expect(result.newLevel, lessThanOrEqualTo(50));
    });

    test('clamps level to 0-100 range', () {
      final session = _makeSession(intimacyLevel: 0);
      final result = intimacy.calculateIntimacy(
        session: session,
        messageContent: '测试消息',
        sentiment: SentimentResult(
            score: -5, label: 'negative', type: SentimentType.negative),
        faModeActive: false,
      );
      expect(result.newLevel, greaterThanOrEqualTo(0));
    });
  });

  group('shouldSkipReply', () {
    test('never skips first reply', () {
      expect(
        intimacy.shouldSkipReply(
          personality: '高冷',
          intimacyLevel: 50,
          messageContent: '嗯',
          consecutiveAiReplies: 0,
          messageType: MessageType.text,
        ),
        false,
      );
    });

    test('never skips image messages', () {
      expect(
        intimacy.shouldSkipReply(
          personality: '高冷',
          intimacyLevel: 50,
          messageContent: '',
          consecutiveAiReplies: 3,
          messageType: MessageType.image,
        ),
        false,
      );
    });

    test('never skips questions', () {
      expect(
        intimacy.shouldSkipReply(
          personality: '高冷',
          intimacyLevel: 50,
          messageContent: '你在干嘛？',
          consecutiveAiReplies: 3,
          messageType: MessageType.text,
        ),
        false,
      );
    });

    test('short replies can be skipped after consecutive AI replies', () {
      final skipped = intimacy.shouldSkipReply(
        personality: '高冷',
        intimacyLevel: 80,
        messageContent: '嗯',
        consecutiveAiReplies: 2,
        messageType: MessageType.text,
      );
      expect(skipped, isA<bool>());
    });
  });

  group('calculateForgiveChance', () {
    test('increases with more pending messages', () {
      final chance1 = intimacy.calculateForgiveChance(
        pendingCount: 1,
        blockDuration: const Duration(minutes: 1),
        emotionIntensity: 0.5,
      );
      final chance5 = intimacy.calculateForgiveChance(
        pendingCount: 5,
        blockDuration: const Duration(minutes: 1),
        emotionIntensity: 0.5,
      );
      expect(chance5, greaterThan(chance1));
    });

    test('increases with longer block duration', () {
      final chance1 = intimacy.calculateForgiveChance(
        pendingCount: 1,
        blockDuration: const Duration(minutes: 1),
        emotionIntensity: 0.5,
      );
      final chance15 = intimacy.calculateForgiveChance(
        pendingCount: 1,
        blockDuration: const Duration(minutes: 15),
        emotionIntensity: 0.5,
      );
      expect(chance15, greaterThan(chance1));
    });

    test('clamps to max 0.95', () {
      final chance = intimacy.calculateForgiveChance(
        pendingCount: 100,
        blockDuration: const Duration(hours: 1),
        emotionIntensity: 0.0,
      );
      expect(chance, lessThanOrEqualTo(0.95));
    });

    test('clamps to min 0.0', () {
      final chance = intimacy.calculateForgiveChance(
        pendingCount: 0,
        blockDuration: Duration.zero,
        emotionIntensity: 1.0,
      );
      expect(chance, greaterThanOrEqualTo(0.0));
    });
  });

  group('calculateReadDelay', () {
    test('returns base delay for neutral emotion', () {
      final delay = intimacy.calculateReadDelay(EmotionType.calm, 0.0);
      expect(delay, 800);
    });

    test('angry emotion increases delay', () {
      final delay = intimacy.calculateReadDelay(EmotionType.angry, 0.8);
      expect(delay, greaterThan(800));
    });

    test('sad emotion increases delay moderately', () {
      final delay = intimacy.calculateReadDelay(EmotionType.sad, 0.5);
      expect(delay, greaterThan(800));
      expect(
          delay, lessThan(intimacy.calculateReadDelay(EmotionType.angry, 0.5)));
    });
  });

  group('getTypingDelay', () {
    test('returns default delay', () {
      expect(intimacy.getTypingDelay('活泼'), 2);
      expect(intimacy.getTypingDelay('高冷'), 2);
      expect(intimacy.getTypingDelay(''), 2);
    });
  });

  group('updateMessageStats / avgMessageLength', () {
    test('tracks message lengths', () {
      intimacy.updateMessageStats('chat1', 'hello');
      intimacy.updateMessageStats('chat1', 'world!!');
      final avg = intimacy.avgMessageLength('chat1');
      expect(avg, (5 + 7) / 2);
    });

    test('returns 0 for unknown chat', () {
      expect(intimacy.avgMessageLength('unknown'), 0);
    });
  });
}
