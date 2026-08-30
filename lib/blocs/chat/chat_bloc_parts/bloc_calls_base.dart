// 通话消息与基础工具（拆分生成，同库 part）
part of '../chat_bloc.dart';

mixin _BlocCallsBase on Bloc<ChatEvent, ChatState>, ChatBlocUtils, ChatBlocIntimacy, _ChatBlocCore {
  bool _isAIRefusal(String content) => isAIRefusal(content);


  bool get _isPureAIForced => _storage.isPureAiModeEnabled();


  String _fallbackForRefusal(String userMessage) =>
      fallbackForRefusal(userMessage);


  /// 从用户消息中移除“系统提示”指令部分，用于保存到聊天记录
  String _stripSystemDirective(String text) => stripSystemDirective(text);


  /// 追加一条消息（通话记录等系统消息）并刷新消息列表。
  /// 供 VoiceCallController 等非事件入口使用。
  Future<void> appendSystemMessage(ChatMessage message) async {
    try {
      await _storage.saveChatMessage(message);
      if (isClosed) return;
      add(ChatLoadMessages(message.chatId));
    } catch (e) {
      LogService.instance
          .w('Chat', 'appendSystemMessage 失败: $e', chatId: message.chatId);
    }
  }


  /// 静默化语音通话：删除 [since] 之后写入的用户/AI 消息并刷新列表。
  /// 通话内容不进聊天页（记忆已由 extractCallMemories 静默入库），
  /// 聊天页只保留通话记录系统消息与时间。
  Future<void> clearCallMessages({
    required String chatId,
    required DateTime since,
  }) async {
    try {
      await _storage.deleteChatMessagesSince(chatId, since);
      if (isClosed) return;
      add(ChatLoadMessages(chatId));
    } catch (e) {
      LogService.instance
          .w('Chat', 'clearCallMessages 失败: $e', chatId: chatId);
    }
  }


  /// 通话结束后强制提取一次通话记忆（不走降频，保证内容入库）。
  /// 传入 [recentMessages] 为通话内的用户/AI 消息。
  Future<void> extractCallMemories({
    required String chatId,
    required List<ChatMessage> recentMessages,
  }) async {
    try {
      final safeRecent = recentMessages
          .where(
              (m) => !(m.isFromAI && MessageSanitizer.isAIRefusal(m.content)))
          .toList();
      if (safeRecent.length < 2) return;
      final session = await _storage.getChatSession(chatId);
      if (session == null) return;
      final character = await _storage.getAICharacter(session.aiCharacterId);
      if (character == null) return;
      await _memoryEngine.extractMemory(
        character: character,
        userId: session.userId,
        recentMessages: safeRecent,
        characterName: character.name,
      );
      LogService.instance
          .i('Memory', '通话记忆提取完成 (msgs=${safeRecent.length})', chatId: chatId);
    } catch (e) {
      LogService.instance.w('Memory', '通话记忆提取失败: $e', chatId: chatId);
    }
  }

  // ═══════════════════════════════════════════════════════
  // 桥接层辅助方法（渐进迁移：优先用新适配器，回退到旧服务）
  // ═══════════════════════════════════════════════════════


  /// 是否使用新适配器（当 _aiAdapter 不为空时启用）
  bool get _useAdapter => _aiAdapter != null;


  int _getTypingDelay(String personality) => getTypingDelay(personality);


  List<String> _extractKeywords(String text) => extractKeywords(text);


  String _formatAiError(Object error) => formatAiError(error);


  double _avgMessageLength(String chatId) {
    final lengths = _msgLengths[chatId] ?? [];
    if (lengths.isEmpty) return 0;
    return lengths.reduce((a, b) => a + b) / lengths.length;
  }


  Future<LlmSettings> _loadLlmSettings() async {
    final config = await _storage.getActiveAIConfig();
    if (config != null) {
      return LlmSettings(
        apiKey: config.apiKey,
        baseUrl: config.baseUrl,
        model: config.modelName,
      );
    }
    return const LlmSettings();
  }
}
