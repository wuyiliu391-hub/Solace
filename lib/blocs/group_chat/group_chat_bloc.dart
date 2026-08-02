import 'dart:async';
import 'dart:math';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';
import '../../models/group_chat_session.dart';
import '../../models/group_chat_message.dart';
import '../../models/group_chat_branch.dart';
import '../../models/chat_message.dart';
import '../../models/memory.dart';
import '../../models/ai_character.dart';
import '../../repositories/local_storage_repository.dart';
import '../../services/ai_service.dart';
import '../../services/log_service.dart';
import '../../utils/message_sanitizer.dart';
import '../../utils/content_filter.dart';
import 'group_chat_speaker.dart';
import 'group_chat_prompts.dart';

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

  /// 单轮接话守卫：限制一次用户消息最多触发 2 个 AI 回复
  int _followUpCount = 0;

  /// 当前群聊的 AI 回复互斥（防止并发触发多个流）
  final Map<String, bool> _replyingGroups = {};

  /// 自动接话轮询
  Timer? _autoModeTimer;
  final Map<String, bool> _autoModeByGroup = {};
  final Map<String, int> _groupDelays = {};

  /// 手动锁定发言人（内存态，群聊 UI 激活条写入）
  final Map<String, List<String>> _forcedSpeakers = {};

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
    on<GroupChatSetSpeakers>(_onSetSpeakers);
    on<GroupChatAIMessageSaved>(_onAIMessageSaved);
    on<GroupChatUpdateConfig>(_onUpdateConfig);
    on<GroupChatCreateBranch>(_onCreateBranch);
    on<GroupChatSwitchBranch>(_onSwitchBranch);
    on<GroupChatDeleteBranch>(_onDeleteBranch);
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
      _forcedSpeakers.remove(event.groupId);
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
      final session = await _storage.getGroupChatSession(event.groupId);
      final chatId = session?.chatId;
      final messages =
          await _storage.getGroupChatMessages(event.groupId, chatId: chatId);
      emit(GroupChatMessagesLoaded(event.groupId, messages));
      // 顺带加载分支列表，供 UI 聊天记录管理
      if (session != null) {
        final branches = await _storage.getGroupChatBranches(event.groupId);
        emit(GroupChatBranchesLoaded(
          groupId: event.groupId,
          branches: branches,
          currentChatId: session.chatId ?? '',
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
        metadata: (event.imagePaths?.isNotEmpty ?? false)
            ? {'imagePaths': event.imagePaths}
            : null,
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

      // 加载最新消息列表
      final messages = await _storage
          .getGroupChatMessages(event.groupId, chatId: session?.chatId);
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
      final session = await _storage.getGroupChatSession(event.groupId);
      if (session == null) {
        _replyingGroups[event.groupId] = false;
        return;
      }
      // autoModeEnabled：由定时轮询驱动接话，这里不再概率触发
      if (session.autoModeEnabled) {
        _replyingGroups[event.groupId] = false;
        return;
      }
      // 单轮已回复 2 个 AI → 不再接话
      if (_followUpCount >= 2) {
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

  /// ST generateGroupWrapper 的激活列表 → 逐个生成
  Future<void> _generateAIReplies({
    required String groupId,
    required String userId,
    required GroupChatSession session,
    required String userMessage,
    required List<String>? imagePaths,
    required bool isFollowUp,
    required String? excludeCharacterId,
  }) async {
    // 生成模式 APPEND：合并卡一次生成
    if (session.generationMode != GroupGenerationMode.swap) {
      await _generateAppendReply(
        groupId: groupId,
        userId: userId,
        session: session,
        userMessage: userMessage,
        imagePaths: imagePaths,
        isFollowUp: isFollowUp,
        excludeCharacterId: excludeCharacterId,
      );
      return;
    }

    final history = await _storage.getGroupChatMessages(groupId,
        limit: 40, chatId: session.chatId);
    final members = await _loadMembers(session.aiCharacterIds);
    if (members.isEmpty) {
      _replyingGroups[groupId] = false;
      return;
    }

    final ctx = SpeakerContext(
      memberIds: session.aiCharacterIds,
      disabledMemberIds: session.disabledMemberIds,
      historySpeakerIds: _extractHistorySpeakers(history),
      lastMessageSpeakerId: _lastAISpeaker(history),
      talkativeness: {for (final m in members) m.id: m.talkativeness},
      allowSelfResponses: session.allowSelfResponses,
      userInput: userMessage,
      isUserInput: userMessage.isNotEmpty,
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
    if (activated.isEmpty) {
      _replyingGroups[groupId] = false;
      emit(GroupChatMessagesLoaded(groupId,
          await _storage.getGroupChatMessages(groupId, chatId: session.chatId)));
      return;
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
    }
    _replyingGroups[groupId] = false;
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
  }) async {
    final character = await _storage.getAICharacter(characterId);
    if (character == null) return;

    final history = await _storage.getGroupChatMessages(groupId,
        limit: 40, chatId: session.chatId);
    final memories = await _storage.getMemories(
      characterId: characterId,
      userId: userId.isNotEmpty ? userId : 'local_user',
      limit: 8,
    );

    final memberNames = await _buildMemberNames(session);
    final intro = buildGroupIntroPrompt(
      selfName: character.name,
      memberNames: memberNames,
      isNewChat: history.isEmpty,
    );
    final nudge = buildGroupNudge(character.name);
    final internalContext = '$intro\n$nudge';

    final chatHistory = _toChatHistory(history, character.id);

    emit(GroupChatTyping(groupId, character.name,
        messages: await _storage
            .getGroupChatMessages(groupId, chatId: session.chatId)));
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
              messages: await _storage
                  .getGroupChatMessages(groupId, chatId: session.chatId)));
        }
      }
    } catch (e) {
      LogService.instance.e('GroupChat', 'AI 回复失败: $e', chatId: groupId);
      _replyingGroups[groupId] = false;
      return;
    }

    final cleanText = MessageSanitizer.sanitizeFinal(fullText).trim();
    if (cleanText.isEmpty) {
      _replyingGroups[groupId] = false;
      return;
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
    emit(GroupChatMessagesLoaded(groupId,
        await _storage.getGroupChatMessages(groupId, chatId: session.chatId)));

    // 触发接话判定
    add(GroupChatAIMessageSaved(
      groupId: groupId,
      characterId: characterId,
      content: cleanText,
    ));
  }

  /// APPEND 合并卡生成（ST generation_mode APPEND / APPEND_DISABLED）
  Future<void> _generateAppendReply({
    required String groupId,
    required String userId,
    required GroupChatSession session,
    required String userMessage,
    required List<String>? imagePaths,
    required bool isFollowUp,
    required String? excludeCharacterId,
  }) async {
    var enabledIds = session.aiCharacterIds
        .where((id) => !session.disabledMemberIds.contains(id))
        .toList();
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

    final history = await _storage.getGroupChatMessages(groupId,
        limit: 40, chatId: session.chatId);
    final memories = await _storage.getMemories(
      characterId: members.first.id,
      userId: userId.isNotEmpty ? userId : 'local_user',
      limit: 8,
    );
    final memberNames = members.map((m) => m.name).toList();
    final internalContext = buildGroupIntroPrompt(
      selfName: session.name.isEmpty ? '群聊' : session.name,
      memberNames: [...memberNames, '你'],
      isNewChat: history.isEmpty,
    );

    final chatHistory = _toChatHistory(history, combo.id);

    emit(GroupChatTyping(groupId, combo.name,
        messages: await _storage
            .getGroupChatMessages(groupId, chatId: session.chatId)));
    _followUpCount++;

    String fullText = '';
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
      )) {
        fullText = chunk.content;
        if (fullText.isNotEmpty) {
          emit(GroupChatStreaming(groupId, combo.name, fullText,
              messages: await _storage
                  .getGroupChatMessages(groupId, chatId: session.chatId)));
        }
      }
    } catch (e) {
      LogService.instance.e('GroupChat', 'APPEND 回复失败: $e', chatId: groupId);
      _replyingGroups[groupId] = false;
      return;
    }

    final cleanText = MessageSanitizer.sanitizeFinal(fullText).trim();
    if (cleanText.isEmpty) {
      _replyingGroups[groupId] = false;
      return;
    }
    final aiMsg = GroupChatMessage(
      id: _uuid.v4(),
      groupId: groupId,
      chatId: session.chatId,
      senderId: 'ai_${members.first.id}',
      senderName: combo.name,
      content: cleanText,
      isUser: false,
      type: GroupChatMessageType.text,
      timestamp: DateTime.now(),
      status: GroupChatMessageStatus.sent,
    );
    await _storage.saveGroupChatMessage(aiMsg);
    _replyingGroups[groupId] = false;
    emit(GroupChatMessagesLoaded(groupId,
        await _storage.getGroupChatMessages(groupId, chatId: session.chatId)));
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

  /// 历史 → 发言人序列（最新在前，遇到用户消息停止；ST spokenSinceUser）
  List<String> _extractHistorySpeakers(List<GroupChatMessage> history) {
    final result = <String>[];
    for (final m in history) {
      if (m.isUser || m.isSystem) break;
      if (m.senderId.startsWith('ai_')) {
        result.add(m.senderId.substring(3));
      }
    }
    return result;
  }

  /// 最后一条 AI 发言者角色 id
  String? _lastAISpeaker(List<GroupChatMessage> history) {
    for (final m in history) {
      if (m.isUser || m.isSystem) continue;
      if (m.senderId.startsWith('ai_')) return m.senderId.substring(3);
    }
    return null;
  }

  /// 批量加载角色（保持传入顺序）
  Future<List<AICharacter>> _loadMembers(List<String> ids) async {
    final result = <AICharacter>[];
    for (final id in ids) {
      final c = await _storage.getAICharacter(id);
      if (c != null) result.add(c);
    }
    return result;
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

  /// 群消息 → 单聊格式（供 AIService 消费；ST 群聊格式：名字: 内容）
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
              : '${m.senderName}: ${m.content}')
          : (m.senderName == '我' ? m.content : '${m.senderName}: ${m.content}');
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
        disabledMemberIds:
            event.disabledMemberIds ?? session.disabledMemberIds,
        autoModeDelay: event.autoModeDelay ?? session.autoModeDelay,
        autoModeEnabled: event.autoModeEnabled ?? session.autoModeEnabled,
        updatedAt: DateTime.now(),
      );
      await _storage.saveGroupChatSession(updated);
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
      final branch =
          await _storage.createGroupChatBranch(event.groupId, event.name);
      emit(GroupChatBranchesLoaded(
        groupId: event.groupId,
        branches: [branch],
        currentChatId: session?.chatId ?? '',
      ));
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
      final messages = await _storage.getGroupChatMessages(event.groupId,
          chatId: event.chatId);
      emit(GroupChatMessagesLoaded(event.groupId, messages));
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
      final wasCurrent =
          session != null && session.chatId == event.chatId;
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
      await _restartAutoModeTimer();
    } else {
      _autoModeByGroup.remove(groupId);
      _groupDelays.remove(groupId);
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
    _autoModeTimer = Timer.periodic(
      Duration(seconds: minDelay),
      (_) => unawaited(_autoModeTick()),
    );
  }

  /// 轮询 tick：检查启用自动接话的群，最后消息不是用户/系统则触发 AI 回复
  Future<void> _autoModeTick() async {
    for (final groupId in _autoModeByGroup.keys.toList()) {
      if (_replyingGroups[groupId] == true) continue;
      final session = await _storage.getGroupChatSession(groupId);
      if (session == null) continue;
      if (!session.autoModeEnabled) {
        _autoModeByGroup.remove(groupId);
        _groupDelays.remove(groupId);
        continue;
      }
      final history = await _storage.getGroupChatMessages(groupId,
          limit: 1, chatId: session.chatId);
      if (history.isEmpty) continue;
      final last = history.last;
      // 最后一条不是用户发的 → AI 自己接力（自答）
      if (!last.isUser && !last.isSystem) continue;
      _replyingGroups[groupId] = true;
      _followUpCount = 0;
      await _generateAIReplies(
        groupId: groupId,
        userId: '',
        session: session,
        userMessage: '',
        imagePaths: null,
        isFollowUp: false,
        excludeCharacterId: null,
      );
    }
    // 更新各群延迟后重启轮询（使新配置生效）
    await _restartAutoModeTimer();
  }

  @override
  Future<void> close() {
    _autoModeTimer?.cancel();
    return super.close();
  }
}
