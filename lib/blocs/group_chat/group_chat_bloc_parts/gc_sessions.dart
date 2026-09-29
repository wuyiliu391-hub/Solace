// 群聊 BLoC 拆分 part
part of '../group_chat_bloc.dart';

mixin _GcSessions on Bloc<GroupChatEvent, GroupChatState>, _GcCore {
Future<void> _onLoadSessions(
  GroupChatLoadSessions event,
  Emitter<GroupChatState> emit,
) async {
  emit(GroupChatLoading());
  try {
    final sessions = await _storage.getGroupChatSessions(event.userId);
    emit(GroupChatSessionsLoaded(sessions));
  } catch (e) {
    LogService.instance.e('GroupChat', '_onLoadSessions failed: $e');
    emit(GroupChatError(e.toString()));
  }
}

Future<void> _onCreate(
  GroupChatCreate event,
  Emitter<GroupChatState> emit,
) async {
  emit(GroupChatLoading());
  try {
    final now = DateTime.now();
    final session = GroupChatSession(
      id: 'gc_${_uuid.v4()}',
      userId: event.userId,
      name: event.name,
      avatarUrl: event.avatarUrl,
      memberIds: List<String>.from(event.memberIds),
      aiCharacterIds: List<String>.from(event.aiCharacterIds),
      creatorId: event.userId,
      createdAt: now,
      updatedAt: now,
    );
    await _storage.saveGroupChatSession(session);

    // 成员入场仪式：每个 AI 成员写入「xxx 加入了群聊」系统消息
    // （只做 UI 展示，_toChatHistory/speakersSinceLastUser 均跳过系统消息）
    for (final id in session.aiCharacterIds) {
      final char = await _storage.getAICharacter(id);
      await _writeSystemMessage(
        session,
        '${char?.name ?? id} 加入了群聊',
      );
    }
    emit(GroupChatCreated(session));
  } catch (e) {
    LogService.instance.e('GroupChat', '_onCreate failed: $e');
    emit(GroupChatError(e.toString()));
  }
}

/// 写入一条系统消息（成员入场/离场等；isSystem 消息不进 AI 上下文）
Future<void> _writeSystemMessage(
  GroupChatSession session,
  String content,
) async {
  await _storage.saveGroupChatMessage(GroupChatMessage(
    id: _uuid.v4(),
    groupId: session.id,
    chatId: session.chatId,
    senderId: 'system',
    senderName: '系统',
    content: content,
    isSystem: true,
    type: GroupChatMessageType.system,
  ));
}

Future<void> _onDelete(
  GroupChatDelete event,
  Emitter<GroupChatState> emit,
) async {
  GroupChatMessage? targetToRestore;
  try {
    await _storage.deleteGroupChatSession(event.groupId);
    _replyingGroups.remove(event.groupId);
    _forcedSpeakers.remove(event.groupId);
    _lastAutoRunAt.remove(event.groupId);
    _lastAutoRunByCharacter
        .removeWhere((key, _) => key.startsWith('${event.groupId}:'));
    emit(GroupChatDeleted(event.groupId));
  } catch (e) {
    LogService.instance.e('GroupChat', '_onDelete failed: $e');
    emit(GroupChatError(e.toString()));
  }
}

}
