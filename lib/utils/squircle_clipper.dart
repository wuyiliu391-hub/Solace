import 'dart:math';
import 'package:flutter/rendering.dart';

/// iOS 风格的 squircle (超椭圆) 裁剪路径
///
/// 使用 n=5 超椭圆的贝塞尔近似，k = 0.551784
/// 圆角半径 = 宽度 × 0.2237 (iOS 标准)
class SquircleClipper extends CustomClipper<Path> {
  final double radius;
  const SquircleClipper(this.radius);

  @override
  Path getClip(Size size) {
    final r = min(radius, min(size.width, size.height) / 2);
    final w = size.width;
    final h = size.height;
    const k = 0.551784;

    return Path()
      ..moveTo(r, 0)
      ..lineTo(w - r, 0)
      ..cubicTo(w - r + r * k, 0, w, r - r * k, w, r)
      ..lineTo(w, h - r)
      ..cubicTo(w, h - r + r * k, w - r + r * k, h, w - r, h)
      ..lineTo(r, h)
      ..cubicTo(r - r * k, h, 0, h - r + r * k, 0, h - r)
      ..lineTo(0, r)
      ..cubicTo(0, r - r * k, r - r * k, 0, r, 0)
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

/// iOS squircle 圆角半径计算
double squircleRadius(double size) => size * 0.2237;
