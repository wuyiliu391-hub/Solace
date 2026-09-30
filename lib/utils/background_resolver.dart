import 'dart:io';

import 'package:flutter/material.dart';

/// 按当前屏幕朝向挑选背景图。
///
/// 背景图分横竖屏两张存储；只设了一边时另一方向回退到已设的那张，
/// 避免用户只配了一边就出现半边空白。渲染背景的地方统一走这里，
/// 免得各处各写一遍 if。
class BackgroundResolver {
  BackgroundResolver._();

  /// [portrait] 语义为竖屏背景，[landscape] 为横屏背景（可空）。
  static String? resolve({
    String? portrait,
    String? landscape,
    bool? isLandscape,
  }) {
    final wide = isLandscape ? _clean(landscape) : _clean(portrait);
    // 本朝向没有就回退到另一朝向
    return wide ?? _clean(isLandscape ? portrait : landscape);
  }

  /// 直接给 ImageProvider；无图返回 null（调用方决定退化样式）。
  static ImageProvider? provider({
    String? portrait,
    String? landscape,
    bool? isLandscape,
  }) {
    final p = resolve(
        portrait: portrait, landscape: landscape, isLandscape: isLandscape);
    if (p == null) return null;
    if (p.startsWith('http://') || p.startsWith('https://')) {
      return NetworkImage(p);
    }
    return FileImage(File(p));
  }

  static String? _clean(String? p) {
    if (p == null) return null;
    final t = p.trim();
    return t.isEmpty ? null : t;
  }
}
