import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../config/phone_theme.dart';

/// 毛玻璃面板：卡片 / Dock / 顶栏通用。
///
/// 低端机上 BackdropFilter 很贵；blur<=0 时退化为半透明面板（观感接近、成本低很多）。
class PhoneGlassPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double radius;
  final double blur;
  final double fillOpacity;
  final double borderOpacity;
  final List<BoxShadow>? boxShadow;
  final VoidCallback? onTap;

  const PhoneGlassPanel({
    super.key,
    required this.child,
    this.padding,
    this.radius = PhoneTheme.cardRadius,
    this.blur = PhoneTheme.glassBlur,
    this.fillOpacity = 0.30,
    this.borderOpacity = 0.50,
    this.boxShadow,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final reduce =
        MediaQuery.disableAnimationsOf(context) || PhoneTheme.preferLiteGlass;
    final effectiveBlur = reduce ? 0.0 : blur;
    final effectiveFill =
        reduce ? (fillOpacity + 0.12).clamp(0.0, 0.55) : fillOpacity;

    Widget content = Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: (effectiveFill + 0.14).clamp(0, 1)),
            Colors.white.withValues(alpha: effectiveFill),
            Colors.white.withValues(alpha: (effectiveFill - 0.05).clamp(0, 1)),
          ],
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: borderOpacity),
          width: 1.15,
        ),
        boxShadow: boxShadow ?? PhoneTheme.glassCardShadow,
      ),
      child: Stack(
        children: [
          Positioned(
            left: 12,
            right: 12,
            top: 0,
            child: IgnorePointer(
              child: Container(
                height: 1.2,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  gradient: LinearGradient(
                    colors: [
                      Colors.white.withValues(alpha: 0.0),
                      Colors.white.withValues(alpha: 0.55),
                      Colors.white.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );

    final panel = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: effectiveBlur > 0.5
          ? BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: effectiveBlur,
                sigmaY: effectiveBlur,
              ),
              child: content,
            )
          : content,
    );

    if (onTap == null) return panel;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: panel,
      ),
    );
  }
}

/// 天空壁纸 + 体积光 + 微粒子（支持主题包）。
///
/// [animate]=false 时只画静态渐变+少量光斑，适合无障碍「减少动态效果」。
class PhoneWallpaper extends StatelessWidget {
  final Widget? child;
  final Offset parallax;
  final double breath;
  final PhoneWallpaperTheme theme;
  final bool animate;

  const PhoneWallpaper({
    super.key,
    this.child,
    this.parallax = Offset.zero,
    this.breath = 1.0,
    this.theme = PhoneWallpaperTheme.dawn,
    this.animate = true,
  });

  @override
  Widget build(BuildContext context) {
    final palette = PhoneWallpaperPalette.of(theme);
    return Stack(
      fit: StackFit.expand,
      children: [
        // 深层渐变：5 段式模拟大气透视
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: palette.gradient,
              stops: const [0.0, 0.28, 0.52, 0.76, 1.0],
            ),
          ),
        ),
        // 体积光主层：大团柔光，随视差缓慢漂移
        Transform.translate(
          offset: parallax,
          child: CustomPaint(
            painter: _AuroraLightPainter(
              intensity: breath,
              colorA: palette.bokehA,
              colorB: palette.bokehB,
              fog: palette.fog,
              theme: theme,
              lite: !animate,
            ),
          ),
        ),
        // 次级光斑：反向微漂移，制造层次
        if (animate)
          Transform.translate(
            offset: Offset(-parallax.dx * 0.4, -parallax.dy * 0.3),
            child: CustomPaint(
              painter: _AuroraLightPainter(
                intensity: breath * 0.6,
                colorA: palette.bokehB,
                colorB: palette.bokehA,
                fog: palette.fog,
                theme: theme,
                alt: true,
              ),
            ),
          ),
        // 微粒子层：悬浮尘埃/星点
        if (animate)
          CustomPaint(
            painter: _ParticleFieldPainter(
              intensity: breath,
              theme: theme,
            ),
          ),
        // 夜空专属：星轨
        if (theme == PhoneWallpaperTheme.night && animate)
          CustomPaint(
            painter: _StarTrailPainter(intensity: breath),
          ),
        // 底部雾化过渡
        Align(
          alignment: Alignment.bottomCenter,
          child: IgnorePointer(
            child: Container(
              height: 200,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    palette.fog.withValues(alpha: 0.15),
                    palette.fog.withValues(alpha: 0.45),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (child != null) child!,
      ],
    );
  }
}

/// 极光体积光画家：用多层径向渐变模拟大气中的光散射
class _AuroraLightPainter extends CustomPainter {
  final double intensity;
  final bool alt;
  final bool lite;
  final Color colorA;
  final Color colorB;
  final Color fog;
  final PhoneWallpaperTheme theme;

  const _AuroraLightPainter({
    this.intensity = 1,
    this.alt = false,
    this.lite = false,
    required this.colorA,
    required this.colorB,
    required this.fog,
    required this.theme,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    void glow(Offset c, double r, Color color, double alpha) {
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: alpha * intensity),
            color.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: c, radius: r));
      canvas.drawCircle(c, r, paint);
    }

    if (!alt) {
      // 主光源：顶部偏左，模拟太阳/月亮位置
      glow(Offset(w * 0.2, h * 0.12), w * 0.7, colorA, 0.35);
      glow(Offset(w * 0.75, h * 0.3), w * 0.5, colorB, 0.22);
      if (!lite) {
        // 中层：大气散射
        glow(Offset(w * 0.5, h * 0.5), w * 0.65, fog, 0.12);
        glow(Offset(w * 0.15, h * 0.65), w * 0.4, colorA, 0.15);
        glow(Offset(w * 0.85, h * 0.75), w * 0.35, colorB, 0.10);
      }
    } else {
      // 次级：反向补光
      glow(Offset(w * 0.8, h * 0.6), w * 0.35, colorB, 0.18);
      glow(Offset(w * 0.3, h * 0.35), w * 0.25, colorA, 0.12);
    }
  }

  @override
  bool shouldRepaint(covariant _AuroraLightPainter old) =>
      (old.intensity - intensity).abs() > 0.015 ||
      old.alt != alt ||
      old.lite != lite ||
      old.colorA != colorA ||
      old.colorB != colorB;
}

/// 微粒子层：悬浮尘埃，增加空气感
class _ParticleFieldPainter extends CustomPainter {
  final double intensity;
  final PhoneWallpaperTheme theme;

  const _ParticleFieldPainter({
    this.intensity = 1,
    required this.theme,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final random = math.Random(42); // 固定种子，粒子位置稳定
    final count = theme == PhoneWallpaperTheme.night ? 35 : 20;

    for (var i = 0; i < count; i++) {
      final x = random.nextDouble() * size.width;
      final y = random.nextDouble() * size.height;
      final r = 0.5 + random.nextDouble() * 1.5;
      final alpha = (0.08 + random.nextDouble() * 0.15) * intensity;

      final paint = Paint()
        ..color = Colors.white.withValues(alpha: alpha)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5);
      canvas.drawCircle(Offset(x, y), r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ParticleFieldPainter old) =>
      (old.intensity - intensity).abs() > 0.02;
}

/// 星轨画家：夜空主题的流星/星轨效果
class _StarTrailPainter extends CustomPainter {
  final double intensity;
  const _StarTrailPainter({this.intensity = 1});

  @override
  void paint(Canvas canvas, Size size) {
    final random = math.Random(7);
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.35 * intensity)
      ..strokeWidth = 0.8
      ..strokeCap = StrokeCap.round;

    // 固定位置的星星
    for (var i = 0; i < 18; i++) {
      final x = random.nextDouble() * size.width;
      final y = random.nextDouble() * size.height * 0.6;
      final r = 0.6 + random.nextDouble() * 1.2;
      canvas.drawCircle(
        Offset(x, y),
        r,
        Paint()..color = Colors.white.withValues(alpha: 0.4 * intensity),
      );
    }

    // 两条流星轨迹
    final trail1 = Path()
      ..moveTo(size.width * 0.1, size.height * 0.15)
      ..quadraticBezierTo(
        size.width * 0.35,
        size.height * 0.08,
        size.width * 0.6,
        size.height * 0.12,
      );
    canvas.drawPath(trail1, paint);

    final trail2 = Path()
      ..moveTo(size.width * 0.55, size.height * 0.25)
      ..quadraticBezierTo(
        size.width * 0.75,
        size.height * 0.18,
        size.width * 0.9,
        size.height * 0.22,
      );
    canvas.drawPath(
      trail2,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.2 * intensity)
        ..strokeWidth = 0.5
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _StarTrailPainter old) =>
      old.intensity != intensity;
}
