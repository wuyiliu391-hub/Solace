// Fish Audio TTS 服务。
//
// 引擎：S2.1 Pro（官方文档 https://docs.fish.audio）
//   - 免费模型 `s2.1-pro-free`：定价页标价 $0.00 / M UTF-8 bytes。
//   - 付费模型 `s2.1-pro`：$15.00 / M UTF-8 bytes。
//
// 与 MiMo 的关键差异：音色是**预先创建**的，不是每次上传音频。
//   MiMo：每次合成都带参考音频 → 本地传 base64
//   Fish：先 POST /v1/model 建音色拿到 reference_id → 之后只传 id
// 因此本服务把 characterId → reference_id 的映射持久化到 SharedPreferences。
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
    (label: 'S2.1 Pro（免费·限时至 2026-11-30）', id: freeModel),
    (label: 'S2.1 Pro（付费 $15/M 字节）', id: paidModel),
  ];

  final String apiKey;
  final String baseUrl;
  final String model;

  const FishAudioTtsConfig({
    required this.apiKey,
    this.baseUrl = defaultBaseUrl,
    this.model = freeModel,
  });

  bool get isValid => apiKey.trim().isNotEmpty;

  /// 免费模型是否仍在免费期（仅用于 UI 提示，不影响能否调用）。
  bool get isFreeModel => model == freeModel;
}

class FishAudioTtsConfigStore {
  static const _kKey = 'fish_audio_api_key';
  static const _kBaseUrl = 'fish_audio_base_url';
  static const _kModel = 'fish_audio_model';
  static const _kRefPrefix = 'fish_audio_ref_';

  static Future<FishAudioTtsConfig?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final apiKey = prefs.getString(_kKey) ?? '';
    if (apiKey.isEmpty) return null;
    return FishAudioTtsConfig(
      apiKey: apiKey,
      baseUrl: prefs.getString(_kBaseUrl) ?? FishAudioTtsConfig.defaultBaseUrl,
      model: prefs.getString(_kModel) ?? FishAudioTtsConfig.freeModel,
    );
  }

  static Future<void> save(
    String apiKey, {
    String? baseUrl,
    String? model,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kKey, apiKey.trim());
    if (baseUrl != null) await prefs.setString(_kBaseUrl, baseUrl.trim());
    if (model != null) await prefs.setString(_kModel, model.trim());
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
    final bytes = await File(referenceAudioPath).readAsBytes();
    final body = jsonEncode({
      // 建模型必须带参考文本；用户留空时传空串（Fish 接受）
      'text': referenceText,
      'audios': [base64Encode(bytes)],
    });
    final resp = await http.post(
      Uri.parse('${config.baseUrl}/model'),
      headers: {
        'Authorization': 'Bearer ${config.apiKey}',
        'Content-Type': 'application/json',
      },
      body: body,
    );
    if (resp.statusCode != 200) {
      throw StateError('Fish Audio 音色创建失败（HTTP ${resp.statusCode}）: ${resp.body}');
    }
    final json = jsonDecode(resp.body);
    final id = (json is Map ? json['_id'] : null)?.toString();
    if (id == null || id.isEmpty) {
      throw StateError('Fish Audio 未返回音色 id');
    }
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
