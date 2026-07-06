import 'package:flutter_test/flutter_test.dart';
import 'package:solace/services/ai_moment_service.dart';

void main() {
  group('AIMomentService content extraction', () {
    test('returns content inside <MOMENT> tag and strips <THINK>', () {
      const raw = '<THINK>我需要发一条开心的朋友圈。</THINK><MOMENT>今天阳光特别好，忍不住想出去走走～</MOMENT>';
      final result = AIMomentService.extractFinalMomentContent(raw);
      expect(result, '今天阳光特别好，忍不住想出去走走～');
    });

    test('returns whole text when no tags present but cleanable reasoning remains', () {
      const raw = '用户让我分享生活，那我就分享一下吧。今天有点累，想早点休息。';
      final result = AIMomentService.extractFinalMomentContent(raw);
      expect(result, contains('今天有点累'));
      expect(result, isNot(contains('用户让我')));
    });

    test('trim empty or whitespace-only content to empty', () {
      const raw = '<MOMENT>   </MOMENT>';
      final result = AIMomentService.extractFinalMomentContent(raw);
      expect(result, isEmpty);
    });

    test('keeps plain output without tags as final content', () {
      const raw = '刚吃完一碗热腾腾的拉面，整个人都活过来了。';
      final result = AIMomentService.extractFinalMomentContent(raw);
      expect(result, '刚吃完一碗热腾腾的拉面，整个人都活过来了。');
    });
  });
}
