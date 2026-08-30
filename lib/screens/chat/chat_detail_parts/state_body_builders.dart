// 背景/空态构建（拆分生成，同库 part）
part of '../chat_detail_screen.dart';

mixin _StateBodyBuilders on State<ChatDetailScreen>, _StateCore, _StateLoadCore, _StateSelection, _StateSideStory, _StateVoice, _StateSendInput, _StateMoney, _StateSearch, _StateMessageActions, _StateNavDialogs, _StateAppBarBuilders, _StateListInputBuilders {
  Widget _buildBody(ColorScheme colorScheme) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final content = Column(
      children: [
        if (_isSideStory) _buildSideStoryBanner(colorScheme, isDark),
        Expanded(
          child: Stack(
            children: [
              BlocConsumer<ChatBloc, ChatState>(
                bloc: _chatBloc,
                buildWhen: (previous, current) {
                  // 仅当消息真正变化时才重建列表，避免每轮状态跳跃都触发全量刷新
                  if (current is ChatAIStreaming) return true;
                  if (current is ChatTransferStatusUpdated) return true;
                  if (current is ChatMessagesLoaded &&
                      previous is ChatMessagesLoaded) {
                    // P3: 消息数量或内容变化均需重建（支持编辑/删除后的 UI 刷新）
                    if (current.messages.length != previous.messages.length)
                      return true;
                    for (var i = 0; i < current.messages.length; i++) {
                      if (i >= previous.messages.length) return true;
                      if (current.messages[i].content !=
                              previous.messages[i].content ||
                          current.messages[i].isBookmark !=
                              previous.messages[i].isBookmark) {
                        return true;
                      }
                    }
                    return false;
                  }
                  return previous.runtimeType != current.runtimeType;
                },
                listenWhen: (previous, current) =>
                    previous?.runtimeType != current.runtimeType ||
                    current is ChatAITyping ||
                    current is ChatError ||
                    current is ChatAIObserving ||
                    (current is ChatMessagesLoaded &&
                        previous is ChatMessagesLoaded &&
                        current.messages.length != previous.messages.length),
                listener: (context, state) {
                  LogService.instance.d('UI', 'Listener: ${state.runtimeType}',
                      chatId: widget.session.id);
                  if (state is ChatError) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(state.message),
                        duration: const Duration(seconds: 3),
                      ),
                    );
                  }
                  if (state is ChatAITyping) {
                    if (!_isBlockedByAI) {
                      _isAiTypingNotifier.value = true;
                    }
                  }
                  if (state is ChatAIStreaming) {
                    if (!_isBlockedByAI) {
                      _isAiTypingNotifier.value = true;
                    }
                    // 流式滚动节流：每 400ms 最多滚一次，避免每 chunk 跳跃
                    final now = DateTime.now().millisecondsSinceEpoch;
                    if (now - _lastStreamingScrollTime > 400) {
                      _lastStreamingScrollTime = now;
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) _scrollToBottom(force: false);
                      });
                    }
                  }
                  if (state is ChatMessagesLoaded || state is ChatError) {
                    if (_isAiTypingNotifier.value)
                      _isAiTypingNotifier.value = false;
                  }
                  if (state is ChatAIObserving) {
                    if (_isAiTypingNotifier.value)
                      _isAiTypingNotifier.value = false;
                  }
                  if (state is ChatPersonaEvolved &&
                      state.chatId == widget.session.id) {
                    _showPersonaEvolutionNotice(state);
                  }
                  if (state is ChatIntimacyChanged &&
                      state.chatId == widget.session.id) {
                    setState(() {
                      _currentSession = (_currentSession ?? widget.session)
                          .copyWith(intimacyLevel: state.newLevel);
                    });
                  }
                  if (state is ChatTurnStateUpdated &&
                      state.chatId == widget.session.id) {
                    setState(() {
                      _turnEmotion = state.emotion;
                      _turnIntensity = state.intensity;
                      _turnThought = state.thought;
                    });
                  }
                  if (state is ChatMessagesLoaded) {
                    _hasMoreMessages = state.hasMore;
                    // 从收藏/搜索等外部入口打开时，首帧消息加载后自动定位并高亮目标消息（仅一次）
                    if (widget.initialJumpToMessage != null &&
                        !_didInitialJump) {
                      _didInitialJump = true;
                      final target = widget.initialJumpToMessage!;
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) _jumpToMessage(target);
                      });
                    }
                    if (_isLoadingMore) {
                      _isLoadingMore = false;
                    } else {
                      _reloadSessionStatus();
                    }
                    final pendingTarget = _pendingJumpTarget;
                    if (pendingTarget != null) {
                      final targetLoaded =
                          state.messages.any((m) => m.id == pendingTarget.id);
                      if (targetLoaded) {
                        _pendingJumpTarget = null;
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) _scrollToTargetMessage(pendingTarget);
                        });
                      } else if (!state.hasMore) {
                        _pendingJumpTarget = null;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('没有找到目标消息位置'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                    }
                  }
                  // 强制刷新UI（已由 BlocConsumer.buildWhen 控制重建时机）
                  if ((state is ChatMessagesLoaded ||
                          state is ChatTransferStatusUpdated) &&
                      mounted) {
                    final wasLoadingMore = _isLoadingMore;
                    if (!wasLoadingMore) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted && !_isJumpedToMessage) {
                          _scrollToBottom(force: false);
                        }
                      });
                    }
                  }
                  if (state is ChatMessagesLoaded &&
                      _cachedMessages.isNotEmpty &&
                      state.messages.length > _cachedMessages.length &&
                      _lastMessageCount > 0 &&
                      _userScrolledUp &&
                      mounted) {
                    _showNewMessageBannerNotifier.value = true;
                  }
                },
                builder: (context, state) {
                  debugPrint(
                      '[SYNC] BlocBuilder rebuild: type=${state.runtimeType}, msgCount=${state is ChatMessagesLoaded ? state.messages.length : (state is ChatTransferStatusUpdated ? state.messages.length : (state is ChatAITyping ? state.messages.length : (state is ChatAIObserving ? state.messages.length : 0)))}');
                  // 统一更新缓存：任何含消息列表的状态都同步到 _cachedMessages
                  if (state is ChatMessagesLoaded) {
                    _cachedMessages = state.messages;
                    _lastMessageCount = state.messages.length;
                    _cancelLoadingFallbackTimer();
                  } else if (state is ChatTransferStatusUpdated) {
                    _cachedMessages = state.messages;
                    _lastMessageCount = state.messages.length;
                  } else if (state is ChatAITyping &&
                      state.messages.isNotEmpty) {
                    _cachedMessages = state.messages;
                  } else if (state is ChatAIObserving &&
                      state.messages.isNotEmpty) {
                    _cachedMessages = state.messages;
                  }

                  // 搜索模式
                  if (_isSearching && _searchQuery.isNotEmpty) {
                    return _buildSearchResults(context);
                  }

                  // 优先级：消息加载完成 - 直接使用 state 中的完整消息列表
                  if (state is ChatMessagesLoaded) {
                    if (state.messages.isEmpty) return _buildEmptyChat(context);
                    _logTransferStatus(state.messages, 'ChatMessagesLoaded');
                    return _buildMessageList(context, state.messages,
                        showTyping: false);
                  }

                  // 优先级：转账状态局部更新 - 同样有完整消息列表
                  if (state is ChatTransferStatusUpdated) {
                    if (state.messages.isEmpty) return _buildEmptyChat(context);
                    _logTransferStatus(
                        state.messages, 'ChatTransferStatusUpdated');
                    return _buildMessageList(context, state.messages,
                        showTyping: false);
                  }

                  // 优先级：AI正在输入 - 显示已有消息 + 输入指示器
                  if (state is ChatAITyping) {
                    if (state.messages.isNotEmpty) {
                      return _buildMessageList(context, state.messages,
                          showTyping: true);
                    }
                    if (_cachedMessages.isNotEmpty) {
                      return _buildMessageList(context, _cachedMessages,
                          showTyping: true);
                    }
                  }

                  // 优先级：AI流式输出 - 显示已有消息 + 流式气泡
                  if (state is ChatAIStreaming) {
                    final baseMessages = state.messages.isNotEmpty
                        ? state.messages
                        : _cachedMessages;
                    return _buildMessageListWithStreaming(context, baseMessages,
                        state.streamingText, state.characterName,
                        reasoning: state.reasoning);
                  }

                  if (state is ChatAIObserving) {
                    if (state.messages.isNotEmpty) {
                      return _buildMessageList(context, state.messages,
                          showTyping: false);
                    }
                    if (_cachedMessages.isNotEmpty) {
                      return _buildMessageList(context, _cachedMessages,
                          showTyping: false);
                    }
                  }

                  // 优先级：错误状态回退
                  if (state is ChatError) {
                    if (_cachedMessages.isNotEmpty) {
                      return _buildMessageList(context, _cachedMessages,
                          showTyping: false);
                    }
                    return _buildMessageListFromStorage(context);
                  }

                  // 优先级：备用方案（超时后显示已有缓存或从数据库直读）
                  if (_forceUseFallback) {
                    if (_cachedMessages.isNotEmpty) {
                      return _buildMessageList(context, _cachedMessages,
                          showTyping: false);
                    }
                    return _buildMessageListFromStorage(context);
                  }

                  // 优先级：初始化加载中
                  return _buildMessageListFromStorage(context);
                },
              ),
              ValueListenableBuilder<bool>(
                valueListenable: _showNewMessageBannerNotifier,
                builder: (context, showBanner, _) {
                  if (!showBanner) return const SizedBox.shrink();
                  return Positioned(
                    top: 8,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: GestureDetector(
                        onTap: () => _scrollToBottom(force: true),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Text(
                            '新的消息',
                            style: TextStyle(
                              color: colorScheme.onPrimaryContainer,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        _buildInputArea(context),
      ],
    );

    final hasCustomBg = _currentSession?.backgroundImage != null &&
        _currentSession!.backgroundImage!.isNotEmpty;
    // 18.3.0 沉浸式：深色下总是铺氛围背景——
    // 有自定义图用图（叠暗纱保证气泡可读），否则用角色主题色渐变。
    if (hasCustomBg || isDark) {
      return Stack(
        children: [
          Positioned.fill(
            child: hasCustomBg
                ? _buildBackgroundImage(colorScheme)
                : _buildAmbientBackground(colorScheme),
          ),
          if (hasCustomBg && isDark)
            Positioned.fill(
              child: Container(color: Colors.black.withOpacity(0.25)),
            ),
          content,
        ],
      );
    }
    return content;
  }


  Widget _buildPureAiModeSidebar(ColorScheme colorScheme) {
    const orbSize = 64.0;
    const panelWidth = 214.0;
    const panelHeight = 116.0;
    const margin = 8.0;
    final storage = RepositoryProvider.of<LocalStorageRepository>(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark
        ? const Color(0xFF1F1F1F).withOpacity(0.94)
        : colorScheme.surface.withOpacity(0.96);
    final borderColor = colorScheme.outlineVariant.withOpacity(0.7);

    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final widgetWidth = _pureAiPanelExpanded ? panelWidth : orbSize;
          final widgetHeight = _pureAiPanelExpanded ? panelHeight : orbSize;
          final fallbackOffset = Offset(
            constraints.maxWidth - orbSize - 14,
            constraints.maxHeight - orbSize - 24,
          );
          final rawOffset = _pureAiOrbOffset ?? fallbackOffset;
          final maxLeft = constraints.maxWidth - widgetWidth - margin;
          final maxTop = constraints.maxHeight - widgetHeight - margin;
          final left = rawOffset.dx.clamp(
            margin,
            maxLeft < margin ? margin : maxLeft,
          );
          final top = rawOffset.dy.clamp(
            margin,
            maxTop < margin ? margin : maxTop,
          );

          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: left.toDouble(),
                top: top.toDouble(),
                width: widgetWidth,
                height: widgetHeight,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onPanUpdate: (details) {
                    final current = _pureAiOrbOffset ?? fallbackOffset;
                    setState(() {
                      _pureAiOrbOffset = Offset(
                        current.dx + details.delta.dx,
                        current.dy + details.delta.dy,
                      );
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    decoration: BoxDecoration(
                      color: surfaceColor,
                      borderRadius: BorderRadius.circular(
                        _pureAiPanelExpanded ? 14 : orbSize / 2,
                      ),
                      border: Border.all(color: borderColor, width: 0.5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(isDark ? 0.28 : 0.12),
                          blurRadius: _pureAiPanelExpanded ? 18 : 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: _pureAiPanelExpanded
                        ? ValueListenableBuilder<bool>(
                            valueListenable: storage.pureAiModeNotifier,
                            builder: (context, enabled, _) {
                              return Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(12, 10, 12, 10),
                                child: Row(
                                  children: [
                                    InkWell(
                                      borderRadius: BorderRadius.circular(20),
                                      onTap: () => setState(
                                          () => _pureAiPanelExpanded = false),
                                      child: SizedBox(
                                        width: 40,
                                        height: 40,
                                        child: Center(
                                          child: Text(
                                            'AI',
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w700,
                                              color: colorScheme.primary,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '纯AI视角模式',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: colorScheme.onSurface,
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            enabled ? '已开启' : '已关闭',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: colorScheme.onSurface
                                                  .withOpacity(0.55),
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Switch(
                                            value: enabled,
                                            onChanged: (value) =>
                                                storage.setPureAiMode(value),
                                            activeColor: colorScheme.primary,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          )
                        : InkWell(
                            borderRadius: BorderRadius.circular(orbSize / 2),
                            onTap: () =>
                                setState(() => _pureAiPanelExpanded = true),
                            child: Center(
                              child: Text(
                                'AI',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: colorScheme.primary,
                                ),
                              ),
                            ),
                          ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }


  bool _isLocalBgPath(String path) {
    final p = path.trim();
    if (p.isEmpty) return false;
    if (p.startsWith('http://') || p.startsWith('https://')) return false;
    if (p.startsWith('content://')) return false;
    return p.startsWith('/') ||
        p.contains(':\\') ||
        p.startsWith('file://') ||
        !p.contains('://');
  }


  String _normalizeBgPath(String path) {
    if (path.startsWith('file://')) {
      return Uri.parse(path).toFilePath();
    }
    return path;
  }


  Widget _buildBackgroundImage(ColorScheme colorScheme) {
    final raw = _currentSession?.backgroundImage?.trim() ?? '';
    if (raw.isEmpty) {
      return Container(color: colorScheme.surface);
    }

    final isLocal = _isLocalBgPath(raw);
    final localPath = isLocal ? _normalizeBgPath(raw) : raw;
    if (isLocal) {
      final file = File(localPath);
      if (!file.existsSync()) {
        return Container(color: colorScheme.surface);
      }
    }

    // key 绑定路径，换图后强制重建，避免 FileImage 缓存残留
    final imageProvider = isLocal
        ? FileImage(File(localPath)) as ImageProvider
        : NetworkImage(raw) as ImageProvider;

    return Container(
      key: ValueKey('chat_bg_$raw'),
      decoration: BoxDecoration(
        image: DecorationImage(
          image: imageProvider,
          fit: BoxFit.cover,
          onError: (exception, stackTrace) {},
        ),
        color: colorScheme.surface,
      ),
    );
  }


  /// 18.3.0 沉浸式默认背景：角色主题色自上而下渐隐入深夜蓝黑，
  /// 无自定义背景时的氛围铺底（对标 Shine 立绘背景的氛围感）。
  Widget _buildAmbientBackground(ColorScheme colorScheme) {
    // 微信风格：纯色底（浅色靠 Scaffold 底色，这里处理深色态）
    if (_isWeChatStyle) {
      return Container(color: WeChatColors.darkPageBackground);
    }
    final name = _displayName ??
        _currentSession?.aiCharacterName ??
        widget.session.aiCharacterName;
    final base = characterColor(name: name, cs: colorScheme);
    final hsv = HSVColor.fromColor(base);
    // 角色色压暗、降饱和后与底色混合，保证气泡文字对比度
    final top = Color.alphaBlend(
      hsv.withSaturation(0.45).withValue(0.32).toColor().withOpacity(0.9),
      ImmersiveColors.backgroundUp,
    );
    final bottom = Color.alphaBlend(
      hsv.withSaturation(0.55).withValue(0.16).toColor().withOpacity(0.85),
      ImmersiveColors.background,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [top, bottom],
          stops: const [0.0, 0.85],
        ),
      ),
    );
  }


  Widget _buildNewMessageBanner() {
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () {
        _showNewMessageBannerNotifier.value = false;
        _scrollToBottom(force: true);
      },
      child: Container(
        alignment: Alignment.center,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: colorScheme.primary,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: colorScheme.primary.withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.keyboard_arrow_down,
                  size: 18, color: Colors.white),
              const SizedBox(width: 4),
              const Text('新消息',
                  style: TextStyle(fontSize: 13, color: Colors.white)),
            ],
          ),
        ),
      ),
    );
  }


  Widget _buildErrorRetry(BuildContext context, String message) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off,
                size: 48, color: colorScheme.onSurface.withOpacity(0.3)),
            const SizedBox(height: 16),
            Text('消息加载失败',
                style: TextStyle(
                    fontSize: 16,
                    color: colorScheme.onSurface.withOpacity(0.5))),
            const SizedBox(height: 8),
            Text(message,
                style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurface.withOpacity(0.3)),
                textAlign: TextAlign.center),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () =>
                  _chatBloc.add(ChatLoadMessages(widget.session.id)),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }

}
