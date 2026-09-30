import 'dart:io';
import 'dart:math' as math;
// 用别名隔离：dart:io 也 re-export 了 Uint8List，直接同名 import 依赖 SDK 行为不可靠。
import 'dart:typed_data' as td;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// 头像/图片裁剪的几何计算。
///
/// 拆成纯函数（不依赖渲染），便于单元测试直接验证边界，
/// 见 `test/image_cropper_test.dart`。
class CropGeometry {
  CropGeometry._();

  /// 旋转 [quarterTurns] 个 90° 之后的「显示尺寸」。
  /// 图像本身始终按原始宽高绘制，旋转只发生在画布/Transform 坐标系里。
  static Size effectiveSize(int imgW, int imgH, int quarterTurns) {
    if (imgW <= 0 || imgH <= 0) return const Size(1, 1);
    return quarterTurns.isOdd
        ? Size(imgH.toDouble(), imgW.toDouble())
        : Size(imgW.toDouble(), imgH.toDouble());
  }

  /// 刚好铺满取景框所需的缩放（cover）。
  /// 图片不允许缩到比它更小，否则取景框会露白。
  /// [box] 是取景框边长（正方形）。
  static double coverScale(Size disp, double box) =>
      coverScaleForBox(disp, Size(box, box));

  /// [boxSize] 为取景框尺寸（可非正方形，背景图用）。
  static double coverScaleForBox(Size disp, Size boxSize) {
    if (disp.width <= 0 || disp.height <= 0) return 1.0;
    if (boxSize.width <= 0 || boxSize.height <= 0) return 1.0;
    return math.max(boxSize.width / disp.width, boxSize.height / disp.height);
  }

  /// 允许的最大放大倍数（相对 [minScale]）。
  static const double maxZoomFactor = 4.0;

  static double clampScale(double scale, double minScale) {
    final upper = minScale * maxZoomFactor;
    if (scale < minScale) return minScale;
    if (scale > upper) return upper;
    return scale;
  }

  /// 把位移夹在「图片边缘刚好不越过取景框」的范围内。
  /// [offset] 相对取景框中心，[disp] 为旋转后的显示尺寸。
  static Offset clampOffset(
      Offset offset, Size disp, double box, double scale) =>
      clampOffsetForBox(offset, disp, Size(box, box), scale);

  /// [boxSize] 为取景框尺寸（可非正方形）。
  static Offset clampOffsetForBox(
      Offset offset, Size disp, Size boxSize, double scale) {
    if (boxSize.width <= 0 || boxSize.height <= 0) return offset;
    final shownW = disp.width * scale;
    final shownH = disp.height * scale;
    final maxX = math.max(0.0, (shownW - boxSize.width) / 2);
    final maxY = math.max(0.0, (shownH - boxSize.height) / 2);
    return Offset(
      offset.dx.clamp(-maxX, maxX).toDouble(),
      offset.dy.clamp(-maxY, maxY).toDouble(),
    );
  }

  /// 双指缩放时保持焦点下方的像素不动。
  ///
  /// [focal] 相对取景框中心；[startScale]/[startOffset] 是手势开始时的快照。
  /// 先反推该焦点对应的图像局部坐标 p，再按新缩放求新位移。
  static Offset offsetForScale({
    required Offset focal,
    required double startScale,
    required Offset startOffset,
    required double newScale,
  }) {
    if (startScale <= 0) return Offset.zero;
    final px = (focal.dx - startOffset.dx) / startScale;
    final py = (focal.dy - startOffset.dy) / startScale;
    return Offset(focal.dx - px * newScale, focal.dy - py * newScale);
  }
}

/// 打开全屏裁剪页，对 [file] 做「缩放 + 移动 + 旋转 + 裁剪」。
///
/// 返回裁剪后写入 `docs/<folder>` 的文件路径；用户取消返回 null。
///
/// - [aspectRatio] 取景框宽高比。头像传 1.0（正方形，匹配圆形显示）；
///   背景图传 16/9 之类的宽幅。
/// - [outputSize] 输出图长边像素。头像 512；背景图可给 1080/1920。
/// - [folder] 相对 `docs` 的子目录，默认 `avatars`。
/// - [allowRotate] 背景图一般不需要旋转，可关掉省一个按钮。
Future<String?> showImageCropper(
  BuildContext context,
  File file, {
  double aspectRatio = 1.0,
  int outputSize = 512,
  String folder = 'avatars',
  bool allowRotate = true,
}) {
  assert(aspectRatio > 0, 'aspectRatio 必须为正数');
  return Navigator.of(context).push<String>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _CropperRoute(
        file: file,
        outputSize: outputSize,
        aspectRatio: aspectRatio,
        folder: folder,
        allowRotate: allowRotate,
      ),
    ),
  );
}

/// 裁剪页的当前变换状态（由交互区实时回传）。
class CropTransform {
  final double scale;
  final Offset offset;
  final int quarterTurns;

  /// 取景框在屏幕上的尺寸（可非正方形：头像为正方形，背景图为宽幅）。
  final Size boxSize;

  const CropTransform({
    required this.scale,
    required this.offset,
    required this.quarterTurns,
    required this.boxSize,
  });

  static const CropTransform initial = CropTransform(
    scale: 1,
    offset: Offset.zero,
    quarterTurns: 0,
    boxSize: Size.zero,
  );
}

class _CropperRoute extends StatefulWidget {
  final File file;
  final int outputSize;
  final double aspectRatio;
  final String folder;
  final bool allowRotate;

  const _CropperRoute({
    required this.file,
    required this.outputSize,
    required this.aspectRatio,
    required this.folder,
    required this.allowRotate,
  });

  @override
  State<_CropperRoute> createState() => _CropperRouteState();
}

class _CropperRouteState extends State<_CropperRoute> {
  ui.Image? _image;
  String? _error;
  bool _saving = false;

  /// 变换状态只存在这一份，交互区通过 onChanged 回传。
  CropTransform _t = CropTransform.initial;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  // instantiateImageCodec 要求 Uint8List；File.readAsBytes() 返回的正是 Uint8List，
  // 所以这里必须声明成 Uint8List，写成 List<int> 会编译报错。
  Future<ui.Image> _decodeOnce(td.Uint8List bytes,
      {int? targetWidth, int? targetHeight}) async {
    final ui.Codec codec;
    if (targetWidth != null && targetHeight != null) {
      codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: targetWidth,
        targetHeight: targetHeight,
      );
    } else {
      codec = await ui.instantiateImageCodec(bytes);
    }
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  Future<void> _load() async {
    try {
      final bytes = await widget.file.readAsBytes();
      var img = await _decodeOnce(bytes);

      // 手机大图动辄 4000px，直接解码会吃掉上百 MB 内存。
      // 头像最终只输出 512，缩到 2048 已经绰绰有余。
      final maxSide = math.max(img.width, img.height);
      if (maxSide > 2048) {
        final k = 2048 / maxSide;
        // 注意 clamp 返回 num，必须 toInt() 才能传给 int? 参数
        final w = (img.width * k).round().clamp(1, 100000).toInt();
        final h = (img.height * k).round().clamp(1, 100000).toInt();
        img.dispose();
        img = await _decodeOnce(bytes, targetWidth: w, targetHeight: h);
      }

      if (!mounted) {
        img.dispose();
        return;
      }
      setState(() => _image = img);
    } catch (e) {
      debugPrint('[ImageCropper] 解码失败: $e');
      if (mounted) setState(() => _error = '图片读取失败，请换一张试试');
    }
  }

  /// 把取景框内容渲染成 PNG。
  ///
  /// 这里的画布变换顺序（平移 → 旋转 → 缩放 → 以图心绘制）
  /// 必须与 `CropSurface` 的 Transform 顺序一致，否则所见非所得。
  static Future<td.Uint8List> _renderCrop(
    ui.Image image,
    CropTransform t,
    int outputSize,
  ) async {
    final box = t.boxSize;
    if (box.width <= 0 || box.height <= 0) {
      throw StateError('取景框尺寸非法: $box');
    }
    // 输出像素尺寸：保持取景框比例，outputSize 视为长边
    final outW = box.width >= box.height ? outputSize.toDouble() : 0.0;
    final outH = box.height >= box.width ? outputSize.toDouble() : 0.0;
    final finalW = outW > 0 ? outW : (outputSize * box.width / box.height);
    final finalH = outH > 0 ? outH : (outputSize * box.height / box.width);
    // 屏幕像素 → 输出像素（两轴比例相同，因为比例一致）
    final k = finalW / box.width;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()
      ..filterQuality = FilterQuality.high
      ..isAntiAlias = true;

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, finalW, finalH));
    canvas.translate(finalW / 2 + t.offset.dx * k, finalH / 2 + t.offset.dy * k);
    canvas.rotate(t.quarterTurns * math.pi / 2);
    canvas.scale(t.scale * k);

    final w = image.width.toDouble();
    final h = image.height.toDouble();
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, w, h),
      Rect.fromLTWH(-w / 2, -h / 2, w, h),
      paint,
    );
    canvas.restore();

    final picture = recorder.endRecording();
    final outImage = await picture.toImage(finalW.round(), finalH.round());
    final data = await outImage.toByteData(format: ui.ImageByteFormat.png);
    outImage.dispose();
    picture.dispose();
    if (data == null) throw StateError('PNG 编码失败');
    return data.buffer.asUint8List();
  }

  Future<void> _confirm() async {
    final image = _image;
    if (image == null || _saving) return;
    setState(() => _saving = true);
    try {
      final bytes = await _renderCrop(image, _t, widget.outputSize);
      if (!mounted) return;
      final dir = await getApplicationDocumentsDirectory();
      final target = Directory('${dir.path}/${widget.folder}');
      if (!await target.exists()) await target.create(recursive: true);
      final dest = '${target.path}/${widget.folder}_${const Uuid().v4()}.png';
      await File(dest).writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      Navigator.of(context).pop(dest);
    } catch (e) {
      debugPrint('[ImageCropper] 裁剪保存失败: $e');
      if (!mounted) return;
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('裁剪失败，请重试')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final err = _error;
    final image = _image;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('裁剪图片'),
      ),
      body: err != null
          ? Center(
              child: Text(err,
                  style: const TextStyle(color: Colors.white70)),
            )
          : image == null
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    Expanded(
                      child: CropSurface(
                        image: image,
                        aspectRatio: widget.aspectRatio,
                        allowRotate: widget.allowRotate,
                        onChanged: (t) => _t = t,
                      ),
                    ),
                    SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        child: Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  side: const BorderSide(color: Colors.white38),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 14),
                                ),
                                onPressed: _saving
                                    ? null
                                    : () => Navigator.of(context).pop(),
                                child: const Text('取消'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton(
                                style: FilledButton.styleFrom(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 14),
                                ),
                                onPressed: _saving ? null : _confirm,
                                child: _saving
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2),
                                      )
                                    : const Text('完成'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}

/// 裁剪交互区：一个取景框，图片可缩放 / 拖动 / 旋转。
///
/// 状态唯一持有者：`_turns` 只在这里，父组件通过 [onChanged] 拿到快照。
class CropSurface extends StatefulWidget {
  final ui.Image image;

  /// 取景框宽高比。1.0 为正方形（头像）；背景图可传 16/9。
  final double aspectRatio;

  /// 是否显示旋转按钮。
  final bool allowRotate;

  final ValueChanged<CropTransform> onChanged;

  const CropSurface({
    super.key,
    required this.image,
    required this.aspectRatio,
    required this.allowRotate,
    required this.onChanged,
  });

  @override
  State<CropSurface> createState() => _CropSurfaceState();
}

class _CropSurfaceState extends State<CropSurface> {
  double _minScale = 1;
  double _scale = 1;
  Offset _offset = Offset.zero;
  int _turns = 0;

  /// 取景框尺寸（屏幕像素）。由可用空间按 aspectRatio 推出。
  Size _box = Size.zero;

  // 手势开始时的快照，用于算焦点稳定的缩放
  double _startScale = 1;
  Offset _startOffset = Offset.zero;

  Size get _disp => CropGeometry.effectiveSize(
      widget.image.width, widget.image.height, _turns);

  void _syncConstraints() {
    _minScale = CropGeometry.coverScaleForBox(_disp, _box);
    _scale = CropGeometry.clampScale(_scale, _minScale);
    _offset = CropGeometry.clampOffsetForBox(_offset, _disp, _box, _scale);
  }

  void _emit() {
    widget.onChanged(CropTransform(
      scale: _scale,
      offset: _offset,
      quarterTurns: _turns,
      boxSize: _box,
    ));
  }

  void _onScaleStart(ScaleStartDetails d) {
    _startScale = _scale;
    _startOffset = _offset;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (_box.width <= 0 || _box.height <= 0) return;
    final focal = d.localFocalPoint - Offset(_box.width / 2, _box.height / 2);
    setState(() {
      if (d.pointerCount >= 2) {
        final next = CropGeometry.clampScale(_startScale * d.scale, _minScale);
        _offset = CropGeometry.offsetForScale(
          focal: focal,
          startScale: _startScale,
          startOffset: _startOffset,
          newScale: next,
        );
        _scale = next;
      } else {
        // 单指拖动；focalPointDelta 已是相对本控件的位移
        _offset = _offset + d.focalPointDelta;
      }
      _offset = CropGeometry.clampOffsetForBox(_offset, _disp, _box, _scale);
    });
    _emit();
  }

  void _rotate() {
    setState(() {
      _turns = (_turns + 1) % 4;
      _syncConstraints();
    });
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 由可用空间按 aspectRatio 推出取景框尺寸：
        // 宽幅（aspectRatio > 1）先吃满宽度，竖幅反之，正方形取较小边。
        final availW = constraints.maxWidth;
        final availH = constraints.maxHeight;
        final ar = widget.aspectRatio > 0 ? widget.aspectRatio : 1.0;
        var boxW = availW;
        var boxH = boxW / ar;
        if (boxH > availH) {
          boxH = availH;
          boxW = boxH * ar;
        }
        if (boxW > 0 && boxH > 0 &&
            ((boxW - _box.width).abs() > 0.5 ||
                (boxH - _box.height).abs() > 0.5)) {
          // 取景框变化（首帧 / 转屏）时重算约束。
          // 这里只改字段不做 setState：本轮 build 正在计算，用新值渲染即可。
          _box = Size(boxW, boxH);
          _syncConstraints();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _emit();
          });
        }
        // 渲染始终按「图像原始尺寸」摆放，旋转交给外层 Transform。
        // 若这里改用旋转后的尺寸，会与 _renderCrop 的画布变换对不上。
        final w = widget.image.width.toDouble();
        final h = widget.image.height.toDouble();
        final box = _box.width > 0 ? _box : Size(boxW, boxH);

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '双指缩放 · 单指拖动',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6), fontSize: 12),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: box.width,
              height: box.height,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onScaleStart: _onScaleStart,
                onScaleUpdate: _onScaleUpdate,
                child: ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.center,
                    minWidth: w,
                    maxWidth: w,
                    minHeight: h,
                    maxHeight: h,
                    child: Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()
                        // 用 translate 而非已弃用的 translateByDouble：
                        // 后者在仓库里没有先例，无法确认当前 SDK 一定提供。
                        ..translate(_offset.dx, _offset.dy)
                        ..rotateZ(_turns * math.pi / 2)
                        ..scale(_scale),
                      // RawImage 直接吃 ui.Image。Image widget 只接受 ImageProvider，
                      // 传 ui.Image 会报 argument_type_not_assignable。
                      child: RawImage(
                        image: widget.image,
                        fit: BoxFit.fill,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (widget.allowRotate) ...[
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: _rotate,
                icon: const Icon(Icons.rotate_right, size: 18),
                label: const Text('旋转 90°'),
                style: TextButton.styleFrom(foregroundColor: Colors.white),
              ),
            ],
          ],
        );
      },
    );
  }
}
