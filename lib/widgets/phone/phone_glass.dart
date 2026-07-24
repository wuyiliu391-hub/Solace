import 'dart:ui';

import 'package:flutter/material.dart';

import '../../config/phone_theme.dart';

/// 毛玻璃面板：卡片 / Dock / 顶栏通用。
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
    final panel = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: (fillOpacity + 0.14).clamp(0, 1)),
                Colors.white.withValues(alpha: fillOpacity),
                Colors.white.withValues(alpha: (fillOpacity - 0.05).clamp(0, 1)),
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
        ),
      ),
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

/// 天空壁纸 + 柔光斑 + 轻视差（支持主题包）。
class PhoneWallpaper extends StatelessWidget {
  final Widget? child;
  final Offset parallax;
  final double breath;
  final PhoneWallpaperTheme theme;

  const PhoneWallpaper({
    super.key,
    this.child,
    this.parallax = Offset.zero,
    this.breath = 1.0,
    this.theme = PhoneWallpaperTheme.dawn,
  });

  @override
  Widget build(BuildContext context) {
    final palette = SolacePalettes.of(theme);
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: palette.colors,
              stops: palette.gradientStops,
            ),
          ),
        ),
        Transform.translate(
          offset: parallax,
          child: CustomPaint(
            painter: _SkyBokehPainter(
              intensity: breath,
              colorA: palette.bokehA,
              colorB: palette.bokehB,
            ),
          ),
        ),
        Transform.translate(
          offset: Offset(-parallax.dx * 0.5, -parallax.dy * 0.4),
          child: CustomPaint(
            painter: _SkyBokehPainter(
              intensity: breath,
              colorA: palette.bokehB,
              colorB: palette.bokehA,
              alt: true,
            ),
          ),
        ),
        if (theme == PhoneWallpaperTheme.night)
          CustomPaint(painter: _StarFieldPainter(intensity: breath)),
        Align(
          alignment: Alignment.bottomCenter,
          child: IgnorePointer(
            child: Container(
              height: 180,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withValues(alpha: 0.0),
                    palette.fog.withValues(alpha: 0.25),
                    palette.fog,
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

class _SkyBokehPainter extends CustomPainter {
  final double intensity;
  final bool alt;
  final Color colorA;
  final Color colorB;

  const _SkyBokehPainter({
    this.intensity = 1,
    this.alt = false,
    required this.colorA,
    required this.colorB,
  });

  @override
  void paint(Canvas canvas, Size size) {
    void blob(Offset c, double r, Color color) {
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [color, color.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: c, radius: r));
      canvas.drawCircle(c, r * (0.96 + intensity * 0.06), paint);
    }

    if (!alt) {
      blob(Offset(size.width * 0.15, size.height * 0.16), size.width * 0.46,
          colorA);
      blob(Offset(size.width * 0.88, size.height * 0.26), size.width * 0.38,
          colorA.withValues(alpha: 0.45));
      blob(Offset(size.width * 0.55, size.height * 0.52), size.width * 0.55,
          colorB);
      blob(Offset(size.width * 0.18, size.height * 0.72), size.width * 0.42,
          colorA.withValues(alpha: 0.3));
    } else {
      blob(Offset(size.width * 0.72, size.height * 0.62), size.width * 0.32,
          colorB.withValues(alpha: 0.28));
      blob(Offset(size.width * 0.40, size.height * 0.22), size.width * 0.22,
          colorA.withValues(alpha: 0.25));
    }
  }

  @override
  bool shouldRepaint(covariant _SkyBokehPainter oldDelegate) =>
      oldDelegate.intensity != intensity ||
      oldDelegate.alt != alt ||
      oldDelegate.colorA != colorA ||
      oldDelegate.colorB != colorB;
}

class _StarFieldPainter extends CustomPainter {
  final double intensity;
  const _StarFieldPainter({this.intensity = 1});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.55 * intensity);
    final seeds = [
      Offset(0.12, 0.10),
      Offset(0.28, 0.18),
      Offset(0.45, 0.08),
      Offset(0.62, 0.15),
      Offset(0.78, 0.11),
      Offset(0.88, 0.22),
      Offset(0.18, 0.28),
      Offset(0.35, 0.32),
      Offset(0.55, 0.26),
      Offset(0.72, 0.30),
      Offset(0.92, 0.35),
      Offset(0.08, 0.40),
    ];
    for (var i = 0; i < seeds.length; i++) {
      final o = Offset(seeds[i].dx * size.width, seeds[i].dy * size.height);
      final r = 0.8 + (i % 3) * 0.5;
      canvas.drawCircle(o, r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _StarFieldPainter oldDelegate) =>
      oldDelegate.intensity != intensity;
}
