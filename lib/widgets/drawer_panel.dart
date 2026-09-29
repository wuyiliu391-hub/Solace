// 【对标来源：SillyTavern-1.18.0 — index.html 左/右抽屉面板】
// 1:1 转译自 SillyTavern 侧边抽屉面板结构
// 参考文件：public/index.html (#left-nav-panel, #right-nav-panel)

import 'package:flutter/material.dart';

/// 抽屉方向（对标 SillyTavern 左/右面板）
enum DrawerSide {
  left,
  right,
}

/// 抽屉面板组件（对标 SillyTavern #left-nav-panel / #right-nav-panel）
/// 提供可滑出的侧边面板，用于角色列表、设置等
class DrawerPanel extends StatelessWidget {
  /// 抽屉方向
  final DrawerSide side;

  /// 标题
  final String? title;

  /// 子组件
  final Widget child;

  /// 是否显示
  final bool isOpen;

  /// 关闭回调
  final VoidCallback? onClose;

  /// 宽度比例（相对于屏幕宽度）
  final double widthRatio;

  /// 背景颜色
  final Color? backgroundColor;

  const DrawerPanel({
    super.key,
    required this.side,
    this.title,
    required this.child,
    this.isOpen = false,
    this.onClose,
    this.widthRatio = 0.75,
    this.backgroundColor,
  });

  /// 显示左抽屉（对标 SillyTavern 左侧角色列表面板）
  static Future<T?> showLeft<T>({
    required BuildContext context,
    required Widget child,
    String? title,
    double widthRatio = 0.75,
    Color? backgroundColor,
  }) {
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Align(
          alignment: Alignment.centerLeft,
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: MediaQuery.of(context).size.width * widthRatio,
              height: double.infinity,
              decoration: BoxDecoration(
                color: backgroundColor ?? Theme.of(context).scaffoldBackgroundColor,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 8,
                    offset: const Offset(2, 0),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // 标题栏
                  if (title != null)
                    _buildHeader(context, title),

                  // 内容
                  Expanded(child: child),
                ],
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(-1, 0),
            end: Offset.zero,
          ).animate(CurvedAnimation(
            parent: animation,
            curve: Curves.easeOut,
          )),
          child: child,
        );
      },
    );
  }

  /// 显示右抽屉（对标 SillyTavern 右侧设置面板）
  static Future<T?> showRight<T>({
    required BuildContext context,
    required Widget child,
    String? title,
    double widthRatio = 0.75,
    Color? backgroundColor,
  }) {
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Align(
          alignment: Alignment.centerRight,
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: MediaQuery.of(context).size.width * widthRatio,
              height: double.infinity,
              decoration: BoxDecoration(
                color: backgroundColor ?? Theme.of(context).scaffoldBackgroundColor,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 8,
                    offset: const Offset(-2, 0),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // 标题栏
                  if (title != null)
                    _buildHeader(context, title),

                  // 内容
                  Expanded(child: child),
                ],
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(CurvedAnimation(
            parent: animation,
            curve: Curves.easeOut,
          )),
          child: child,
        );
      },
    );
  }

  static Widget _buildHeader(BuildContext context, String title) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor,
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 当作为内嵌组件使用时
    if (!isOpen) return const SizedBox.shrink();

    return Container(
      width: MediaQuery.of(context).size.width * widthRatio,
      decoration: BoxDecoration(
        color: backgroundColor ?? Theme.of(context).scaffoldBackgroundColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: Offset(side == DrawerSide.left ? 2 : -2, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          if (title != null)
            _buildHeader(context, title!),
          Expanded(child: child),
        ],
      ),
    );
  }
}
