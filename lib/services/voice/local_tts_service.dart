// 语音合成（角色语音）服务层接口。
//
// 引擎：MiMo-V2.5-TTS（小米开放平台，OpenAI 兼容 API，限时免费）。
//   - mimo-v2.5-tts-voiceclone：参考音频样本复刻音色（默认）
//   - mimo-v2.5-tts：预置精品音色
//   - mimo-v2.5-tts-voicedesign：文本描述设计音色
//
// API Key 在设置页「MiMo TTS 设置」配置（SharedPreferences）。
// 参考音频样本由 VoiceProfileStore 保存，每次合成上传给 voiceclone 模型。

import 'mimo_tts_service.dart';

/// 本地语音合成结果。
class LocalTtsResult {
  /// 生成的音频文件绝对路径（wav）。
  final String audioFilePath;

  /// 音频时长（毫秒）。
  final int durationMs;

  /// 本次是否复用已缓存的声纹（v1 每次确定性重算，恒为 false，但音色不变）。
  final bool reusedCachedVoice;

  const LocalTtsResult({
    required this.audioFilePath,
    required this.durationMs,
    this.reusedCachedVoice = false,
  });
}

/// 角色声纹档案：参考音频（3~5s wav）+ 可选文字稿。
///
/// MOSS-TTS-Nano 不需要文字稿与音频逐字一致（仅作参考展示）。
class VoiceProfile {
  final String characterId;

  /// 参考音频本地路径（wav）。
  final String referenceAudioPath;

  /// 参考音频的逐字文字稿。
  final String referenceText;

  /// 参考音频文件的 sha1，用于检测用户是否更换了参考音频。
  final String referenceHash;

  VoiceProfile({
    required this.characterId,
    required this.referenceAudioPath,
    required this.referenceText,
    required this.referenceHash,
  });
}

/// 本地 TTS 服务接口。
abstract class LocalTtsService {
  /// 功能总开关（编译期，见 AppConfig.localTtsEnabled）。
  bool get enabled;

  /// 模型文件是否已就位。
  Future<bool> get isModelReady;

  /// 为角色注册/更新参考音频与文字稿。
  Future<VoiceProfile> setReferenceAudio(
    String characterId,
    String referenceAudioPath,
    String referenceText,
  );

  /// 合成一段角色语音并写出 wav。
  Future<LocalTtsResult> synthesize(String characterId, String text);
}

/// 占位实现（测试/降级用）：不加载原生库。
class LocalTtsServiceStub implements LocalTtsService {
  @override
  bool get enabled => false;

  @override
  Future<bool> get isModelReady async => false;

  @override
  Future<VoiceProfile> setReferenceAudio(
    String characterId,
    String referenceAudioPath,
    String referenceText,
  ) async {
    return VoiceProfile(
      characterId: characterId,
      referenceAudioPath: referenceAudioPath,
      referenceText: referenceText,
      referenceHash: referenceText,
    );
  }

  @override
  Future<LocalTtsResult> synthesize(String characterId, String text) async {
    throw UnimplementedError('LocalTtsServiceStub 未接入推理');
  }
}

/// 默认实例：MiMo-V2.5-TTS 云端合成（API Key 在设置页配置）。
LocalTtsService createLocalTtsService() => MiMoTtsService();
