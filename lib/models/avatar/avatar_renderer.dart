import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'avatar_config.dart';

/// 单部位渲染单元
class AvatarPartSpec {
  final String part;
  final String variant;
  final String path;
  final Offset offset;
  final double scale;
  final Color? tint;
  final bool visible;

  const AvatarPartSpec({
    required this.part,
    required this.variant,
    required this.path,
    this.offset = Offset.zero,
    this.scale = 1.0,
    this.tint,
    this.visible = true,
  });
}

/// 内置素材目录与默认变体定义
class AvatarAssets {
  static const String base = 'assets/live2d/variants';

  static const Map<String, List<String>> variants = {
    'bodies': ['default', 'slim', 'chibi'],
    'heads': ['default', 'round', 'sharp'],
    'faces': ['default', 'pale', 'tan', 'cool'],
    'hair_front': ['bob', 'long', 'short', 'bangs', 'twin_tails'],
    'hair_back': ['bob', 'long', 'short', 'twin_tails'],
    'eyebrows': ['default', 'thick', 'thin', 'curved', 'flat'],
    'eyes': ['default', 'round', 'slim', 'doe', 'sleepy'],
    'mouths': ['default', 'smile', 'frown', 'open', 'pout', 'surprise'],
    'shirts': ['default', 'sailor', 'hoodie', 'uniform', 'dress'],
    'pants': ['default', 'skirt', 'jeans', 'shorts'],
    'accessories': ['none', 'cat_ears', 'glasses', 'ribbon', 'hat'],
  };

  static String pathFor(String part, String variant) =>
      '$base/$part/$variant.png';

  static List<String> variantsFor(String part) =>
      variants[part] ?? const ['default'];
}

/// Avatar 渲染器
///
/// 根据 AvatarConfig 生成部位列表、计算捏脸偏移、应用化妆色调。
class AvatarRenderer {
  static const Size canvasSize = Size(200, 250);
  static const Offset center = Offset(100, 125);

  /// 将配置转成可渲染的部位列表（从后到前）
  static List<AvatarPartSpec> buildParts(AvatarConfig config) {
    final face = config.faceShape;
    final makeup = config.makeup;

    // 基础头部缩放
    final headScale = 1.0 + face.headScale * 0.15;

    // 眼睛偏移（像素）
    final eyeSpacingPx = face.eyeSpacing * 20;
    final eyeVerticalPx = face.eyeVertical * 15;
    final eyeScale = 1.0 + face.eyeScale * 0.25;

    // 嘴巴偏移
    final mouthVerticalPx = face.mouthVertical * 12;
    final mouthScale = 1.0 + face.mouthScale * 0.25;

    // 眉毛偏移
    final eyebrowVerticalPx = face.eyebrowVertical * 10;
    final eyebrowTiltRad = face.eyebrowTilt * 0.2;

    final List<AvatarPartSpec> parts = [];

    // 1. 身体
    parts.add(_part(
      part: 'body',
      variant: config.bodyVariant,
      config: config,
      offset: const Offset(0, 20),
      tint: makeup.skinColor,
    ));

    // 2. 下装（在身体上但可能被衬衫遮挡）
    parts.add(_part(
      part: 'pants',
      variant: config.pantsVariant,
      config: config,
      offset: const Offset(0, 10),
    ));

    // 3. 上衣
    parts.add(_part(
      part: 'shirt',
      variant: config.shirtVariant,
      config: config,
      offset: const Offset(0, 12),
    ));

    // 4. 头部（受 headScale 影响）
    parts.add(_part(
      part: 'head',
      variant: config.headVariant,
      config: config,
      offset: const Offset(0, -10),
      scale: headScale,
      tint: makeup.skinColor,
    ));

    // 5. 后发
    parts.add(_part(
      part: 'hair_back',
      variant: config.hairBackVariant,
      config: config,
      offset: const Offset(0, -12),
      scale: headScale,
      tint: makeup.hairColor,
    ));

    // 6. 脸部
    parts.add(_part(
      part: 'face',
      variant: config.faceVariant,
      config: config,
      offset: const Offset(0, -10),
      scale: headScale,
      tint: makeup.skinColor,
    ));

    // 7. 眉毛
    parts.add(_part(
      part: 'eyebrows',
      variant: config.eyebrowVariant,
      config: config,
      offset: Offset(0, -18 + eyebrowVerticalPx),
      scale: headScale,
      rotation: eyebrowTiltRad,
      tint: makeup.hairColor,
    ));

    // 8. 眼睛（左眼/右眼分别偏移）
    parts.add(_part(
      part: 'eyes',
      variant: config.eyesVariant,
      config: config,
      offset: Offset(-eyeSpacingPx, -8 + eyeVerticalPx),
      scale: headScale * eyeScale,
      tint: makeup.irisColor,
    ));

    // 9. 嘴巴
    parts.add(_part(
      part: 'mouths',
      variant: config.mouthVariant,
      config: config,
      offset: Offset(0, 8 + mouthVerticalPx),
      scale: headScale * mouthScale,
      tint: makeup.lipColor,
    ));

    // 10. 眼影/腮红层（半透明叠加）
    parts.add(_makeupLayer(
      part: 'eye_shadow',
      color: makeup.eyeShadowColor,
      config: config,
      offset: Offset(-eyeSpacingPx, -8 + eyeVerticalPx),
      scale: headScale * eyeScale,
    ));
    parts.add(_makeupLayer(
      part: 'blush',
      color: makeup.blushColor,
      config: config,
      offset: const Offset(0, 2),
      scale: headScale,
    ));

    // 11. 前发
    parts.add(_part(
      part: 'hair_front',
      variant: config.hairFrontVariant,
      config: config,
      offset: const Offset(0, -12),
      scale: headScale,
      tint: makeup.hairColor,
    ));

    // 12. 饰品
    if (config.accessoryVariant != null && config.accessoryVariant != 'none') {
      parts.add(_part(
        part: 'accessories',
        variant: config.accessoryVariant!,
        config: config,
        offset: const Offset(0, -20),
        scale: headScale,
      ));
    }

    return parts.where((p) => p.visible).toList();
  }

  static AvatarPartSpec _part({
    required String part,
    required String variant,
    required AvatarConfig config,
    Offset offset = Offset.zero,
    double scale = 1.0,
    double rotation = 0.0,
    Color? tint,
  }) {
    return AvatarPartSpec(
      part: part,
      variant: variant,
      path: AvatarAssets.pathFor(part, variant),
      offset: offset,
      scale: scale,
      tint: tint,
      visible: config.visibleParts.contains(part),
    );
  }

  /// 化妆层（腮红、眼影等）用纯色圆形/椭圆占位，后续可替换为专用素材
  static AvatarPartSpec _makeupLayer({
    required String part,
    required Color color,
    required AvatarConfig config,
    Offset offset = Offset.zero,
    double scale = 1.0,
  }) {
    return AvatarPartSpec(
      part: part,
      variant: 'solid',
      path: '', // 空路径表示纯色层，由渲染层绘制
      offset: offset,
      scale: scale,
      tint: color,
      visible: color.opacity > 0.05,
    );
  }

  /// 加载图片并应用色调（可选）
  static Future<ui.Image?> loadImage(String path, {Color? tint}) async {
    if (path.isEmpty) return null;
    try {
      final data = await rootBundle.load(path);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      return frame.image;
    } catch (e) {
      debugPrint('AvatarRenderer loadImage failed: $path, $e');
      return null;
    }
  }
}

/// CustomPainter 绘制 Avatar，用于悬浮窗和预览页面
class AvatarPainter extends CustomPainter {
  final List<AvatarPartSpec> parts;
  final Map<String, ui.Image> imageCache;

  const AvatarPainter(this.parts, this.imageCache);

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);

    for (final part in parts) {
      if (!part.visible) continue;

      canvas.save();
      canvas.translate(center.dx + part.offset.dx, center.dy + part.offset.dy);
      canvas.scale(part.scale);

      if (part.path.isEmpty && part.tint != null) {
        // 纯色化妆层占位
        _drawMakeupLayer(canvas, part);
      } else if (imageCache.containsKey(part.path)) {
        final image = imageCache[part.path]!;
        final paint = Paint();
        if (part.tint != null && part.tint != Colors.white) {
          paint.colorFilter = ColorFilter.mode(
            part.tint!,
            BlendMode.srcATop,
          );
        }
        final src = Rect.fromLTWH(
          0,
          0,
          image.width.toDouble(),
          image.height.toDouble(),
        );
        final dst = Rect.fromCenter(
          center: Offset.zero,
          width: AvatarRenderer.canvasSize.width,
          height: AvatarRenderer.canvasSize.height,
        );
        canvas.drawImageRect(image, src, dst, paint);
      } else if (part.path.isNotEmpty) {
        // PNG 素材缺失时的矢量 fallback：画一个简笔占位形状，
        // 让悬浮窗在没有 PNG 素材时也能看到一个完整人形，
        // 后续替换为正式 PNG 素材时自动接管。
        _drawFallbackShape(canvas, part);
      }

      canvas.restore();
    }
  }

  void _drawMakeupLayer(Canvas canvas, AvatarPartSpec part) {
    final paint = Paint()..color = part.tint!;
    switch (part.part) {
      case 'blush':
        canvas.drawOval(
          Rect.fromCenter(
            center: const Offset(-30, 20),
            width: 30 * part.scale,
            height: 18 * part.scale,
          ),
          paint,
        );
        canvas.drawOval(
          Rect.fromCenter(
            center: const Offset(30, 20),
            width: 30 * part.scale,
            height: 18 * part.scale,
          ),
          paint,
        );
        break;
      case 'eye_shadow':
        canvas.drawOval(
          Rect.fromCenter(
            center: const Offset(0, 0),
            width: 50 * part.scale,
            height: 28 * part.scale,
          ),
          paint,
        );
        break;
    }
  }

  /// PNG 素材缺失时的矢量占位绘制
  ///
  /// 当 assets/live2d/variants/{part}/{variant}.png 不存在时，
  /// 用基本几何形状画一个简笔人形，保证悬浮窗在没有素材时也能可见。
  /// 坐标系：当前 canvas 已 translate 到部位 offset，所以 (0, 0) 是部位中心。
  /// 坐标范围参考 canvasSize = Size(200, 250)，center = (100, 125)。
  /// 即 (0, 0) 在画布中是 (center.x + part.offset.x, center.y + part.offset.y)。
  void _drawFallbackShape(Canvas canvas, AvatarPartSpec part) {
    final tint = part.tint ?? Colors.grey;
    final fillPaint = Paint()
      ..color = tint
      ..style = PaintingStyle.fill;
    final strokePaint = Paint()
      ..color = tint.withOpacity(0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    switch (part.part) {
      case 'body':
        // 胶囊形身体：宽 100 高 130，垂直方向稍长
        final rect = Rect.fromCenter(
          center: Offset.zero,
          width: 100,
          height: 130,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(40)),
          fillPaint,
        );
        break;

      case 'pants':
        // 梯形下装：底部更宽
        final path = Path()
          ..moveTo(-35, -40)
          ..lineTo(35, -40)
          ..lineTo(45, 55)
          ..lineTo(-45, 55)
          ..close();
        canvas.drawPath(path, Paint()..color = const Color(0xFF3B5998));
        break;

      case 'shirt':
        // 梯形上衣
        final path = Path()
          ..moveTo(-40, -45)
          ..lineTo(40, -45)
          ..lineTo(45, 30)
          ..lineTo(-45, 30)
          ..close();
        canvas.drawPath(path, Paint()..color = const Color(0xFFFFFAFA));
        break;

      case 'head':
        // 圆形头部，直径 90
        canvas.drawCircle(Offset.zero, 45, fillPaint);
        break;

      case 'hair_back':
        // 后发：比头大一圈的圆（部分露出头外）
        canvas.drawCircle(Offset.zero, 52, fillPaint);
        break;

      case 'face':
        // 脸部和 head 重合，跳过避免覆盖 head 染色
        break;

      case 'eyebrows':
        // 两条短粗眉毛
        final eyebrowPath = Path()
          ..moveTo(-22, 0)
          ..lineTo(-8, 0)
          ..moveTo(8, 0)
          ..lineTo(22, 0);
        canvas.drawPath(eyebrowPath, strokePaint..strokeWidth = 4);
        break;

      case 'eyes':
        // 两个椭圆眼睛
        canvas.drawOval(
          Rect.fromCenter(center: const Offset(-18, 0), width: 14, height: 18),
          fillPaint,
        );
        canvas.drawOval(
          Rect.fromCenter(center: const Offset(18, 0), width: 14, height: 18),
          fillPaint,
        );
        // 高光小白点
        final highlightPaint = Paint()..color = Colors.white;
        canvas.drawCircle(const Offset(-15, -3), 3, highlightPaint);
        canvas.drawCircle(const Offset(21, -3), 3, highlightPaint);
        break;

      case 'mouths':
        // 微笑弧线
        final mouthPath = Path()
          ..moveTo(-15, 0)
          ..quadraticBezierTo(0, 12, 15, 0);
        canvas.drawPath(mouthPath, strokePaint..strokeWidth = 3);
        break;

      case 'hair_front':
        // 前发刘海：贝塞尔曲线绘制
        final hairPath = Path()
          ..moveTo(-50, -25)
          ..quadraticBezierTo(-50, -55, 0, -55)
          ..quadraticBezierTo(50, -55, 50, -25)
          ..quadraticBezierTo(40, -10, 25, -20)
          ..quadraticBezierTo(15, -35, 0, -25)
          ..quadraticBezierTo(-15, -35, -25, -20)
          ..quadraticBezierTo(-40, -10, -50, -25)
          ..close();
        canvas.drawPath(hairPath, fillPaint);
        break;

      case 'accessories':
        // 饰品 fallback 不画（避免遮挡）
        break;
    }
  }

  @override
  bool shouldRepaint(covariant AvatarPainter old) =>
      old.parts != parts || old.imageCache != imageCache;
}
