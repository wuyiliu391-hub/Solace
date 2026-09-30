// 群聊 BLoC 拆分 part
part of '../group_chat_bloc.dart';

mixin _GcSessionConfig on Bloc<GroupChatEvent, GroupChatState>, _GcCore, _GcSessions, _GcHelpers, _GcChatFlow, _GcConfigMemory {
Future<void> _onUpdateSession(
  GroupChatUpdateSession event,
  Emitter<GroupChatState> emit,
) async {
  try {
    final session = await _storage.getGroupChatSession(event.groupId);
    if (session == null) return;
    final updated = session.copyWith(
      name: event.name,
      avatarUrl: event.avatarUrl,
      clearAvatarUrl: event.clearAvatarUrl,
      isMuted: event.isMuted,
      isPinned: event.isPinned,
      backgroundImage: event.backgroundImage,
      notice: event.notice,
      isHidden: event.isHidden,
      updatedAt: DateTime.now(),
    );
    await _storage.saveGroupChatSession(updated);
    // 刷新列表（此前不 emit 导致静音/置顶 UI 不刷新）
    final sessions = await _storage.getGroupChatSessions('local_user');
    emit(GroupChatSessionsLoaded(sessions));
  } catch (e) {
    LogService.instance.e('GroupChat', '_onUpdateSession failed: $e');
    emit(GroupChatError(e.toString()));
  }
}

Future<void> _onAddMember(
  GroupChatAddMember event,
  Emitter<GroupChatState> emit,
) async {
  try {
    final session = await _storage.getGroupChatSession(event.groupId);
    if (session == null) return;
    final members = List<String>.from(session.memberIds);
    if (!members.contains(event.memberId)) {
      members.add(event.memberId);
      final aiIds = List<String>.from(session.aiCharacterIds);
      if (!aiIds.contains(event.memberId)) {
        aiIds.add(event.memberId);
      }
      final updated = session.copyWith(
        memberIds: members,
        aiCharacterIds: aiIds,
        updatedAt: DateTime.now(),
      );
      await _storage.saveGroupChatSession(updated);
      // 入场系统消息（对齐微信「xxx 加入了群聊」）
      final char = await _storage.getAICharacter(event.memberId);
      final name = event.memberId == 'local_user'
          ? '我'
          : (char?.name ?? event.memberId);
      await _writeSystemMessage(updated, '$name 加入了群聊');
      final sessions = await _storage.getGroupChatSessions('local_user');
      emit(GroupChatSessionsLoaded(sessions));
    }
  } catch (e) {
    LogService.instance.e('GroupChat', '_onAddMember failed: $e');
    emit(GroupChatError(e.toString()));
  }
}

Future<void> _onRemoveMember(
  GroupChatRemoveMember event,
  Emitter<GroupChatState> emit,
) async {
  try {
    final session = await _storage.getGroupChatSession(event.groupId);
    if (session == null) return;
    final members = List<String>.from(session.memberIds)
      ..remove(event.memberId);
    final aiIds = List<String>.from(session.aiCharacterIds)
      ..remove(event.memberId);
    final updated = session.copyWith(
      memberIds: members,
      aiCharacterIds: aiIds,
      updatedAt: DateTime.now(),
    );
    await _storage.saveGroupChatSession(updated);
    // 离场系统消息（成员已移除，角色卡可能仍可读；取不到用 id）
    final char = await _storage.getAICharacter(event.memberId);
    final name =
        event.memberId == 'local_user' ? '我' : (char?.name ?? event.memberId);
    await _writeSystemMessage(updated, '$name 离开了群聊');
    final sessions = await _storage.getGroupChatSessions('local_user');
    emit(GroupChatSessionsLoaded(sessions));
  } catch (e) {
    LogService.instance.e('GroupChat', '_onRemoveMember failed: $e');
    emit(GroupChatError(e.toString()));
  }
}

Future<void> _onMarkRead(
  GroupChatMarkRead event,
  Emitter<GroupChatState> emit,
) async {
  try {
    final session = await _storage.getGroupChatSession(event.groupId);
    if (session == null) return;
    final updated = session.copyWith(unreadCount: 0);
    await _storage.saveGroupChatSession(updated);
  } catch (e) {
    LogService.instance.e('GroupChat', '_onMarkRead failed: $e');
  }
}

Future<void> _onSetSpeakers(
  GroupChatSetSpeakers event,
  Emitter<GroupChatState> emit,
) async {
  _forcedSpeakers[event.groupId] = List<String>.from(event.speakerIds);
}

// ═══════════════════════════════════════════════════════
// 引擎配置 / 聊天记录（分支）管理
// ═══════════════════════════════════════════════════════

Future<void> _onUpdateConfig(
  GroupChatUpdateConfig event,
  Emitter<GroupChatState> emit,
) async {
  try {
    final session = await _storage.getGroupChatSession(event.groupId);
    if (session == null) return;
    final updated = session.copyWith(
      activationStrategy:
          event.activationStrategy ?? session.activationStrategy,
      generationMode: event.generationMode ?? session.generationMode,
      allowSelfResponses:
          event.allowSelfResponses ?? session.allowSelfResponses,
      disabledMemberIds: event.disabledMemberIds ?? session.disabledMemberIds,
      autoModeDelay: event.autoModeDelay ?? session.autoModeDelay,
      autoModeEnabled: event.autoModeEnabled ?? session.autoModeEnabled,
      autoModeDelaysByCharacter: event.autoModeDelaysByCharacter ??
          session.autoModeDelaysByCharacter,
      updatedAt: DateTime.now(),
    );
    await _storage.saveGroupChatSession(updated);
    // 自动接话开启中改间隔：同步内存计时并重启轮询（否则新间隔不生效）
    if (event.autoModeDelay != null &&
        _autoModeByGroup[event.groupId] == true) {
      _groupDelays[event.groupId] = event.autoModeDelay!;
      await _restartAutoModeTimer();
    }
    // 自动接话开关联动轮询
    if (event.autoModeEnabled != null) {
      await configureAutoMode(
          groupId: event.groupId, enabled: event.autoModeEnabled!);
    }
    final sessions = await _storage.getGroupChatSessions('local_user');
    emit(GroupChatSessionsLoaded(sessions));
  } catch (e) {
    LogService.instance.e('GroupChat', '_onUpdateConfig failed: $e');
    emit(GroupChatError(e.toString()));
  }
}

Future<void> _onCreateBranch(
  GroupChatCreateBranch event,
  Emitter<GroupChatState> emit,
) async {
  try {
    final session = await _storage.getGroupChatSession(event.groupId);
    final branch = event.forkMessageId != null && session != null
        ? await _storage.createGroupChatBranchFromMessage(
            groupId: event.groupId,
            sourceChatId: session.chatId,
            forkMessageId: event.forkMessageId!,
            name: event.name,
          )
        : await _storage.createGroupChatBranch(event.groupId, event.name);
    emit(GroupChatBranchesLoaded(
      groupId: event.groupId,
      branches: [branch],
      currentChatId: session?.chatId ?? '',
    ));
    if (session != null && branch.branchId != session.chatId) {
      add(GroupChatSwitchBranch(
          groupId: event.groupId, chatId: branch.branchId));
    }
  } catch (e) {
    LogService.instance.e('GroupChat', '_onCreateBranch failed: $e');
    emit(GroupChatError(e.toString()));
  }
}

Future<void> _onSwitchBranch(
  GroupChatSwitchBranch event,
  Emitter<GroupChatState> emit,
) async {
  try {
    final session = await _storage.getGroupChatSession(event.groupId);
    if (session == null) return;
    final updated = session.copyWith(
      chatId: event.chatId,
      updatedAt: DateTime.now(),
    );
    await _storage.saveGroupChatSession(updated);
    await _emitLatestPage(event.groupId, event.chatId);
  } catch (e) {
    LogService.instance.e('GroupChat', '_onSwitchBranch failed: $e');
    emit(GroupChatError(e.toString()));
  }
}

Future<void> _onDeleteBranch(
  GroupChatDeleteBranch event,
  Emitter<GroupChatState> emit,
) async {
  try {
    final session = await _storage.getGroupChatSession(event.groupId);
    final wasCurrent = session != null && session.chatId == event.chatId;
    await _storage.deleteGroupChatBranch(event.groupId, event.chatId);
    if (wasCurrent) {
      final branches = await _storage.getGroupChatBranches(event.groupId);
      if (branches.isNotEmpty) {
        final updated = session.copyWith(chatId: branches.first.branchId);
        await _storage.saveGroupChatSession(updated);
        emit(GroupChatBranchesLoaded(
          groupId: event.groupId,
          branches: branches,
          currentChatId: branches.first.branchId,
        ));
      } else {
        final fallback =
            await _storage.createGroupChatBranch(event.groupId, '默认聊天');
        final updated = session.copyWith(chatId: fallback.branchId);
        await _storage.saveGroupChatSession(updated);
        emit(GroupChatBranchesLoaded(
          groupId: event.groupId,
          branches: [fallback],
          currentChatId: fallback.branchId,
        ));
      }
    }
  } catch (e) {
    LogService.instance.e('GroupChat', '_onDeleteBranch failed: $e');
    emit(GroupChatError(e.toString()));
  }
}

// ═══════════════════════════════════════════════════════
// 自动接话轮询（ST auto mode：按 delay 周期检查，由 AI 接话）
// ═══════════════════════════════════════════════════════

/// 开/关某群的自动接话；任意群开启即启动轮询
Future<void> configureAutoMode({
  required String groupId,
  required bool enabled,
}) async {
  if (enabled) {
    final session = await _storage.getGroupChatSession(groupId);
    final delay = session?.autoModeDelay ?? 5;
    _groupDelays[groupId] = delay;
    _autoModeByGroup[groupId] = true;
    // 从当前时刻起算，首轮触发也遵守 delay（对标 ST setInterval）
    _lastAutoRunAt[groupId] = DateTime.now();
    await _restartAutoModeTimer();
  } else {
    _autoModeByGroup.remove(groupId);
    _groupDelays.remove(groupId);
    _lastAutoRunAt.remove(groupId);
    if (_autoModeByGroup.isEmpty) {
      _autoModeTimer?.cancel();
      _autoModeTimer = null;
    }
  }
}

/// 重启轮询（取全部启用群的最小 delay）
Future<void> _restartAutoModeTimer() async {
  _autoModeTimer?.cancel();
  if (_autoModeByGroup.isEmpty) return;
  var minDelay = 5;
  for (final delay in _groupDelays.values) {
    if (delay < minDelay) minDelay = delay;
  }
  for (final groupId in _autoModeByGroup.keys) {
    final session = await _storage.getGroupChatSession(groupId);
    if (session == null) continue;
    for (final delay in session.autoModeDelaysByCharacter.values) {
      if (delay > 0 && delay < minDelay) minDelay = delay;
    }
  }
  _autoModeTimer = Timer.periodic(
    Duration(seconds: minDelay),
    (_) => unawaited(_autoModeTick()),
  );
}

/// 轮询 tick（ST groupChatAutoModeWorker）：群未在生成中就触发，不挑最后消息类型。
/// 每群按各自 delay 限频（共享最短间隔定时器下用 lastRun 兜住长 delay 的群）。
Future<void> _autoModeTick() async {
  final now = DateTime.now();
  for (final groupId in _autoModeByGroup.keys.toList()) {
    if (_replyingGroups[groupId] == true) continue;
    final session = await _storage.getGroupChatSession(groupId);
    if (session == null) continue;
    if (!session.autoModeEnabled) {
      _autoModeByGroup.remove(groupId);
      _groupDelays.remove(groupId);
      _lastAutoRunAt.remove(groupId);
      continue;
    }
    final delay = _groupDelays[groupId] ?? session.autoModeDelay ?? 5;
    final lastRun = _lastAutoRunAt[groupId];
    if (lastRun != null && now.difference(lastRun).inSeconds < delay) {
      continue;
    }
    final history = await _storage.getGroupChatMessages(groupId,
        limit: 1, chatId: session.chatId);
    if (history.isEmpty) continue;
    final last = history.last;
    // 用户消息后的回应由用户消息触发路径负责，auto mode 不抢：
    // 否则 AI 互聊会淹没用户消息（用户插话必须被读到并回应）
    if (last.isUser) continue;
    _lastAutoRunAt[groupId] = now;
    _replyingGroups[groupId] = true;
    _followUpCount = 0;
    // ST activationText = 最后一条非系统消息内容；isUserInput 恒为 false
    await _generateAIReplies(
      groupId: groupId,
      userId: '',
      session: session,
      userMessage: '',
      activationText: last.isSystem ? '' : last.content,
      isUserInput: false,
      imagePaths: null,
      isFollowUp: false,
      excludeCharacterId: null,
    );
  }
  // 更新各群延迟后重启轮询（使新配置生效）
  await _restartAutoModeTimer();
}
}
