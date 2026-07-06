// GridPreset and HomeLayoutConfig are used throughout home screens.
// No UI framework import needed — this is a pure data/utility file.

class HomeBreakpoints {
  HomeBreakpoints._();

  static const double phoneSmall = 380;
  static const double phoneStandard = 430;
  static const double phoneMax = 440;
  static const double tabletMini = 744;
  static const double tabletStandard = 834;
  static const double tabletLarge = 1032;
  static const double landscapeThreshold = 1100;
}

/// 网格密度预设
enum GridPreset {
  fourByFive('4×5', phoneColumns: 4, rows: 5),
  fiveByFive('5×5', phoneColumns: 5, rows: 5),
  fourBySix('4×6', phoneColumns: 4, rows: 6),
  fiveBySix('5×6', phoneColumns: 5, rows: 6);

  final String label;
  final int phoneColumns; // 手机默认列数
  final int rows;         // 每页行数

  const GridPreset(this.label, {required this.phoneColumns, required this.rows});

  /// 根据屏幕宽度决定实际列数（平板列数自适应放大）
  int getEffectiveColumns(double screenWidth) {
    if (screenWidth < HomeBreakpoints.phoneMax) return phoneColumns;
    if (screenWidth < HomeBreakpoints.tabletMini) return phoneColumns;
    if (screenWidth < HomeBreakpoints.tabletStandard) {
      return phoneColumns.clamp(0, 5); // 平板最多 5 列
    }
    return phoneColumns.clamp(0, 6);
  }

  /// 每页总图标数
  int get totalSlots => phoneColumns * rows;
}

class HomeLayoutConfig {
  final int columns;
  final int rows;
  final double iconSize;
  final double hSpacing;
  final double vSpacing;
  final double hMargin;
  final double labelFontSize;

  const HomeLayoutConfig({
    required this.columns,
    required this.rows,
    required this.iconSize,
    required this.hSpacing,
    required this.vSpacing,
    required this.hMargin,
    required this.labelFontSize,
  });

  /// 每页总槽位数
  int get totalSlots => columns * rows;
}

/// 根据网格预设 + 屏幕宽度生成实际布局参数
HomeLayoutConfig layoutForPreset(GridPreset preset, double screenWidth) {
  final cols = preset.getEffectiveColumns(screenWidth);
  final rows = preset.rows;

  // 根据屏幕宽度和列数调整图标尺寸
  double iconSize;
  double hSpacing, vSpacing, hMargin, labelFontSize;

  if (screenWidth < HomeBreakpoints.phoneSmall) {
    iconSize = 52.0;
    hSpacing = 20;
    vSpacing = 20;
    hMargin = 16;
    labelFontSize = 9;
  } else if (screenWidth < HomeBreakpoints.phoneMax) {
    iconSize = 60.0;
    hSpacing = 28;
    vSpacing = 24;
    hMargin = 24;
    labelFontSize = 11;
  } else if (screenWidth < HomeBreakpoints.tabletMini) {
    iconSize = 60.0;
    hSpacing = 32;
    vSpacing = 28;
    hMargin = 28;
    labelFontSize = 11;
  } else if (screenWidth < HomeBreakpoints.tabletStandard) {
    iconSize = 68.0;
    hSpacing = 36;
    vSpacing = 32;
    hMargin = 32;
    labelFontSize = 12;
  } else if (screenWidth < HomeBreakpoints.landscapeThreshold) {
    iconSize = 72.0;
    hSpacing = 36;
    vSpacing = 32;
    hMargin = 32;
    labelFontSize = 12;
  } else {
    iconSize = 68.0;
    hSpacing = 30;
    vSpacing = 32;
    hMargin = 30;
    labelFontSize = 11;
  }

  // 列数越密，图标略小
  if (cols >= 6) {
    iconSize = (iconSize * 0.85).clamp(44.0, 64.0);
    hSpacing = (hSpacing * 0.8).clamp(12.0, 32.0);
  } else if (cols >= 5) {
    iconSize = (iconSize * 0.92).clamp(48.0, 68.0);
  }

  // 行数越多，垂直间距略缩
  if (rows >= 6) {
    vSpacing = (vSpacing * 0.8).clamp(12.0, 28.0);
  }

  return HomeLayoutConfig(
    columns: cols,
    rows: rows,
    iconSize: iconSize,
    hSpacing: hSpacing,
    vSpacing: vSpacing,
    hMargin: hMargin,
    labelFontSize: labelFontSize,
  );
}
