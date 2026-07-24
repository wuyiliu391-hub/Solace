import 'package:flutter/material.dart';

/// 小手机壁纸主题包：晨曦 / 黄昏 / 夜空
enum PhoneWallpaperTheme {
  dawn, // 琉璃青绿 → 夕雾粉
  dusk, // 石墨蓝 → 星辉紫
  night, // 深海墨 → 霓虹青
}

extension PhoneWallpaperThemeX on PhoneWallpaperTheme {
  String get id {
    switch (this) {
      case PhoneWallpaperTheme.dawn:
        return 'dawn';
      case PhoneWallpaperTheme.dusk:
        return 'dusk';
      case PhoneWallpaperTheme.night:
        return 'night';
    }
  }

  String get label {
    switch (this) {
      case PhoneWallpaperTheme.dawn:
        return '琉璃';
      case PhoneWallpaperTheme.dusk:
        return '暮紫';
      case PhoneWallpaperTheme.night:
        return '霓虹';
    }
  }

  static PhoneWallpaperTheme fromId(String? id) {
    switch (id) {
      case 'dusk':
        return PhoneWallpaperTheme.dusk;
      case 'night':
        return PhoneWallpaperTheme.night;
      case 'dawn':
      default:
        return PhoneWallpaperTheme.dawn;
    }
  }
}

/// Solace 品牌调色板（用于壁纸渐变 + 点缀色）
class SolacePalette {
  final String name;
  final List<Color> colors;
  final List<double> gradientStops;
  final Color mid;
  final Color accent;
  final Color fog;
  final Color bokehA;
  final Color bokehB;
  final Color clockTop;
  final Color clockBottom;

  const SolacePalette({
    required this.name,
    required this.colors,
    required this.gradientStops,
    required this.mid,
    required this.accent,
    required this.fog,
    required this.bokehA,
    required this.bokehB,
    required this.clockTop,
    required this.clockBottom,
  });

  LinearGradient get gradient => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: colors,
        stops: gradientStops,
      );
}

/// Solace 品牌调色板集合
class SolacePalettes {
  SolacePalettes._();
  static const dawn = SolacePalette(
    name: '琉璃',
    gradientStops: [0.0, 0.4, 1.0],
    colors: [Color(0xFF0FB8AD), Color(0xFF3AC5B2), Color(0xFFF27AA5)],
    mid: Color(0xFF2AB5A0),
    accent: Color(0xFF00E0C6),
    fog: Color(0xFFF27AA5),
    bokehA: Color(0x440FB8AD),
    bokehB: Color(0x33F27AA5),
    clockTop: Color(0xFFFFFFFF),
    clockBottom: Color(0xFFE8FFF8),
  );
  static const dusk = SolacePalette(
    name: '暮紫',
    gradientStops: [0.0, 0.5, 1.0],
    colors: [Color(0xFF2A3356), Color(0xFF5A4688), Color(0xFF6C4ED0)],
    mid: Color(0xFF4A3A78),
    accent: Color(0xFF9B8AE8),
    fog: Color(0xFF6C4ED0),
    bokehA: Color(0x446C4ED0),
    bokehB: Color(0x335A4688),
    clockTop: Color(0xFFFFF0FF),
    clockBottom: Color(0xFFE8D0FF),
  );
  static const night = SolacePalette(
    name: '霓虹',
    gradientStops: [0.0, 0.6, 1.0],
    colors: [Color(0xFF0B1026), Color(0xFF1B2748), Color(0xFF00E0C6)],
    mid: Color(0xFF0E1A30),
    accent: Color(0xFF00E0C6),
    fog: Color(0xFF0B1026),
    bokehA: Color(0x3300E0C6),
    bokehB: Color(0x2200B4D0),
    clockTop: Color(0xFFE0FFF8),
    clockBottom: Color(0xFF00E0C6),
  );

  static SolacePalette of(PhoneWallpaperTheme theme) {
    switch (theme) {
      case PhoneWallpaperTheme.dawn:
        return dawn;
      case PhoneWallpaperTheme.dusk:
        return dusk;
      case PhoneWallpaperTheme.night:
        return night;
    }
  }
}

class PhoneWallpaperPalette {
  final List<Color> gradient;
  final Color mid;
  final Color bokehA;
  final Color bokehB;
  final Color fog;
  final Color clockTop;
  final Color clockBottom;

  const PhoneWallpaperPalette({
    required this.gradient,
    required this.mid,
    required this.bokehA,
    required this.bokehB,
    required this.fog,
    required this.clockTop,
    required this.clockBottom,
  });

  static PhoneWallpaperPalette of(PhoneWallpaperTheme theme) {
    switch (theme) {
      case PhoneWallpaperTheme.dawn:
        return const PhoneWallpaperPalette(
          gradient: [
            Color(0xFF5BB8DC),
            Color(0xFF8FD0EA),
            Color(0xFFC5E8F6),
            Color(0xFFEAF6FC),
          ],
          mid: Color(0xFFA8DCF0),
          bokehA: Color(0x77FFFFFF),
          bokehB: Color(0x3AA8E0F5),
          fog: Color(0x55EAF6FC),
          clockTop: Color(0xFFFFFFFF),
          clockBottom: Color(0xD9F2FBFF),
        );
      case PhoneWallpaperTheme.dusk:
        return const PhoneWallpaperPalette(
          gradient: [
            Color(0xFF2B3A67),
            Color(0xFF6B4E8C),
            Color(0xFFE07A5F),
            Color(0xFFF2CC8F),
          ],
          mid: Color(0xFF8B5E83),
          bokehA: Color(0x55FFD6A5),
          bokehB: Color(0x44E07A5F),
          fog: Color(0x44F2CC8F),
          clockTop: Color(0xFFFFF6E8),
          clockBottom: Color(0xDDFFD6A5),
        );
      case PhoneWallpaperTheme.night:
        return const PhoneWallpaperPalette(
          gradient: [
            Color(0xFF0B1026),
            Color(0xFF1B2748),
            Color(0xFF2E3A5F),
            Color(0xFF1A2744),
          ],
          mid: Color(0xFF1B2748),
          bokehA: Color(0x44A5B4FC),
          bokehB: Color(0x3387CEEB),
          fog: Color(0x330B1026),
          clockTop: Color(0xFFF0F4FF),
          clockBottom: Color(0xDDC7D2FE),
        );
    }
  }
}

/// 虚拟手机桌面设计 Token
class PhoneTheme {
  PhoneTheme._();

  // ── Solace 品牌色方案 ──
  /// 琉璃青绿 → 夕雾粉（晨曦）
  static const solaceDawn = SolacePalette(
    name: '琉璃',
    gradientStops: [0.0, 0.4, 1.0],
    colors: [Color(0xFF0FB8AD), Color(0xFF3AC5B2), Color(0xFFF27AA5)],
    mid: Color(0xFF2AB5A0),
    accent: Color(0xFF00E0C6),
    fog: Color(0xFFF27AA5),
    bokehA: Color(0x440FB8AD),
    bokehB: Color(0x33F27AA5),
    clockTop: Color(0xFFFFFFFF),
    clockBottom: Color(0xFFE8FFF8),
  );

  /// 石墨蓝 → 星辉紫（黄昏）
  static const solaceDusk = SolacePalette(
    name: '暮紫',
    gradientStops: [0.0, 0.5, 1.0],
    colors: [Color(0xFF2A3356), Color(0xFF5A4688), Color(0xFF6C4ED0)],
    mid: Color(0xFF4A3A78),
    accent: Color(0xFF9B8AE8),
    fog: Color(0xFF6C4ED0),
    bokehA: Color(0x446C4ED0),
    bokehB: Color(0x335A4688),
    clockTop: Color(0xFFFFF0FF),
    clockBottom: Color(0xFFE8D0FF),
  );

  /// 深海墨 → 霓虹青（夜空）
  static const solaceNight = SolacePalette(
    name: '霓虹',
    gradientStops: [0.0, 0.6, 1.0],
    colors: [Color(0xFF0B1026), Color(0xFF1B2748), Color(0xFF00E0C6)],
    mid: Color(0xFF0E1A30),
    accent: Color(0xFF00E0C6),
    fog: Color(0xFF0B1026),
    bokehA: Color(0x3300E0C6),
    bokehB: Color(0x2200B4D0),
    clockTop: Color(0xFFE0FFF8),
    clockBottom: Color(0xFF00E0C6),
  );

  // ── 兼容旧引用 ──
  static const wallpaperTop = Color(0xFF6EC6E6);
  static const wallpaperMid = Color(0xFFA8DCF0);
  static const wallpaperBottom = Color(0xFFEAF6FC);
  static const List<Color> wallpaperGradient = [
    Color(0xFF5BB8DC),
    Color(0xFF8FD0EA),
    Color(0xFFC5E8F6),
    Color(0xFFEAF6FC),
  ];

  static Color glassFill([double o = 0.32]) => Colors.white.withValues(alpha: o);
  static Color glassBorder([double o = 0.55]) =>
      Colors.white.withValues(alpha: o);
  static Color glassHighlight([double o = 0.55]) =>
      Colors.white.withValues(alpha: o);
  static Color glassShadow([double o = 0.10]) =>
      Colors.black.withValues(alpha: o);

  static const double glassBlur = 22;
  static const double cardRadius = 22;
  static const double iconRadiusRatio = 0.28;
  static const double dockRadius = 28;

  static const double homeIconSize = 68;
  static const double dockIconSize = 60;
  static const double iconLabelSize = 11.5;
  static const double gridSpacing = 16;
  static const int gridCrossAxisCount = 4;
  static const int pageCapacity = 12; // 每页 3 行 × 4 列

  static const Color textOnWallpaper = Colors.white;
  static Color textOnWallpaperMuted([double o = 0.85]) =>
      Colors.white.withValues(alpha: o);

  static List<Shadow> get labelShadows => const [
        Shadow(color: Color(0x59000000), blurRadius: 6, offset: Offset(0, 1)),
      ];

  static List<BoxShadow> iconDropShadow(Color accent) => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.18),
          blurRadius: 14,
          offset: const Offset(0, 8),
        ),
        BoxShadow(
          color: accent.withValues(alpha: 0.28),
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
      ];

  static List<BoxShadow> glassCardShadow = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.08),
      blurRadius: 24,
      offset: const Offset(0, 10),
    ),
  ];
}
