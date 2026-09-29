// 重新生成与清空上下文（拆分生成，同库 part）
part of '../chat_bloc.dart';

mixin _BlocRegen on Bloc<ChatEvent, ChatState>, ChatBlocUtils, ChatBlocIntimacy, _ChatBlocCore, _BlocCallsBase, _BlocAiBridge, _BlocMemoryIntimacy, _BlocPromptContext, _BlocTurnState, _BlocBtAgent, _BlocNovel, _BlocMessagesLoad, _BlocStatusStats, _BlocBlockForgive, _BlocMessageOps, _BlocSendMoney, _BlocStickerSession, _BlocSendMain {
  /// 重新生成 AI 回复（对标 SillyTavern regenerate）
  Future<void> _onRegenerateAIReply(
    ChatRegenerateAIReply event,
    Emitter<ChatState> emit,
  ) async {
    try {
      final messages = await _storage.getChatMessages(event.chatId);

      // 找到目标 AI 消息
      final targetIndex = messages.indexWhere((m) => m.id == event.messageId);
      if (targetIndex == -1) {
        LogService.instance.w('Bloc',
            '_onRegenerateAIReply: message not found: ${event.messageId}',
            chatId: event.chatId);
        return;
      }
      final targetMsg = messages[targetIndex];
      if (!targetMsg.isFromAI) {
        LogService.instance.w('Bloc', '_onRegenerateAIReply: not an AI message',
            chatId: event.chatId);
        return;
      }

      final previousVariants = <String>{
        MessageSanitizer.sanitizeFinal(targetMsg.content),
        ...targetMsg.swipeHistory.map(MessageSanitizer.sanitizeFinal),
        ...((targetMsg.metadata?['regenerationHistory'] as List?) ?? const [])
            .map((item) => MessageSanitizer.sanitizeFinal(item.toString())),
      }..removeWhere((item) => item.trim().isEmpty);

      // 删除旧的 AI 消息
      await _storage.deleteChatMessage(event.messageId);
      LogService.instance.i('Bloc', '_onRegenerateAIReply: deleted old AI msg',
          chatId: event.chatId);

      // 加载会话和角色信息
      final session = await _storage.getChatSession(event.chatId);
      if (session == null) return;
      final isSideStory = session.isSideStory;
      final character = await _storage.getAICharacter(session.aiCharacterId);
      if (character == null) return;

      // 找到目标 AI 回复紧邻的前一条用户消息（而非整段对话最后一条），
      // 否则重生成中间某条回复时会拿错上下文。
      ChatMessage? lastUserMsg;
      for (var i = targetIndex - 1; i >= 0; i--) {
        final m = messages[i];
        if (m.isUser && !m.isSystem) {
          lastUserMsg = m;
          break;
        }
      }
      if (lastUserMsg == null) {
        LogService.instance.w(
            'Bloc', '_onRegenerateAIReply: no preceding user message found',
            chatId: event.chatId);
        return;
      }

      // 重新加载删除旧消息后的列表
      final updatedMessages = await _storage.getChatMessages(event.chatId);

      // 显示 AI 正在输入
      emit(ChatAITyping(updatedMessages, character.name));

      final memories = isSideStory
          ? const <Memory>[]
          : await _storage.getMemories(
              characterId: character.id,
              userId: session.userId,
              limit: Limit.memoryFetch,
            );

      String finalContent = '';
      String finalReasoning = '';
      final random = Random();

      for (var attempt = 1; attempt <= 2; attempt++) {
        final variantSeed =
            '${DateTime.now().microsecondsSinceEpoch}-${random.nextInt(999999)}';
        final avoidText =
            previousVariants.take(5).map((text) => '- $text').join('\n');
        final regenerateInstruction = '''

【重新生成要求】
这是第 $attempt 次重新生成。必须生成一个新的候选回复。
- 不要复用上一版的动作、场景描写、句式和对白。
- 不要输出空行；每一行都必须有内容。
- 可以改变动作切入点、语气、回应角度或情绪推进。
- 随机锚点：$variantSeed
${avoidText.isNotEmpty ? '\n【禁止重复的旧版本】\n$avoidText' : ''}
''';

        finalContent = '';
        finalReasoning = '';
        try {
          await for (final chunk in _bridgeSendMessageStream(
            character: character,
            userId: session.userId,
            userMessage: '${lastUserMsg.content}$regenerateInstruction',
            chatHistory: updatedMessages,
            memories: memories,
            intimacyLevel: session.intimacyLevel,
            sentiment: SentimentAnalyzer.analyze(lastUserMsg.content),
            isSideStory: isSideStory,
          ).timeout(
            const Duration(seconds: 90),
            onTimeout: (sink) {
              sink.add(const AIStreamChunk(content: '', reasoning: ''));
              sink.close();
            },
          )) {
            finalReasoning = chunk.reasoning;
            finalContent = chunk.content;
          }
        } catch (e) {
          LogService.instance.w('Bloc',
              '_onRegenerateAIReply: stream error on attempt $attempt: $e',
              chatId: event.chatId);
          if (attempt == 2) {
            finalContent = '';
            finalReasoning = '';
          }
          continue;
        }

        final candidate = MessageSanitizer.sanitizeFinal(finalContent);
        final normalizedCandidate = _normalizeForRegenerationCompare(candidate);
        final isRepeated = previousVariants.any((previous) =>
            _normalizeForRegenerationCompare(previous) == normalizedCandidate);
        if (!isRepeated || attempt == 2) {
          break;
        }
        previousVariants.add(candidate);
        LogService.instance.w('Bloc',
            '_onRegenerateAIReply: repeated candidate, retrying with stronger variation',
            chatId: event.chatId);
      }

      if (finalContent.trim().isEmpty ||
          MessageSanitizer.isLikelyUnreadableGibberish(finalContent)) {
        LogService.instance.w('Bloc',
            '_onRegenerateAIReply: empty/mojibake response, using fallback',
            chatId: event.chatId);
        finalContent = MessageSanitizer.failureFallbackText();
        finalReasoning = '';
      }

      // 保存新的 AI 消息
      final reasoningParts = MessageSanitizer.stripReasoningTags(finalContent);
      final extractedReasoning = reasoningParts[1];
      if (extractedReasoning.isNotEmpty) {
        finalReasoning +=
            (finalReasoning.isNotEmpty ? '\n' : '') + extractedReasoning;
      }
      var cleanContent = MessageSanitizer.removeRepeatedContent(
        reasoningParts[0],
        previousMessages: previousVariants,
        fallback: MessageSanitizer.failureFallbackText(),
      );
      if (cleanContent.isEmpty ||
          MessageSanitizer.isLikelyUnreadableGibberish(cleanContent)) {
        cleanContent = MessageSanitizer.failureFallbackText();
      }
      final regenerationHistory = <String>{
        ...previousVariants,
        cleanContent,
      }.where((item) => item.trim().isNotEmpty).take(8).toList();
      final aiMsg = ChatMessage(
        id: _uuid.v4(),
        chatId: event.chatId,
        senderId: 'ai_${character.id}',
        senderName: character.name,
        content: cleanContent,
        type: MessageType.text,
        status: MessageStatus.sent,
        createdAt: DateTime.now(),
        isUser: false,
        reasoning: finalReasoning.isNotEmpty ? finalReasoning : null,
        metadata: {
          ...(targetMsg.metadata ?? {}),
          'regeneratedAt': DateTime.now().toIso8601String(),
          'regenerationHistory': regenerationHistory,
        },
      );
      await _storage.saveChatMessage(aiMsg);

      final finalMessages = await _storage.getChatMessages(event.chatId);
      emit(ChatMessagesLoaded(finalMessages));
      LogService.instance.i(
          'Bloc', '_onRegenerateAIReply: done, new AI msg saved',
          chatId: event.chatId);
    } catch (e) {
      LogService.instance
          .e('Bloc', '_onRegenerateAIReply failed: $e', chatId: event.chatId);
      emit(ChatError('重新生成失败'));
    }
  }


  /// 清空上下文（对标 SillyTavern clearContext）
  Future<void> _onClearContext(
    ChatClearContext event,
    Emitter<ChatState> emit,
  ) async {
    try {
      // 保留最近 N 条消息，删除更早的消息
      final messages = await _storage.getChatMessages(event.chatId);
      if (messages.length <= 10) {
        emit(ChatContextCleared(chatId: event.chatId));
        return;
      }

      // 保留最后 10 条消息
      final toDelete = messages.take(messages.length - 10).toList();
      for (final msg in toDelete) {
        await _storage.deleteChatMessage(msg.id);
      }

      final updatedMessages = await _storage.getChatMessages(event.chatId);
      emit(ChatContextCleared(chatId: event.chatId));
      emit(ChatMessagesLoaded(updatedMessages));
    } catch (e) {
      LogService.instance
          .e('Bloc', '_onClearContext failed: $e', chatId: event.chatId);
    }
  }

}
