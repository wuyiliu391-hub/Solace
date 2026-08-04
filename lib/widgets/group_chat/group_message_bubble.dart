import 'dart:io';
import 'package:flutter/material.dart';
import '../../models/group_chat_message.dart';
import '../../utils/avatar_resolver.dart';

/// ST 风格群聊消息气泡：
/// AI = 左侧角色色（头像/名字/淡色气泡），用户 = 右对齐主色气泡（Solace 原样式）
class GroupMessageBubble extends StatelessWidget {
  final GroupChatMessage message;
  final bool showAvatar;
  final double screenWidth;
  final Color? speakerColor;

  /// 发送者头像 URL（AI 角色用真实头像，null 回退首字圆）
  final String? avatarUrl;

  /// 长按回调（消息操作菜单）
  final VoidCallback? onLongPress;

  /// 多选模式点击回调（选中/取消选中）
  final VoidCallback? onTap;

  /// 多选模式下是否被选中（高亮背景）
  final bool isSelected;

  const GroupMessageBubble({
    super.key,
    required this.message,
    required this.showAvatar,
    required this.screenWidth,
    this.speakerColor,
    this.avatarUrl,
    this.onLongPress,
    this.onTap,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 系统消息：居中灰条（沿用现有）
    if (message.isSystem) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              message.content,
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            ),
          ),
        ),
      );
    }

    // 用户消息：右对齐主色气泡（沿用现有）
    if (message.isUser) {
      return _wrapSelected(
        context,
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _contentBubble(cs, isMe: true, isDark: isDark),
                  const SizedBox(height: 2),
                  Text(
                    _formatTime(message.timestamp),
                    style: TextStyle(
                      fontSize: 11,
                      color: cs.onSurface.withValues(alpha: 0.35),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _avatar('我', cs.primaryContainer, cs.primary,
                avatarUrl: avatarUrl),
          ],
        ),
        ),
      );
    }

    // AI 消息：角色色
    final color = speakerColor ?? cs.tertiary;
    final bubbleBg = color.withValues(
      alpha: Theme.of(context).brightness == Brightness.dark ? 0.18 : 0.10,
    );
    return _wrapSelected(
      context,
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showAvatar)
              _avatar(message.senderName, color, Colors.white,
                  avatarUrl: avatarUrl)
            else
              const SizedBox(width: 32),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.senderName,
                    style: TextStyle(
                      fontSize: 12,
                      color: color,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  _contentBubble(cs,
                      isMe: false, aiColor: color, bg: bubbleBg, isDark: isDark),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 多选模式下选中态高亮背景
  Widget _wrapSelected(BuildContext context, Widget child) {
    if (!isSelected) return child;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .primaryContainer
            .withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: child,
    );
  }

  Widget _contentBubble(
    ColorScheme cs, {
    required bool isMe,
    Color? aiColor,
    Color? bg,
    required bool isDark,
  }) {
    // 引用预览条：消息上方显示被引用消息的来源与摘要
    final replyTo = message.replyTo;
    // 已撤回：灰字占位，不显示原内容
    final recalled = message.isRecalled;
    final edited = message.metadata?['editedAt'] != null;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment:
            isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (replyTo != null)
            _replyPreview(cs, isMe: isMe, replyTo: replyTo, isDark: isDark),
          _bubbleBody(cs, isMe: isMe, bg: bg, recalled: recalled),
          if (message.isBookmarked || edited)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (message.isBookmarked)
                    Icon(Icons.star, size: 13, color: Colors.amber.shade600),
                  if (edited)
                    Icon(Icons.edit_outlined,
                        size: 12,
                        color: isMe
                            ? cs.onPrimary.withValues(alpha: 0.8)
                            : cs.onSurfaceVariant),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// 气泡主体（图片 / 文本）
  Widget _bubbleBody(
    ColorScheme cs, {
    required bool isMe,
    Color? bg,
    required bool recalled,
  }) {
    // 图片消息
    if (message.type == GroupChatMessageType.image) {
      final paths =
          (message.metadata?['imagePaths'] as List?)?.cast<String>() ??
              (message.content.isNotEmpty ? [message.content] : <String>[]);
      final first = paths.isNotEmpty ? paths.first : null;
      return Container(
        constraints: BoxConstraints(maxWidth: screenWidth * 0.6),
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: isMe ? cs.primary : (bg ?? cs.surfaceContainerHighest),
          borderRadius: BorderRadius.circular(16).copyWith(
            bottomRight: isMe ? const Radius.circular(4) : null,
            bottomLeft: isMe ? null : const Radius.circular(4),
          ),
        ),
        child: first != null && File(first).existsSync()
            ? ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(
                  File(first),
                  width: 160,
                  height: 160,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox(
                    width: 160,
                    height: 160,
                    child: Icon(Icons.broken_image),
                  ),
                ),
              )
            : const Padding(
                padding: EdgeInsets.all(12),
                child: Icon(Icons.broken_image),
              ),
      );
    }

    return Container(
      constraints: BoxConstraints(maxWidth: screenWidth * 0.7),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isMe ? cs.primary : (bg ?? cs.surfaceContainerHighest),
        borderRadius: BorderRadius.circular(16).copyWith(
          bottomRight: isMe ? const Radius.circular(4) : null,
          bottomLeft: isMe ? null : const Radius.circular(4),
        ),
      ),
      child: recalled
          ? Text(
              '已撤回',
              style: TextStyle(
                fontSize: 14,
                fontStyle: FontStyle.italic,
                color: isMe
                    ? cs.onPrimary.withValues(alpha: 0.7)
                    : cs.onSurfaceVariant,
              ),
            )
          : Text(
              message.content,
              style: TextStyle(
                fontSize: 15,
                color: isMe ? cs.onPrimary : cs.onSurface,
              ),
            ),
    );
  }

  /// 引用预览条（对齐单聊 _buildReplyPreview）
  Widget _replyPreview(
    ColorScheme cs, {
    required bool isMe,
    required Map<String, dynamic> replyTo,
    required bool isDark,
  }) {
    final senderName = replyTo['senderName'] as String? ?? '';
    final contentPreview = replyTo['contentPreview'] as String? ?? '';
    final previewBg = isMe
        ? Colors.white.withValues(alpha: 0.15)
        : (isDark
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.black.withValues(alpha: 0.05));
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: BoxDecoration(
        color: previewBg,
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(
            color: isMe ? Colors.white.withValues(alpha: 0.5) : cs.primary.withValues(alpha: 0.5),
            width: 3,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            senderName,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isMe ? cs.onPrimary.withValues(alpha: 0.85) : cs.primary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            contentPreview,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: isMe
                  ? cs.onPrimary.withValues(alpha: 0.7)
                  : cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatar(String name, Color bg, Color fg, {String? avatarUrl}) {
    // 真实头像图片优先（本地文件/asset/网络），失败回退首字圆
    final image = AvatarResolver.imageWidget(
      avatarUrl,
      width: 32,
      height: 32,
      fit: BoxFit.cover,
      onError: () => _avatarFallback(name, bg, fg),
    );
    if (image != null) {
      return ClipOval(
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(shape: BoxShape.circle, color: bg),
          child: image,
        ),
      );
    }
    return _avatarFallback(name, bg, fg);
  }

  Widget _avatarFallback(String name, Color bg, Color fg) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(shape: BoxShape.circle, color: bg),
      child: Center(
        child: Text(
          name.isNotEmpty ? name.substring(0, 1) : '?',
          style: TextStyle(
            color: fg,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(time.year, time.month, time.day);
    if (d == today) {
      return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    }
    return '${time.month}/${time.day} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}
