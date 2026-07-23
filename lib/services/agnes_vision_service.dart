import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/doh_client.dart';

/// Agnes 2.0 Flash 多模态识图服务
///
/// 流程：用户发送图片 → Agnes 2.0 Flash 识别图片内容 → 返回文字描述 →
/// 该描述作为用户消息的一部分，传给用户配置的 LLM 模型进行最终输出
class AgnesVisionService {
  static const String _defaultBaseUrl = 'https://apihub.agnes-ai.com/v1';
  static const String _defaultModel = 'agnes-2.0-flash';
  static const String _defaultPrompt = '请详细描述这张图片的内容，包括场景、人物、物品、文字、氛围等所有你能看到的细节。';

  static const String _prefKey = 'agnes_api_key';
  static const String _prefBaseUrl = 'agnes_base_url';
  static const String _prefModel = 'agnes_model';
  static const String _prefPrompt = 'agnes_prompt';

  /// 获取用户配置的 Agnes API Key
  static Future<String?> getApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefKey);
  }

  /// 保存 Agnes API Key
  static Future<void> setApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, key.trim());
  }

  /// 是否已配置 API Key
  static Future<bool> isConfigured() async {
    final key = await getApiKey();
    return key != null && key.isNotEmpty;
  }

  /// 获取配置的 Base URL
  static Future<String> getBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefBaseUrl) ?? _defaultBaseUrl;
  }

  /// 获取配置的模型名
  static Future<String> getModel() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefModel) ?? _defaultModel;
  }

  /// 获取配置的识图 Prompt
  static Future<String> getPrompt() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefPrompt) ?? _defaultPrompt;
  }

  /// 识别单张图片，返回文字描述
  static Future<String> recognizeImage(String imagePath) async {
    final apiKey = await getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('Agnes API Key 未配置，请在 API 设置中填写');
    }

    final baseUrl = await getBaseUrl();
    final model = await getModel();
    final prompt = await getPrompt();

    final file = File(imagePath);
    if (!await file.exists()) {
      throw Exception('图片文件不存在: $imagePath');
    }

    final bytes = await file.readAsBytes();
    final base64Str = base64Encode(bytes);

    // 根据文件扩展名确定 MIME 类型
    final ext = imagePath.toLowerCase();
    String mimeType;
    if (ext.endsWith('.png')) {
      mimeType = 'image/png';
    } else if (ext.endsWith('.jpg') || ext.endsWith('.jpeg')) {
      mimeType = 'image/jpeg';
    } else if (ext.endsWith('.webp')) {
      mimeType = 'image/webp';
    } else if (ext.endsWith('.gif')) {
      mimeType = 'image/gif';
    } else {
      mimeType = 'image/png'; // 默认
    }

    final body = {
      'model': model,
      'messages': [
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': prompt},
            {'type': 'image_url', 'image_url': {'url': 'data:$mimeType;base64,$base64Str'}},
          ],
        },
      ],
    };

    try {
      final response = await DohResolver.post(
        Uri.parse('$baseUrl/chat/completions'),
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
          'Authorization': 'Bearer $apiKey',
        },
        body: utf8.encode(jsonEncode(body)),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(utf8.decode(response.bodyBytes))
            as Map<String, dynamic>;
        final choices = json['choices'] as List<dynamic>?;
        if (choices == null || choices.isEmpty) {
          throw Exception('Agnes 返回了空结果');
        }
        final message = choices.first['message'] as Map<String, dynamic>?;
        final content = message?['content'] as String?;
        if (content == null || content.trim().isEmpty) {
          throw Exception('Agnes 未识别出图片内容');
        }
        return content.trim();
      } else {
        final errorBody = utf8.decode(response.bodyBytes);
        debugPrint('[AgnesVision] API 错误 ${response.statusCode}: $errorBody');
        throw Exception('Agnes API 返回错误 (${response.statusCode}): $errorBody');
      }
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Agnes 识图请求失败: $e');
    }
  }

  /// 识别多张图片，返回合并的文字描述
  static Future<String> recognizeMultipleImages(List<String> imagePaths) async {
    final apiKey = await getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('Agnes API Key 未配置，请在 API 设置中填写');
    }

    final contentParts = <Map<String, dynamic>>[];
    contentParts.add({
      'type': 'text',
      'text': '请详细描述以下${imagePaths.length}张图片中每一张的内容，包括场景、人物、物品、文字、氛围等所有你能看到的细节。',
    });

    for (final path in imagePaths) {
      final file = File(path);
      if (!await file.exists()) continue;
      final bytes = await file.readAsBytes();
      final base64 = base64Encode(bytes);

      final ext = path.toLowerCase();
      String mimeType;
      if (ext.endsWith('.png')) {
        mimeType = 'image/png';
      } else if (ext.endsWith('.jpg') || ext.endsWith('.jpeg')) {
        mimeType = 'image/jpeg';
      } else if (ext.endsWith('.webp')) {
        mimeType = 'image/webp';
      } else if (ext.endsWith('.gif')) {
        mimeType = 'image/gif';
      } else {
        mimeType = 'image/png';
      }

      contentParts.add({
        'type': 'image_url',
        'image_url': {
          'url': 'data:$mimeType;base64,$base64',
        },
      });
    }

    final body = {
      'model': await getModel(),
      'messages': [
        {
          'role': 'user',
          'content': contentParts,
        }
      ],
      'max_tokens': 2048,
      'temperature': 0.3,
    };

    try {
      final response = await DohResolver.post(
        Uri.parse('${await getBaseUrl()}/chat/completions'),
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
          'Authorization': 'Bearer $apiKey',
        },
        body: utf8.encode(jsonEncode(body)),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(utf8.decode(response.bodyBytes))
            as Map<String, dynamic>;
        final choices = json['choices'] as List<dynamic>?;
        if (choices == null || choices.isEmpty) {
          throw Exception('Agnes 返回了空结果');
        }
        final message = choices.first['message'] as Map<String, dynamic>?;
        final content = message?['content'] as String?;
        if (content == null || content.trim().isEmpty) {
          throw Exception('Agnes 未识别出图片内容');
        }
        return content.trim();
      } else {
        final errorBody = utf8.decode(response.bodyBytes);
        throw Exception('Agnes API 返回错误 (${response.statusCode}): $errorBody');
      }
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Agnes 识图请求失败: $e');
    }
  }
}