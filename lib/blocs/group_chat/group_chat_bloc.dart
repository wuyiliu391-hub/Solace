import 'dart:async';
import 'dart:math';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';
import '../../models/group_chat_session.dart';
import '../../models/group_chat_message.dart';
import '../../models/chat_message.dart';
import '../../models/memory.dart';
import '../../models/ai_character.dart';
import '../../repositories/local_storage_repository.dart';
import '../../services/ai_service.dart';
import '../../services/log_service.dart';
import '../../utils/message_sanitizer.dart';

part 'group_chat_event.dart';
part 'group_chat_state.dart';

/// AI 群聊 BLoC
/// 
/// 支持：本地消息 + AI 角色轮流回复（真人群聊风格）+ 少量接话
class GroupChatBloc extends Bloc<GroupChatEvent, GroupChatState> {
  final LocalStorageRepository _storage;
  final AIService _aiService;
  final _uuid = const Uuid();
  final _random = Random();

  /// 轮询游标：决定下一条用户消息优先由哪个 AI 回复
  int _replyCursor = 0;

  /// 单轮接话守卫：限制一次用户消息最多触发 2 个 AI 回复
  int _followUpCount = 0;

  /// 当前群聊的 AI 回复互斥（防止并发触发多个流）
  final Map<String, bool> _replyingGroups = {};

  GroupChatBloc(this._storage, this._aiService) : super(GroupChatInitial()) {
    on<GroupChatLoadSessions>(_onLoadSessions);
    on<GroupChatCreate>(_onCreate);
    on<GroupChatDelete>(_onDelete);
    on<GroupChatLoadMessages>(_onLoadMessages);
    on<GroupChatSendMessage>(_onSendMessage);
    on<GroupChatUpdateSession>(_onUpdateSession);
    on<GroupChatAddMember>(_onAddMember);
    on<GroupChatRemoveMember>(_onRemoveMember);
    on<GroupChatMarkRead>(_onMarkRead);
    on<GroupChatAIMessageSaved>(_onAIMessageSaved);
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
      _replyingGroups.remove(event.groupId);
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
      final now = DateTime.now();
      final msg = GroupChatMessage(
        id: _uuid.v4(),
        groupId: event.groupId,
        senderId: event.userId,
        senderName: '我',
        content: event.content,
        isUser: true,
        type: (event.imagePaths?.isNotEmpty ?? false)
            ? GroupChatMessageType.image
            : GroupChatMessageType.text,
        timestamp: now,
        status: GroupChatMessageStatus.sent,
        metadata: (event.imagePaths?.isNotEmpty ?? false)
            ? {'imagePaths': event.imagePaths}
            : null,
      );
      await _storage.saveGroupChatMessage(msg);

      // 更新会话最后消息
      final session = await _storage.getGroupChatSession(event.groupId);
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

      // 加载最新消息列表
      final messages = await _storage.getGroupChatMessages(event.groupId);
      emit(GroupChatMessagesLoaded(event.groupId, messages));

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

  /// AI 回复完成后（可能触发接话）
  Future<void> _onAIMessageSaved(
    GroupChatAIMessageSaved event,
    Emitter<GroupChatState> emit,
  ) async {
    try {
      // 单轮已回复 2 个 AI → 不再接话
      if (_followUpCount >= 2) {
        _replyingGroups[event.groupId] = false;
        return;
      }
      final session = await _storage.getGroupChatSession(event.groupId);
      if (session == null) {
        _replyingGroups[event.groupId] = false;
        return;
      }
      // 35% 概率另一角色接话
      final roll = _random.nextDouble();
      if (roll < 0.35) {
        await _generateAIReplies(
          groupId: event.groupId,
          userId: '',
          session: session,
          userMessage: event.content,
          imagePaths: null,
          isFollowUp: true,
          excludeCharacterId: event.characterId,
        );
      } else {
        _replyingGroups[event.groupId] = false;
      }
    } catch (e) {
      LogService.instance.e('GroupChat', '_onAIMessageSaved failed: $e');
      _replyingGroups[event.groupId] = false;
    }
  }

  // ═══════════════════════════════════════════════════════
  // AI 回复引擎
  // ═══════════════════════════════════════════════════════

  Future<void> _triggerAIReply({
    required String groupId,
    required String userId,
    required String userMessage,
    required List<String>? imagePaths,
    required GroupChatSession? session,
  }) async {
    if (session == null) return;
    if (_replyingGroups[groupId] == true) return; // 已有回复进行中
    _replyingGroups[groupId] = true;
    _followUpCount = 0;

    await _generateAIReplies(
      groupId: groupId,
      userId: userId,
      session: session,
      userMessage: userMessage,
      imagePaths: imagePaths,
      isFollowUp: false,
      excludeCharacterId: null,
    );
  }

  /// 生成 AI 回复：轮流选择 1 个角色，流式输出后落库
  Future<void> _generateAIReplies({
    required String groupId,
    required String userId,
    required GroupChatSession session,
    required String userMessage,
    required List<String>? imagePaths,
    required bool isFollowUp,
    required String? excludeCharacterId,
  }) async {
    final aiIds = session.aiCharacterIds
        .where((id) => id != excludeCharacterId)
        .toList();
    if (aiIds.isEmpty) {
      _replyingGroups[groupId] = false;
      return;
    }

    // 轮流：主回复角色从游标开始；接话时随机选一个
    int idx;
    if (isFollowUp) {
      idx = _random.nextInt(aiIds.length);
    } else {
      idx = _replyCursor % aiIds.length;
      _replyCursor = (_replyCursor + 1) % session.aiCharacterIds.length;
    }
    final characterId = aiIds[idx];

    final character = await _storage.getAICharacter(characterId);
    if (character == null) {
      _replyingGroups[groupId] = false;
      return;
    }

    // 加载群消息历史
    final history = await _storage.getGroupChatMessages(groupId, limit: 40);
    // 按角色取记忆
    final memories = await _storage.getMemories(
      characterId: characterId,
      userId: userId.isNotEmpty ? userId : 'local_user',
      limit: 8,
    );

    // 群聊上下文注入
    final memberNames = await _buildMemberNames(session);
    final internalContext =
        '这是一个群聊。你是「${character.name}」，群成员有：${memberNames.join('、')}。'
        '你在群里发言要自然，像真人聊天一样，语气符合你的性格。'
        '刚才大家聊的内容见历史消息。';

    // 转换历史
    final chatHistory = _toChatHistory(history, character.id);

    // 流式回复
    emit(GroupChatTyping(groupId, character.name,
        messages: await _storage.getGroupChatMessages(groupId)));
    _followUpCount++;

    String fullText = '';
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
        if (fullText.isNotEmpty) {
          emit(GroupChatStreaming(groupId, character.name, fullText,
              messages: await _storage.getGroupChatMessages(groupId)));
        }
      }
    } catch (e) {
      LogService.instance.e('GroupChat', 'AI 回复失败: $e', chatId: groupId);
      _replyingGroups[groupId] = false;
      emit(GroupChatMessagesLoaded(
          groupId, await _storage.getGroupChatMessages(groupId)));
      return;
    }

    final cleanText = MessageSanitizer.sanitizeFinal(fullText).trim();
    if (cleanText.isNotEmpty) {
      final aiMsg = GroupChatMessage(
        id: _uuid.v4(),
        groupId: groupId,
        senderId: 'ai_$characterId',
        senderName: character.name,
        content: cleanText,
        isUser: false,
        type: GroupChatMessageType.text,
        timestamp: DateTime.now(),
        status: GroupChatMessageStatus.sent,
      );
      await _storage.saveGroupChatMessage(aiMsg);

      // 更新会话最后消息
      final latest = await _storage.getGroupChatSession(groupId);
      if (latest != null) {
        await _storage.saveGroupChatSession(latest.copyWith(
          lastMessage: cleanText,
          lastMessageTime: DateTime.now(),
          updatedAt: DateTime.now(),
        ));
      }
      emit(GroupChatMessagesLoaded(
          groupId, await _storage.getGroupChatMessages(groupId)));

      // 触发接话判定
      add(GroupChatAIMessageSaved(
        groupId: groupId,
        characterId: characterId,
        content: cleanText,
      ));
    } else {
      _replyingGroups[groupId] = false;
      emit(GroupChatMessagesLoaded(
          groupId, await _storage.getGroupChatMessages(groupId)));
    }
  }

  /// 群成员名称列表（AI 用真实名，用户显示"你"）
  Future<List<String>> _buildMemberNames(GroupChatSession session) async {
    final names = <String>[];
    for (final id in session.aiCharacterIds) {
      final ch = await _storage.getAICharacter(id);
      names.add(ch?.name ?? id);
    }
    // 用户成员（非 AI 的 memberIds）
    for (final id in session.memberIds) {
      if (!session.aiCharacterIds.contains(id)) {
        names.add(id == 'local_user' ? '你' : id);
      }
    }
    return names;
  }

  /// 群消息 → 单聊格式（供 AIService 消费）
  List<ChatMessage> _toChatHistory(
      List<GroupChatMessage> history, String selfCharacterId) {
    final result = <ChatMessage>[];
    for (final m in history) {
      if (m.isSystem) continue;
      final isAi = !m.isUser;
      // 自己是说话人时用 content；他人消息标注说话人
      final content = isAi
          ? (m.senderId == 'ai_$selfCharacterId'
              ? m.content
              : '【${m.senderName}】${m.content}')
          : (m.senderName == '我' ? m.content : '【${m.senderName}】${m.content}');
      result.add(ChatMessage(
        id: m.id,
        chatId: m.groupId,
        senderId: m.senderId,
        senderName: m.senderName,
        content: content,
        isUser: m.isUser,
        isSystem: false,
        type: MessageType.text,
        status: MessageStatus.sent,
        timestamp: m.timestamp,
        metadata: m.metadata,
      ));
    }
    return result;
  }

  // ═══════════════════════════════════════════════════════
  // 会话管理
  // ═══════════════════════════════════════════════════════

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
        notice: event.notice,
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
}
