import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../config/image_gen_config.dart';

/// Agnes 图像生成服务（v2 重构版）
///
/// 所有配置从 [ImageGenConfig] 动态读取，零硬编码。
/// 支持文生图（Text-to-Image）和图生图（Image-to-Image），
/// 统一使用 Base64 输出，避免 CDN 下载被墙问题。
class AgnesImageService {
  static final AgnesImageService _instance = AgnesImageService._();
  factory AgnesImageService() => _instance;
  AgnesImageService._();

  final _uuid = const Uuid();

  // 超时默认值
  static const _kDefaultTimeoutSec = 120;

  /// 从 ImageGenConfig 读取 API Key（缓存避免反复读 SP）
  String? _cachedKey;
  Future<String> _getApiKey() async {
    if (_cachedKey != null) return _cachedKey!;
    final key = await ImageGenConfig.getApiKey();
    _cachedKey = key ?? '';
    return _cachedKey!;
  }

  // ═══════════════════════════════════════════════════════
  // 文生图（Text-to-Image）
  // ═══════════════════════════════════════════════════════

  /// 文生图接口（OpenAI 兼容格式，通过 chatgpt2api 的 gpt-image-2 模型）
  ///
  /// [prompt] 完整的正向 prompt（由调用方拼接好）
  /// [characterName] 角色名，用于日志和文件命名
  /// [seed] 随机种子
  Future<AgnesImageResult> textToImage({
    required String prompt,
    String? characterName,
    int? seed,
  }) async {
    final model = await ImageGenConfig.modelName;
    final url = '${await ImageGenConfig.baseUrl}${await ImageGenConfig.imagesPath}';

    debugPrint('[GPTImage][T2I] 开始文生图 | model: $model');
    debugPrint('[GPTImage][T2I] Prompt: ${prompt.substring(0, prompt.length.clamp(0, 120))}...');

    try {
      final body = <String, dynamic>{
        'model': model,
        'prompt': prompt,
        'n': 1,
        'response_format': 'b64_json',
      };

      debugPrint('[GPTImage][T2I] POST $url');

      final response = await http
          .post(
            Uri.parse(url),
            headers: await _headers(),
            body: jsonEncode(body),
          )
          .timeout(Duration(seconds: _kDefaultTimeoutSec));

      return _handleResponse(response, 'T2I', characterName);
    } on TimeoutException {
      debugPrint('[GPTImage][T2I] 请求超时');
      return AgnesImageResult.error('图像生成超时，请稍后重试');
    } on http.ClientException catch (e) {
      debugPrint('[GPTImage][T2I] 网络异常: $e');
      return AgnesImageResult.error('网络连接失败，请检查网络后重试');
    } catch (e) {
      debugPrint('[GPTImage][T2I] 未知异常: $e');
      return AgnesImageResult.error('图像生成失败: $e');
    }
  }

  // ═══════════════════════════════════════════════════════
  // 图生图（Image-to-Image）— 通过 chatgpt2api edits 端点
  // ═══════════════════════════════════════════════════════

  /// 图生图接口（通过 chatgpt2api 的 /v1/images/edits 接口）
  ///
  /// [sourceImagePath] 参考图本地路径（角色立绘锚定底图）
  /// [prompt] 正向 prompt
  /// [characterName] 角色名
  Future<AgnesImageResult> imageToImage({
    required String sourceImagePath,
    required String prompt,
    String? characterName,
  }) async {
    // 1. 校验原图
    final sourceFile = File(sourceImagePath);
    if (!await sourceFile.exists()) {
      debugPrint('[GPTImage][I2I] 原图不存在: $sourceImagePath');
      return AgnesImageResult.error('参考图文件不存在，请重新选择');
    }

    final model = await ImageGenConfig.modelName;
    final url = '${await ImageGenConfig.baseUrl}/images/edits';

    debugPrint('[GPTImage][I2I] 开始图生图');

    try {
      // 读取原图并转为 Base64 Data URI
      final imageBytes = await sourceFile.readAsBytes();
      final base64Image = base64Encode(imageBytes);
      final dataUri = 'data:image/png;base64,$base64Image';
      debugPrint('[GPTImage][I2I] 原图大小: ${(imageBytes.length / 1024).toStringAsFixed(1)}KB');

      final body = <String, dynamic>{
        'model': model,
        'prompt': prompt,
        'n': 1,
        'images': [
          {'image_url': dataUri},
        ],
      };

      debugPrint('[GPTImage][I2I] POST $url');

      final response = await http
          .post(
            Uri.parse(url),
            headers: await _headers(),
            body: jsonEncode(body),
          )
          .timeout(Duration(seconds: _kDefaultTimeoutSec + 60));

      return _handleResponse(response, 'I2I', characterName);
    } on TimeoutException {
      debugPrint('[GPTImage][I2I] 请求超时');
      return AgnesImageResult.error('图像生成超时，请稍后重试');
    } on http.ClientException catch (e) {
      debugPrint('[GPTImage][I2I] 网络异常: $e');
      return AgnesImageResult.error('网络连接失败，请检查网络后重试');
    } catch (e) {
      debugPrint('[GPTImage][I2I] 未知异常: $e');
      return AgnesImageResult.error('图像生成失败: $e');
    }
  }

  // ═══════════════════════════════════════════════════════
  // 响应处理
  // ═══════════════════════════════════════════════════════

  /// 处理 Agnes API 响应（OpenAI 兼容格式，Base64 输出）
  Future<AgnesImageResult> _handleResponse(
    http.Response response,
    String tag,
    String? characterName,
  ) async {
    final statusCode = response.statusCode;
    debugPrint('[Agnes][$tag] HTTP $statusCode');

    if (statusCode == 401) {
      return AgnesImageResult.error('API Key 无效或已过期，请联系管理员更新 chatgpt2api auth-key');
    }
    if (statusCode == 402 || statusCode == 429) {
      return AgnesImageResult.error('API 额度已耗尽或请求过于频繁，请稍后再试');
    }
    if (statusCode == 500 || statusCode == 502 || statusCode == 503) {
      return AgnesImageResult.error('chatgpt2api 服务暂时不可用，请稍后重试');
    }
    if (statusCode != 200) {
      final bodyPreview = response.body.length > 200
          ? response.body.substring(0, 200)
          : response.body;
      debugPrint('[Agnes][$tag] 错误响应: $bodyPreview');
      return AgnesImageResult.error('图像生成失败（HTTP $statusCode），请稍后重试');
    }

    try {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final data = json['data'];
      if (data == null || data is! List || data.isEmpty) {
        return AgnesImageResult.error('服务未返回图像数据，请重试');
      }

      final imageData = data[0] as Map<String, dynamic>;
      final b64 = imageData['b64_json'] as String?;

      if (b64 == null || b64.isEmpty) {
        debugPrint('[Agnes][$tag] 响应中无 b64_json 数据');
        return AgnesImageResult.error('图像数据为空，请重试');
      }

      final localPath = await _saveBase64Image(b64, tag, characterName);
      if (localPath.isEmpty) {
        return AgnesImageResult.error('图像保存失败，请重试');
      }

      debugPrint('[Agnes][$tag] 成功 | 本地: $localPath');
      return AgnesImageResult.success(imagePath: localPath);
    } catch (e) {
      debugPrint('[Agnes][$tag] 响应解析失败: $e');
      return AgnesImageResult.error('图像数据解析失败，请重试');
    }
  }

  // ═══════════════════════════════════════════════════════
  // 图片本地保存
  // ═══════════════════════════════════════════════════════

  Future<String> _saveBase64Image(
    String base64Str,
    String tag,
    String? characterName,
  ) async {
    try {
      final bytes = base64Decode(base64Str);
      final dir = await getApplicationDocumentsDirectory();
      final agnesDir = Directory('${dir.path}/agnes_images');
      if (!await agnesDir.exists()) {
        await agnesDir.create(recursive: true);
      }
      final fileName = 'agnes_${tag.toLowerCase()}_${_uuid.v4().substring(0, 8)}.png';
      final filePath = '${agnesDir.path}/$fileName';
      final file = File(filePath);
      await file.writeAsBytes(bytes);
      debugPrint('[Agnes][$tag] 已保存到: $filePath (${(bytes.length / 1024).toStringAsFixed(1)}KB)');
      return filePath;
    } catch (e) {
      debugPrint('[Agnes][$tag] 保存异常: $e');
      return '';
    }
  }

  /// 构建通用请求头（从 ImageGenConfig 动态读取 API Key）
  Future<Map<String, String>> _headers() async => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${await _getApiKey()}',
      };
}

// ═══════════════════════════════════════════════════════
// 结果模型
// ═══════════════════════════════════════════════════════

/// Agnes 图像生成结果
class AgnesImageResult {
  final bool isSuccess;
  final String? imagePath;
  final String? errorMessage;

  const AgnesImageResult._({
    required this.isSuccess,
    this.imagePath,
    this.errorMessage,
  });

  factory AgnesImageResult.success({required String imagePath}) =>
      AgnesImageResult._(isSuccess: true, imagePath: imagePath);

  factory AgnesImageResult.error(String message) =>
      AgnesImageResult._(isSuccess: false, errorMessage: message);

  bool get isError => !isSuccess;
}
