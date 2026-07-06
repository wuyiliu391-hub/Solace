// 【对标来源：SillyTavern-1.18.0 — chats.js 消息操作】
// 1:1 转译自 SillyTavern 消息操作按钮和上下文菜单
// 参考文件：public/scripts/chats.js (hide/unhide/copy/edit/delete)

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/chat_message.dart';

/// 消息操作结果
enum MessageAction {
  edit,
  copy,
  delete,
  hide,
  unhide,
  bookmark,
  unbookmark,
  regenerate,
  branch,
  moveUp,
  moveDown,
}

/// 消息操作栏组件（对标 SillyTavern .mes_buttons）
/// 提供编辑/复制/隐藏/删除/收藏等操作
class MessageActions extends StatelessWidget {
  /// 消息数据
  final ChatMessage message;

  /// 是否用户消息
  final bool isUser;

  /// 操作回调
  final void Function(MessageAction action)? onAction;

  /// 编辑回调（独立，用于编辑模式）
  final VoidCallback? onEdit;

  /// 删除回调
  final VoidCallback? onDelete;

  /// 复制回调
  final VoidCallback? onCopy;

  /// 隐藏/显示回调
  final VoidCallback? onToggleHide;

  /// 收藏回调
  final VoidCallback? onToggleBookmark;

  /// 重新生成回调（仅 AI 消息）
  final VoidCallback? onRegenerate;

  const MessageActions({
    super.key,
    required this.message,
    this.isUser = false,
    this.onAction,
    this.onEdit,
    this.onDelete,
    this.onCopy,
    this.onToggleHide,
    this.onToggleBookmark,
    this.onRegenerate,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 生成时间（对标 .mes_timer）
        if (message.generationTime != null)
          Text(
            '${(message.generationTime! / 1000).toStringAsFixed(1)}s',
            style: TextStyle(fontSize: 10, color: Colors.grey[400]),
          ),

        // Token 计数（对标 .tokenCounterDisplay）
        if (message.tokenCount != null) ...[
          const SizedBox(width: 8),
          Text(
            '${message.tokenCount} tokens',
            style: TextStyle(fontSize: 10, color: Colors.grey[400]),
          ),
        ],

        const Spacer(),

        // 收藏按钮（对标 .mes_bookmark）
        if (onToggleBookmark != null)
          GestureDetector(
            onTap: onToggleBookmark,
            child: Icon(
              message.isBookmark ? Icons.flag : Icons.outlined_flag,
              size: 14,
              color: message.isBookmark ? Colors.amber : Colors.grey[400],
            ),
          ),

        // 更多操作按钮（对标 .extraMesButtonsHint）
        if (onAction != null) ...[
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => _showActionMenu(context),
            child: Icon(Icons.more_horiz, size: 14, color: Colors.grey[400]),
          ),
        ],

        // 编辑按钮（对标 .mes_edit）
        if (onEdit != null) ...[
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onEdit,
            child: Icon(Icons.edit, size: 14, color: Colors.grey[400]),
          ),
        ],
      ],
    );
  }

  /// 显示操作菜单（对标 SillyTavern .extraMesButtons）
  void _showActionMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 复制（对标 .mes_copy）
          if (onCopy != null || onAction != null)
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('复制'),
              onTap: () {
                Navigator.pop(context);
                if (onCopy != null) {
                  onCopy!();
                } else {
                  onAction?.call(MessageAction.copy);
                }
                // 复制到剪贴板
                Clipboard.setData(ClipboardData(text: message.content));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已复制到剪贴板'), duration: Duration(seconds: 1)),
                );
              },
            ),

          // 编辑（对标 .mes_edit）
          if (onEdit != null || onAction != null)
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('编辑'),
              onTap: () {
                Navigator.pop(context);
                if (onEdit != null) {
                  onEdit!();
                } else {
                  onAction?.call(MessageAction.edit);
                }
              },
            ),

          // 隐藏/显示（对标 .mes_hide / .mes_unhide）
          if (onToggleHide != null || onAction != null)
            ListTile(
              leading: Icon(message.isHidden ? Icons.visibility : Icons.visibility_off),
              title: Text(message.isHidden ? '显示' : '隐藏'),
              onTap: () {
                Navigator.pop(context);
                if (onToggleHide != null) {
                  onToggleHide!();
                } else {
                  onAction?.call(message.isHidden ? MessageAction.unhide : MessageAction.hide);
                }
              },
            ),

          // 收藏（对标 .mes_bookmark）
          if (onToggleBookmark != null || onAction != null)
            ListTile(
              leading: Icon(message.isBookmark ? Icons.flag : Icons.outlined_flag),
              title: Text(message.isBookmark ? '取消收藏' : '收藏'),
              onTap: () {
                Navigator.pop(context);
                if (onToggleBookmark != null) {
                  onToggleBookmark!();
                } else {
                  onAction?.call(message.isBookmark ? MessageAction.unbookmark : MessageAction.bookmark);
                }
              },
            ),

          // 重新生成（仅 AI 消息）
          if (!isUser && (onRegenerate != null || onAction != null))
            ListTile(
              leading: const Icon(Icons.refresh),
              title: const Text('重新生成'),
              onTap: () {
                Navigator.pop(context);
                if (onRegenerate != null) {
                  onRegenerate!();
                } else {
                  onAction?.call(MessageAction.regenerate);
                }
              },
            ),

          // 删除（对标 .mes_edit_delete）
          if (onDelete != null || onAction != null)
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('删除', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _showDeleteConfirm(context);
              },
            ),
        ],
      ),
    );
  }

  /// 显示删除确认弹窗（对标 SillyTavern confirmDialog）
  void _showDeleteConfirm(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: const Text('确定要删除这条消息吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              if (onDelete != null) {
                onDelete!();
              } else {
                onAction?.call(MessageAction.delete);
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}
