// 【对标来源：SillyTavern-1.18.0 — script.js 聊天交互 + chats.js 消息操作】
// 1:1 转译自 SillyTavern 聊天页面交互逻辑为 Flutter 页面
// 参考文件：script.js (消息发送/接收/编辑)、chats.js (消息操作)

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../blocs/chat/chat_bloc.dart';
import '../../../models/chat_message.dart';
import '../../../models/character_card_v2.dart';
import '../../../widgets/v2/message_bubble_v2.dart';
import '../../../widgets/message_actions.dart';
import '../../../widgets/swipe_handler.dart';
import '../../../widgets/confirm_dialog.dart';
import '../../../widgets/background_manager.dart';

/// 聊天页面 V2（对标 SillyTavern 聊天界面）
/// 完整保留 SillyTavern 的聊天交互：发送/编辑/删除/滑动/收藏
class ChatScreenV2 extends StatefulWidget {
  final String sessionId;
  final CharacterCardV2 character;
  final String? backgroundPath;

  const ChatScreenV2({
    super.key,
    required this.sessionId,
    required this.character,
    this.backgroundPath,
  });

  @override
  State<ChatScreenV2> createState() => _ChatScreenV2State();
}

class _ChatScreenV2State extends State<ChatScreenV2> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  List<ChatMessage> _messages = [];
  bool _isGenerating = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadMessages();
  }

  void _loadMessages() {
    // 通过 ChatBloc 加载消息
    context.read<ChatBloc>().add(ChatLoadMessages(widget.sessionId));
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return BackgroundManager(
      backgroundPath: widget.backgroundPath,
      opacity: 0.3,
      fallbackColor: colorScheme.surface,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: _buildAppBar(context),
        body: Column(
          children: [
            // 消息列表
            Expanded(
              child: _buildMessageList(),
            ),

            // 输入区域
            _buildInputArea(),
          ],
        ),
      ),
    );
  }

  /// 构建 AppBar（对标 SillyTavern 顶部导航）
  PreferredSizeWidget _buildAppBar(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AppBar(
      backgroundColor: colorScheme.surface.withOpacity(0.9),
      elevation: 0,
      title: Row(
        children: [
          // 角色头像（对标 SillyTavern .avatar img）
          CircleAvatar(
            radius: 18,
            backgroundColor: colorScheme.primaryContainer,
            backgroundImage: widget.character.avatarPath != null
                ? AssetImage(widget.character.avatarPath!)
                : null,
            child: widget.character.avatarPath == null
                ? Text(
                    widget.character.name.isNotEmpty
                        ? widget.character.name[0]
                        : '?',
                    style: TextStyle(
                      fontSize: 16,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 12),
          // 角色名称 + 状态
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.character.name,
                style: const TextStyle(fontSize: 16),
              ),
              BlocBuilder<ChatBloc, ChatState>(
                builder: (context, state) {
                  return Text(
                    _isGenerating ? '正在输入...' : '在线',
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  );
                },
              ),
            ],
          ),
        ],
      ),
      actions: [
        // 清空上下文（对标 SillyTavern clearContext）
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: '清空上下文',
          onPressed: _clearContext,
        ),
        // 设置
        IconButton(
          icon: const Icon(Icons.settings),
          onPressed: _openSettings,
        ),
      ],
    );
  }

  /// 构建消息列表（对标 SillyTavern #chat）
  Widget _buildMessageList() {
    return BlocConsumer<ChatBloc, ChatState>(
      listener: (context, state) {
        if (state is ChatMessagesLoaded) {
          setState(() {
            _messages = state.messages;
            _isLoading = false;
          });
          _scrollToBottom();
        } else if (state is ChatAITyping) {
          setState(() {
            _isGenerating = true;
            _messages = state.messages;
          });
        } else if (state is ChatAIStreaming) {
          setState(() {
            _isGenerating = true;
            _messages = state.messages;
          });
        } else if (state is ChatSwiped) {
          // 滑动完成，刷新消息列表
          _loadMessages();
        } else if (state is ChatMessageDeleted) {
          _loadMessages();
        } else if (state is ChatContextCleared) {
          _loadMessages();
        }
      },
      builder: (context, state) {
        if (_isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (_messages.isEmpty) {
          return _buildEmptyState();
        }

        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: _messages.length,
          itemBuilder: (context, index) => _buildMessage(index),
        );
      },
    );
  }

  /// 构建空状态（对标 SillyTavern 首条消息）
  Widget _buildEmptyState() {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 64,
            color: colorScheme.onSurface.withOpacity(0.3),
          ),
          const SizedBox(height: 16),
          Text(
            '和 ${widget.character.name} 开始对话',
            style: TextStyle(
              fontSize: 16,
              color: colorScheme.onSurface.withOpacity(0.5),
            ),
          ),
          if (widget.character.firstMes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                widget.character.firstMes,
                style: TextStyle(
                  fontSize: 14,
                  color: colorScheme.onSurface.withOpacity(0.4),
                ),
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 构建消息气泡（对标 SillyTavern #message_template）
  Widget _buildMessage(int index) {
    final message = _messages[index];
    final colorScheme = Theme.of(context).colorScheme;

    return SwipeHandler(
      swipeCount: message.swipeHistory.length,
      currentIndex: message.swipeIndex,
      onSwipeLeft: () => _swipeLeft(index),
      onSwipeRight: () => _swipeRight(index),
      child: MessageBubbleV2(
        message: message,
        characterName: widget.character.name,
        avatarPath: widget.character.avatarPath,
        isUser: message.isUser,
        isSystem: message.isSystem,
        isGhost: message.isGhost,
        isHidden: message.isHidden,
        isBookmarked: message.isBookmark,
        reasoning: message.reasoning,
        swipeHistory: message.swipeHistory,
        swipeIndex: message.swipeIndex,
        generationTime: message.generationTime,
        tokenCount: message.tokenCount,
        onEdit: () => _editMessage(index),
        onDelete: () => _deleteMessage(index),
        onCopy: () => _copyMessage(index),
        onToggleHide: () => _toggleHide(index),
        onToggleBookmark: () => _toggleBookmark(index),
        onSwipeLeft: () => _swipeLeft(index),
        onSwipeRight: () => _swipeRight(index),
      ),
    );
  }

  /// 构建输入区域
  Widget _buildInputArea() {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: colorScheme.surface.withOpacity(0.95),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 3,
            offset: const Offset(0, -1),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            // 附件按钮
            IconButton(
              icon: Icon(Icons.attach_file, color: colorScheme.onSurface.withOpacity(0.6)),
              onPressed: _attachFile,
            ),
            // 输入框
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: TextField(
                  controller: _messageController,
                  focusNode: _focusNode,
                  maxLines: 4,
                  minLines: 1,
                  decoration: InputDecoration(
                    hintText: '输入消息...',
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    hintStyle: TextStyle(
                      color: colorScheme.onSurface.withOpacity(0.4),
                    ),
                  ),
                  style: TextStyle(color: colorScheme.onSurface),
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // 发送按钮
            Container(
              decoration: BoxDecoration(
                color: colorScheme.primary,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: _isGenerating
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colorScheme.onPrimary,
                        ),
                      )
                    : Icon(Icons.send, color: colorScheme.onPrimary),
                onPressed: _isGenerating ? null : _sendMessage,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 发送消息
  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    _messageController.clear();
    _focusNode.requestFocus();

    // 通过 ChatBloc 发送消息
    context.read<ChatBloc>().add(ChatSendMessage(
      chatId: widget.sessionId,
      userId: 'user', // TODO: 从 AuthBloc 获取真实 userId
      content: text,
    ));
  }

  /// 编辑消息（对标 SillyTavern .mes_edit）
  void _editMessage(int index) {
    final message = _messages[index];
    final controller = TextEditingController(text: message.content);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('编辑消息'),
        content: TextField(
          controller: controller,
          maxLines: 10,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: '输入新内容...',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              context.read<ChatBloc>().add(ChatEditAIReply(
                chatId: widget.sessionId,
                messageId: message.id,
                newContent: controller.text,
              ));
              Navigator.pop(context);
            },
            child: const Text('确认'),
          ),
        ],
      ),
    );
  }

  /// 删除消息（对标 SillyTavern .mes_edit_delete）
  Future<void> _deleteMessage(int index) async {
    final message = _messages[index];
    final result = await ConfirmDialog.show(
      context: context,
      title: '删除消息',
      content: '确定删除这条消息吗？此操作不可撤销。',
      confirmText: '删除',
      isDestructive: true,
    );

    if (result == ConfirmResult.ok && mounted) {
      context.read<ChatBloc>().add(ChatDeleteMessage(
        chatId: widget.sessionId,
        messageId: message.id,
      ));
    }
  }

  /// 复制消息（对标 SillyTavern .mes_copy）
  void _copyMessage(int index) {
    final message = _messages[index];
    Clipboard.setData(ClipboardData(text: message.content));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已复制到剪贴板'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  /// 切换隐藏（对标 SillyTavern .mes_hide / .mes_unhide）
  void _toggleHide(int index) {
    final message = _messages[index];
    if (message.isHidden) {
      context.read<ChatBloc>().add(ChatUnhideMessage(
        chatId: widget.sessionId,
        messageId: message.id,
      ));
    } else {
      context.read<ChatBloc>().add(ChatHideMessage(
        chatId: widget.sessionId,
        messageId: message.id,
      ));
    }
  }

  /// 切换收藏（对标 SillyTavern .mes_bookmark）
  void _toggleBookmark(int index) {
    final message = _messages[index];
    context.read<ChatBloc>().add(ChatToggleBookmark(
      chatId: widget.sessionId,
      messageId: message.id,
    ));
  }

  /// 左滑历史（对标 SillyTavern .swipe_left）
  void _swipeLeft(int index) {
    final message = _messages[index];
    context.read<ChatBloc>().add(ChatSwipeLeft(
      chatId: widget.sessionId,
      messageId: message.id,
    ));
  }

  /// 右滑历史（对标 SillyTavern .swipe_right）
  void _swipeRight(int index) {
    final message = _messages[index];
    context.read<ChatBloc>().add(ChatSwipeRight(
      chatId: widget.sessionId,
      messageId: message.id,
    ));
  }

  /// 清空上下文（对标 SillyTavern clearContext）
  Future<void> _clearContext() async {
    final result = await ConfirmDialog.show(
      context: context,
      title: '清空上下文',
      content: '确定清空聊天上下文吗？最近 10 条消息将被保留。',
      confirmText: '清空',
    );

    if (result == ConfirmResult.ok && mounted) {
      context.read<ChatBloc>().add(ChatClearContext(
        chatId: widget.sessionId,
      ));
    }
  }

  void _openSettings() {
    // TODO: 打开聊天设置页面
  }

  void _attachFile() {
    // TODO: 附件选择
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }
}
