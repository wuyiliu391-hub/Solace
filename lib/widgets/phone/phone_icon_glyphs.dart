import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 为关键桌面图标绘制比 Material 更「软、圆、厚」的矢量符号。
/// 坐标约定：画在 0..1 的逻辑方框内，由调用方做缩放。
class PhoneIconGlyphs {
  PhoneIconGlyphs._();

  static void paint(
    Canvas canvas,
    Size size,
    String id, {
    Color color = Colors.white,
  }) {
    final s = size.shortestSide;
    canvas.save();
    canvas.translate((size.width - s) / 2, (size.height - s) / 2);
    canvas.scale(s, s);

    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.07
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    // A 档立体优先
    switch (id) {
      case 'phone':
        _phone3d(canvas, color);
        break;
      case 'chat':
        _chat3d(canvas, color);
        break;
      case 'wallet':
        _wallet3d(canvas, color);
        break;
      case 'shop':
        _shop3d(canvas, color);
        break;
      case 'diary':
        _diary3d(canvas, color);
        break;
      case 'memory':
        _memory3d(canvas, color);
        break;
      case 'contacts':
        _contacts3d(canvas, color);
        break;
      case 'settings':
        _settings3d(canvas, color);
        break;
      case 'moments':
        _moments3d(canvas, color);
        break;
      case 'notes':
        _notes3d(canvas, color);
        break;
      case 'power':
        _power3d(canvas, color);
        break;
      case 'tarot':
      case 'oracle':
        _oracle3d(canvas, color);
        break;
      case 'music':
        _music3d(canvas, color);
        break;
      case 'story':
      case 'destiny':
        _book3d(canvas, color);
        break;
      case 'mailbox':
        _mail3d(canvas, color);
        break;
      case 'calendar':
        _calendar3d(canvas, color);
        break;
      case 'inspiration':
        _bulb3d(canvas, color);
        break;
      case 'coins':
        _coins3d(canvas, color);
        break;
      case 'love_lab':
        _flask3d(canvas, color);
        break;
      case 'love_sign':
        _cup3d(canvas, color);
        break;
      case 'reading':
        _openBook3d(canvas, color);
        break;
      case 'guide':
        _guide3d(canvas, color);
        break;
      case 'store':
        _store3d(canvas, color);
        break;
      case 'forum':
        _forum3d(canvas, color);
        break;
      case 'map':
        _map(canvas, fill, stroke);
        break;
      default:
        _spark(canvas, fill);
        break;
    }
    canvas.restore();
  }


  // ── A 档：多层立体核心图标 ──
  // 约定：投影 → 主体 → 厚度/内面 → 高光 → 细节

  static Paint _p(Color c, [double a = 1]) => Paint()
    ..color = c.withValues(alpha: a)
    ..style = PaintingStyle.fill
    ..isAntiAlias = true;

  static void _shade(Canvas c, Path path, Offset o, Color base) {
    c.drawPath(path.shift(o), _p(base, 0.22));
  }

  static void _phone3d(Canvas c, Color color) {
    c.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0.30, 0.78, 0.40, 0.10),
        const Radius.circular(0.05),
      ),
      _p(const Color(0xFF000000), 0.12),
    );

    final body = RRect.fromRectAndRadius(
      const Rect.fromLTWH(0.27, 0.12, 0.46, 0.74),
      const Radius.circular(0.13),
    );
    final bodyPath = Path()..addRRect(body);
    _shade(c, bodyPath, const Offset(0.02, 0.03), const Color(0xFF000000));

    c.drawRRect(body, _p(color, 0.95));
    c.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0.31, 0.16, 0.38, 0.66),
        const Radius.circular(0.10),
      ),
      _p(Colors.white, 0.18),
    );
    c.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0.33, 0.22, 0.34, 0.48),
        const Radius.circular(0.06),
      ),
      _p(Colors.white, 0.28),
    );
    final spec = Path()
      ..moveTo(0.36, 0.24)
      ..lineTo(0.48, 0.24)
      ..lineTo(0.40, 0.68)
      ..lineTo(0.34, 0.68)
      ..close();
    c.drawPath(spec, _p(Colors.white, 0.22));
    c.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0.40, 0.17, 0.20, 0.028),
        const Radius.circular(0.014),
      ),
      _p(Colors.white, 0.45),
    );
    c.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0.42, 0.74, 0.16, 0.028),
        const Radius.circular(0.014),
      ),
      _p(Colors.white, 0.50),
    );
    c.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0.30, 0.13, 0.40, 0.04),
        const Radius.circular(0.02),
      ),
      _p(Colors.white, 0.35),
    );
  }

  static void _chat3d(Canvas c, Color color) {
    c.drawOval(
      const Rect.fromLTWH(0.22, 0.72, 0.52, 0.12),
      _p(const Color(0xFF000000), 0.10),
    );

    final main = Path()
      ..moveTo(0.20, 0.30)
      ..cubicTo(0.20, 0.16, 0.34, 0.14, 0.50, 0.14)
      ..cubicTo(0.72, 0.14, 0.84, 0.22, 0.84, 0.38)
      ..cubicTo(0.84, 0.54, 0.70, 0.62, 0.52, 0.62)
      ..lineTo(0.40, 0.62)
      ..lineTo(0.26, 0.78)
      ..lineTo(0.30, 0.62)
      ..cubicTo(0.22, 0.60, 0.20, 0.48, 0.20, 0.38)
      ..close();
    _shade(c, main, const Offset(0.02, 0.03), const Color(0xFF000000));
    c.drawPath(main, _p(color, 0.96));

    final inner = Path()
      ..moveTo(0.28, 0.34)
      ..cubicTo(0.28, 0.24, 0.38, 0.22, 0.50, 0.22)
      ..cubicTo(0.68, 0.22, 0.76, 0.28, 0.76, 0.38)
      ..cubicTo(0.76, 0.50, 0.64, 0.54, 0.50, 0.54)
      ..lineTo(0.42, 0.54)
      ..lineTo(0.34, 0.64)
      ..lineTo(0.36, 0.54)
      ..cubicTo(0.30, 0.52, 0.28, 0.44, 0.28, 0.38)
      ..close();
    c.drawPath(inner, _p(Colors.white, 0.16));

    final sub = RRect.fromRectAndRadius(
      const Rect.fromLTWH(0.40, 0.40, 0.40, 0.26),
      const Radius.circular(0.12),
    );
    c.drawRRect(sub.shift(const Offset(0.015, 0.02)), _p(const Color(0xFF000000), 0.12));
    c.drawRRect(sub, _p(Colors.white, 0.30));
    c.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0.44, 0.44, 0.32, 0.18),
        const Radius.circular(0.08),
      ),
      _p(Colors.white, 0.18),
    );

    final d = _p(Colors.white, 0.75);
    c.drawCircle(const Offset(0.48, 0.53), 0.025, d);
    c.drawCircle(const Offset(0.58, 0.53), 0.025, d);
    c.drawCircle(const Offset(0.68, 0.53), 0.025, d);

    c.drawOval(
      const Rect.fromLTWH(0.28, 0.20, 0.28, 0.12),
      _p(Colors.white, 0.28),
    );
  }

  static void _wallet3d(Canvas c, Color color) {
    c.drawOval(
      const Rect.fromLTWH(0.20, 0.74, 0.58, 0.12),
      _p(const Color(0xFF000000), 0.10),
    );

    final back = RRect.fromRectAndRadius(
      const Rect.fromLTWH(0.16, 0.28, 0.68, 0.46),
      const Radius.circular(0.12),
    );
    c.drawRRect(back.shift(const Offset(0.02, 0.03)), _p(const Color(0xFF000000), 0.18));
    c.drawRRect(back, _p(color, 0.75));

    final front = RRect.fromRectAndRadius(
      const Rect.fromLTWH(0.16, 0.38, 0.68, 0.40),
      const Radius.circular(0.12),
    );
    c.drawRRect(front, _p(color, 0.98));

    c.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0.16, 0.36, 0.68, 0.08),
        const Radius.circular(0.04),
      ),
      _p(Colors.white, 0.14),
    );

    c.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0.28, 0.24, 0.44, 0.12),
        const Radius.circular(0.04),
      ),
      _p(Colors.white, 0.42),
    );
    c.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0.32, 0.26, 0.36, 0.08),
        const Radius.circular(0.03),
      ),
      _p(color, 0.35),
    );

    final clasp = RRect.fromRectAndRadius(
      const Rect.fromLTWH(0.54, 0.48, 0.24, 0.18),
      const Radius.circular(0.05),
    );
    c.drawRRect(clasp.shift(const Offset(0.01, 0.01)), _p(const Color(0xFF000000), 0.15));
    c.drawRRect(clasp, _p(Colors.white, 0.38));
    c.drawCircle(const Offset(0.66, 0.57), 0.035, _p(Colors.white, 0.85));
    c.drawCircle(const Offset(0.66, 0.57), 0.016, _p(color, 0.55));

    c.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0.20, 0.42, 0.14, 0.28),
        const Radius.circular(0.05),
      ),
      _p(Colors.white, 0.20),
    );
  }

  static void _shop3d(Canvas c, Color color) {
    c.drawOval(
      const Rect.fromLTWH(0.24, 0.78, 0.50, 0.10),
      _p(const Color(0xFF000000), 0.10),
    );

    final bag = Path()
      ..moveTo(0.26, 0.38)
      ..lineTo(0.32, 0.80)
      ..cubicTo(0.34, 0.88, 0.40, 0.90, 0.50, 0.90)
      ..cubicTo(0.60, 0.90, 0.66, 0.88, 0.68, 0.80)
      ..lineTo(0.74, 0.38)
      ..close();
    _shade(c, bag, const Offset(0.02, 0.03), const Color(0xFF000000));
    c.drawPath(bag, _p(color, 0.96));

    final panel = Path()
      ..moveTo(0.34, 0.46)
      ..lineTo(0.38, 0.78)
      ..cubicTo(0.40, 0.84, 0.44, 0.85, 0.50, 0.85)
      ..cubicTo(0.56, 0.85, 0.60, 0.84, 0.62, 0.78)
      ..lineTo(0.66, 0.46)
      ..close();
    c.drawPath(panel, _p(Colors.white, 0.16));

    final handlePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.07
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    final handleShadow = Paint()
      ..color = const Color(0x55000000)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.07
      ..strokeCap = StrokeCap.round;

    final h1 = Path()
      ..moveTo(0.38, 0.40)
      ..cubicTo(0.38, 0.18, 0.50, 0.14, 0.50, 0.14)
      ..cubicTo(0.50, 0.14, 0.62, 0.18, 0.62, 0.40);
    c.drawPath(h1.shift(const Offset(0.01, 0.015)), handleShadow);
    c.drawPath(h1, handlePaint);

    final hHi = Paint()
      ..color = Colors.white.withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.025
      ..strokeCap = StrokeCap.round;
    c.drawPath(
      Path()
        ..moveTo(0.40, 0.38)
        ..cubicTo(0.40, 0.22, 0.50, 0.18, 0.50, 0.18)
        ..cubicTo(0.50, 0.18, 0.60, 0.22, 0.60, 0.38),
      hHi,
    );

    final heart = Path()
      ..moveTo(0.50, 0.72)
      ..cubicTo(0.50, 0.72, 0.38, 0.64, 0.38, 0.56)
      ..cubicTo(0.38, 0.50, 0.43, 0.48, 0.47, 0.48)
      ..cubicTo(0.49, 0.48, 0.50, 0.50, 0.50, 0.52)
      ..cubicTo(0.50, 0.50, 0.51, 0.48, 0.53, 0.48)
      ..cubicTo(0.57, 0.48, 0.62, 0.50, 0.62, 0.56)
      ..cubicTo(0.62, 0.64, 0.50, 0.72, 0.50, 0.72)
      ..close();
    c.drawPath(heart.shift(const Offset(0.01, 0.01)), _p(const Color(0xFF000000), 0.15));
    c.drawPath(heart, _p(Colors.white, 0.88));

    c.drawLine(
      const Offset(0.30, 0.40),
      const Offset(0.70, 0.40),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.35)
        ..strokeWidth = 0.03
        ..strokeCap = StrokeCap.round,
    );
  }

  static void _diary3d(Canvas c, Color color) {
    c.drawOval(
      const Rect.fromLTWH(0.22, 0.78, 0.56, 0.10),
      _p(const Color(0xFF000000), 0.10),
    );

    final pages = RRect.fromRectAndRadius(
      const Rect.fromLTWH(0.28, 0.18, 0.52, 0.66),
      const Radius.circular(0.06),
    );
    c.drawRRect(pages.shift(const Offset(0.03, 0.02)), _p(const Color(0xFF000000), 0.16));
    c.drawRRect(pages, _p(Colors.white, 0.55));

    final cover = RRect.fromRectAndRadius(
      const Rect.fromLTWH(0.22, 0.16, 0.52, 0.66),
      const Radius.circular(0.08),
    );
    c.drawRRect(cover.shift(const Offset(0.015, 0.02)), _p(const Color(0xFF000000), 0.18));
    c.drawRRect(cover, _p(color, 0.98));

    c.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0.30, 0.18, 0.06, 0.62),
        const Radius.circular(0.03),
      ),
      _p(const Color(0xFF000000), 0.14),
    );
    c.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0.31, 0.19, 0.03, 0.60),
        const Radius.circular(0.015),
      ),
      _p(Colors.white, 0.20),
    );

    final corner = Path()
      ..moveTo(0.60, 0.16)
      ..lineTo(0.74, 0.16)
      ..lineTo(0.74, 0.30)
      ..lineTo(0.68, 0.30)
      ..lineTo(0.68, 0.22)
      ..lineTo(0.60, 0.22)
      ..close();
    c.drawPath(corner, _p(Colors.white, 0.40));

    const fx = 0.54;
    const fy = 0.48;
    for (var i = 0; i < 6; i++) {
      final a = i * math.pi / 3;
      final cx = fx + math.cos(a) * 0.08;
      final cy = fy + math.sin(a) * 0.08;
      c.drawOval(
        Rect.fromCenter(center: Offset(cx + 0.008, cy + 0.008), width: 0.09, height: 0.07),
        _p(const Color(0xFF000000), 0.10),
      );
      c.drawOval(
        Rect.fromCenter(center: Offset(cx, cy), width: 0.09, height: 0.07),
        _p(Colors.white, 0.82),
      );
      c.drawOval(
        Rect.fromCenter(center: Offset(cx - 0.01, cy - 0.01), width: 0.04, height: 0.03),
        _p(Colors.white, 0.35),
      );
    }
    c.drawCircle(const Offset(fx + 0.008, fy + 0.008), 0.035, _p(const Color(0xFF000000), 0.12));
    c.drawCircle(const Offset(fx, fy), 0.035, _p(Colors.white, 0.95));
    c.drawCircle(const Offset(fx - 0.008, fy - 0.008), 0.014, _p(Colors.white, 0.7));

    c.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0.26, 0.20, 0.18, 0.50),
        const Radius.circular(0.06),
      ),
      _p(Colors.white, 0.14),
    );
  }

  static void _memory3d(Canvas c, Color color) {
    c.drawOval(
      const Rect.fromLTWH(0.22, 0.78, 0.56, 0.10),
      _p(const Color(0xFF000000), 0.10),
    );

    for (final x in [0.36, 0.64]) {
      c.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x - 0.025, 0.14, 0.05, 0.14),
          const Radius.circular(0.02),
        ),
        _p(Colors.white, 0.55),
      );
      c.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x - 0.018, 0.15, 0.036, 0.10),
          const Radius.circular(0.015),
        ),
        _p(color, 0.45),
      );
    }

    final body = RRect.fromRectAndRadius(
      const Rect.fromLTWH(0.18, 0.24, 0.64, 0.56),
      const Radius.circular(0.11),
    );
    c.drawRRect(body.shift(const Offset(0.02, 0.03)), _p(const Color(0xFF000000), 0.18));
    c.drawRRect(body, _p(color, 0.96));

    c.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0.18, 0.24, 0.64, 0.16),
        const Radius.circular(0.11),
      ),
      _p(Colors.white, 0.22),
    );
    c.drawLine(
      const Offset(0.22, 0.40),
      const Offset(0.78, 0.40),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.25)
        ..strokeWidth = 0.02,
    );

    for (var row = 0; row < 2; row++) {
      for (var col = 0; col < 4; col++) {
        c.drawCircle(
          Offset(0.30 + col * 0.13, 0.50 + row * 0.12),
          0.028,
          _p(Colors.white, 0.22 + (row + col) % 2 * 0.08),
        );
      }
    }

    final heart = Path()
      ..moveTo(0.72, 0.58)
      ..cubicTo(0.72, 0.58, 0.58, 0.48, 0.58, 0.40)
      ..cubicTo(0.58, 0.34, 0.64, 0.32, 0.68, 0.32)
      ..cubicTo(0.70, 0.32, 0.72, 0.34, 0.72, 0.36)
      ..cubicTo(0.72, 0.34, 0.74, 0.32, 0.76, 0.32)
      ..cubicTo(0.80, 0.32, 0.86, 0.34, 0.86, 0.40)
      ..cubicTo(0.86, 0.48, 0.72, 0.58, 0.72, 0.58)
      ..close();
    c.drawPath(heart.shift(const Offset(0.01, 0.015)), _p(const Color(0xFF000000), 0.16));
    c.drawPath(heart, _p(Colors.white, 0.92));
    c.drawOval(
      const Rect.fromLTWH(0.62, 0.34, 0.08, 0.05),
      _p(Colors.white, 0.55),
    );

    c.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0.22, 0.28, 0.16, 0.40),
        const Radius.circular(0.06),
      ),
      _p(Colors.white, 0.14),
    );
  }

  // ── glyphs ──

  static void _contacts3d(Canvas c, Color color) {
    c.drawOval(const Rect.fromLTWH(0.22, 0.76, 0.56, 0.12), _p(const Color(0xFF000000), 0.10));
    final card = RRect.fromRectAndRadius(const Rect.fromLTWH(0.18, 0.20, 0.64, 0.60), const Radius.circular(0.12));
    c.drawRRect(card.shift(const Offset(0.02, 0.03)), _p(const Color(0xFF000000), 0.16));
    c.drawRRect(card, _p(color, 0.96));
    c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(0.22, 0.24, 0.56, 0.18), const Radius.circular(0.08)), _p(Colors.white, 0.16));
    c.drawCircle(const Offset(0.50, 0.42), 0.11, _p(Colors.white, 0.40));
    c.drawCircle(const Offset(0.50, 0.40), 0.07, _p(Colors.white, 0.55));
    c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(0.34, 0.56, 0.32, 0.14), const Radius.circular(0.07)), _p(Colors.white, 0.35));
    c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(0.22, 0.24, 0.14, 0.48), const Radius.circular(0.05)), _p(Colors.white, 0.14));
  }

  static void _settings3d(Canvas c, Color color) {
    c.drawOval(const Rect.fromLTWH(0.24, 0.76, 0.52, 0.12), _p(const Color(0xFF000000), 0.10));
    const cx = 0.5;
    const cy = 0.48;
    const outer = 0.30;
    const inner = 0.11;
    final path = Path();
    const teeth = 8;
    for (var i = 0; i < teeth; i++) {
      final a0 = i * math.pi * 2 / teeth - math.pi / teeth;
      final a1 = a0 + math.pi / teeth * 0.55;
      final a2 = a0 + math.pi / teeth;
      final a3 = a0 + math.pi / teeth * 1.45;
      void pt(double a, double r, {bool move = false}) {
        final x = cx + math.cos(a) * r;
        final y = cy + math.sin(a) * r;
        if (move) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      pt(a0, outer * 0.72, move: i == 0);
      pt(a1, outer);
      pt(a2, outer);
      pt(a3, outer * 0.72);
    }
    path.close();
    c.drawPath(path.shift(const Offset(0.015, 0.02)), _p(const Color(0xFF000000), 0.18));
    c.drawPath(path, _p(color, 0.96));
    c.drawCircle(const Offset(cx, cy), inner + 0.04, _p(Colors.white, 0.18));
    c.drawCircle(const Offset(cx, cy), inner, _p(Colors.white, 0.35));
    c.drawCircle(const Offset(cx - 0.03, cy - 0.04), 0.04, _p(Colors.white, 0.35));
  }

  static void _moments3d(Canvas c, Color color) {
    c.drawOval(const Rect.fromLTWH(0.20, 0.76, 0.58, 0.12), _p(const Color(0xFF000000), 0.10));
    final body = RRect.fromRectAndRadius(const Rect.fromLTWH(0.16, 0.28, 0.68, 0.48), const Radius.circular(0.12));
    c.drawRRect(body.shift(const Offset(0.02, 0.03)), _p(const Color(0xFF000000), 0.16));
    c.drawRRect(body, _p(color, 0.96));
    c.drawCircle(const Offset(0.50, 0.52), 0.16, _p(Colors.white, 0.22));
    c.drawCircle(const Offset(0.50, 0.52), 0.10, _p(Colors.white, 0.40));
    c.drawCircle(const Offset(0.50, 0.52), 0.045, _p(Colors.white, 0.75));
    c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(0.62, 0.34, 0.14, 0.09), const Radius.circular(0.03)), _p(Colors.white, 0.45));
    c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(0.20, 0.32, 0.16, 0.34), const Radius.circular(0.05)), _p(Colors.white, 0.14));
  }

  static void _notes3d(Canvas c, Color color) {
    c.drawOval(const Rect.fromLTWH(0.22, 0.78, 0.56, 0.10), _p(const Color(0xFF000000), 0.10));
    c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(0.26, 0.22, 0.54, 0.58), const Radius.circular(0.08)), _p(color, 0.55));
    final top = RRect.fromRectAndRadius(const Rect.fromLTWH(0.20, 0.16, 0.54, 0.58), const Radius.circular(0.08));
    c.drawRRect(top.shift(const Offset(0.02, 0.02)), _p(const Color(0xFF000000), 0.12));
    c.drawRRect(top, _p(color, 0.98));
    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.38)
      ..strokeWidth = 0.035
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 3; i++) {
      final y = 0.36 + i * 0.11;
      c.drawLine(Offset(0.32, y), Offset(0.64, y), line);
    }
    c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(0.24, 0.20, 0.14, 0.42), const Radius.circular(0.05)), _p(Colors.white, 0.16));
  }

  static void _power3d(Canvas c, Color color) {
    c.drawOval(const Rect.fromLTWH(0.24, 0.76, 0.52, 0.12), _p(const Color(0xFF000000), 0.10));
    c.drawCircle(const Offset(0.51, 0.51), 0.28, _p(const Color(0xFF000000), 0.14));
    c.drawCircle(const Offset(0.50, 0.48), 0.28, _p(color, 0.96));
    c.drawCircle(const Offset(0.50, 0.48), 0.20, _p(Colors.white, 0.14));
    final stroke = Paint()
      ..color = Colors.white.withValues(alpha: 0.92)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.085
      ..strokeCap = StrokeCap.round;
    c.drawArc(const Rect.fromLTWH(0.30, 0.28, 0.40, 0.40), -math.pi * 0.75, math.pi * 1.5, false, stroke);
    c.drawLine(const Offset(0.50, 0.22), const Offset(0.50, 0.46), stroke);
    c.drawCircle(const Offset(0.40, 0.36), 0.05, _p(Colors.white, 0.28));
  }

  static void _oracle3d(Canvas c, Color color) {
    c.drawOval(const Rect.fromLTWH(0.28, 0.78, 0.44, 0.10), _p(const Color(0xFF000000), 0.10));
    final tube = RRect.fromRectAndRadius(const Rect.fromLTWH(0.32, 0.20, 0.36, 0.58), const Radius.circular(0.14));
    c.drawRRect(tube.shift(const Offset(0.015, 0.02)), _p(const Color(0xFF000000), 0.16));
    c.drawRRect(tube, _p(color, 0.96));
    c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(0.36, 0.24, 0.12, 0.50), const Radius.circular(0.08)), _p(Colors.white, 0.16));
    final stick = Paint()
      ..color = Colors.white.withValues(alpha: 0.55)
      ..strokeWidth = 0.04
      ..strokeCap = StrokeCap.round;
    c.drawLine(const Offset(0.40, 0.28), const Offset(0.38, 0.68), stick);
    c.drawLine(const Offset(0.50, 0.26), const Offset(0.50, 0.70), stick);
    c.drawLine(const Offset(0.60, 0.28), const Offset(0.62, 0.68), stick);
    c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(0.34, 0.18, 0.32, 0.08), const Radius.circular(0.04)), _p(Colors.white, 0.30));
  }

  static void _music3d(Canvas c, Color color) {
    c.drawOval(const Rect.fromLTWH(0.22, 0.78, 0.56, 0.10), _p(const Color(0xFF000000), 0.10));
    c.drawCircle(const Offset(0.38, 0.70), 0.13, _p(const Color(0xFF000000), 0.14));
    c.drawCircle(const Offset(0.70, 0.62), 0.13, _p(const Color(0xFF000000), 0.14));
    c.drawCircle(const Offset(0.36, 0.68), 0.13, _p(color, 0.96));
    c.drawCircle(const Offset(0.68, 0.60), 0.13, _p(color, 0.96));
    c.drawCircle(const Offset(0.36, 0.68), 0.06, _p(Colors.white, 0.28));
    c.drawCircle(const Offset(0.68, 0.60), 0.06, _p(Colors.white, 0.28));
    final bar = Path()
      ..moveTo(0.46, 0.68)
      ..lineTo(0.46, 0.26)
      ..lineTo(0.78, 0.20)
      ..lineTo(0.78, 0.58)
      ..lineTo(0.70, 0.58)
      ..lineTo(0.70, 0.30)
      ..lineTo(0.54, 0.34)
      ..lineTo(0.54, 0.68)
      ..close();
    c.drawPath(bar.shift(const Offset(0.01, 0.015)), _p(const Color(0xFF000000), 0.14));
    c.drawPath(bar, _p(color, 0.96));
    c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(0.48, 0.28, 0.08, 0.30), const Radius.circular(0.03)), _p(Colors.white, 0.18));
  }

  static void _book3d(Canvas c, Color color) {
    c.drawOval(const Rect.fromLTWH(0.22, 0.78, 0.56, 0.10), _p(const Color(0xFF000000), 0.10));
    final pages = RRect.fromRectAndRadius(const Rect.fromLTWH(0.26, 0.20, 0.54, 0.58), const Radius.circular(0.07));
    c.drawRRect(pages.shift(const Offset(0.03, 0.02)), _p(const Color(0xFF000000), 0.14));
    c.drawRRect(pages, _p(Colors.white, 0.50));
    final cover = RRect.fromRectAndRadius(const Rect.fromLTWH(0.20, 0.18, 0.54, 0.58), const Radius.circular(0.08));
    c.drawRRect(cover.shift(const Offset(0.015, 0.02)), _p(const Color(0xFF000000), 0.16));
    c.drawRRect(cover, _p(color, 0.98));
    c.drawLine(const Offset(0.47, 0.20), const Offset(0.47, 0.74), Paint()..color = Colors.white.withValues(alpha: 0.28)..strokeWidth = 0.035);
    _star(c, const Offset(0.48, 0.46), 0.11, _p(Colors.white, 0.90));
    c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(0.24, 0.22, 0.14, 0.42), const Radius.circular(0.05)), _p(Colors.white, 0.14));
  }

  static void _mail3d(Canvas c, Color color) {
    c.drawOval(const Rect.fromLTWH(0.20, 0.76, 0.58, 0.12), _p(const Color(0xFF000000), 0.10));
    final body = RRect.fromRectAndRadius(const Rect.fromLTWH(0.16, 0.30, 0.68, 0.44), const Radius.circular(0.10));
    c.drawRRect(body.shift(const Offset(0.02, 0.03)), _p(const Color(0xFF000000), 0.16));
    c.drawRRect(body, _p(color, 0.96));
    final flap = Path()
      ..moveTo(0.16, 0.34)
      ..lineTo(0.50, 0.56)
      ..lineTo(0.84, 0.34)
      ..lineTo(0.84, 0.30)
      ..lineTo(0.16, 0.30)
      ..close();
    c.drawPath(flap, _p(Colors.white, 0.22));
    c.drawLine(const Offset(0.20, 0.36), const Offset(0.50, 0.54), Paint()..color = Colors.white.withValues(alpha: 0.45)..strokeWidth = 0.035..strokeCap = StrokeCap.round);
    c.drawLine(const Offset(0.80, 0.36), const Offset(0.50, 0.54), Paint()..color = Colors.white.withValues(alpha: 0.45)..strokeWidth = 0.035..strokeCap = StrokeCap.round);
    c.drawCircle(const Offset(0.50, 0.48), 0.05, _p(Colors.white, 0.55));
  }

  static void _calendar3d(Canvas c, Color color) {
    c.drawOval(const Rect.fromLTWH(0.22, 0.78, 0.56, 0.10), _p(const Color(0xFF000000), 0.10));
    for (final x in [0.36, 0.64]) {
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x - 0.025, 0.14, 0.05, 0.14), const Radius.circular(0.02)), _p(Colors.white, 0.55));
    }
    final body = RRect.fromRectAndRadius(const Rect.fromLTWH(0.18, 0.24, 0.64, 0.56), const Radius.circular(0.11));
    c.drawRRect(body.shift(const Offset(0.02, 0.03)), _p(const Color(0xFF000000), 0.16));
    c.drawRRect(body, _p(color, 0.96));
    c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(0.18, 0.24, 0.64, 0.16), const Radius.circular(0.11)), _p(Colors.white, 0.22));
    for (var row = 0; row < 2; row++) {
      for (var col = 0; col < 4; col++) {
        c.drawCircle(Offset(0.30 + col * 0.13, 0.52 + row * 0.12), 0.028, _p(Colors.white, 0.25 + ((row + col) % 2) * 0.08));
      }
    }
  }

  static void _bulb3d(Canvas c, Color color) {
    c.drawOval(const Rect.fromLTWH(0.28, 0.78, 0.44, 0.10), _p(const Color(0xFF000000), 0.10));
    c.drawCircle(const Offset(0.51, 0.44), 0.22, _p(const Color(0xFF000000), 0.14));
    c.drawCircle(const Offset(0.50, 0.42), 0.22, _p(color, 0.96));
    c.drawCircle(const Offset(0.50, 0.42), 0.12, _p(Colors.white, 0.22));
    c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(0.40, 0.60, 0.20, 0.16), const Radius.circular(0.04)), _p(color, 0.98));
    c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(0.42, 0.62, 0.16, 0.05), const Radius.circular(0.02)), _p(Colors.white, 0.28));
    final ray = Paint()
      ..color = Colors.white.withValues(alpha: 0.75)
      ..strokeWidth = 0.04
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 5; i++) {
      final a = -math.pi / 2 + (i - 2) * 0.35;
      c.drawLine(Offset(0.50 + math.cos(a) * 0.28, 0.42 + math.sin(a) * 0.28), Offset(0.50 + math.cos(a) * 0.36, 0.42 + math.sin(a) * 0.36), ray);
    }
  }

  static void _coins3d(Canvas c, Color color) {
    c.drawOval(const Rect.fromLTWH(0.24, 0.76, 0.52, 0.12), _p(const Color(0xFF000000), 0.10));
    c.drawCircle(const Offset(0.44, 0.60), 0.19, _p(const Color(0xFF000000), 0.14));
    c.drawCircle(const Offset(0.42, 0.58), 0.19, _p(color, 0.90));
    c.drawCircle(const Offset(0.60, 0.44), 0.19, _p(const Color(0xFF000000), 0.14));
    c.drawCircle(const Offset(0.58, 0.42), 0.19, _p(color, 0.98));
    c.drawCircle(const Offset(0.58, 0.42), 0.10, _p(Colors.white, 0.28));
    c.drawCircle(const Offset(0.52, 0.36), 0.04, _p(Colors.white, 0.35));
  }

  static void _flask3d(Canvas c, Color color) {
    c.drawOval(const Rect.fromLTWH(0.28, 0.78, 0.44, 0.10), _p(const Color(0xFF000000), 0.10));
    final pth = Path()
      ..moveTo(0.40, 0.16)
      ..lineTo(0.60, 0.16)
      ..lineTo(0.60, 0.36)
      ..lineTo(0.76, 0.72)
      ..quadraticBezierTo(0.78, 0.84, 0.66, 0.84)
      ..lineTo(0.34, 0.84)
      ..quadraticBezierTo(0.22, 0.84, 0.24, 0.72)
      ..lineTo(0.40, 0.36)
      ..close();
    c.drawPath(pth.shift(const Offset(0.015, 0.02)), _p(const Color(0xFF000000), 0.16));
    c.drawPath(pth, _p(color, 0.96));
    c.drawCircle(const Offset(0.50, 0.68), 0.10, _p(Colors.white, 0.28));
    c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(0.44, 0.18, 0.06, 0.22), const Radius.circular(0.02)), _p(Colors.white, 0.20));
  }

  static void _cup3d(Canvas c, Color color) {
    c.drawOval(const Rect.fromLTWH(0.26, 0.80, 0.48, 0.10), _p(const Color(0xFF000000), 0.10));
    final cup = Path()
      ..moveTo(0.28, 0.30)
      ..lineTo(0.34, 0.78)
      ..quadraticBezierTo(0.36, 0.88, 0.50, 0.88)
      ..quadraticBezierTo(0.64, 0.88, 0.66, 0.78)
      ..lineTo(0.72, 0.30)
      ..close();
    c.drawPath(cup.shift(const Offset(0.015, 0.02)), _p(const Color(0xFF000000), 0.16));
    c.drawPath(cup, _p(color, 0.96));
    c.drawArc(const Rect.fromLTWH(0.68, 0.38, 0.16, 0.24), -math.pi / 2, math.pi, false, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 0.06..strokeCap = StrokeCap.round);
    c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(0.34, 0.36, 0.10, 0.34), const Radius.circular(0.04)), _p(Colors.white, 0.16));
    final st = Paint()
      ..color = Colors.white.withValues(alpha: 0.55)
      ..strokeWidth = 0.03
      ..strokeCap = StrokeCap.round;
    c.drawLine(const Offset(0.42, 0.22), const Offset(0.40, 0.48), st);
    c.drawLine(const Offset(0.50, 0.18), const Offset(0.50, 0.50), st);
    c.drawLine(const Offset(0.58, 0.22), const Offset(0.60, 0.48), st);
  }

  static void _openBook3d(Canvas c, Color color) {
    c.drawOval(const Rect.fromLTWH(0.20, 0.76, 0.60, 0.12), _p(const Color(0xFF000000), 0.10));
    final left = Path()
      ..moveTo(0.50, 0.26)
      ..lineTo(0.16, 0.34)
      ..lineTo(0.16, 0.74)
      ..lineTo(0.50, 0.66)
      ..close();
    final right = Path()
      ..moveTo(0.50, 0.26)
      ..lineTo(0.84, 0.34)
      ..lineTo(0.84, 0.74)
      ..lineTo(0.50, 0.66)
      ..close();
    c.drawPath(left.shift(const Offset(0.01, 0.02)), _p(const Color(0xFF000000), 0.14));
    c.drawPath(right.shift(const Offset(0.01, 0.02)), _p(const Color(0xFF000000), 0.14));
    c.drawPath(left, _p(color, 0.96));
    c.drawPath(right, _p(color, 0.85));
    c.drawLine(const Offset(0.50, 0.28), const Offset(0.50, 0.68), Paint()..color = Colors.white.withValues(alpha: 0.35)..strokeWidth = 0.03);
  }

  static void _guide3d(Canvas c, Color color) {
    _book3d(c, color);
    c.drawCircle(const Offset(0.62, 0.32), 0.06, _p(Colors.white, 0.55));
    _star(c, const Offset(0.62, 0.32), 0.045, _p(Colors.white, 0.95));
  }

  static void _store3d(Canvas c, Color color) {
    c.drawOval(const Rect.fromLTWH(0.24, 0.76, 0.52, 0.12), _p(const Color(0xFF000000), 0.10));
    c.drawCircle(const Offset(0.51, 0.51), 0.30, _p(const Color(0xFF000000), 0.14));
    c.drawCircle(const Offset(0.50, 0.48), 0.30, _p(color, 0.96));
    c.drawCircle(const Offset(0.50, 0.48), 0.20, _p(Colors.white, 0.14));
    final d = _p(Colors.white, 0.9);
    c.drawCircle(const Offset(0.36, 0.48), 0.045, d);
    c.drawCircle(const Offset(0.50, 0.48), 0.045, d);
    c.drawCircle(const Offset(0.64, 0.48), 0.045, d);
    c.drawCircle(const Offset(0.40, 0.36), 0.05, _p(Colors.white, 0.25));
  }

  static void _forum3d(Canvas c, Color color) {
    c.drawOval(const Rect.fromLTWH(0.22, 0.76, 0.56, 0.12), _p(const Color(0xFF000000), 0.10));
    void bubble(Offset o, double r, double a) {
      c.drawCircle(o.translate(0.012, 0.015), r, _p(const Color(0xFF000000), 0.14));
      c.drawCircle(o, r, _p(color, a));
      c.drawCircle(o.translate(-r * 0.25, -r * 0.25), r * 0.35, _p(Colors.white, 0.22));
    }
    bubble(const Offset(0.36, 0.42), 0.15, 0.96);
    bubble(const Offset(0.64, 0.42), 0.15, 0.90);
    bubble(const Offset(0.50, 0.62), 0.15, 0.96);
  }

  static void _contacts(Canvas c, Paint fill) {
    // card
    c.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0.20, 0.22, 0.60, 0.58),
        const Radius.circular(0.12),
      ),
      fill,
    );
    final ink = Paint()..color = Colors.white.withValues(alpha: 0.35);
    c.drawCircle(const Offset(0.50, 0.42), 0.10, ink);
    c.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0.34, 0.56, 0.32, 0.12),
        const Radius.circular(0.06),
      ),
      ink,
    );
  }

  static void _settings(Canvas c, Paint fill) {
    const cx = 0.5, cy = 0.5, outer = 0.28, inner = 0.12;
    final path = Path();
    const teeth = 8;
    for (var i = 0; i < teeth; i++) {
      final a0 = i * math.pi * 2 / teeth - math.pi / teeth;
      final a1 = a0 + math.pi / teeth * 0.55;
      final a2 = a0 + math.pi / teeth;
      final a3 = a0 + math.pi / teeth * 1.45;
      void pt(double a, double r) {
        final x = cx + math.cos(a) * r;
        final y = cy + math.sin(a) * r;
        if (i == 0 && r == outer) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      pt(a0, outer * 0.72);
      pt(a1, outer);
      pt(a2, outer);
      pt(a3, outer * 0.72);
    }
    path.close();
    c.drawPath(path, fill);
    c.drawCircle(
      Offset(cx, cy),
      inner,
      Paint()..color = Colors.white.withValues(alpha: 0.35),
    );
  }

  static void _moments(Canvas c, Paint fill, Paint stroke) {
    c.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0.18, 0.28, 0.64, 0.48),
        const Radius.circular(0.1),
      ),
      fill,
    );
    c.drawCircle(const Offset(0.50, 0.52), 0.14, Paint()..color = Colors.white.withValues(alpha: 0.35));
    c.drawCircle(const Offset(0.50, 0.52), 0.08, Paint()..color = Colors.white.withValues(alpha: 0.55));
    c.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0.62, 0.34, 0.12, 0.08),
        const Radius.circular(0.03),
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.55),
    );
  }

  static void _notes(Canvas c, Paint fill) {
    c.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0.22, 0.18, 0.56, 0.64),
        const Radius.circular(0.08),
      ),
      fill,
    );
    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.4)
      ..strokeWidth = 0.04
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 3; i++) {
      final y = 0.38 + i * 0.12;
      c.drawLine(Offset(0.34, y), Offset(0.66, y), line);
    }
  }

  static void _power(Canvas c, Paint stroke, Paint fill) {
    c.drawArc(
      const Rect.fromLTWH(0.24, 0.24, 0.52, 0.52),
      -math.pi * 0.75,
      math.pi * 1.5,
      false,
      stroke
        ..strokeWidth = 0.09
        ..color = fill.color,
    );
    c.drawLine(
      const Offset(0.50, 0.18),
      const Offset(0.50, 0.48),
      stroke
        ..strokeWidth = 0.09
        ..color = fill.color,
    );
  }

  static void _oracle(Canvas c, Paint fill, Paint stroke) {
    // tube
    c.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0.34, 0.22, 0.32, 0.56),
        const Radius.circular(0.12),
      ),
      fill,
    );
    // sticks
    final stick = Paint()
      ..color = Colors.white.withValues(alpha: 0.55)
      ..strokeWidth = 0.035
      ..strokeCap = StrokeCap.round;
    c.drawLine(const Offset(0.42, 0.30), const Offset(0.40, 0.68), stick);
    c.drawLine(const Offset(0.50, 0.28), const Offset(0.50, 0.70), stick);
    c.drawLine(const Offset(0.58, 0.30), const Offset(0.60, 0.68), stick);
  }

  static void _music(Canvas c, Paint fill) {
    c.drawCircle(const Offset(0.36, 0.68), 0.12, fill);
    c.drawCircle(const Offset(0.68, 0.60), 0.12, fill);
    final bar = Path()
      ..moveTo(0.46, 0.68)
      ..lineTo(0.46, 0.28)
      ..lineTo(0.78, 0.22)
      ..lineTo(0.78, 0.60)
      ..lineTo(0.70, 0.60)
      ..lineTo(0.70, 0.32)
      ..lineTo(0.54, 0.36)
      ..lineTo(0.54, 0.68)
      ..close();
    c.drawPath(bar, fill);
  }

  static void _book(Canvas c, Paint fill, Paint stroke) {
    c.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0.22, 0.22, 0.56, 0.58),
        const Radius.circular(0.08),
      ),
      fill,
    );
    c.drawLine(
      const Offset(0.50, 0.22),
      const Offset(0.50, 0.80),
      stroke
        ..strokeWidth = 0.04
        ..color = Colors.white.withValues(alpha: 0.35),
    );
    // star
    _star(c, const Offset(0.50, 0.48), 0.10, Paint()..color = Colors.white.withValues(alpha: 0.9));
  }

  static void _mail(Canvas c, Paint fill, Paint stroke) {
    c.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0.18, 0.30, 0.64, 0.42),
        const Radius.circular(0.08),
      ),
      fill,
    );
    final flap = Path()
      ..moveTo(0.18, 0.34)
      ..lineTo(0.50, 0.54)
      ..lineTo(0.82, 0.34);
    c.drawPath(
      flap,
      stroke
        ..strokeWidth = 0.05
        ..color = Colors.white.withValues(alpha: 0.55),
    );
  }

  static void _calendar(Canvas c, Paint fill, Paint stroke) {
    c.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0.22, 0.26, 0.56, 0.52),
        const Radius.circular(0.1),
      ),
      fill,
    );
    c.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0.22, 0.26, 0.56, 0.14),
        const Radius.circular(0.1),
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.3),
    );
    // rings
    c.drawLine(const Offset(0.36, 0.20), const Offset(0.36, 0.34), stroke..strokeWidth = 0.05..color = fill.color);
    c.drawLine(const Offset(0.64, 0.20), const Offset(0.64, 0.34), stroke..strokeWidth = 0.05..color = fill.color);
  }

  static void _bulb(Canvas c, Paint fill, Paint stroke) {
    c.drawCircle(const Offset(0.50, 0.42), 0.20, fill);
    c.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0.40, 0.58, 0.20, 0.16),
        const Radius.circular(0.04),
      ),
      fill,
    );
    // rays
    final ray = stroke
      ..strokeWidth = 0.04
      ..color = fill.color;
    for (var i = 0; i < 5; i++) {
      final a = -math.pi / 2 + (i - 2) * 0.35;
      c.drawLine(
        Offset(0.50 + math.cos(a) * 0.26, 0.42 + math.sin(a) * 0.26),
        Offset(0.50 + math.cos(a) * 0.34, 0.42 + math.sin(a) * 0.34),
        ray,
      );
    }
  }

  static void _coins(Canvas c, Paint fill, Paint stroke) {
    c.drawCircle(const Offset(0.42, 0.58), 0.18, fill);
    c.drawCircle(const Offset(0.58, 0.42), 0.18, fill);
    c.drawCircle(
      const Offset(0.58, 0.42),
      0.10,
      Paint()..color = Colors.white.withValues(alpha: 0.3),
    );
  }

  static void _flask(Canvas c, Paint fill, Paint stroke) {
    final p = Path()
      ..moveTo(0.40, 0.18)
      ..lineTo(0.60, 0.18)
      ..lineTo(0.60, 0.38)
      ..lineTo(0.74, 0.72)
      ..quadraticBezierTo(0.76, 0.82, 0.66, 0.82)
      ..lineTo(0.34, 0.82)
      ..quadraticBezierTo(0.24, 0.82, 0.26, 0.72)
      ..lineTo(0.40, 0.38)
      ..close();
    c.drawPath(p, fill);
    // heart liquid
    c.drawCircle(const Offset(0.50, 0.66), 0.08, Paint()..color = Colors.white.withValues(alpha: 0.45));
  }

  static void _cup(Canvas c, Paint fill, Paint stroke) {
    final cup = Path()
      ..moveTo(0.28, 0.32)
      ..lineTo(0.34, 0.78)
      ..quadraticBezierTo(0.36, 0.86, 0.50, 0.86)
      ..quadraticBezierTo(0.64, 0.86, 0.66, 0.78)
      ..lineTo(0.72, 0.32)
      ..close();
    c.drawPath(cup, fill);
    // handle
    c.drawArc(
      const Rect.fromLTWH(0.68, 0.40, 0.16, 0.22),
      -math.pi / 2,
      math.pi,
      false,
      stroke
        ..strokeWidth = 0.06
        ..color = fill.color,
    );
  }

  static void _openBook(Canvas c, Paint fill, Paint stroke) {
    final left = Path()
      ..moveTo(0.50, 0.28)
      ..lineTo(0.18, 0.34)
      ..lineTo(0.18, 0.74)
      ..lineTo(0.50, 0.68)
      ..close();
    final right = Path()
      ..moveTo(0.50, 0.28)
      ..lineTo(0.82, 0.34)
      ..lineTo(0.82, 0.74)
      ..lineTo(0.50, 0.68)
      ..close();
    c.drawPath(left, fill);
    c.drawPath(right, Paint()..color = fill.color.withValues(alpha: 0.85));
  }

  static void _guide(Canvas c, Paint fill, Paint stroke) {
    c.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0.24, 0.20, 0.52, 0.62),
        const Radius.circular(0.08),
      ),
      fill,
    );
    _spark(c, Paint()..color = Colors.white.withValues(alpha: 0.9));
  }

  static void _store(Canvas c, Paint fill) {
    c.drawCircle(const Offset(0.50, 0.50), 0.28, fill);
    final dot = Paint()..color = Colors.white.withValues(alpha: 0.9);
    c.drawCircle(const Offset(0.36, 0.50), 0.045, dot);
    c.drawCircle(const Offset(0.50, 0.50), 0.045, dot);
    c.drawCircle(const Offset(0.64, 0.50), 0.045, dot);
  }

  static void _forum(Canvas c, Paint fill) {
    c.drawCircle(const Offset(0.36, 0.42), 0.14, fill);
    c.drawCircle(const Offset(0.62, 0.42), 0.14, fill);
    c.drawCircle(const Offset(0.50, 0.62), 0.14, fill);
  }

  static void _map(Canvas c, Paint fill, Paint stroke) {
    final p = Path()
      ..moveTo(0.22, 0.30)
      ..lineTo(0.42, 0.24)
      ..lineTo(0.62, 0.32)
      ..lineTo(0.82, 0.26)
      ..lineTo(0.78, 0.74)
      ..lineTo(0.58, 0.80)
      ..lineTo(0.38, 0.72)
      ..lineTo(0.18, 0.78)
      ..close();
    c.drawPath(p, fill);
    c.drawCircle(const Offset(0.50, 0.48), 0.06, Paint()..color = Colors.white.withValues(alpha: 0.55));
  }

  static void _face(Canvas c, Paint fill, Paint stroke) {
    c.drawCircle(const Offset(0.50, 0.48), 0.26, fill);
    final eye = Paint()..color = Colors.white.withValues(alpha: 0.55);
    c.drawCircle(const Offset(0.40, 0.44), 0.04, eye);
    c.drawCircle(const Offset(0.60, 0.44), 0.04, eye);
    c.drawArc(
      const Rect.fromLTWH(0.38, 0.48, 0.24, 0.16),
      0.15,
      math.pi - 0.3,
      false,
      stroke
        ..strokeWidth = 0.04
        ..color = Colors.white.withValues(alpha: 0.55),
    );
  }

  static void _spark(Canvas c, Paint fill) {
    _star(c, const Offset(0.50, 0.50), 0.16, fill);
  }

  static void _star(Canvas c, Offset center, double r, Paint paint) {
    final path = Path();
    for (var i = 0; i < 5; i++) {
      final a = -math.pi / 2 + i * math.pi * 2 / 5;
      final a2 = a + math.pi / 5;
      final p1 = Offset(center.dx + math.cos(a) * r, center.dy + math.sin(a) * r);
      final p2 = Offset(center.dx + math.cos(a2) * r * 0.42, center.dy + math.sin(a2) * r * 0.42);
      if (i == 0) {
        path.moveTo(p1.dx, p1.dy);
      } else {
        path.lineTo(p1.dx, p1.dy);
      }
      path.lineTo(p2.dx, p2.dy);
    }
    path.close();
    c.drawPath(path, paint);
  }
}

/// 可直接当 Icon 用的自定义绘制
class PhoneGlyph extends StatelessWidget {
  final String id;
  final double size;
  final Color color;

  const PhoneGlyph({
    super.key,
    required this.id,
    this.size = 28,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _GlyphPainter(id: id, color: color),
    );
  }
}

class _GlyphPainter extends CustomPainter {
  final String id;
  final Color color;
  const _GlyphPainter({required this.id, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    PhoneIconGlyphs.paint(canvas, size, id, color: color);
  }

  @override
  bool shouldRepaint(covariant _GlyphPainter oldDelegate) =>
      oldDelegate.id != id || oldDelegate.color != color;
}
