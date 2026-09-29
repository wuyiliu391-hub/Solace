import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/utils/character_color.dart';

void main() {
  const light = ColorScheme.light();
  const dark = ColorScheme.dark();

  test('同名同色：同一角色永远同一颜色', () {
    final a = characterColor(name: '小夜', cs: light);
    final b = characterColor(name: '小夜', cs: light);
    expect(a, b);
  });

  test('不同名大概率不同色', () {
    final colors = <Color>{
      for (final n in ['小夜', '阿夏', '露娜', '白夜', '千羽'])
        characterColor(name: n, cs: light),
    };
    expect(colors.length, greaterThanOrEqualTo(4));
  });

  test('colorHex 配置优先', () {
    final c = characterColor(colorHex: '#E53935', name: '小夜', cs: light);
    expect(c, const Color(0xFFE53935));
  });

  test('浅色/深色模式都返回可读色（与背景对比）', () {
    for (final cs in [light, dark]) {
      final c = characterColor(name: '小夜', cs: cs);
      // 亮度不在极端区间（不会和背景糊一起）
      final luminance = c.computeLuminance();
      expect(luminance, greaterThan(0.05));
      expect(luminance, lessThan(0.95));
    }
  });
}
