import 'dart:io';
import 'dart:math';
import 'package:image/image.dart' as img;

class ImageAnalysisResult {
  final String dominantColors;
  final String lighting;
  final String composition;
  final bool isWarm;
  final String colorRichness;
  final String sceneType;
  final bool hasPeople;
  final String objectComplexity;
  final String contrast;
  final String texture;
  final String mood;

  const ImageAnalysisResult({
    required this.dominantColors,
    required this.lighting,
    required this.composition,
    required this.isWarm,
    required this.colorRichness,
    this.sceneType = '未知',
    this.hasPeople = false,
    this.objectComplexity = '未知',
    this.contrast = '对比度适中',
    this.texture = '未知',
    this.mood = '普通',
  });
}

class ImageAnalyzer {
  static Future<ImageAnalysisResult> analyze(String imagePath) async {
    try {
      final file = File(imagePath);
      final bytes = await file.readAsBytes();
      final image = img.decodeImage(bytes);

      if (image == null) {
        return _fallbackResult();
      }

      final colors = _extractDominantColors(image);
      final brightness = _calculateBrightness(image);
      final comp = _analyzeComposition(image);
      final warm = _isWarmTone(colors);
      final richness = _analyzeColorRichness(image);
      final scene = _estimateSceneType(image, colors, brightness);
      final hasPeopleFlag = _detectSkinTone(image);
      final complexity = _analyzeEdgeDensity(image);
      final contrastLevel = _calculateContrast(image);
      final textureLevel = _analyzeTexture(image);
      final moodResult = _determineMood(scene, brightness, warm, richness, contrastLevel);

      return ImageAnalysisResult(
        dominantColors: colors,
        lighting: brightness,
        composition: comp,
        isWarm: warm,
        colorRichness: richness,
        sceneType: scene,
        hasPeople: hasPeopleFlag,
        objectComplexity: complexity,
        contrast: contrastLevel,
        texture: textureLevel,
        mood: moodResult,
      );
    } catch (e) {
      return _fallbackResult();
    }
  }

  static ImageAnalysisResult _fallbackResult() {
    return const ImageAnalysisResult(
      dominantColors: '未知',
      lighting: '正常',
      composition: '未知',
      isWarm: false,
      colorRichness: '未知',
      sceneType: '未知',
      hasPeople: false,
      objectComplexity: '未知',
      contrast: '对比度适中',
      texture: '未知',
      mood: '普通',
    );
  }

  static String _estimateSceneType(img.Image image, String colors, String lighting) {
    final w = image.width;
    final h = image.height;
    final step = max(1, (w * h ~/ 50000));

    int topBlue = 0, topWhite = 0, topCount = 0;
    int bottomGreen = 0, bottomBrown = 0, bottomCount = 0;
    int skinCount = 0, totalSampled = 0;
    int darkCount = 0;

    final skinColorRanges = [
      (rMin: 140, rMax: 255, gMin: 80, gMax: 200, bMin: 50, bMax: 180),
      (rMin: 180, rMax: 255, gMin: 120, gMax: 220, bMin: 80, bMax: 190),
      (rMin: 100, rMax: 220, gMin: 60, gMax: 170, bMin: 40, bMax: 150),
    ];

    for (int y = 0; y < h; y += step) {
      for (int x = 0; x < w; x += step) {
        final pixel = image.getPixel(x, y);
        final r = pixel.r.toInt();
        final g = pixel.g.toInt();
        final b = pixel.b.toInt();

        final lum = 0.299 * r + 0.587 * g + 0.114 * b;
        if (lum < 40) darkCount++;

        totalSampled++;

        if (y < h ~/ 3) {
          topCount++;
          if (b > 150 && b > r + 20 && b > g + 20) topBlue++;
          if (r > 200 && g > 200 && b > 200) topWhite++;
        }

        if (y > h * 2 ~/ 3) {
          bottomCount++;
          if (g > 120 && g > r + 20 && g > b + 20) bottomGreen++;
          if (r > 120 && g > 60 && g < 160 && b < 120) bottomBrown++;
        }

        for (final range in skinColorRanges) {
          if (r >= range.rMin && r <= range.rMax &&
              g >= range.gMin && g <= range.gMax &&
              b >= range.bMin && b <= range.bMax) {
            skinCount++;
            break;
          }
        }
      }
    }

    if (totalSampled == 0) return '未知';

    final skinRatio = skinCount / totalSampled;
    final darkRatio = darkCount / totalSampled;

    if (darkRatio > 0.6) return '夜景/暗光场景';

    if (skinRatio > 0.08) return '人像/自拍';

    final topBlueRatio = topCount > 0 ? topBlue / topCount : 0;
    final topWhiteRatio = topCount > 0 ? topWhite / topCount : 0;
    final bottomGreenRatio = bottomCount > 0 ? bottomGreen / bottomCount : 0;
    final bottomBrownRatio = bottomCount > 0 ? bottomBrown / bottomCount : 0;

    if (topBlueRatio > 0.3 && bottomGreenRatio > 0.2) return '自然风景/户外';
    if (topBlueRatio > 0.4) return '天空/海景';
    if (topWhiteRatio > 0.3 && bottomGreenRatio > 0.2) return '户外自然';
    if (bottomGreenRatio > 0.4) return '绿地/植被';

    if (bottomBrownRatio > 0.3) return '室内/建筑';

    if (bottomBrownRatio > 0.2 && colors.contains('暖色')) return '室内/家居';

    final warmColors = ['红色', '黄色', '橙色', '暖色', '粉色'];
    final hasWarmColor = warmColors.any((c) => colors.contains(c));
    if (hasWarmColor && colors.contains('绿色')) return '美食/餐饮';

    if (colors.contains('白色') && colors.contains('黑色')) return '文本/文档';
    if (colors.contains('白色') && colors.contains('蓝色')) return '户外/天空';

    return '日常场景';
  }

  static bool _detectSkinTone(img.Image image) {
    final w = image.width;
    final h = image.height;
    final centerX = w ~/ 2;
    final centerY = h ~/ 2;
    final regionSize = min(w, h) ~/ 4;
    final step = 4;

    int skinCount = 0;
    int totalChecked = 0;

    final skinColorRanges = [
      (rMin: 140, rMax: 255, gMin: 80, gMax: 200, bMin: 50, bMax: 180),
      (rMin: 180, rMax: 255, gMin: 120, gMax: 220, bMin: 80, bMax: 190),
      (rMin: 100, rMax: 220, gMin: 60, gMax: 170, bMin: 40, bMax: 150),
    ];

    for (int y = centerY - regionSize; y < centerY + regionSize; y += step) {
      for (int x = centerX - regionSize; x < centerX + regionSize; x += step) {
        if (x < 0 || x >= w || y < 0 || y >= h) continue;
        totalChecked++;

        final pixel = image.getPixel(x, y);
        final r = pixel.r.toInt();
        final g = pixel.g.toInt();
        final b = pixel.b.toInt();

        for (final range in skinColorRanges) {
          if (r >= range.rMin && r <= range.rMax &&
              g >= range.gMin && g <= range.gMax &&
              b >= range.bMin && b <= range.bMax) {
            skinCount++;
            break;
          }
        }
      }
    }

    if (totalChecked == 0) return false;
    return skinCount / totalChecked > 0.05;
  }

  static String _analyzeEdgeDensity(img.Image image) {
    final w = image.width;
    final h = image.height;
    final step = 4;
    int edgePixels = 0;
    int totalChecked = 0;

    for (int y = step; y < h - step; y += step) {
      for (int x = step; x < w - step; x += step) {
        final p1 = image.getPixel(x, y);
        final p2 = image.getPixel(x + step, y);
        final p3 = image.getPixel(x, y + step);

        final dr1 = (p1.r - p2.r).abs();
        final dg1 = (p1.g - p2.g).abs();
        final db1 = (p1.b - p2.b).abs();
        final gradX = dr1 + dg1 + db1;

        final dr2 = (p1.r - p3.r).abs();
        final dg2 = (p1.g - p3.g).abs();
        final db2 = (p1.b - p3.b).abs();
        final gradY = dr2 + dg2 + db2;

        if (gradX > 60 || gradY > 60) edgePixels++;
        totalChecked++;
      }
    }

    if (totalChecked == 0) return '未知';
    final edgeRatio = edgePixels / totalChecked;

    if (edgeRatio > 0.25) return '复杂（多物体/细节丰富）';
    if (edgeRatio > 0.12) return '适中';
    return '简单（主体突出/背景干净）';
  }

  static String _calculateContrast(img.Image image) {
    final w = image.width;
    final h = image.height;
    final step = max(1, (w * h ~/ 30000));

    double totalLuminance = 0;
    int count = 0;
    final luminanceValues = <double>[];

    for (int y = 0; y < h; y += step) {
      for (int x = 0; x < w; x += step) {
        final pixel = image.getPixel(x, y);
        final lum = 0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
        luminanceValues.add(lum);
        totalLuminance += lum;
        count++;
      }
    }

    if (count == 0) return '对比度适中';

    final mean = totalLuminance / count;
    double variance = 0;
    for (final lum in luminanceValues) {
      variance += (lum - mean) * (lum - mean);
    }
    variance /= count;
    final stdDev = sqrt(variance);

    if (stdDev > 60) return '高对比度（明暗层次分明）';
    if (stdDev > 30) return '对比度适中';
    return '低对比度（柔和/朦胧）';
  }

  static String _analyzeTexture(img.Image image) {
    final w = image.width;
    final h = image.height;
    final step = 4;
    double totalVariation = 0;
    int count = 0;

    for (int y = step; y < h - step; y += step) {
      for (int x = step; x < w - step; x += step) {
        final p1 = image.getPixel(x, y);
        final p2 = image.getPixel(x + 2, y + 2);

        final diff = (p1.r - p2.r).abs() + (p1.g - p2.g).abs() + (p1.b - p2.b).abs();
        totalVariation += diff;
        count++;
      }
    }

    if (count == 0) return '未知';
    final avgVariation = totalVariation / count;

    if (avgVariation > 100) return '粗糙纹理（有颗粒感/细节多）';
    if (avgVariation > 50) return '中等质感';
    return '细腻平滑（柔和/模糊）';
  }

  static String _determineMood(
    String sceneType,
    String lighting,
    bool isWarm,
    String colorRichness,
    String contrast,
  ) {
    if (sceneType == '夜景/暗光场景') return '神秘/安静';
    if (sceneType == '自然风景/户外' && lighting == '明亮') return '清新/开阔';
    if (sceneType == '人像/自拍' && isWarm) return '温馨/亲密';
    if (sceneType == '人像/自拍') return '生活/日常';

    if (isWarm && lighting == '明亮') return '温暖/愉悦';
    if (isWarm && lighting == '偏暗') return '温馨/柔和';

    if (lighting == '明亮' && colorRichness == '色彩丰富') return '活泼/充满活力';
    if (lighting == '明亮') return '明朗/清爽';

    if (lighting == '昏暗') return '安静/沉静';
    if (lighting == '偏暗') return '柔和/低调';

    if (contrast.contains('高对比度')) return '强烈/有冲击力';
    if (contrast.contains('低对比度')) return '柔和/梦幻';

    if (colorRichness == '色调单一') return '简约/素雅';

    return '自然/平和';
  }

  static String _extractDominantColors(img.Image image) {
    final colorCounts = <int, int>{};
    final step = (image.width * image.height > 10000) ? 10 : 5;

    for (int y = 0; y < image.height; y += step) {
      for (int x = 0; x < image.width; x += step) {
        final pixel = image.getPixel(x, y);
        final r = pixel.r.toInt();
        final g = pixel.g.toInt();
        final b = pixel.b.toInt();

        final quantized = _quantizeColor(r, g, b);
        colorCounts[quantized] = (colorCounts[quantized] ?? 0) + 1;
      }
    }

    final sorted = colorCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final topColors = sorted.take(3).map((e) => _colorToName(e.key)).toList();

    if (topColors.isEmpty) return '未知';
    return topColors.join('、');
  }

  static int _quantizeColor(int r, int g, int b) {
    return ((r ~/ 64) << 6) | ((g ~/ 64) << 3) | (b ~/ 64);
  }

  static String _colorToName(int quantized) {
    final r = ((quantized >> 6) & 7) * 64 + 32;
    final g = ((quantized >> 3) & 7) * 64 + 32;
    final b = (quantized & 7) * 64 + 32;

    if (r > 200 && g > 200 && b > 200) return '白色';
    if (r < 60 && g < 60 && b < 60) return '黑色';
    if (r > 180 && g > 140 && b < 100) return '暖色';
    if (r > 180 && g < 100 && b < 100) return '红色';
    if (r < 100 && g > 180 && b < 100) return '绿色';
    if (r < 100 && g < 100 && b > 180) return '蓝色';
    if (r > 180 && g > 180 && b < 100) return '黄色';
    if (r > 180 && g < 100 && b > 180) return '紫色';
    if (r > 180 && g > 140 && b > 140) return '粉色';

    if (r > g && r > b) return '暖色';
    if (g > r && g > b) return '绿色';
    if (b > r && b > g) return '蓝色';

    return '彩色';
  }

  static String _calculateBrightness(img.Image image) {
    double totalBrightness = 0;
    int count = 0;
    final step = (image.width * image.height > 10000) ? 10 : 5;

    for (int y = 0; y < image.height; y += step) {
      for (int x = 0; x < image.width; x += step) {
        final pixel = image.getPixel(x, y);
        final brightness = 0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
        totalBrightness += brightness;
        count++;
      }
    }

    if (count == 0) return '正常';

    final avg = totalBrightness / count;
    if (avg > 180) return '明亮';
    if (avg > 120) return '适中';
    if (avg > 60) return '偏暗';
    return '昏暗';
  }

  static String _analyzeComposition(img.Image image) {
    final ratio = image.width / image.height;

    if (ratio > 1.5) return '横向宽幅';
    if (ratio > 1.2) return '横向';
    if (ratio < 0.67) return '竖向长幅';
    if (ratio < 0.85) return '竖向';
    return '方形';
  }

  static bool _isWarmTone(String dominantColors) {
    final warmColors = ['红色', '黄色', '橙色', '暖色', '粉色'];
    return warmColors.any((c) => dominantColors.contains(c));
  }

  static String _analyzeColorRichness(img.Image image) {
    final uniqueColors = <int>{};
    final step = (image.width * image.height > 10000) ? 15 : 8;

    for (int y = 0; y < image.height; y += step) {
      for (int x = 0; x < image.width; x += step) {
        final pixel = image.getPixel(x, y);
        final r = (pixel.r ~/ 32) * 32;
        final g = (pixel.g ~/ 32) * 32;
        final b = (pixel.b ~/ 32) * 32;
        uniqueColors.add((r << 16) | (g << 8) | b);
      }
    }

    final count = uniqueColors.length;
    if (count > 80) return '色彩丰富';
    if (count > 40) return '色彩适中';
    return '色调单一';
  }
}