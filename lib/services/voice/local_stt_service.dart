// 本地离线语音转文本（ASR）服务层。
//
// 引擎：sherpa-onnx（k2-fsa，Apache-2.0），模型：SenseVoice（中英日韩粤语，
//       int8 ONNX，~229MB）。模型文件不内置，运行时按需下载（见 VoiceModelManager）。
//
// 输入为 16kHz 单声道音频（wav 路径或直接 Float32 样本）；非 16k 时做线性重采样。
// 推理跑在后台 isolate，避免阻塞 UI。

import 'dart:isolate';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

import '../../config/app_config.dart';
import 'voice_model_manager.dart';

/// 语音转文本结果。
class LocalSttResult {
  final String text;

  /// 可选：逐 token 时间戳（秒）。SenseVoice 支持，暂无 UI 消费，保留字段。
  final List<double> timestamps;

  const LocalSttResult({required this.text, this.timestamps = const []});
}

/// 本地 STT 服务接口。
abstract class LocalSttService {
  /// 功能总开关（编译期，见 AppConfig.localSttEnabled）。
  bool get enabled;

  /// 模型文件是否已就位。
  Future<bool> get isModelReady;

  /// 转写一段 wav 音频为文本。
  Future<LocalSttResult> transcribe(String audioFilePath);

  /// 直接转写 16kHz 单声道 Float32 样本（通话链路用，避免文件 IO）。
  Future<LocalSttResult> transcribeSamples(
    Float32List samples, {
    int sampleRate = 16000,
  });
}

/// 真实实现：sherpa-onnx SenseVoice。
class SherpaOnnxLocalSttService implements LocalSttService {
  @override
  bool get enabled => AppConfig.localSttEnabled;

  @override
  Future<bool> get isModelReady async =>
      await VoiceModelManager.instance.isReady(VoiceModelKind.senseVoiceStt);

  @override
  Future<LocalSttResult> transcribe(String audioFilePath) async {
    if (!enabled) {
      throw StateError('本地语音转文本未启用（AppConfig.localSttEnabled=false）');
    }
    final ready = await isModelReady;
    if (!ready) {
      throw StateError('SenseVoice 模型未就位，请先手动导入');
    }
    final dir = await VoiceModelManager.instance.modelDir(VoiceModelKind.senseVoiceStt);
    final args = _SttArgs(
      modelPath: p.join(dir.path, 'model.int8.onnx'),
      tokensPath: p.join(dir.path, 'tokens.txt'),
      audioPath: audioFilePath,
    );
    return await Isolate.run(() => _transcribeSync(args));
  }

  @override
  Future<LocalSttResult> transcribeSamples(
    Float32List samples, {
    int sampleRate = 16000,
  }) async {
    if (!enabled) {
      throw StateError('本地语音转文本未启用（AppConfig.localSttEnabled=false）');
    }
    final ready = await isModelReady;
    if (!ready) {
      throw StateError('SenseVoice 模型未就位，请先手动导入');
    }
    final dir = await VoiceModelManager.instance.modelDir(VoiceModelKind.senseVoiceStt);
    final args = _SttArgs(
      modelPath: p.join(dir.path, 'model.int8.onnx'),
      tokensPath: p.join(dir.path, 'tokens.txt'),
      samples: samples,
      sampleRate: sampleRate,
    );
    return await Isolate.run(() => _transcribeSync(args));
  }
}

/// 占位实现（测试/降级用）。
class LocalSttServiceStub implements LocalSttService {
  @override
  bool get enabled => false;

  @override
  Future<bool> get isModelReady async => false;

  @override
  Future<LocalSttResult> transcribe(String audioFilePath) async {
    throw UnimplementedError('LocalSttServiceStub 未接入推理');
  }

  @override
  Future<LocalSttResult> transcribeSamples(
    Float32List samples, {
    int sampleRate = 16000,
  }) async {
    throw UnimplementedError('LocalSttServiceStub 未接入推理');
  }
}

/// 默认实例。
LocalSttService createLocalSttService() => SherpaOnnxLocalSttService();

// ─────────────────────────────────────────────────────────────────────────────

class _SttArgs {
  final String modelPath;
  final String tokensPath;
  final String? audioPath;
  final Float32List? samples;
  final int sampleRate;

  _SttArgs({
    required this.modelPath,
    required this.tokensPath,
    this.audioPath,
    this.samples,
    this.sampleRate = 16000,
  });
}

LocalSttResult _transcribeSync(_SttArgs args) {
  sherpa_onnx.initBindings();

  final senseVoice = sherpa_onnx.OfflineSenseVoiceModelConfig(
    model: args.modelPath,
    language: 'auto',
    useInverseTextNormalization: true,
  );
  final modelConfig = sherpa_onnx.OfflineModelConfig(
    senseVoice: senseVoice,
    tokens: args.tokensPath,
    numThreads: 4,
    debug: false,
  );
  final recognizer = sherpa_onnx.OfflineRecognizer(
    sherpa_onnx.OfflineRecognizerConfig(model: modelConfig),
  );
  try {
    Float32List samples;
    int sampleRate;
    if (args.samples != null) {
      samples = args.samples!;
      sampleRate = args.sampleRate;
    } else {
      final wave = sherpa_onnx.readWave(args.audioPath!);
      if (wave.samples.isEmpty || wave.sampleRate == 0) {
        throw StateError('音频读取失败: ${args.audioPath}');
      }
      samples = wave.samples;
      sampleRate = wave.sampleRate;
    }
    final resampled = _resampleTo16k(samples, sampleRate);

    final stream = recognizer.createStream();
    try {
      stream.acceptWaveform(samples: resampled, sampleRate: 16000);
      recognizer.decode(stream);
      final result = recognizer.getResult(stream);
      return LocalSttResult(text: result.text, timestamps: result.timestamps);
    } finally {
      stream.free();
    }
  } finally {
    recognizer.free();
  }
}

/// 线性重采样到 16kHz（单声道）。已是 16k 时原样返回。
Float32List _resampleTo16k(Float32List samples, int srcRate) {
  const dstRate = 16000;
  if (srcRate == dstRate) return samples;
  if (samples.isEmpty) return samples;

  final n = (samples.length * dstRate / srcRate).round();
  final out = Float32List(n);
  final step = samples.length / n;
  for (int i = 0; i < n; i++) {
    final pos = i * step;
    final i0 = pos.floor();
    final i1 = (i0 + 1) < samples.length ? i0 + 1 : i0;
    final frac = pos - i0;
    out[i] = samples[i0] * (1 - frac) + samples[i1] * frac;
  }
  return out;
}
