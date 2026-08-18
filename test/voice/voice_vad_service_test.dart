// VAD 服务测试：未初始化状态下的安全语义。
// Silero VAD 的 native 推理（sherpa-onnx）依赖模型文件与原生库，
// 在纯 Dart 单测环境不可用，因此这里只验证「未 init 时全部操作
// 静默空操作、不崩溃」的防御性行为——这正是通话控制器依赖的保证。

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:solace/services/voice/voice_vad_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VoiceVadService 未初始化防御', () {
    test('hasSegment 恒为 false', () {
      final vad = VoiceVadService();
      expect(vad.hasSegment, isFalse);
    });

    test('takeSegment 返回 null', () {
      final vad = VoiceVadService();
      expect(vad.takeSegment(), isNull);
    });

    test('acceptSamples 喂入空数据不崩溃', () {
      final vad = VoiceVadService();
      // 内部 _vad 为 null 时直接 return
      vad.acceptSamples(Float32List(0));
      vad.acceptSamples(Float32List(512));
    });

    test('reset / dispose 幂等且不崩溃', () async {
      final vad = VoiceVadService();
      vad.reset();
      await vad.dispose();
      await vad.dispose(); // 二次 dispose：_vad 已置 null，仍安全
    });
  });
}
