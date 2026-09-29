import 'package:flutter_test/flutter_test.dart';
import 'package:solace/utils/sentiment_analyzer.dart';

void main() {
  group('SentimentAnalyzer.analyze', () {
    test('returns neutral for empty string', () {
      final result = SentimentAnalyzer.analyze('');
      expect(result.type, SentimentType.neutral);
      expect(result.score, 0);
    });

    test('returns neutral for whitespace-only', () {
      final result = SentimentAnalyzer.analyze('   ');
      expect(result.type, SentimentType.neutral);
    });

    test('detects positive sentiment', () {
      final result = SentimentAnalyzer.analyze('谢谢你，真的好喜欢你');
      expect(result.score, greaterThan(0));
      expect(result.type,
          isIn([SentimentType.positive, SentimentType.veryPositive]));
    });

    test('detects negative sentiment', () {
      final result = SentimentAnalyzer.analyze('讨厌你，滚开');
      expect(result.score, lessThan(0));
      expect(result.type,
          isIn([SentimentType.negative, SentimentType.veryNegative]));
    });

    test('detects very negative sentiment', () {
      final result = SentimentAnalyzer.analyze('你这个混蛋，去死吧');
      expect(result.score, lessThan(-2));
      expect(result.type, SentimentType.veryNegative);
    });

    test('positive words increase score', () {
      final result = SentimentAnalyzer.analyze('爱你 想你 晚安');
      expect(result.score, greaterThanOrEqualTo(2));
    });

    test('negative words decrease score', () {
      final result = SentimentAnalyzer.analyze('讨厌 烦 恶心');
      expect(result.score, lessThanOrEqualTo(-3));
    });

    test('mixed sentiment nets correctly', () {
      final result = SentimentAnalyzer.analyze('喜欢你但是讨厌你的行为');
      // Should have both positive and negative, net could be either way
      expect(result.type, isNot(SentimentType.neutral));
    });

    test('emoji detection works', () {
      final positive = SentimentAnalyzer.analyze('hello 😊😍');
      expect(positive.score, greaterThan(0));

      final negative = SentimentAnalyzer.analyze('hello 😡😤');
      expect(negative.score, lessThan(0));
    });

    test('exclamation marks amplify negative', () {
      final withExclaim = SentimentAnalyzer.analyze('讨厌！！！');
      final without = SentimentAnalyzer.analyze('讨厌');
      expect(withExclaim.score, lessThanOrEqualTo(without.score));
    });

    test('case insensitive', () {
      final result = SentimentAnalyzer.analyze('HATE stupid');
      expect(result.score, lessThan(0));
    });
  });
}
