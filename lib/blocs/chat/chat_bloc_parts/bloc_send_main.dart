// 发送主链路（拆分生成，同库 part）
part of '../chat_bloc.dart';

mixin _BlocSendMain on Bloc<ChatEvent, ChatState>, ChatBlocUtils, ChatBlocIntimacy, _ChatBlocCore, _BlocCallsBase, _BlocAiBridge, _BlocMemoryIntimacy, _BlocPromptContext, _BlocTurnState, _BlocBtAgent, _BlocNovel, _BlocMessagesLoad, _BlocStatusStats, _BlocBlockForgive, _BlocMessageOps, _BlocSendMoney, _BlocStickerSession {
  Future<void> _onSendMessage(
    ChatSendMessage event,
    Emitter<ChatState> emit,
  ) async {
    final now = DateTime.now();

    // 括号动作/旁白：只做标记；说明走 system/internal，禁止塞进 user 台词
    // （旧实现把说明写成又一段「（请注意…）」会让模型把旁白当对白）
    final bool hasActionBracket = event.metadata?['hasActionBracket'] == true ||
        _containsActionBracket(event.content);
    final imagePaths = <String>[
      ...?event.imagePaths,
      if (event.metadata?['imagePath'] is String &&
          (event.metadata!['imagePath'] as String).trim().isNotEmpty)
        (event.metadata!['imagePath'] as String).trim(),
      if (event.metadata?['imagePaths'] is List)
        for (final p in (event.metadata!['imagePaths'] as List))
          if (p is String && p.trim().isNotEmpty) p.trim(),
    ];
    // 去重
    final uniqueImagePaths = <String>[];
    for (final p in imagePaths) {
      if (!uniqueImagePaths.contains(p)) uniqueImagePaths.add(p);
    }
    imagePaths
      ..clear()
      ..addAll(uniqueImagePaths);

    // 用户原文即可；结构化拆分在 AIService._buildMessages 内完成
    final String userMessageForAI = event.content;
    final imageDescription = event.metadata?['imageDescription'] as String?;

    final displayContent = _stripSystemDirective(event.content);
    final isDirectiveOnly = displayContent.isEmpty;
    // 有图时：气泡 content 优先用本地路径（UI Image.file），文案放 caption
    final hasImages = imagePaths.isNotEmpty;
    final primaryImagePath = hasImages ? imagePaths.first : null;
    final caption = displayContent.trim();
    final userMsg = ChatMessage(
      id: _uuid.v4(),
      chatId: event.chatId,
      senderId: event.userId,
      content: hasImages
          ? primaryImagePath!
          : (isDirectiveOnly ? event.content : displayContent),
      type: hasImages ? MessageType.image : MessageType.text,
      status: MessageStatus.sent,
      createdAt: now,
      isUser: true,
      metadata: {
        ...?(isDirectiveOnly
            ? {...(event.metadata ?? {}), 'isSystemDirective': true}
            : event.metadata),
        if (hasActionBracket) 'hasActionBracket': true,
        if (hasImages) 'imagePaths': imagePaths,
        if (hasImages && caption.isNotEmpty) 'caption': caption,
        if (imageDescription != null) 'imageDescription': imageDescription,
      },
    );

    try {
      debugPrint(
          '[Bloc] _onSendMessage: saving user msg, content="${event.content.substring(0, event.content.length > 20 ? 20 : event.content.length)}"');
      LogService.instance.i('Bloc',
          '_onSendMessage: saving user msg, isUser=${userMsg.isUser}, id=${userMsg.id.substring(0, 8)}',
          chatId: event.chatId);
      await _storage.saveChatMessage(userMsg);

      LogService.instance
          .i('Bloc', '_onSendMessage: user msg saved', chatId: event.chatId);
      // 标记会话活跃 → 在线状态实时更新
      unawaited(AIStatusService(_storage).markSessionActive(event.chatId));
    } catch (_) {
      LogService.instance
          .e('Bloc', '_onSendMessage: save failed', chatId: event.chatId);
      emit(ChatError('保存消息失败'));
      return;
    }

    List<ChatMessage> messages;
    try {
      messages = await _storage.getChatMessages(event.chatId);
    } catch (_) {
      messages = [];
    }
    // 确保用户消息在列表中（防止数据库读取延迟导致消息丢失）
    if (!messages.any((m) => m.id == userMsg.id)) {
      messages.add(userMsg);
      messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    }
    LogService.instance.i(
        'Bloc', '_onSendMessage: emit ${messages.length} msgs',
        chatId: event.chatId);
    emit(ChatMessagesLoaded(messages));

    var session = await _storage.getChatSession(event.chatId);

    // 检查用户是否已拉黑 AI - 用户拉黑后不发消息
    if (session != null &&
        session.isBlocked &&
        session.blockedBy == BlockedBy.user) {
      emit(ChatMessagesLoaded(messages));
      return;
    }

    final bool isBlockedByAI = session != null &&
        session.isBlocked &&
        session.blockedBy == BlockedBy.ai;

    // 假性拉黑：消息已保存，AI 静默接收，事件驱动观察（不要挂着「等待中」）
    if (isBlockedByAI) {
      _pendingBlockMessages.putIfAbsent(event.chatId, () => []);
      _pendingBlockMessages[event.chatId]!.add(event.content);
      emit(ChatMessagesLoaded(messages));
      _observeAsBlockedAI(event.chatId, event.userId, event.content);
      return;
    }

    // NSFW 内容检测 → 自动拉黑（法模式下跳过检测）
    final faModeActive = _storage.isFaModeEnabled();
    final nsfwResult = faModeActive
        ? const ContentFilterResult()
        : ContentFilter.check(event.content);
    if (nsfwResult.isNSFW) {
      await _storage.blockSession(event.chatId, BlockedBy.ai, 'nsfw');
      final blockMsg = ChatMessage(
        id: _uuid.v4(),
        chatId: event.chatId,
        senderId: 'system',
        senderName: '系统',
        content: '检测到违规内容，已将你拉黑。',
        type: MessageType.system,
        status: MessageStatus.sent,
        createdAt: DateTime.now(),
        metadata: {'isBlockNotice': true, 'blockReason': 'nsfw'},
      );
      await _storage.saveChatMessage(blockMsg);
      final updatedMessages = await _storage
          .getChatMessages(event.chatId)
          .catchError((_) => <ChatMessage>[]);
      emit(ChatBlockedByAI(
        chatId: event.chatId,
        reason: 'nsfw',
        messages: updatedMessages,
      ));
      return;
    }

    // 行为风控检测（715 合规）
    _updateMessageStats(event.chatId, event.content);
    final riskResult = BehaviorRiskDetector.analyze(
      message: event.content,
      dailyMessageCount: _dailyMsgCount[event.chatId] ?? 0,
      hourlyMessageCount: _hourlyMsgCount[event.chatId] ?? 0,
      isLateNight: BehaviorRiskDetector.isLateNight(),
      avgMessageLength: _avgMessageLength(event.chatId),
      faMode: faModeActive,
    );

    if (riskResult.shouldWarn && riskResult.warningMessage != null) {
      LogService.instance.w(
          'Risk', 'Behavior risk detected: ${riskResult.level}',
          chatId: event.chatId);

      // 保存风控警告消息（系统消息）
      await _storage.saveChatMessage(ChatMessage(
        id: _uuid.v4(),
        chatId: event.chatId,
        senderId: 'system_risk',
        senderName: '系统提示',
        content: riskResult.warningMessage!,
        type: MessageType.text,
        status: MessageStatus.sent,
        createdAt: DateTime.now(),
        metadata: {'isRiskWarning': true, 'riskLevel': riskResult.level.name},
      ));

      messages = await _storage.getChatMessages(event.chatId);
      emit(ChatMessagesLoaded(messages));

      if (riskResult.shouldLockEmotion) {
        _emotionLockedSessions.add(event.chatId);
      }

      // 高风险时暂停AI回复（已 emit Loaded，不会卡「等待中」）
      if (riskResult.level == RiskLevel.high) {
        return;
      }
    }

    // 如果情感功能被锁定，跳过亲密度计算和深度情感回复
    final isEmotionLocked = _emotionLockedSessions.contains(event.chatId);

    AICharacter? character;
    try {
      session = await _storage.getChatSession(event.chatId);
      if (session == null) {
        LogService.instance
            .e('Bloc', '_onSendMessage: session is null', chatId: event.chatId);
        emit(ChatMessagesLoaded(messages));
        return;
      }
      character = await _storage.getAICharacter(session.aiCharacterId);
      if (character == null) {
        LogService.instance.e('Bloc', '_onSendMessage: character is null',
            chatId: event.chatId);
        emit(ChatMessagesLoaded(messages));
        return;
      }
    } catch (e) {
      LogService.instance.e(
          'Bloc', '_onSendMessage: session/character load failed: $e',
          chatId: event.chatId);
      emit(ChatMessagesLoaded(messages));
      return;
    }

    // 番外平行小剧场：与主线完全隔离（不读主线记忆、不写主线记忆）。
    final isSideStory = session.isSideStory;

    // 情感锁定时，修改 AI 角色配置为安全模式
    if (isEmotionLocked) {
      character = character.copyWith(
        personality:
            '${character.personality}\n\n【安全模式】当前用户已被系统标记为需要保护状态\n你必须：1.保持友善但理性的态度；2.不提供深度情感安慰；3.建议用户寻求现实帮助\n4.不表达任何亲密关系暗示；5.如用户表达极端情绪，提供心理援助热线 400-161-9995',
      );
    }

    // 自然跳过：必须在显示「等待中」之前判定，否则会永久卡在输入中
    final shouldSkip = _shouldSkipReply(
      personality: character.personality,
      intimacyLevel: session.intimacyLevel,
      messageContent: event.content,
      consecutiveAiReplies: _consecutiveAiReplies[event.chatId] ?? 0,
      messageType: userMsg.type,
    );
    if (shouldSkip) {
      _consecutiveAiReplies[event.chatId] = 0;
      emit(ChatMessagesLoaded(messages));
      return;
    }
    _consecutiveAiReplies[event.chatId] =
        (_consecutiveAiReplies[event.chatId] ?? 0) + 1;

    // 确认会发起 AI 请求后再显示「等待中」
    emit(ChatAITyping(messages, character.name));

    // 为 AI 额外拉一截更长历史，避免 UI 默认 50 条截断导致“失忆”
    try {
      final aiHistory = await _storage.getChatMessages(
        event.chatId,
        limit: Limit.chatHistoryLoadForAI,
      );
      if (aiHistory.length > messages.length) {
        messages = aiHistory;
        // 确保刚发送的用户消息仍在列表中
        if (!messages.any((m) => m.id == userMsg.id)) {
          messages = [...messages, userMsg]
            ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
        }
      }
    } catch (e) {
      LogService.instance.w(
        'Bloc',
        '加载 AI 历史失败，回退当前列表: $e',
        chatId: event.chatId,
      );
    }

    // 回复前轻量状态预提取（不阻塞；解决「刚说完仍被追问」）
    // 番外平行会话：跳过预提取，不读取主线记忆。
    if (!isSideStory) {
      unawaited(_memoryEngine.preExtractState(
        characterId: character.id,
        userId: event.userId,
        currentMessage: event.content,
      ));
    }

    final memories = isSideStory
        ? const <Memory>[]
        : await _storage.getMemories(
            characterId: character.id,
            userId: event.userId,
            limit: Limit.memoryFetch,
          );

    SentimentResult sentiment = const SentimentResult(
      type: SentimentType.neutral,
      score: 0,
      label: '平静',
    );

    final config = character.interactionConfig;
    final replyMode = config?.replyMode ?? ReplyMode.normal;

    // 复用已加载消息列表，避免等待期反复读库导致卡顿
    List<ChatMessage> waitMsgs = messages;

    if (replyMode == ReplyMode.instant) {
      emit(ChatAITyping(waitMsgs, character.name));
      await Future.delayed(AppDurations.instantReplyDelay);
    } else if (replyMode == ReplyMode.delayed) {
      // 用户显式设置的延迟；上限 8s，避免「像卡死」
      final delay = (config?.replyDelaySeconds ?? 5).clamp(1, 8);
      emit(ChatAITyping(waitMsgs, character.name));
      await Future.delayed(Duration(seconds: delay));
    } else if (replyMode == ReplyMode.manual) {
      final prefs = await PrefsHelper.instance;
      final pending =
          prefs.getString(PrefKeys.pendingReply(event.chatId)) ?? '';
      await prefs.setString(PrefKeys.pendingReply(event.chatId),
          pending.isEmpty ? event.content : '$pending\n---\n${event.content}');
      emit(ChatMessagesLoaded(waitMsgs));
      return;
    } else {
      // normal: 轻量拟人延迟（旧逻辑最高 15s + 犹豫撤回，会被当成卡住）
      final preSentiment = SentimentAnalyzer.analyze(event.content);
      final random = Random();
      final msgLen = event.content.length;

      // 基础：200ms 思考 + 每字约 18ms，长文不再线性爆表
      int baseMs = 200 + (msgLen * 18).clamp(0, 900);

      double emotionMultiplier = 1.0;
      if (preSentiment.type == SentimentType.veryNegative ||
          preSentiment.type == SentimentType.negative) {
        emotionMultiplier = 1.2 + random.nextDouble() * 0.4; // 略慢，不再 3~5 倍
      } else if (preSentiment.type == SentimentType.veryPositive ||
          preSentiment.type == SentimentType.positive) {
        emotionMultiplier = 0.7 + random.nextDouble() * 0.25;
      } else {
        emotionMultiplier = 0.85 + random.nextDouble() * 0.35;
      }
      if (random.nextDouble() < 0.12) {
        emotionMultiplier = 0.45; // 偶尔快回
      }

      final totalMs = (baseMs * emotionMultiplier)
          .toInt()
          .clamp(AppDurations.typingDelayMinMs, AppDurations.typingDelayMaxMs);

      emit(ChatAITyping(waitMsgs, character.name));
      await Future.delayed(Duration(milliseconds: totalMs));
      // 已移除「犹豫撤回」：会关掉输入中再等数秒，表现为卡住后恢复
    }

    try {
      final lastUserMsg = waitMsgs.where((m) => !m.isFromAI).lastOrNull;
      if (lastUserMsg != null &&
          lastUserMsg.status.index < MessageStatus.delivered.index) {
        await _storage.saveChatMessage(lastUserMsg.copyWith(
          status: MessageStatus.delivered,
        ));
      }
    } catch (e) {
      LogService.instance.e(
          'Bloc', '_onSendMessage: pre-AI read status failed: $e',
          chatId: event.chatId);
    }

    try {
      _lastMessageTime = DateTime.now();

      sentiment = SentimentAnalyzer.analyze(event.content);
      // 番外平行会话：不落盘情绪/承诺/关系，也不读取主线承诺与关系进度。
      CharacterCommitment? commitmentForPrompt;
      RelationshipContext? relationship;
      if (!isSideStory) {
        // 用户话语先经本地情绪规则落盘；本轮模型状态会在回复完成后低权重归并。
        await _emotionEngine.updateEmotion(
          character: character,
          userId: event.userId,
          userMessage: event.content,
          userSentiment: sentiment,
          intimacyLevel: session.intimacyLevel,
        );
        await _commitmentService.createFromUserMessage(
          characterId: character.id,
          userId: event.userId,
          chatId: event.chatId,
          message: event.content,
        );
        final activeCommitment = await _commitmentService.getActive(
          characterId: character.id,
          userId: event.userId,
        );
        final commitmentResolution =
            await _commitmentService.resolveFromUserMessage(
          commitment: activeCommitment,
          message: event.content,
        );
        if (commitmentResolution != null) {
          await _storage.saveMemory(Memory(
            id: _uuid.v4(),
            characterId: character.id,
            userId: event.userId,
            type: MemoryType.milestone,
            content: commitmentResolution.summary,
            importance: MemoryImportance.important,
            keywords: const ['共同经历', '承诺结果'],
            createdAt: DateTime.now(),
            pinned: true,
          ));
        }
        commitmentForPrompt =
            commitmentResolution == null ? activeCommitment : null;
        relationship = await _relationshipService.updateFromUserMessage(
          chatId: event.chatId,
          message: event.content,
          sentiment: sentiment,
        );
        if (relationship.hasConflict != session.isInFriction) {
          await _storage.saveChatSession(session.copyWith(
            isInFriction: relationship.hasConflict,
            frictionDaysLeft: relationship.hasConflict ? 3 : 0,
            updatedAt: DateTime.now(),
          ));
        }
      }

      // 仅在需要最新列表时再读库（标记已读后可能变更 status）
      final chatMsgs = await _storage.getChatMessages(event.chatId);
      final july15EasterEggDirective =
          _buildJuly15EasterEggDirective(event.content);
      // 作息上下文（本地 Wellbeing，与设备操控无关）
      final wellbeingContext = await _buildWellbeingContext();
      String? sessionStateContext = _buildSessionStateAnchor(chatMsgs);
      sessionStateContext = _mergeInternalSystemContext(
        sessionStateContext,
        july15EasterEggDirective,
      );
      // 语C括号旁白：系统级规则，禁止模型把括号当对白
      if (hasActionBracket) {
        sessionStateContext = _mergeInternalSystemContext(
          sessionStateContext,
          _buildActionBracketSystemRule(),
        );
      }
      sessionStateContext =
          _mergeInternalSystemContext(sessionStateContext, wellbeingContext);
      if (!isSideStory) {
        final relatedGroupMemory = await _memoryEngine
            .buildRelatedGroupMemoryContext(character.id, event.content);
        sessionStateContext = _mergeInternalSystemContext(
          sessionStateContext,
          relatedGroupMemory,
        );
        sessionStateContext = _mergeInternalSystemContext(
          sessionStateContext,
          _commitmentService.buildPrompt(commitmentForPrompt),
        );
        sessionStateContext = _mergeInternalSystemContext(
          sessionStateContext,
          _relationshipService.buildPrompt(relationship!),
        );
      }

      // 声明后续会用到的变量
      String aiVisibleText = '';
      String reasoningText = '';

      // 普通角色聊天路径（无设备意图分类/工具执行）
      List<RegExpMatch> aiStickerMatches = const [];
      if (aiVisibleText.isEmpty) {
        // ── 主动决策引擎：在普通聊天前评估是否需要主动执行动作 ──
        ProactiveDecisionResult? proactiveDecision;
        ProactiveActionResult? proactiveAction;
        try {
          // 读取角色配置中的主动调用开关和敏感度
          final interactionConfig = character.interactionConfig;
          _proactiveDecisionEngine.enabled =
              interactionConfig?.enableProactiveToolCalling ?? false;
          _proactiveDecisionEngine.sensitivity =
              interactionConfig?.proactiveSensitivity ?? 'medium';

          if (_proactiveDecisionEngine.enabled) {
            final proactiveLlm = LlmService(settings: await _loadLlmSettings());
            proactiveDecision = await _proactiveDecisionEngine.evaluate(
              character: character,
              userId: event.userId,
              recentMessages: chatMsgs,
              storyStateService: _storyStateService,
              llm: proactiveLlm,
            );

            if (proactiveDecision.shouldAct &&
                proactiveDecision.actionType != null) {
              final executor = ProactiveActionExecutor(
                storyStateService: _storyStateService,
                characterId: character.id,
                userId: event.userId,
              );
              proactiveAction = await executor.execute(
                proactiveDecision.actionType!,
                proactiveDecision.actionArgs,
                event.content,
              );

              LogService.instance.i(
                'ProactiveAction',
                '${proactiveAction.actionType.name}: ${proactiveAction.log}',
                chatId: event.chatId,
              );
            }
          }
        } catch (e) {
          debugPrint('[ProactiveAction] 执行异常: $e');
        }

        // 非工具请求或工具路径未返回内容，走角色聊天路径
        // 将主动动作的上下文注入追加到系统提示中
        final effectiveContext = proactiveAction?.contextInjection != null
            ? '$sessionStateContext\n${proactiveAction!.contextInjection}'
            : sessionStateContext;

        try {
          final normalResult = await _streamAndProcessAIResponse(
            character: character,
            userId: event.userId,
            messageForAI: userMessageForAI,
            messages: messages,
            memories: memories,
            session: session,
            sentiment: sentiment,
            chatMsgs: chatMsgs,
            emit: emit,
            chatId: event.chatId,
            originalUserMessage: event.content,
            imageDescription: imageDescription,
            imagePaths: imagePaths,
            enableWebSearch: event.enableWebSearch,
            internalSystemContext: effectiveContext,
            isSideStory: isSideStory,
            forceConcise: event.forceConcise,
          );
          aiVisibleText = normalResult.cleanText;
          reasoningText = normalResult.reasoning;
          aiStickerMatches = normalResult.stickerMatches;
        } catch (e) {
          LogService.instance
              .e('ChatBloc', '角色聊天路径异常: $e', chatId: event.chatId);
          aiVisibleText = MessageSanitizer.failureFallbackText();
        }
      }

      if (aiVisibleText.trim().isEmpty) {
        LogService.instance.w(
          'ChatBloc',
          '_onSendMessage: AI response was empty',
          chatId: event.chatId,
        );
        aiVisibleText = '${character.name}才刚说完，你先别急。';
      }


      // 组装最终 AI 回复消息
      final aiReply = ChatMessage(
        id: _uuid.v4(),
        chatId: event.chatId,
        senderId: 'ai_',
        senderName: character.name,
        content: MessageSanitizer.sanitizeStream(aiVisibleText),
        type: MessageType.text,
        status: MessageStatus.sent,
        createdAt: DateTime.now(),
        isUser: false,
        reasoning: reasoningText.isNotEmpty ? reasoningText : null,
      );

      try {
        await _storage.saveChatMessage(aiReply);
        // AI 已回复 → 用户消息标为已读
        await _markUserMessagesAsRead(event.chatId, event.userId);
        // 标记会话活跃 → 在线状态实时更新
        unawaited(AIStatusService(_storage).markSessionActive(event.chatId));
        LogService.instance.i(
            'Bloc', '_onSendMessage: AI reply saved, hadTools=',
            chatId: event.chatId);
      } catch (e) {
        LogService.instance.e('Bloc', '_onSendMessage: AI reply save failed: ',
            chatId: event.chatId);
      }

      // 番外平行会话：不写主线内心状态/亲密度/记忆，主线记忆 100% 保留。
      if (!isSideStory) {
        await _persistTurnState(
          chatId: event.chatId,
          character: character,
          userId: event.userId,
          userMessage: event.content,
          aiReply: aiVisibleText,
          sentimentLabel: sentiment.label,
          emit: emit,
        );
      } else {
        // 番外会话自身的 lastMessage/时间仍需更新，供回看列表排序与预览。
        await _storage.updateChatSessionLastMessage(
          event.chatId,
          displayContent.isNotEmpty ? displayContent : event.content,
          DateTime.now(),
        );
      }

      // AI 回复中带贴纸标签 → 追加保存为独立的贴纸消息（此前提取后从未消费，贴纸丢失）
      if (_isStickerReplyEnabled(character) && aiStickerMatches.isNotEmpty) {
        await BuiltinStickerService.loadDefaultPack();
        for (final match in aiStickerMatches) {
          final stickerId = match.group(1) ?? '';
          final sticker = BuiltinStickerService.findStickerById(stickerId);
          if (sticker == null) continue;
          await _storage.saveChatMessage(ChatMessage(
            id: _uuid.v4(),
            chatId: event.chatId,
            senderId: 'ai_${character.id}',
            senderName: character.name,
            content: sticker.id,
            type: MessageType.sticker,
            status: MessageStatus.sent,
            createdAt: DateTime.now(),
            metadata: {
              'stickerId': sticker.id,
              'stickerName': sticker.name,
              'isBuiltinSticker': true,
              'stickerFile': sticker.file,
            },
          ));
        }
        emit(ChatMessagesLoaded(await _storage.getChatMessages(event.chatId)));
      }

      // 文本单聊：AI 回复成功后结算亲密度（此前漏接导致永远不加）
      // 番外平行会话：不结算主线亲密度。
      if (!isSideStory) {
        try {
          final preview =
              displayContent.isNotEmpty ? displayContent : event.content;
          await _applyIntimacyAfterReply(
            session: session,
            messageContent:
                displayContent.isNotEmpty ? displayContent : event.content,
            sentiment: sentiment,
            source: 'text',
            emit: emit,
            lastMessagePreview:
                preview.length > 80 ? preview.substring(0, 80) : preview,
            skipWhenEmotionLocked: true,
          );
        } catch (e) {
          LogService.instance.e(
            'Bloc',
            '_onSendMessage: intimacy update failed: $e',
            chatId: event.chatId,
          );
        }
      }

      // 记忆库自动更新：微记忆 + 降频 LLM/正则提取（修复「极少数永远不更新」）
      // 番外平行会话：不提取、不写入主线记忆。
      if (!isSideStory) {
        try {
          final recentForMemory = await _storage.getChatMessages(event.chatId);
          unawaited(_extractMemoriesAfterReply(
            chatId: event.chatId,
            character: character,
            userId: event.userId,
            justSavedAiMsg: aiReply,
            userContent: event.content,
            recentMessages: recentForMemory,
          ));
        } catch (e) {
          LogService.instance.w(
            'Memory',
            '调度记忆提取失败: $e',
            chatId: event.chatId,
          );
        }
      }

      // 重新读取最终消息列表
      try {
        final updatedMessages = await _storage.getChatMessages(event.chatId);
        emit(ChatMessagesLoaded(updatedMessages));
      } catch (e) {
        LogService.instance.e(
            'Bloc', '_onSendMessage: final message load failed: ',
            chatId: event.chatId);
        // 兜底再 emit 一次最终列表
        final currentMsgs = await _storage.getChatMessages(event.chatId);
        emit(ChatMessagesLoaded(currentMsgs));
      }
    } catch (e, stack) {
      LogService.instance.e(
          'Bloc', '_onSendMessage: unhandled error: $e\n$stack',
          chatId: event.chatId);
      // Show actual error instead of generic message
      String errorDisplay = e.toString();
      if (errorDisplay.contains('Timeout') ||
          errorDisplay.contains('timeout')) {
        errorDisplay = 'AI请求超时，请检查网络连接后重试';
      } else if (errorDisplay.contains('Socket') ||
          errorDisplay.contains('connection')) {
        errorDisplay = '连接AI服务失败，请检查网络设置';
      }
      emit(ChatError(errorDisplay));
    }
  }


  Future<void> _onProactiveReply(
    ChatProactiveReply event,
    Emitter<ChatState> emit,
  ) async {
    final session = await _storage.getChatSession(event.chatId);
    if (session == null) return;

    // 番外平行会话不触发主动回复（主动互动属于主线节奏）。
    if (session.isSideStory) return;

    if (session.isBlocked && session.blockedBy == BlockedBy.user) return;
    if (session.isBlocked && session.blockedBy == BlockedBy.ai) return;

    final character = await _storage.getAICharacter(session.aiCharacterId);
    if (character == null) return;
    final messages = await _storage.getChatMessages(event.chatId);

    try {
      final memories = await _storage.getMemories(
        characterId: character.id,
        userId: event.userId,
        limit: 10,
      );

      final recentUserMessages = messages
          .where((m) => !m.isFromAI)
          .take(3)
          .map((m) => m.content)
          .join('。');
      final topicHint = recentUserMessages.isNotEmpty
          ? '你们最近聊到了"$recentUserMessages"，可以自然地接续或换个角度聊'
          : '随意自然地开始一段对话';
      final activeCommitment = await _commitmentService.getActive(
        characterId: character.id,
        userId: event.userId,
      );
      final relationship = await _storage.getRelationshipContext(event.chatId);
      final now = DateTime.now();
      final proactiveMessages = messages.where((message) =>
          message.isFromAI && message.metadata?['isProactive'] == true);
      final deliveredToday = proactiveMessages
          .where((message) =>
              message.createdAt.year == now.year &&
              message.createdAt.month == now.month &&
              message.createdAt.day == now.day)
          .length;
      final latestProactive = proactiveMessages.isEmpty
          ? null
          : proactiveMessages
              .map((message) => message.createdAt)
              .reduce((a, b) => a.isAfter(b) ? a : b);
      final latestUserMessage = messages
          .where((message) => !message.isFromAI)
          .map((message) => message.createdAt)
          .fold<DateTime?>(
              null,
              (latest, value) =>
                  latest == null || value.isAfter(latest) ? value : latest);
      final policy = _proactivePolicy.evaluate(ProactivePolicyInput(
        enabled: character.interactionConfig?.enableMomentInteraction ?? false,
        frequencyHours:
            character.interactionConfig?.activeMessageFrequency ?? 2,
        now: now,
        lastUserMessageAt: latestUserMessage,
        lastProactiveAt: latestProactive,
        deliveredToday: deliveredToday,
        hasDueCommitment: activeCommitment?.isDue == true,
        respectsBoundary: relationship?.boundary?.isNotEmpty != true,
      ));
      if (!policy.allowed) {
        LogService.instance
            .i('ProactivePolicy', policy.reason, chatId: event.chatId);
        emit(ChatMessagesLoaded(messages));
        return;
      }
      emit(ChatAITyping(messages, character.name));
      final commitmentPrompt = _commitmentService.buildPrompt(activeCommitment);
      final relationshipPrompt = relationship == null
          ? ''
          : _relationshipService.buildPrompt(relationship);

      final silencePrompt = '（$topicHint。用你平时说话的风格，像真人一样发一条消息，'
          '不要用太整齐的句式，可以口语化一点，可以说说你现在在想什么或者分享一个想法'
          '只发一条简短的消息，不要说"你还好吗"这种太刻意的问候。）'
          '${commitmentPrompt.isEmpty ? '' : '\n$commitmentPrompt'}'
          '${relationshipPrompt.isEmpty ? '' : '\n$relationshipPrompt'}';

      final aiResponse = await _bridgeSendMessage(
        character: character,
        userId: event.userId,
        userMessage: silencePrompt,
        chatHistory: messages,
        memories: memories,
        intimacyLevel: session.intimacyLevel,
      );
      _completedTurnStates[event.chatId] =
          AiTurnState.parse(aiResponse) ?? _bridgeLastTurnState;

      final stickerReplyEnabled = _isStickerReplyEnabled(character);
      var text = aiResponse.trim().isNotEmpty
          ? (stickerReplyEnabled
              ? _normalizeBareStickerTags(aiResponse)
              : MessageSanitizer.sanitizeFinal(
                  _stripAIStickerOutput(aiResponse),
                ))
          : '';
      // 主动回复也需要过滤禁用短语
      text = MessageSanitizer.filterForbiddenPhrases(
        text,
        _storage.getForbiddenPhrases(),
      );
      if (text.isEmpty) return;

      final parts = stickerReplyEnabled ? _bridgeSplitMessages(text) : [text];

      emit(ChatAITyping(
          await _storage.getChatMessages(event.chatId), character.name));

      for (int i = 0; i < parts.length; i++) {
        if (i > 0) {
          await Future.delayed(AppDurations.multiMessageDelay);
          emit(ChatAITyping(
              await _storage.getChatMessages(event.chatId), character.name));
        }
        final part = parts[i];
        // 兼容整行贴纸 [STICKER:x] 或文本夹带（哈哈[STICKER:x]）
        final stickerMatch = stickerReplyEnabled
            ? (_stickerFullLineRe.firstMatch(part) ??
                _stickerTagRe.firstMatch(part))
            : null;
        if (stickerMatch != null) {
          final stickerId = stickerMatch.group(1)!;
          final sticker = BuiltinStickerService.findStickerById(stickerId);
          if (sticker != null) {
            await _storage.saveChatMessage(ChatMessage(
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
            ));
            // 文本夹带贴纸：剩余文本另存一条
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
                  metadata: const {'isProactive': true},
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
              metadata: const {'isProactive': true},
            ));
          }
        } else {
          await _storage.saveChatMessage(ChatMessage(
            id: _uuid.v4(),
            chatId: event.chatId,
            senderId: 'ai_${character.id}',
            senderName: character.name,
            content: part,
            type: MessageType.text,
            status: MessageStatus.sent,
            createdAt: DateTime.now(),
            metadata: const {'isProactive': true},
          ));
        }
        final currentMessages = await _storage.getChatMessages(event.chatId);
        emit(ChatMessagesLoaded(currentMessages));
      }

      // 重新读取最新 session，避免覆盖用户在此期间做的修改（如置顶）
      final latestSession =
          await _storage.getChatSession(event.chatId) ?? session;
      await _storage.saveChatSession(latestSession.copyWith(
        lastMessage: parts.last,
        lastMessageTime: DateTime.now(),
        updatedAt: DateTime.now(),
      ));
      await _persistTurnState(
        chatId: event.chatId,
        character: character,
        userId: event.userId,
        userMessage: silencePrompt,
        aiReply: parts.join('\n'),
        sentimentLabel: '平静',
        emit: emit,
      );
      if (activeCommitment?.isDue == true) {
        await _commitmentService.fulfill(activeCommitment!);
      }
    } catch (e) {
      LogService.instance
          .e('Bloc', '_onProactiveReply failed: $e', chatId: event.chatId);
      emit(ChatMessagesLoaded(await _storage.getChatMessages(event.chatId)));
    }
  }

}
