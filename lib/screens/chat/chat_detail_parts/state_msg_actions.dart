// 消息操作（拆分生成，同库 part）
part of '../chat_detail_screen.dart';

mixin _StateMessageActions on State<ChatDetailScreen>, _StateCore, _StateLoadCore, _StateSelection, _StateSideStory, _StateVoice, _StateSendInput, _StateMoney, _StateSearch {
  void _showStickerPicker() {
    tapHaptic();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.4,
        minChildSize: 0.3,
        maxChildSize: 0.7,
        expand: false,
        builder: (context, scrollController) => _StickerPickerSheet(
          onEmojiSelected: (emoji) {
            Navigator.pop(context);
            _sendSticker(emoji);
          },
          onStickerSelected: (stickerId) {
            Navigator.pop(context);
            _sendBuiltinSticker(stickerId);
          },
          onImageStickerSelected: (imagePath) {
            Navigator.pop(context);
            _sendImageSticker(imagePath);
          },
          storage: RepositoryProvider.of<LocalStorageRepository>(context),
        ),
      ),
    );
  }


  Future<void> _deleteMessage(ChatMessage message) async {
    confirmHaptic();
    _chatBloc.add(ChatDeleteMessage(
      chatId: widget.session.id,
      messageId: message.id,
    ));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('消息已删除'), duration: Duration(seconds: 1)),
      );
    }
  }


  Future<void> _recallMessage(ChatMessage message) async {
    _chatBloc.add(ChatRecallMessage(
      chatId: widget.session.id,
      messageId: message.id,
    ));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('消息已撤回'), duration: Duration(seconds: 1)),
      );
    }
  }


  /// 微信式转发：选择目标会话 → 原样复制一条消息过去并刷新会话摘要。
  void _showForwardPicker(ChatMessage message) {
    final authState = context.read<AuthBloc>().state;
    final user = authState is AuthAuthenticated ? authState.user : null;
    if (user == null) return;
    final storage = RepositoryProvider.of<LocalStorageRepository>(context);
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
      builder: (ctx) => FutureBuilder<List<ChatSession>>(
        future: storage.getChatSessions(user.id),
        builder: (context, snapshot) {
          final sessions = (snapshot.data ?? [])
              .where((s) => s.id != widget.session.id && !s.isHidden)
              .toList();
          final isDark = Theme.of(context).brightness == Brightness.dark;
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    '转发到',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: _isWeChatStyle
                          ? (isDark
                              ? WeChatColors.darkTextPrimary
                              : WeChatColors.textPrimary)
                          : null,
                    ),
                  ),
                ),
                Flexible(
                  child: sessions.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('没有其他会话'),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: sessions.length,
                          itemBuilder: (context, i) {
                            final s = sessions[i];
                            return ListTile(
                              leading: WeChatAvatar(
                                imageUrl: s.aiCharacterAvatar,
                                size: 36,
                                fallbackText: s.aiCharacterName,
                              ),
                              title: Text(s.aiCharacterName),
                              onTap: () async {
                                Navigator.pop(ctx);
                                await _forwardMessage(message, s);
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }


  Future<void> _forwardMessage(ChatMessage message, ChatSession target) async {
    try {
      final storage = RepositoryProvider.of<LocalStorageRepository>(context);
      final authState = context.read<AuthBloc>().state;
      final user = authState is AuthAuthenticated ? authState.user : null;
      if (user == null) return;

      final now = DateTime.now();
      final forwardableTypes = [
        MessageType.text,
        MessageType.image,
        MessageType.sticker,
        MessageType.voice,
      ];
      final directCopy = forwardableTypes.contains(message.type);
      final forwarded = directCopy
          ? ChatMessage(
              id: const Uuid().v4(),
              chatId: target.id,
              senderId: user.id,
              content: message.content,
              type: message.type,
              status: MessageStatus.sent,
              createdAt: now,
              isUser: true,
              metadata: message.metadata == null
                  ? {'forwardedFrom': message.senderName}
                  : {
                      ...message.metadata!,
                      'forwardedFrom': message.senderName,
                    },
            )
          : ChatMessage(
              id: const Uuid().v4(),
              chatId: target.id,
              senderId: user.id,
              content: '[转发的${_replyPreview(message)}]',
              type: MessageType.text,
              status: MessageStatus.sent,
              createdAt: now,
              isUser: true,
            );
      await storage.saveChatMessage(forwarded);
      await storage.updateChatSessionLastMessage(
          target.id, _replyPreview(forwarded), now);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('已转发给 ${target.aiCharacterName}'),
            duration: const Duration(seconds: 1)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('转发失败')));
      }
    }
  }


  void _showMessageOptions(BuildContext context, ChatMessage message,
      {Offset? anchor}) {
    final isUserMessage = message.isFromUser;
    final isAIMessage = message.isFromAI;
    final canRecall = isUserMessage &&
        DateTime.now().difference(message.createdAt).inMinutes <= 2 &&
        message.content != '已撤回';
    final isRecalled =
        message.metadata?['recalled'] == true || message.content == '已撤回';
    final canEditAI =
        isAIMessage && !isRecalled && message.type == MessageType.text;
    final canRegenerate = isAIMessage && !isRecalled;

    // 微信模式：横向浮动菜单（回复/复制/编辑/重新生成/撤回/转发/收藏/多选/删除）
    if (_isWeChatStyle) {
      final items = <WeChatMenuItem>[
        WeChatMenuItem(
            label: '回复',
            icon: Icons.reply_outlined,
            onPressed: () => _setReplyTo(message)),
        if (!isRecalled && message.type == MessageType.text)
          WeChatMenuItem(
            label: '复制',
            icon: Icons.copy_outlined,
            onPressed: () {
              Clipboard.setData(ClipboardData(text: message.content));
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('已复制'), duration: Duration(seconds: 1)));
              }
            },
          ),
        if (canEditAI)
          WeChatMenuItem(
              label: '编辑',
              icon: Icons.edit_outlined,
              onPressed: () => _showEditAIReplyDialog(message)),
        if (canRegenerate)
          WeChatMenuItem(
              label: '重新生成',
              icon: Icons.refresh_outlined,
              onPressed: () => _showRegenerateConfirm(message)),
        if (canRecall)
          WeChatMenuItem(
              label: '撤回',
              icon: Icons.undo_outlined,
              onPressed: () => _recallMessage(message)),
        if (!isRecalled &&
            message.type != MessageType.transfer &&
            message.type != MessageType.redPacket)
          WeChatMenuItem(
              label: '转发',
              icon: Icons.forward_outlined,
              onPressed: () => _showForwardPicker(message)),
        WeChatMenuItem(
            label: message.isBookmark ? '取消收藏' : '收藏',
            icon: Icons.star_outline,
            onPressed: () => _chatBloc.add(ChatToggleBookmark(
                chatId: widget.session.id, messageId: message.id))),
        WeChatMenuItem(
            label: '多选',
            icon: Icons.checklist_outlined,
            onPressed: () => _enterSelection(message.id)),
        WeChatMenuItem(
            label: '删除',
            icon: Icons.delete_outline,
            onPressed: () => _showDeleteConfirm(message)),
      ];
      WeChatMessageMenu.show(context: context, items: items, anchor: anchor);
      return;
    }

    final actions = <MessageActionItem>[
      MessageActionItem(
          label: '回复',
          icon: Icons.reply,
          color: Colors.blue,
          onPressed: () => _setReplyTo(message)),
      if (!isRecalled && message.type == MessageType.text)
        MessageActionItem(
          label: '复制',
          icon: Icons.copy,
          color: Colors.teal,
          onPressed: () {
            Clipboard.setData(ClipboardData(text: message.content));
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('已复制到剪贴板'), duration: Duration(seconds: 1)));
          },
        ),
      if (canEditAI)
        MessageActionItem(
            label: '编辑',
            icon: Icons.edit,
            color: Colors.green,
            subtitle: '修改AI的回复内容',
            onPressed: () => _showEditAIReplyDialog(message)),
      if (canRegenerate)
        MessageActionItem(
            label: '重新生成',
            icon: Icons.refresh,
            color: Colors.purple,
            subtitle: '让AI重新回复，覆盖当前内容',
            onPressed: () => _showRegenerateConfirm(message)),
      if (canRecall)
        MessageActionItem(
            label: '撤回',
            icon: Icons.undo,
            color: Colors.orange,
            subtitle: '2分钟内可撤回',
            onPressed: () => _recallMessage(message)),
      MessageActionItem(
          label: message.isBookmark ? '取消收藏' : '收藏',
          icon: Icons.bookmark_border,
          color: Colors.amber.shade700,
          subtitle: message.isBookmark ? '从收藏夹移除' : '收藏此消息到发现页',
          onPressed: () => _chatBloc.add(ChatToggleBookmark(
              chatId: widget.session.id, messageId: message.id))),
      MessageActionItem(
          label: '删除',
          icon: Icons.delete_outline,
          color: Colors.red[400],
          onPressed: () => _showDeleteConfirm(message)),
      MessageActionItem(
          label: '多选',
          icon: Icons.checklist_rtl,
          color: Colors.blueGrey,
          subtitle: '批量删除 / 收藏消息',
          onPressed: () => _enterSelection(message.id)),
    ];
    MessageActionsSheet.show(context: context, actions: actions);
  }


  void _showEditAIReplyDialog(ChatMessage message) {
    final controller = TextEditingController(text: message.content);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑AI回复'),
        content: TextField(
          controller: controller,
          maxLines: null,
          minLines: 3,
          autofocus: true,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: '输入新的回复内容',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              final newContent = controller.text.trim();
              if (newContent.isEmpty) return;
              Navigator.pop(ctx);
              _chatBloc.add(ChatEditAIReply(
                chatId: widget.session.id,
                messageId: message.id,
                newContent: newContent,
              ));
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }


  void _showRegenerateConfirm(ChatMessage message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重新生成'),
        content: const Text('AI将重新回复，当前回复会被覆盖。确定吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _chatBloc.add(ChatRegenerateAIReply(
                chatId: widget.session.id,
                messageId: message.id,
              ));
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }


  void _showDeleteConfirm(ChatMessage message) {
    final ctx = context;
    showDialog(
      context: ctx,
      builder: (context) => AlertDialog(
        title: const Text('删除消息'),
        content: const Text('确定要删除这条消息吗？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteMessage(message);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }


  Future<void> _openChatSettings(BuildContext context) async {
    final storage = RepositoryProvider.of<LocalStorageRepository>(context);
    AICharacter? character;

    try {
      character = await storage.getAICharacter(
          _currentSession?.aiCharacterId ?? widget.session.aiCharacterId);
    } catch (e) {
      debugPrint('获取角色信息失败: $e');
    }

    if (mounted) {
      final settingsChanged = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChatSettingsScreen(
            session: _currentSession ?? widget.session,
            character: character,
          ),
        ),
      );

      if (mounted) {
        debugPrint('从设置页面返回，settingsChanged=$settingsChanged');

        // 处理从设置页面发起的转账
        if (settingsChanged is Map &&
            settingsChanged['pendingTransfer'] != null) {
          final transfer =
              settingsChanged['pendingTransfer'] as Map<String, dynamic>;
          final amount = (transfer['amount'] as num).toDouble();
          final message = transfer['message'] as String? ?? '';
          final user = context.read<AuthBloc>().state;
          if (user is AuthAuthenticated) {
            _chatBloc.add(ChatSendRedPacket(
              chatId: widget.session.id,
              userId: user.user.id,
              amount: amount,
              message: message,
            ));
          }
          _hasSettingsChanged = true;
        }

        if (settingsChanged == true || settingsChanged is Map) {
          _hasSettingsChanged = true;
          _chatBloc.add(ChatLoadMessages(widget.session.id));
        }

        final updatedSession = await storage.getChatSession(widget.session.id);
        if (updatedSession != null && mounted) {
          // 换背景后清掉旧图缓存，确保立刻生效
          final oldBg = _currentSession?.backgroundImage;
          final newBg = updatedSession.backgroundImage;
          if (oldBg != null && oldBg.isNotEmpty && oldBg != newBg) {
            try {
              final p = oldBg.startsWith('file://')
                  ? Uri.parse(oldBg).toFilePath()
                  : oldBg;
              if (!(oldBg.startsWith('http://') ||
                  oldBg.startsWith('https://'))) {
                await FileImage(File(p)).evict();
              } else {
                await NetworkImage(oldBg).evict();
              }
            } catch (_) {}
          }
          if (newBg != null && newBg.isNotEmpty) {
            try {
              final p = newBg.startsWith('file://')
                  ? Uri.parse(newBg).toFilePath()
                  : newBg;
              if (!(newBg.startsWith('http://') ||
                  newBg.startsWith('https://'))) {
                await FileImage(File(p)).evict();
              }
            } catch (_) {}
          }
          setState(() {
            _currentSession = updatedSession;
            _isBlockedByAI = updatedSession.isBlocked &&
                updatedSession.blockedBy == BlockedBy.ai;
            _isBlockedByUser = updatedSession.isBlocked &&
                updatedSession.blockedBy == BlockedBy.user;
          });
          debugPrint('已更新会话状态 - lastMessage: ${updatedSession.lastMessage}');
        }
        final updatedCharacter = await storage.getAICharacter(
            _currentSession?.aiCharacterId ?? widget.session.aiCharacterId);
        if (updatedCharacter != null && mounted) {
          setState(() {
            _aiPersonality = updatedCharacter.personality;
            _displayName = updatedCharacter.userAlias ?? updatedCharacter.name;
            _replyMode = updatedCharacter.interactionConfig?.replyMode;
            _enableProactiveMessage =
                updatedCharacter.interactionConfig?.enableMomentInteraction ??
                    true;
          });
        }
      }
    }
  }

}
