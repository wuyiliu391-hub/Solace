import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/ai_config.dart';
import '../repositories/local_storage_repository.dart';
import '../utils/response_decoder.dart';

/// 云端语音识别服务
///
/// 通过 OpenAI 兼容的 `/audio/transcriptions` 接口将音频转文字。
/// 替代 `speech_to_text` 插件，解决国产安卓机无语音引擎的问题。
///
/// 支持多 API 配置自动探测：遍历所有已配置的 API，找到支持音频识别的那个。
class AudioTranscriptionService {
  final LocalStorageRepository _storage;

  AudioTranscriptionService(this._storage);

  /// 将音频文件发送到云端 API 做语音识别
  /// 返回识别出的文字，失败返回 null
  Future<String?> transcribe(String audioPath) async {
    final file = File(audioPath);
    if (!file.existsSync()) {
      debugPrint('AudioTranscription: 音频文件不存在: $audioPath');
      return null;
    }

    // 1. 先尝试所有已配置 API，找到支持音频识别的
    final configs = await _storage.getAllAIConfigs();
    if (configs.isEmpty) {
      debugPrint('AudioTranscription: 无 API 配置');
      return null;
    }

    // 2. 优先尝试 SiliconFlow（已知支持语音识别）
    final candidates = <AIConfig>[];
    for (final c in configs) {
      if (c.baseUrl.contains('siliconflow') ||
          c.baseUrl.contains('api.nvidia.com')) {
        candidates.add(c);
      }
    }
    // 再添加其他配置作为 fallback
    for (final c in configs) {
      if (!candidates.contains(c)) candidates.add(c);
    }

    // 3. 逐个尝试
    for (final config in candidates) {
      final result = await _tryTranscribe(config, audioPath);
      if (result != null) return result;
    }

    debugPrint('AudioTranscription: 所有 API 均识别失败');
    return null;
  }

  Future<String?> _tryTranscribe(AIConfig config, String audioPath) async {
    try {
      final uri = _buildTranscriptionUri(config);
      debugPrint('AudioTranscription: 尝试 ${config.providerName} (${config.baseUrl})');

      final request = http.MultipartRequest('POST', uri);
      request.headers['Authorization'] = 'Bearer ${config.apiKey}';
      request.files.add(await http.MultipartFile.fromPath('file', audioPath));
      request.fields['model'] = 'FunAudioLLM/SenseVoiceSmall';
      request.fields['language'] = 'zh';
      request.fields['response_format'] = 'json';

      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 30),
      );
      final response = await http.Response.fromStream(streamedResponse);

      final decoded = await ResponseDecoder.decode(response.headers['content-type'], response.bodyBytes);

      if (response.statusCode == 200) {
        final data = jsonDecode(decoded) as Map<String, dynamic>;
        final text = data['text'] as String?;
        debugPrint('AudioTranscription: 200 响应, text="$text"');
        if (text != null && text.trim().isNotEmpty) {
          debugPrint('AudioTranscription: 成功: "${text.trim()}"');
          return text.trim();
        }
        // text 为空 — 可能是音频内容太短或全是噪音
        debugPrint('AudioTranscription: text 为空, 完整响应: ${decoded.substring(0, decoded.length > 300 ? 300 : decoded.length)}');
      } else if (response.statusCode == 404) {
        debugPrint('AudioTranscription: ${config.baseUrl} 不支持音频识别 (404)');
      } else {
        debugPrint('AudioTranscription: API 返回 ${response.statusCode}: ${decoded.substring(0, decoded.length > 300 ? 300 : decoded.length)}');
      }
    } catch (e) {
      debugPrint('AudioTranscription: ${config.baseUrl} 请求失败: $e');
    }
    return null;
  }

  /// 检查是否有任何 API 支持语音识别
  Future<bool> isAvailable() async {
    final configs = await _storage.getAllAIConfigs();
    if (configs.isEmpty) return false;

    for (final config in configs) {
      try {
        final uri = _buildTranscriptionUri(config);
        final response = await http.head(uri).timeout(const Duration(seconds: 5));
        if (response.statusCode != 404) return true;
      } catch (_) {
        // 继续尝试下一个
      }
    }
    return false;
  }

  Uri _buildTranscriptionUri(AIConfig config) {
    var baseUrl = config.baseUrl.trim();
    while (baseUrl.endsWith('/')) {
      baseUrl = baseUrl.substring(0, baseUrl.length - 1);
    }
    // 如果 url 已包含 /chat/completions，替换为 /audio/transcriptions
    if (baseUrl.endsWith('/chat/completions')) {
      baseUrl = baseUrl.replaceAll('/chat/completions', '');
    } else if (baseUrl.contains('/chat/completions')) {
      baseUrl = baseUrl.split('/chat/completions').first;
    }
    return Uri.parse('$baseUrl/audio/transcriptions');
  }
}
