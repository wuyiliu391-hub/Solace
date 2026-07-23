import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';
import '../../models/group_chat_session.dart';
import '../../models/group_chat_message.dart';
import '../../repositories/local_storage_repository.dart';
import '../../services/log_service.dart';

part 'group_chat_event.dart';
part 'group_chat_state.dart';

/// AI 群聊 BLoC
class GroupChatBloc extends Bloc<GroupChatEvent, GroupChatState> {
  final LocalStorageRepository _storage;
  final _uuid = const Uuid();

  GroupChatBloc(this._storage) : super(GroupChatInitial()) {
    on<GroupChatLoadSessions>(_onLoadSessions);
    on<GroupChatCreate>(_onCreate);
    on<GroupChatDelete>(_onDelete);
    on<GroupChatLoadMessages>(_onLoadMessages);
    on<GroupChatSendMessage>(_onSendMessage);
    on<GroupChatUpdateSession>(_onUpdateSession);
    on<GroupChatAddMember>(_onAddMember);
    on<GroupChatRemoveMember>(_onRemoveMember);
    on<GroupChatMarkRead>(_onMarkRead);
  }

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
        name: event.name,
        avatarUrl: event.avatarUrl,
        memberIds: List<String>.from(event.memberIds),
        aiCharacterIds: List<String>.from(event.aiCharacterIds),
        creatorId: event.userId,
        createdAt: now,
        updatedAt: now,
      );
      await _storage.saveGroupChatSession(session);
      emit(GroupChatCreated(session));
    } catch (e) {
      LogService.instance.e('GroupChat', '_onCreate failed: $e');
      emit(GroupChatError(e.toString()));
    }
  }

  Future<void> _onDelete(
    GroupChatDelete event,
    Emitter<GroupChatState> emit,
  ) async {
    try {
      await _storage.deleteGroupChatSession(event.groupId);
      emit(GroupChatDeleted(event.groupId));
    } catch (e) {
      LogService.instance.e('GroupChat', '_onDelete failed: $e');
      emit(GroupChatError(e.toString()));
    }
  }

  Future<void> _onLoadMessages(
    GroupChatLoadMessages event,
    Emitter<GroupChatState> emit,
  ) async {
    try {
      final messages = await _storage.getGroupChatMessages(event.groupId);
      emit(GroupChatMessagesLoaded(event.groupId, messages));
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
      final msg = GroupChatMessage(
        id: _uuid.v4(),
        groupId: event.groupId,
        senderId: event.userId,
        senderName: '我',
        content: event.content,
        isUser: true,
        timestamp: DateTime.now(),
        status: GroupChatMessageStatus.sent,
      );
      await _storage.saveGroupChatMessage(msg);

      // 更新会话最后消息
      final session = await _storage.getGroupChatSession(event.groupId);
      if (session != null) {
        final updated = session.copyWith(
          lastMessage: event.content,
          lastMessageTime: msg.timestamp,
          updatedAt: msg.timestamp,
        );
        await _storage.saveGroupChatSession(updated);
      }

      // 加载最新消息列表
      final messages = await _storage.getGroupChatMessages(event.groupId);
      emit(GroupChatMessagesLoaded(event.groupId, messages));
    } catch (e) {
      LogService.instance.e('GroupChat', '_onSendMessage failed: $e');
      emit(GroupChatError(e.toString()));
    }
  }

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
        isMuted: event.isMuted,
        isPinned: event.isPinned,
        backgroundImage: event.backgroundImage,
        updatedAt: DateTime.now(),
      );
      await _storage.saveGroupChatSession(updated);
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
        final updated = session.copyWith(
          memberIds: members,
          updatedAt: DateTime.now(),
        );
        await _storage.saveGroupChatSession(updated);
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
      final updated = session.copyWith(
        memberIds: members,
        updatedAt: DateTime.now(),
      );
      await _storage.saveGroupChatSession(updated);
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
}
