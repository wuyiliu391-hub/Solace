import 'package:flutter/material.dart';

import '../config/app_colors.dart';

/// 微信式消息长按菜单。
///
/// 横向排列（图标在上、标签在下），浅色白底 / 深色 #2C2C2C，圆角 8，
/// 通过 [show] 锚定在长按位置上方弹出（WeChat 原生交互位置）。
/// 项过多时横向可滚动。
class WeChatMessageMenu {
  const WeChatMessageMenu._();

  static Future<void> show({
    required BuildContext context,
    required List<WeChatMenuItem> items,
    Offset? anchor,
  }) async {
    if (items.isEmpty) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screen = MediaQuery.of(context).size;
    final navigator = Navigator.of(context);

    final x = anchor == null ? screen.width / 2 : anchor.dx.clamp(24.0, screen.width - 24.0);
    // 菜单尽量出现在长按点上方（估算菜单高 ~76）
    final y = anchor == null
        ? screen.height / 2
        : (anchor.dy - 88).clamp(48.0, screen.height - 120);

    await showMenu<void>(
      context: context,
      position: RelativeRect.fromSize(
        Rect.fromLTWH(x, y, 1, 1),
        screen,
      ),
      color: isDark ? WeChatColors.darkCard : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      elevation: 4,
      items: [
        PopupMenuItem<void>(
          padding: EdgeInsets.zero,
          height: 0,
          onTap: null,
          enabled: false,
          child: SizedBox(
            height: 74,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final item in items)
                    _WeChatMenuItemButton(
                      item: item,
                      isDark: isDark,
                      onTap: () {
                        navigator.pop();
                        item.onPressed();
                      },
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class WeChatMenuItem {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  const WeChatMenuItem({
    required this.label,
    required this.icon,
    required this.onPressed,
  });
}

class _WeChatMenuItemButton extends StatelessWidget {
  final WeChatMenuItem item;
  final bool isDark;
  final VoidCallback onTap;

  const _WeChatMenuItemButton({
    required this.item,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = isDark
        ? WeChatColors.darkTextPrimary
        : WeChatColors.textPrimary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(item.icon, size: 22, color: fg),
            const SizedBox(height: 5),
            Text(
              item.label,
              style: TextStyle(fontSize: 11.5, color: fg),
            ),
          ],
        ),
      ),
    );
  }
}
