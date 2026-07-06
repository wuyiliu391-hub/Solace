// ============================================================
// 年龄提取器 — 从角色背景故事中自动提取年龄
// ============================================================

import 'package:flutter/foundation.dart';

class AgeExtractor {
  AgeExtractor._();

  /// 从文本中提取年龄
  ///
  /// 支持格式：
  /// - "22岁" / "22 歲" / "22-year-old"
  /// - "年龄22" / "年龄：22"
  /// - "二十二岁" / "二十岁"
  /// - "20多岁" → 20
  /// - "十几岁" → 15
  ///
  /// 返回 null 表示未找到明确年龄
  static int? extract(String? text) {
    if (text == null || text.isEmpty) return null;

    // 数字 + 岁/歲
    final agePattern1 = RegExp(r'(\d{1,3})\s*[岁歲]');
    final match1 = agePattern1.firstMatch(text);
    if (match1 != null) {
      final age = int.tryParse(match1.group(1)!);
      if (age != null && age >= 1 && age <= 150) {
        debugPrint('[AgeExtractor] 提取年龄: $age (from "$text")');
        return age;
      }
    }

    // 年龄：XX / 年龄XX
    final agePattern2 = RegExp(r'年龄[：:]?\s*(\d{1,3})');
    final match2 = agePattern2.firstMatch(text);
    if (match2 != null) {
      final age = int.tryParse(match2.group(1)!);
      if (age != null && age >= 1 && age <= 150) {
        debugPrint('[AgeExtractor] 提取年龄: $age (from "$text")');
        return age;
      }
    }

    // XX-year-old
    final agePattern3 = RegExp(r'(\d{1,3})\s*-\s*year\s*-\s*old');
    final match3 = agePattern3.firstMatch(text);
    if (match3 != null) {
      final age = int.tryParse(match3.group(1)!);
      if (age != null && age >= 1 && age <= 150) {
        debugPrint('[AgeExtractor] 提取年龄: $age (from "$text")');
        return age;
      }
    }

    // 中文数字：十几岁 → 15
    final agePattern4 = RegExp(r'十几岁');
    if (agePattern4.hasMatch(text)) {
      debugPrint('[AgeExtractor] 提取年龄: 15 (from "十几岁")');
      return 15;
    }

    // 二十多岁 / 三十多岁 → 取整十
    final agePattern5 = RegExp(r'(二十|三十|四十|五十|六十|七十|八十|九十)多岁');
    final match5 = agePattern5.firstMatch(text);
    if (match5 != null) {
      final cnNum = match5.group(1)!;
      final base = _cnToInt(cnNum);
      if (base != null) {
        debugPrint('[AgeExtractor] 提取年龄: $base (from "$cnNum多岁")');
        return base;
      }
    }

    // 中文数字 + 岁：二十二岁、三十五岁
    final agePattern6 = RegExp(r'([一二三四五六七八九十百]+)岁');
    final match6 = agePattern6.firstMatch(text);
    if (match6 != null) {
      final age = _cnToInt(match6.group(1)!);
      if (age != null && age >= 1 && age <= 150) {
        debugPrint('[AgeExtractor] 提取年龄: $age (from "${match6.group(0)}")');
        return age;
      }
    }

    debugPrint('[AgeExtractor] 未找到明确年龄');
    return null;
  }

  /// 中文数字转整数（简单版，支持 1-99）
  static int? _cnToInt(String cn) {
    const cnDigits = {
      '零': 0, '一': 1, '二': 2, '三': 3, '四': 4,
      '五': 5, '六': 6, '七': 7, '八': 8, '九': 9,
      '十': 10, '百': 100,
    };

    if (cn.isEmpty) return null;

    // 单独的"十"
    if (cn == '十') return 10;

    // 十X
    if (cn.startsWith('十')) {
      final rest = cn.substring(1);
      final r = cnDigits[rest];
      if (r != null) return 10 + r;
    }

    // X十
    if (cn.endsWith('十')) {
      final first = cn.substring(0, cn.length - 1);
      final f = cnDigits[first];
      if (f != null) return f * 10;
    }

    // X十Y
    if (cn.contains('十')) {
      final parts = cn.split('十');
      if (parts.length == 2) {
        final f = cnDigits[parts[0]];
        final r = parts[1].isEmpty ? 0 : cnDigits[parts[1]];
        if (f != null && r != null) return f * 10 + r;
      }
    }

    // 单个数字
    return cnDigits[cn];
  }
}
