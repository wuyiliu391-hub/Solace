// MiMo-V2.5-TTS 云端语音合成服务（小米 MiMo 开放平台）。
//
// 接口：OpenAI 兼容（base_url = https://api.xiaomimimo.com/v1）
// 模型：
//   mimo-v2.5-tts          预置音色（流式）
//   mimo-v2.5-tts-voiceclone  音色克隆（音频样本复刻）
//   mimo-v2.5-tts-voicedesign 音色设计（文本描述）
//
// 音色来源：VoiceProfileStore 保存的用户参考音频样本（voice_refs/），
// 每次合成时把样本作为 audio.voice 传入 voiceclone 模型。
//
// API Key 配置：设置页 → MiMo TTS 设置（存 ai_configs 表 providerName=mimo-tts）。

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/app_config.dart';
import 'local_tts_service.dart';

/// MiMo TTS 配置（持久化在 SharedPreferences）。
class MiMoTtsConfig {
  static const String providerName = 'mimo-tts';
  static const String defaultBaseUrl = 'https://api.xiaomimimo.com/v1';
  static const String defaultModel = 'mimo-v2.5-tts-voiceclone';

  final String apiKey;
  final String baseUrl;
  final String model;

  const MiMoTtsConfig({
    required this.apiKey,
    this.baseUrl = defaultBaseUrl,
    this.model = defaultModel,
  });

  bool get isValid => apiKey.trim().isNotEmpty;
}

/// MiMo TTS 配置存储（SharedPreferences，服务层可直接访问）。
class MiMoTtsConfigStore {
  static const _kKey = 'mimo_tts_api_key';
  static const _kBaseUrl = 'mimo_tts_base_url';
  static const _kModel = 'mimo_tts_model';

  static Future<MiMoTtsConfig?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final apiKey = prefs.getString(_kKey) ?? '';
    if (apiKey.isEmpty) return null;
    return MiMoTtsConfig(
      apiKey: apiKey,
      baseUrl: prefs.getString(_kBaseUrl) ?? MiMoTtsConfig.defaultBaseUrl,
      model: prefs.getString(_kModel) ?? MiMoTtsConfig.defaultModel,
    );
  }

  static Future<void> save(String apiKey, {String? baseUrl, String? model}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kKey, apiKey.trim());
    if (baseUrl != null) await prefs.setString(_kBaseUrl, baseUrl.trim());
    if (model != null) await prefs.setString(_kModel, model.trim());
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kKey);
  }
}

/// MiMo TTS 服务实现（OpenAI 兼容 chat.completions + audio 参数）。
///
/// 深度适配（调研自官方文档 + 官方 MiMo-Skills 仓库）：
/// - 导演模式：role:user 传「角色/场景/指导」三层指令（voiceclone 完整继承控制能力）
/// - 音频标签：assistant 文本内嵌 (风格)[内联标签]，官方推荐克制使用
/// - 无记忆：每次调用重传样本；本地按角色缓存 base64（文件 sha1 变化才失效）
/// - 随机性：TTS 有随机性，官方建议多生成挑选；429 指数退避重试
class MiMoTtsService implements LocalTtsService {
  final Map<String, VoiceProfile> _profiles = {};

  /// 角色样本 base64 缓存（key: characterId，value: data URL）。
  final Map<String, String> _sampleCache = {};

  /// 角色样本文件的 sha1 缓存（用于检测样本更换）。
  final Map<String, String> _sampleHashCache = {};

  @override
  bool get enabled => AppConfig.localTtsEnabled;

  @override
  Future<bool> get isModelReady async {
    final config = await MiMoTtsConfigStore.load();
    return config != null && config.isValid;
  }

  @override
  Future<VoiceProfile> setReferenceAudio(
    String characterId,
    String referenceAudioPath,
    String referenceText,
  ) async {
    final hash = await sha1.bind(File(referenceAudioPath).openRead()).first;
    final profile = VoiceProfile(
      characterId: characterId,
      referenceAudioPath: referenceAudioPath,
      referenceText: referenceText,
      referenceHash: hash.toString(),
    );
    _profiles[characterId] = profile;
    // 样本变更 → 失效 base64 缓存
    _sampleCache.remove(characterId);
    _sampleHashCache.remove(characterId);
    return profile;
  }

  @override
  Future<LocalTtsResult> synthesize(String characterId, String text) =>
      synthesizeWithStyle(characterId, text);

  /// 合成带导演指令的角色语音。
  ///
  /// [style]：导演模式指令文本（角色/场景/指导三层，放入 role:user）。
  /// 为空时不传 user 内容（等效官方空串）。
  /// [maxRetries]：429 退避重试次数（默认 3）。
  Future<LocalTtsResult> synthesizeWithStyle(
    String characterId,
    String text, {
    String style = '',
    int maxRetries = 3,
  }) async {
    if (!enabled) {
      throw StateError('本地语音合成未启用（AppConfig.localTtsEnabled=false）');
    }
    final profile = _profiles[characterId];
    if (profile == null) {
      throw StateError('角色 $characterId 未设置参考音频，请先到「音色克隆」页面录制');
    }
    final config = await MiMoTtsConfigStore.load();
    if (config == null || !config.isValid) {
      throw StateError('MiMo TTS API Key 未配置，请到「我」→「设置」→「MiMo TTS 设置」填写');
    }

    // 样本 base64（内存缓存，文件 sha1 变更时失效）
    final voiceData = await _sampleDataUrl(profile);

    final tmp = await getTemporaryDirectory();
    final outputPath = p.join(
        tmp.path, 'mimo_tts_${DateTime.now().millisecondsSinceEpoch}.wav');

    // 调 MiMo voiceclone API（带重试）
    final audioBytes = await _synthesizeWithConfig(
      config,
      text,
      voiceData,
      style: style,
      maxRetries: maxRetries,
    );

    // 写 wav 文件
    await File(outputPath).writeAsBytes(audioBytes, flush: true);
    final durationMs = _wavDurationMs(audioBytes);
    return LocalTtsResult(
      audioFilePath: outputPath,
      durationMs: durationMs,
    );
  }

  /// 生成多版语音供挑选（官方建议：TTS 有随机性，多生成几次挑选）。
  ///
  /// 返回 [count] 个合成结果（wav 文件路径列表），同一输入每次结果不同。
  Future<List<LocalTtsResult>> synthesizeMultiple(
    String characterId,
    String text, {
    String style = '',
    int count = 3,
    int maxRetries = 3,
  }) async {
    final results = <LocalTtsResult>[];
    for (var i = 0; i < count; i++) {
      final r = await synthesizeWithStyle(
        characterId,
        text,
        style: style,
        maxRetries: maxRetries,
      );
      results.add(r);
    }
    return results;
  }

  /// 生成参考音频的 data URL（mp3/wav → base64），带角色级内存缓存。
  Future<String> _sampleDataUrl(VoiceProfile profile) async {
    final cached = _sampleCache[profile.characterId];
    final cachedHash = _sampleHashCache[profile.characterId];
    if (cached != null && cachedHash == profile.referenceHash) {
      return cached;
    }
    final refFile = File(profile.referenceAudioPath);
    if (!await refFile.exists()) {
      throw StateError('参考音频文件不存在: ${profile.referenceAudioPath}');
    }
    final sampleBytes = await refFile.readAsBytes();
    if (sampleBytes.length > 10 * 1024 * 1024) {
      throw StateError('参考音频超过 10MB 上限（base64 后），请裁剪后重试');
    }
    final mime = refFile.path.toLowerCase().endsWith('.mp3')
        ? 'audio/mpeg'
        : 'audio/wav';
    final dataUrl = 'data:$mime;base64,${base64Encode(sampleBytes)}';
    _sampleCache[profile.characterId] = dataUrl;
    _sampleHashCache[profile.characterId] = profile.referenceHash;
    return dataUrl;
  }

  /// 调 OpenAI 兼容接口。返回 wav 字节。429 指数退避重试。
  Future<Uint8List> _synthesizeWithConfig(
    MiMoTtsConfig config,
    String text,
    String voiceData, {
    String style = '',
    int maxRetries = 3,
  }) async {
    final uri = Uri.parse('${config.baseUrl}/chat/completions');

    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      final body = jsonEncode({
        'model': config.model,
        'messages': [
          {'role': 'user', 'content': style},
          {'role': 'assistant', 'content': text},
        ],
        'audio': {
          'format': 'wav',
          'voice': voiceData,
        },
      });
      final resp = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${config.apiKey}',
            },
            body: body,
          )
          .timeout(const Duration(seconds: 120));

      if (resp.statusCode == 429 && attempt < maxRetries) {
        // 指数退避：1s, 2s, 4s...
        final delay = Duration(seconds: 1 << attempt);
        await Future<void>.delayed(delay);
        continue;
      }
      if (resp.statusCode != 200) {
        throw StateError(
            'MiMo TTS 请求失败 (${resp.statusCode}): ${_extractError(resp.body)}');
      }
      final json =
          jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final audio = (json['choices'] as List?)?.firstOrNull?['message']?['audio'];
      if (audio is Map && audio['data'] is String) {
        return base64Decode(audio['data'] as String);
      }
      throw StateError('MiMo TTS 响应缺少音频数据');
    }
    throw StateError('MiMo TTS 请求重试次数用尽');
  }

  String _extractError(String body) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      final err = json['error'];
      if (err is Map) return err['message']?.toString() ?? body;
      if (err is String) return err;
      return json['message']?.toString() ?? body;
    } catch (_) {
      return body.length > 300 ? body.substring(0, 300) : body;
    }
  }

  int _wavDurationMs(Uint8List wavBytes) {
    try {
      final data = ByteData.sublistView(wavBytes);
      if (wavBytes.length < 44) return 0;
      final byteRate = data.getUint32(28, Endian.little);
      if (byteRate == 0) return 0;
      // data chunk 大小
      var offset = 12;
      while (offset + 8 <= wavBytes.length) {
        final id = data.getUint32(offset, Endian.little);
        final size = data.getUint32(offset + 4, Endian.little);
        if (id == 0x61746164) {
          // 'data'
          return (size * 1000 / byteRate).round();
        }
        offset += 8 + size + (size & 1);
      }
      return 0;
    } catch (_) {
      return 0;
    }
  }
}
