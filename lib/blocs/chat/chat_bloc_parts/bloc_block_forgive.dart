// 拉黑与原谅机制（拆分生成，同库 part）
part of '../chat_bloc.dart';

mixin _BlocBlockForgive on Bloc<ChatEvent, ChatState>, ChatBlocUtils, ChatBlocIntimacy, _ChatBlocCore, _BlocCallsBase, _BlocAiBridge, _BlocMemoryIntimacy, _BlocPromptContext, _BlocTurnState, _BlocBtAgent, _BlocNovel, _BlocMessagesLoad, _BlocStatusStats {
  Future<void> _onBlockByUser(
    ChatBlockByUser event,
    Emitter<ChatState> emit,
  ) async {
    await _storage.blockSession(event.chatId, BlockedBy.user, 'user_initiated');
    final session = await _storage.getChatSession(event.chatId);
    if (session != null) {
      final systemMsg = ChatMessage(
        id: _uuid.v4(),
        chatId: event.chatId,
        senderId: 'system',
        senderName: '系统',
        content: '你已将对方拉黑。',
        type: MessageType.system,
        status: MessageStatus.sent,
        createdAt: DateTime.now(),
        metadata: {'isBlockNotice': true, 'blockReason': 'user_initiated'},
      );
      await _storage.saveChatMessage(systemMsg);
    }
    final messages = await _storage.getChatMessages(event.chatId);
    emit(ChatMessagesLoaded(messages));
  }


  Future<void> _onUnblockByUser(
    ChatUnblockByUser event,
    Emitter<ChatState> emit,
  ) async {
    await _storage.unblockSession(event.chatId);
    final session = await _storage.getChatSession(event.chatId);
    if (session != null) {
      final systemMsg = ChatMessage(
        id: _uuid.v4(),
        chatId: event.chatId,
        senderId: 'system',
        senderName: '系统',
        content: '你已解除对方拉黑。',
        type: MessageType.system,
        status: MessageStatus.sent,
        createdAt: DateTime.now(),
        metadata: {'isBlockNotice': true, 'blockReason': 'user_unblocked'},
      );
      await _storage.saveChatMessage(systemMsg);
    }
    final messages = await _storage.getChatMessages(event.chatId);
    emit(ChatMessagesLoaded(messages));
  }


  Future<void> _onAIForgaveUser(
    ChatAIForgaveUser event,
    Emitter<ChatState> emit,
  ) async {
    final messages = await _storage.getChatMessages(event.chatId);
    emit(ChatUnblockedByAI(chatId: event.chatId, messages: messages));

    // 台阶消息：原谅后先发一条缓和情绪的话
    if (event.forgiveMessage != null && event.forgiveMessage!.isNotEmpty) {
      final session = await _storage.getChatSession(event.chatId);
      if (session == null) return;
      final character = await _storage.getAICharacter(session.aiCharacterId);
      if (character == null) return;

      await Future.delayed(Duration(seconds: 2 + Random().nextInt(3)));
      await _storage.saveChatMessage(ChatMessage(
        id: _uuid.v4(),
        chatId: event.chatId,
        senderId: 'ai_${character.id}',
        senderName: character.name,
        content: MessageSanitizer.filterForbiddenPhrases(
          event.forgiveMessage!,
          _storage.getForbiddenPhrases(),
        ),
        type: MessageType.text,
        status: MessageStatus.sent,
        createdAt: DateTime.now(),
      ));
      if (!isClosed) {
        emit(ChatMessagesLoaded(await _storage.getChatMessages(event.chatId)));
      }
    }
  }


  Future<void> _onAIObservingNotify(
    ChatAIObservingNotify event,
    Emitter<ChatState> emit,
  ) async {
    final messages = await _storage.getChatMessages(event.chatId, limit: 50);
    emit(ChatAIObserving(
      chatId: event.chatId,
      statusText: event.statusText,
      emotionLabel: event.emotionLabel,
      emotionEmoji: event.emotionEmoji,
      emotionIntensity: event.emotionIntensity,
      pendingCount: event.pendingCount,
      messages: messages,
    ));
  }


  Future<void> _observeAsBlockedAI(
    String chatId,
    String userId,
    String latestMessage,
  ) async {
    // 事件驱动：新消息到达时立即触发观察，而非依赖定时轮询
    _lastObservationTrigger[chatId] = DateTime.now();

    if (_activeObservations.contains(chatId)) return;
    _activeObservations.add(chatId);

    try {
      final random = Random();
      final blockedAt = DateTime.now();

      // 首次观察：短延迟后立即响应
      await Future.delayed(Duration(seconds: 5 + random.nextInt(15)));
      if (isClosed) return;

      int cycleCount = 0;

      while (!isClosed) {
        final session = await _storage.getChatSession(chatId);
        if (session == null ||
            !session.isBlocked ||
            session.blockedBy != BlockedBy.ai) break;

        cycleCount++;
        final elapsed = DateTime.now().difference(blockedAt);

        final character = await _storage.getAICharacter(session.aiCharacterId);
        if (character == null) break;

        final emotion = await _emotionEngine.getCurrentEmotion(
          character: character,
          userId: userId,
        );

        final observeStatus = _getObserveStatusText(
          elapsed: elapsed,
          cycleCount: cycleCount,
          emotion: emotion.primaryEmotion,
          random: random,
        );

        if (!isClosed) {
          add(ChatAIObservingNotify(
            chatId: chatId,
            statusText: observeStatus,
            emotionLabel: emotion.primaryEmotion.label,
            emotionEmoji: emotion.primaryEmotion.emoji,
            emotionIntensity: emotion.currentIntensity,
            pendingCount: _pendingBlockMessages[chatId]?.length ?? 0,
          ));
        }

        // 情绪驱动的已读：生气时延迟更久才标记已读
        final readDelayMs = _calculateReadDelay(
            emotion.primaryEmotion, emotion.currentIntensity);
        await Future.delayed(Duration(milliseconds: readDelayMs));
        await _markRecentMessagesAsRead(chatId, userId, random);
        if (!isClosed) {
          add(ChatAIObservingNotify(
            chatId: chatId,
            statusText: observeStatus,
            emotionLabel: emotion.primaryEmotion.label,
            emotionEmoji: emotion.primaryEmotion.emoji,
            emotionIntensity: emotion.currentIntensity,
            pendingCount: _pendingBlockMessages[chatId]?.length ?? 0,
          ));
        }

        // 原谅概率：基于情绪强度、时间、累积消息数
        final forgiveChance = _calculateForgiveChance(
          elapsed: elapsed,
          cycleCount: cycleCount,
          emotion: emotion,
          pendingCount: _pendingBlockMessages[chatId]?.length ?? 0,
        );

        if (random.nextDouble() < forgiveChance) {
          final success =
              await _aiConsiderForgiveness(chatId, userId, character);
          if (success) break;
        }

        // 事件驱动间隔：10~30秒，比之前的60~180秒快得多
        final nextDelay = Duration(seconds: 10 + random.nextInt(20));
        await Future.delayed(nextDelay);
      }
    } finally {
      _activeObservations.remove(chatId);
    }
  }


  String _getObserveStatusText({
    required Duration elapsed,
    required int cycleCount,
    EmotionType? emotion,
    required Random random,
  }) {
    if (emotion == EmotionType.angry) {
      final texts = ['还在生气', '不想理你', '心里还有气', '需要冷静一下'];
      return texts[random.nextInt(texts.length)];
    }
    if (emotion == EmotionType.sad) {
      final texts = ['有些难过', '在想你说的话', '心情不太好', '有点委屈'];
      return texts[random.nextInt(texts.length)];
    }
    if (emotion == EmotionType.anxious) {
      final texts = ['有些不安', '在犹豫要不要理你', '心里有点难过'];
      return texts[random.nextInt(texts.length)];
    }

    if (elapsed.inMinutes < 2) {
      final texts = ['看到了你的消息', '在观察你的态度', '在想你说的话'];
      return texts[random.nextInt(texts.length)];
    }
    if (elapsed.inMinutes < 10) {
      final texts = ['有些心软了', '其实有点动摇', '还在纠结要不要理你', '在想你说的话'];
      return texts[random.nextInt(texts.length)];
    }

    final texts = ['看到你这么坚持', '其实没那么生气了', '在考虑要不要原谅你', '心有点软了'];
    return texts[random.nextInt(texts.length)];
  }


  double _calculateForgiveChance({
    required Duration elapsed,
    required int cycleCount,
    CharacterEmotion? emotion,
    int pendingCount = 0,
  }) {
    double chance = 0.25;
    // 时间推移增加原谅概率
    chance += (elapsed.inMinutes / 8) * 0.12;
    // 观察轮次增加
    chance += cycleCount * 0.1;
    // 情绪强度降低时更容易原谅
    if (emotion != null && emotion.currentIntensity < 0.5) chance += 0.2;
    // 用户坚持发消息越多越容易原谅
    if (pendingCount >= 3) chance += 0.15;
    if (pendingCount >= 5) chance += 0.15;
    // 超过10分钟大幅增加
    if (elapsed.inMinutes > 10) chance += 0.2;
    return chance.clamp(0.0, 0.9);
  }


  int _calculateReadDelay(EmotionType emotion, double intensity) {
    // 生气时延迟更久才标记已读（模拟"看了不想回"）
    if (emotion == EmotionType.angry) {
      return (3000 + intensity * 5000).toInt(); // 3~8绉?
    }
    if (emotion == EmotionType.sad) {
      return (2000 + intensity * 4000).toInt(); // 2~6绉?
    }
    if (emotion == EmotionType.anxious) {
      return (1500 + intensity * 2500).toInt(); // 1.5~4绉?
    }
    // 平静/开心：快速已读
    return 500 + Random().nextInt(1500); // 0.5~2绉?
  }


  /// AI 已回复时，将用户侧未读消息标为已读（正常聊天路径）
  Future<void> _markUserMessagesAsRead(String chatId, String userId) async {
    try {
      final messages = await _storage.getChatMessages(chatId, limit: 40);
      final now = DateTime.now();
      for (final msg in messages) {
        if (!msg.isUser || msg.isSystem) continue;
        if (msg.senderId != userId) continue;
        if (msg.status == MessageStatus.read) continue;
        await _storage.saveChatMessage(msg.copyWith(
          status: MessageStatus.read,
          readAt: now,
        ));
      }
    } catch (e) {
      LogService.instance
          .e('Bloc', '_markUserMessagesAsRead failed: $e', chatId: chatId);
    }
  }


  Future<void> _markRecentMessagesAsRead(
      String chatId, String userId, Random random) async {
    try {
      final messages = await _storage.getChatMessages(chatId, limit: 5);
      final unreadUserMessages = messages
          .where((m) => m.senderId == userId && m.status != MessageStatus.read)
          .toList();

      for (var msg in unreadUserMessages) {
        if (random.nextDouble() < 0.6) {
          await _storage.saveChatMessage(msg.copyWith(
            status: MessageStatus.read,
            readAt: DateTime.now(),
          ));
        }
      }
    } catch (e) {
      LogService.instance
          .e('Bloc', '_markRecentMessagesAsRead failed: $e', chatId: chatId);
    }
  }


  Future<bool> _aiConsiderForgiveness(
    String chatId,
    String userId,
    AICharacter character,
  ) async {
    try {
      final session = await _storage.getChatSession(chatId);
      if (session == null ||
          !session.isBlocked ||
          session.blockedBy != BlockedBy.ai) return false;

      final allMsgs = await _storage.getChatMessages(chatId);
      final blockedAt = session.blockedAt;
      final userMsgsSinceBlock = allMsgs
          .where((m) =>
              !m.isFromAI &&
              m.senderId != 'system' &&
              m.senderId != 'system_risk' &&
              (blockedAt == null || m.createdAt.isAfter(blockedAt)))
          .toList();

      if (userMsgsSinceBlock.isEmpty) return false;

      final judgment = await _bridgeConsiderForgiveness(
        character: character,
        userId: userId,
        userMessagesSinceBlock: userMsgsSinceBlock,
        blockReason: session.blockReason,
      );

      if (judgment.shouldForgive) {
        await _storage.unblockSession(chatId);
        _pendingBlockMessages.remove(chatId);

        if (!isClosed) {
          add(ChatAIForgaveUser(
              chatId: chatId, forgiveMessage: judgment.forgiveMessage));
        }
        return true;
      }
      return false;
    } catch (e) {
      LogService.instance
          .e('Bloc', '_aiConsiderForgiveness failed: $e', chatId: chatId);
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════
  // SillyTavern 对标方法：消息滑动（swipe_left/right）
  // ═══════════════════════════════════════════════════════

}
