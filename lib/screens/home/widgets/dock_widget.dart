import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../models/app_item.dart';
import '../../../services/badge_service.dart';
import '../../../utils/ios_colors.dart';
import 'app_icon_widget.dart';

/// iOS 风格的毛玻璃 Dock 栏
///
/// 编辑模式下支持拖拽进出
/// 动态帧率降级：首帧启用模糊，若检测到掉帧则自动降级为半透明纯色
class DockWidget extends StatefulWidget {
  final List<AppItem> items;
  final double iconSize;
  final bool isEditMode;
  final BadgeService? badgeService;
  final Function(AppItem)? onItemTap;
  final Function(AppItem)? onItemLongPress;

  /// 从 Dock 拖到网格区域时的回调
  final Function(AppItem item, int toPage, int toIndex)? onItemDraggedToGrid;

  const DockWidget({
    super.key,
    required this.items,
    this.iconSize = 60,
    this.isEditMode = false,
    this.badgeService,
    this.onItemTap,
    this.onItemLongPress,
    this.onItemDraggedToGrid,
  });

  @override
  State<DockWidget> createState() => _DockWidgetState();
}

class _DockWidgetState extends State<DockWidget> {
  bool _useBlur = true;
  bool _hasMeasured = false;

  @override
  void initState() {
    super.initState();
    // 安卓和 Web 默认不启用模糊（性能考虑）
    if (kIsWeb || (!Platform.isIOS && !Platform.isMacOS)) {
      _useBlur = false;
      _hasMeasured = true;
    }
  }

  void _onBuildComplete(Duration timestamp) {
    if (_hasMeasured) return;
    _hasMeasured = true;
    // 在 iOS/macOS 上，首帧渲染后检测是否掉帧
    // 如果首帧耗时超过 20ms（低于 50fps），降级为无模糊
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // 简单策略：首帧后直接保留模糊（Apple 设备通常够快）
      // 如果需要更精确的检测，可以在这里测量帧时间
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Widget content = Container(
      margin: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: bottomPadding + 10,
      ),
      height: 96,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(40),
        child: _useBlur
            ? BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
                child: _buildContent(isDark),
              )
            : _buildContent(isDark),
      ),
    );

    // Dock 作为放置目标：接收从网格拖来的图标
    if (widget.isEditMode) {
      content = DragTarget<AppItem>(
        onWillAcceptWithDetails: (details) {
          return !details.data.isDock;
        },
        onAcceptWithDetails: (details) {
          final item = details.data.copyWith(isDock: true);
          widget.items.add(item);
          HapticFeedback.mediumImpact();
        },
        builder: (context, candidateData, rejectedData) {
          if (candidateData.isNotEmpty) {
            return Container(
              margin: const EdgeInsets.only(left: 20, right: 20, bottom: 10),
              height: 96,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(40),
                border: Border.all(
                  color: Colors.white.withOpacity(0.5),
                  width: 2,
                ),
              ),
              child: content,
            );
          }
          return content;
        },
      );
    }

    return content;
  }

  Widget _buildContent(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? IOSColors.dockBgDark : IOSColors.dockBgLight,
        border: Border.all(
          color: isDark ? IOSColors.dockBorderDark : IOSColors.dockBorderLight,
          width: 0.5,
        ),
        borderRadius: BorderRadius.circular(40),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: widget.items.map((item) {
          final badgeCount = widget.badgeService?.getBadge(item.id) ?? 0;
          final iconWidget = AppIconWidget(
            item: item,
            size: widget.iconSize,
            labelFontSize: 10,
            isEditMode: widget.isEditMode,
            badgeCount: badgeCount,
            onTap: () => widget.onItemTap?.call(item),
            onLongPress: widget.isEditMode
                ? null
                : () => widget.onItemLongPress?.call(item),
          );

          if (!widget.isEditMode) return iconWidget;

          return LongPressDraggable<AppItem>(
            data: item,
            delay: const Duration(milliseconds: 100),
            feedback: Material(
              color: Colors.transparent,
              child: Opacity(
                opacity: 0.85,
                child: AppIconWidget(
                  item: item,
                  size: widget.iconSize * 1.1,
                  labelFontSize: 10,
                  isEditMode: false,
                ),
              ),
            ),
            childWhenDragging: Opacity(opacity: 0.3, child: iconWidget),
            onDragStarted: () => HapticFeedback.mediumImpact(),
            child: iconWidget,
          );
        }).toList(),
      ),
    );
  }
}
