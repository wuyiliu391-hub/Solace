// 消息列表与输入区构建（拆分生成，同库 part）
part of '../chat_detail_screen.dart';

mixin _StateListInputBuilders on State<ChatDetailScreen>, _StateCore, _StateLoadCore, _StateSelection, _StateSideStory, _StateVoice, _StateSendInput, _StateMoney, _StateSearch, _StateMessageActions, _StateNavDialogs, _StateAppBarBuilders {
  Widget _buildMessageList(BuildContext context, List<ChatMessage> messages,
      {bool showTyping = false, String? typingStatusText}) {
    final authState = context.read<AuthBloc>().state;
    final userAvatarUrl =
        authState is AuthAuthenticated ? authState.user.avatarUrl : null;
    final currentAvatar =
        _currentSession?.aiCharacterAvatar ?? widget.session.aiCharacterAvatar;
    final currentName =
        _currentSession?.aiCharacterName ?? widget.session.aiCharacterName;

    final totalItems =
        messages.length + (showTyping ? 1 : 0) + (_hasMoreMessages ? 1 : 0);

    return Container(
      color: Colors.transparent,
      child: ListView.builder(
        controller: _scrollController,
        physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics()),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        reverse: true,
        itemCount: totalItems,
        itemBuilder: (context, index) {
          if (_hasMoreMessages && index == totalItems - 1) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: _isLoadingMore
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text('上滑加载更多历史消息',
                        style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withOpacity(0.4))),
              ),
            );
          }

          if (showTyping && index == 0) {
            return TypingIndicator(
              avatarUrl: currentAvatar,
              name: currentName,
              statusText: typingStatusText ?? '等待中...',
            );
          }

          final msgIndex = showTyping ? index - 1 : index;
          final reversedIndex = messages.length - 1 - msgIndex;
          final message = messages[reversedIndex];
          final isHighlighted = message.id == _highlightedMessageId;
          final selected = _selectionMode && _selectedIds.contains(message.id);
          final showTime = reversedIndex == messages.length - 1 ||
              messages[reversedIndex + 1]
                      .createdAt
                      .difference(message.createdAt)
                      .inMinutes >
                  5;

          return AnimatedListItem(
            index: msgIndex,
            key: _messageKeys.putIfAbsent(message.id, () => GlobalKey()),
            child: Container(
              decoration: (isHighlighted || selected)
                  ? BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .primaryContainer
                          .withOpacity(selected ? 0.5 : 0.3),
                      borderRadius: BorderRadius.circular(10),
                    )
                  : null,
              padding: isHighlighted
                  ? const EdgeInsets.symmetric(vertical: 4)
                  : null,
              child: Column(
                children: [
                  GestureDetector(
                    onTap:
                        _selectionMode ? () => _toggleSelect(message.id) : null,
                    onLongPressStart: _selectionMode
                        ? null
                        : (details) {
                            confirmHaptic();
                            _showMessageOptions(context, message,
                                anchor: details.globalPosition);
                          },
                    child: _MessageBubble(
                      message: message,
                      aiAvatarUrl: currentAvatar,
                      userAvatarUrl: userAvatarUrl,
                      aiName: currentName,
                      novelMode: _isNovelModeEnabled(),
                      dialogueColorLight:
                          RepositoryProvider.of<LocalStorageRepository>(context)
                              .getNovelDialogueColor(),
                      dialogueColorDark:
                          RepositoryProvider.of<LocalStorageRepository>(context)
                              .getNovelDialogueColor(),
                      hasBackgroundImage: _hasVisibleBackground,
                      wechatStyle: _isWeChatStyle,
                      onMoneyTap: _moneyTapHandler(message),
                      onImageTap: message.type == MessageType.image
                          ? () => _showFullScreenImage(message.content)
                          : null,
                      onPlayVoice: message.isFromAI
                          ? () => _playMessageVoice(message)
                          : null,
                      voiceBusy: _synthesizingMessageId == message.id,
                    ),
                  ),
                  if (showTime)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: _isWeChatStyle
                          ? Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? const Color(0xFF3A3A3A)
                                      : const Color(0xFFE6E6E6),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  _formatMessageTime(message.createdAt),
                                  style: TextStyle(
                                    fontSize: 9,
                                    height: 1.2,
                                    color: Theme.of(context).brightness ==
                                            Brightness.dark
                                        ? WeChatColors.darkTextSecondary
                                        : const Color(0xFFB2B2B2),
                                  ),
                                ),
                              ),
                            )
                          : Text(
                              _formatMessageTime(message.createdAt),
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withOpacity(0.4),
                              ),
                            ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }


  Widget _buildInputArea(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (_isBlockedByAI) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: colorScheme.error.withOpacity(0.08),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.block, size: 14, color: colorScheme.error),
                const SizedBox(width: 6),
                Text(
                  '你处于对方黑名单中，消息可能不会被回复',
                  style: TextStyle(fontSize: 12, color: colorScheme.error),
                ),
              ],
            ),
          ),
          _buildNormalInput(context, colorScheme),
        ],
      );
    }

    if (_isBlockedByUser) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          border: Border(
              top: BorderSide(color: colorScheme.outlineVariant, width: 0.5)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.block,
                size: 16, color: colorScheme.onSurface.withOpacity(0.5)),
            const SizedBox(width: 8),
            Text(
              '你已拉黑对方',
              style: TextStyle(
                  fontSize: 14, color: colorScheme.onSurface.withOpacity(0.5)),
            ),
          ],
        ),
      );
    }

    return _buildNormalInput(context, colorScheme);
  }


  /// 保留为兼容旧调用点；当前布局不再挂载常驻快捷栏。
  Widget _buildQuickActionsBar(
      BuildContext context, ColorScheme colorScheme) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isWeChat = _isWeChatStyle;
    final fg = isWeChat
        ? (isDark ? WeChatColors.darkTextPrimary : WeChatColors.textPrimary)
        : (isDark ? ImmersiveColors.textSecondary : const Color(0xFF766E6C));
    final panelColor = isWeChat
        ? (isDark ? WeChatColors.darkChatBottomBar : WeChatColors.listItem)
        : (isDark
            ? ImmersiveColors.cardHigh
            : Colors.white.withOpacity(0.78));
    final panelBorder = isWeChat
        ? (isDark ? WeChatColors.darkDivider : WeChatColors.divider)
        : (isDark
            ? Colors.white.withOpacity(0.10)
            : Colors.black.withOpacity(0.07));

    Widget actionButton(IconData icon, String label, VoidCallback onTap) {
      return Expanded(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 20, color: fg),
                const SizedBox(height: 3),
                Text(label, style: TextStyle(fontSize: 10, color: fg)),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: panelColor,
        borderRadius: BorderRadius.circular(isWeChat ? 8.0 : 16),
        border: Border.all(color: panelBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.12 : 0.035),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          actionButton(Icons.call_rounded, '语音通话',
              () => _openVoiceCall(context)),
          actionButton(Icons.person_outline_rounded, '角色卡',
              () => _openChatSettings(context)),
          actionButton(Icons.emoji_emotions_outlined, '贴纸',
              () => _showStickerPicker()),
          actionButton(
              Icons.add_circle_outline_rounded, '更多', () => _showMoreActions()),
        ],
      ),
    );
  }


  Widget _buildNormalInput(BuildContext context, ColorScheme colorScheme) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_hasPendingReply)
          GestureDetector(
            onTap: _triggerPendingReply,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: colorScheme.primary.withOpacity(0.08),
              child: Row(
                children: [
                  Icon(Icons.unfold_more, size: 16, color: colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '上滑查看 TA 的回复',
                      style:
                          TextStyle(fontSize: 13, color: colorScheme.primary),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: colorScheme.primary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text('查看回复',
                        style: TextStyle(fontSize: 12, color: Colors.white)),
                  ),
                ],
              ),
            ),
          ),
        if (_replyToMessage != null)
          Container(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
            decoration: BoxDecoration(
              color: colorScheme.primary.withOpacity(0.08),
              border: Border(
                top: BorderSide(color: colorScheme.primary.withOpacity(0.2)),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 3,
                  height: 32,
                  decoration: BoxDecoration(
                    color: colorScheme.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _replyToMessage!.senderName ??
                            (_replyToMessage!.isFromAI ? 'AI' : '用户'),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _replyPreview(_replyToMessage!),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close,
                      size: 18, color: colorScheme.onSurface.withOpacity(0.4)),
                  onPressed: _cancelReply,
                  constraints: const BoxConstraints(),
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
        Container(
          decoration: BoxDecoration(
            color: _isWeChatStyle
                ? (isDark ? WeChatColors.darkChatBottomBar : WeChatColors.chatBottomBar)
                : (isDark
                    ? ImmersiveColors.cardHigh
                    : Colors.white.withOpacity(0.82)),
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(_isWeChatStyle ? 0 : 22),
            ),
            border: Border(
              top: BorderSide(
                color: _isWeChatStyle
                    ? (isDark ? WeChatColors.darkDivider : WeChatColors.divider)
                    : (isDark
                        ? Colors.white.withOpacity(0.10)
                        : Colors.black.withOpacity(0.07)),
                width: 0.7,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.16 : 0.035),
                blurRadius: 18,
                offset: const Offset(0, -5),
              ),
            ],
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_pendingImagePaths.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                    child: SizedBox(
                      height: 72,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _pendingImagePaths.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          final path = _pendingImagePaths[index];
                          return Stack(
                            clipBehavior: Clip.none,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Image.file(
                                  File(path),
                                  width: 72,
                                  height: 72,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
                                    width: 72,
                                    height: 72,
                                    color: isDark
                                        ? Colors.white12
                                        : Colors.black12,
                                    child: Icon(
                                      Icons.broken_image_outlined,
                                      color: colorScheme.onSurface
                                          .withOpacity(0.4),
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                top: -6,
                                right: -6,
                                child: GestureDetector(
                                  onTap: () => _removePendingImage(index),
                                  child: Container(
                                    width: 22,
                                    height: 22,
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.65),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.close,
                                      size: 14,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Row(
                    children: [
                      _buildWebSearchToggle(colorScheme, isDark),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // 语音输入按钮（录音转文字）
                      Tooltip(
                        message: _isRecordingVoice ? '停止并识别' : '语音输入',
                        child: GestureDetector(
                          onTap: _handleVoiceInput,
                          child: Container(
                            width: 36,
                            height: 40,
                            margin: const EdgeInsets.only(right: 4, bottom: 2),
                            alignment: Alignment.center,
                            child: _isTranscribingVoice
                                ? SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: isDark
                                          ? Colors.white.withOpacity(0.7)
                                          : Colors.black.withOpacity(0.5),
                                    ),
                                  )
                                : Icon(
                                    _isRecordingVoice
                                        ? Icons.stop_circle_outlined
                                        : Icons.mic_none,
                                    size: 24,
                                    color: _isRecordingVoice
                                        ? Colors.redAccent
                                        : (isDark
                                            ? Colors.white.withOpacity(0.6)
                                            : Colors.black.withOpacity(0.5)),
                                  ),
                          ),
                        ),
                      ),
                      // 括号快捷按钮（语c动作描写）
                      Tooltip(
                        message: '输入括号（语C动作描写）',
                        child: GestureDetector(
                          onTap: () {
                            final text = _messageController.text;
                            final selection = _messageController.selection;
                            final start = selection.start < 0
                                ? text.length
                                : selection.start;
                            final newText =
                                '${text.substring(0, start)}（）${text.substring(start)}';
                            _messageController.text = newText;
                            // 光标定位到括号中间
                            _messageController.selection =
                                TextSelection.collapsed(offset: start + 1);
                            _messageFocusNode.requestFocus();
                            // 更新发送按钮状态
                            _syncCanSend();
                          },
                          child: Container(
                            width: 36,
                            height: 40,
                            margin: const EdgeInsets.only(right: 4, bottom: 2),
                            alignment: Alignment.center,
                            child: Text(
                              '()',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? Colors.white.withOpacity(0.6)
                                    : Colors.black.withOpacity(0.5),
                              ),
                            ),
                          ),
                        ),
                      ),
                      // 输入框（微信风格：白底小圆角；沉浸式：深底胶囊）
                      Expanded(
                        child: Container(
                          constraints: const BoxConstraints(
                              minHeight: 40, maxHeight: 120),
                          decoration: BoxDecoration(
                            color: _isWeChatStyle
                                ? (isDark
                                    ? WeChatColors.darkInputBox
                                    : WeChatColors.inputBox)
                            : isDark
                                ? ImmersiveColors.backgroundUp.withOpacity(0.72)
                                : const Color(0xFFF8F5F2),
                            borderRadius: BorderRadius.circular(
                                _isWeChatStyle ? 6.0 : 18),
                            border: Border.all(
                              color: _isWeChatStyle && !isDark
                                  ? WeChatColors.dividerLight
                                  : (isDark
                                      ? Colors.white.withOpacity(0.10)
                                      : Colors.black.withOpacity(0.07)),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              // 文本输入
                              Expanded(
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxHeight: 120,
                                  ),
                                  child: SingleChildScrollView(
                                    physics: const ClampingScrollPhysics(),
                                    child: TextField(
                                      controller: _messageController,
                                      focusNode: _messageFocusNode,
                                      decoration: InputDecoration(
                                        hintText: _pendingImagePaths.isEmpty
                                            ? '发消息...'
                                            : '添加说明，或直接发送图片...',
                                        hintStyle: TextStyle(
                                          color: isDark
                                              ? Colors.white.withOpacity(0.35)
                                              : Colors.black.withOpacity(0.35),
                                          fontSize: 15,
                                        ),
                                        filled: false,
                                        border: InputBorder.none,
                                        contentPadding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 10,
                                        ),
                                      ),
                                      style: TextStyle(
                                        color: colorScheme.onSurface,
                                        fontSize: 15,
                                      ),
                                      textInputAction: TextInputAction.send,
                                      onSubmitted: (_) => _sendMessage(),
                                      onTapOutside: (_) {
                                        _messageFocusNode.unfocus();
                                      },
                                      maxLines: null,
                                      onChanged: (v) {
                                        _syncCanSend();
                                      },
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // 表情按钮
                      GestureDetector(
                        onTap: _showStickerPicker,
                        child: Container(
                          width: 36,
                          height: 40,
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.emoji_emotions_outlined,
                            color: isDark
                                ? Colors.white.withOpacity(0.6)
                                : Colors.black.withOpacity(0.5),
                            size: 24,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      // 图片按钮 / 发送按钮（有文字时显示发送）
                      ValueListenableBuilder<bool>(
                        valueListenable: _canSendNotifier,
                        builder: (context, canSend, _) {
                          if (canSend) {
                            return GestureDetector(
                              onTap: _sendMessage,
                              child: Container(
                                width: 40,
                                height: 40,
                                margin: const EdgeInsets.only(bottom: 2),
                                decoration: BoxDecoration(
                                  color: colorScheme.primary,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.arrow_upward_rounded,
                                  color: Colors.white,
                                  size: 22,
                                ),
                              ),
                            );
                          } else {
                            return GestureDetector(
                              onTap: _showMoreActions,
                              child: Container(
                                width: 36,
                                height: 40,
                                alignment: Alignment.center,
                                child: Icon(
                                  Icons.add_circle_outline,
                                  color: isDark
                                      ? Colors.white.withOpacity(0.6)
                                      : Colors.black.withOpacity(0.5),
                                  size: 24,
                                ),
                              ),
                            );
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }


  Widget _buildWebSearchToggle(ColorScheme colorScheme, bool isDark) {
    final enabled = _webSearchEnabled;
    final bgColor = enabled
        ? colorScheme.primary
        : (isDark ? const Color(0xFF1F1F1F) : Colors.white);
    final fgColor = enabled
        ? Colors.white
        : (isDark
            ? Colors.white.withOpacity(0.72)
            : Colors.black.withOpacity(0.62));
    final borderColor = enabled
        ? colorScheme.primary
        : (isDark
            ? Colors.white.withOpacity(0.12)
            : Colors.black.withOpacity(0.10));

    return GestureDetector(
      onTap: () => setState(() => _webSearchEnabled = !_webSearchEnabled),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: borderColor),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: colorScheme.primary.withOpacity(0.24),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.public_rounded, size: 15, color: fgColor),
            const SizedBox(width: 6),
            Text(
              '联网搜索',
              style: TextStyle(
                color: fgColor,
                fontSize: 13,
                fontWeight: enabled ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildMessageListFromStorage(BuildContext context) {
    return FutureBuilder<List<ChatMessage>>(
      future: RepositoryProvider.of<LocalStorageRepository>(context)
          .getChatMessages(widget.session.id),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasData && snapshot.data!.isNotEmpty) {
          return _buildMessageList(context, snapshot.data!);
        }
        return _buildEmptyChat(context);
      },
    );
  }


  /// 带流式输出气泡的消息列表
  Widget _buildMessageListWithStreaming(BuildContext context,
      List<ChatMessage> messages, String streamingText, String characterName,
      {String reasoning = ''}) {
    final authState = context.read<AuthBloc>().state;
    final userAvatarUrl =
        authState is AuthAuthenticated ? authState.user.avatarUrl : null;
    final currentAvatar =
        _currentSession?.aiCharacterAvatar ?? widget.session.aiCharacterAvatar;
    final currentName =
        _currentSession?.aiCharacterName ?? widget.session.aiCharacterName;

    // 流式气泡占一个item（index 0），消息列表占剩余items
    final totalItems = messages.length + 1 + (_hasMoreMessages ? 1 : 0);

    return Container(
      color: Colors.transparent,
      child: ListView.builder(
        controller: _scrollController,
        physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics()),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        reverse: true,
        itemCount: totalItems,
        itemBuilder: (context, index) {
          if (_hasMoreMessages && index == totalItems - 1) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: _isLoadingMore
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text('上滑加载更多历史消息',
                        style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withOpacity(0.4))),
              ),
            );
          }

          // index 0 = 流式输出气泡（因为reverse: true，显示在最底部）
          if (index == 0) {
            if (streamingText.isEmpty) {
              final statusText = reasoning.isNotEmpty ? '思考中...' : '等待中...';
              return TypingIndicator(
                avatarUrl: currentAvatar,
                name: currentName,
                statusText: statusText,
              );
            }
            return _StreamingBubble(
              text: streamingText,
              reasoning: reasoning,
              avatarUrl: currentAvatar,
              name: currentName,
              novelMode: _isNovelModeEnabled(),
              hasActionBracket:
                  RegExp(r'[（(]([^（)()]+)[）)]').hasMatch(streamingText),
              wechatStyle: _isWeChatStyle,
            );
          }
          final msgIndex = index - 1;
          final reversedIndex = messages.length - 1 - msgIndex;
          if (reversedIndex < 0 || reversedIndex >= messages.length)
            return const SizedBox();
          final message = messages[reversedIndex];
          final isHighlighted = message.id == _highlightedMessageId;
          final selected = _selectionMode && _selectedIds.contains(message.id);

          return Container(
            key: ValueKey(message.id),
            decoration: (isHighlighted || selected)
                ? BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .primaryContainer
                        .withOpacity(selected ? 0.5 : 0.3),
                    borderRadius: BorderRadius.circular(10),
                  )
                : null,
            padding:
                isHighlighted ? const EdgeInsets.symmetric(vertical: 4) : null,
            child: GestureDetector(
              onTap: _selectionMode ? () => _toggleSelect(message.id) : null,
              child: _MessageBubble(
                message: message,
                aiAvatarUrl: currentAvatar,
                userAvatarUrl: userAvatarUrl,
                aiName: currentName,
                novelMode: _isNovelModeEnabled(),
                dialogueColorLight:
                    RepositoryProvider.of<LocalStorageRepository>(context)
                        .getNovelDialogueColor(),
                dialogueColorDark:
                    RepositoryProvider.of<LocalStorageRepository>(context)
                        .getNovelDialogueColor(),
                hasBackgroundImage: _hasVisibleBackground,
                wechatStyle: _isWeChatStyle,
                onMoneyTap: _moneyTapHandler(message),
                onImageTap: message.type == MessageType.image ? () {} : null,
                onPlayVoice:
                    message.isFromAI ? () => _playMessageVoice(message) : null,
                voiceBusy: _synthesizingMessageId == message.id,
              ),
            ),
          );
        },
      ),
    );
  }


  Widget _buildEmptyChat(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final currentAvatar =
        _currentSession?.aiCharacterAvatar ?? widget.session.aiCharacterAvatar;
    final currentName =
        _currentSession?.aiCharacterName ?? widget.session.aiCharacterName;

    final greetings = [
      '你好呀，我是$currentName',
      '终于等到你了，想聊点什么？',
      '今天过得怎么样？和我分享一下吧',
      '我在这里，随时陪你聊天',
    ];
    final greeting =
        greetings[DateTime.now().millisecondsSinceEpoch % greetings.length];

    final suggestedTopics = [
      '今天发生了什么有趣的事？',
      '你最近有什么烦恼吗？',
      '分享一首你喜欢的歌吧',
      '你理想中的生活是什么样的？',
      '说说你最喜欢的电影',
      '你小时候的梦想是什么？',
    ];
    final randomTopics = suggestedTopics..shuffle();
    final displayTopics = randomTopics.take(3).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 40),
          TweenAnimationBuilder<double>(
            duration: const Duration(milliseconds: 800),
            curve: Curves.easeOutBack,
            tween: Tween(begin: 0, end: 1),
            builder: (context, value, child) {
              return Transform.scale(
                scale: value,
                child: child,
              );
            },
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: colorScheme.primary.withOpacity(0.3),
                  width: 3,
                ),
                boxShadow: [
                  BoxShadow(
                    color: colorScheme.primary.withOpacity(0.15),
                    blurRadius: 20,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: ClipOval(
                child: currentAvatar != null && currentAvatar.isNotEmpty
                    ? (AvatarResolver.imageWidget(currentAvatar,
                            fit: BoxFit.cover,
                            onError: () => _buildAvatarPlaceholder(
                                currentName, colorScheme)) ??
                        _buildAvatarPlaceholder(currentName, colorScheme))
                    : _buildAvatarPlaceholder(currentName, colorScheme),
              ),
            ),
          ),
          const SizedBox(height: 24),
          TweenAnimationBuilder<double>(
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOut,
            tween: Tween(begin: 0, end: 1),
            builder: (context, value, child) {
              return Opacity(
                opacity: value,
                child: Transform.translate(
                  offset: Offset(0, 10 * (1 - value)),
                  child: child,
                ),
              );
            },
            child: Text(
              greeting,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: colorScheme.onSurface.withOpacity(0.8),
              ),
            ),
          ),
          const SizedBox(height: 8),
          TweenAnimationBuilder<double>(
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOut,
            tween: Tween(begin: 0, end: 1),
            builder: (context, value, child) {
              return Opacity(
                opacity: value,
                child: Transform.translate(
                  offset: Offset(0, 10 * (1 - value)),
                  child: child,
                ),
              );
            },
            child: Text(
              '试试下面这些话题开始聊天吧',
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.onSurface.withOpacity(0.4),
              ),
            ),
          ),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: colorScheme.outline.withOpacity(0.1),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.lightbulb_outline,
                        size: 18, color: colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      '推荐话题',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ...displayTopics.map((topic) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: GestureDetector(
                        onTap: () {
                          _messageController.text = topic;
                          _sendMessage();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color:
                                colorScheme.primaryContainer.withOpacity(0.4),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: colorScheme.primary.withOpacity(0.15),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.chat_bubble_outline,
                                size: 14,
                                color: colorScheme.primary.withOpacity(0.6),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  topic,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: colorScheme.primary,
                                  ),
                                ),
                              ),
                              Icon(
                                Icons.arrow_forward_ios,
                                size: 12,
                                color: colorScheme.primary.withOpacity(0.3),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildAvatarPlaceholder(String name, ColorScheme colorScheme) {
    return Container(
      color: colorScheme.primaryContainer,
      child: Center(
        child: Text(
          name.isNotEmpty ? name.substring(0, 1) : 'A',
          style: TextStyle(
            fontSize: 36,
            fontWeight: FontWeight.bold,
            color: colorScheme.primary,
          ),
        ),
      ),
    );
  }

}
