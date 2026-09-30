// 群聊 BLoC 拆分 part
part of '../group_chat_bloc.dart';

mixin _GcConfigMemory on Bloc<GroupChatEvent, GroupChatState>, _GcCore, _GcSessions, _GcHelpers, _GcChatFlow {
Future<void> _onSelectSwipe(
  GroupChatSelectSwipe event,
  Emitter<GroupChatState> emit,
) async {
  final session = await _storage.getGroupChatSession(event.groupId);
  final messages = await _storage.getGroupChatMessages(event.groupId,
      limit: 100000, chatId: session?.chatId);
  final message = messages.cast<GroupChatMessage?>().firstWhere(
        (m) => m!.id == event.messageId,
        orElse: () => null,
      );
  if (message == null ||
      event.index < 0 ||
      event.index >= message.swipeHistory.length) return;
  await _storage.saveGroupChatMessage(message.copyWith(
    content: message.swipeHistory[event.index],
    swipeIndex: event.index,
  ));
  await _emitLatestPage(event.groupId, session?.chatId);
}

Future<void> _onSaveLorebookEntry(
    GroupChatSaveLorebookEntry event, Emitter<GroupChatState> emit) async {
  await _storage.saveGroupChatLorebookEntry(event.entry);
}

Future<void> _onDeleteLorebookEntry(
    GroupChatDeleteLorebookEntry event, Emitter<GroupChatState> emit) async {
  await _storage.deleteGroupChatLorebookEntry(event.entryId);
}


Future<void> _generateAppendReply({
  required String groupId,
  required String userId,
  required GroupChatSession session,
  required String userMessage,
  required List<String>? imagePaths,
  required bool isFollowUp,
  required String? excludeCharacterId,
}) async {
  // ST 语义（group-chats.js:553）：APPEND=排除禁言成员；APPEND_DISABLED=包括禁言成员
  var enabledIds = session.generationMode == GroupGenerationMode.append
      ? session.aiCharacterIds
          .where((id) => !session.disabledMemberIds.contains(id))
          .toList()
      : List<String>.from(session.aiCharacterIds);
  enabledIds = enabledIds.where((id) => id != excludeCharacterId).toList();
  if (enabledIds.isEmpty) {
    _replyingGroups[groupId] = false;
    return;
  }
  final members = await _loadMembers(enabledIds);
  if (members.isEmpty) {
    _replyingGroups[groupId] = false;
    return;
  }

  final card = buildCombinedCard(
    members: members,
    joinPrefix: session.joinPrefix,
    joinSuffix: session.joinSuffix,
  );

  // 组合角色：用群名作为名称，卡字段合并
  final combo = AICharacter(
    id: session.id,
    name: session.name.isEmpty ? '群聊' : session.name,
    personality: card.personality,
    coreDesire: card.scenario,
    moralBoundary: '',
    backgroundStory: card.description,
    createdAt: DateTime.now(),
    talkativeness: 0.5,
    dialogueExamples: [],
  );

  final loadedHistory = await _storage.getGroupChatMessages(groupId,
      limit: 120, chatId: session.chatId);
  final history = _promptPipeline.trimHistory(loadedHistory);
  // 全员记忆聚合（全共享），修复原先只取 members.first 的遗漏
  final memories = await _aggregateMemberMemories(
    memberIds: enabledIds,
    userId: userId.isNotEmpty ? userId : 'local_user',
  );
  final memberNames = members.map((m) => m.name).toList();
  // 用户身份三件套（代称/性别/追加指令）：合体路径此前同样缺失，一并补上
  final comboUser = await _groupUserIdentity(_storage);
  final shared = await _memoryEngine.buildGroupSharedContext(
    self: combo,
    members: members,
    userId: userId.isNotEmpty ? userId : 'local_user',
    groupId: groupId,
    chatId: session.chatId,
  );
  // 注意引号：外层双引号、内层单引号，Dart 不允许同种引号嵌套
  final comboIdBlock = comboUser.identityBlock;
  final comboAdBlock = comboUser.addendumBlock;
  final internalContext = "${buildGroupIntroPrompt(
    selfName: session.name.isEmpty ? '群聊' : session.name,
    memberNames: [...memberNames, '你'],
    isNewChat: history.isEmpty,
  )}\n$shared"
      "${comboIdBlock.isEmpty ? '' : '\n$comboIdBlock'}"
      "${comboAdBlock.isEmpty ? '' : '\n$comboAdBlock'}";

  final chatHistory =
      _toChatHistory(history, combo.id, userAlias: comboUser.alias);

  emit(GroupChatTyping(groupId, combo.name,
      messages: await _storage.getGroupChatMessages(groupId,
          chatId: session.chatId)));
  _followUpCount++;

  String fullText = '';
  String fullReasoning = '';
  Map<String, dynamic>? usage;
  String? finishReason;
  final generationId = _uuid.v4();
  final generationStartedAt = DateTime.now();
  try {
    await for (final chunk in _aiService.sendMessageStream(
      character: combo,
      userId: userId.isNotEmpty ? userId : 'local_user',
      userMessage: userMessage,
      chatHistory: chatHistory,
      memories: memories,
      intimacyLevel: 50,
      sentiment: null,
      imagePaths: imagePaths,
      internalSystemContext: internalContext,
      requestScope: '群聊',
    )) {
      fullText = chunk.content;
      fullReasoning = chunk.reasoning;
      usage = chunk.usage ?? usage;
      finishReason = chunk.finishReason ?? finishReason;
      // 思考阶段也 emit（对齐 SWAP 分支），避免「无气泡但背后在准备回复」
      final streamText = MessageSanitizer.sanitizeStream(chunk.content);
      final streamReasoning = _mergeStreamReasoning(chunk);
      if (streamText.isNotEmpty || streamReasoning.isNotEmpty) {
        emit(GroupChatStreaming(groupId, combo.name, streamText,
            reasoning: streamReasoning,
            messages: await _storage.getGroupChatMessages(groupId,
                chatId: session.chatId)));
      }
    }
  } catch (e) {
    LogService.instance.e('GroupChat', 'APPEND 回复失败: $e', chatId: groupId);
    _replyingGroups[groupId] = false;
    return;
  }

  var cleanText = MessageSanitizer.sanitizeFinal(fullText).trim();
  if (_isNovelModeEnabled()) {
    cleanText = MessageSanitizer.normalizeNovelPunctuation(cleanText);
  }
  if (cleanText.isEmpty) {
    _replyingGroups[groupId] = false;
    return;
  }
  AIConfig? generationConfig;
  try {
    generationConfig = await _storage.getActiveAIConfig();
  } catch (e) {
    LogService.instance
        .w('GroupChat', '读取 APPEND 生成配置失败，保存基础元数据: $e', chatId: groupId);
  }
  final aiMsg = GroupChatMessage(
    id: _uuid.v4(),
    groupId: groupId,
    chatId: session.chatId,
    // 群身份归属（非首个成员）：避免污染 NATURAL/POOLED 的“最后发言者”检测
    senderId: 'ai_${session.id}',
    senderName: combo.name,
    content: cleanText,
    isUser: false,
    type: GroupChatMessageType.text,
    timestamp: DateTime.now(),
    status: GroupChatMessageStatus.sent,
    metadata: {
      'generationId': generationId,
      'generationStartedAt': generationStartedAt.toIso8601String(),
      'generationMode': session.generationMode.name,
      'model': generationConfig?.modelName,
      'temperature': generationConfig?.temperature,
      'maxTokens': generationConfig?.maxTokens,
      'finishReason': finishReason,
      'generationDurationMs':
          DateTime.now().difference(generationStartedAt).inMilliseconds,
      'usage': usage,
      'reasoning': fullReasoning,
      'promptTokenCount': usage?['prompt_tokens'] ?? usage?['input_tokens'],
      'completionTokenCount':
          usage?['completion_tokens'] ?? usage?['output_tokens'],
    },
  );
  await _storage.saveGroupChatMessage(aiMsg);
  unawaited(_refreshGroupRollingSummary(groupId, session));
  _replyingGroups[groupId] = false;
  await _emitLatestPage(groupId, session.chatId);
  // APPEND_DISABLED：生成后不触发自动接话
  if (session.generationMode == GroupGenerationMode.appendDisabled) {
    return;
  }
  add(GroupChatAIMessageSaved(
    groupId: groupId,
    characterId: members.first.id,
    content: cleanText,
  ));
}

/// 聚合群成员记忆（全共享）：每成员 3 条，总上限 12
}
