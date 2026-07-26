import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:image/image.dart' as img;

/// OpenAI / 中转站 vision 用的本地图片编码结果
class VisionImagePayload {
  final String dataUrl;
  final String mime;
  final int originalBytes;
  final int encodedBytes;
  final int width;
  final int height;
  final bool compressed;

  const VisionImagePayload({
    required this.dataUrl,
    required this.mime,
    required this.originalBytes,
    required this.encodedBytes,
    required this.width,
    required this.height,
    required this.compressed,
  });
}

/// 将本地图片压成适合 OpenAI 兼容中转的 data URL。
///
/// 策略（兼容官方 + 多数 OneAPI/NewAPI 中转）：
/// 1. 魔数识别真实 MIME（不盲信扩展名）
/// 2. 长边缩到 [maxLongEdge]
/// 3. 统一输出 JPEG（体积稳、兼容最好；透明 PNG 会铺白底）
/// 4. 控制编码后体积，避免网关 body limit / 超时
class VisionImageEncoder {
  /// 长边上限。OpenAI high detail 按 2048 切块；1536 在清晰度与体积间更稳。
  static const int defaultMaxLongEdge = 1536;

  /// 编码后原始字节上限（base64 前）。约 1.5MB raw → base64 ~2MB。
  static const int defaultMaxEncodedBytes = 1500 * 1024;

  /// 读前原始文件硬上限，超过直接放弃（防 OOM）
  static const int hardReadLimitBytes = 25 * 1024 * 1024;

  /// 单次请求建议最多附图数（与 AIService 历史凑图上限对齐）
  static const int maxImagesPerRequest = 3;

  const VisionImageEncoder();

  /// 编码本地路径为 `data:image/jpeg;base64,...`
  Future<VisionImagePayload?> encodeFile(
    String path, {
    int maxLongEdge = defaultMaxLongEdge,
    int maxEncodedBytes = defaultMaxEncodedBytes,
    int quality = 82,
  }) async {
    try {
      final file = File(path);
      if (!await file.exists()) {
        debugPrint('[VisionImage] 文件不存在: $path');
        return null;
      }

      final originalBytes = await file.length();
      if (originalBytes <= 0) {
        debugPrint('[VisionImage] 空文件: $path');
        return null;
      }
      if (originalBytes > hardReadLimitBytes) {
        debugPrint(
            '[VisionImage] 文件过大已跳过: ${originalBytes}B path=$path');
        return null;
      }

      final raw = await file.readAsBytes();
      final sniffed = sniffMime(raw) ?? mimeFromPath(path);

      // 已是小图 JPEG：可直接 data URL，少一次重编码损失
      if (sniffed == 'image/jpeg' &&
          raw.length <= maxEncodedBytes &&
          raw.length <= 800 * 1024) {
        // 仍尝试读尺寸用于日志；失败则当 0
        final decodedSmall = img.decodeImage(raw);
        if (decodedSmall != null) {
          final longEdge = decodedSmall.width > decodedSmall.height
              ? decodedSmall.width
              : decodedSmall.height;
          if (longEdge <= maxLongEdge) {
            return VisionImagePayload(
              dataUrl: 'data:image/jpeg;base64,${base64Encode(raw)}',
              mime: 'image/jpeg',
              originalBytes: originalBytes,
              encodedBytes: raw.length,
              width: decodedSmall.width,
              height: decodedSmall.height,
              compressed: false,
            );
          }
        }
      }

      final decoded = img.decodeImage(raw);
      if (decoded == null) {
        // HEIC 等 image 包解不出的格式：若本身是 jpeg/png/webp/gif 且不太大，原样上传
        if (_isDirectlyUploadable(sniffed) &&
            raw.length <= maxEncodedBytes) {
          debugPrint(
              '[VisionImage] 无法重编码，原样上传 mime=$sniffed size=${raw.length}');
          return VisionImagePayload(
            dataUrl: 'data:$sniffed;base64,${base64Encode(raw)}',
            mime: sniffed ?? 'image/jpeg',
            originalBytes: originalBytes,
            encodedBytes: raw.length,
            width: 0,
            height: 0,
            compressed: false,
          );
        }
        debugPrint('[VisionImage] 解码失败 path=$path mime=$sniffed');
        return null;
      }

      var image = decoded;
      // 修正 EXIF 方向（部分手机竖图会横着）
      image = img.bakeOrientation(image);

      final longEdge =
          image.width > image.height ? image.width : image.height;
      if (longEdge > maxLongEdge) {
        if (image.width >= image.height) {
          image = img.copyResize(
            image,
            width: maxLongEdge,
            interpolation: img.Interpolation.linear,
          );
        } else {
          image = img.copyResize(
            image,
            height: maxLongEdge,
            interpolation: img.Interpolation.linear,
          );
        }
      }

      // 透明通道 → 白底，避免 JPEG 变黑
      if (image.numChannels == 4) {
        final flat = img.Image(
          width: image.width,
          height: image.height,
          numChannels: 3,
        );
        img.fill(flat, color: img.ColorRgb8(255, 255, 255));
        img.compositeImage(flat, image);
        image = flat;
      }

      var q = quality.clamp(40, 95);
      Uint8List encoded = Uint8List.fromList(img.encodeJpg(image, quality: q));

      // 超体积则降质量 / 再缩一次
      var guard = 0;
      while (encoded.length > maxEncodedBytes && guard < 6) {
        guard++;
        if (q > 55) {
          q -= 10;
        } else {
          final nextW = (image.width * 0.82).round().clamp(320, maxLongEdge);
          image = img.copyResize(
            image,
            width: nextW,
            interpolation: img.Interpolation.linear,
          );
        }
        encoded = Uint8List.fromList(img.encodeJpg(image, quality: q));
      }

      if (encoded.length > maxEncodedBytes) {
        debugPrint(
            '[VisionImage] 压缩后仍过大: ${encoded.length}B path=$path');
        return null;
      }

      final payload = VisionImagePayload(
        dataUrl: 'data:image/jpeg;base64,${base64Encode(encoded)}',
        mime: 'image/jpeg',
        originalBytes: originalBytes,
        encodedBytes: encoded.length,
        width: image.width,
        height: image.height,
        compressed: true,
      );
      debugPrint(
          '[VisionImage] ok ${payload.width}x${payload.height} '
          '${payload.originalBytes}B→${payload.encodedBytes}B q=$q path=$path');
      return payload;
    } catch (e) {
      debugPrint('[VisionImage] 编码失败: $e path=$path');
      return null;
    }
  }

  /// 魔数嗅探 MIME
  static String? sniffMime(List<int> bytes) {
    if (bytes.length < 12) return null;
    // JPEG
    if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
      return 'image/jpeg';
    }
    // PNG
    if (bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'image/png';
    }
    // GIF
    if (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46) {
      return 'image/gif';
    }
    // WEBP: RIFF....WEBP
    if (bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return 'image/webp';
    }
    // BMP
    if (bytes[0] == 0x42 && bytes[1] == 0x4D) {
      return 'image/bmp';
    }
    return null;
  }

  static String? mimeFromPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.bmp')) return 'image/bmp';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    if (lower.endsWith('.heic') || lower.endsWith('.heif')) {
      return 'image/heic';
    }
    return null;
  }

  static bool _isDirectlyUploadable(String? mime) {
    return mime == 'image/jpeg' ||
        mime == 'image/png' ||
        mime == 'image/webp' ||
        mime == 'image/gif';
  }

  /// OpenAI `image_url.detail`：单图 auto，多图 low 省 token/带宽
  static String detailForCount(int imageCount) {
    if (imageCount <= 1) return 'auto';
    return 'low';
  }

  /// 从 API 错误文案判断是否 vision / 体积相关
  static String? friendlyVisionError(String? rawMessage) {
    if (rawMessage == null || rawMessage.trim().isEmpty) return null;
    final m = rawMessage.toLowerCase();
    if (m.contains('image') &&
        (m.contains('not support') ||
            m.contains('unsupported') ||
            m.contains('does not support') ||
            m.contains('vision') ||
            m.contains('multimodal') ||
            m.contains('invalid_image') ||
            m.contains('cannot identify image'))) {
      return '当前模型或中转站不支持看图。请确认：① AI 配置已勾选「多模态」；② 模型本身支持 vision（如 gpt-4o / qwen-vl）；③ 中转站已开通该模型的多模态。';
    }
    if ((m.contains('payload') && m.contains('large')) ||
        m.contains('request entity too large') ||
        m.contains('body size') ||
        (m.contains('too large') &&
            (m.contains('image') || m.contains('request'))) ||
        (m.contains('context length') && m.contains('image')) ||
        m.contains('maximum context length')) {
      return '图片请求体积过大或超出上下文限制。请少发几张、或换更清晰的中转/模型后再试。';
    }
    if (m.contains('invalid_base64') ||
        m.contains('base64') && m.contains('invalid') ||
        m.contains('invalid image url') ||
        m.contains('failed to download') && m.contains('image')) {
      return '图片编码或格式不被中转站接受。请换一张 JPG/PNG 再试。';
    }
    return null;
  }
}
