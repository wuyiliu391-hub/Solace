import 'dart:io';
import 'package:flutter/material.dart';
import '../../models/group_chat_message.dart';

/// ST 风格群聊消息气泡：
/// AI = 左侧角色色（头像/名字/淡色气泡），用户 = 右对齐主色气泡（Solace 原样式）
class GroupMessageBubble extends StatelessWidget {
  final GroupChatMessage message;
  final bool showAvatar;
  final double screenWidth;
  final Color? speakerColor;

  const GroupMessageBubble({
    super.key,
    required this.message,
    required this.showAvatar,
    required this.screenWidth,
    this.speakerColor,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

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
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _contentBubble(cs, isMe: true),
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
            _avatar('我', cs.primaryContainer, cs.primary),
          ],
        ),
      );
    }

    // AI 消息：角色色
    final color = speakerColor ?? cs.tertiary;
    final bubbleBg = color.withValues(
      alpha: Theme.of(context).brightness == Brightness.dark ? 0.18 : 0.10,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showAvatar)
            _avatar(message.senderName, color, Colors.white)
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
                _contentBubble(cs, isMe: false, aiColor: color, bg: bubbleBg),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _contentBubble(
    ColorScheme cs, {
    required bool isMe,
    Color? aiColor,
    Color? bg,
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
      child: Text(
        message.content,
        style: TextStyle(
          fontSize: 15,
          color: isMe ? cs.onPrimary : cs.onSurface,
        ),
      ),
    );
  }

  Widget _avatar(String name, Color bg, Color fg) {
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
