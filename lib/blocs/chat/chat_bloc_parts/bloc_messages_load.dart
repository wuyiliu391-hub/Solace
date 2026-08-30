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


  Future<void> _onLoadUntilMessage(
    ChatLoadUntilMessage event,
    Emitter<ChatState> emit,
  ) async {
    if (_loadingMore.contains(event.chatId)) return;
    _loadingMore.add(event.chatId);
    try {
      List<ChatMessage> allMessages;
      if (state is ChatMessagesLoaded) {
        allMessages =
            List<ChatMessage>.from((state as ChatMessagesLoaded).messages);
      } else {
        allMessages = await _storage.getChatMessages(
          event.chatId,
          limit: 50,
          offset: 0,
        );
      }

      var currentOffset = _loadedOffsets[event.chatId] ?? allMessages.length;
      var hasMore = allMessages.length >= 50;

      while (!allMessages.any((m) => m.id == event.messageId) && hasMore) {
        final olderMessages = await _storage.getChatMessages(
          event.chatId,
          limit: 50,
          offset: currentOffset,
        );
        if (olderMessages.isEmpty) {
          hasMore = false;
          break;
        }
        allMessages = [...olderMessages, ...allMessages];
        currentOffset += olderMessages.length;
        hasMore = olderMessages.length >= 50;
      }

      _loadedOffsets[event.chatId] = currentOffset;
      _hasMoreByChat[event.chatId] = hasMore;
      LogService.instance.i(
        'Bloc',
        '_onLoadUntilMessage: target=${event.messageId}, total=${allMessages.length}, hasMore=$hasMore',
        chatId: event.chatId,
      );
      emit(ChatMessagesLoaded(allMessages, hasMore: hasMore));
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

}
