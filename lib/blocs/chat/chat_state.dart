part of 'chat_bloc.dart';

abstract class ChatState extends Equatable {
  const ChatState();

  @override
  List<Object?> get props => [];
}

class ChatInitial extends ChatState {}

class ChatLoading extends ChatState {}

class ChatSessionsLoaded extends ChatState {
  final List<ChatSession> sessions;

  const ChatSessionsLoaded(this.sessions);

  @override
  List<Object?> get props => [sessions];
}

class ChatMessagesLoaded extends ChatState {
  final List<ChatMessage> messages;
  final bool hasMore;

  const ChatMessagesLoaded(this.messages, {this.hasMore = true});

  @override
  List<Object?> get props => [messages, hasMore];
}

class ChatAITyping extends ChatState {
  final List<ChatMessage> messages;
  final String characterName;

  const ChatAITyping(this.messages, this.characterName);

  @override
  List<Object?> get props => [messages, characterName];
}

class ChatAIStreaming extends ChatState {
  final List<ChatMessage> messages;
  final String streamingText;
  final String characterName;
  final String reasoning;

  const ChatAIStreaming(this.messages, this.streamingText, this.characterName,
      {this.reasoning = ''});

  @override
  List<Object?> get props =>
      [messages, streamingText, characterName, reasoning];
}

class ChatSessionCreated extends ChatState {
  final ChatSession session;

  const ChatSessionCreated(this.session);

  @override
  List<Object?> get props => [session];
}

class ChatError extends ChatState {
  final String message;

  const ChatError(this.message);

  @override
  List<Object?> get props => [message];
}

class ChatIntimacyChanged extends ChatState {
  final String chatId;
  final int oldLevel;
  final int newLevel;

  const ChatIntimacyChanged({
    required this.chatId,
    required this.oldLevel,
    required this.newLevel,
  });

  @override
  List<Object?> get props => [chatId, oldLevel, newLevel];
}

class ChatEmotionChanged extends ChatState {
  final String chatId;
  final String emotionLabel;
  final SentimentType emotionType;

  const ChatEmotionChanged({
    required this.chatId,
    required this.emotionLabel,
    required this.emotionType,
  });

  @override
  List<Object?> get props => [chatId, emotionLabel, emotionType];
}

class ChatTransferStatusUpdated extends ChatState {
  final String messageId;
  final String transferStatus;
  final List<ChatMessage> messages;

  const ChatTransferStatusUpdated({
    required this.messageId,
    required this.transferStatus,
    required this.messages,
  });

  @override
  List<Object?> get props => [messageId, transferStatus, messages];
}

class ChatAICoinsSent extends ChatState {
  final String characterId;
  final double amount;
  final List<ChatMessage> messages;

  const ChatAICoinsSent({
    required this.characterId,
    required this.amount,
    required this.messages,
  });

  @override
  List<Object?> get props => [characterId, amount, messages];
}

/// AI 正在生成图片（显示在消息列表中，类似 TypingIndicator）

/// ??????????? Operit InputProcessingState
enum ChatProcessingState {
  idle,
  preparing,
  connecting,
  receiving,
  executingTool,
  processingToolResult,
  completed,
  error,
}

/// AI ???????????????
class ChatAIProcessing extends ChatState {
  final List<ChatMessage> messages;
  final String statusText;
  final String characterName;
  final ChatProcessingState processingState;

  const ChatAIProcessing(
    this.messages,
    this.statusText,
    this.characterName, {
    this.processingState = ChatProcessingState.preparing,
  });

  @override
  List<Object?> get props => [messages, statusText, characterName, processingState];
}

class ChatBlockedByAI extends ChatState {
  final String chatId;
  final String reason;
  final List<ChatMessage> messages;

  const ChatBlockedByAI({
    required this.chatId,
    required this.reason,
    required this.messages,
  });

  @override
  List<Object?> get props => [chatId, reason, messages];
}

class ChatUnblockedByAI extends ChatState {
  final String chatId;
  final List<ChatMessage> messages;

  const ChatUnblockedByAI({
    required this.chatId,
    required this.messages,
  });

  @override
  List<Object?> get props => [chatId, messages];
}

class ChatAIObserving extends ChatState {
  final String chatId;
  final String statusText;
  final String? emotionLabel;
  final String? emotionEmoji;
  final double? emotionIntensity;
  final int pendingCount;
  final List<ChatMessage> messages;

  const ChatAIObserving({
    required this.chatId,
    required this.statusText,
    this.emotionLabel,
    this.emotionEmoji,
    this.emotionIntensity,
    this.pendingCount = 0,
    required this.messages,
  });

  @override
  List<Object?> get props => [
        chatId,
        statusText,
        emotionLabel,
        emotionEmoji,
        emotionIntensity,
        pendingCount,
        messages
      ];
}

class ChatPersonaEvolved extends ChatState {
  final String chatId;
  final String characterId;
  final String mode;
  final String summary;

  const ChatPersonaEvolved({
    required this.chatId,
    required this.characterId,
    required this.mode,
    required this.summary,
  });

  @override
  List<Object?> get props => [chatId, characterId, mode, summary];
}

// ── SillyTavern 对标状态：消息滑动 ──

/// 消息滑动完成（对标 SillyTavern swipe 更新）
class ChatSwiped extends ChatState {
  final String chatId;
  final String messageId;
  final int newIndex;
  final String content;

  const ChatSwiped({
    required this.chatId,
    required this.messageId,
    required this.newIndex,
    required this.content,
  });

  @override
  List<Object?> get props => [chatId, messageId, newIndex, content];
}

// ── SillyTavern 对标状态：消息操作反馈 ──

/// 消息已隐藏（对标 SillyTavern mes_hide）
class ChatMessageHidden extends ChatState {
  final String chatId;
  final String messageId;

  const ChatMessageHidden({
    required this.chatId,
    required this.messageId,
  });

  @override
  List<Object?> get props => [chatId, messageId];
}

/// 消息已取消隐藏（对标 SillyTavern mes_unhide）
class ChatMessageUnhidden extends ChatState {
  final String chatId;
  final String messageId;

  const ChatMessageUnhidden({
    required this.chatId,
    required this.messageId,
  });

  @override
  List<Object?> get props => [chatId, messageId];
}

/// 消息已删除（对标 SillyTavern deleteMessage）
class ChatMessageDeleted extends ChatState {
  final String chatId;
  final String messageId;

  const ChatMessageDeleted({
    required this.chatId,
    required this.messageId,
  });

  @override
  List<Object?> get props => [chatId, messageId];
}

/// 消息已复制（对标 SillyTavern mes_copy）
class ChatMessageCopied extends ChatState {
  final String chatId;
  final String messageId;
  final String content;

  const ChatMessageCopied({
    required this.chatId,
    required this.messageId,
    required this.content,
  });

  @override
  List<Object?> get props => [chatId, messageId, content];
}

/// 上下文已清空（对标 SillyTavern clearContext）
class ChatContextCleared extends ChatState {
  final String chatId;

  const ChatContextCleared({required this.chatId});

  @override
  List<Object?> get props => [chatId];
}

// ── AutoGLM 自动化状态 ──

/// AutoGLM 正在执行中
class ChatAutoGlmRunning extends ChatState {
  final List<ChatMessage> messages;
  final int currentStep;
  final int maxSteps;
  final String? currentAction;
  final String? thinking;

  const ChatAutoGlmRunning({
    required this.messages,
    required this.currentStep,
    required this.maxSteps,
    this.currentAction,
    this.thinking,
  });

  @override
  List<Object?> get props => [messages, currentStep, maxSteps, currentAction, thinking];
}

/// AutoGLM 执行完成
class ChatAutoGlmCompleted extends ChatState {
  final List<ChatMessage> messages;
  final bool success;
  final String resultMessage;
  final int totalSteps;

  const ChatAutoGlmCompleted({
    required this.messages,
    required this.success,
    required this.resultMessage,
    required this.totalSteps,
  });

  @override
  List<Object?> get props => [messages, success, resultMessage, totalSteps];
}
