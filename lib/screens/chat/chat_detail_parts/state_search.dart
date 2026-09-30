// 搜索与跳转（拆分生成，同库 part）
part of '../chat_detail_screen.dart';

mixin _StateSearch on State<ChatDetailScreen>, _StateCore, _StateLoadCore, _StateSelection, _StateSideStory, _StateVoice, _StateSendInput, _StateMoney {
  void _performSearch(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _searchTotalCount = 0;
        _searchHasMore = false;
      });
      return;
    }
    setState(() {
      _searchLoading = true;
      _searchResults = [];
      _searchTotalCount = 0;
      _searchHasMore = false;
    });
    try {
      final storage = RepositoryProvider.of<LocalStorageRepository>(context);
      final results = await storage.searchChatMessages(
        widget.session.id,
        query,
        limit: _searchPageSize,
        offset: 0,
      );
      final totalCount =
          await storage.countSearchMessages(widget.session.id, query);
      if (mounted)
        setState(() {
          _searchResults = results;
          _searchTotalCount = totalCount;
          _searchHasMore = results.length < totalCount;
        });
    } catch (_) {}
    if (mounted) setState(() => _searchLoading = false);
  }


  void _loadMoreSearchResults() async {
    if (_searchLoadingMore || !_searchHasMore) return;
    setState(() => _searchLoadingMore = true);
    try {
      final storage = RepositoryProvider.of<LocalStorageRepository>(context);
      final more = await storage.searchChatMessages(
        widget.session.id,
        _searchQuery,
        limit: _searchPageSize,
        offset: _searchResults.length,
      );
      if (mounted)
        setState(() {
          _searchResults = [..._searchResults, ...more];
          _searchHasMore = _searchResults.length < _searchTotalCount;
        });
    } catch (_) {}
    if (mounted) setState(() => _searchLoadingMore = false);
  }


  /// 跳转到指定消息（搜索结果点击 / 收藏页打开会话后自动定位，都走这里）。
  ///
  /// 关键点：外部入口（收藏页）传入的 `targetMessage` 来自**另一套查询**
  /// （全库扫 isBookmark），它的对象与本会话当前缓存里的同 id 消息不是同一实例，
  /// 内容也可能已被编辑。所以定位一律以 **id** 为准，不依赖对象相等。
  void _jumpToMessage(ChatMessage targetMessage) {
    final preservedResults = List<ChatMessage>.from(_searchResults);
    final preservedQuery = _searchQuery;
    final targetId = targetMessage.id;
    final isLoaded =
        _cachedMessages.any((message) => message.id == targetId);

    setState(() {
      _isSearching = false;
      _searchQuery = '';
      _searchController.clear();
      _isJumpedToMessage = true;
      _jumpedToMessage = targetMessage;
      _pendingJumpTarget = isLoaded ? null : targetMessage;
      _preservedSearchResults = preservedResults;
      _preservedSearchQuery = preservedQuery;
      // 定位后不要再被「自动滚到底部」抢走，否则会闪一下再跳回去
      _userScrolledUp = true;
    });

    if (isLoaded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _scrollToTargetMessage(targetMessage);
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('正在加载目标消息位置...'),
          duration: Duration(seconds: 1),
        ),
      );
      // 收藏消息可能远在历史深处：直接按 id 取窗口，而不是一页页上翻
      _chatBloc.add(ChatLoadUntilMessage(
        chatId: widget.session.id,
        messageId: targetId,
      ));
    }

    setState(() => _highlightedMessageId = targetId);
    _highlightTimer?.cancel();
    _highlightTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _highlightedMessageId = null);
    });
  }


  /// 在当前消息列表里按 id 找消息。定位一律以 id 为准：
  /// 外部入口（收藏页）传进来的 ChatMessage 来自全库扫描，与本会话缓存里的
  /// 同 id 对象不是同一实例，内容也可能已被编辑，对象相等不可靠。
  ChatMessage? _findMessageById(List<ChatMessage> list, String id) {
    for (final m in list) {
      if (m.id == id) return m;
    }
    return null;
  }

  /// 定位到目标消息。[target] 为 null 时退化到 [_jumpedToMessage] 再退化到
  /// 按 id 查缓存；都拿不到就说明数据窗口没覆盖到（理论上不会，因为 bloc 侧
  /// 已按 id 取窗口），此时静默返回而不是弹 Toast 刷屏。
  void _scrollToTargetMessage(ChatMessage? target) {
    if (!_scrollController.hasClients) {
      // 列表尚未 layout，下一帧再试
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollToTargetMessage(target);
      });
      return;
    }

    final targetId = target?.id ?? _jumpedToMessage?.id;
    if (targetId == null) return;

    final messages = _cachedMessages;
    final targetIndex = messages.indexWhere((m) => m.id == targetId);

    if (targetIndex == -1) {
      // 仍不在缓存：请求窗口，而不是让用户自己上滑（收藏跳转必经此路径）。
      // 用 id 而非 target.id —— target 可能为 null（见方法签名说明）。
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('正在加载目标消息位置...'),
          duration: Duration(seconds: 1),
        ),
      );
      setState(() => _pendingJumpTarget = _findMessageById(messages, targetId) ?? target ?? _jumpedToMessage);
      _chatBloc.add(ChatLoadUntilMessage(
        chatId: widget.session.id,
        messageId: targetId,
      ));
      return;
    }

    // 优先：GlobalKey 已挂载 → ensureVisible 精准定位
    final key = _messageKeys[targetId];
    final targetContext = key?.currentContext;
    if (targetContext != null) {
      Scrollable.ensureVisible(
        targetContext,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOut,
        alignment: 0.5,
      );
      return;
    }

    // 次选：按 reverse 列表索引估算 offset（消息高度差异大时仍可能偏）
    // reverse:true 时 index0 = 最新；目标在正序列表的 targetIndex
    // → ListView index ≈ messages.length - 1 - targetIndex（+ 上滑提示位）
    final itemsNewerThanTarget =
        messages.length - 1 - targetIndex + (_hasMoreMessages ? 1 : 0);
    final averageItemHeight = messages.length > 1
        ? (_scrollController.position.maxScrollExtent /
                (messages.length - 1 + (_hasMoreMessages ? 1 : 0)))
            .clamp(72.0, 320.0)
        : 96.0;
    final estimatedOffset = (itemsNewerThanTarget * averageItemHeight)
        .clamp(0.0, _scrollController.position.maxScrollExtent);

    _scrollController.animateTo(
      estimatedOffset,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );

    // 大列表上 ensureVisible 常在首帧拿不到 context：多轮重试
    void retryEnsure(int attempt) {
      if (!mounted || attempt > 6) return;
      final ctx = _messageKeys[targetId]?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeInOut,
          alignment: 0.5,
        );
        return;
      }
      // context 仍不存在：按同样公式再微调一次 offset
      if (_scrollController.hasClients) {
        final off = (itemsNewerThanTarget * averageItemHeight)
            .clamp(0.0, _scrollController.position.maxScrollExtent);
        _scrollController.jumpTo(off);
      }
      Timer(Duration(milliseconds: 120 + attempt * 80), () {
        if (mounted) retryEnsure(attempt + 1);
      });
    }

    Timer(const Duration(milliseconds: 280), () {
      if (mounted) retryEnsure(0);
    });
  }


  void _returnToSearchResults() {
    setState(() {
      _isJumpedToMessage = false;
      _jumpedToMessage = null;
      _isSearching = true;
      _searchQuery = _preservedSearchQuery;
      _searchResults = _preservedSearchResults;
      _searchController.text = _preservedSearchQuery;
    });
    _searchFocusNode.requestFocus();
  }


  Widget _buildSearchResults(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final authState = context.read<AuthBloc>().state;
    final userAvatarUrl =
        authState is AuthAuthenticated ? authState.user.avatarUrl : null;
    final currentAvatar =
        _currentSession?.aiCharacterAvatar ?? widget.session.aiCharacterAvatar;
    if (_searchLoading) return const Center(child: CircularProgressIndicator());
    if (_searchResults.isEmpty)
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.search_off,
              size: 48, color: colorScheme.onSurface.withOpacity(0.2)),
          const SizedBox(height: 12),
          Text('未找到相关消息',
              style: TextStyle(color: colorScheme.onSurface.withOpacity(0.4))),
        ]),
      );
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            _searchHasMore
                ? '已加载${_searchResults.length} 条，共$_searchTotalCount 条结果'
                : '找到 $_searchTotalCount 条结果',
            style: TextStyle(
                fontSize: 12, color: colorScheme.onSurface.withOpacity(0.5)),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: _searchResults.length + (_searchHasMore ? 1 : 0),
            itemBuilder: (context, index) {
              // "Load more" button at the bottom
              if (index == _searchResults.length) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: _searchLoadingMore
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : GestureDetector(
                            onTap: _loadMoreSearchResults,
                            child: Text(
                              '加载更多',
                              style: TextStyle(
                                fontSize: 13,
                                color: colorScheme.primary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                  ),
                );
              }
              final msg = _searchResults[index];
              final senderName = msg.isFromAI
                  ? ((msg.senderName ?? '').isNotEmpty
                      ? (msg.senderName ?? 'AI')
                      : 'AI')
                  : '用户';
              return InkWell(
                onTap: () => _jumpToMessage(msg),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 4),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: msg.isFromAI
                            ? Colors.purple.withOpacity(0.1)
                            : Colors.blue.withOpacity(0.1),
                      ),
                      child: ClipOval(
                        child: _buildSearchResultAvatar(
                          msg.isFromAI ? currentAvatar : userAvatarUrl,
                          36.0,
                          msg.isFromAI,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Text(senderName,
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color:
                                      colorScheme.onSurface.withOpacity(0.6))),
                          const Spacer(),
                          Text(DateFormat('MM/dd HH:mm').format(msg.createdAt),
                              style: TextStyle(
                                  fontSize: 11,
                                  color:
                                      colorScheme.onSurface.withOpacity(0.35))),
                        ]),
                        const SizedBox(height: 3),
                        _buildHighlightedText(
                            msg.content, _searchQuery, colorScheme),
                      ],
                    )),
                  ]),
                ),
              );
            },
          ),
        ),
      ],
    );
  }


  Widget _buildSearchResultAvatar(String? avatarUrl, double size, bool isAI) {
    Widget fallback() => Icon(
          isAI ? Icons.smart_toy_outlined : Icons.person_outline,
          size: size * 0.5,
          color: isAI ? Colors.purple : Colors.blue,
        );

    final image = AvatarResolver.imageWidget(
      avatarUrl,
      width: size,
      height: size,
      onError: fallback,
    );
    if (image != null) return image;
    return fallback();
  }


  Widget _buildHighlightedText(
      String text, String query, ColorScheme colorScheme) {
    if (query.isEmpty) {
      return Text(text,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontSize: 14, color: colorScheme.onSurface.withOpacity(0.7)));
    }
    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final spans = <TextSpan>[];
    int start = 0;
    while (true) {
      final idx = lowerText.indexOf(lowerQuery, start);
      if (idx == -1) {
        if (start < text.length) {
          spans.add(TextSpan(
              text: text.substring(start),
              style: TextStyle(
                  fontSize: 14,
                  color: colorScheme.onSurface.withOpacity(0.7))));
        }
        break;
      }
      if (idx > start) {
        spans.add(TextSpan(
            text: text.substring(start, idx),
            style: TextStyle(
                fontSize: 14, color: colorScheme.onSurface.withOpacity(0.7))));
      }
      spans.add(TextSpan(
          text: text.substring(idx, idx + query.length),
          style: TextStyle(
              fontSize: 14,
              color: colorScheme.primary,
              fontWeight: FontWeight.w600,
              backgroundColor: colorScheme.primary.withOpacity(0.15))));
      start = idx + query.length;
    }
    return RichText(
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(children: spans),
    );
  }

}
