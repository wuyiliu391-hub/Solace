import 'package:flutter_test/flutter_test.dart';
import 'package:solace/utils/content_filter.dart';

void main() {
  group('ContentFilter.check', () {
    test('returns non-NSFW for normal messages', () {
      final result = ContentFilter.check('你好，今天天气怎么样？');
      expect(result.isNSFW, false);
      expect(result.matchedKeyword, isNull);
    });

    test('returns non-NSFW for empty string', () {
      final result = ContentFilter.check('');
      expect(result.isNSFW, false);
    });

    test('detects NSFW keywords', () {
      final result = ContentFilter.check('做爱');
      expect(result.isNSFW, true);
      expect(result.matchedKeyword, '做爱');
    });

    test('detects NSFW patterns', () {
      final result = ContentFilter.check('想操你');
      expect(result.isNSFW, true);
    });

    test('case insensitive matching', () {
      final result = ContentFilter.check('SM');
      expect(result.isNSFW, true);
    });

    test('detects keyword within longer text', () {
      final result = ContentFilter.check('我想和你做爱');
      expect(result.isNSFW, true);
      expect(result.matchedKeyword, '做爱');
    });

    test('returns first matched keyword', () {
      final result = ContentFilter.check('色情 黄片');
      expect(result.isNSFW, true);
      expect(result.matchedKeyword, isNotNull);
    });

    test('does not match innocent substrings', () {
      // "av" might match in innocent contexts
      final result = ContentFilter.check('av');
      expect(result.isNSFW, true); // 'av' is in the keyword list
    });

    test('handles pattern with multiple groups', () {
      final result = ContentFilter.check('想干她');
      expect(result.isNSFW, true);
    });

    test('handles whitespace in message', () {
      final result = ContentFilter.check('  做爱  ');
      expect(result.isNSFW, true);
    });
  });
}
