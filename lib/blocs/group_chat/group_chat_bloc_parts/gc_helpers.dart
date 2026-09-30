// 群聊 BLoC 拆分 part
part of '../group_chat_bloc.dart';

mixin _GcHelpers on Bloc<GroupChatEvent, GroupChatState>, _GcCore, _GcSessions {
Future<void> _refreshGroupRollingSummary(
    String groupId, GroupChatSession session) async {
  return _groupSummaryRefreshes.run(groupId, session.chatId, () async {
    try {
      final messages = await _storage.getGroupChatMessages(
        groupId,
        limit: 100000,
        chatId: session.chatId,
      );
      final old = await _storage.getGroupChatSummary(groupId, session.chatId);
      if (!shouldRefreshGroupSummary(
        messageCount: messages.length,
        summarizedCount: old?.messageCount ?? 0,
      )) {
        return;
      }
      final ordered = messages.reversed.toList();
      final reset = shouldResetGroupSummary(
        messageCount: ordered.length,
        summarizedCount: old?.messageCount ?? 0,
      );
      final start =
          reset ? 0 : (old?.messageCount ?? 0).clamp(0, ordered.length);
      final newMessages = _toChatHistory(ordered.sublist(start), '',
          userAlias: (await _groupUserIdentity(_storage)).alias);
      final summary = await _aiService.generateGroupRollingSummary(
        existingSummary: reset ? null : old?.summary,
        newMessages: newMessages,
      );
      if (summary == null || summary.trim().isEmpty) return;
      await _storage.saveGroupChatSummary(GroupChatSummary(
        groupId: groupId,
        chatId: session.chatId,
        summary: summary.trim(),
        messageCount: ordered.length,
        updatedAt: DateTime.now(),
      ));
    } catch (e) {
      LogService.instance.w('GroupChat', '群聊滚动总结失败: $e', chatId: groupId);
    }
  });
}

/// APPEND 合并卡生成（ST generation_mode APPEND / APPEND_DISABLED）

Future<List<Memory>> _aggregateMemberMemories({
  required List<String> memberIds,
  required String userId,
}) async {
  final result = <Memory>[];
  for (final id in memberIds) {
    final mems = await _storage.getMemories(
      characterId: id,
      userId: userId,
      limit: 3,
    );
    result.addAll(mems);
    if (result.length >= 12) break;
  }
  if (result.length > 12) {
    result.removeRange(12, result.length);
  }
  return result;
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

bool _isNovelModeEnabled() {
  try {
    return _storage.isChatStyleNovelModeEnabled() &&
        !_storage.isPureAiModeEnabled();
  } catch (_) {
    return false;
  }
}

/// 群聊 AI 回复后：LLM 提取本轮群聊事件为社交记忆（降频，unawaited）
Future<void> _extractGroupMemoriesAfterReply({
  required String groupId,
  required GroupChatSession session,
}) async {
  try {
    final recent = await _storage.getGroupChatMessages(groupId,
        limit: 12, chatId: session.chatId);
    if (recent.length < 2) return;

    // 拒绝/脱角色模板不参与群聊记忆与事件提取（旧拒绝不再污染新上下文）。
    final safeRecent = recent
        .where((m) =>
            !(m.isUser == false &&
                m.isSystem == false &&
                MessageSanitizer.isAIRefusal(m.content)))
        .toList();
    if (safeRecent.length < 2) return;

    // 角色名 → 角色 id 映射（反查 LLM 输出的 speaker）
    final members = await _loadMembers(session.aiCharacterIds);
    final speakerMap = <String, String>{
      for (final m in members) m.name: m.id,
    };

    await _memoryEngine.extractGroupMemories(
      messages: safeRecent,
      groupName: session.name,
      speakerCharacterIds: speakerMap,
      groupId: groupId,
    );

    final summary =
        await _storage.getGroupChatSummary(groupId, session.chatId);
    final events = await _aiService.extractGroupPublicEvents(
      groupName: session.name,
      messages: _toChatHistory(safeRecent, '',
          userAlias: (await _groupUserIdentity(_storage)).alias),
      existingSummary: summary?.summary,
    );
    for (final characterId in session.aiCharacterIds) {
      final existing = await _storage.getGroupPublicEventMemories(
          characterId: characterId, groupId: groupId, chatId: session.chatId);
      for (var index = 0; index < events.length; index++) {
        final event = events[index];
        if (existing.any((old) =>
            old.content == event.content ||
            old.sourceMessageIds
                .toSet()
                .intersection(event.sourceMessageIds.toSet())
                .isNotEmpty)) {
          continue;
        }
        await _storage.saveGroupPublicEventMemory(GroupPublicEventMemory(
          id: _uuid.v4(),
          characterId: characterId,
          groupId: groupId,
          chatId: session.chatId,
          content: event.content,
          keywords: event.keywords,
          sourceMessageIds: event.sourceMessageIds,
          speakerNames: event.speakerNames,
          sourceGroupName: session.name,
          importance: event.importance,
          pinned: event.pinned,
          createdAt: DateTime.now(),
          lastRecalledAt: null,
        ));
        existing.add(GroupPublicEventMemory(
          id: '',
          characterId: characterId,
          groupId: groupId,
          chatId: session.chatId,
          content: event.content,
          keywords: event.keywords,
          sourceMessageIds: event.sourceMessageIds,
          speakerNames: event.speakerNames,
          sourceGroupName: session.name,
          importance: event.importance,
          pinned: event.pinned,
          createdAt: DateTime.now(),
          lastRecalledAt: null,
        ));
      }
    }
  } catch (e) {
    LogService.instance.w('GroupChat', '群聊记忆提取失败: $e', chatId: groupId);
  }
}

/// 群聊社交记忆每日维护（艾宾浩斯衰减，20h 节流，unawaited 静默执行）
Future<void> _runSocialMaintenanceQuietly(
    String groupId, List<String> memberCharacterIds) async {
  try {
    await _memoryEngine.runSocialDailyMaintenance(
      groupId: groupId,
      memberCharacterIds: memberCharacterIds,
    );
  } catch (e) {
    LogService.instance.w('GroupChat', '社交记忆维护失败: $e', chatId: groupId);
  }
}

/// 群成员名称列表（AI 用真实名，用户显示代称为主）
Future<List<String>> _buildMemberNames(GroupChatSession session) async {
  final names = <String>[];
  for (final id in session.aiCharacterIds) {
    final ch = await _storage.getAICharacter(id);
    names.add(ch?.name ?? id);
  }
  // 用户成员（非 AI 的 memberIds）：代称优先，并明确标注"就是用户本人"，
  // 否则模型会把"林晚晚"之类的代称当成群里另一个 AI 成员。
  String userLabel = '你';
  try {
    final me = await _storage.getCurrentUser();
    final alias = me?.chatAlias?.trim() ?? '';
    if (alias.isNotEmpty) {
      userLabel = '$alias（就是用户本人，不是群成员）';
    } else {
      final nickname = me?.nickname.trim() ?? '';
      if (nickname.isNotEmpty) {
        userLabel = '$nickname（就是用户本人，你）';
      }
    }
  } catch (_) {}
  for (final id in session.memberIds) {
    if (!session.aiCharacterIds.contains(id)) {
      names.add(id == 'local_user' ? userLabel : id);
    }
  }
  return names;
}

/// 合并流式思考内容用于实时展示（对齐单聊 chat_bloc._mergeStreamReasoning）。
///
/// 部分推理模型不使用独立的 reasoning_content 字段，而是把思考直接写在
/// 正文的 <think>…</think> 里。思考阶段标签未闭合、content 清洗后为空，
/// 若只按 content 判断会一直不 emit —— 表现为「无气泡但背后已在准备回复，
/// 思考完才一次性蹦出正文」。
String _mergeStreamReasoning(AIStreamChunk chunk) {
  final fromField = MessageSanitizer.sanitizeStream(chunk.reasoning);
  // cleanForStreamDisplay 返回 [正文, 从 content 提取出的思考]
  final parts = AIService.cleanForStreamDisplay(chunk.content);
  final fromContent =
      parts.length > 1 ? MessageSanitizer.sanitizeStream(parts[1]) : '';
  return [fromField, fromContent].where((r) => r.isNotEmpty).join('\n');
}

/// 群聊用户身份三件套（与单聊主路径同源文案，见 `utils/identity_label.dart`）。
///
/// 群聊此前从不声明用户身份与性别，模型只能靠猜——这是群聊里代称/性别错乱的根源。
/// 返回：identity 段、addendum 段、代称（历史标注用）。读失败时全空，调用方跳过注入。
Future<({String identityBlock, String addendumBlock, String alias})>
    _groupUserIdentity(LocalStorageRepository storage) async {
  try {
    final me = await storage.getCurrentUser();
    var alias = me?.chatAlias?.trim() ?? '';
    var nickname = me?.nickname.trim() ?? '';
    return (
      identityBlock: identity.buildUserIdentityBlock(
        alias: alias.isEmpty ? null : alias,
        nickname: nickname.isEmpty ? null : nickname,
        gender: me?.gender,
      ),
      addendumBlock:
          identity.buildUserAddendumBlock(storage.getUserPromptAddendum()),
      alias: alias,
    );
  } catch (_) {
    return (identityBlock: '', addendumBlock: '', alias: '');
  }
}

/// 群消息 → 单聊格式（供 AIService 消费；ST 群聊格式：名字: 内容）
List<ChatMessage> _toChatHistory(
  List<GroupChatMessage> history,
  String selfCharacterId, {
  // 用户代称：用户发言标注为"代称: 内容"，让模型把"我"绑定到代称人物。
  // 为空时保持旧行为（senderName=='我' 的消息不带前缀）。
  String userAlias = '',
}) {
  final result = <ChatMessage>[];
  for (final m in history) {
    if (m.isSystem) continue;
    // 拒绝/脱角色模板不进模型上下文、滚动总结或事件提取，
    // 避免某个模型拒绝/报助手身份一次后，换模型也洗不掉。
    if (!m.isUser && MessageSanitizer.isAIRefusal(m.content)) continue;
    final isAi = !m.isUser;
    // 自己是说话人时用 content；他人消息标注说话人。
    // 用户发言：有代称则标注"代称: 内容"（绑定"我"=代称人物），无代称保持旧行为。
    final content = isAi
        ? (m.senderId == 'ai_$selfCharacterId'
            ? m.content
            : '${m.senderName}: ${m.content}')
        : (m.senderName == '我' && userAlias.isEmpty
            ? m.content
            : '${m.senderName == '我' ? userAlias : m.senderName}: ${m.content}');
    result.add(ChatMessage(
      id: m.id,
      chatId: m.chatId.isEmpty ? m.groupId : m.chatId,
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

}
