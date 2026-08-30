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


  void _jumpToMessage(ChatMessage targetMessage) {
    final preservedResults = List<ChatMessage>.from(_searchResults);
    final preservedQuery = _searchQuery;
    final isLoaded =
        _cachedMessages.any((message) => message.id == targetMessage.id);

    setState(() {
      _isSearching = false;
      _searchQuery = '';
      _searchController.clear();
      _isJumpedToMessage = true;
      _jumpedToMessage = targetMessage;
      _pendingJumpTarget = isLoaded ? null : targetMessage;
      _preservedSearchResults = preservedResults;
      _preservedSearchQuery = preservedQuery;
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
      _chatBloc.add(ChatLoadUntilMessage(
        chatId: widget.session.id,
        messageId: targetMessage.id,
      ));
    }

    setState(() => _highlightedMessageId = targetMessage.id);
    _highlightTimer?.cancel();
    _highlightTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _highlightedMessageId = null);
    });
  }


  void _scrollToTargetMessage(ChatMessage target) {
    if (!_scrollController.hasClients) return;

    final messages = _cachedMessages;
    final targetIndex = messages.indexWhere((m) => m.id == target.id);

    if (targetIndex == -1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('消息未加载，请上滑加载更多历史消息后再试'),
            duration: Duration(seconds: 2)),
      );
      return;
    }

    final key = _messageKeys[target.id];
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

    final itemsAfterTarget = messages.length - 1 - targetIndex;
    final averageItemHeight = messages.length > 1
        ? (_scrollController.position.maxScrollExtent / (messages.length - 1))
            .clamp(80.0, 260.0)
        : 80.0;
    // reverse:true means index 0 is the newest item. Estimate from the target
    // position, then let ensureVisible correct the final offset after layout.
    final estimatedOffset = itemsAfterTarget * averageItemHeight;
    final clampedOffset = estimatedOffset.clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );

    _scrollController.animateTo(
      clampedOffset,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
    Timer(const Duration(milliseconds: 420), () {
      if (!mounted) return;
      final retryContext = _messageKeys[target.id]?.currentContext;
      if (retryContext != null) {
        Scrollable.ensureVisible(
          retryContext,
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeInOut,
          alignment: 0.5,
        );
      }
    });
    Timer(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      final retryContext = _messageKeys[target.id]?.currentContext;
      if (retryContext != null) {
        Scrollable.ensureVisible(
          retryContext,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          alignment: 0.5,
        );
      }
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
