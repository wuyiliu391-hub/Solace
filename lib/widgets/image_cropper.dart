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

  /// 刚好铺满边长 [box] 正方形取景框所需的缩放（cover）。
  /// 图片不允许缩到比它更小，否则取景框会露白。
  static double coverScale(Size disp, double box) {
    if (disp.width <= 0 || disp.height <= 0 || box <= 0) return 1.0;
    return math.max(box / disp.width, box / disp.height);
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
      Offset offset, Size disp, double box, double scale) {
    if (box <= 0) return offset;
    final shownW = disp.width * scale;
    final shownH = disp.height * scale;
    final maxX = math.max(0.0, (shownW - box) / 2);
    final maxY = math.max(0.0, (shownH - box) / 2);
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
/// 返回裁剪后写入 `docs/avatars` 的文件路径；用户取消返回 null。
/// 输出是 [outputSize] × [outputSize] 的 PNG 正方形，正好对应项目里
/// 所有头像的圆形显示。
Future<String?> showImageCropper(
  BuildContext context,
  File file, {
  int outputSize = 512,
}) {
  return Navigator.of(context).push<String>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _CropperRoute(file: file, outputSize: outputSize),
    ),
  );
}

/// 裁剪页的当前变换状态（由交互区实时回传）。
class CropTransform {
  final double scale;
  final Offset offset;
  final int quarterTurns;
  final double box;

  const CropTransform({
    required this.scale,
    required this.offset,
    required this.quarterTurns,
    required this.box,
  });

  static const CropTransform initial =
      CropTransform(scale: 1, offset: Offset.zero, quarterTurns: 0, box: 0);
}

class _CropperRoute extends StatefulWidget {
  final File file;
  final int outputSize;
  const _CropperRoute({required this.file, required this.outputSize});

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

  /// 把取景框内容渲染成正方形 PNG。
  ///
  /// 这里的画布变换顺序（平移 → 旋转 → 缩放 → 以图心绘制）
  /// 必须与 `CropSurface` 的 Transform 顺序一致，否则所见非所得。
  static Future<td.Uint8List> _renderCrop(
    ui.Image image,
    CropTransform t,
    int outputSize,
  ) async {
    final out = outputSize.toDouble();
    if (t.box <= 0) throw StateError('取景框尺寸非法: ${t.box}');
    // 屏幕像素 → 输出像素
    final k = out / t.box;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()
      ..filterQuality = FilterQuality.high
      ..isAntiAlias = true;

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, out, out));
    canvas.translate(out / 2 + t.offset.dx * k, out / 2 + t.offset.dy * k);
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
    final outImage = await picture.toImage(outputSize, outputSize);
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
      final avatars = Directory('${dir.path}/avatars');
      if (!await avatars.exists()) await avatars.create(recursive: true);
      final dest = '${avatars.path}/avatar_${const Uuid().v4()}.png';
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

/// 裁剪交互区：一个正方形取景框，图片可缩放 / 拖动 / 旋转。
///
/// 状态唯一持有者：`_turns` 只在这里，父组件通过 [onChanged] 拿到快照。
class CropSurface extends StatefulWidget {
  final ui.Image image;
  final ValueChanged<CropTransform> onChanged;

  const CropSurface({super.key, required this.image, required this.onChanged});

  @override
  State<CropSurface> createState() => _CropSurfaceState();
}

class _CropSurfaceState extends State<CropSurface> {
  double _minScale = 1;
  double _scale = 1;
  Offset _offset = Offset.zero;
  int _turns = 0;
  double _box = 0;

  // 手势开始时的快照，用于算焦点稳定的缩放
  double _startScale = 1;
  Offset _startOffset = Offset.zero;

  Size get _disp => CropGeometry.effectiveSize(
      widget.image.width, widget.image.height, _turns);

  void _syncConstraints() {
    _minScale = CropGeometry.coverScale(_disp, _box);
    _scale = CropGeometry.clampScale(_scale, _minScale);
    _offset = CropGeometry.clampOffset(_offset, _disp, _box, _scale);
  }

  void _emit() {
    widget.onChanged(CropTransform(
      scale: _scale,
      offset: _offset,
      quarterTurns: _turns,
      box: _box,
    ));
  }

  void _onScaleStart(ScaleStartDetails d) {
    _startScale = _scale;
    _startOffset = _offset;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (_box <= 0) return;
    final focal = d.localFocalPoint - Offset(_box / 2, _box / 2);
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
      _offset = CropGeometry.clampOffset(_offset, _disp, _box, _scale);
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
        final side = math.min(constraints.maxWidth, constraints.maxHeight);
        if (side > 0 && (side - _box).abs() > 0.5) {
          // 取景框边长变化（首帧 / 转屏）时重算约束。
          // 这里只改字段不做 setState：本轮 build 正在计算，用新值渲染即可。
          _box = side;
          _syncConstraints();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _emit();
          });
        }
        final box = _box <= 0 ? side : _box;
        // 渲染始终按「图像原始尺寸」摆放，旋转交给外层 Transform。
        // 若这里改用旋转后的尺寸，会与 _renderCrop 的画布变换对不上。
        final w = widget.image.width.toDouble();
        final h = widget.image.height.toDouble();

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
              width: box,
              height: box,
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
                      // 不用 isAntiAlias / filterQuality：这两个参数在仓库里没有先例，
                      // 无法确认当前 SDK 一定提供；平滑交给 filterQuality 默认值。
                      child: RawImage(
                        image: widget.image,
                        fit: BoxFit.fill,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: _rotate,
              icon: const Icon(Icons.rotate_right, size: 18),
              label: const Text('旋转 90°'),
              style: TextButton.styleFrom(foregroundColor: Colors.white),
            ),
          ],
        );
      },
    );
  }
}
