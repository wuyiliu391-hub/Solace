// 【对标来源：SillyTavern-1.18.0 — index.html:7377 #message_template 消息模板】
// 1:1 转译自 SillyTavern 消息气泡 DOM 结构为 Flutter Widget
// 参考文件：index.html:7377-7450 (#message_template)

import "package:flutter/material.dart";
import "../../models/chat_message.dart";

/// 消息气泡 V2（对标 SillyTavern #message_template）
/// 完整保留 SillyTavern 的消息布局：头像/名称/时间戳/内容/操作按钮
class MessageBubbleV2 extends StatelessWidget {
  /// 消息数据
  final ChatMessage message;

  /// 角色名称（对标 ch_name）
  final String characterName;

  /// 角色头像路径
  final String? avatarPath;

  /// 是否当前用户消息（对标 is_user）
  final bool isUser;

  /// 是否系统消息（对标 is_system）
  final bool isSystem;

  /// 是否幽灵消息（对标 is_ghost，对AI不可见）
  final bool isGhost;

  /// 是否已隐藏（对标 .mes_hide）
  final bool isHidden;

  /// 是否已收藏（对标 .mes_bookmark）
  final bool isBookmarked;

  /// 思考内容（对标 .mes_reasoning）
  final String? reasoning;

  /// 滑动历史（对标 swipe_history）
  final List<String> swipeHistory;

  /// 当前滑动索引（对标 swipe_index）
  final int swipeIndex;

  /// 生成时间毫秒（对标 .mes_timer）
  final int? generationTime;

  /// Token 计数（对标 .tokenCounterDisplay）
  final int? tokenCount;

  /// 编辑回调
  final VoidCallback? onEdit;

  /// 删除回调
  final VoidCallback? onDelete;

  /// 复制回调
  final VoidCallback? onCopy;

  /// 隐藏/显示回调
  final VoidCallback? onToggleHide;

  /// 收藏回调
  final VoidCallback? onToggleBookmark;

  /// 左滑回调（对标 .swipe_left）
  final VoidCallback? onSwipeLeft;

  /// 右滑回调
  final VoidCallback? onSwipeRight;

  /// 消息点击回调
  final VoidCallback? onTap;

  const MessageBubbleV2({
    super.key,
    required this.message,
    this.characterName = '',
    this.avatarPath,
    this.isUser = false,
    this.isSystem = false,
    this.isGhost = false,
    this.isHidden = false,
    this.isBookmarked = false,
    this.reasoning,
    this.swipeHistory = const [],
    this.swipeIndex = 0,
    this.generationTime,
    this.tokenCount,
    this.onEdit,
    this.onDelete,
    this.onCopy,
    this.onToggleHide,
    this.onToggleBookmark,
    this.onSwipeLeft,
    this.onSwipeRight,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // 系统消息特殊样式
    if (isSystem) {
      return _buildSystemMessage(context);
    }

    return GestureDetector(
      onTap: onTap,
      onLongPress: () => _showContextMenu(context),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment:
              isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            // AI 头像（对标 .mesAvatarWrapper）
            if (!isUser) _buildAvatar(),

            // 消息块（对标 .mes_block）
            Expanded(
              child: Column(
                crossAxisAlignment: isUser
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  // 名称行（对标 .ch_name）
                  _buildNameRow(context),

                  // 思考块（对标 .mes_reasoning_details）
                  if (reasoning != null && reasoning!.isNotEmpty)
                    _buildReasoningBlock(),

                  // 消息内容（对标 .mes_text）
                  _buildMessageContent(context),

                  // 消息操作栏
                  _buildActionBar(context),
                ],
              ),
            ),

            // 用户头像
            if (isUser) _buildAvatar(),
          ],
        ),
      ),
    );
  }

  /// 构建头像（对标 .mesAvatarWrapper .avatar img）
  Widget _buildAvatar() {
    return Container(
      width: 40,
      height: 40,
      margin: const EdgeInsets.only(right: 8, top: 4),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.grey[300],
        image: avatarPath != null
            ? DecorationImage(
                image: AssetImage(avatarPath!),
                fit: BoxFit.cover,
              )
            : null,
      ),
      child: avatarPath == null
          ? Icon(
              isUser ? Icons.person : Icons.smart_toy,
              color: Colors.grey[600],
            )
          : null,
    );
  }

  /// 构建名称行（对标 .ch_name flex-container）
  Widget _buildNameRow(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 名称文本（对标 .name_text）
          Text(
            isUser ? '你' : characterName,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isUser ? Colors.blue[700] : Colors.grey[700],
            ),
          ),

          // 幽灵标记（对标 .mes_ghost）
          if (isGhost) ...[
            const SizedBox(width: 4),
            Icon(Icons.visibility_off, size: 12, color: Colors.grey[400]),
          ],

          // 时间戳（对标 .timestamp）
          if (message.timestamp != null) ...[
            const SizedBox(width: 8),
            Text(
              _formatTimestamp(message.timestamp),
              style: TextStyle(fontSize: 10, color: Colors.grey[400]),
            ),
          ],
        ],
      ),
    );
  }

  /// 构建思考块（对标 .mes_reasoning_details）
  Widget _buildReasoningBlock() {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lightbulb_outline, size: 14, color: Colors.amber[700]),
              const SizedBox(width: 4),
              Text(
                '思考过程',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            reasoning!,
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  /// 构建消息内容（对标 .mes_text）
  Widget _buildMessageContent(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isUser ? Colors.blue[50] : Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
        border: isHidden
            ? Border.all(color: Colors.orange[300]!, style: BorderStyle.solid)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 隐藏标记
          if (isHidden)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.visibility_off,
                      size: 12, color: Colors.orange[400]),
                  const SizedBox(width: 4),
                  Text(
                    '已隐藏',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.orange[400],
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),

          // 消息文本
          Text(
            message.content,
            style: const TextStyle(fontSize: 14),
          ),

          // 滑动历史指示器
          if (swipeHistory.length > 1) _buildSwipeIndicator(),
        ],
      ),
    );
  }

  /// 构建滑动指示器（对标 .swipe_left / swipe_right）
  Widget _buildSwipeIndicator() {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (swipeIndex > 0)
            GestureDetector(
              onTap: onSwipeLeft,
              child: Icon(Icons.chevron_left,
                  size: 16, color: Colors.grey[400]),
            ),
          Text(
            '${swipeIndex + 1}/${swipeHistory.length}',
            style: TextStyle(fontSize: 10, color: Colors.grey[400]),
          ),
          if (swipeIndex < swipeHistory.length - 1)
            GestureDetector(
              onTap: onSwipeRight,
              child: Icon(Icons.chevron_right,
                  size: 16, color: Colors.grey[400]),
            ),
        ],
      ),
    );
  }

  /// 构建操作栏（对标 .mes_buttons）
  Widget _buildActionBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 生成时间（对标 .mes_timer）
          if (generationTime != null)
            Text(
              '${(generationTime! / 1000).toStringAsFixed(1)}s',
              style: TextStyle(fontSize: 10, color: Colors.grey[400]),
            ),

          // Token 计数（对标 .tokenCounterDisplay）
          if (tokenCount != null) ...[
            const SizedBox(width: 8),
            Text(
              '$tokenCount tokens',
              style: TextStyle(fontSize: 10, color: Colors.grey[400]),
            ),
          ],

          const Spacer(),

          // 收藏按钮（对标 .mes_bookmark）
          if (onToggleBookmark != null)
            GestureDetector(
              onTap: onToggleBookmark,
              child: Icon(
                isBookmarked ? Icons.flag : Icons.outlined_flag,
                size: 14,
                color: isBookmarked ? Colors.amber : Colors.grey[400],
              ),
            ),

          // 编辑按钮（对标 .mes_edit）
          if (onEdit != null) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onEdit,
              child: Icon(Icons.edit, size: 14, color: Colors.grey[400]),
            ),
          ],
        ],
      ),
    );
  }

  /// 构建系统消息
  Widget _buildSystemMessage(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            message.content,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
              fontStyle: FontStyle.italic,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  /// 显示上下文菜单（对标 .extraMesButtons）
  void _showContextMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onCopy != null)
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('复制'),
              onTap: () {
                Navigator.pop(context);
                onCopy?.call();
              },
            ),
          if (onEdit != null)
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('编辑'),
              onTap: () {
                Navigator.pop(context);
                onEdit?.call();
              },
            ),
          if (onToggleHide != null)
            ListTile(
              leading: Icon(isHidden ? Icons.visibility : Icons.visibility_off),
              title: Text(isHidden ? '显示' : '隐藏'),
              onTap: () {
                Navigator.pop(context);
                onToggleHide?.call();
              },
            ),
          if (onToggleBookmark != null)
            ListTile(
              leading: Icon(isBookmarked ? Icons.flag : Icons.outlined_flag),
              title: Text(isBookmarked ? '取消收藏' : '收藏'),
              onTap: () {
                Navigator.pop(context);
                onToggleBookmark?.call();
              },
            ),
          if (onDelete != null)
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('删除', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                onDelete?.call();
              },
            ),
        ],
      ),
    );
  }

  /// 格式化时间戳
  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final diff = now.difference(timestamp);

    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes}分钟前';
    if (diff.inDays < 1) return '${diff.inHours}小时前';
    return '${timestamp.month}/${timestamp.day} ${timestamp.hour}:${timestamp.minute.toString().padLeft(2, '0')}';
  }
}

