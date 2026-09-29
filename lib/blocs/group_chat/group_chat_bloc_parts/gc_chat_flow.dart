// 群聊 BLoC 拆分 part
part of '../group_chat_bloc.dart';

mixin _GcChatFlow on Bloc<GroupChatEvent, GroupChatState>, _GcCore, _GcSessions, _GcHelpers {
Future<void> _onLoadMessages(
  GroupChatLoadMessages event,
  Emitter<GroupChatState> emit,
) async {
  try {
    final session = await _storage.getGroupChatSession(event.groupId);
    final chatId = session?.chatId;
    // 多取一条判断是否还有更早历史；getGroupChatMessages 返回降序（新→旧），
    // 所以「最新 100 条」= 前 100 条，切掉的是最旧的尾条（与单聊方向相反）。
    final page = await _storage.getGroupChatMessages(event.groupId,
        chatId: chatId, limit: 101);
    final hasMore = page.length > 100;
    final messages = hasMore ? page.sublist(0, 100) : page;
    _loadedOffsets[event.groupId] = messages.length;
    _hasMoreByGroup[event.groupId] = hasMore;
    emit(GroupChatMessagesLoaded(event.groupId, messages, hasMore: hasMore));
    // 懒触发群聊社交记忆每日维护（艾宾浩斯衰减，20h 节流，unawaited）
    if (session != null && session.aiCharacterIds.isNotEmpty) {
      unawaited(_runSocialMaintenanceQuietly(
          event.groupId, session.aiCharacterIds));
    }
    // 顺带加载分支列表，供 UI 聊天记录管理
    if (session != null) {
      final branches = await _storage.getGroupChatBranches(event.groupId);
      emit(GroupChatBranchesLoaded(
        groupId: event.groupId,
        branches: branches,
        currentChatId: session.chatId ?? '',
        // 同批消息随分支态携带：UI 若因同帧合并只看到本状态，也能渲染消息区
        messages: messages,
      ));
    }
  } catch (e) {
    LogService.instance.e('GroupChat', '_onLoadMessages failed: $e');
    emit(GroupChatError(e.toString()));
  }
}

Future<void> _onSendMessage(
  GroupChatSendMessage event,
  Emitter<GroupChatState> emit,
) async {
  try {
    final now = DateTime.now();
    final session = await _storage.getGroupChatSession(event.groupId);
    // NSFW 内容检测：法模式下跳过（对齐单聊 chat_bloc 语义）
    final faMode = _storage.isFaModeEnabled();
    final nsfwResult = faMode
        ? const ContentFilterResult()
        : ContentFilter.check(event.content);
    if (nsfwResult.isNSFW) {
      emit(GroupChatError('检测到违规内容，消息未发送。'));
      return;
    }
    final msg = GroupChatMessage(
      id: _uuid.v4(),
      groupId: event.groupId,
      chatId: session?.chatId ?? '',
      senderId: event.userId,
      senderName: '我',
      content: event.content,
      isUser: true,
      type: (event.imagePaths?.isNotEmpty ?? false)
          ? GroupChatMessageType.image
          : GroupChatMessageType.text,
      timestamp: now,
      status: GroupChatMessageStatus.sent,
      metadata: {
        ...?event.metadata,
        if (event.imagePaths?.isNotEmpty ?? false)
          'imagePaths': event.imagePaths,
      },
    );
    await _storage.saveGroupChatMessage(msg);

    // 更新会话最后消息
    if (session != null) {
      final updated = session.copyWith(
        lastMessage: event.content.isNotEmpty
            ? event.content
            : (event.imagePaths?.isNotEmpty ?? false ? '[图片]' : ''),
        lastMessageTime: now,
        updatedAt: now,
      );
      await _storage.saveGroupChatSession(updated);
    }

    // 加载最新消息列表（重置到最新一页）
    await _emitLatestPage(event.groupId, session?.chatId);

    // 触发 AI 回复（真人群聊：轮流单角色回复 + 可能接话）
    unawaited(_triggerAIReply(
      groupId: event.groupId,
      userId: event.userId,
      userMessage: event.content,
      imagePaths: event.imagePaths,
      session: session,
    ));
  } catch (e) {
    LogService.instance.e('GroupChat', '_onSendMessage failed: $e');
    emit(GroupChatError(e.toString()));
  }
}

/// 从任意含消息列表的状态取当前已展示消息，供分页拼接使用。
List<GroupChatMessage> _currentVisibleMessages() {
  final s = state;
  if (s is GroupChatMessagesLoaded) return s.messages;
  if (s is GroupChatStreaming && s.messages.isNotEmpty) return s.messages;
  if (s is GroupChatTyping && s.messages.isNotEmpty) return s.messages;
  if (s is GroupChatBranchesLoaded && s.messages.isNotEmpty) return s.messages;
  return const [];
}

/// 重置到「最新一页」并 emit（发送/流式结束/切换分支等回到底部的场景）。
/// 不接收 Emitter 参数：内部直接用 Bloc.emit，兼容来自 on<> 处理器与普通
/// 私有方法（如 _generateOneReply）两类调用方。
Future<void> _emitLatestPage(String groupId, String? chatId) async {
  final page = await _storage.getGroupChatMessages(groupId,
      chatId: chatId, limit: 101);
  final hasMore = page.length > 100;
  final messages = hasMore ? page.sublist(0, 100) : page;
  _loadedOffsets[groupId] = messages.length;
  _hasMoreByGroup[groupId] = hasMore;
  emit(GroupChatMessagesLoaded(groupId, messages, hasMore: hasMore));
}

/// 重新加载群聊消息并 emit（消息操作后的统一刷新入口）。
/// 保留当前已加载窗口大小，避免删除/编辑/撤回后把「加载更多」翻出来的更早消息塌缩掉。
Future<void> _reloadMessages(
    String groupId, Emitter<GroupChatState> emit) async {
  final session = await _storage.getGroupChatSession(groupId);
  final loaded = _loadedOffsets[groupId];
  final target = (loaded != null && loaded > 100) ? loaded : 100;
  final page = await _storage.getGroupChatMessages(groupId,
      chatId: session?.chatId, limit: target + 1);
  final hasMore = page.length > target;
  final messages = hasMore ? page.sublist(0, target) : page;
  _loadedOffsets[groupId] = messages.length;
  _hasMoreByGroup[groupId] = hasMore;
  emit(GroupChatMessagesLoaded(groupId, messages, hasMore: hasMore));
}

/// 加载更早的群聊消息（上滑分页，对齐单聊）。
Future<void> _onLoadMoreMessages(
  GroupChatLoadMoreMessages event,
  Emitter<GroupChatState> emit,
) async {
  if (_loadingMore.contains(event.groupId)) return;
  _loadingMore.add(event.groupId);
  try {
    final session = await _storage.getGroupChatSession(event.groupId);
    final currentMessages = _currentVisibleMessages();
    final offset =
        _loadedOffsets[event.groupId] ?? currentMessages.length;
    // 多取一条判断是否还有更早；降序列表「更早一页」= 前 100 条。
    final page = await _storage.getGroupChatMessages(event.groupId,
        chatId: session?.chatId, limit: 101, offset: offset);
    if (page.isEmpty) {
      _hasMoreByGroup[event.groupId] = false;
      emit(GroupChatMessagesLoaded(event.groupId, currentMessages,
          hasMore: false));
      return;
    }
    final hasMore = page.length > 100;
    final olderMessages = hasMore ? page.sublist(0, 100) : page;
    final allMessages = [...currentMessages, ...olderMessages];
    _loadedOffsets[event.groupId] = offset + olderMessages.length;
    _hasMoreByGroup[event.groupId] = hasMore;
    emit(GroupChatMessagesLoaded(event.groupId, allMessages,
        hasMore: hasMore));
  } catch (e) {
    LogService.instance.e('GroupChat', '_onLoadMoreMessages failed: $e');
  } finally {
    _loadingMore.remove(event.groupId);
  }
}

/// 删除单条消息
Future<void> _onDeleteMessage(
  GroupChatDeleteMessage event,
  Emitter<GroupChatState> emit,
) async {
  try {
    final messages = await _storage.getGroupChatMessages(event.groupId);
    final msg = messages.cast<GroupChatMessage?>().firstWhere(
          (m) => m!.id == event.messageId,
          orElse: () => null,
        );
    if (msg == null) return;
    await _storage.deleteGroupChatMessage(msg.id);
    await _reloadMessages(event.groupId, emit);
  } catch (e) {
    LogService.instance.e('GroupChat', '_onDeleteMessage failed: $e');
    emit(GroupChatError(e.toString()));
  }
}

/// 收藏 / 取消收藏（metadata['bookmarked'] 翻转，无需 DB 迁移）
Future<void> _onToggleBookmark(
  GroupChatToggleBookmark event,
  Emitter<GroupChatState> emit,
) async {
  try {
    final messages = await _storage.getGroupChatMessages(event.groupId);
    final msg = messages.cast<GroupChatMessage?>().firstWhere(
          (m) => m!.id == event.messageId,
          orElse: () => null,
        );
    if (msg == null) return;
    final toggled = msg.copyWith(metadata: {
      ...?msg.metadata,
      'bookmarked': !msg.isBookmarked,
    });
    await _storage.saveGroupChatMessage(toggled);
    await _reloadMessages(event.groupId, emit);
  } catch (e) {
    LogService.instance.e('GroupChat', '_onToggleBookmark failed: $e');
    emit(GroupChatError(e.toString()));
  }
}

/// 编辑 AI 回复内容（仅 AI 消息，对齐单聊 ChatEditAIReply）
Future<void> _onEditAIReply(
  GroupChatEditAIReply event,
  Emitter<GroupChatState> emit,
) async {
  try {
    final messages = await _storage.getGroupChatMessages(event.groupId);
    final msg = messages.cast<GroupChatMessage?>().firstWhere(
          (m) => m!.id == event.messageId,
          orElse: () => null,
        );
    if (msg == null || msg.isUser || msg.isSystem || msg.isRecalled) return;
    final cleaned = MessageSanitizer.sanitizeFinal(event.newContent).trim();
    if (cleaned.isEmpty) return;
    await _storage.saveGroupChatMessage(msg.copyWith(
      content: cleaned,
      metadata: {
        ...?msg.metadata,
        'editedAt': DateTime.now().toIso8601String(),
      },
    ));
    await _reloadMessages(event.groupId, emit);
  } catch (e) {
    LogService.instance.e('GroupChat', '_onEditAIReply failed: $e');
    emit(GroupChatError(e.toString()));
  }
}

/// 撤回用户消息（2 分钟内 → 「已撤回」占位，对齐单聊 _recallMessage）
Future<void> _onRecallMessage(
  GroupChatRecallMessage event,
  Emitter<GroupChatState> emit,
) async {
  try {
    final messages = await _storage.getGroupChatMessages(event.groupId);
    final msg = messages.cast<GroupChatMessage?>().firstWhere(
          (m) => m!.id == event.messageId,
          orElse: () => null,
        );
    if (msg == null || !msg.isUser || msg.isRecalled) return;
    // 超过 2 分钟不可撤回
    if (DateTime.now().difference(msg.timestamp).inMinutes > 2) return;
    await _storage.saveGroupChatMessage(msg.copyWith(
      content: '已撤回',
      status: GroupChatMessageStatus.failed,
      metadata: {
        ...?msg.metadata,
        'recalled': true,
        'originalContent': msg.content,
      },
    ));
    await _reloadMessages(event.groupId, emit);
  } catch (e) {
    LogService.instance.e('GroupChat', '_onRecallMessage failed: $e');
    emit(GroupChatError(e.toString()));
  }
}

/// 重新生成 AI 回复：删除旧消息 → 用该角色重新回复（复用 _generateOneReply）
Future<void> _onRegenerateMessage(
  GroupChatRegenerateMessage event,
  Emitter<GroupChatState> emit,
) async {
  GroupChatMessage? targetToRestore;
  try {
    final session = await _storage.getGroupChatSession(event.groupId);
    if (session == null) return;
    if (_replyingGroups[event.groupId] == true) return; // 已有回复进行中

    final messages = await _storage.getGroupChatMessages(event.groupId,
        chatId: session.chatId);
    final targetIndex = messages.indexWhere((m) => m.id == event.messageId);
    if (targetIndex == -1) return;
    final target = messages[targetIndex];
    targetToRestore = target;
    if (target.isUser || target.isSystem || target.isRecalled) return;
    if (!target.senderId.startsWith('ai_')) return;

    final characterId = target.senderId.substring(3);
    // 激活文本：目标消息的前一条消息内容（无论谁发的），作为重新生成的输入
    final triggerContent = targetIndex + 1 < messages.length
        ? messages[targetIndex + 1].content
        : target.content;

    await _storage.deleteGroupChatMessage(event.messageId);
    _replyingGroups[event.groupId] = true;
    _followUpCount = 0;
    await _generateOneReply(
      groupId: event.groupId,
      userId: session.userId.isNotEmpty ? session.userId : 'local_user',
      session: session,
      characterId: characterId,
      userMessage: triggerContent,
      imagePaths: null,
      isFollowUp: false,
    );
    final generated = await _storage.getGroupChatMessages(event.groupId,
        limit: 20, chatId: session.chatId);
    final replacement = generated.cast<GroupChatMessage?>().firstWhere(
          (m) => m!.senderId == target.senderId && m.id != target.id,
          orElse: () => null,
        );
    if (replacement != null) {
      await _storage.deleteGroupChatMessage(replacement.id);
      final candidates = <String>[];
      for (final candidate in [
        ...target.swipeHistory,
        target.content,
        replacement.content,
      ]) {
        if (candidate.isNotEmpty && !candidates.contains(candidate)) {
          candidates.add(candidate);
        }
      }
      await _storage.saveGroupChatMessage(target.copyWith(
        content: replacement.content,
        swipeHistory: candidates,
        swipeIndex: candidates.length - 1,
        metadata: {
          ...?target.metadata,
          ...?replacement.metadata,
          'swipeSourceMessageId': target.id,
          'swipeIndex': candidates.length - 1,
        },
      ));
    }
    if (replacement == null) {
      await _storage.saveGroupChatMessage(target);
    }
    _replyingGroups[event.groupId] = false;
  } catch (e) {
    LogService.instance.e('GroupChat', '_onRegenerateMessage failed: $e');
    if (targetToRestore != null) {
      try {
        await _storage.saveGroupChatMessage(targetToRestore);
      } catch (_) {}
    }
    _replyingGroups[event.groupId] = false;
    emit(GroupChatError(e.toString()));
  }
}

/// AI 回复完成后（可能触发接话）
Future<void> _onAIMessageSaved(
  GroupChatAIMessageSaved event,
  Emitter<GroupChatState> emit,
) async {
  try {
    final session = await _storage.getGroupChatSession(event.groupId);
    if (session == null) {
      _replyingGroups[event.groupId] = false;
      return;
    }
    // autoModeEnabled：由定时轮询驱动接话，这里不再概率触发
    if (session.autoModeEnabled) {
      _replyingGroups[event.groupId] = false;
      unawaited(_drainPendingUserReply(event.groupId));
      return;
    }
    // 单轮已回复 2 个 AI → 不再接话
    if (_followUpCount >= 2) {
      _replyingGroups[event.groupId] = false;
      unawaited(_drainPendingUserReply(event.groupId));
      return;
    }
    // 35% 概率另一角色接话（非用户输入：模型从历史续写，AI 内容仅作选角文本）
    final roll = _random.nextDouble();
    if (roll < 0.35) {
      await _generateAIReplies(
        groupId: event.groupId,
        userId: '',
        session: session,
        userMessage: '',
        activationText: event.content,
        isUserInput: false,
        imagePaths: null,
        isFollowUp: true,
        excludeCharacterId: event.characterId,
      );
    } else {
      _replyingGroups[event.groupId] = false;
      unawaited(_drainPendingUserReply(event.groupId));
    }
  } catch (e) {
    LogService.instance.e('GroupChat', '_onAIMessageSaved failed: $e');
    _replyingGroups[event.groupId] = false;
  }
}

// ═══════════════════════════════════════════════════════
// AI 回复引擎（对标 SillyTavern generateGroupWrapper）
// ═══════════════════════════════════════════════════════

Future<void> _triggerAIReply({
  required String groupId,
  required String userId,
  required String userMessage,
  required List<String>? imagePaths,
  required GroupChatSession? session,
}) async {
  if (session == null) return;
  if (_replyingGroups[groupId] == true) {
    // AI 正在生成：用户消息排队，当前生成结束后补回应（不丢失）
    _pendingUserReply[groupId] = true;
    return;
  }
  _replyingGroups[groupId] = true;
  _followUpCount = 0;

  await _generateAIReplies(
    groupId: groupId,
    userId: userId,
    session: session,
    userMessage: userMessage,
    activationText: userMessage,
    isUserInput: true,
    imagePaths: imagePaths,
    isFollowUp: false,
    excludeCharacterId: null,
  );
}

/// 生成结束后消费排队中的用户消息：若最后一条仍是用户消息（未被回应），
/// 以用户消息为输入补一次 AI 回应（用户消息优先，不淹没不丢失）。
Future<void> _drainPendingUserReply(String groupId) async {
  if (_pendingUserReply[groupId] != true) return;
  _pendingUserReply[groupId] = false;
  try {
    final session = await _storage.getGroupChatSession(groupId);
    if (session == null) return;
    if (_replyingGroups[groupId] == true) return;
    final history = await _storage.getGroupChatMessages(groupId,
        limit: 1, chatId: session.chatId);
    if (history.isEmpty || !history.last.isUser) return; // 已被回应或无需处理
    _replyingGroups[groupId] = true;
    _followUpCount = 0;
    await _generateAIReplies(
      groupId: groupId,
      userId: session.userId.isNotEmpty ? session.userId : 'local_user',
      session: session,
      userMessage: history.last.content,
      activationText: history.last.content,
      isUserInput: true,
      imagePaths: null,
      isFollowUp: false,
      excludeCharacterId: null,
    );
    _replyingGroups[groupId] = false;
  } catch (e) {
    LogService.instance.e('GroupChat', '_drainPendingUserReply failed: $e');
    _replyingGroups[groupId] = false;
  }
}

/// ST generateGroupWrapper 的激活列表 → 逐个生成
///
/// [userMessage] 给模型的用户输入（自动接话/接话路径传空，模型从历史续写）；
/// [activationText] 选角用文本（ST activationText = 用户输入或最后一条消息内容）；
/// [isUserInput] 是否用户输入触发（ST isUserInput，直接决定 NATURAL 禁言/POOLED 轮换语义）。
Future<void> _generateAIReplies({
  required String groupId,
  required String userId,
  required GroupChatSession session,
  required String userMessage,
  required String activationText,
  required bool isUserInput,
  required List<String>? imagePaths,
  required bool isFollowUp,
  required String? excludeCharacterId,
}) async {
  // 多角色必须逐个使用真实角色卡生成。APPEND 的合并角色卡会丢失
  // 当前说话人的身份，导致不同角色复用同一套措辞，因此统一走 SWAP。

  final loadedHistory = await _storage.getGroupChatMessages(groupId,
      limit: 120, chatId: session.chatId);
  final history = _promptPipeline.trimHistory(loadedHistory);
  final members = await _loadMembers(session.aiCharacterIds);
  if (members.isEmpty) {
    _replyingGroups[groupId] = false;
    return;
  }

  // ST lastMessage = chat 最后一条；用户消息/系统消息 → 无“最后发言者”
  final lastMsg = history.isEmpty ? null : history.last;
  final lastSpeakerId = lastMsg != null &&
          !lastMsg.isUser &&
          !lastMsg.isSystem &&
          lastMsg.senderId.startsWith('ai_')
      ? lastMsg.senderId.substring(3)
      : null;

  final ctx = SpeakerContext(
    memberIds: session.aiCharacterIds,
    disabledMemberIds: session.disabledMemberIds,
    // POOLED 轮换池：用户输入触发时无人“已发言”（ST isUserInput 立即 break）
    historySpeakerIds:
        isUserInput ? const <String>[] : speakersSinceLastUser(history),
    lastMessageSpeakerId: lastSpeakerId,
    talkativeness: {for (final m in members) m.id: m.talkativeness},
    allowSelfResponses: session.allowSelfResponses,
    userInput: activationText,
    isUserInput: isUserInput,
    forceCharacterId: null,
    memberNames: {for (final m in members) m.id: m.name},
    random: _random,
  );

  var activated;
  final forcedIds = _forcedSpeakers[groupId] ?? const <String>[];
  if (forcedIds.isNotEmpty) {
    activated = resolveForcedSpeakers(
      forcedIds: forcedIds,
      memberIds: session.aiCharacterIds,
      disabledMemberIds: session.disabledMemberIds,
    );
  } else {
    activated = selectSpeakers(
      strategy: session.activationStrategy,
      ctx: ctx,
    );
  }
  if (excludeCharacterId != null) {
    activated = activated.where((id) => id != excludeCharacterId).toList();
  }
  if (!isUserInput) {
    final now = DateTime.now();
    activated = activated.where((id) {
      final last = _lastAutoRunByCharacter['$groupId:$id'];
      final delay =
          session.autoModeDelaysByCharacter[id] ?? session.autoModeDelay;
      return last == null || now.difference(last).inSeconds >= delay;
    }).toList();
  }
  if (activated.isEmpty) {
    _replyingGroups[groupId] = false;
    await _emitLatestPage(groupId, session.chatId);
    return;
  }

  // 手动点名只作用于当前这一轮，避免用户一次点名后后续每轮都被锁死。
  if (forcedIds.isNotEmpty) {
    _forcedSpeakers.remove(groupId);
  }

  // 逐个生成（SWAP 模式，ST 的 for chId of activatedMembers）
  for (final characterId in activated) {
    if (_replyingGroups[groupId] != true) break;
    await _generateOneReply(
      groupId: groupId,
      userId: userId,
      session: session,
      characterId: characterId,
      userMessage: userMessage,
      imagePaths: imagePaths,
      isFollowUp: isFollowUp,
    );
    if (!isUserInput) {
      _lastAutoRunByCharacter['$groupId:$characterId'] = DateTime.now();
    }
  }
  _replyingGroups[groupId] = false;
  // 生成结束：消费排队中的用户消息（若已被回应则 no-op）
  unawaited(_drainPendingUserReply(groupId));
}

/// 单个角色生成（SWAP 子流程，含 nudge）
Future<void> _generateOneReply({
  required String groupId,
  required String userId,
  required GroupChatSession session,
  required String characterId,
  required String userMessage,
  required List<String>? imagePaths,
  required bool isFollowUp,
  int duplicateRetry = 0,
  List<String> avoidReplies = const [],
}) async {
  final character = await _storage.getAICharacter(characterId);
  if (character == null) return;

  var history = await _storage.getGroupChatMessages(groupId,
      limit: 40, chatId: session.chatId);
  // 防复读：历史末尾正是本条触发消息时剔除，避免同一句话在 prompt 里出现两次
  // （用户输入触发时 userMessage=该条用户消息；接话续写时 userMessage 为空不处理）
  if (userMessage.isNotEmpty &&
      history.isNotEmpty &&
      history.last.isUser &&
      history.last.content == userMessage) {
    history = history.sublist(0, history.length - 1);
  }

  // 全员记忆聚合（全共享）：每个成员取 3 条，让角色互相知道实时记忆库
  final members = await _loadMembers(session.aiCharacterIds);
  final memories = await _aggregateMemberMemories(
    memberIds: session.aiCharacterIds,
    userId: userId.isNotEmpty ? userId : 'local_user',
  );

  final memberNames = await _buildMemberNames(session);
  final intro = buildGroupIntroPrompt(
    selfName: character.name,
    memberNames: memberNames,
    isNewChat: history.isEmpty,
  );
  // 群共享上下文：其他成员设定压缩 + 与用户记忆 + 群内社交记忆
  String shared;
  try {
    shared = await _memoryEngine.buildGroupSharedContext(
      self: character,
      members: members.where((m) => m.id != character.id).toList(),
      userId: userId.isNotEmpty ? userId : 'local_user',
      groupId: groupId,
      chatId: session.chatId,
    );
  } catch (_) {
    // Compatibility with older memory engines and test doubles that do not
    // yet accept the optional branch scope.
    shared = await _memoryEngine.buildGroupSharedContext(
      self: character,
      members: members.where((m) => m.id != character.id).toList(),
      userId: userId.isNotEmpty ? userId : 'local_user',
      groupId: groupId,
    );
  }
  // 朋友圈/动态闭环：让群聊里的角色也知道自己在朋友圈做过/看到过什么
  String momentCtx = '';
  try {
    momentCtx = await MomentContextService(_storage)
        .buildCharacterMomentContext(
      characterId: character.id,
      characterName: character.name,
      userId: userId.isNotEmpty ? userId : 'local_user',
    );
  } catch (e) {
    LogService.instance.w('GroupChat', '构建朋友圈上下文失败: $e');
  }
  final nudge = buildGroupNudge(character.name);
  final recentReplies = history
      .where((message) => !message.isUser && !message.isSystem)
      .toList()
      .reversed
      .take(4)
      .map((message) => '${message.senderName}：${message.content}')
      .toList()
      .reversed
      .toList();
  final voice = buildMemberVoicePrompt(
    self: character,
    otherMembers:
        members.where((member) => member.id != character.id).toList(),
    recentReplies: recentReplies,
    avoidReplies: avoidReplies,
  );
  // Keep generation compatible with older test doubles and migrated stores
  // that do not yet expose the optional lorebook table.
  List<GroupChatLorebookEntry> lore = const [];
  try {
    lore = await _storage.getGroupChatLorebookEntries(groupId,
        chatId: session.chatId);
  } catch (e) {
    LogService.instance
        .w('GroupChat', '读取 Lorebook 失败，跳过本轮注入: $e', chatId: groupId);
  }
  final internalContext = _promptPipeline.build(
    segments: [
      GroupPromptSegment(id: 'intro', content: intro, priority: 100),
      GroupPromptSegment(id: 'member_voice', content: voice, priority: 110),
      if (momentCtx.isNotEmpty)
        GroupPromptSegment(
            id: 'moment_context', content: momentCtx, priority: 55),
      GroupPromptSegment(id: 'shared_memory', content: shared, priority: 60),
      GroupPromptSegment(id: 'nudge', content: nudge, priority: 90),
    ],
    lorebook: lore,
    history: history,
    tokenBudget: 1800,
  );

  final chatHistory = _toChatHistory(history, character.id);

  emit(GroupChatTyping(groupId, character.name,
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
      character: character,
      userId: userId.isNotEmpty ? userId : 'local_user',
      userMessage: userMessage,
      chatHistory: chatHistory,
      memories: memories,
      intimacyLevel: 50,
      sentiment: null,
      imagePaths: imagePaths,
      internalSystemContext: internalContext,
    )) {
      fullText = chunk.content;
      fullReasoning = chunk.reasoning;
      usage = chunk.usage ?? usage;
      finishReason = chunk.finishReason ?? finishReason;
      // 思考阶段 content 为空、reasoning 非空也必须 emit，
      // 否则思考型模型表现为「无气泡但背后在准备回复」
      final streamText = MessageSanitizer.sanitizeStream(chunk.content);
      final streamReasoning = _mergeStreamReasoning(chunk);
      if (streamText.isNotEmpty || streamReasoning.isNotEmpty) {
        emit(GroupChatStreaming(groupId, character.name, streamText,
            reasoning: streamReasoning,
            messages: await _storage.getGroupChatMessages(groupId,
                chatId: session.chatId)));
      }
    }
  } catch (e) {
    LogService.instance.e('GroupChat', 'AI 回复失败: $e', chatId: groupId);
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
  // 拒绝/脱角色模板不入群聊记录与记忆：避免某个模型拒绝一次后，
  // 后续（含换模型后）群聊上下文持续被这段拒绝文本限制。
  if (MessageSanitizer.isAIRefusal(cleanText)) {
    _replyingGroups[groupId] = false;
    LogService.instance.w(
      'GroupChat',
      '检测到拒绝模板，跳过保存以防污染上下文',
      chatId: groupId,
    );
    return;
  }

  final recentAiReplies = history
      .where((message) => !message.isUser && !message.isSystem)
      .map((message) => message.content)
      .toList();
  final isDuplicate = [
    ...recentAiReplies,
    ...avoidReplies,
  ].any((previous) => isDuplicateGroupReply(cleanText, previous));
  if (isDuplicate && duplicateRetry < 1) {
    LogService.instance.w(
      'GroupChat',
      '检测到重复回复，重生成 ${character.name}',
      chatId: groupId,
    );
    await _generateOneReply(
      groupId: groupId,
      userId: userId,
      session: session,
      characterId: characterId,
      userMessage: userMessage,
      imagePaths: imagePaths,
      isFollowUp: isFollowUp,
      duplicateRetry: duplicateRetry + 1,
      avoidReplies: [...avoidReplies, cleanText],
    );
    return;
  }

  AIConfig? generationConfig;
  try {
    generationConfig = await _storage.getActiveAIConfig();
  } catch (e) {
    LogService.instance
        .w('GroupChat', '读取生成配置失败，保存基础元数据: $e', chatId: groupId);
  }
  final aiMsg = GroupChatMessage(
    id: _uuid.v4(),
    groupId: groupId,
    chatId: session.chatId,
    senderId: 'ai_$characterId',
    senderName: character.name,
    content: cleanText,
    isUser: false,
    type: GroupChatMessageType.text,
    timestamp: DateTime.now(),
    status: GroupChatMessageStatus.sent,
    metadata: {
      'generationId': generationId,
      'generationStartedAt': generationStartedAt.toIso8601String(),
      'generationMode': 'swap',
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

  // 沉淀群聊社交记忆：角色记住自己在群里说过的话（群内/单聊互通数据源）
  // 粗摘要降频（每5轮一条，避免噪音堆积）；每5轮触发一次 LLM 事件提取
  _groupMemoryCounter[groupId] = (_groupMemoryCounter[groupId] ?? 0) + 1;
  final round = _groupMemoryCounter[groupId]!;
  if (round % 5 == 1) {
    final summary =
        cleanText.length > 100 ? cleanText.substring(0, 100) : cleanText;
    await _memoryEngine.saveSocialMemory(
      characterId: characterId,
      targetCharacterId: groupId,
      interactionType: 'group_chat',
      content: '在群「${session.name}」中说过：$summary',
      keywords: const ['群聊'],
    );
  }
  if (round % 5 == 0) {
    // LLM 提取本轮群聊事件（unawaited，不阻塞气泡）
    unawaited(_extractGroupMemoriesAfterReply(
      groupId: groupId,
      session: session,
    ));
  }

  // 更新会话最后消息
  final latest = await _storage.getGroupChatSession(groupId);
  if (latest != null) {
    await _storage.saveGroupChatSession(latest.copyWith(
      lastMessage: cleanText,
      lastMessageTime: DateTime.now(),
      updatedAt: DateTime.now(),
    ));
  }
  await _emitLatestPage(groupId, session.chatId);

  // 触发接话判定
  add(GroupChatAIMessageSaved(
    groupId: groupId,
    characterId: characterId,
    content: cleanText,
  ));
}

}
