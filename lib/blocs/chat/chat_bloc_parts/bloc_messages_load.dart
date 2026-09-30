// 会话与消息加载（拆分生成，同库 part）
part of '../chat_bloc.dart';

mixin _BlocMessagesLoad on Bloc<ChatEvent, ChatState>, ChatBlocUtils, ChatBlocIntimacy, _ChatBlocCore, _BlocCallsBase, _BlocAiBridge, _BlocMemoryIntimacy, _BlocPromptContext, _BlocTurnState, _BlocBtAgent, _BlocNovel {
  Future<void> _onLoadSessions(
    ChatLoadSessions event,
    Emitter<ChatState> emit,
  ) async {
    emit(ChatLoading());
    try {
      final sessions = await _storage.getChatSessions(event.userId);
      emit(ChatSessionsLoaded(sessions));
    } catch (e) {
      emit(ChatError(e.toString()));
    }
  }


  Future<void> _onLoadMessages(
    ChatLoadMessages event,
    Emitter<ChatState> emit,
  ) async {
    try {
      var page =
          await _storage.getChatMessages(event.chatId, limit: 51, offset: 0);
      // 历史数据修复：AI 已回复过的用户消息仍显示「未读」时纠正
      // getChatMessages 返回升序（旧→新），展示的是「最新 50 条」= 末尾 50 条。
      final healed = await _healUnreadUserMessages(event.chatId,
          page.length > 50 ? page.sublist(page.length - 50) : page);
      if (healed) {
        page =
            await _storage.getChatMessages(event.chatId, limit: 51, offset: 0);
      }
      // 多取一条判断是否还有更早历史，避免恰好 50 条时误判「还有更多」。
      // 列表升序（旧→新）：保留「最新 50 条」= 去掉最旧的首条，绝不能截掉最新一条。
      final hasMore = page.length > 50;
      final messages = hasMore ? page.sublist(page.length - 50) : page;
      _loadedOffsets[event.chatId] = messages.length;
      _hasMoreByChat[event.chatId] = hasMore;
      emit(ChatMessagesLoaded(messages, hasMore: hasMore));
      // 懒触发艾宾浩斯每日维护（20h 节流，unawaited，复活单聊衰减调度）
      unawaited(_runMemoryMaintenanceQuietly(event.chatId));
    } catch (e) {
      emit(ChatError(e.toString()));
    }
  }


  /// 从收藏/搜索等外部入口按 id 定位。
  ///
  /// ★ 与 `_onLoadMessages` 的区别（收藏跳转失效的历史根因）：
  /// `_onLoadMessages` 永远取「最新 50 条」。所以从收藏页进来的消息若在更早的
  /// 历史里，首屏根本不含它；此时必须走本方法按 id 取窗口，否则页面只能停在
  /// 最新位置，看起来就是「跳转没反应」。
  ///
  /// 取回窗口后必须 **emit 一个与首屏不同的状态**，UI 侧的 listener 才会跑。
  /// `ChatMessagesLoaded` 走 Equatable 比较，消息列表内容完全相同时新旧状态
  /// `==` 成立，BlocConsumer 的 listenWhen/buildWhen 都不会被触发 —— 这正是
  /// 「打开聊天页毫无反应」的第二个原因。
  /// 因此这里额外携带 `jumpToMessageId`，与普通加载产生可区分的状态实例。
  Future<void> _onLoadUntilMessage(
    ChatLoadUntilMessage event,
    Emitter<ChatState> emit,
  ) async {
    if (_loadingMore.contains(event.chatId)) return;
    _loadingMore.add(event.chatId);
    try {
      // 大历史量：SQL 算 offset + 一次取窗口，替代 while 50 条翻页
      // （收藏跳转 / 搜索定位在十万级消息下旧实现会极慢甚至加载失败）
      final window = await _storage.getChatMessagesAroundId(
        chatId: event.chatId,
        messageId: event.messageId,
        before: 40,
        after: 20,
      );

      final exists = window.any((m) => m.id == event.messageId);
      // 与现有列表合并去重，保持时间正序
      final existing = state is ChatMessagesLoaded
          ? List<ChatMessage>.from(
              (state as ChatMessagesLoaded).messages)
          : <ChatMessage>[];
      final byId = <String, ChatMessage>{
        for (final m in existing) m.id: m,
        for (final m in window) m.id: m,
      };
      final merged = byId.values.toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

      // 是否还能再往更旧加载：窗口里最旧是否等于全局更旧边界
      // 简化：若窗口条数达到请求上限则认为可能还有更旧
      final hasMore = window.length >= 60 || existing.isNotEmpty;

      LogService.instance.i(
        'Bloc',
        '_onLoadUntilMessage: target=${event.messageId}, '
        'window=${window.length}, exists=$exists, total=${merged.length}',
        chatId: event.chatId,
      );
      _loadedOffsets[event.chatId] = merged.length;
      _hasMoreByChat[event.chatId] = hasMore;
      emit(ChatMessagesLoaded(
        merged,
        hasMore: hasMore,
        jumpToMessageId: event.messageId,
      ));

      if (!exists) {
        LogService.instance.w(
          'Bloc',
          '_onLoadUntilMessage: 目标消息不在窗口中 id=${event.messageId}',
          chatId: event.chatId,
        );
      }
    } catch (e) {
      LogService.instance.e(
        'Bloc',
        '_onLoadUntilMessage failed: $e',
        chatId: event.chatId,
      );
    } finally {
      _loadingMore.remove(event.chatId);
    }
  }


  /// 若某条用户消息之后已有 AI 回复，则标为已读（修复历史「未读」残留）
  Future<bool> _healUnreadUserMessages(
    String chatId,
    List<ChatMessage> messages,
  ) async {
    if (messages.isEmpty) return false;
    final hasLaterAiReply = messages.any((m) => m.isFromAI && !m.isSystem);
    if (!hasLaterAiReply) return false;

    DateTime? lastAiAt;
    for (var i = messages.length - 1; i >= 0; i--) {
      final m = messages[i];
      if (m.isFromAI && !m.isSystem) {
        lastAiAt = m.createdAt;
        break;
      }
    }
    if (lastAiAt == null) return false;

    var changed = false;
    final now = DateTime.now();
    for (final msg in messages) {
      if (!msg.isUser || msg.isSystem) continue;
      if (msg.status == MessageStatus.read) continue;
      // 用户消息时间不晚于最后一条 AI 回复 → AI 已看过并回过
      if (!msg.createdAt.isAfter(lastAiAt)) {
        await _storage.saveChatMessage(msg.copyWith(
          status: MessageStatus.read,
          readAt: msg.readAt ?? now,
        ));
        changed = true;
      }
    }
    return changed;
  }


  /// 从当前状态提取已展示的消息列表，供分页拼接使用。
  /// 覆盖所有携带 messages 的状态，避免强转 ChatMessagesLoaded 抛 TypeError。
  List<ChatMessage> _currentVisibleMessages() {
    final s = state;
    if (s is ChatMessagesLoaded) return s.messages;
    if (s is ChatTransferStatusUpdated) return s.messages;
    if (s is ChatAITyping) return s.messages;
    if (s is ChatAIStreaming) return s.messages;
    if (s is ChatAIObserving) return s.messages;
    if (s is ChatBlockedByAI) return s.messages;
    if (s is ChatUnblockedByAI) return s.messages;
    if (s is ChatAICoinsSent) return s.messages;
    return const [];
  }


  Future<void> _onLoadMoreMessages(
    ChatLoadMoreMessages event,
    Emitter<ChatState> emit,
  ) async {
    if (_loadingMore.contains(event.chatId)) return;
    _loadingMore.add(event.chatId);
    try {
      final currentOffset = _loadedOffsets[event.chatId] ?? 0;
      // 多取一条判断是否还有更早历史
      final page = await _storage.getChatMessages(
        event.chatId,
        limit: 51,
        offset: currentOffset,
      );
      // 从任意「含消息列表」的状态取当前已展示消息，避免 AI 输入/流式期间
      // 直接强转 ChatMessagesLoaded 抛 TypeError。
      final currentMessages = _currentVisibleMessages();
      if (page.isEmpty) {
        _hasMoreByChat[event.chatId] = false;
        if (currentMessages.isNotEmpty) {
          emit(ChatMessagesLoaded(currentMessages, hasMore: false));
        }
        return;
      }
      final hasMore = page.length > 50;
      // 列表升序（旧→新）：保留本批「最新 50 条」（去掉最旧首条），与已展示消息无缝衔接。
      final olderMessages = hasMore ? page.sublist(page.length - 50) : page;
      final allMessages = [...olderMessages, ...currentMessages];
      _loadedOffsets[event.chatId] = currentOffset + olderMessages.length;
      _hasMoreByChat[event.chatId] = hasMore;
      LogService.instance.i('Bloc',
          '_onLoadMoreMessages: +${olderMessages.length} msgs, total=${allMessages.length}, hasMore=$hasMore',
          chatId: event.chatId);
      emit(ChatMessagesLoaded(allMessages, hasMore: hasMore));
    } catch (e) {
      LogService.instance
          .e('Bloc', '_onLoadMoreMessages failed: $e', chatId: event.chatId);
    } finally {
      _loadingMore.remove(event.chatId);
    }
  }


}
