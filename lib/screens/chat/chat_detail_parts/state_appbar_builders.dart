// 顶栏构建（拆分生成，同库 part）
part of '../chat_detail_screen.dart';

mixin _StateAppBarBuilders on State<ChatDetailScreen>, _StateCore, _StateLoadCore, _StateSelection, _StateSideStory, _StateVoice, _StateSendInput, _StateMoney, _StateSearch, _StateMessageActions, _StateNavDialogs {
  // ─── 现代风格 AppBar ───
  PreferredSizeWidget _buildModernAppBar(ColorScheme colorScheme) {
    final brightness = Theme.of(context).brightness;
    final isDark = brightness == Brightness.dark;
    final isWeChat = _isWeChatStyle;
    final currentName = _displayName ??
        _currentSession?.aiCharacterName ??
        widget.session.aiCharacterName;
    final currentAvatar =
        _currentSession?.aiCharacterAvatar ?? widget.session.aiCharacterAvatar;
    final iconColor = isDark
        ? (isWeChat ? Colors.white : ImmersiveColors.textPrimary)
        : (isWeChat ? Colors.black87 : const Color(0xFF4A4140));
    return AppBar(
      // 18.3.0 沉浸式：深色下 AppBar 透明，仅保留自上而下的暗色渐变遮罩，
      // 让角色氛围背景从屏幕顶端贯通到底部。
      // 微信风格：实色顶栏（#EAEAEA/#111111），标题单行角色名。
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      flexibleSpace: isWeChat
          ? DecoratedBox(
              decoration: BoxDecoration(
                color: isDark
                    ? WeChatColors.darkPageBackground
                    : WeChatColors.chatBackground,
              ),
            )
          : isDark
              ? DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        ImmersiveColors.background.withOpacity(0.92),
                        ImmersiveColors.background.withOpacity(0.35),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.7, 1.0],
                    ),
                  ),
                )
              : DecoratedBox(
                  decoration: const BoxDecoration(color: Color(0xFFF1EFEB)),
                ),
      leading: IconButton(
        icon: Icon(
          Icons.arrow_back_ios_new_rounded,
          color: iconColor,
          size: 20,
        ),
        onPressed: () => Navigator.pop(context, _hasSettingsChanged),
      ),
      title: _buildCompactChatTitle(
        colorScheme,
        isDark,
        currentName,
        currentAvatar,
      ),
      titleSpacing: 0,
      centerTitle: false,
      bottom: isWeChat
          ? PreferredSize(
              preferredSize: const Size.fromHeight(WeChatDimens.dividerHeight),
              child: Divider(
                height: WeChatDimens.dividerHeight,
                thickness: WeChatDimens.dividerHeight,
                color: isDark
                    ? WeChatColors.darkDivider
                    : WeChatColors.divider,
              ),
            )
          : null,
      actions: [
        IconButton(
          tooltip: '语音通话',
          icon: Icon(Icons.call_rounded, color: iconColor, size: 22),
          onPressed: () => _openVoiceCall(context),
        ),
        PopupMenuButton<String>(
          icon: Icon(Icons.more_horiz_rounded, color: iconColor, size: 24),
          tooltip: '更多',
          offset: const Offset(0, 50),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'virtual_phone',
              child: Row(
                children: [
                  Icon(Icons.smartphone_rounded, size: 20),
                  SizedBox(width: 12),
                  Text('TA 的手机'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'moments',
              child: Row(
                children: [
                  Icon(Icons.auto_awesome_rounded, size: 20),
                  SizedBox(width: 12),
                  Text('查看动态'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'turn_state',
              child: Row(
                children: [
                  Icon(Icons.insights_outlined, size: 20),
                  SizedBox(width: 12),
                  Text('TA 的当前状态'),
                ],
              ),
            ),
            if (!_isSideStory)
              const PopupMenuItem(
                value: 'side_story_new',
                child: Row(
                  children: [
                    Icon(Icons.auto_awesome_motion_outlined, size: 20),
                    SizedBox(width: 12),
                    Text('开启番外小剧场'),
                  ],
                ),
              ),
            if (!_isSideStory)
              const PopupMenuItem(
                value: 'side_story_list',
                child: Row(
                  children: [
                    Icon(Icons.history_rounded, size: 20),
                    SizedBox(width: 12),
                    Text('番外小剧场回看'),
                  ],
                ),
              ),
            const PopupMenuItem(
              value: 'settings',
              child: Row(
                children: [
                  Icon(Icons.settings_outlined, size: 20),
                  SizedBox(width: 12),
                  Text('聊天设置'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'character_profile',
              child: Row(
                children: [
                  Icon(Icons.person_outline_rounded, size: 20),
                  SizedBox(width: 12),
                  Text('角色设定'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'memory_recall',
              child: Row(
                children: [
                  Icon(Icons.auto_stories_outlined, size: 20),
                  SizedBox(width: 12),
                  Text('记忆回溯'),
                ],
              ),
            ),
          ],
          onSelected: (value) {
            if (value == 'virtual_phone') {
              _openVirtualPhone(context);
            } else if (value == 'moments') {
              _openMoments(context);
            } else if (value == 'turn_state') {
              _showFullStatus(context);
            } else if (value == 'settings') {
              _openChatSettings(context);
            } else if (value == 'side_story_new') {
              _startSideStory();
            } else if (value == 'side_story_list') {
              _openSideStoryList();
            } else if (value == 'character_profile') {
              _openCharacterProfile(context);
            } else if (value == 'memory_recall') {
              _openMemoryRecall(context);
            }
          },
        ),
      ],
    );
  }

  /// 紧凑聊天标题：集中展示角色身份和一行状态，避免在消息区重复占位。
  /// 搜索/定位场景也复用同一标题，避免 AppBar 在状态切换时跳变。
  Widget _buildCompactChatTitle(

    ColorScheme colorScheme,
    bool isDark,
    String currentName,
    String? currentAvatar,
  ) {
    final isWeChat = _isWeChatStyle;
    final primary = isDark
        ? (isWeChat ? WeChatColors.darkTextPrimary : ImmersiveColors.textPrimary)
        : (isWeChat ? WeChatColors.textPrimary : const Color(0xFF312B29));
    final secondary = isDark
        ? (isWeChat ? WeChatColors.darkTextSecondary : ImmersiveColors.textSecondary)
        : (isWeChat ? WeChatColors.textSecondary : const Color(0xFF817775));
    final accent = isWeChat
        ? colorScheme.primary
        : (isDark ? ImmersiveColors.accent : const Color(0xFF9B5F67));
    final intimacy = (_currentSession ?? widget.session)
        .intimacyLevel
        .clamp(0, 999999)
        .toInt();

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.48,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildAppBarAvatar(currentAvatar, isDark),
          const SizedBox(width: 8),
          Flexible(
            child: ValueListenableBuilder<bool>(
              valueListenable: _isAiTypingNotifier,
              builder: (context, typing, _) {
                final subtitle = typing
                    ? '对方正在输入…'
                    : '${_turnEmotion.isEmpty ? '等待互动' : _turnEmotion} · 亲密度 $intimacy';
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      currentName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: primary,
                        fontSize: isWeChat ? 16 : 15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: isWeChat ? 0 : 0.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            color: typing ? accent : secondary.withOpacity(0.7),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: typing ? accent : secondary,
                              fontSize: 10,
                              height: 1.1,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }


  /// 放大查看 AI 当前完整内心状态
  void _showFullStatus(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final colorScheme = Theme.of(ctx).colorScheme;
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final name = _displayName ?? 'TA';
        return Container(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: colorScheme.onSurfaceVariant.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Text(
                  '$name 此刻的内心',
                  style: TextStyle(
                    fontSize: 12,
                    letterSpacing: 1,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                // 大号 emoji
                Container(
                  width: 88,
                  height: 88,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withOpacity(0.08),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    _turnEmoji,
                    style: const TextStyle(fontSize: 44, height: 1),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  _turnEmotion,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                // 情绪强度进度条
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: _turnIntensity.clamp(0.0, 1.0),
                    minHeight: 6,
                    backgroundColor: colorScheme.surfaceContainerHighest,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '情绪强度 ${(_turnIntensity * 100).round()}%',
                  style: TextStyle(
                    fontSize: 11,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withOpacity(0.05)
                        : Colors.black.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    _turnThought,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.6,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton.tonal(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('知道了'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }


  Widget _buildAppBarAvatar(String? avatarUrl, bool isDark) {
    Widget fallback() => Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
          ),
          child: Icon(
            Icons.smart_toy_rounded,
            size: 20,
            color: isDark ? Colors.white70 : Colors.grey.shade600,
          ),
        );

    final image = AvatarResolver.imageWidget(
      avatarUrl,
      width: 36,
      height: 36,
      onError: fallback,
    );
    if (image != null) return image;
    return fallback();
  }


  Widget _buildChatTitle(ColorScheme colorScheme) {
    return BlocConsumer<ChatBloc, ChatState>(
      bloc: _chatBloc,
      listenWhen: (previous, current) =>
          current is ChatIntimacyChanged ||
          current is ChatEmotionChanged ||
          current is ChatBlockedByAI ||
          current is ChatUnblockedByAI ||
          current is ChatAIObserving ||
          current is ChatTurnStateUpdated,
      listener: (context, state) {
        if (state is ChatBlockedByAI && state.chatId == widget.session.id) {
          setState(() => _isBlockedByAI = true);
        }
        if (state is ChatUnblockedByAI && state.chatId == widget.session.id) {
          setState(() => _isBlockedByAI = false);
        }
        if (state is ChatAIObserving && state.chatId == widget.session.id) {
          // setState 已移除，ChatAIObserving 由 BlocConsumer.buildWhen 处理重建
        }
        if (state is ChatTurnStateUpdated &&
            state.chatId == widget.session.id) {
          setState(() {
            _turnEmoji = state.emoji;
            _turnEmotion = state.emotion;
            _turnIntensity = state.intensity;
            _turnThought = state.thought;
          });
        }
      },
      builder: (context, state) {
        String? moodText;
        Color moodColor = colorScheme.onSurface.withOpacity(0.4);

        if (state is ChatAITyping && !_isBlockedByAI) {
          moodText = '正在输入中...';
          moodColor = colorScheme.primary;
        } else if (state is ChatAIObserving) {
          moodText = state.statusText;
          if (state.pendingCount > 0) {
            moodText += ' · 已读${state.pendingCount}条';
          }
          if (state.emotionEmoji == '生气' || state.emotionEmoji == '愤怒') {
            moodColor = Colors.red.shade400;
          } else if (state.emotionEmoji == '难过' || state.emotionEmoji == '伤心') {
            moodColor = Colors.blueGrey.shade400;
          } else if (state.emotionEmoji == '焦虑' || state.emotionEmoji == '紧张') {
            moodColor = Colors.amber.shade600;
          } else {
            moodColor = Colors.orange.shade400;
          }
        } else if (_isBlockedByAI) {
          moodText = '已拉黑你';
          moodColor = Colors.red.shade300;
        }

        if (moodText == null) return const SizedBox.shrink();

        return AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 300),
          style: TextStyle(fontSize: 12, color: moodColor),
          child: Text(moodText, overflow: TextOverflow.ellipsis),
        );
      },
    );
  }


  void _showFullTurnState() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('TA 的当前状态',
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      )),
              const SizedBox(height: 12),
              Text('情绪：$_turnEmotion'),
              if (_turnIntensity > 0)
                Text('强度：${(_turnIntensity * 100).round()}%'),
              const SizedBox(height: 12),
              Text(_turnThought,
                  style: Theme.of(ctx).textTheme.bodyLarge?.copyWith(
                        height: 1.6,
                      )),
            ],
          ),
        ),
      ),
    );
  }


  PreferredSizeWidget _buildJumpedAppBar(ColorScheme colorScheme) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentName = _displayName ??
        _currentSession?.aiCharacterName ??
        widget.session.aiCharacterName;
    final currentAvatar =
        _currentSession?.aiCharacterAvatar ?? widget.session.aiCharacterAvatar;
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: _returnToSearchResults,
      ),
      title: _buildCompactChatTitle(
        colorScheme,
        isDark,
        currentName,
        currentAvatar,
      ),
      titleSpacing: 0,
      centerTitle: false,
      elevation: 0,
      actions: [
        IconButton(
          icon: const Icon(Icons.search),
          tooltip: '搜索聊天记录',
          onPressed: _returnToSearchResults,
        ),
      ],
    );
  }


  PreferredSizeWidget _buildSearchAppBar(ColorScheme colorScheme) {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () {
          setState(() {
            _isSearching = false;
            _searchQuery = '';
            _searchResults = [];
            _searchController.clear();
          });
        },
      ),
      title: TextField(
        controller: _searchController,
        focusNode: _searchFocusNode,
        autofocus: true,
        decoration: InputDecoration(
          hintText: '搜索聊天记录',
          hintStyle: TextStyle(color: colorScheme.onSurface.withOpacity(0.4)),
          border: InputBorder.none,
        ),
        style: TextStyle(fontSize: 16, color: colorScheme.onSurface),
        onChanged: (v) {
          setState(() => _searchQuery = v);
          _performSearch(v);
        },
      ),
      elevation: 0,
      actions: [
        if (_searchQuery.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: () {
              setState(() {
                _searchQuery = '';
                _searchResults = [];
                _searchController.clear();
              });
              _searchFocusNode.requestFocus();
            },
          ),
      ],
    );
  }

}
