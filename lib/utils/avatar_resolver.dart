import 'dart:io';
import 'package:flutter/material.dart';

/// 头像解析工具 — 统一处理所有头像 URL 类型
///
/// 支持的格式：
/// - `asset:assets/xxx.png` → 内置资源头像
/// - `/path/to/file` 或 `C:\path` → 本地文件头像
/// - `http://` / `https://` → 网络头像
/// - `solace://` → 本地文件（旧格式兼容）
class AvatarResolver {
  AvatarResolver._();

  /// 判断头像 URL 是否为内置资源
  static bool isAsset(String? url) =>
      url != null && url.startsWith('asset:');

  /// 判断头像 URL 是否为本地文件路径
  static bool isFile(String? url) {
    if (url == null || url.isEmpty) return false;
    return url.startsWith('/') ||
        url.startsWith('C:') ||
        url.startsWith('D:') ||
        url.startsWith('\\') ||
        url.startsWith('solace://');
  }

  /// 判断头像 URL 是否为网络地址
  static bool isNetwork(String? url) =>
      url != null && (url.startsWith('http://') || url.startsWith('https://'));

  /// 将 asset: 前缀转为纯资源路径
  static String? assetPath(String? url) {
    if (url == null) return null;
    if (url.startsWith('asset:')) return url.replaceFirst('asset:', '');
    return null;
  }

  /// 根据 URL 返回对应的 [ImageProvider]
  ///
  /// 返回 null 表示无法解析，调用方可回退到默认头像。
  static ImageProvider? imageProvider(String? url) {
    if (url == null || url.isEmpty) return null;

    if (url.startsWith('asset:')) {
      final path = url.replaceFirst('asset:', '');
      return AssetImage(path);
    }

    if (url.startsWith('http://') || url.startsWith('https://')) {
      return NetworkImage(url);
    }

    // solace:// 旧格式 → 转为文件路径
    if (url.startsWith('solace://')) {
      final path = url.replaceFirst('solace://', '');
      return FileImage(File(path));
    }

    // 本地文件路径（/xxx, C:\xxx, D:\xxx 等）
    if (url.startsWith('/') ||
        url.startsWith('C:') ||
        url.startsWith('D:') ||
        url.startsWith('\\')) {
      return FileImage(File(url));
    }

    return null;
  }

  /// 构建头像 Image Widget（带 errorBuilder 回退）
  ///
  /// [size] 图片宽高，[fit] 填充模式。
  /// 无法解析时返回 null，调用方应回退到默认头像。
  static Widget? imageWidget(
    String? url, {
    double? width,
    double? height,
    BoxFit fit = BoxFit.cover,
    Widget Function()? onError,
  }) {
    if (url == null || url.isEmpty) return null;

    if (url.startsWith('asset:')) {
      final path = url.replaceFirst('asset:', '');
      return Image.asset(
        path,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, __, ___) =>
            onError?.call() ?? const SizedBox.shrink(),
      );
    }

    if (url.startsWith('http://') || url.startsWith('https://')) {
      return Image.network(
        url,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, __, ___) =>
            onError?.call() ?? const SizedBox.shrink(),
      );
    }

    // solace:// 旧格式
    if (url.startsWith('solace://')) {
      final path = url.replaceFirst('solace://', '');
      return Image.file(
        File(path),
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, __, ___) =>
            onError?.call() ?? const SizedBox.shrink(),
      );
    }

    // 本地文件路径
    if (url.startsWith('/') ||
        url.startsWith('C:') ||
        url.startsWith('D:') ||
        url.startsWith('\\')) {
      return Image.file(
        File(url),
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, __, ___) =>
            onError?.call() ?? const SizedBox.shrink(),
      );
    }

    return null;
  }
}
