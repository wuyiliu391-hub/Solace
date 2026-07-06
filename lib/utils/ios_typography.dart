import 'dart:io';
import 'package:flutter/widgets.dart';

class IOSTypography {
  IOSTypography._();

  static String get fontFamily {
    if (Platform.isIOS) return '.SF Pro Text';
    return 'Inter';
  }

  /// 锁屏时间 — 大号纤细字体
  static TextStyle lockTime({Color color = const Color(0xFFFFFFFF)}) =>
      TextStyle(
        fontFamily: fontFamily,
        fontSize: 82,
        fontWeight: FontWeight.w100,
        height: 1.0,
        letterSpacing: -2,
        color: color,
      );

  /// 锁屏日期
  static TextStyle lockDate({Color color = const Color(0xFFFFFFFF)}) =>
      TextStyle(
        fontFamily: fontFamily,
        fontSize: 20,
        fontWeight: FontWeight.w300,
        height: 1.2,
        color: color,
      );

  /// 图标标签
  static TextStyle iconLabel(
    double fontSize, {
    Color color = const Color(0xFFFFFFFF),
  }) =>
      TextStyle(
        fontFamily: fontFamily,
        fontSize: fontSize,
        fontWeight: FontWeight.w400,
        height: 1.2,
        color: color,
        shadows: [
          Shadow(
            color: const Color(0x4D000000), // black 30%
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      );

  /// 上滑解锁提示
  static TextStyle unlockHint({Color color = const Color(0x99FFFFFF)}) =>
      TextStyle(
        fontFamily: fontFamily,
        fontSize: 13,
        fontWeight: FontWeight.w400,
        height: 1.2,
        color: color,
      );
}
