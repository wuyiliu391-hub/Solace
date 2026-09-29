// 群聊角色色相去重测试：多角色群聊防撞色（头像/身份混淆修复）。
//
// 问题：characterColor 哈希色相 0-359，多角色（7+）时色相相近 → 角色气泡
// 颜色无法区分 → 视觉上「身份混淆」。
// 修复：groupMemberColors 对哈希色做环形色相去重（色相差 < 30° 偏移）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/utils/character_color.dart';

void main() {
  // 从色卡反查色相
  double hueOf(Color c) => HSVColor.fromColor(c).hue;

  /// 环形色相差（0-180）
  double hueGap(double a, double b) {
    final delta = ((a - b) % 360 + 360) % 360;
    return delta < 180 ? delta : 360 - delta;
  }

  test('相近哈希色相被去重：两两色相差 >= 30°', () {
    // 构造 8 个名字，全部无 colorHex（哈希色）
    final names = ['小明', '小美', '小红', '阿强', '阿珍', '莉莉', '娜娜', '小刚'];
    final colors = groupMemberColors(
      memberIds: names,
      resolve: (id) => characterColor(
        colorHex: null,
        name: id,
        cs: ThemeData.light().colorScheme,
      ),
      minHueGap: 30,
    );

    // 两两色相差检查
    final hues = names.map((n) => hueOf(colors[n]!)).toList();
    for (var i = 0; i < hues.length; i++) {
      for (var j = i + 1; j < hues.length; j++) {
        final gap = hueGap(hues[i], hues[j]);
        expect(gap >= 30,
            isTrue,
            reason: '$names[i] 与 $names[j] 色相差仅 ${gap.toStringAsFixed(1)}°');
      }
    }
  });

  test('显式 colorHex 保留：指定色不被偏移', () {
    final colors = groupMemberColors(
      memberIds: ['a', 'b'],
      resolve: (id) => id == 'a'
          ? const Color(0xFF001E8F) // 克莱因蓝（显式指定）
          : characterColor(colorHex: null, name: 'b', cs: ThemeData.light().colorScheme),
      minHueGap: 30,
    );
    expect(colors['a'], const Color(0xFF001E8F), reason: '指定色必须原样保留');
  });

  test('同一输入确定性：两次调用结果一致', () {
    final names = ['小明', '小美', '小红'];
    final cs = ThemeData.light().colorScheme;
    final c1 = groupMemberColors(
      memberIds: names,
      resolve: (id) => characterColor(colorHex: null, name: id, cs: cs),
      minHueGap: 30,
    );
    final c2 = groupMemberColors(
      memberIds: names,
      resolve: (id) => characterColor(colorHex: null, name: id, cs: cs),
      minHueGap: 30,
    );
    for (final n in names) {
      expect(c1[n], c2[n], reason: '$n 的颜色必须稳定');
    }
  });

  test('单角色不退化为异常：返回自身颜色', () {
    final colors = groupMemberColors(
      memberIds: ['solo'],
      resolve: (id) => characterColor(
          colorHex: null, name: id, cs: ThemeData.light().colorScheme),
      minHueGap: 30,
    );
    expect(colors.length, 1);
    expect(colors['solo'], isNotNull);
  });
}
