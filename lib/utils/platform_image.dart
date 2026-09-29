import 'dart:convert' show base64Decode;
import 'dart:io' show File;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// 跨平台安全的图片 Provider
/// - Web 端：支持 data:image URI 和网络 URL
/// - 原生端：支持本地文件路径和网络 URL
ImageProvider? safeImageProvider(String? path) {
  if (path == null || path.isEmpty) return null;

  // 网络 URL 两端通用
  if (path.startsWith('http://') || path.startsWith('https://')) {
    return NetworkImage(path);
  }

  if (kIsWeb) {
    // Web 端：data URI 转 MemoryImage
    if (path.startsWith('data:image')) {
      try {
        final bytes = Uri.parse(path).data?.contentAsBytes();
        if (bytes != null) return MemoryImage(bytes);
      } catch (_) {
        // fallback: 手动 base64 解码
        try {
          final parts = path.split(',');
          if (parts.length == 2) {
            return MemoryImage(base64Decode(parts[1]));
          }
        } catch (_) {}
      }
    }
    return null;
  }

  // 原生端：本地文件路径
  try {
    return FileImage(File(path));
  } catch (_) {
    return null;
  }
}

/// 跨平台安全的图片 Widget
Widget safeImage(
  String? path, {
  BoxFit fit = BoxFit.cover,
  double? width,
  double? height,
  Widget? placeholder,
}) {
  final provider = safeImageProvider(path);
  if (provider == null) {
    return placeholder ??
        Icon(Icons.person, size: width ?? 40, color: Colors.grey);
  }
  return Image(
    image: provider,
    fit: fit,
    width: width,
    height: height,
    errorBuilder: (_, __, ___) =>
        placeholder ?? Icon(Icons.person, size: width ?? 40, color: Colors.grey),
  );
}