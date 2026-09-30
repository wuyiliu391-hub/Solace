import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/permission_service.dart';
import 'image_cropper.dart';

/// 背景图的两个朝向。
///
/// 手机上横竖屏的可见区域差别很大，一张图只存一个朝向必然有一边被裁得很惨，
/// 所以背景图按朝向分开存，各自独立裁剪。
enum BackgroundOrientation {
  portrait, // 竖屏
  landscape, // 横屏
  ;

  String get label => this == portrait ? '竖屏' : '横屏';

  /// 取景框比例。竖屏偏高，横屏偏宽。
  double get aspectRatio => this == portrait ? 9.0 / 16.0 : 16.0 / 9.0;

  /// 输出长边像素。
  int get outputSize => this == portrait ? 1440 : 1920;

  String get folder => 'backgrounds';
}

/// 底部弹窗的返回结果。用显式类型区分「清除」与「直接关闭弹窗」——
/// 都用 null 表示会导致点空白处关闭时误清背景。
class _BgPickResult {
  /// 非 null 表示要选图；null 且 [clear] 为 true 表示清除。
  final ImageSource? source;
  final bool clear;

  const _BgPickResult.pick(this.source) : clear = false;
  const _BgPickResult.clear()
      : source = null,
        clear = true;
  const _BgPickResult.dismiss()
      : source = null,
        clear = false;
}

/// 按「横屏 / 竖屏」分别设置背景图的入口。
///
/// 每个朝向独立选图 + 裁剪 + 持久化；[currentPortrait] / [currentLandscape]
/// 任一为空时，该朝向回退到另一个朝向的图（避免用户只设了一边时另一边空白）。
class BackgroundPicker extends StatelessWidget {
  /// 竖屏背景本地路径或 http 地址。
  final String? currentPortrait;

  /// 横屏背景本地路径或 http 地址。
  final String? currentLandscape;

  final void Function(BackgroundOrientation orientation, String? path)
      onChanged;

  /// 是否允许清除（清除走 onChanged(orientation, null)）。
  final bool allowClear;

  const BackgroundPicker({
    super.key,
    required this.currentPortrait,
    required this.currentLandscape,
    required this.onChanged,
    this.allowClear = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final o in BackgroundOrientation.values)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: _OrientationRow(
              orientation: o,
              path: _resolve(o),
              allowClear: allowClear,
              onTap: () => _pick(context, o),
            ),
          ),
      ],
    );
  }

  /// 某朝向实际生效的图：本朝向优先，另一朝向兜底。
  String? _resolve(BackgroundOrientation o) {
    final mine = o == BackgroundOrientation.portrait
        ? currentPortrait
        : currentLandscape;
    if (mine != null && mine.isNotEmpty) return mine;
    final other = o == BackgroundOrientation.portrait
        ? currentLandscape
        : currentPortrait;
    return (other != null && other.isNotEmpty) ? other : null;
  }

  Future<void> _pick(BuildContext context, BackgroundOrientation o) async {
    if (!await PermissionService.requestStoragePermission()) return;
    if (!context.mounted) return;

    final result = await showModalBottomSheet<_BgPickResult>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text('设置${o.label}背景',
                style: Theme.of(ctx).textTheme.titleMedium),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('从相册选择'),
              onTap: () =>
                  Navigator.pop(ctx, _BgPickResult.pick(ImageSource.gallery)),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('拍照'),
              onTap: () =>
                  Navigator.pop(ctx, _BgPickResult.pick(ImageSource.camera)),
            ),
            if (allowClear && _resolve(o) != null)
              ListTile(
                leading: Icon(Icons.delete_outline,
                    color: Theme.of(ctx).colorScheme.error),
                title: Text('清除${o.label}背景',
                    style: TextStyle(
                        color: Theme.of(ctx).colorScheme.error)),
                onTap: () => Navigator.pop(ctx, const _BgPickResult.clear()),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );

    // null = 用户直接关闭弹窗，什么都不做
    if (result == null) return;

    if (result.clear) {
      onChanged(o, null);
      return;
    }
    final source = result.source;
    if (source == null || !context.mounted) return;

    final picked = await ImagePicker().pickImage(
      source: source,
      // 背景图要覆盖整屏，给足分辨率；裁剪器会再按朝向比例出图。
      maxWidth: 2560,
      maxHeight: 2560,
      imageQuality: 90,
    );
    if (picked == null || !context.mounted) return;

    final cropped = await showImageCropper(
      context,
      File(picked.path),
      aspectRatio: o.aspectRatio,
      outputSize: o.outputSize,
      folder: o.folder,
      // 背景图通常不需要旋转，横向构图靠裁剪而不是转屏
      allowRotate: false,
    );
    if (cropped == null) return;
    onChanged(o, cropped);
  }
}

class _OrientationRow extends StatelessWidget {
  final BackgroundOrientation orientation;
  final String? path;
  final bool allowClear;
  final VoidCallback onTap;

  const _OrientationRow({
    required this.orientation,
    required this.path,
    required this.allowClear,
    required this.onTap,
  });

  bool get _isLocal =>
      path != null && path!.isNotEmpty && !path!.startsWith('http');

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Row(
          children: [
            // 缩略图按朝向给出不同宽高比，所见即所得
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 56,
                height: 56 / orientation.aspectRatio,
                child: path == null
                    ? ColoredBox(
                        color: cs.surfaceContainerHighest,
                        child: Icon(Icons.wallpaper_outlined,
                            color: cs.onSurfaceVariant),
                      )
                    : (_isLocal
                        ? Image.file(File(path!), fit: BoxFit.cover)
                        : Image.network(path!, fit: BoxFit.cover)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${orientation.label}背景',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    path == null ? '未设置' : '已设置，点击更换',
                    style: TextStyle(
                        fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            if (allowClear && path != null)
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                tooltip: '清除',
                onPressed: onTap,
              )
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}
