// 语音录制服务：封装 record 插件。
// 语音转写/通话用 16kHz 单声道（SenseVoice 期望输入）；
// 音色克隆参考音频用 48kHz 双声道（MOSS codec encode 期望输入）。
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

class VoiceRecorderService {
  final AudioRecorder _recorder = AudioRecorder();
  String? _currentPath;

  /// 是否正在录音（由本层自维护状态，避免依赖插件的状态流）。
  bool get isRecording => _currentPath != null;

  Future<bool> hasPermission() => _recorder.hasPermission();

  /// 开始录音。返回录音文件的最终路径。
  /// [sampleRate] 默认 16000（语音转写用）；音色克隆参考音频请传 48000 并 [channels]=2。
  Future<String> start({int sampleRate = 16000, int channels = 1}) async {
    await stop();
    final dir = await getTemporaryDirectory();
    _currentPath =
        p.join(dir.path, 'voice_${DateTime.now().millisecondsSinceEpoch}.wav');
    await _recorder.start(
      RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: sampleRate,
        numChannels: channels,
      ),
      path: _currentPath!,
    );
    return _currentPath!;
  }

  /// 停止录音。返回 wav 路径（失败为 null）。
  Future<String?> stop() async {
    final path = await _recorder.stop();
    _currentPath = null;
    return path;
  }

  /// 开始流式录音（实时语音通话用）：返回 PCM16 字节流。
  /// 采样率 16kHz 单声道，带噪声抑制；echoCancel 因通话半双工（放音时关麦）默认不开。
  Future<Stream<Uint8List>> startStream() async {
    await stop();
    return _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
        noiseSuppress: true,
        autoGain: true,
        echoCancel: false,
        streamBufferSize: 4096,
      ),
    );
  }

  /// 取消当前录音并删除文件。
  Future<void> cancel() async {
    final path = await stop();
    if (path != null) {
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }

  Future<void> dispose() => _recorder.dispose();
}
