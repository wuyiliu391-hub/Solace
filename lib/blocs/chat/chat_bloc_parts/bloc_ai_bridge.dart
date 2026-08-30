// 纯AI/适配器桥接（拆分生成，同库 part）
part of '../chat_bloc.dart';

mixin _BlocAiBridge on Bloc<ChatEvent, ChatState>, ChatBlocUtils, ChatBlocIntimacy, _ChatBlocCore, _BlocCallsBase {
  List<PureAIMessage> _toPureAIHistory(List<ChatMessage> chatHistory) {
    final recent = chatHistory.length > Limit.chatHistoryContext
        ? chatHistory.sublist(chatHistory.length - Limit.chatHistoryContext)
        : chatHistory;
    return recent
        .where((m) =>
            !m.isSystem &&
            !m.isHidden &&
            !m.isGhost &&
            !MessageSanitizer.isLikelyUnreadableGibberish(m.content))
        .map((m) => PureAIMessage(
              id: m.id,
              sessionId: m.chatId,
              senderId: m.isFromAI ? 'ai' : m.senderId,
              senderName: m.isFromAI ? 'AI' : m.senderName,
              content: MessageSanitizer.sanitizeFinal(m.content),
              type: m.type,
              status: m.status,
              createdAt: m.createdAt,
              metadata: m.metadata,
            ))
        .where((m) => m.content.trim().isNotEmpty)
        .toList();
  }


  /// 发送消息（桥接：优先适配器）
  Future<String> _bridgeSendMessage({
    required AICharacter character,
    required String userId,
    required String userMessage,
    required List<ChatMessage> chatHistory,
    required List<Memory> memories,
    required int intimacyLevel,
    String? userStatus,
    SentimentResult? sentiment,
    String? imageDescription,
    List<String>? imagePaths,
    bool isBlockedByAI = false,
    String? blockReason,
    bool enableWebSearch = false,
    String? internalSystemContext,
    bool isSideStory = false,
    bool forceConcise = false,
  }) async {
    if (_isPureAIForced) {
      return _pureAIService.sendPureAIMessage(
        userMessage: userMessage,
        chatHistory: _toPureAIHistory(chatHistory),
        imageDescription: imageDescription,
        imagePaths: imagePaths,
        enableWebSearch: enableWebSearch,
      );
    }

    // 统一咽喉：过滤乱码 + AI 拒绝/脱角色消息，确保换模型后旧拒绝不再被重新注入。
    final safeChatHistory = chatHistory
        .where((m) =>
            !MessageSanitizer.isLikelyUnreadableGibberish(m.content) &&
            !(m.isFromAI && MessageSanitizer.isAIRefusal(m.content)))
        .toList();
    final safeMemories = memories
        .where((m) => !MessageSanitizer.isLikelyUnreadableGibberish(m.content))
        .toList();
    if (_useAdapter) {
      return _aiAdapter!.sendMessage(
        character: character,
        userId: userId,
        userMessage: userMessage,
        chatHistory: safeChatHistory,
        memories: safeMemories,
        intimacyLevel: intimacyLevel,
        sentiment: sentiment,
        imageDescription: imageDescription,
        imagePaths: imagePaths,
        isBlockedByAI: isBlockedByAI,
        blockReason: blockReason,
        enableWebSearch: enableWebSearch,
        internalSystemContext: internalSystemContext,
        isSideStory: isSideStory,
        forceConcise: forceConcise,
      );
    }
    return _aiService.sendMessage(
      character: character,
      userId: userId,
      userMessage: userMessage,
      chatHistory: safeChatHistory,
      memories: safeMemories,
      intimacyLevel: intimacyLevel,
      sentiment: sentiment,
      imageDescription: imageDescription,
      imagePaths: imagePaths,
      isBlockedByAI: isBlockedByAI,
      blockReason: blockReason,
      enableWebSearch: enableWebSearch,
      internalSystemContext: internalSystemContext,
      isSideStory: isSideStory,
      forceConcise: forceConcise,
    );
  }


  /// 合并流式思考内容用于实时展示。
  ///
  /// 部分推理模型不使用独立的 reasoning_content 字段，而是把思考直接写在
  /// 正文的 <think>…</think> 里。思考阶段该标签尚未闭合，sanitizeStream
  /// 会把它整段清空，导致 streamText 与 chunk.reasoning 双双为空、消费循环
  /// 一直不 emit —— 表现为「先卡住、思考完才一次性蹦出正文」。
  /// 这里同时把 content 内嵌的 <think> 提取出来纳入 reasoning，
  /// 让思考过程也能逐 chunk 实时流式显示。
  String _mergeStreamReasoning(AIStreamChunk chunk) {
    final fromField = MessageSanitizer.sanitizeStream(chunk.reasoning);
    // cleanForStreamDisplay 返回 [正文, 从 content 提取出的思考]
    final parts = AIService.cleanForStreamDisplay(chunk.content);
    final fromContent =
        parts.length > 1 ? MessageSanitizer.sanitizeStream(parts[1]) : '';
    return [fromField, fromContent].where((r) => r.isNotEmpty).join('\n');
  }


  /// 流式发送（桥接：优先适配器）
  Stream<AIStreamChunk> _bridgeSendMessageStream({
    required AICharacter character,
    required String userId,
    required String userMessage,
    required List<ChatMessage> chatHistory,
    required List<Memory> memories,
    required int intimacyLevel,
    String? userStatus,
    SentimentResult? sentiment,
    String? imageDescription,
    List<String>? imagePaths,
    bool isBlockedByAI = false,
    String? blockReason,
    bool enableWebSearch = false,
    String? internalSystemContext,
    bool isSideStory = false,
    bool forceConcise = false,
  }) {
    if (_isPureAIForced) {
      return _pureAIService.sendPureAIMessageStream(
        userMessage: userMessage,
        chatHistory: _toPureAIHistory(chatHistory),
        imageDescription: imageDescription,
        imagePaths: imagePaths,
        enableWebSearch: enableWebSearch,
      );
    }

    // 统一咽喉：过滤乱码 + AI 拒绝/脱角色消息，确保换模型后旧拒绝不再被重新注入。
    final safeChatHistory = chatHistory
        .where((m) =>
            !MessageSanitizer.isLikelyUnreadableGibberish(m.content) &&
            !(m.isFromAI && MessageSanitizer.isAIRefusal(m.content)))
        .toList();
    final safeMemories = memories
        .where((m) => !MessageSanitizer.isLikelyUnreadableGibberish(m.content))
        .toList();
    if (_useAdapter) {
      return _aiAdapter!.sendMessageStream(
        character: character,
        userId: userId,
        userMessage: userMessage,
        chatHistory: safeChatHistory,
        memories: safeMemories,
        intimacyLevel: intimacyLevel,
        sentiment: sentiment,
        imageDescription: imageDescription,
        imagePaths: imagePaths,
        isBlockedByAI: isBlockedByAI,
        blockReason: blockReason,
        enableWebSearch: enableWebSearch,
        internalSystemContext: internalSystemContext,
        isSideStory: isSideStory,
        forceConcise: forceConcise,
      );
    }
    return _aiService.sendMessageStream(
      character: character,
      userId: userId,
      userMessage: userMessage,
      chatHistory: safeChatHistory,
      memories: safeMemories,
      intimacyLevel: intimacyLevel,
      sentiment: sentiment,
      imageDescription: imageDescription,
      imagePaths: imagePaths,
      isBlockedByAI: isBlockedByAI,
      blockReason: blockReason,
      enableWebSearch: enableWebSearch,
      internalSystemContext: internalSystemContext,
      isSideStory: isSideStory,
      forceConcise: forceConcise,
    );
  }


  /// 拆分消息（桥接）
  List<String> _bridgeSplitMessages(String text) {
    final parts = _useAdapter
        ? _aiAdapter!.splitIntoMessages(text)
        : _aiService.splitIntoMessages(text);
    return parts
        .map(MessageSanitizer.sanitizeFinal)
        .where((part) => part.isNotEmpty)
        .toList();
  }

}
