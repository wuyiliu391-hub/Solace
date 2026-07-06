import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../models/app_item.dart';
import '../../../utils/squircle_clipper.dart';
import '../../../utils/ios_typography.dart';
import '../../../services/custom_icon_service.dart';
import '../data/default_apps.dart';

/// iOS 风格的 squircle 图标组件
///
/// 支持两种图标渲染：
/// - A 方案：Remix Icon 专业矢量图标（默认）
/// - B 方案：用户自定义相册照片（优先级更高）
///
/// 长按弹出操作菜单：更换自定义图标 / 恢复默认图标
class AppIconWidget extends StatefulWidget {
  final AppItem item;
  final double size;
  final double labelFontSize;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool isEditMode;
  final int badgeCount;

  const AppIconWidget({
    super.key,
    required this.item,
    required this.size,
    this.labelFontSize = 11,
    this.onTap,
    this.onLongPress,
    this.isEditMode = false,
    this.badgeCount = 0,
  });

  @override
  State<AppIconWidget> createState() => _AppIconWidgetState();
}

class _AppIconWidgetState extends State<AppIconWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _tapController;
  late Animation<double> _scaleAnimation;

  /// 自定义图标路径（null 表示使用默认矢量图标）
  String? _customIconPath;

  @override
  void initState() {
    super.initState();
    _tapController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _scaleAnimation = Tween(begin: 1.0, end: 0.92).animate(
      CurvedAnimation(parent: _tapController, curve: Curves.easeOutCubic),
    );
    _loadCustomIcon();
  }

  @override
  void didUpdateWidget(AppIconWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id) {
      _loadCustomIcon();
    }
  }

  void _loadCustomIcon() {
    final path = CustomIconService.getCustomIconPath(widget.item.id);
    if (path != null && File(path).existsSync()) {
      setState(() {
        _customIconPath = path;
      });
    } else {
      setState(() {
        _customIconPath = null;
      });
    }
  }

  @override
  void dispose() {
    _tapController.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails _) {
    _tapController.forward();
  }

  void _onTapUp(TapUpDetails _) {
    _tapController.reverse();
  }

  void _onTapCancel() {
    _tapController.reverse();
  }

  /// 长按弹出操作菜单
  void _showIconMenu() {
    HapticFeedback.mediumImpact();

    final cs = Theme.of(context).colorScheme;
    final hasCustom = _customIconPath != null;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: cs.onSurfaceVariant.withOpacity(0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            // 图标预览
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: cs.shadow.withOpacity(0.1),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: _buildIconContent(64),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              widget.item.name,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 20),
            // 更换自定义图标
            _buildMenuTile(
              icon: Icons.photo_library_rounded,
              label: '更换自定义图标',
              description: '从相册选择照片作为图标',
              color: cs.primary,
              onTap: () async {
                Navigator.pop(ctx);
                await _pickCustomIcon();
              },
            ),
            // 恢复默认图标
            if (hasCustom)
              _buildMenuTile(
                icon: Icons.restore_rounded,
                label: '恢复默认图标',
                description: '切回 Remix 专业矢量图标',
                color: const Color(0xFFFF9800),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _restoreDefault();
                },
              ),
            SizedBox(height: MediaQuery.of(ctx).viewInsets.bottom + 20),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuTile({
    required IconData icon,
    required String label,
    required String description,
    required Color color,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, size: 22, color: color),
      ),
      title: Text(
        label,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: cs.onSurface,
        ),
      ),
      subtitle: Text(
        description,
        style: TextStyle(
          fontSize: 12,
          color: cs.onSurfaceVariant.withOpacity(0.6),
        ),
      ),
      onTap: onTap,
    );
  }

  /// 选择并设置自定义图标
  Future<void> _pickCustomIcon() async {
    final path = await CustomIconService.pickAndCropImage();
    if (path != null && mounted) {
      await CustomIconService.setCustomIcon(widget.item.id, path);
      setState(() => _customIconPath = path);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('自定义图标已设置'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    }
  }

  /// 恢复默认图标
  Future<void> _restoreDefault() async {
    await CustomIconService.restoreDefault(widget.item.id);
    setState(() => _customIconPath = null);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('已恢复默认图标'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  /// 构建图标内容（自定义图片 或 Remix 矢量图标）
  Widget _buildIconContent(double iconSize) {
    // 优先渲染用户自定义图片
    if (_customIconPath != null) {
      return Image.file(
        File(_customIconPath!),
        fit: BoxFit.cover,
        width: iconSize,
        height: iconSize,
        errorBuilder: (_, __, ___) => _buildDefaultIcon(iconSize),
      );
    }
    return _buildDefaultIcon(iconSize);
  }

  /// 构建默认 Remix 矢量图标
  Widget _buildDefaultIcon(double iconSize) {
    final iconData = DefaultApps.getIcon(widget.item.iconAsset);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(widget.item.accentColor),
            Color.lerp(Color(widget.item.accentColor), Colors.black, 0.2)!,
          ],
        ),
      ),
      child: Center(
        child: Icon(
          iconData,
          size: iconSize * 0.5,
          color: Colors.white,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final iconSize = widget.size;
    final radius = squircleRadius(iconSize);

    Widget iconWidget = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 图标 + 角标（Hero 包裹实现共享元素过渡）
        Stack(
          clipBehavior: Clip.none,
          children: [
            Hero(
              tag: 'app_icon_${widget.item.id}',
              flightShuttleBuilder: (flightContext, animation, direction,
                  fromContext, toContext) {
                return ScaleTransition(
                  scale: Tween(begin: 1.0, end: 0.6).animate(
                    CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
                  ),
                  child: Container(
                    width: iconSize,
                    height: iconSize,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(radius),
                    ),
                    child: ClipPath(
                      clipper: SquircleClipper(radius),
                      child: _buildIconContent(iconSize),
                    ),
                  ),
                );
              },
              child: Container(
                width: iconSize,
                height: iconSize,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(radius),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.25),
                      blurRadius: 8,
                      spreadRadius: -1,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: ClipPath(
                  clipper: SquircleClipper(radius),
                  child: widget.item.type == AppItemType.folder
                      ? _buildFolderPreview(widget.item, iconSize)
                      : _buildIconContent(iconSize),
                ),
              ),
            ),
            // 角标
            if (widget.badgeCount > 0)
              Positioned(
                top: -4,
                right: -4,
                child: _Badge(count: widget.badgeCount),
              ),
          ],
        ),
        const SizedBox(height: 6),
        // 标签
        SizedBox(
          width: iconSize + 16,
          child: Text(
            widget.item.name,
            style: IOSTypography.iconLabel(widget.labelFontSize),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );

    // 编辑模式抖动
    if (widget.isEditMode) {
      iconWidget = _WiggleWrapper(
        seed: widget.item.id.hashCode,
        child: iconWidget,
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.deferToChild,
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      onTap: widget.isEditMode
          ? null
          : () {
              HapticFeedback.lightImpact();
              widget.onTap?.call();
            },
      onLongPress: widget.isEditMode
          ? null
          : () {
              if (widget.onLongPress != null) {
                widget.onLongPress!.call();
              } else {
                _showIconMenu();
              }
            },
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: iconWidget,
      ),
    );
  }

  /// 文件夹内的 2×2 小图标预览
  Widget _buildFolderPreview(AppItem folder, double iconSize) {
    final children = folder.children ?? [];
    final previewSize = iconSize * 0.35;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accentColor,
            Color.lerp(accentColor, Colors.black, 0.2)!,
          ],
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(iconSize * 0.15),
        child: Wrap(
          spacing: 2,
          runSpacing: 2,
          alignment: WrapAlignment.center,
          children: children.take(4).map((child) {
            final childIcon = DefaultApps.getIcon(child.iconAsset);
            final childColor = Color(child.accentColor);
            return Container(
              width: previewSize,
              height: previewSize,
              decoration: BoxDecoration(
                color: childColor,
                borderRadius: BorderRadius.circular(previewSize * 0.22),
              ),
              child: Icon(childIcon, size: previewSize * 0.55, color: Colors.white),
            );
          }).toList(),
        ),
      ),
    );
  }

  Color get accentColor => Color(widget.item.accentColor);
}

/// 角标组件
class _Badge extends StatelessWidget {
  final int count;
  const _Badge({required this.count});

  @override
  Widget build(BuildContext context) {
    final display = count > 99 ? '99+' : '$count';
    final width = count > 9 ? 22.0 : 18.0;
    return Container(
      width: width,
      height: 18,
      decoration: BoxDecoration(
        color: Colors.red,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: Colors.black, width: 1.5),
      ),
      alignment: Alignment.center,
      child: Text(
        display,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          height: 1,
        ),
      ),
    );
  }
}

/// 编辑模式抖动动画包装器
class _WiggleWrapper extends StatefulWidget {
  final int seed;
  final Widget child;
  const _WiggleWrapper({required this.seed, required this.child});

  @override
  State<_WiggleWrapper> createState() => _WiggleWrapperState();
}

class _WiggleWrapperState extends State<_WiggleWrapper>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late double _phase;

  @override
  void initState() {
    super.initState();
    _phase = Random(widget.seed).nextDouble() * 0.5;
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 250 + Random(widget.seed).nextInt(150)),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final angle =
            sin((_controller.value + _phase) * pi * 2) * 0.035;
        return Transform.rotate(angle: angle, child: child);
      },
      child: widget.child,
    );
  }
}
