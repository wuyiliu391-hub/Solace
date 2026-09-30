// Fish Audio TTS 服务。
//
// 引擎：S2.1 Pro（官方文档 https://docs.fish.audio）
//   - 免费模型 `s2.1-pro-free`：定价页标价 $0.00 / M UTF-8 bytes。
//   - 付费模型 `s2.1-pro`：$15.00 / M UTF-8 bytes。
//
// 与 MiMo 的关键差异：音色是**预先创建**的，不是每次上传音频。
//   MiMo：每次合成都带参考音频 → 本地传 base64
//   Fish：先 POST /model 建音色拿到 reference_id → 之后只传 id
// 因此本服务把 characterId → reference_id 的映射持久化到 SharedPreferences。
//
// ★ 两个实测踩坑（2026-09-30 真实 API 验证，务必别改回去）：
// 1. 建音色的 endpoint 是 `/model`，**在根路径、不带 /v1**。
//    用 `${baseUrl}/model`（= /v1/model）会 404 "Nothing matches the given URI"。
//    合成才在 /v1 下（/v1/tts）。两者路径不对称，别想当然统一。
// 2. 建音色必须用 **multipart/form-data 文件上传**。
//    官方 OpenAPI 把 voices 声明成 array of string（看着像传 base64），
//    但服务端实际校验 UploadFile，传 base64 会 422
//    "Expected UploadFile, received str instead."。
//    必填字段：type / title / train_mode / voices。
//    train_mode: 'fast' 表示创建后立即可用，不进训练队列。
//
// 免费期限制（务必知悉，写代码时不要假设它永久有效）：
//   - 官方公告免费期至 2026-11-30，且已多次延期（7/24 → 7/31 → 8/31 → 11/30），
//     说明随时可能再变。
//   - 无 SLA、无延迟保证。
//   - 请求内容可能被用于改进模型（与本项目「隐私优先」定位冲突）。
//   - 商用：ARR > $1M 需先联系官方。
//   - ASR（transcribe-1）**没有**免费模型，$0.36/audio hour。

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/app_config.dart';
import 'audio_converter_service.dart';
import 'local_tts_service.dart';

/// Fish Audio 配置（持久化在 SharedPreferences）。
class FishAudioTtsConfig {
  static const String providerName = 'fish-audio';
  static const String defaultBaseUrl = 'https://api.fish.audio/v1';

  /// 免费模型：定价页标价 $0.00 / M UTF-8 bytes。免费期至 2026-11-30。
  static const String freeModel = 's2.1-pro-free';

  /// 付费模型：$15.00 / M UTF-8 bytes。免费期结束后需要切到这里。
  static const String paidModel = 's2.1-pro';

  /// 可选模型（仅免费 + 付费两档，其余见官方定价页）。
  static const List<({String label, String id})> models = [
    (label: 'S2.1 Pro（免费·限时至 2026-11-30）', id: 's2.1-pro-free'),
    (label: r'S2.1 Pro（付费 $15/M 字节）', id: 's2.1-pro'),
  ];

  /// temperature 的可选档位。Fish TTS 没有「情绪强度」参数，
  /// temperature 是唯一能调的原生表现力维度（0~1）。
  ///
  /// 实测（s2.1-pro-free，同一克隆音色 + 同一句台词）：
  ///   0.1  -> 平稳保守，适合旁白/提示音
  ///   0.5  -> 居中，日常对话
  ///   0.95 -> 起伏最大，适合撒娇/哽咽/激动等情绪戏
  /// 代价：温度越高越容易出现发音含糊、重复字、吞音。
  static const List<({String label, double value})> temperaturePresets = [
    (label: '克制（0.1·平稳）', value: 0.1),
    (label: '自然（0.5·日常）', value: 0.5),
    (label: '鲜活（0.7·默认）', value: 0.7),
    (label: '戏剧（0.95·起伏最大）', value: 0.95),
  ];

  final String apiKey;
  final String baseUrl;
  final String model;

  /// 原生表现力 0~1，越高越有起伏、也越发散。默认 0.7（服务端默认）。
  final double temperature;

  /// 原生语速 0.5~2.0。默认 1.0（不改变）。
  ///
  /// ★ 实测坑：`s2.1-pro-free` 上**减速有效、加速近乎无效**。
  ///   同一句台词 speed=0.7 得 5.10s、1.0 得 2.74s（明显变慢），
  ///   但 1.4 只得 2.85s（仅比 1.0 快 4%，预期快 35%）。
  ///   所以默认别用 >1 的加速；要加速请走本地变速。
  final double speed;

  const FishAudioTtsConfig({
    required this.apiKey,
    this.baseUrl = defaultBaseUrl,
    this.model = freeModel,
    this.temperature = 0.7,
    this.speed = 1.0,
  });

  /// 建音色的根地址：剥掉末尾的 `/v1`。
  ///
  /// Fish 的路径不对称——合成在 `/v1/tts`，建音色却在根 `/model`。
  /// 所以这里不能直接拿 baseUrl 拼 `/model`，否则必然 404。
  String get rootBaseUrl {
    var root = baseUrl;
    while (root.endsWith('/')) {
      root = root.substring(0, root.length - 1);
    }
    if (root.endsWith('/v1')) {
      root = root.substring(0, root.length - 3);
    }
    return root;
  }

  bool get isValid => apiKey.trim().isNotEmpty;

  /// 免费模型是否仍在免费期（仅用于 UI 提示，不影响能否调用）。
  bool get isFreeModel => model == freeModel;
}

class FishAudioTtsConfigStore {
  static const _kKey = 'fish_audio_api_key';
  static const _kBaseUrl = 'fish_audio_base_url';
  static const _kModel = 'fish_audio_model';
  static const _kTemperature = 'fish_audio_temperature';
  static const _kSpeed = 'fish_audio_speed';
  static const _kRefPrefix = 'fish_audio_ref_';

  static Future<FishAudioTtsConfig?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final apiKey = prefs.getString(_kKey) ?? '';
    if (apiKey.isEmpty) return null;
    return FishAudioTtsConfig(
      apiKey: apiKey,
      baseUrl: prefs.getString(_kBaseUrl) ?? FishAudioTtsConfig.defaultBaseUrl,
      model: prefs.getString(_kModel) ?? FishAudioTtsConfig.freeModel,
      // getDouble 在 key 存成 int 时会抛异常，这里兜底
      temperature: _readDouble(prefs, _kTemperature, 0.7),
      speed: _readDouble(prefs, _kSpeed, 1.0),
    );
  }

  /// SharedPreferences 在「整数值恰好可存为 int」时会返回 int，
  /// 直接 getDouble 会抛类型异常，这里统一按 num 兜底。
  static double _readDouble(SharedPreferences prefs, String key, double def) {
    final v = prefs.get(key);
    if (v is num) return v.toDouble();
    if (v is String) {
      final parsed = double.tryParse(v);
      if (parsed != null) return parsed;
    }
    return def;
  }

  static Future<void> save(
    String apiKey, {
    String? baseUrl,
    String? model,
    double? temperature,
    double? speed,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kKey, apiKey.trim());
    if (baseUrl != null) await prefs.setString(_kBaseUrl, baseUrl.trim());
    if (model != null) await prefs.setString(_kModel, model.trim());
    if (temperature != null) {
      await prefs.setDouble(_kTemperature, temperature.clamp(0.0, 1.0));
    }
    if (speed != null) {
      await prefs.setDouble(_kSpeed, speed.clamp(0.5, 2.0));
    }
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kKey);
  }

  // ---- 音色 reference_id 映射（characterId → Fish model id） ----

  static String _refKey(String characterId) => '$_kRefPrefix$characterId';

  static Future<String?> loadReferenceId(String characterId) async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_refKey(characterId));
    return (id == null || id.isEmpty) ? null : id;
  }

  static Future<void> saveReferenceId(
      String characterId, String referenceId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_refKey(characterId), referenceId);
  }

  static Future<void> clearReferenceId(String characterId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_refKey(characterId));
  }
}

/// Fish Audio TTS 服务实现。
class FishAudioTtsService implements TtsService {
  @override
  bool get enabled => AppConfig.localTtsEnabled;

  @override
  Future<bool> get isModelReady async {
    final config = await FishAudioTtsConfigStore.load();
    return config != null && config.isValid;
  }

  @override
  Future<VoiceProfile> setReferenceAudio(
    String characterId,
    String referenceAudioPath,
    String referenceText,
  ) async {
    final hash = await sha1.bind(File(referenceAudioPath).openRead()).first;
    return VoiceProfile(
      characterId: characterId,
      referenceAudioPath: referenceAudioPath,
      referenceText: referenceText,
      referenceHash: hash.toString(),
    );
  }

  @override
  Future<TtsResult> synthesize(String characterId, String text) =>
      synthesizeWithStyle(characterId, text);

  /// Fish Audio 不接受导演指令，[style] 仅用于对齐统一接口而被忽略。
  @override
  Future<TtsResult> synthesizeWithStyle(
    String characterId,
    String text, {
    String style = '',
    int maxRetries = 3,
  }) async {
    if (!enabled) {
      throw StateError('语音合成未启用（AppConfig.localTtsEnabled=false）');
    }
    final config = await FishAudioTtsConfigStore.load();
    if (config == null || !config.isValid) {
      throw StateError('Fish Audio API Key 未配置，请到「我」→「设置」→「语音设置」填写');
    }
    final referenceId = await FishAudioTtsConfigStore.loadReferenceId(characterId);
    if (referenceId == null) {
      throw StateError('该角色尚未在 Fish Audio 创建音色，请先在「音色克隆」页录入参考音频');
    }

    final bytes = await _synthesizeBytes(config, referenceId, text, maxRetries);
    return _writeResult(bytes);
  }

  /// 用参考音频在 Fish Audio 创建一个音色模型，持久化 reference_id。
  ///
  /// 与 MiMo 的差别：这一步是**一次性**的，之后合成只传 id。
  /// [referenceText] 为 Fish 建模型必填项；本项目允许用户留空，此时传空串。
  Future<String> createVoiceModel(
    String characterId,
    String referenceAudioPath,
    String referenceText,
  ) async {
    final config = await FishAudioTtsConfigStore.load();
    if (config == null || !config.isValid) {
      throw StateError('Fish Audio API Key 未配置');
    }
    final file = File(referenceAudioPath);
    if (!file.existsSync()) {
      throw StateError('参考音频不存在: $referenceAudioPath');
    }
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      throw StateError('参考音频是空文件: $referenceAudioPath');
    }

    // 必须 multipart 文件上传，不能用 JSON + base64（服务端校验 UploadFile）
    final req = http.MultipartRequest(
      'POST',
      Uri.parse('${config.rootBaseUrl}/model'),
    )..headers['Authorization'] = 'Bearer ${config.apiKey}';

    // multipart 的标量字段全部按字符串传
    req.fields['type'] = 'tts';
    req.fields['title'] = 'solace_${characterId.hashCode.toUnsigned(32)}';
    req.fields['description'] = 'Solace 角色音色（用户在 App 内克隆）';
    req.fields['visibility'] = 'private';
    // fast = 创建后立即可用，不进训练队列
    req.fields['train_mode'] = 'fast';
    req.fields['enhance_audio_quality'] = 'true';
    req.fields['generate_sample'] = 'false';
    // 参考音频文字稿可选；不传则服务端用 ASR 自动转写（实测可用）
    if (referenceText.trim().isNotEmpty) {
      req.fields['texts'] = referenceText.trim();
    }

    req.files.add(http.MultipartFile.fromBytes(
      'voices',
      bytes,
      filename: p.basename(referenceAudioPath),
    ));

    final streamed = await req.send();
    final resp = await http.Response.fromStream(streamed);
    if (resp.statusCode != 200 && resp.statusCode != 201) {
      throw StateError('Fish Audio 音色创建失败（HTTP ${resp.statusCode}）: ${resp.body}');
    }
    final json = jsonDecode(resp.body);
    final id = (json is Map ? json['_id'] : null)?.toString();
    if (id == null || id.isEmpty) {
      throw StateError('Fish Audio 未返回音色 id');
    }
    final state = json is Map ? json['state']?.toString() : null;
    debugPrint('[FishAudio] 音色已创建 id=$id state=$state');
    await FishAudioTtsConfigStore.saveReferenceId(characterId, id);
    return id;
  }

  Future<List<int>> _synthesizeBytes(
    FishAudioTtsConfig config,
    String referenceId,
    String text,
    int maxRetries,
  ) async {
    // Fish 要 wav；参考音频已在 VoiceProfileStore 规范化，这里不再重复转码
    final body = jsonEncode({
      'text': text,
      'reference_id': referenceId,
      'format': 'wav',
      // temperature 是 Fish 唯一的原生情绪杠杆（0~1，默认 0.7）。
      // 实测同一句台词在 0.1 / 0.5 / 0.95 下的时长与频谱质心都有可测差异，
      // 越高越「有表现力」，也越发散。
      // ★ 注意：Fish **没有** expressive / emotion / style 这类参数
      //   （openapi.json 的 TTSRequest 里确认过；Agent 平台那个 expressive
      //   只存在于 /v1/agent/* 的配置里，不在 TTS API）。
      //   所以风格化只能靠 temperature + prosody + 参考音频本身的情绪。
      'temperature': config.temperature,
      'prosody': {
        'speed': config.speed,
        // 统一响度，避免不同角色忽大忽小（对 S2 系列有效）
        'normalize_loudness': true,
      },
    });
    var attempt = 0;
    while (true) {
      attempt++;
      final resp = await http.post(
        Uri.parse('${config.baseUrl}/tts'),
        headers: {
          'Authorization': 'Bearer ${config.apiKey}',
          'Content-Type': 'application/json',
          // 免费/付费模型由这里切换
          'model': config.model,
        },
        body: body,
      );
      if (resp.statusCode == 200) {
        return resp.bodyBytes;
      }
      // 429 退避重试
      if (resp.statusCode == 429 && attempt <= maxRetries) {
        final wait = Duration(milliseconds: 400 * attempt);
        debugPrint('[FishTTS] 429 限流，${wait.inMilliseconds}ms 后重试 ($attempt/$maxRetries)');
        await Future<void>.delayed(wait);
        continue;
      }
      throw StateError(
          'Fish Audio 合成失败（HTTP ${resp.statusCode}）: ${resp.body}');
    }
  }

  /// 把返回的音频字节写到应用缓存目录，供播放器使用。
  Future<TtsResult> _writeResult(List<int> bytes) async {
    final dir = await getTemporaryDirectory();
    final out = Directory('${dir.path}/fish_tts');
    if (!await out.exists()) await out.create(recursive: true);
    final path = p.join(out.path, 'fish_${DateTime.now().millisecondsSinceEpoch}.wav');
    await File(path).writeAsBytes(bytes, flush: true);
    // 时长由播放器解析，这里不做额外解码，置 0 表示未知
    return TtsResult(audioFilePath: path, durationMs: 0);
  }
}
