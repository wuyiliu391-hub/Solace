// 记忆提取与亲密处理（拆分生成，同库 part）
part of '../chat_bloc.dart';

mixin _BlocMemoryIntimacy on Bloc<ChatEvent, ChatState>, ChatBlocUtils, ChatBlocIntimacy, _ChatBlocCore, _BlocCallsBase, _BlocAiBridge {
  /// 统一亲密度结算：使用 ChatBlocIntimacy.calculateIntimacy，写回 session 并派发事件
  Future<void> _applyIntimacyAfterReply({
    required ChatSession session,
    required String messageContent,
    required SentimentResult sentiment,
    required String source,
    required Emitter<ChatState> emit,
    String? lastMessagePreview,
    bool skipWhenEmotionLocked = false,
  }) async {
    if (skipWhenEmotionLocked && _emotionLockedSessions.contains(session.id)) {
      // 情感锁定时仍更新最后消息时间，但不加减亲密度
      final locked = await _storage.getChatSession(session.id) ?? session;
      await _storage.saveChatSession(locked.copyWith(
        lastMessage: lastMessagePreview ?? messageContent,
        lastMessageTime: DateTime.now(),
        updatedAt: DateTime.now(),
      ));
      return;
    }

    // 重新读取，避免覆盖期间的会话修改（置顶/背景等）
    final latest = await _storage.getChatSession(session.id) ?? session;
    final intimacyResult = calculateIntimacy(
      session: latest,
      messageContent: messageContent,
      sentiment: sentiment,
      faModeActive: _storage.isFaModeEnabled(),
    );

    final updatedSession = latest.copyWith(
      lastMessage: lastMessagePreview ?? messageContent,
      lastMessageTime: DateTime.now(),
      updatedAt: DateTime.now(),
      intimacyLevel: intimacyResult.newLevel,
      dailyIntimacyCount: intimacyResult.dailyCount,
      lastIntimacyDate: intimacyResult.date,
    );
    await _storage.saveChatSession(updatedSession);
    await _recordIntimacyEvent(
      session: latest,
      newLevel: intimacyResult.newLevel,
      dailyCount: intimacyResult.dailyCount,
      source: source,
      messageContent: messageContent,
      sentiment: sentiment,
    );

    if (intimacyResult.newLevel != latest.intimacyLevel) {
      emit(ChatIntimacyChanged(
        chatId: session.id,
        oldLevel: latest.intimacyLevel,
        newLevel: intimacyResult.newLevel,
      ));
      LogService.instance.i(
        'Intimacy',
        'chat=${session.id} ${latest.intimacyLevel}→${intimacyResult.newLevel} ($source)',
        chatId: session.id,
      );
    }
  }


  Future<void> _recordIntimacyEvent({
    required ChatSession session,
    required int newLevel,
    required int dailyCount,
    required String source,
    required String messageContent,
    required SentimentResult sentiment,
  }) async {
    if (newLevel == session.intimacyLevel) return;

    final preview = messageContent.trim();
    await _storage.saveIntimacyEvent(IntimacyEvent(
      id: _uuid.v4(),
      chatId: session.id,
      userId: session.userId,
      characterId: session.aiCharacterId,
      oldLevel: session.intimacyLevel,
      newLevel: newLevel,
      delta: newLevel - session.intimacyLevel,
      dailyCount: dailyCount,
      source: source,
      messagePreview: preview.length > 80 ? preview.substring(0, 80) : preview,
      sentimentLabel: sentiment.label,
      sentimentType: sentiment.type.name,
      createdAt: DateTime.now(),
    ));
  }


  /// LLM 记忆提取降频：按「本会话用户消息条数」间隔触发，避免每条都打 API。
  /// 返回 true 时会推进计数；false 表示本轮跳过。
  bool _shouldExtractMemory(String chatId, List<ChatMessage> recentMessages) {
    final userMessageCount =
        recentMessages.where((m) => m.isUser || !m.isFromAI).length;
    // 至少 1 条有效用户话即可（旧逻辑要求 2 条导致新会话很难写入）
    if (userMessageCount < 1) return false;

    final lastExtracted = _lastMemoryExtractionUserCount[chatId] ?? 0;
    // 首次：第 1 条就提；之后每 3 条用户消息提一次（原 5 过稀 →「很久不更新」）
    final shouldExtract =
        lastExtracted == 0 || userMessageCount - lastExtracted >= 3;
    if (shouldExtract) {
      _lastMemoryExtractionUserCount[chatId] = userMessageCount;
    }
    return shouldExtract;
  }


  bool _looksLikeMicroMemorySignal(String userText, String aiText) {
    final t = userText.trim();
    if (t.isEmpty) return false;
    if (_microIgnoreSubstrings.any(t.contains)) return false;
    // 过短纯语气
    if (t.length < 4) return false;

    if (_microUserRegex.hasMatch(t)) return true;
    if (aiText.isNotEmpty && _microAiRegex.hasMatch(aiText)) return true;

    // 信息密度兜底：稍长、含实质内容的句子也记一条，避免「永远不更新」
    if (t.length >= 12) {
      final hasCjk = RegExp(r'[\u4e00-\u9fff]').hasMatch(t);
      final hasAlphaNum = RegExp(r'[A-Za-z0-9]').hasMatch(t);
      if (hasCjk || hasAlphaNum) return true;
    }
    return false;
  }


  Future<void> _maybeExtractMicroMemory({
    required String chatId,
    required String characterId,
    required String userId,
    required ChatMessage justSavedAiMsg,
    required String userContent,
  }) async {
    final trimmed = userContent.trim();
    if (!_looksLikeMicroMemorySignal(trimmed, justSavedAiMsg.content)) {
      return;
    }

    final last = _lastMicroTime[chatId];
    final now = DateTime.now();
    if (last != null && now.difference(last) < _microCooldown) return;
    _lastMicroTime[chatId] = now;

    final userSnip =
        trimmed.length > 80 ? '${trimmed.substring(0, 80)}…' : trimmed;
    final aiRaw = justSavedAiMsg.content.trim();
    final aiSnip = aiRaw.length > 80 ? '${aiRaw.substring(0, 80)}…' : aiRaw;
    final memContent =
        '用户说："$userSnip" — 对方回复："${aiSnip.isEmpty ? "（无回应文字）" : aiSnip}"';

    try {
      await _storage.saveMemory(Memory(
        id: _uuid.v4(),
        characterId: characterId,
        userId: userId,
        type: MemoryType.conversation,
        content: memContent,
        importance: MemoryImportance.normal,
        keywords: _extractKeywords(trimmed).take(6).toList(),
        createdAt: now,
        weight: 1.2,
      ));
      LogService.instance.i(
        'Memory',
        '微记忆已写入 (${trimmed.length}字)',
        chatId: chatId,
      );
    } catch (e) {
      LogService.instance.w('Bloc', '微记忆提取失败: $e', chatId: chatId);
    }
  }


  /// AI 回复成功后：微记忆（快）+ 降频 LLM/正则 extractMemory（稳）
  /// 全程 unawaited，不阻塞聊天气泡。
  Future<void> _extractMemoriesAfterReply({
    required String chatId,
    required AICharacter character,
    required String userId,
    required ChatMessage justSavedAiMsg,
    required String userContent,
    required List<ChatMessage> recentMessages,
  }) async {
    if (_isPureAIForced) return;
    // 拒绝/脱角色模板不入记忆：避免某个模型拒绝一次后，后续换模型仍被这段文本限制。
    if (MessageSanitizer.isAIRefusal(justSavedAiMsg.content)) return;
    // 全局记忆 off：仍允许写入库，便于用户之后打开模式能看到历史积累
    // （注入 prompt 由 memoryMode 控制，与写入解耦）

    // 1) 微记忆：尽量每轮有信息就记（自带冷却）
    try {
      await _maybeExtractMicroMemory(
        chatId: chatId,
        characterId: character.id,
        userId: userId,
        justSavedAiMsg: justSavedAiMsg,
        userContent: userContent,
      );
    } catch (e) {
      LogService.instance.w('Memory', '微记忆异常: $e', chatId: chatId);
    }

    // 2) 正式提取：降频，避免费用爆炸
    if (!_shouldExtractMemory(chatId, recentMessages)) return;

    try {
      // 取最近一段对话给引擎（含本轮 AI）
      final slice = recentMessages.length > 24
          ? recentMessages.sublist(recentMessages.length - 24)
          : recentMessages;
      await _memoryEngine.extractMemory(
        character: character,
        userId: userId,
        recentMessages: slice,
        characterName: character.name,
      );
      LogService.instance.i(
        'Memory',
        'extractMemory 完成 (msgs=${slice.length})',
        chatId: chatId,
      );
    } catch (e) {
      LogService.instance.w('Memory', 'extractMemory 失败: $e', chatId: chatId);
    }
  }


  /// 艾宾浩斯每日维护（20h 节流，静默执行，失败不打扰聊天）
  Future<void> _runMemoryMaintenanceQuietly(String chatId) async {
    try {
      final session = await _storage.getChatSession(chatId);
      if (session == null || session.aiCharacterId.isEmpty) return;
      await _memoryEngine.runDailyMaintenance(
        characterId: session.aiCharacterId,
        userId: session.userId,
      );
    } catch (e) {
      LogService.instance.w('Bloc', '每日记忆维护失败: $e', chatId: chatId);
    }
  }

}
