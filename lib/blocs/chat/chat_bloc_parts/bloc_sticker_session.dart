// 贴纸与会话管理（拆分生成，同库 part）
part of '../chat_bloc.dart';

mixin _BlocStickerSession on Bloc<ChatEvent, ChatState>, ChatBlocUtils, ChatBlocIntimacy, _ChatBlocCore, _BlocCallsBase, _BlocAiBridge, _BlocMemoryIntimacy, _BlocPromptContext, _BlocTurnState, _BlocBtAgent, _BlocNovel, _BlocMessagesLoad, _BlocStatusStats, _BlocBlockForgive, _BlocMessageOps, _BlocSendMoney {
  Future<void> _onSendSticker(
    ChatSendSticker event,
    Emitter<ChatState> emit,
  ) async {
    try {
      final now = DateTime.now();
      final stickerMessage = ChatMessage(
        id: _uuid.v4(),
        chatId: event.chatId,
        senderId: event.userId,
        content: event.sticker,
        type: MessageType.sticker,
        status: MessageStatus.sent,
        createdAt: now,
        isUser: true,
        metadata: event.isImageSticker
            ? {'isImageSticker': true}
            : {
                'isBuiltinSticker': true,
                'stickerFile':
                    BuiltinStickerService.findStickerById(event.sticker)
                            ?.file ??
                        '',
              },
      );

      await _storage.saveChatMessage(stickerMessage);

      final messages = await _storage.getChatMessages(event.chatId);
      emit(ChatMessagesLoaded(messages));

      final session = await _storage.getChatSession(event.chatId);
      if (session == null) {
        LogService.instance
            .e('Bloc', '_onSendSticker: session is null', chatId: event.chatId);
        return;
      }

      final character = await _storage.getAICharacter(session.aiCharacterId);
      if (character == null) {
        LogService.instance.e('Bloc', '_onSendSticker: character is null',
            chatId: event.chatId);
        return;
      }

      final stickerImagePaths =
          event.isImageSticker && event.sticker.trim().isNotEmpty
              ? <String>[event.sticker.trim()]
              : null;

      // Reply mode check
      final replyModeSt =
          character.interactionConfig?.replyMode ?? ReplyMode.normal;

      if (replyModeSt == ReplyMode.manual) {
        LogService.instance.e(
            'Bloc', '_onSendSticker: replyMode is manual, skip AI reply',
            chatId: event.chatId);
        final prefs = await PrefsHelper.instance;
        final msg = event.isImageSticker ? '[表情包]' : event.sticker;
        final pending =
            prefs.getString(PrefKeys.pendingReply(event.chatId)) ?? '';
        await prefs.setString(PrefKeys.pendingReply(event.chatId),
            pending.isEmpty ? msg : '$pending\n---\n$msg');
        return;
      }

      emit(ChatAITyping(messages, character.name));

      if (replyModeSt == ReplyMode.instant) {
        await Future.delayed(AppDurations.instantReplyDelay);
      } else if (replyModeSt == ReplyMode.delayed) {
        final delay = character.interactionConfig?.replyDelaySeconds ?? 5;
        await Future.delayed(Duration(seconds: delay));
      } else {
        final personality = (character.personality).toLowerCase();
        int typingDelay = 1;
        if (personality.contains('高冷') || personality.contains('冷淡')) {
          typingDelay = 3;
        } else if (personality.contains('温柔') || personality.contains('体贴')) {
          typingDelay = 2;
        }
        await Future.delayed(Duration(seconds: typingDelay));
      }

      // AI 离线时不影响回复，只是带着状态语气回应
      //（已在系统 prompt 中根据 currentStatus 引导语气）

      final memories = await _storage.getMemories(
        characterId: character.id,
        userId: event.userId,
        limit: Limit.memoryFetch,
      );

      // 表情包/贴纸有时自然跳过回复
      final shouldSkip = _shouldSkipReply(
        personality: character.personality,
        intimacyLevel: session.intimacyLevel,
        messageContent: event.isImageSticker ? '[表情包图片]' : event.sticker,
        consecutiveAiReplies: _consecutiveAiReplies[event.chatId] ?? 0,
        messageType: MessageType.sticker,
      );
      if (shouldSkip) {
        _consecutiveAiReplies[event.chatId] = 0;
        emit(ChatMessagesLoaded(await _storage.getChatMessages(event.chatId)));
        return;
      }
      _consecutiveAiReplies[event.chatId] =
          (_consecutiveAiReplies[event.chatId] ?? 0) + 1;

      String aiResponse;
      String userMessageForAI;
      SentimentResult sentimentResult;

      // 确保内置贴纸包已加载（否则描述退化为"一个表情包"，AI 读不到具体情绪）
      await BuiltinStickerService.loadDefaultPack();

      final stickerDesc =
          BuiltinStickerService.getStickerDescription(event.sticker);
      userMessageForAI = '[用户发送了一个表情包：$stickerDesc]';
      sentimentResult = SentimentResult(
          label: 'positive', score: 1, type: SentimentType.positive);
      await _emotionEngine.updateEmotion(
        character: character,
        userId: event.userId,
        userMessage: userMessageForAI,
        userSentiment: sentimentResult,
        intimacyLevel: session.intimacyLevel,
      );
      try {
        aiResponse = await _bridgeSendMessage(
          character: character,
          userId: event.userId,
          userMessage: userMessageForAI,
          chatHistory: messages,
          memories: memories,
          intimacyLevel: session.intimacyLevel,
          sentiment: sentimentResult,
          imagePaths: stickerImagePaths,
        );
        if (aiResponse.trim().isEmpty) {
          aiResponse = '哈哈，这个表情包好有趣！';
        }
      } catch (aiError) {
        String errorText = _formatAiError(aiError);
        final now = DateTime.now();
        final lastError = _lastErrorTime[event.chatId];
        if (lastError != null && now.difference(lastError).inSeconds < 30) {
          LogService.instance.w('ChatBloc', '跳过重复报错: $errorText');
          final updatedMessages = await _storage.getChatMessages(event.chatId);
          emit(ChatMessagesLoaded(updatedMessages));
          return;
        }
        _lastErrorTime[event.chatId] = now;
        _errorSessions.add(event.chatId);
        final errorMessage = ChatMessage(
          id: _uuid.v4(),
          chatId: event.chatId,
          senderId: 'ai_${character.id}',
          senderName: character.name,
          content: errorText,
          type: MessageType.text,
          status: MessageStatus.sent,
          createdAt: now,
          metadata: {'isError': true},
        );
        await _storage.saveChatMessage(errorMessage);
        final updatedMessages = await _storage.getChatMessages(event.chatId);
        emit(ChatMessagesLoaded(updatedMessages));
        return;
      }

      final stickerReplyEnabled = _isStickerReplyEnabled(character);
      final cleanedAIResponse = MessageSanitizer.filterForbiddenPhrases(
        stickerReplyEnabled
            ? _normalizeBareStickerTags(aiResponse)
            : MessageSanitizer.sanitizeFinal(_stripAIStickerOutput(aiResponse)),
        _storage.getForbiddenPhrases(),
      );
      List<String> messageParts = stickerReplyEnabled
          ? _bridgeSplitMessages(cleanedAIResponse)
          : [cleanedAIResponse];

      // 修复：API 返回后、保存第一条消息前，保持 typing 状态可见
      emit(ChatAITyping(
          await _storage.getChatMessages(event.chatId), character.name));

      for (int i = 0; i < messageParts.length; i++) {
        if (i > 0) {
          await Future.delayed(AppDurations.multiMessageDelay);
          emit(ChatAITyping(
              await _storage.getChatMessages(event.chatId), character.name));
        }

        final part = messageParts[i];
        // 兼容两种格式：整行贴纸 [STICKER:x] 或文本中夹带（哈哈[STICKER:x]）
        final stickerMatch = stickerReplyEnabled
            ? (_stickerFullLineRe.firstMatch(part) ??
                _stickerTagRe.firstMatch(part))
            : null;
        if (stickerMatch != null) {
          final stickerId = stickerMatch.group(1)!;
          final sticker = BuiltinStickerService.findStickerById(stickerId);
          if (sticker != null) {
            final aiMessage = ChatMessage(
              id: _uuid.v4(),
              chatId: event.chatId,
              senderId: 'ai_${character.id}',
              senderName: character.name,
              content: stickerId,
              type: MessageType.sticker,
              status: MessageStatus.sent,
              createdAt: DateTime.now(),
              metadata: {
                'stickerId': stickerId,
                'stickerName': sticker.name,
                'isBuiltinSticker': true,
                'stickerFile': sticker.file
              },
            );
            await _storage.saveChatMessage(aiMessage);
            // 整行贴纸：不再存文本；文本夹带贴纸：剩余文本另存一条
            if (!_stickerFullLineRe.hasMatch(part)) {
              final remainder = part.replaceAll(_stickerTagRe, '').trim();
              if (remainder.isNotEmpty) {
                await _storage.saveChatMessage(ChatMessage(
                  id: _uuid.v4(),
                  chatId: event.chatId,
                  senderId: 'ai_${character.id}',
                  senderName: character.name,
                  content: remainder,
                  type: MessageType.text,
                  status: MessageStatus.sent,
                  createdAt: DateTime.now(),
                ));
              }
            }
          } else {
            // 贴纸 ID 不在内置库：降级为纯文本展示
            await _storage.saveChatMessage(ChatMessage(
              id: _uuid.v4(),
              chatId: event.chatId,
              senderId: 'ai_${character.id}',
              senderName: character.name,
              content: part,
              type: MessageType.text,
              status: MessageStatus.sent,
              createdAt: DateTime.now(),
            ));
          }
        } else {
          final aiMessage = ChatMessage(
            id: _uuid.v4(),
            chatId: event.chatId,
            senderId: 'ai_${character.id}',
            senderName: character.name,
            content: part,
            type: MessageType.text,
            status: MessageStatus.sent,
            createdAt: DateTime.now(),
          );
          await _storage.saveChatMessage(aiMessage);
        }

        final currentMessages = await _storage.getChatMessages(event.chatId);
        emit(ChatMessagesLoaded(currentMessages));
      }

      await _markUserMessagesAsRead(event.chatId, event.userId);
      final readUpdated = await _storage.getChatMessages(event.chatId);
      emit(ChatMessagesLoaded(readUpdated));

      _updateAIStatus(character, chatId: event.chatId);
      await _persistTurnState(
        chatId: event.chatId,
        character: character,
        userId: event.userId,
        userMessage: userMessageForAI,
        aiReply: cleanedAIResponse,
        sentimentLabel: sentimentResult.label,
        emit: emit,
      );
      _errorSessions.remove(event.chatId);

      await _applyIntimacyAfterReply(
        session: session,
        messageContent: userMessageForAI,
        sentiment: sentimentResult,
        source: 'sticker',
        emit: emit,
        lastMessagePreview: '[表情]',
      );

      emit(ChatEmotionChanged(
        chatId: event.chatId,
        emotionLabel: sentimentResult.label,
        emotionType: sentimentResult.type,
      ));

      await _storage.saveMemory(Memory(
        id: _uuid.v4(),
        characterId: character.id,
        userId: event.userId,
        type: MemoryType.conversation,
        content:
            'User sent sticker: ${event.isImageSticker ? "[图片表情包]" : event.sticker}',
        importance: MemoryImportance.normal,
        keywords: _extractKeywords(userMessageForAI),
        createdAt: now,
      ));
    } catch (e) {
      emit(ChatError(e.toString()));
    }
  }


  Future<void> _onCreateSession(
    ChatCreateSession event,
    Emitter<ChatState> emit,
  ) async {
    try {
      final now = DateTime.now();
      final session = ChatSession(
        id: _uuid.v4(),
        userId: event.userId,
        aiCharacterId: event.character.id,
        aiCharacterName: event.character.name,
        aiCharacterAvatar: event.character.avatarUrl,
        createdAt: now,
        updatedAt: now,
      );

      await _storage.saveChatSession(session);

      final sessions = await _storage.getChatSessions(event.userId);
      emit(ChatSessionsLoaded(sessions));
      emit(ChatSessionCreated(session));
    } catch (e) {
      emit(ChatError(e.toString()));
    }
  }


  Future<void> _onDeleteSession(
    ChatDeleteSession event,
    Emitter<ChatState> emit,
  ) async {
    try {
      // 级联删除：连消息与番外小剧场会话一起清理，避免孤儿数据。
      await _storage.deleteChatSessionCascade(event.chatId);

      final sessions = await _storage.getChatSessions(event.userId);
      emit(ChatSessionsLoaded(sessions));
    } catch (e) {
      emit(ChatError(e.toString()));
    }
  }

}
