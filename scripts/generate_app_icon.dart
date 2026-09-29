// ignore_for_file: avoid_print
//
// Solace App Icon Generator — 左蓝右粉双色版
// 图形：左侧蓝色渐变 + 右侧粉色渐变 + 白色爱心 + 双色 Solace 文字
//
// 用法：dart run scripts/generate_app_icon.dart

import 'dart:io';
import 'dart:math';

// ── 配置 ──
const int _designSize = 1024;
const int _blueTop = 0xFFB3E5FC;    // 浅蓝
const int _blueBottom = 0xFF81D4FA;  // 浅蓝
const int _pinkTop = 0xFFF8BBD0;    // 浅粉
const int _pinkBottom = 0xFFF48FB1; // 浅粉
const int _heartColor = 0xFFFFFFFF;

// Android mipmap 尺寸规范
const Map<String, int> _launcherSizes = {
  'mipmap-mdpi': 48,
  'mipmap-hdpi': 72,
  'mipmap-xhdpi': 96,
  'mipmap-xxhdpi': 144,
  'mipmap-xxxhdpi': 192,
};

const Map<String, int> _foregroundSizes = {
  'mipmap-mdpi': 108,
  'mipmap-hdpi': 162,
  'mipmap-xhdpi': 216,
  'mipmap-xxhdpi': 324,
  'mipmap-xxxhdpi': 432,
};

// 自适应图标背景尺寸（与前景一致）
const Map<String, int> _backgroundSizes = {
  'mipmap-mdpi': 108,
  'mipmap-hdpi': 162,
  'mipmap-xhdpi': 216,
  'mipmap-xxhdpi': 324,
  'mipmap-xxxhdpi': 432,
};

void main() {
  final projectRoot = _findProjectRoot();
  final resDir = Directory('$projectRoot/android/app/src/main/res');

  if (!resDir.existsSync()) {
    print('❌ 找不到 res 目录: ${resDir.path}');
    exit(1);
  }

  print('🎨 Solace App Icon Generator — 左蓝右粉版');
  print('   设计稿: ${_designSize}x${_designSize}');
  print('');

  // 1. 生成设计稿
  print('📝 生成设计稿...');
  final design = _generateDesign(_designSize);

  // 1.5 保存 1024x1024 高清设计稿到 assets/
  final assetsDir = Directory('$projectRoot/assets');
  if (assetsDir.existsSync()) {
    final hdPath = '${assetsDir.path}/app_icon_1024.png';
    File(hdPath).writeAsBytesSync(_encodePng(design));
    print('   ✅ 设计稿已保存: $hdPath');
  }

  // 2. SVG 源文件已手动更新，跳过

  // 3. 生成 ic_launcher.png
  print('📱 生成 ic_launcher.png:');
  for (final entry in _launcherSizes.entries) {
    final dir = Directory('${resDir.path}/${entry.key}');
    if (!dir.existsSync()) continue;
    final resized = _resizeImage(design, entry.value);
    File('${dir.path}/ic_launcher.png').writeAsBytesSync(_encodePng(resized));
    print('   ✅ ${entry.key} (${entry.value}x${entry.value})');
  }

  // 4. 生成 ic_launcher_foreground.png
  print('📱 生成 ic_launcher_foreground.png:');
  for (final entry in _foregroundSizes.entries) {
    final dir = Directory('${resDir.path}/${entry.key}');
    if (!dir.existsSync()) continue;
    final fg = _generateForeground(entry.value);
    File('${dir.path}/ic_launcher_foreground.png').writeAsBytesSync(_encodePng(fg));
    print('   ✅ ${entry.key} (${entry.value}x${entry.value})');
  }

  // 5. 生成 ic_launcher_background.png（左蓝右粉渐变底板）
  print('📱 生成 ic_launcher_background.png:');
  for (final entry in _backgroundSizes.entries) {
    final dir = Directory('${resDir.path}/${entry.key}');
    if (!dir.existsSync()) continue;
    final bg = _generateBackground(entry.value);
    File('${dir.path}/ic_launcher_background.png').writeAsBytesSync(_encodePng(bg));
    print('   ✅ ${entry.key} (${entry.value}x${entry.value})');
  }

  print('\n🎉 全部图标生成完毕！');
}

// ─────────────────────────────────────────────────
// 图标绘制
// ─────────────────────────────────────────────────

List<List<_Pixel>> _generateDesign(int size) {
  final pixels = List.generate(
    size,
    (y) => List.generate(size, (x) => _Pixel(0, 0, 0, 0)),
  );

  final centerX = size / 2;

  // 背景：左蓝右粉，各自带垂直渐变
  for (int y = 0; y < size; y++) {
    final t = y / size;
    final blue = _Pixel.lerp(_Pixel.fromHex(_blueTop), _Pixel.fromHex(_blueBottom), t);
    final pink = _Pixel.lerp(_Pixel.fromHex(_pinkTop), _Pixel.fromHex(_pinkBottom), t);

    for (int x = 0; x < size; x++) {
      pixels[y][x] = x < centerX ? blue : pink;
    }
  }

  // 圆角裁剪（模拟 squircle）
  final radius = size * 0.215;
  for (int y = 0; y < size; y++) {
    for (int x = 0; x < size; x++) {
      if (!_isInsideRoundedRect(x, y, size, size, radius)) {
        pixels[y][x] = _Pixel(0, 0, 0, 0);
      }
    }
  }

  // 白色爱心（居中）
  final heartSize = size * 0.28;
  final heartCX = centerX;
  final heartCY = size * 0.40;

  for (int y = 0; y < size; y++) {
    for (int x = 0; x < size; x++) {
      final dx = (x - heartCX) / heartSize;
      final dy = (y - heartCY) / heartSize;
      if (_isInsideHeart(dx, dy)) {
        pixels[y][x] = _Pixel.fromHex(_heartColor);
      }
    }
  }

  // Solace 文字（偏下）：左蓝右粉
  _drawDualColorText(
    pixels, 'Solace', centerX, size * 0.79, size * 0.088,
    _Pixel.fromHex(_blueBottom), _Pixel.fromHex(_pinkBottom), centerX,
  );

  return pixels;
}

/// 生成自适应图标前景层：白色爱心 + 双色文字
/// Android 安全区域：中心 66%（108dp 中只有 72dp 可见）
/// 内容必须在 25%~75% 范围内（留足余量）
List<List<_Pixel>> _generateForeground(int size) {
  final pixels = List.generate(
    size,
    (y) => List.generate(size, (x) => _Pixel(0, 0, 0, 0)),
  );

  final centerX = size / 2;

  // 爱心（居中偏下）
  final heartSize = size * 0.13;
  final heartCX = centerX;
  final heartCY = size * 0.46;

  for (int y = 0; y < size; y++) {
    for (int x = 0; x < size; x++) {
      final dx = (x - heartCX) / heartSize;
      final dy = (y - heartCY) / heartSize;
      if (_isInsideHeart(dx, dy)) {
        pixels[y][x] = _Pixel.fromHex(_heartColor);
      }
    }
  }

  // 文字（深色，安全区内偏下）
  _drawDualColorText(
    pixels, 'Solace', centerX, size * 0.70, size * 0.06,
    _Pixel.fromHex(0xFF1565C0), _Pixel.fromHex(0xFFD81B60), centerX,
  );

  return pixels;
}

/// 生成自适应图标背景层：左蓝右粉渐变底板（全尺寸，无圆角，不透明）
List<List<_Pixel>> _generateBackground(int size) {
  final pixels = List.generate(
    size,
    (y) => List.generate(size, (x) => _Pixel(0, 0, 0, 255)),
  );

  final centerX = size / 2;

  for (int y = 0; y < size; y++) {
    final t = y / size;
    final blue = _Pixel.lerp(_Pixel.fromHex(_blueTop), _Pixel.fromHex(_blueBottom), t);
    final pink = _Pixel.lerp(_Pixel.fromHex(_pinkTop), _Pixel.fromHex(_pinkBottom), t);

    for (int x = 0; x < size; x++) {
      pixels[y][x] = x < centerX ? blue : pink;
    }
  }

  return pixels;
}

bool _isInsideRoundedRect(int x, int y, int w, int h, double r) {
  // 四个角的圆角判定
  if (x < r && y < r) return sqrt(pow(x - r, 2) + pow(y - r, 2)) <= r;
  if (x >= w - r && y < r) return sqrt(pow(x - (w - r), 2) + pow(y - r, 2)) <= r;
  if (x < r && y >= h - r) return sqrt(pow(x - r, 2) + pow(y - (h - r), 2)) <= r;
  if (x >= w - r && y >= h - r) return sqrt(pow(x - (w - r), 2) + pow(y - (h - r), 2)) <= r;
  return true;
}

bool _isInsideHeart(double dx, double dy) {
  final x = dx;
  final y = -dy;
  final a = x * x + y * y - 1;
  return a * a * a - x * x * y * y * y < 0;
}

// ─────────────────────────────────────────────────
// 双色文字绘制
// ─────────────────────────────────────────────────

void _drawDualColorText(
  List<List<_Pixel>> pixels,
  String text,
  double centerX,
  double y,
  double fontSize,
  _Pixel leftColor,
  _Pixel rightColor,
  double splitX,
) {
  final charWidth = fontSize * 0.55;
  final spacing = fontSize * 0.12;
  final totalWidth = text.length * charWidth + (text.length - 1) * spacing;
  final startX = centerX - totalWidth / 2;

  for (int i = 0; i < text.length; i++) {
    final charCenterX = startX + i * (charWidth + spacing) + charWidth / 2;
    _drawCharDualColor(pixels, text[i], charCenterX, y, fontSize, leftColor, rightColor, splitX);
  }
}

void _drawCharDualColor(
  List<List<_Pixel>> pixels,
  String char,
  double cx,
  double cy,
  double size,
  _Pixel leftColor,
  _Pixel rightColor,
  double splitX,
) {
  final bitmap = _getCharBitmap(char);
  if (bitmap.isEmpty) return;

  final pixelSize = size / 7;
  final startX = cx - (bitmap[0].length * pixelSize) / 2;
  final startY = cy - (bitmap.length * pixelSize) / 2;

  for (int row = 0; row < bitmap.length; row++) {
    for (int col = 0; col < bitmap[row].length; col++) {
      if (bitmap[row][col] == 1) {
        final px = startX + col * pixelSize + pixelSize / 2;
        final color = px < splitX ? leftColor : rightColor;
        _drawFilledRect(
          pixels,
          startX + col * pixelSize,
          startY + row * pixelSize,
          pixelSize,
          pixelSize,
          _pixelToHex(color),
        );
      }
    }
  }
}

int _pixelToHex(_Pixel p) => (p.r << 16) | (p.g << 8) | p.b;

List<List<int>> _getCharBitmap(String char) {
  switch (char.toUpperCase()) {
    case 'S':
      return [
        [0, 1, 1, 1, 0],
        [1, 0, 0, 0, 1],
        [1, 0, 0, 0, 0],
        [0, 1, 1, 1, 0],
        [0, 0, 0, 0, 1],
        [1, 0, 0, 0, 1],
        [0, 1, 1, 1, 0],
      ];
    case 'O':
      return [
        [0, 1, 1, 1, 0],
        [1, 0, 0, 0, 1],
        [1, 0, 0, 0, 1],
        [1, 0, 0, 0, 1],
        [1, 0, 0, 0, 1],
        [1, 0, 0, 0, 1],
        [0, 1, 1, 1, 0],
      ];
    case 'L':
      return [
        [1, 0, 0, 0, 0],
        [1, 0, 0, 0, 0],
        [1, 0, 0, 0, 0],
        [1, 0, 0, 0, 0],
        [1, 0, 0, 0, 0],
        [1, 0, 0, 0, 0],
        [1, 1, 1, 1, 1],
      ];
    case 'A':
      return [
        [0, 1, 1, 1, 0],
        [1, 0, 0, 0, 1],
        [1, 0, 0, 0, 1],
        [1, 1, 1, 1, 1],
        [1, 0, 0, 0, 1],
        [1, 0, 0, 0, 1],
        [1, 0, 0, 0, 1],
      ];
    case 'C':
      return [
        [0, 1, 1, 1, 0],
        [1, 0, 0, 0, 1],
        [1, 0, 0, 0, 0],
        [1, 0, 0, 0, 0],
        [1, 0, 0, 0, 0],
        [1, 0, 0, 0, 1],
        [0, 1, 1, 1, 0],
      ];
    case 'E':
      return [
        [1, 1, 1, 1, 1],
        [1, 0, 0, 0, 0],
        [1, 0, 0, 0, 0],
        [1, 1, 1, 1, 0],
        [1, 0, 0, 0, 0],
        [1, 0, 0, 0, 0],
        [1, 1, 1, 1, 1],
      ];
    default:
      return [];
  }
}

// ─────────────────────────────────────────────────
// 基础绘图
// ─────────────────────────────────────────────────

void _drawFilledRect(List<List<_Pixel>> pixels, double x, double y, double w, double h, int color) {
  final p = _Pixel.fromHex(color);
  final x0 = x.floor().clamp(0, pixels[0].length - 1);
  final y0 = y.floor().clamp(0, pixels.length - 1);
  final x1 = (x + w).ceil().clamp(0, pixels[0].length - 1);
  final y1 = (y + h).ceil().clamp(0, pixels.length - 1);
  for (int py = y0; py < y1; py++) {
    for (int px = x0; px < x1; px++) {
      pixels[py][px] = p;
    }
  }
}

List<List<_Pixel>> _resizeImage(List<List<_Pixel>> src, int targetSize) {
  final srcH = src.length;
  final srcW = src[0].length;
  return List.generate(targetSize, (y) {
    return List.generate(targetSize, (x) {
      final srcX = x * srcW / targetSize;
      final srcY = y * srcH / targetSize;
      final x0 = srcX.floor().clamp(0, srcW - 1);
      final y0 = srcY.floor().clamp(0, srcH - 1);
      final x1 = (x0 + 1).clamp(0, srcW - 1);
      final y1 = (y0 + 1).clamp(0, srcH - 1);
      final fx = srcX - x0;
      final fy = srcY - y0;
      return _Pixel.lerp(
        _Pixel.lerp(src[y0][x0], src[y0][x1], fx),
        _Pixel.lerp(src[y1][x0], src[y1][x1], fx),
        fy,
      );
    });
  });
}

// ─────────────────────────────────────────────────
// PNG 编码
// ─────────────────────────────────────────────────

List<int> _encodePng(List<List<_Pixel>> pixels) {
  final height = pixels.length;
  final width = pixels[0].length;
  final bytes = <int>[];
  bytes.addAll([137, 80, 78, 71, 13, 10, 26, 10]);

  final ihdr = <int>[];
  _addInt32(ihdr, width);
  _addInt32(ihdr, height);
  ihdr.addAll([8, 6, 0, 0, 0]);
  _addChunk(bytes, 'IHDR', ihdr);

  final rawData = <int>[];
  for (int y = 0; y < height; y++) {
    rawData.add(0);
    for (int x = 0; x < width; x++) {
      final p = pixels[y][x];
      rawData.addAll([p.r, p.g, p.b, p.a]);
    }
  }
  _addChunk(bytes, 'IDAT', _zlibCompress(rawData));
  _addChunk(bytes, 'IEND', <int>[]);
  return bytes;
}

void _addChunk(List<int> bytes, String type, List<int> data) {
  _addInt32(bytes, data.length);
  final typeBytes = type.codeUnits;
  bytes.addAll(typeBytes);
  bytes.addAll(data);
  _addInt32(bytes, _crc32([...typeBytes, ...data]));
}

void _addInt32(List<int> bytes, int value) {
  bytes.addAll([(value >> 24) & 0xFF, (value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF]);
}

List<int>? _crc32Table;
int _crc32(List<int> data) {
  _crc32Table ??= List.generate(256, (i) {
    var crc = i;
    for (int j = 0; j < 8; j++) {
      crc = (crc & 1) != 0 ? 0xEDB88320 ^ (crc >> 1) : crc >> 1;
    }
    return crc;
  });
  var crc = 0xFFFFFFFF;
  for (final byte in data) {
    crc = _crc32Table![(crc ^ byte) & 0xFF] ^ (crc >> 8);
  }
  return crc ^ 0xFFFFFFFF;
}

List<int> _zlibCompress(List<int> data) {
  final result = <int>[];
  result.addAll([0x78, 0x01]);
  const blockSize = 65535;
  int offset = 0;
  while (offset < data.length) {
    final remaining = data.length - offset;
    final chunkSize = remaining > blockSize - 5 ? blockSize - 5 : remaining;
    final isLast = offset + chunkSize >= data.length;
    result.add(isLast ? 0x01 : 0x00);
    result.add(chunkSize & 0xFF);
    result.add((chunkSize >> 8) & 0xFF);
    result.add((~chunkSize) & 0xFF);
    result.add(((~chunkSize) >> 8) & 0xFF);
    result.addAll(data.sublist(offset, offset + chunkSize));
    offset += chunkSize;
  }
  int a = 1, b = 0;
  for (final byte in data) {
    a = (a + byte) % 65521;
    b = (b + a) % 65521;
  }
  _addInt32(result, (b << 16) | a);
  return result;
}

// ─────────────────────────────────────────────────
// 工具
// ─────────────────────────────────────────────────

String _findProjectRoot() {
  var dir = Directory.current;
  while (true) {
    if (File('${dir.path}/pubspec.yaml').existsSync()) return dir.path;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  return Directory.current.path;
}

class _Pixel {
  final int r, g, b, a;
  const _Pixel(this.r, this.g, this.b, [this.a = 255]);

  factory _Pixel.fromHex(int hex) => _Pixel((hex >> 16) & 0xFF, (hex >> 8) & 0xFF, hex & 0xFF, 255);

  static _Pixel lerp(_Pixel a, _Pixel b, double t) => _Pixel(
    (a.r + (b.r - a.r) * t).round().clamp(0, 255),
    (a.g + (b.g - a.g) * t).round().clamp(0, 255),
    (a.b + (b.b - a.b) * t).round().clamp(0, 255),
    (a.a + (b.a - a.a) * t).round().clamp(0, 255),
  );
}
