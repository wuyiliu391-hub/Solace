import 'package:flutter/material.dart';

/// 解析角色主题色（对标 ST 角色卡 color 字段）：
/// 1. colorHex（#RRGGBB / RRGGBB）配置优先；
/// 2. 否则按名字哈希生成稳定色相（同一角色永远同色）；
/// 3. 深色模式提亮明度保证可读性。
Color characterColor({
  String? colorHex,
  required String name,
  required ColorScheme cs,
}) {
  if (colorHex != null) {
    final hex = colorHex.replaceAll('#', '').trim();
    if (hex.length == 6 || hex.length == 8) {
      final v = int.tryParse(hex.substring(0, 6), radix: 16);
      if (v != null) return Color(0xFF000000 | v);
    }
  }
  var hash = 0;
  for (final c in name.codeUnits) {
    hash = (hash * 31 + c) & 0x7fffffff;
  }
  final hue = (hash % 360).toDouble();
  final isDark = cs.brightness == Brightness.dark;
  return HSVColor.fromAHSV(1, hue, 0.62, isDark ? 0.85 : 0.62).toColor();
}

/// 群聊成员颜色映射（防撞色混淆）：
/// 1. colorHex 配置优先且保留（用户显式指定）；
/// 2. 哈希色相互相去重：色相差 < 30° 时后一个角色色相偏移 30°，
///    保证多角色群聊中相邻成员颜色可区分（解决「头像/身份混淆」）。
/// 返回 角色 id → 颜色。
Map<String, Color> groupMemberColors({
  required List<String> memberIds,
  required Color Function(String id) resolve,
  required double minHueGap,
}) {
  final result = <String, Color>{};
  final usedHues = <double>{};
  for (final id in memberIds) {
    final color = resolve(id);
    var hsv = HSVColor.fromColor(color);
    var guard = 0;
    while (guard < 12 &&
        usedHues.any((h) {
          // 环形色相差：(-30)%360 在 Dart 中为负，需归一化
          final delta = (((hsv.hue - h) % 360) + 360) % 360;
          final gap = delta < 180 ? delta : 360 - delta;
          return gap < minHueGap;
        })) {
      hsv = hsv.withHue((hsv.hue + minHueGap) % 360);
      guard++;
    }
    usedHues.add(hsv.hue);
    result[id] = hsv.toColor();
  }
  return result;
}
