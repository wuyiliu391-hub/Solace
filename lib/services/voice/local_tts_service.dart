// 语音合成（TTS）服务层接口。
//
// 引擎为**云端**供应商，通过 provider 选择切换（见 TtsProvider）：
//   - MiMo（小米开放平台，OpenAI 兼容，api.xiaomimimo.com）
//   - Fish Audio（api.fish.audio，S2.1 Pro）
// 早期版本曾规划本地 MOSS-TTS-Nano 推理，但该模型从未落地，TTS 一直是云端，
// 因此这里不再有「本地模型」概念。仍保留在本地运行的只有 STT 与 VAD
// （见 local_stt_service.dart / voice_vad_service.dart，与 TTS 无关）。
//
// API Key 在设置页「语音设置」配置（SharedPreferences）。
// MiMo 的参考音频样本由 VoiceProfileStore 保存，每次合成上传给 voiceclone 模型；
// Fish Audio 则需先建音色拿 reference_id 并持久化，见 FishAudioTtsService。

import 'package:shared_preferences/shared_preferences.dart';

import 'fish_audio_tts_service.dart';
import 'mimo_tts_service.dart';

/// TTS 供应商。
enum TtsProvider {
  mimo('MiMo', 'mimo-tts'),
  fishAudio('Fish Audio', 'fish-audio');

  final String label;
  final String providerName;
  const TtsProvider(this.label, this.providerName);

  static TtsProvider fromName(String? name) => switch (name) {
        'fish-audio' => TtsProvider.fishAudio,
        _ => TtsProvider.mimo,
      };
}

/// 语音合成结果。
class TtsResult {
  /// 生成的音频文件绝对路径（wav）。
  final String audioFilePath;

  /// 音频时长（毫秒）；0 表示未知（未解码）。
  final int durationMs;

  /// 本次是否复用已缓存的声纹（v1 每次确定性重算，恒为 false，但音色不变）。
  final bool reusedCachedVoice;

  const TtsResult({
    required this.audioFilePath,
    required this.durationMs,
    this.reusedCachedVoice = false,
  });
}

/// 角色声纹档案：参考音频（3~5s wav）+ 可选文字稿。
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

/// TTS 服务接口。两种云端供应商都实现它。
abstract class TtsService {
  /// 功能总开关（编译期，见 AppConfig.localTtsEnabled）。
  bool get enabled;

  /// 配置（API Key）是否就位。
  Future<bool> get isModelReady;

  /// 为角色注册/更新参考音频与文字稿。
  Future<VoiceProfile> setReferenceAudio(
    String characterId,
    String referenceAudioPath,
    String referenceText,
  );

  /// 合成一段角色语音并写出音频文件。
  Future<TtsResult> synthesize(String characterId, String text);

  /// 带导演指令的合成。[style] 为导演模式指令文本。
  /// Fish Audio 不接受导演指令，实现里会忽略该参数。
  Future<TtsResult> synthesizeWithStyle(
    String characterId,
    String text, {
    String style = '',
    int maxRetries = 3,
  });
}

/// 占位实现（测试/降级用）：不可用。
class TtsServiceStub implements TtsService {
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
  Future<TtsResult> synthesize(String characterId, String text) async {
    throw UnimplementedError('TtsServiceStub 未接入推理');
  }

  @override
  Future<TtsResult> synthesizeWithStyle(
    String characterId,
    String text, {
    String style = '',
    int maxRetries = 3,
  }) async {
    throw UnimplementedError('TtsServiceStub 未接入推理');
  }
}

/// 当前选中的 TTS 供应商（SharedPreferences，默认 MiMo）。
class TtsProviderStore {
  static const _kProvider = 'tts_provider';

  static Future<TtsProvider> load() async {
    final prefs = await SharedPreferences.getInstance();
    return TtsProvider.fromName(prefs.getString(_kProvider));
  }

  static Future<void> save(TtsProvider p) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kProvider, p.providerName);
  }
}

/// 按 provider 构造对应实现。
TtsService createTtsService(TtsProvider provider) => switch (provider) {
      TtsProvider.mimo => MiMoTtsService(),
      TtsProvider.fishAudio => FishAudioTtsService(),
    };

/// 读取当前设置并构造对应实现（需要 provider 生效时用这个）。
Future<TtsService> createTtsServiceFromSettings() async =>
    createTtsService(await TtsProviderStore.load());
