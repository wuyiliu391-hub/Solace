import 'package:flutter_test/flutter_test.dart';
import 'package:solace/utils/response_decoder.dart';

void main() {
  group('ResponseDecoder', () {
    test('repairs common GBK mojibake phrases', () {
      expect(
        ResponseDecoder.repairText('鐢ㄦ埛鍙戦€佷簡涓€寮犲浘鐗'),
        '用户发送了一张图片',
      );
      // 验证 repairText 能识别并修复 GBK mojibake 片段
      final repaired = ResponseDecoder.repairText('鍥炲锛氫綘濂�');
      expect(repaired.contains('回复'), isTrue);
    });
  });
}
