// 群聊详情页面（对标 ChatDetailScreen 简化版）
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../blocs/group_chat/group_chat_bloc.dart';
import '../../models/group_chat_session.dart';
import '../../models/group_chat_message.dart';
import '../../blocs/auth/auth_bloc.dart';

class GroupChatDetailScreen extends StatefulWidget {
  final GroupChatSession session;
  const GroupChatDetailScreen({super.key, required this.session});

  @override
  State<GroupChatDetailScreen> createState() => _GroupChatDetailScreenState();
}

class _GroupChatDetailScreenState extends State<GroupChatDetailScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late String _groupId;
  List<GroupChatMessage> _messages = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _groupId = widget.session.id;
    _loadMessages();
  }

  Future<void> _loadMessages() async {
    context.read<GroupChatBloc>().add(GroupChatLoadMessages(_groupId));
    _isLoading = true;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: Text(widget.session.name),
        actions: [
          IconButton(
            icon: Icon(widget.session.isMuted ? Icons.notifications_off : Icons.notifications),
            onPressed: () {
              context.read<GroupChatBloc>().add(GroupChatUpdateSession(
                groupId: _groupId,
                isMuted: !widget.session.isMuted,
              ));
            },
          ),
          PopupMenuButton<String>(
            onSelected: _handleMenuAction,
            itemBuilder: (ctx) => [
              const PopupMenuItem(value: 'pin', child: Text('置顶群聊')),
              const PopupMenuItem(value: 'settings', child: Text('群设置')),
              const PopupMenuItem(value: 'delete', child: Text('删除群聊')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: BlocBuilder<GroupChatBloc, GroupChatState>(
              builder: (context, state) {
                if (state is GroupChatLoading && _isLoading) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (state is GroupChatError) {
                  return Center(child: Text('加载失败: ${state.message}'));
                }
                if (state is GroupChatMessagesLoaded && state.groupId == _groupId) {
                  _messages = state.messages;
                  _isLoading = false;
                  if (mounted) setState(() {});
                  return _buildMessageList();
                }
                return const Center(child: CircularProgressIndicator());
              },
            ),
          ),
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildMessageList() {
    if (_messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chat_bubble_outline, size: 48,
                color: Theme.of(context).colorScheme.primary.withOpacity(0.4)),
            const SizedBox(height: 16),
            Text(
              '暂无消息',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5)),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      reverse: true,
      padding: const EdgeInsets.all(12),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final msg = _messages[index];
        final isUser = msg.isUser;
        final showAvatar = index == 0 || _messages[index - 1].senderId != msg.senderId;
        return _MessageBubble(
          message: msg,
          isUser: isUser,
          showAvatar: showAvatar,
          screenWidth: MediaQuery.of(context).size.width,
        );
      },
    );
  }

  Widget _buildInputBar() {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
        border: Border(top: BorderSide(color: colorScheme.outline.withOpacity(0.2))),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              decoration: InputDecoration(
                hintText: '输入消息...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: colorScheme.surface,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
              maxLines: null,
              textCapitalization: TextCapitalization.sentences,
              onSubmitted: _sendMessage,
            ),
          ),
          const SizedBox(width: 8),
          CircleAvatar(
            radius: 18,
            backgroundColor: colorScheme.primary,
            child: IconButton(
              icon: const Icon(Icons.send, color: Colors.white, size: 18),
              onPressed: () => _sendMessage(_messageController.text),
            ),
          ),
        ],
      ),
    );
  }

  void _sendMessage(String content) {
    if (content.trim().isEmpty) return;
    final authState = context.read<AuthBloc>().state;
    String userId = 'local_user';
    if (authState is AuthAuthenticated) {
      userId = authState.user.id;
    }

    context.read<GroupChatBloc>().add(GroupChatSendMessage(
          groupId: _groupId,
          userId: userId,
          content: content.trim(),
        ));
    _messageController.clear();

    // 滚动到底部
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _handleMenuAction(String action) {
    switch (action) {
      case 'pin':
        context.read<GroupChatBloc>().add(GroupChatUpdateSession(
              groupId: _groupId,
              isPinned: !widget.session.isPinned,
            ));
        break;
      case 'settings':
        _showGroupSettings();
        break;
      case 'delete':
        _confirmDelete();
        break;
    }
  }

  void _showGroupSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: Theme.of(ctx).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                ListTile(
                  leading: Icon(Icons.group),
                  title: const Text('群成员'),
                  subtitle: Text('${widget.session.memberIds.length} 人'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showMembers();
                  },
                ),
                ListTile(
                  leading: Icon(Icons.info_outline),
                  title: const Text('群信息'),
                  subtitle: Text('创建者: ${widget.session.creatorId.substring(0, 8)}...'),
                  onTap: () {
                    Navigator.pop(ctx);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showMembers() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${widget.session.name} - 成员'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: widget.session.memberIds.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (ctx, index) {
              final memberId = widget.session.memberIds[index];
              final isAi = widget.session.aiCharacterIds.contains(memberId);
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: isAi
                      ? Theme.of(ctx).colorScheme.tertiaryContainer
                      : Theme.of(ctx).colorScheme.primaryContainer,
                  child: Icon(
                    isAi ? Icons.smart_toy : Icons.person,
                    size: 18,
                    color: isAi
                        ? Theme.of(ctx).colorScheme.tertiary
                        : Theme.of(ctx).colorScheme.primary,
                  ),
                ),
                title: Text(isAi ? 'AI 角色' : (memberId == 'local_user' ? '我' : memberId)),
                subtitle: Text(isAi ? 'AI' : '用户'),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  void _confirmDelete() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除群聊'),
        content: Text('确定要删除群聊"${widget.session.name}"吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              context.read<GroupChatBloc>().add(GroupChatDelete(_groupId));
              if (context.mounted) {
                Navigator.pop(context, true);
              }
            },
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFE53935)),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}

/// 单条消息气泡
class _MessageBubble extends StatelessWidget {
  final GroupChatMessage message;
  final bool isUser;
  final bool showAvatar;
  final double screenWidth;

  const _MessageBubble({
    required this.message,
    required this.isUser,
    required this.showAvatar,
    required this.screenWidth,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isMe = isUser;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isMe) ...[
            _messageAvatar(message.senderName, colorScheme),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.senderName,
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.primary.withOpacity(0.7),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  _buildContentBubble(message.content, colorScheme, false),
                ],
              ),
            ),
          ] else ...[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _buildContentBubble(message.content, colorScheme, true),
                  const SizedBox(height: 2),
                  Text(
                    _formatTime(message.timestamp),
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onSurface.withOpacity(0.35),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _messageAvatar('我', colorScheme),
          ],
        ],
      ),
    );
  }

  Widget _buildContentBubble(String content, ColorScheme cs, bool isMe) {
    return Container(
      constraints: BoxConstraints(
        maxWidth: screenWidth * 0.7,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isMe ? cs.primary : cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16).copyWith(
          bottomRight: isMe ? const Radius.circular(4) : null,
          bottomLeft: isMe ? const Radius.circular(4) : null,
        ),
      ),
      child: Text(
        content,
        style: TextStyle(
          fontSize: 15,
          color: isMe ? cs.onPrimary : cs.onSurface,
        ),
      ),
    );
  }

  Widget _messageAvatar(String name, ColorScheme cs) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: cs.primaryContainer,
      ),
      child: ClipOval(
        child: Center(
          child: Text(
            name.isNotEmpty ? name.substring(0, 1) : '?',
            style: TextStyle(
              color: cs.primary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}
