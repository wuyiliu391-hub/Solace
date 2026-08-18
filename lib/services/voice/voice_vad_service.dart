// 本地语音活动检测（VAD）服务：Silero VAD（sherpa-onnx，Apache-2.0，~644KB）。
//
// 用于实时语音通话的「你说完自动断句」：麦克风流式喂入 16kHz Float32 样本，
// 检测到一段语音 + 后续静音后，产出这段语音的样本（供 SenseVoice 转写）。
//
// 模型极小、推理极快（32ms 窗口内几毫秒），直接跑在调用方 isolate（主 isolate），
// 与 TTS/STT 的后台 isolate 互不干扰；每个 isolate 各自 initBindings()。
//
// 诊断日志：`[VAD]` 前缀，每一步 native 调用前后打点，
// 崩溃时最后一条日志即崩溃点。

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

import 'voice_model_manager.dart';

class VoiceVadService {
  sherpa_onnx.VoiceActivityDetector? _vad;
  int _chunkCount = 0;
  bool _lastDetected = false;

  /// 初始化 VAD（需先确保 Silero VAD 模型已下载）。
  Future<void> init({
    double threshold = 0.5,
    double minSilenceDuration = 0.6,
    double minSpeechDuration = 0.25,
    double maxSpeechDuration = 15.0,
  }) async {
    if (_vad != null) return;
    final dir =
        await VoiceModelManager.instance.modelDir(VoiceModelKind.sileroVad);
    final modelPath = p.join(dir.path, 'silero_vad.onnx');
    final modelExists = await File(modelPath).exists();
    debugPrint('[VAD] init: modelPath=$modelPath exists=$modelExists');

    sherpa_onnx.initBindings();
    debugPrint('[VAD] init: initBindings done');
    final config = sherpa_onnx.VadModelConfig(
      sileroVad: sherpa_onnx.SileroVadModelConfig(
        model: modelPath,
        threshold: threshold,
        minSilenceDuration: minSilenceDuration,
        minSpeechDuration: minSpeechDuration,
        windowSize: 512,
        maxSpeechDuration: maxSpeechDuration,
      ),
      sampleRate: 16000,
      numThreads: 1,
      provider: 'cpu',
      debug: false,
    );
    debugPrint('[VAD] init: creating VoiceActivityDetector...');
    _vad = sherpa_onnx.VoiceActivityDetector(
      config: config,
      bufferSizeInSeconds: 30,
    );
    debugPrint('[VAD] init: created OK, ptr=${_vad!.ptr.address}');
  }

  /// 喂入一段 16kHz Float32 单声道样本（麦克风流式增量）。
  void acceptSamples(Float32List samples) {
    final vad = _vad;
    if (vad == null) return;
    _chunkCount++;
    if (_chunkCount % 50 == 1) {
      debugPrint('[VAD] acceptWaveform chunk#$_chunkCount len=${samples.length}');
    }
    vad.acceptWaveform(samples);
  }

  /// 是否已有检测完成的语音段可取出。
  bool get hasSegment {
    final vad = _vad;
    if (vad == null) return false;
    final d = vad.isDetected();
    if (d != _lastDetected) {
      _lastDetected = d;
      debugPrint('[VAD] isDetected -> $d');
    }
    return d;
  }

  /// 取出最早的一个完成语音段（16kHz Float32）；没有则返回 null。
  ///
  /// 注意：sherpa-onnx 1.13.x Android 的 `pop()` 存在 native 崩溃
  /// （SherpaOnnxVoiceActivityDetectorPop SIGSEGV，GitHub issue 未修），
  /// 因此改用 `clear()` 清空队列规避；半双工回合制一次只取一段，语义等价。
  Float32List? takeSegment() {
    final vad = _vad;
    if (vad == null || !vad.isDetected()) return null;
    debugPrint('[VAD] takeSegment: calling front()...');
    final seg = vad.front();
    debugPrint('[VAD] takeSegment: front() done, samples=${seg.samples.length}');
    final samples = seg.samples;
    debugPrint('[VAD] takeSegment: calling clear()...');
    vad.clear();
    debugPrint('[VAD] takeSegment: clear() done');
    return samples.isEmpty ? null : samples;
  }

  /// 清空缓冲区（挂断/重置时）。
  void reset() {
    debugPrint('[VAD] reset()');
    _vad?.reset();
  }

  Future<void> dispose() async {
    debugPrint('[VAD] dispose()');
    _vad?.free();
    _vad = null;
    debugPrint('[VAD] dispose done');
  }
}