// 【对标来源：SillyTavern-1.18.0 — backgrounds.js 背景图管理】
// 1:1 转译自 SillyTavern 背景图管理逻辑
// 参考文件：public/scripts/backgrounds.js

import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';

/// 背景图管理组件（对标 SillyTavern backgrounds.js）
/// 提供聊天背景图的选择、显示和管理功能
class BackgroundManager extends StatelessWidget {
  /// 背景图路径（本地文件路径或 null 表示使用默认背景）
  final String? backgroundPath;

  /// 背景图透明度
  final double opacity;

  /// 背景模糊程度
  final double blurSigma;

  /// 子组件
  final Widget child;

  /// 背景颜色（当无背景图时使用）
  final Color? fallbackColor;

  /// 是否启用暗色遮罩
  final bool enableDarkOverlay;

  /// 暗色遮罩透明度
  final double darkOverlayOpacity;

  const BackgroundManager({
    super.key,
    this.backgroundPath,
    this.opacity = 1.0,
    this.blurSigma = 0.0,
    required this.child,
    this.fallbackColor,
    this.enableDarkOverlay = false,
    this.darkOverlayOpacity = 0.3,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // 背景颜色层
        if (fallbackColor != null)
          Container(color: fallbackColor),

        // 背景图层
        if (backgroundPath != null && backgroundPath!.isNotEmpty)
          _buildBackgroundImage(),

        // 暗色遮罩层
        if (enableDarkOverlay && backgroundPath != null)
          Container(
            color: Colors.black.withOpacity(darkOverlayOpacity),
          ),

        // 子组件
        child,
      ],
    );
  }

  Widget _buildBackgroundImage() {
    // 检查是本地文件还是资源文件
    final isFile = backgroundPath!.startsWith('/') ||
        backgroundPath!.startsWith('file://') ||
        backgroundPath!.contains('\\');

    Widget imageWidget;

    if (isFile) {
      final filePath = backgroundPath!.replaceFirst('file://', '');
      final file = File(filePath);
      if (!file.existsSync()) {
        return const SizedBox.shrink();
      }
      imageWidget = Image.file(
        file,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
      );
    } else {
      // 假设是 assets 路径
      imageWidget = Image.asset(
        backgroundPath!,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
      );
    }

    // 应用透明度和模糊效果
    return Opacity(
      opacity: opacity.clamp(0.0, 1.0),
      child: blurSigma > 0
          ? ImageFiltered(
              imageFilter: ImageFilter.blur(
                sigmaX: blurSigma,
                sigmaY: blurSigma,
              ),
              child: imageWidget,
            )
          : imageWidget,
    );
  }
}

/// 背景选择器（对标 SillyTavern 背景选择功能）
class BackgroundPicker extends StatelessWidget {
  /// 当前背景路径
  final String? currentPath;

  /// 可用背景列表（assets 路径）
  final List<String> availableBackgrounds;

  /// 背景选择回调
  final ValueChanged<String?>? onBackgroundSelected;

  /// 自定义背景选择回调
  final VoidCallback? onPickCustom;

  const BackgroundPicker({
    super.key,
    this.currentPath,
    this.availableBackgrounds = const [],
    this.onBackgroundSelected,
    this.onPickCustom,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 标题
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Text(
                '聊天背景',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              const Spacer(),
              if (onPickCustom != null)
                TextButton.icon(
                  onPressed: onPickCustom,
                  icon: const Icon(Icons.add_photo_alternate, size: 18),
                  label: const Text('自定义'),
                ),
            ],
          ),
        ),

        // 背景网格
        SizedBox(
          height: 120,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              // 无背景选项
              _buildBackgroundItem(
                context,
                path: null,
                label: '默认',
                icon: Icons.format_color_reset,
                isSelected: currentPath == null,
                onTap: () => onBackgroundSelected?.call(null),
              ),

              // 可用背景
              ...availableBackgrounds.map((path) {
                return _buildBackgroundItem(
                  context,
                  path: path,
                  isSelected: currentPath == path,
                  onTap: () => onBackgroundSelected?.call(path),
                );
              }),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBackgroundItem(
    BuildContext context, {
    required String? path,
    String? label,
    IconData? icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 80,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? colorScheme.primary : Colors.grey.withOpacity(0.3),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(7),
          child: path != null
              ? Stack(
                  fit: StackFit.expand,
                  children: [
                    // 背景预览图
                    path.startsWith('/')
                        ? Image.file(File(path), fit: BoxFit.cover)
                        : Image.asset(path, fit: BoxFit.cover),

                    // 选中指示器
                    if (isSelected)
                      Container(
                        color: colorScheme.primary.withOpacity(0.3),
                        child: Center(
                          child: Icon(
                            Icons.check_circle,
                            color: colorScheme.primary,
                            size: 24,
                          ),
                        ),
                      ),
                  ],
                )
              : Container(
                  color: colorScheme.surfaceContainerHighest,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        icon ?? Icons.image,
                        color: isSelected
                            ? colorScheme.primary
                            : colorScheme.onSurface.withOpacity(0.5),
                        size: 24,
                      ),
                      if (label != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 10,
                            color: isSelected
                                ? colorScheme.primary
                                : colorScheme.onSurface.withOpacity(0.5),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
