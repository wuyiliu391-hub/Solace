import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import '../config/constants.dart';
import '../config/image_gen_config.dart';
import '../utils/response_decoder.dart';

class MultimodalService {
  static final MultimodalService _instance = MultimodalService._();
  factory MultimodalService() => _instance;
  MultimodalService._();

  // ═══════════════════════════════════════════════════════
  // 多模态识别服务
  // 通过 OpenAI 兼容的 /v1/chat/completions 接口传递图片
  // 默认接入 HF Space chatgpt2api 部署
  // ═══════════════════════════════════════════════════════

  /// 从 ImageGenConfig 读取 base URL（与生图服务共享同一后端）
  Future<String> _getBaseUrl() async {
    final url = await ImageGenConfig.baseUrl;
    if (url.isEmpty || url == 'https://your-image-api.example.com/v1') {
      return 'https://qwen2apiloliu-chatgpt2api-v2.hf.space/v1';
    }
    return url;
  }

  /// 从 ImageGenConfig 读取 API Key（与生图服务共享同一 auth-key）
  Future<String> _getApiKey() async {
    final key = await ImageGenConfig.getApiKey();
    if (key == null || key.isEmpty) {
      return '';
    }
    return key;
  }

  static const List<String> _modelFallbacks = [
    'gpt-5',
    'gpt-5-1',
    'gpt-5-2',
    'gpt-5-3',
  ];

  bool _initialized = false;
  bool get isReady => _initialized;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
  }

  Future<String> describeImage(String imagePath) async {
    try {
      final file = File(imagePath);
      if (!await file.exists()) {
        debugPrint('[ERR] [多模态] 图片文件不存在: $imagePath');
        return '';
      }

      final bytes = await file.readAsBytes();
      debugPrint('[IMG] [多模态] 原始图片: ${(bytes.length / 1024).toStringAsFixed(1)}KB');

      final apiKey = await _getApiKey();
      if (apiKey.isEmpty) {
        debugPrint('[ERR] [多模态] 未配置 API Key，请在设置中配置');
        return '用户发送了一张图片';
      }

      final baseUrl = await _getBaseUrl();

      final processed = await _prepareImage(bytes, imagePath);
      if (processed.$1.isEmpty) return '';

      final base64Image = base64Encode(processed.$1);
      debugPrint('[OUT] [多模态] 编码后: ${(base64Image.length / 1024).toStringAsFixed(1)}KB');

      for (int i = 0; i < _modelFallbacks.length; i++) {
        final model = _modelFallbacks[i];
        debugPrint('[TRY] [多模态] 尝试模型[$i]: $model');
        try {
          final result = await _callVisionAPI(
            baseUrl: baseUrl,
            apiKey: apiKey,
            model: model,
            mimeType: processed.$2,
            base64Image: base64Image,
          );
          if (result.isNotEmpty) {
            debugPrint('[OK] [多模态] 模型 $model 识别成功');
            return result;
          }
        } catch (e) {
          debugPrint('[WARN] [多模态] 模型 $model 失败: $e');
        }
      }

      debugPrint('[ERR] [多模态] 所有模型均失败');
      return '用户发送了一张图片';
    } catch (e, stackTrace) {
      debugPrint('[ERR] [多模态] 异常: $e');
      debugPrint('Stack: $stackTrace');
      return '用户发送了一张图片';
    }
  }

  Future<String> describeImages(List<String> imagePaths) async {
    if (imagePaths.isEmpty) return '';
    if (imagePaths.length == 1) return describeImage(imagePaths[0]);
    try {
      final apiKey = await _getApiKey();
      if (apiKey.isEmpty) {
        debugPrint('[ERR] [多模态批处理] 未配置 API Key');
        return '';
      }

      final baseUrl = await _getBaseUrl();

      final List<Map<String, dynamic>> contentItems = [];
      contentItems.add({
        'type': 'text',
        'text': '请仔细看这些图片，分别描述每张图片的内容（物体、场景、人物、文字等），按顺序逐张回答。用中文回答。',
      });

      for (final imagePath in imagePaths) {
        final file = File(imagePath);
        if (!await file.exists()) continue;
        final bytes = await file.readAsBytes();
        final processed = await _prepareImage(bytes, imagePath);
        if (processed.$1.isEmpty) continue;
        final base64Image = base64Encode(processed.$1);
        contentItems.add({
          'type': 'image_url',
          'image_url': {'url': 'data:${processed.$2};base64,$base64Image'},
        });
      }

      if (contentItems.length <= 1) return '';

      for (int i = 0; i < _modelFallbacks.length; i++) {
        final model = _modelFallbacks[i];
        try {
          final result = await _callVisionAPIBatch(
            baseUrl: baseUrl,
            apiKey: apiKey,
            model: model,
            contentItems: contentItems,
          );
          if (result.isNotEmpty) return result;
        } catch (e) {
          debugPrint('[WARN] [多模态批处理] 模型 $model 失败: $e');
        }
      }
      debugPrint('[ERR] [多模态批处理] 所有模型均失败');
      return '';
    } catch (e) {
      debugPrint('[ERR] [多模态批处理] 异常: $e');
      return '';
    }
  }

  Future<String> _callVisionAPI({
    required String baseUrl,
    required String apiKey,
    required String model,
    required String mimeType,
    required String base64Image,
  }) async {
    const maxRetries = 2;
    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final response = await http.post(
          Uri.parse('$baseUrl/chat/completions'),
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'model': model,
            'messages': [
              {
                'role': 'user',
                'content': [
                  {
                    'type': 'text',
                    'text': '请仔细看这张图片，完成两件事：\n1. 识别图中所有文字，逐字转录\n2. 描述图片内容（类型、物体、场景、人物等）\n\n用中文回答。',
                  },
                  {
                    'type': 'image_url',
                    'image_url': {'url': 'data:$mimeType;base64,$base64Image'},
                  }
                ]
              }
            ],
            'temperature': 0.1,
            'max_tokens': 2000,
          }),
          ).timeout(AppDurations.visionApi);

        if (response.statusCode == 200) {
          final data = jsonDecode(utf8.decode(response.bodyBytes));
          final content = ResponseDecoder.extractContent(data);
          if (content.trim().isEmpty) return '';
          return content;
        }

        final errorBody = utf8.decode(response.bodyBytes);
        debugPrint('[ERR] [多模态] HTTP ${response.statusCode} (attempt ${attempt + 1}): $errorBody');

        if (response.statusCode == 401 || response.statusCode == 403) throw Exception('API密钥无效');
        if (response.statusCode == 404) throw Exception('模型不可用');
        if (response.statusCode == 400) throw Exception('请求参数错误');
        if (response.statusCode == 429 && attempt < maxRetries) {
          await Future.delayed(Duration(seconds: (attempt + 1) * 2));
          continue;
        }
        if (attempt < maxRetries) {
          await Future.delayed(Duration(seconds: (attempt + 1) * 2));
          continue;
        }
        throw Exception('HTTP ${response.statusCode}');
      } catch (e) {
        if (attempt < maxRetries) {
          debugPrint('[WARN] [多模态] 重试 (attempt ${attempt + 1}): $e');
          await Future.delayed(Duration(seconds: (attempt + 1) * 2));
          continue;
        }
        rethrow;
      }
    }
    throw Exception('视觉识别失败');
  }

  Future<String> _callVisionAPIBatch({
    required String baseUrl,
    required String apiKey,
    required String model,
    required List<Map<String, dynamic>> contentItems,
  }) async {
    const maxRetries = 2;
    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final response = await http.post(
          Uri.parse('$baseUrl/chat/completions'),
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'model': model,
            'messages': [
              {'role': 'user', 'content': contentItems}
            ],
            'temperature': 0.1,
            'max_tokens': 2000,
          }),
        ).timeout(AppDurations.visionBatch);

        if (response.statusCode == 200) {
          final data = jsonDecode(utf8.decode(response.bodyBytes));
          final content = ResponseDecoder.extractContent(data);
          if (content.trim().isEmpty) return '';
          return content;
        }

        final errorBody = utf8.decode(response.bodyBytes);
        debugPrint('[ERR] [多模态批处理] HTTP ${response.statusCode} (attempt ${attempt + 1}): $errorBody');

        if (response.statusCode == 401 || response.statusCode == 403) throw Exception('API密钥无效');
        if (response.statusCode == 404) throw Exception('模型不可用');
        if (response.statusCode == 400) throw Exception('请求参数错误');
        if (response.statusCode == 429 && attempt < maxRetries) {
          await Future.delayed(Duration(seconds: (attempt + 1) * 2));
          continue;
        }
        if (attempt < maxRetries) {
          await Future.delayed(Duration(seconds: (attempt + 1) * 2));
          continue;
        }
        throw Exception('HTTP ${response.statusCode}');
      } catch (e) {
        if (attempt < maxRetries) {
          debugPrint('[WARN] [多模态批处理] 重试 (attempt ${attempt + 1}): $e');
          await Future.delayed(Duration(seconds: (attempt + 1) * 2));
          continue;
        }
        rethrow;
      }
    }
    throw Exception('批处理失败');
  }

  Future<(Uint8List, String)> _prepareImage(Uint8List bytes, String imagePath) async {
    String mimeType = 'image/jpeg';
    final ext = imagePath.toLowerCase();
    if (ext.endsWith('.png')) mimeType = 'image/png';
    else if (ext.endsWith('.webp')) mimeType = 'image/webp';
    else if (ext.endsWith('.gif')) mimeType = 'image/gif';

    Uint8List processed = bytes;
    if (bytes.length > 4 * 1024 * 1024) {
      debugPrint('[DBG] [多模态] 图片过大(${(bytes.length / 1024 / 1024).toStringAsFixed(1)}MB)，压缩中...');
      final compressed = _compressImage(bytes);
      if (compressed.isNotEmpty) {
        processed = compressed;
        mimeType = 'image/jpeg';
        debugPrint('[OK] [多模态] 压缩后: ${(processed.length / 1024).toStringAsFixed(1)}KB');
      }
    }
    return (processed, mimeType);
  }

  Uint8List _compressImage(Uint8List bytes) {
    try {
      final image = img.decodeImage(bytes);
      if (image == null) return Uint8List(0);
      int w = image.width;
      int h = image.height;
      if (w > 1600 || h > 1600) {
        final ratio = 1600 / (w > h ? w : h);
        w = (w * ratio).round();
        h = (h * ratio).round();
        final resized = img.copyResize(image, width: w, height: h);
        return Uint8List.fromList(img.encodeJpg(resized, quality: 80));
      }
      return Uint8List.fromList(img.encodeJpg(image, quality: 80));
    } catch (e) {
      debugPrint('[ERR] [压缩] 失败: $e');
      return bytes;
    }
  }
}
