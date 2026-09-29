import 'package:flutter/material.dart';

/// 消息菜单的一项。页面只声明能力和行为，菜单外观与交互保持一致。
class MessageActionItem {
  final String label;
  final IconData icon;
  final Color? color;
  final String? subtitle;
  final VoidCallback onPressed;

  const MessageActionItem({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.color,
    this.subtitle,
  });
}

class MessageActionsSheet {
  const MessageActionsSheet._();

  static Future<void> show({
    required BuildContext context,
    required List<MessageActionItem> actions,
  }) async {
    if (actions.isEmpty) return;
    await showModalBottomSheet<void>(
      context: context,
      // 允许按内容/限高布局，避免小屏被系统默认 max height 裁切后仍不能滚
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        final media = MediaQuery.of(sheetContext);
        // 群聊最多约 9 项；小屏限高 70%，保证拖动条 + 列表可滚
        final maxListHeight = media.size.height * 0.70 - 28;
        return SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: media.size.height * 0.70,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  decoration: BoxDecoration(
                    color: Theme.of(sheetContext)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: .2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Flexible(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: 0,
                      maxHeight: maxListHeight > 0 ? maxListHeight : 200,
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: actions.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 0),
                      itemBuilder: (_, index) {
                        final action = actions[index];
                        return ListTile(
                          leading: Icon(action.icon, color: action.color),
                          title: Text(action.label),
                          subtitle: action.subtitle == null
                              ? null
                              : Text(action.subtitle!),
                          onTap: () {
                            Navigator.of(sheetContext).pop();
                            action.onPressed();
                          },
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }
}
