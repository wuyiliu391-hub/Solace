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

import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/app_config.dart';
import 'audio_converter_service.dart';
import 'local_tts_service.dart';
import 'voice_profile_store.dart';

/// MiMo TTS 配置（持久化在 SharedPreferences）。
class MiMoTtsConfig {
  static const String providerName = 'mimo-tts';
  static const String defaultBaseUrl = 'https://api.xiaomimimo.com/v1';
  static const String defaultModel = 'mimo-v2.5-tts-voiceclone';
  static const String defaultPresetModel = 'mimo-v2.5-tts';
  static const String defaultDesignModel = 'mimo-v2.5-tts-voicedesign';

/// 引擎：'voiceclone'（参考音频复刻，默认）、'preset'（内置预置音色）
  /// 或 'voicedesign'（文本描述设计音色）。
  final String engine;
  final String apiKey;
  final String baseUrl;
  final String model;
  final String presetVoice;
  final String voiceDesignPrompt;

  /// 预置音色默认值（官方 mimo_default，中国集群为「冰糖」女声）。
  static const String presetVoices = 'mimo_default';

  const MiMoTtsConfig({
    required this.apiKey,
    this.baseUrl = defaultBaseUrl,
    this.model = defaultModel,
    this.engine = 'voiceclone',
    this.presetVoice = presetVoices,
    this.voiceDesignPrompt = '',
  });

  bool get isValid => apiKey.trim().isNotEmpty;
  bool get usePreset => engine == 'preset';
  bool get useVoicedesign => engine == 'voicedesign';

  /// 当前引擎对应的模型 ID。
  String get effectiveModel => switch (engine) {
        'preset' => defaultPresetModel,
        'voicedesign' => defaultDesignModel,
        _ => model,
      };
}

/// MiMo 内置预置音色（mimo-v2.5-tts 模型专用）。
class MiMoPresetVoices {
  MiMoPresetVoices._();

  /// (显示名, Voice ID)。实测 MiMo 服务端仅真正区分以下音色
  /// （2026-08-18 实测：茉莉/白桦/Mia/Chloe 全部静默回退同一默认女声，
  /// 字节大小一致；Dean/Milo 为男声、mimo_default 为默认女声）。
  /// 为避免「切换音色无效」的假象，只列出服务端真实生效的 ID。
  static const List<({String label, String id})> all = [
    (label: 'MiMo-默认（女声）', id: 'mimo_default'),
    (label: 'Dean（男声）', id: 'Dean'),
    (label: 'Milo（男声）', id: 'Milo'),
  ];
}

/// MiMo TTS 配置存储（SharedPreferences，服务层可直接访问）。
class MiMoTtsConfigStore {
  static const _kKey = 'mimo_tts_api_key';
  static const _kBaseUrl = 'mimo_tts_base_url';
  static const _kModel = 'mimo_tts_model';
  static const _kEngine = 'mimo_tts_engine';
  static const _kPresetVoice = 'mimo_tts_preset_voice';
  static const _kDesignPrompt = 'mimo_tts_design_prompt';

  static Future<MiMoTtsConfig?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final apiKey = prefs.getString(_kKey) ?? '';
    if (apiKey.isEmpty) return null;
    return MiMoTtsConfig(
      apiKey: apiKey,
      baseUrl: prefs.getString(_kBaseUrl) ?? MiMoTtsConfig.defaultBaseUrl,
      model: prefs.getString(_kModel) ?? MiMoTtsConfig.defaultModel,
      engine: prefs.getString(_kEngine) ?? 'voiceclone',
      presetVoice:
          prefs.getString(_kPresetVoice) ?? MiMoTtsConfig.presetVoices,
      voiceDesignPrompt: prefs.getString(_kDesignPrompt) ?? '',
    );
  }

  static Future<void> save(
    String apiKey, {
    String? baseUrl,
    String? model,
    String? engine,
    String? presetVoice,
    String? voiceDesignPrompt,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kKey, apiKey.trim());
    if (baseUrl != null) await prefs.setString(_kBaseUrl, baseUrl.trim());
    if (model != null) await prefs.setString(_kModel, model.trim());
    if (engine != null) await prefs.setString(_kEngine, engine.trim());
    if (presetVoice != null) {
      await prefs.setString(_kPresetVoice, presetVoice.trim());
    }
    if (voiceDesignPrompt != null) {
      await prefs.setString(_kDesignPrompt, voiceDesignPrompt.trim());
    }
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
  MiMoTtsService() {
    // 预置音色切换时同步清除内存缓存，避免旧样本被复用
    VoiceProfileStore.instance.onPresetChanged = _onPresetChanged;
  }

  final Map<String, VoiceProfile> _profiles = {};

  /// 角色样本 base64 缓存（key: characterId，value: data URL）。
  final Map<String, String> _sampleCache = {};

  /// 角色样本文件的 sha1 缓存（用于检测样本更换）。
  final Map<String, String> _sampleHashCache = {};

  /// 预置音色切换回调：清除该角色的样本 base64 与 hash 缓存，
  /// 避免切换音色后旧的 voiceclone 样本仍被命中。
  void _onPresetChanged(String characterId) {
    _sampleCache.remove(characterId);
    _sampleHashCache.remove(characterId);
    _profiles.remove(characterId);
  }

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
    final config = await MiMoTtsConfigStore.load();
    if (config == null || !config.isValid) {
      throw StateError('MiMo TTS API Key 未配置，请到「我」→「设置」→「MiMo TTS 设置」填写');
    }

    // 角色级预置音色（克隆页选择）**始终优先**于全局引擎：
    // 只要角色设置了预置音色，不管全局选的是哪个引擎都走
    // mimo-v2.5-tts + 该角色的 Voice ID（修复「切换音色后仍用第一个」）。
    final charPreset = await VoiceProfileStore.instance.loadPreset(characterId);
    debugPrint('[MiMoTTS] 引擎决策: charId=$characterId charPreset=$charPreset '
        'globalEngine=${config.engine} globalPreset=${config.presetVoice}');
    final effectiveConfig = charPreset != null
        ? MiMoTtsConfig(
            apiKey: config.apiKey,
            baseUrl: config.baseUrl,
            engine: 'preset',
            presetVoice: charPreset,
          )
        : config;

    // 预置音色引擎无需参考音频；音色设计引擎需在 user 消息传音色描述
    String voiceData;
    VoiceProfile? cloneProfile;
    if (effectiveConfig.usePreset) {
      voiceData = '';
    } else if (effectiveConfig.useVoicedesign) {
      voiceData = '';
    } else {
      final profile = _profiles[characterId];
      if (profile == null) {
        throw StateError('角色 $characterId 未设置参考音频，请先到「音色克隆」页面录制');
      }
      cloneProfile = profile;
      // 样本 base64（内存缓存，文件 sha1 变更时失效）
      voiceData = await _sampleDataUrl(profile);
    }

    final tmp = await getTemporaryDirectory();

    // 音色克隆引擎：合成后做音色相似度检测，漂移（<0.85）自动重合成
    // （最多 2 次）。MiMo 每次合成独立采样有随机漂移，重试到合格为止。
    const similarityThreshold = 0.85;
    const maxRetryForDrift = 2;
    final textPreview = _preview(text, 60);
    Uint8List audioBytes;
    if (cloneProfile != null) {
      audioBytes = Uint8List(0);
      for (var attempt = 0; attempt <= maxRetryForDrift; attempt++) {
        audioBytes = await _synthesizeWithConfig(
          effectiveConfig,
          text,
          voiceData,
          style: style,
          maxRetries: maxRetries,
        );
        final outPath = p.join(tmp.path,
            'mimo_tts_check_${DateTime.now().millisecondsSinceEpoch}.wav');
        await File(outPath).writeAsBytes(audioBytes, flush: true);
        final score = await AudioConverterService.instance
            .voiceSimilarity(cloneProfile.referenceAudioPath, outPath);
        try {
          await File(outPath).delete();
        } catch (_) {}
        debugPrint('[MiMoTTS] 音色相似度检测: $attempt 得分=$score '
            '阈值=$similarityThreshold (文本="$textPreview")');
        if (score >= similarityThreshold) break;
        if (attempt < maxRetryForDrift) {
          debugPrint('[MiMoTTS] 音色漂移($score)，重合成 ${attempt + 1}/$maxRetryForDrift');
        }
      }
    } else {
      audioBytes = await _synthesizeWithConfig(
        effectiveConfig,
        text,
        voiceData,
        style: style,
        maxRetries: maxRetries,
      );
    }

    // 写 wav 文件
    final outputPath = p.join(
        tmp.path, 'mimo_tts_${DateTime.now().millisecondsSinceEpoch}.wav');
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

  /// 用「音色设计」模型合成一次（voicedesign，效果优于克隆但音色不固定）：
  /// 生成一句参考样本音频，保存为角色参考音频后由 voiceclone 复刻固定。
  ///
  /// [designPrompt]：音色设计描述（voicedesign 的 user 消息必填）。
  /// [text]：用于生成样本的台词（建议贴合音色的一句短句）。
  /// 返回生成的 wav 文件路径。
  Future<String> synthesizeDesignSample(
    String designPrompt,
    String text, {
    int maxRetries = 3,
  }) async {
    if (!enabled) {
      throw StateError('本地语音合成未启用（AppConfig.localTtsEnabled=false）');
    }
    final config = await MiMoTtsConfigStore.load();
    if (config == null || !config.isValid) {
      throw StateError('MiMo TTS API Key 未配置，请到「我」→「设置」→「MiMo TTS 设置」填写');
    }
    // 临时切 voicedesign 模型合成样本；不触碰持久化配置
    final designConfig = MiMoTtsConfig(
      apiKey: config.apiKey,
      baseUrl: config.baseUrl,
      engine: 'voicedesign',
      voiceDesignPrompt: designPrompt,
    );
    final audioBytes = await _synthesizeWithConfig(
      designConfig,
      text,
      '',
      style: '',
      maxRetries: maxRetries,
    );
    final tmp = await getTemporaryDirectory();
    final outPath = p.join(
        tmp.path, 'design_sample_${DateTime.now().millisecondsSinceEpoch}.wav');
    await File(outPath).writeAsBytes(audioBytes, flush: true);
    return outPath;
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
    if (sampleBytes.isEmpty) {
      throw StateError('参考音频文件为空（0 字节）: ${profile.referenceAudioPath}，'
          '请重新录制音色或删除该角色的自定义音色以回退默认音色');
    }
    if (sampleBytes.length > 10 * 1024 * 1024) {
      throw StateError('参考音频超过 10MB 上限（base64 后），请裁剪后重试');
    }
    final mime = refFile.path.toLowerCase().endsWith('.mp3')
        ? 'audio/mpeg'
        : 'audio/wav';
    debugPrint('[MiMoTTS] 音色样本: path=${profile.referenceAudioPath} '
        'bytes=${sampleBytes.length} mime=$mime hash=${profile.referenceHash} '
        'spec=${_wavSpecSummary(sampleBytes)}');
    final dataUrl = 'data:$mime;base64,${base64Encode(sampleBytes)}';
    _sampleCache[profile.characterId] = dataUrl;
    _sampleHashCache[profile.characterId] = profile.referenceHash;
    return dataUrl;
  }

  /// 调 OpenAI 兼容接口。返回 wav 字节。429 指数退避重试。
  ///
  /// 日志退路：每次请求打出 model/文本/风格/音色样本摘要，失败打出完整
  /// 响应体——400 Param Incorrect 时可直接从日志定位是哪个参数不合法。
  Future<Uint8List> _synthesizeWithConfig(
    MiMoTtsConfig config,
    String text,
    String voiceData, {
    String style = '',
    int maxRetries = 3,
  }) async {
    final uri = Uri.parse('${config.baseUrl}/chat/completions');
    final textPreview = _preview(text, 100);
    final stylePreview = _preview(style, 80);
    final model = config.effectiveModel;
    // 预置音色引擎不传参考音频，只传 Voice ID（mimo_default/冰糖/…）；
    // 音色设计引擎把设计描述并入 user 指令（官方文档：voicedesign 时
    // user 消息为必填，描述即音色设计文本），audio.voice 不传。
    final voice = config.usePreset ? config.presetVoice : voiceData;
    final userContent = config.useVoicedesign
        ? _joinDesignAndStyle(config.voiceDesignPrompt, style)
        : style;

    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      debugPrint('[MiMoTTS] 请求(#$attempt): model=$model '
          'textLen=${text.length} text="$textPreview" '
          'styleLen=${style.length} style="$stylePreview" '
          'voice=${config.usePreset ? 'preset:$voice' : 'clone(${voice.length}B)'}');
      final body = jsonEncode({
        'model': model,
        'messages': [
          {'role': 'user', 'content': userContent},
          {'role': 'assistant', 'content': text},
        ],
        'audio': {
          'format': 'wav',
          if (!config.usePreset && !config.useVoicedesign) 'voice': voice,
        },
      });
      final http.Response resp;
      try {
        resp = await http
            .post(
              uri,
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer ${config.apiKey}',
              },
              body: body,
            )
            .timeout(const Duration(seconds: 120));
      } catch (e) {
        debugPrint('[MiMoTTS] 网络/超时(#$attempt): $e text="$textPreview"');
        rethrow;
      }

      if (resp.statusCode == 429 && attempt < maxRetries) {
        debugPrint('[MiMoTTS] 429 限流(#$attempt)，退避重试 body=${_preview(resp.body, 300)}');
        // 指数退避：1s, 2s, 4s...
        final delay = Duration(seconds: 1 << attempt);
        await Future<void>.delayed(delay);
        continue;
      }
      if (resp.statusCode != 200) {
        debugPrint('[MiMoTTS] 失败(#$attempt): HTTP ${resp.statusCode} '
            'body=${_preview(resp.body, 500)} text="$textPreview"');
        throw StateError(
            'MiMo TTS 请求失败 (${resp.statusCode}): ${_extractError(resp.body)}');
      }
      final json =
          jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final audio = (json['choices'] as List?)?.firstOrNull?['message']?['audio'];
      if (audio is Map && audio['data'] is String) {
        final bytes = base64Decode(audio['data'] as String);
        debugPrint('[MiMoTTS] 成功(#$attempt): audioBytes=${bytes.length} '
            'durationMs=${_wavDurationMs(bytes)}');
        return bytes;
      }
      debugPrint('[MiMoTTS] 响应缺少音频数据(#$attempt): '
          'body=${_preview(resp.body, 500)}');
      throw StateError('MiMo TTS 响应缺少音频数据');
    }
    throw StateError('MiMo TTS 请求重试次数用尽');
  }

  /// 音色设计引擎：user 消息 = 音色设计描述 + 风格指令（逗号衔接，均非空才拼接）。
  static String _joinDesignAndStyle(String design, String style) {
    final d = design.trim();
    final s = style.trim();
    if (d.isEmpty) return s;
    if (s.isEmpty) return d;
    return '$d\n$s';
  }

  /// 日志用文本预览：截断 + 换行压平，避免刷屏。
  static String _preview(String s, int max) {
    final flat = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return flat.length > max ? '${flat.substring(0, max)}…' : flat;
  }

  /// wav 头摘要（采样率/声道/时长），用于确认参考音频规格是否符合
  /// 规范化约定（24kHz/单声道/≤6s）；非 wav 或头不可读返回「-」。
  static String _wavSpecSummary(Uint8List bytes) {
    if (bytes.length < 44) return '-';
    final d = ByteData.sublistView(bytes);
    final channels = d.getUint16(22, Endian.little);
    final sampleRate = d.getUint32(24, Endian.little);
    final dataSize = d.getUint32(40, Endian.little);
    if (channels <= 0 || sampleRate <= 0 || dataSize <= 0) return '-';
    final dur = dataSize / (sampleRate * channels * 2);
    return '${sampleRate}Hz/${channels}ch/${dur.toStringAsFixed(1)}s';
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
