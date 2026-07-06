import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';
import '../../models/ai_character.dart' show AICharacter;
import '../../models/chat_message.dart';
import '../../models/group_chat_session.dart';
import '../../models/group_member_settings.dart';
import '../../models/group_relationship.dart';
import '../../models/group_message.dart';
import '../../repositories/local_storage_repository.dart';
import '../../services/ai_service.dart';
import '../../services/memory_engine.dart';
import 'group_chat_event.dart';
import 'group_chat_state.dart';

class GroupChatBloc extends Bloc<GroupChatEvent, GroupChatState> {
  final LocalStorageRepository _storage;
  final AIService _aiService;
  late final MemoryEngine _memoryEngine;
  final _uuid = const Uuid();
  final _random = Random();

  GroupChatBloc({
    required LocalStorageRepository storage,
    required AIService aiService,
  })  : _storage = storage,
        _aiService = aiService,
        super(GroupChatInitial()) {
    _memoryEngine = MemoryEngine(_storage);
    on<GroupChatLoadSessions>(_onLoadSessions);
    on<GroupChatCreateSession>(_onCreateSession);
    on<GroupChatDeleteSession>(_onDeleteSession);
    on<GroupChatLoadMessages>(_onLoadMessages);
    on<GroupChatSendMessage>(_onSendMessage);
    on<GroupChatForceReply>(_onForceReply);
    on<GroupChatUpdateMember>(_onUpdateMember);
    on<GroupChatUpdateRelationship>(_onUpdateRelationship);
    on<GroupChatUpdateSettings>(_onUpdateSettings);
  }

  Future<void> _onLoadSessions(
      GroupChatLoadSessions event, Emitter<GroupChatState> emit) async {
    emit(GroupChatLoading());
    final sessions = await _storage.getGroupChatSessions(event.userId);
    emit(GroupChatSessionsLoaded(sessions));
  }

  Future<void> _onCreateSession(
      GroupChatCreateSession event, Emitter<GroupChatState> emit) async {
    emit(GroupChatLoading());
    try {
      final id = _uuid.v4();
      final now = DateTime.now();
      final session = GroupChatSession(
        id: id,
        userId: event.userId,
        name: event.name,
        scenario: event.scenario,
        scenarioTemplate: event.scenarioTemplate,
        participantIds: event.participants.map((p) => p.id).toList(),
        participantNames: event.participants.map((p) => p.name).toList(),
        participantAvatars: event.participants.map((p) => p.avatarUrl).toList(),
        replyMode: event.replyMode,
        activationStrategy: event.activationStrategy,
        tavernMode: event.tavernMode,
        immersion: event.immersion,
        interactionFrequency: event.interactionFrequency,
        createdAt: now,
      );
      await _storage.saveGroupChatSession(session);

      for (int i = 0; i < event.participants.length; i++) {
        final p = event.participants[i];
        await _storage.saveGroupMemberSettings(GroupMemberSettings(
          id: _uuid.v4(),
          groupChatId: id,
          characterId: p.id,
          sortOrder: i,
          triggerKeywords: event.memberKeywords[p.id] ?? [],
        ));
      }

      for (int i = 0; i < event.participants.length; i++) {
        for (int j = i + 1; j < event.participants.length; j++) {
          await _storage.saveGroupRelationship(GroupRelationship(
            id: _uuid.v4(),
            groupChatId: id,
            characterIdA: event.participants[i].id,
            characterIdB: event.participants[j].id,
          ));
        }
      }

      emit(GroupChatSessionCreated(session));
      add(GroupChatLoadSessions(event.userId));
    } catch (e) {
      debugPrint('GroupChatCreateSession error: $e');
      emit(GroupChatError('创建故事书失败：$e'));
    }
  }

  Future<void> _onDeleteSession(
      GroupChatDeleteSession event, Emitter<GroupChatState> emit) async {
    await _storage.deleteGroupChatSession(event.groupChatId);
    final updated = await _storage.getGroupChatSessions(event.userId);
    emit(GroupChatSessionsLoaded(updated));
  }

  Future<void> _onLoadMessages(
      GroupChatLoadMessages event, Emitter<GroupChatState> emit) async {
    final messages =
        await _storage.getChatMessages(event.groupChatId, limit: 50);
    emit(GroupChatMessagesLoaded(
        groupChatId: event.groupChatId, messages: messages.reversed.toList()));
  }

  Future<void> _onSendMessage(
      GroupChatSendMessage event, Emitter<GroupChatState> emit) async {
    final userMsg = ChatMessage(
      id: _uuid.v4(),
      chatId: event.groupChatId,
      senderId: event.userId,
      content: event.content,
      type: MessageType.text,
      status: MessageStatus.sent,
      createdAt: DateTime.now(),
    );
    await _storage.saveChatMessage(userMsg);
    await _storage.updateGroupChatSessionById(event.groupChatId,
        lastMessage: event.content, lastMessageTime: DateTime.now());

    final messages =
        await _storage.getChatMessages(event.groupChatId, limit: 50);
    final group = await _storage.getGroupChatSession(event.groupChatId);
    if (group == null) return;

    emit(GroupChatMessagesLoaded(
        groupChatId: event.groupChatId, messages: messages.reversed.toList()));

    final participants = <AICharacter>[];
    for (final id in group.participantIds) {
      final char = await _storage.getAICharacter(id);
      if (char != null) participants.add(char);
    }
    final memberSettings =
        await _storage.getGroupMemberSettingsByGroup(event.groupChatId);
    final relationships =
        await _storage.getGroupRelationships(event.groupChatId);

    final orderedParticipants = _orderedParticipants(participants, memberSettings);

    // 第一版先强制使用逐个回复，避免快闪模式一次扮演多角色导致身份串线。
    // 旧酒馆可能仍保存为 ReplyMode.flash，但运行时先按 sequential 处理。
    await _handleSequentialReply(event, group, orderedParticipants, memberSettings,
        relationships, messages.reversed.toList(), emit);
  }

  List<AICharacter> _orderedParticipants(
    List<AICharacter> participants,
    List<GroupMemberSettings> settings,
  ) {
    final order = {
      for (final setting in settings) setting.characterId: setting.sortOrder,
    };
    final sorted = [...participants];
    sorted.sort((a, b) {
      final aOrder = order[a.id] ?? participants.indexOf(a);
      final bOrder = order[b.id] ?? participants.indexOf(b);
      return aOrder.compareTo(bOrder);
    });
    return sorted;
  }

  int _targetReplyCount(GroupChatSession group, int participantCount) {
    if (participantCount <= 0) return 0;
    final max = group.immersion.maxMessages;
    switch (group.immersion) {
      case TavernImmersion.quiet:
        return 1;
      case TavernImmersion.daily:
        return participantCount >= 2 ? 2 : 1;
      case TavernImmersion.lively:
        return participantCount >= 3 ? 3 : participantCount;
      case TavernImmersion.carnival:
        return participantCount < max ? participantCount : max;
    }
  }

  void _logGroupDebug(String message) {
    debugPrint('[DBG] GroupChatDebug: $message');
  }

  String _stripSpeakerPrefix(String content, AICharacter char) {
    var text = content.trim();
    final names = <String>{char.name};
    if (char.userNickname != null && char.userNickname!.trim().isNotEmpty) {
      names.add(char.userNickname!.trim());
    }
    if (char.userAlias != null && char.userAlias!.trim().isNotEmpty) {
      names.add(char.userAlias!.trim());
    }
    for (final name in names) {
      text = text.replaceFirst(
        RegExp('^\\[?${RegExp.escape(name)}\\]?[:：]\\s*'),
        '',
      );
    }
    return text.trim();
  }

  bool _lineBelongsToOtherSpeaker(String line, AICharacter char, List<AICharacter> participants) {
    final match = RegExp(r'^\[?([^\]：:]{1,20})\]?[:：]').firstMatch(line.trim());
    if (match == null) return false;
    final prefix = match.group(1)?.trim();
    if (prefix == null || prefix.isEmpty) return false;
    final ownNames = <String>{char.name};
    if (char.userNickname != null && char.userNickname!.trim().isNotEmpty) {
      ownNames.add(char.userNickname!.trim());
    }
    if (char.userAlias != null && char.userAlias!.trim().isNotEmpty) {
      ownNames.add(char.userAlias!.trim());
    }
    if (ownNames.contains(prefix)) return false;
    return participants.any((p) {
      final names = <String>{p.name};
      if (p.userNickname != null && p.userNickname!.trim().isNotEmpty) {
        names.add(p.userNickname!.trim());
      }
      if (p.userAlias != null && p.userAlias!.trim().isNotEmpty) {
        names.add(p.userAlias!.trim());
      }
      return names.contains(prefix);
    });
  }

  String _reactionInstruction({
    required GroupChatSession group,
    required int speakerIndex,
    required AICharacter current,
    AICharacter? previousSpeaker,
    ChatMessage? previousMessage,
  }) {
    if (speakerIndex == 0 || previousSpeaker == null || previousMessage == null) {
      return '你是本轮第一个发言者：先回应用户刚刚说的话，同时给后面的角色留下可以接的话头。';
    }

    final targetName = previousSpeaker.name;
    final previousText = previousMessage.content.trim();
    final targetLine = previousText.length > 90
        ? '${previousText.substring(0, 90)}…'
        : previousText;

    switch (group.interactionFrequency) {
      case TavernInteractionFrequency.gentle:
        return '你是本轮第 ${speakerIndex + 1} 个发言者：先简短回应用户，再顺带接一下$targetName刚才的话。$targetName刚才说：“$targetLine”。不要重复回答用户同一个点。';
      case TavernInteractionFrequency.natural:
        return '你是本轮第 ${speakerIndex + 1} 个发言者：优先回应$targetName刚才的话，可以同意、反驳、吐槽、追问、安慰或补充，反应要符合你的人设。$targetName刚才说：“$targetLine”。不要像客服一样重新回答用户。';
      case TavernInteractionFrequency.vivid:
        return '你是本轮第 ${speakerIndex + 1} 个发言者：把用户的话题当作群聊引子，主要接$targetName的话。你可以阴阳、拆台、护短、同情、起哄、补刀或转移话题，但必须符合你的人设和关系。$targetName刚才说：“$targetLine”。';
    }
  }

  List<AICharacter> _takeSpeakersForRound(
    List<AICharacter> participants,
    int count,
    List<ChatMessage> chatHistory,
  ) {
    if (participants.isEmpty || count <= 0) return [];
    var startIndex = 0;
    for (final msg in chatHistory.reversed) {
      if (!msg.senderId.startsWith('ai_')) continue;
      final characterId = msg.senderId.replaceFirst('ai_', '');
      final index = participants.indexWhere((p) => p.id == characterId);
      if (index >= 0) {
        startIndex = (index + 1) % participants.length;
        break;
      }
    }
    return List.generate(count, (i) => participants[(startIndex + i) % participants.length]);
  }

  Future<void> _insertStoryNarration(
    GroupChatSendMessage event,
    GroupChatSession group,
    List<ChatMessage> chatHistory,
    Emitter<GroupChatState> emit,
  ) async {
    final lastUserLine = event.content.trim().isNotEmpty
        ? event.content.trim()
        : '有人轻轻推动了场景。';
    final scenarioText = group.scenario?.trim().isNotEmpty == true
        ? group.scenario!.trim()
        : '酒馆里的气氛继续流动。';
    final narration = scenarioText.length > 18
        ? '$scenarioText\n$lastUserLine 之后，空气里多了一点新的变化。'
        : '$scenarioText，$lastUserLine 之后，空气里多了一点新的变化。';
    final msg = ChatMessage(
      id: _uuid.v4(),
      chatId: event.groupChatId,
      senderId: 'system',
      senderName: '旁白',
      content: narration,
      type: MessageType.narration,
      isSystem: true,
      status: MessageStatus.sent,
      createdAt: DateTime.now(),
    );
    await _storage.saveChatMessage(msg);
    await _storage.updateGroupChatSessionById(event.groupChatId,
        lastMessage: '—— $narration', lastMessageTime: DateTime.now());
    final updated = await _storage.getChatMessages(event.groupChatId, limit: 50);
    emit(GroupChatMessagesLoaded(
        groupChatId: event.groupChatId, messages: updated.reversed.toList()));
  }

  Future<void> _handleFlashReply(
    GroupChatSendMessage event,
    GroupChatSession group,
    List<AICharacter> participants,
    List<GroupMemberSettings> memberSettings,
    List<GroupRelationship> relationships,
    List<ChatMessage> chatHistory,
    Emitter<GroupChatState> emit,
  ) async {
    emit(const GroupChatAITyping(''));

    try {
      final rollingSummary = await _memoryEngine.getRollingSummary(
        characterId: event.groupChatId,
        userId: 'group',
      );

      final chatMsgs =
          await _storage.getChatMessages(event.groupChatId, limit: 50);
      if (group.tavernMode == TavernMode.story) {
        await _insertStoryNarration(event, group, chatHistory, emit);
      }
      final speakers = _takeSpeakersForRound(
        participants,
        _targetReplyCount(group, participants.length),
        chatHistory,
      );
      _logGroupDebug('flash speakers=${speakers.map((c) => c.name).join(',')} mode=${group.tavernMode.label} immersion=${group.immersion.label}');
      if (speakers.isEmpty) return;
      String finalResponse = '';

      await for (final chunk in _aiService.sendGroupFlashMessageStream(
        participants: speakers,
        userId: event.userId,
        userMessage: event.content,
        chatHistory: chatHistory,
        scenario: group.scenario,
        scenarioTemplate: group.scenarioTemplate,
        relationships: relationships,
        loverMode: group.loverModeEnabled,
        openMode: group.openModeEnabled,
        faMode: group.faModeEnabled,
        daoMode: group.daoModeEnabled,
        rollingSummary: rollingSummary,
      )) {
        finalResponse = chunk.content;
        emit(GroupChatAIStreaming(
          groupChatId: event.groupChatId,
          messages: chatMsgs.reversed.toList(),
          streamingText: chunk.content,
          characterName: '',
          reasoning: chunk.reasoning,
        ));
      }

      _logGroupDebug('flash raw=${finalResponse.replaceAll('\n', ' / ')}');
      final parsed = GroupMessage.parseMultiCharacterResponse(finalResponse);
      _logGroupDebug('flash parsed=${parsed.map((p) => '${p.characterName}:${p.content}').join(' | ')}');
      if (parsed.isEmpty) {
        final fallbackChar = participants.first;
        emit(GroupChatAITyping(fallbackChar.name));
        await Future.delayed(
            Duration(milliseconds: 500 + _random.nextInt(500)));
        final aiMsg = ChatMessage(
          id: _uuid.v4(),
          chatId: event.groupChatId,
          senderId: 'ai_${fallbackChar.id}',
          senderName: fallbackChar.name,
          content: finalResponse,
          type: MessageType.text,
          status: MessageStatus.sent,
          createdAt: DateTime.now(),
        );
        await _storage.saveChatMessage(aiMsg);
        await _storage.updateGroupChatSessionById(event.groupChatId,
            lastMessage: '[${fallbackChar.name}] $finalResponse',
            lastMessageTime: DateTime.now());
        final updated =
            await _storage.getChatMessages(event.groupChatId, limit: 50);
        emit(GroupChatMessagesLoaded(
            groupChatId: event.groupChatId,
            messages: updated.reversed.toList()));
        return;
      }

      for (int i = 0; i < parsed.length; i++) {
        final p = parsed[i];
        final char = speakers.firstWhere(
          (c) => c.name == p.characterName,
          orElse: () => speakers[i % speakers.length],
        );

        emit(GroupChatAITyping(char.name));
        await Future.delayed(
            Duration(milliseconds: i == 0 ? 300 : 800 + _random.nextInt(700)));

        final aiMsg = ChatMessage(
          id: _uuid.v4(),
          chatId: event.groupChatId,
          senderId: 'ai_${char.id}',
          senderName: char.name,
          content: p.content,
          type: MessageType.text,
          status: MessageStatus.sent,
          createdAt: DateTime.now(),
        );
        await _storage.saveChatMessage(aiMsg);
        await _storage.updateGroupChatSessionById(event.groupChatId,
            lastMessage: '[${char.name}] ${p.content}',
            lastMessageTime: DateTime.now());

        final updated =
            await _storage.getChatMessages(event.groupChatId, limit: 50);
        emit(GroupChatMessagesLoaded(
            groupChatId: event.groupChatId,
            messages: updated.reversed.toList()));
      }

      await _checkAndGenerateSummary(event.groupChatId, group, participants);
      await _generateGroupRollingSummary(event.groupChatId, participants.first);
    } catch (e) {
      emit(GroupChatError(e.toString()));
      final updated =
          await _storage.getChatMessages(event.groupChatId, limit: 50);
      emit(GroupChatMessagesLoaded(
          groupChatId: event.groupChatId, messages: updated.reversed.toList()));
    }
  }

  Future<void> _handleSequentialReply(
    GroupChatSendMessage event,
    GroupChatSession group,
    List<AICharacter> participants,
    List<GroupMemberSettings> memberSettings,
    List<GroupRelationship> relationships,
    List<ChatMessage> chatHistory,
    Emitter<GroupChatState> emit,
  ) async {
    final roundHistory = [...chatHistory];
    if (group.tavernMode == TavernMode.story) {
      await _insertStoryNarration(event, group, chatHistory, emit);
      final refreshedHistory =
          await _storage.getChatMessages(event.groupChatId, limit: 50);
      roundHistory
        ..clear()
        ..addAll(refreshedHistory.reversed.toList());
    }
    final speakers = _takeSpeakersForRound(
      participants,
      _targetReplyCount(group, participants.length),
      roundHistory,
    );
    _logGroupDebug('sequential speakers=${speakers.map((c) => c.name).join(',')} mode=${group.tavernMode.label} immersion=${group.immersion.label}');

    // 追踪本轮上一个发言者和消息，用于接话链
    AICharacter? previousSpeaker;
    ChatMessage? previousSavedMessage;

    for (int i = 0; i < speakers.length; i++) {
      final char = speakers[i];
      emit(GroupChatAITyping(char.name));
      await Future.delayed(Duration(milliseconds: 500 + _random.nextInt(1000)));

      try {
        final intimacyMap = <String, int>{};
        for (final id in group.participantIds) {
          final sessions = await _storage.getChatSessionsByCharacterId(id);
          if (sessions.isNotEmpty) {
            intimacyMap[id] = sessions.first.intimacyLevel;
          }
        }

        final rollingSummary = await _memoryEngine.getRollingSummary(
          characterId: event.groupChatId,
          userId: 'group',
        );

        final chatMsgs =
            await _storage.getChatMessages(event.groupChatId, limit: 50);

        // 生成本轮接话指令
        final reaction = _reactionInstruction(
          group: group,
          speakerIndex: i,
          current: char,
          previousSpeaker: previousSpeaker,
          previousMessage: previousSavedMessage,
        );
        _logGroupDebug('sequential reaction ${char.name}: ${reaction.substring(0, reaction.length > 60 ? 60 : reaction.length)}…');

        // 构造回复目标 metadata
        final replyMeta = previousSpeaker == null
            ? null
            : <String, dynamic>{
                'replyToCharacterId': previousSpeaker.id,
                'replyToCharacterName': previousSpeaker.name,
              };

        String finalResponse = '';

        await for (final chunk in _aiService.sendGroupMessageStream(
          character: char,
          allParticipants: participants,
          userId: event.userId,
          userMessage: event.content,
          chatHistory: roundHistory,
          memories: [],
          intimacyLevel: intimacyMap[char.id] ?? 0,
          scenario: group.scenario,
          scenarioTemplate: group.scenarioTemplate,
          relationships: relationships,
          loverMode: group.loverModeEnabled,
          openMode: group.openModeEnabled,
          faMode: group.faModeEnabled,
          daoMode: group.daoModeEnabled,
          rollingSummary: rollingSummary,
          tavernModeLabel: group.tavernMode.label,
          immersionLabel: group.immersion.label,
          interactionFrequencyLabel: group.interactionFrequency.label,
          targetReplyCount: speakers.length,
          reactionInstruction: reaction,
        )) {
          finalResponse = chunk.content;
          emit(GroupChatAIStreaming(
            groupChatId: event.groupChatId,
            messages: chatMsgs.reversed.toList(),
            streamingText: chunk.content,
            characterName: char.name,
            reasoning: chunk.reasoning,
          ));
        }

        _logGroupDebug('sequential raw speaker=${char.name} raw=${finalResponse.replaceAll('\n', ' / ')}');
        final msgParts = finalResponse
            .split('\n')
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty)
            .where((l) => !_lineBelongsToOtherSpeaker(l, char, participants))
            .map((l) => _stripSpeakerPrefix(l, char))
            .where((l) => l.trim().isNotEmpty)
            .toList();
        _logGroupDebug('sequential save speaker=${char.name} parts=${msgParts.join(' / ')}');

        // 保存每条消息（含 replyTo metadata）
        for (final part in msgParts) {
          final aiMsg = ChatMessage(
            id: _uuid.v4(),
            chatId: event.groupChatId,
            senderId: 'ai_${char.id}',
            senderName: char.name,
            content: part.trim(),
            type: MessageType.text,
            status: MessageStatus.sent,
            createdAt: DateTime.now(),
            metadata: replyMeta,
          );
          await _storage.saveChatMessage(aiMsg);
          // 更新接话链：本轮最后一个保存的消息成为下一位的接话目标
          previousSpeaker = char;
          previousSavedMessage = aiMsg;
        }

        // 如果过滤后没有内容，仍保留原始回复作为 fallback
        if (msgParts.isEmpty && finalResponse.trim().isNotEmpty) {
          final fallbackMsg = ChatMessage(
            id: _uuid.v4(),
            chatId: event.groupChatId,
            senderId: 'ai_${char.id}',
            senderName: char.name,
            content: finalResponse.trim(),
            type: MessageType.text,
            status: MessageStatus.sent,
            createdAt: DateTime.now(),
            metadata: replyMeta,
          );
          await _storage.saveChatMessage(fallbackMsg);
          previousSpeaker = char;
          previousSavedMessage = fallbackMsg;
        }

        await _storage.updateGroupChatSessionById(event.groupChatId,
            lastMessage: '[${char.name}] $finalResponse',
            lastMessageTime: DateTime.now());
        final updated =
            await _storage.getChatMessages(event.groupChatId, limit: 50);
        emit(GroupChatMessagesLoaded(
            groupChatId: event.groupChatId,
            messages: updated.reversed.toList()));
      } catch (e) {
        emit(GroupChatError(e.toString()));
        final updated =
            await _storage.getChatMessages(event.groupChatId, limit: 50);
        emit(GroupChatMessagesLoaded(
            groupChatId: event.groupChatId,
            messages: updated.reversed.toList()));
      }
    }

    await _checkAndGenerateSummary(event.groupChatId, group, participants);
    await _generateGroupRollingSummary(event.groupChatId, participants.first);
  }

  List<AICharacter> _determineNextSpeakers({
    required String userMessage,
    required List<AICharacter> participants,
    required List<GroupMemberSettings> settings,
    required List<GroupRelationship> relationships,
  }) {
    for (final char in participants) {
      final setting = settings.where((s) => s.characterId == char.id).toList();
      if (setting.isNotEmpty) {
        for (final keyword in setting.first.triggerKeywords) {
          if (userMessage.contains(keyword)) {
            return [char];
          }
        }
      }
    }

    final mentioned =
        participants.where((c) => userMessage.contains(c.name)).toList();
    if (mentioned.isNotEmpty) return mentioned.take(2).toList();

    final activated = <AICharacter>[];
    for (final char in participants) {
      final setting = settings.where((s) => s.characterId == char.id).toList();
      if (setting.isNotEmpty && setting.first.isMuted) continue;
      final talkativeness =
          setting.isNotEmpty ? setting.first.talkativeness / 100.0 : 0.5;
      if (_random.nextDouble() < talkativeness) {
        activated.add(char);
      }
    }
    if (activated.isNotEmpty) return activated.take(1).toList();

    final available = participants.where((c) {
      final s = settings.where((ss) => ss.characterId == c.id).toList();
      return s.isEmpty || !s.first.isMuted;
    }).toList();
    if (available.isEmpty) return [];
    return [available[_random.nextInt(available.length)]];
  }

  Future<void> _checkAndGenerateSummary(
    String groupChatId,
    GroupChatSession group,
    List<AICharacter> participants,
  ) async {
    final allMessages = await _storage.getChatMessages(groupChatId, limit: 100);
    if (allMessages.length < 50) return;

    final messagesToSummarize = allMessages.reversed.take(20).toList();
    final summary = await _aiService.generateGroupSummary(
      messagesToSummarize: messagesToSummarize,
      participants: participants,
    );
    if (summary.isNotEmpty) {
      await _storage.updateGroupChatSessionById(
        groupChatId,
        conversationSummary: summary,
        summaryMessageCount: allMessages.length,
      );
    }
  }

  Future<void> _generateGroupRollingSummary(
      String groupChatId, AICharacter character) async {
    try {
      final allMessages = await _storage.getChatMessages(groupChatId);
      final newMsgs = await _memoryEngine.checkRollingSummaryNeeded(
        characterId: groupChatId,
        userId: 'group',
        allMessages: allMessages,
      );
      if (newMsgs == null || newMsgs.isEmpty) return;

      final existingSummary = await _memoryEngine.getRollingSummary(
        characterId: groupChatId,
        userId: 'group',
      );
      final newSummary = await _aiService.generateRollingSummary(
        newMessages: newMsgs,
        character: character,
        existingSummary: existingSummary,
      );
      if (newSummary.isNotEmpty) {
        await _memoryEngine.saveRollingSummary(
          characterId: groupChatId,
          userId: 'group',
          summary: newSummary,
          messageCount: allMessages.length,
        );
      }
    } catch (e) {
      // 静默失败，不影响主流程
    }
  }

  Future<void> _handleObserveContinue(
    GroupChatForceReply event,
    GroupChatSession group,
    List<AICharacter> participants,
    List<GroupRelationship> relationships,
    List<ChatMessage> chatHistory,
    Emitter<GroupChatState> emit,
  ) async {
    final speakers = _takeSpeakersForRound(
      participants,
      _targetReplyCount(group, participants.length),
      chatHistory,
    );
    if (speakers.isEmpty) return;

    AICharacter? previousSpeaker;
    ChatMessage? previousSavedMessage;

    for (int i = 0; i < speakers.length; i++) {
      final char = speakers[i];
      emit(GroupChatAITyping(char.name));
      await Future.delayed(Duration(milliseconds: 500 + _random.nextInt(800)));
      try {
        final rollingSummary = await _memoryEngine.getRollingSummary(
          characterId: event.groupChatId,
          userId: 'group',
        );
        final messages = await _storage.getChatMessages(event.groupChatId, limit: 50);

        final reaction = _reactionInstruction(
          group: group,
          speakerIndex: i,
          current: char,
          previousSpeaker: previousSpeaker,
          previousMessage: previousSavedMessage,
        );

        final replyMeta = previousSpeaker == null
            ? null
            : <String, dynamic>{
                'replyToCharacterId': previousSpeaker.id,
                'replyToCharacterName': previousSpeaker.name,
              };

        final response = await _aiService.sendGroupMessage(
          character: char,
          allParticipants: participants,
          userId: event.userId,
          userMessage: '请你们围绕上一个话题自然继续聊，不要等待用户提问。',
          chatHistory: messages.reversed.toList(),
          memories: [],
          scenario: group.scenario,
          scenarioTemplate: group.scenarioTemplate,
          relationships: relationships,
          loverMode: group.loverModeEnabled,
          openMode: group.openModeEnabled,
          faMode: group.faModeEnabled,
          daoMode: group.daoModeEnabled,
          rollingSummary: rollingSummary,
          tavernModeLabel: group.tavernMode.label,
          immersionLabel: group.immersion.label,
          interactionFrequencyLabel: group.interactionFrequency.label,
          targetReplyCount: _targetReplyCount(group, participants.length),
          reactionInstruction: reaction,
        );
        final aiMsg = ChatMessage(
          id: _uuid.v4(),
          chatId: event.groupChatId,
          senderId: 'ai_${char.id}',
          senderName: char.name,
          content: response,
          type: MessageType.text,
          status: MessageStatus.sent,
          createdAt: DateTime.now(),
          metadata: replyMeta,
        );
        await _storage.saveChatMessage(aiMsg);
        previousSpeaker = char;
        previousSavedMessage = aiMsg;

        await _storage.updateGroupChatSessionById(event.groupChatId,
            lastMessage: '[${char.name}] $response',
            lastMessageTime: DateTime.now());
        final updated = await _storage.getChatMessages(event.groupChatId, limit: 50);
        emit(GroupChatMessagesLoaded(
            groupChatId: event.groupChatId, messages: updated.reversed.toList()));
      } catch (e) {
        emit(GroupChatError(e.toString()));
      }
    }
  }

  Future<void> _onForceReply(
      GroupChatForceReply event, Emitter<GroupChatState> emit) async {
    final group = await _storage.getGroupChatSession(event.groupChatId);
    if (group == null) return;

    final char = await _storage.getAICharacter(event.characterId);
    if (char == null) return;

    final participants = <AICharacter>[];
    for (final id in group.participantIds) {
      final c = await _storage.getAICharacter(id);
      if (c != null) participants.add(c);
    }

    final messages =
        await _storage.getChatMessages(event.groupChatId, limit: 50);
    final relationships =
        await _storage.getGroupRelationships(event.groupChatId);
    final memberSettings =
        await _storage.getGroupMemberSettingsByGroup(event.groupChatId);
    final orderedParticipants = _orderedParticipants(participants, memberSettings);

    if (event.observeContinue) {
      await _handleObserveContinue(event, group, orderedParticipants,
          relationships, messages.reversed.toList(), emit);
      return;
    }

    final rollingSummary = await _memoryEngine.getRollingSummary(
      characterId: event.groupChatId,
      userId: 'group',
    );

    emit(GroupChatAITyping(char.name));

    try {
      final response = await _aiService.sendGroupMessage(
        character: char,
        allParticipants: participants,
        userId: event.userId,
        userMessage: '',
        chatHistory: messages.reversed.toList(),
        memories: [],
        scenario: group.scenario,
        scenarioTemplate: group.scenarioTemplate,
        relationships: relationships,
        loverMode: group.loverModeEnabled,
        openMode: group.openModeEnabled,
        faMode: group.faModeEnabled,
        daoMode: group.daoModeEnabled,
        rollingSummary: rollingSummary,
      );

      final aiMsg = ChatMessage(
        id: _uuid.v4(),
        chatId: event.groupChatId,
        senderId: 'ai_${char.id}',
        senderName: char.name,
        content: response,
        type: MessageType.text,
        status: MessageStatus.sent,
        createdAt: DateTime.now(),
      );
      await _storage.saveChatMessage(aiMsg);
      await _storage.updateGroupChatSessionById(event.groupChatId,
          lastMessage: '[${char.name}] $response',
          lastMessageTime: DateTime.now());
      final updated =
          await _storage.getChatMessages(event.groupChatId, limit: 50);
      emit(GroupChatMessagesLoaded(
          groupChatId: event.groupChatId, messages: updated.reversed.toList()));
    } catch (e) {
      emit(GroupChatError(e.toString()));
    }
  }

  Future<void> _onUpdateMember(
      GroupChatUpdateMember event, Emitter<GroupChatState> emit) async {
    final settings =
        await _storage.getGroupMemberSettingsByGroup(event.groupChatId);
    final existing =
        settings.where((s) => s.characterId == event.characterId).toList();
    if (existing.isNotEmpty) {
      final updated = existing.first.copyWith(
        talkativeness: event.talkativeness,
        isMuted: event.isMuted,
        triggerKeywords: event.triggerKeywords,
      );
      await _storage.saveGroupMemberSettings(updated);
    }
    final group = await _storage.getGroupChatSession(event.groupChatId);
    if (group != null) {
      final participants = <AICharacter>[];
      for (final id in group.participantIds) {
        final c = await _storage.getAICharacter(id);
        if (c != null) participants.add(c);
      }
      final rels = await _storage.getGroupRelationships(event.groupChatId);
      emit(GroupChatSettingsLoaded(
          session: group,
          participants: participants,
          memberSettings: settings,
          relationships: rels));
    }
  }

  Future<void> _onUpdateRelationship(
      GroupChatUpdateRelationship event, Emitter<GroupChatState> emit) async {
    final rels = await _storage.getGroupRelationships(event.groupChatId);
    final existing = rels
        .where((r) => r.pairContains(event.characterIdA, event.characterIdB))
        .toList();
    if (existing.isNotEmpty) {
      final updated = existing.first.copyWith(relationship: event.relationship);
      await _storage.saveGroupRelationship(updated);
    } else {
      await _storage.saveGroupRelationship(GroupRelationship(
        id: _uuid.v4(),
        groupChatId: event.groupChatId,
        characterIdA: event.characterIdA,
        characterIdB: event.characterIdB,
        relationship: event.relationship,
      ));
    }
  }

  Future<void> _onUpdateSettings(
      GroupChatUpdateSettings event, Emitter<GroupChatState> emit) async {
    final group = await _storage.getGroupChatSession(event.groupChatId);
    if (group != null) {
      final updated = group.copyWith(
        name: event.name,
        scenario: event.scenario,
        scenarioTemplate: event.scenarioTemplate,
        replyMode: event.replyMode,
        activationStrategy: event.activationStrategy,
        autoModeEnabled: event.autoModeEnabled,
        allowSelfResponse: event.allowSelfResponse,
      );
      await _storage.saveGroupChatSession(updated);
    }
  }
}
