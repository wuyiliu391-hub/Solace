// 消息CRUD/滑动/分支（拆分生成，同库 part）
part of '../chat_bloc.dart';

mixin _BlocMessageOps on Bloc<ChatEvent, ChatState>, ChatBlocUtils, ChatBlocIntimacy, _ChatBlocCore, _BlocCallsBase, _BlocAiBridge, _BlocMemoryIntimacy, _BlocPromptContext, _BlocTurnState, _BlocBtAgent, _BlocNovel, _BlocMessagesLoad, _BlocStatusStats, _BlocBlockForgive {
  /// 右滑：切换到下一条备选回复（对标 SillyTavern swipe_right）
  Future<void> _onSwipeRight(
    ChatSwipeRight event,
    Emitter<ChatState> emit,
  ) async {
    try {
      final messages = await _storage.getChatMessages(event.chatId);
      final msgIndex = messages.indexWhere((m) => m.id == event.messageId);
      if (msgIndex == -1) return;

      final msg = messages[msgIndex];
      if (msg.swipeHistory.isEmpty ||
          msg.swipeIndex >= msg.swipeHistory.length - 1) {
        LogService.instance
            .i('Bloc', '_onSwipeRight: no more swipes', chatId: event.chatId);
        return;
      }

      final newIndex = msg.swipeIndex + 1;
      final newContent = msg.swipeHistory[newIndex];
      final updated = msg.copyWith(
        content: newContent,
        swipeIndex: newIndex,
      );
      await _storage.saveChatMessage(updated);

      final updatedMessages = await _storage.getChatMessages(event.chatId);
      emit(ChatSwiped(
        chatId: event.chatId,
        messageId: event.messageId,
        newIndex: newIndex,
        content: newContent,
      ));
      emit(ChatMessagesLoaded(updatedMessages));
    } catch (e) {
      LogService.instance
          .e('Bloc', '_onSwipeRight failed: $e', chatId: event.chatId);
    }
  }


  /// 左滑：切换到上一条备选回复（对标 SillyTavern swipe_left）
  Future<void> _onSwipeLeft(
    ChatSwipeLeft event,
    Emitter<ChatState> emit,
  ) async {
    try {
      final messages = await _storage.getChatMessages(event.chatId);
      final msgIndex = messages.indexWhere((m) => m.id == event.messageId);
      if (msgIndex == -1) return;

      final msg = messages[msgIndex];
      if (msg.swipeHistory.isEmpty || msg.swipeIndex <= 0) {
        LogService.instance
            .i('Bloc', '_onSwipeLeft: no more swipes', chatId: event.chatId);
        return;
      }

      final newIndex = msg.swipeIndex - 1;
      final newContent = msg.swipeHistory[newIndex];
      final updated = msg.copyWith(
        content: newContent,
        swipeIndex: newIndex,
      );
      await _storage.saveChatMessage(updated);

      final updatedMessages = await _storage.getChatMessages(event.chatId);
      emit(ChatSwiped(
        chatId: event.chatId,
        messageId: event.messageId,
        newIndex: newIndex,
        content: newContent,
      ));
      emit(ChatMessagesLoaded(updatedMessages));
    } catch (e) {
      LogService.instance
          .e('Bloc', '_onSwipeLeft failed: $e', chatId: event.chatId);
    }
  }

  // ═══════════════════════════════════════════════════════
  // SillyTavern 对标方法：消息操作（hide/unhide/copy/edit/delete）
  // ═══════════════════════════════════════════════════════


  /// 隐藏消息（对标 SillyTavern hideChatMessageRange）
  /// 隐藏的消息在构建 prompt 时被排除
  Future<void> _onHideMessage(
    ChatHideMessage event,
    Emitter<ChatState> emit,
  ) async {
    try {
      final messages = _currentVisibleMessages();
      final msg = messages.firstWhere(
        (m) => m.id == event.messageId,
        orElse: () => ChatMessage(id: '', senderId: ''),
      );
      if (msg.id.isEmpty) return;

      await _storage.saveChatMessage(msg.copyWith(isHidden: true));
      final updatedMessages = messages
          .map((m) => m.id == event.messageId ? m.copyWith(isHidden: true) : m)
          .toList();
      emit(ChatMessageHidden(chatId: event.chatId, messageId: event.messageId));
      emit(ChatMessagesLoaded(updatedMessages,
          hasMore: _hasMoreByChat[event.chatId] ?? false));
    } catch (e) {
      LogService.instance
          .e('Bloc', '_onHideMessage failed: $e', chatId: event.chatId);
    }
  }


  /// 取消隐藏消息（对标 SillyTavern unhideChatMessageRange）
  Future<void> _onUnhideMessage(
    ChatUnhideMessage event,
    Emitter<ChatState> emit,
  ) async {
    try {
      final messages = _currentVisibleMessages();
      final msg = messages.firstWhere(
        (m) => m.id == event.messageId,
        orElse: () => ChatMessage(id: '', senderId: ''),
      );
      if (msg.id.isEmpty) return;

      await _storage.saveChatMessage(msg.copyWith(isHidden: false));
      final updatedMessages = messages
          .map((m) => m.id == event.messageId ? m.copyWith(isHidden: false) : m)
          .toList();
      emit(ChatMessageUnhidden(
          chatId: event.chatId, messageId: event.messageId));
      emit(ChatMessagesLoaded(updatedMessages,
          hasMore: _hasMoreByChat[event.chatId] ?? false));
    } catch (e) {
      LogService.instance
          .e('Bloc', '_onUnhideMessage failed: $e', chatId: event.chatId);
    }
  }


  /// 删除单条消息（对标 SillyTavern deleteMessage）
  Future<void> _onDeleteMessage(
    ChatDeleteMessage event,
    Emitter<ChatState> emit,
  ) async {
    try {
      await _storage.deleteChatMessage(event.messageId);
      // 不要重新拉取「最新 50 条」：那会丢掉用户已通过「加载更多」翻出来的更早消息。
      // 直接在已加载列表上移除被删的那条，保持滚动位置与分页状态不变。
      final currentMessages = _currentVisibleMessages();
      final removedLoadedMessage =
          currentMessages.any((m) => m.id == event.messageId);
      final updatedMessages =
          currentMessages.where((m) => m.id != event.messageId).toList();
      if (removedLoadedMessage) {
        final offset = _loadedOffsets[event.chatId];
        if (offset != null && offset > 0) {
          _loadedOffsets[event.chatId] = offset - 1;
        }
      }
      emit(
          ChatMessageDeleted(chatId: event.chatId, messageId: event.messageId));
      emit(ChatMessagesLoaded(updatedMessages,
          hasMore: _hasMoreByChat[event.chatId] ?? false));
    } catch (e) {
      LogService.instance
          .e('Bloc', '_onDeleteMessage failed: $e', chatId: event.chatId);
    }
  }


  /// 批量删除消息（多选模式）：一次性删库并更新当前已加载窗口，避免逐条重载。
  Future<void> _onDeleteMessages(
    ChatDeleteMessages event,
    Emitter<ChatState> emit,
  ) async {
    try {
      final ids = event.messageIds.toSet();
      for (final id in ids) {
        await _storage.deleteChatMessage(id);
      }
      final currentMessages = _currentVisibleMessages();
      final removedCount =
          currentMessages.where((m) => ids.contains(m.id)).length;
      final updatedMessages =
          currentMessages.where((m) => !ids.contains(m.id)).toList();
      if (removedCount > 0) {
        final offset = _loadedOffsets[event.chatId];
        if (offset != null && offset > 0) {
          _loadedOffsets[event.chatId] = offset - removedCount;
        }
      }
      emit(ChatMessagesLoaded(updatedMessages,
          hasMore: _hasMoreByChat[event.chatId] ?? false));
    } catch (e) {
      LogService.instance
          .e('Bloc', '_onDeleteMessages failed: $e', chatId: event.chatId);
    }
  }


  /// 撤回消息：把内容替换为「已撤回」，就地更新已加载列表（不整页重载）。
  Future<void> _onRecallMessage(
    ChatRecallMessage event,
    Emitter<ChatState> emit,
  ) async {
    try {
      final messages = _currentVisibleMessages();
      final msg = messages.firstWhere(
        (m) => m.id == event.messageId,
        orElse: () => ChatMessage(id: '', senderId: ''),
      );
      if (msg.id.isEmpty) return;

      final recalled = msg.copyWith(
        content: '已撤回',
        status: MessageStatus.failed,
        metadata: {'recalled': true, 'originalContent': msg.content},
      );
      await _storage.saveChatMessage(recalled);
      final updatedMessages =
          messages.map((m) => m.id == event.messageId ? recalled : m).toList();
      emit(ChatMessagesLoaded(updatedMessages,
          hasMore: _hasMoreByChat[event.chatId] ?? false));
    } catch (e) {
      LogService.instance
          .e('Bloc', '_onRecallMessage failed: $e', chatId: event.chatId);
    }
  }


  /// 批量收藏消息（多选模式）：就地更新已加载列表，避免整页重载截断历史。
  Future<void> _onBatchBookmark(
    ChatBatchBookmark event,
    Emitter<ChatState> emit,
  ) async {
    try {
      final ids = event.messageIds.toSet();
      final messages = _currentVisibleMessages();
      for (final m in messages) {
        if (ids.contains(m.id) && !m.isBookmark) {
          await _storage.saveChatMessage(m.copyWith(isBookmark: true));
        }
      }
      final updatedMessages = messages
          .map((m) => ids.contains(m.id) ? m.copyWith(isBookmark: true) : m)
          .toList();
      emit(ChatMessagesLoaded(updatedMessages,
          hasMore: _hasMoreByChat[event.chatId] ?? false));
    } catch (e) {
      LogService.instance
          .e('Bloc', '_onBatchBookmark failed: $e', chatId: event.chatId);
    }
  }


  /// 收藏/取消收藏消息（对标 SillyTavern mes_bookmark）
  Future<void> _onToggleBookmark(
    ChatToggleBookmark event,
    Emitter<ChatState> emit,
  ) async {
    try {
      final messages = _currentVisibleMessages();
      final msg = messages.firstWhere(
        (m) => m.id == event.messageId,
        orElse: () => ChatMessage(id: '', senderId: ''),
      );
      if (msg.id.isEmpty) return;

      await _storage.saveChatMessage(msg.copyWith(isBookmark: !msg.isBookmark));
      final updatedMessages = messages
          .map((m) => m.id == event.messageId
              ? m.copyWith(isBookmark: !m.isBookmark)
              : m)
          .toList();
      emit(ChatMessagesLoaded(updatedMessages,
          hasMore: _hasMoreByChat[event.chatId] ?? false));
    } catch (e) {
      LogService.instance
          .e('Bloc', '_onToggleBookmark failed: $e', chatId: event.chatId);
    }
  }


  /// 复制消息内容（对标 SillyTavern mes_copy）
  Future<void> _onCopyMessage(
    ChatCopyMessage event,
    Emitter<ChatState> emit,
  ) async {
    try {
      final messages = await _storage.getChatMessages(event.chatId);
      final msg = messages.firstWhere(
        (m) => m.id == event.messageId,
        orElse: () => ChatMessage(id: '', senderId: ''),
      );
      if (msg.id.isEmpty) return;

      emit(ChatMessageCopied(
        chatId: event.chatId,
        messageId: event.messageId,
        content: msg.content,
      ));
    } catch (e) {
      LogService.instance
          .e('Bloc', '_onCopyMessage failed: $e', chatId: event.chatId);
    }
  }


  /// 编辑 AI 回复内容
  Future<void> _onEditAIReply(
    ChatEditAIReply event,
    Emitter<ChatState> emit,
  ) async {
    try {
      final messages = await _storage.getChatMessages(event.chatId);
      final msg = messages.firstWhere(
        (m) => m.id == event.messageId,
        orElse: () => ChatMessage(id: '', senderId: ''),
      );
      if (msg.id.isEmpty || !msg.isFromAI) return;

      final cleanedContent = MessageSanitizer.sanitizeFinal(event.newContent);
      if (cleanedContent.isEmpty) return;

      await _storage.saveChatMessage(msg.copyWith(
        content: cleanedContent,
        reasoning: null,
        metadata: {
          ...(msg.metadata ?? {}),
          'editedAt': DateTime.now().toIso8601String(),
        },
      ));
      final updatedMessages = await _storage.getChatMessages(event.chatId);
      emit(ChatMessagesLoaded(updatedMessages));
    } catch (e) {
      LogService.instance
          .e('Bloc', '_onEditAIReply failed: $e', chatId: event.chatId);
    }
  }


  /// 上移消息（对标 SillyTavern mes_edit_up）
  Future<void> _onMoveMessageUp(
    ChatMoveMessageUp event,
    Emitter<ChatState> emit,
  ) async {
    try {
      final messages = await _storage.getChatMessages(event.chatId);
      final msgIndex = messages.indexWhere((m) => m.id == event.messageId);
      if (msgIndex <= 0) return; // 已经是第一条或找不到

      // 交换时间戳实现上移
      final currentMsg = messages[msgIndex];
      final prevMsg = messages[msgIndex - 1];
      await _storage.saveChatMessage(currentMsg.copyWith(
        timestamp: prevMsg.timestamp,
      ));
      await _storage.saveChatMessage(prevMsg.copyWith(
        timestamp: currentMsg.timestamp,
      ));

      final updatedMessages = await _storage.getChatMessages(event.chatId);
      emit(ChatMessagesLoaded(updatedMessages));
    } catch (e) {
      LogService.instance
          .e('Bloc', '_onMoveMessageUp failed: $e', chatId: event.chatId);
    }
  }


  /// 下移消息（对标 SillyTavern mes_edit_down）
  Future<void> _onMoveMessageDown(
    ChatMoveMessageDown event,
    Emitter<ChatState> emit,
  ) async {
    try {
      final messages = await _storage.getChatMessages(event.chatId);
      final msgIndex = messages.indexWhere((m) => m.id == event.messageId);
      if (msgIndex == -1 || msgIndex >= messages.length - 1)
        return; // 已经是最后一条或找不到

      // 交换时间戳实现下移
      final currentMsg = messages[msgIndex];
      final nextMsg = messages[msgIndex + 1];
      await _storage.saveChatMessage(currentMsg.copyWith(
        timestamp: nextMsg.timestamp,
      ));
      await _storage.saveChatMessage(nextMsg.copyWith(
        timestamp: currentMsg.timestamp,
      ));

      final updatedMessages = await _storage.getChatMessages(event.chatId);
      emit(ChatMessagesLoaded(updatedMessages));
    } catch (e) {
      LogService.instance
          .e('Bloc', '_onMoveMessageDown failed: $e', chatId: event.chatId);
    }
  }


  /// 创建检查点/分支（对标 SillyTavern mes_create_bookmark / mes_create_branch）
  Future<void> _onCreateBranch(
    ChatCreateBranch event,
    Emitter<ChatState> emit,
  ) async {
    try {
      final messages = await _storage.getChatMessages(event.chatId);
      final msgIndex = messages.indexWhere((m) => m.id == event.messageId);
      if (msgIndex == -1) return;

      // 标记当前消息为书签
      final msg = messages[msgIndex];
      await _storage.saveChatMessage(msg.copyWith(isBookmark: true));

      LogService.instance.i(
          'Bloc', '_onCreateBranch: branch created at msg ${event.messageId}',
          chatId: event.chatId);
      final updatedMessages = await _storage.getChatMessages(event.chatId);
      emit(ChatMessagesLoaded(updatedMessages));
    } catch (e) {
      LogService.instance
          .e('Bloc', '_onCreateBranch failed: $e', chatId: event.chatId);
    }
  }


  String _normalizeForRegenerationCompare(String text) =>
      normalizeForRegenerationCompare(text);

}
