part of 'chat_bloc.dart';

abstract class ChatEvent extends Equatable {
  const ChatEvent();

  @override
  List<Object?> get props => [];
}

class ChatLoadSessions extends ChatEvent {
  final String userId;

  const ChatLoadSessions(this.userId);

  @override
  List<Object?> get props => [userId];
}

class ChatLoadMessages extends ChatEvent {
  final String chatId;

  const ChatLoadMessages(this.chatId);

  @override
  List<Object?> get props => [chatId];
}

class ChatLoadMoreMessages extends ChatEvent {
  final String chatId;

  const ChatLoadMoreMessages(this.chatId);

  @override
  List<Object?> get props => [chatId];
}

class ChatLoadUntilMessage extends ChatEvent {
  final String chatId;
  final String messageId;

  const ChatLoadUntilMessage({
    required this.chatId,
    required this.messageId,
  });

  @override
  List<Object?> get props => [chatId, messageId];
}

class ChatSendMessage extends ChatEvent {
  final String chatId;
  final String userId;
  final String content;
  final Map<String, dynamic>? metadata;
  final bool enableWebSearch;

  const ChatSendMessage({
    required this.chatId,
    required this.userId,
    required this.content,
    this.metadata,
    this.enableWebSearch = false,
  });

  @override
  List<Object?> get props =>
      [chatId, userId, content, metadata, enableWebSearch];
}

class ChatCreateSession extends ChatEvent {
  final String userId;
  final AICharacter character;

  const ChatCreateSession({
    required this.userId,
    required this.character,
  });

  @override
  List<Object?> get props => [userId, character];
}

class ChatDeleteSession extends ChatEvent {
  final String chatId;
  final String userId;

  const ChatDeleteSession({
    required this.chatId,
    required this.userId,
  });

  @override
  List<Object?> get props => [chatId, userId];
}

class ChatSendVoiceMessage extends ChatEvent {
  final String chatId;
  final String userId;
  final String characterId;
  final String audioPath;
  final int duration;
  final String transcript;

  const ChatSendVoiceMessage({
    required this.chatId,
    required this.userId,
    required this.characterId,
    required this.audioPath,
    required this.duration,
    required this.transcript,
  });

  @override
  List<Object?> get props =>
      [chatId, userId, characterId, audioPath, duration, transcript];
}

class ChatSendSticker extends ChatEvent {
  final String chatId;
  final String userId;
  final String sticker;
  final bool isImageSticker;

  const ChatSendSticker({
    required this.chatId,
    required this.userId,
    required this.sticker,
    this.isImageSticker = false,
  });

  @override
  List<Object?> get props => [chatId, userId, sticker, isImageSticker];
}

class ChatProactiveReply extends ChatEvent {
  final String chatId;
  final String userId;

  const ChatProactiveReply({
    required this.chatId,
    required this.userId,
  });

  @override
  List<Object?> get props => [chatId, userId];
}

class ChatSendRedPacket extends ChatEvent {
  final String chatId;
  final String userId;
  final double amount;
  final String? message;

  const ChatSendRedPacket({
    required this.chatId,
    required this.userId,
    required this.amount,
    this.message,
  });

  @override
  List<Object?> get props => [chatId, userId, amount, message];
}

class ChatSendGift extends ChatEvent {
  final String chatId;
  final String userId;
  final String itemName;
  final String itemEmoji;
  final int price;
  final String? message;

  const ChatSendGift({
    required this.chatId,
    required this.userId,
    required this.itemName,
    required this.itemEmoji,
    required this.price,
    this.message,
  });

  @override
  List<Object?> get props =>
      [chatId, userId, itemName, itemEmoji, price, message];
}

class ChatAISendCoins extends ChatEvent {
  final String chatId;
  final String characterId;
  final double amount;
  final String? message;

  const ChatAISendCoins({
    required this.chatId,
    required this.characterId,
    required this.amount,
    this.message,
  });

  @override
  List<Object?> get props => [chatId, characterId, amount, message];
}

class ChatBlockByUser extends ChatEvent {
  final String chatId;
  final String userId;

  const ChatBlockByUser({
    required this.chatId,
    required this.userId,
  });

  @override
  List<Object?> get props => [chatId, userId];
}

class ChatUnblockByUser extends ChatEvent {
  final String chatId;
  final String userId;

  const ChatUnblockByUser({
    required this.chatId,
    required this.userId,
  });

  @override
  List<Object?> get props => [chatId, userId];
}

class ChatAIForgaveUser extends ChatEvent {
  final String chatId;
  final String? forgiveMessage;

  const ChatAIForgaveUser({
    required this.chatId,
    this.forgiveMessage,
  });

  @override
  List<Object?> get props => [chatId, forgiveMessage];
}

class ChatAIObservingNotify extends ChatEvent {
  final String chatId;
  final String statusText;
  final String? emotionLabel;
  final String? emotionEmoji;
  final double? emotionIntensity;
  final int pendingCount;

  const ChatAIObservingNotify({
    required this.chatId,
    required this.statusText,
    this.emotionLabel,
    this.emotionEmoji,
    this.emotionIntensity,
    this.pendingCount = 0,
  });

  @override
  List<Object?> get props => [
        chatId,
        statusText,
        emotionLabel,
        emotionEmoji,
        emotionIntensity,
        pendingCount
      ];
}

class ChatEditAIReply extends ChatEvent {
  final String chatId;
  final String messageId;
  final String newContent;

  const ChatEditAIReply({
    required this.chatId,
    required this.messageId,
    required this.newContent,
  });

  @override
  List<Object?> get props => [chatId, messageId, newContent];
}

class ChatRegenerateAIReply extends ChatEvent {
  final String chatId;
  final String messageId;

  const ChatRegenerateAIReply({
    required this.chatId,
    required this.messageId,
  });

  @override
  List<Object?> get props => [chatId, messageId];
}

// ── SillyTavern 对标事件：消息滑动 ──

/// 滑动到下一条备选回复（对标 SillyTavern swipe_right）
class ChatSwipeRight extends ChatEvent {
  final String chatId;
  final String messageId;

  const ChatSwipeRight({
    required this.chatId,
    required this.messageId,
  });

  @override
  List<Object?> get props => [chatId, messageId];
}

/// 滑动到上一条备选回复（对标 SillyTavern swipe_left）
class ChatSwipeLeft extends ChatEvent {
  final String chatId;
  final String messageId;

  const ChatSwipeLeft({
    required this.chatId,
    required this.messageId,
  });

  @override
  List<Object?> get props => [chatId, messageId];
}

// ── SillyTavern 对标事件：消息操作 ──

/// 隐藏消息（对标 SillyTavern hideChatMessageRange）
/// 隐藏的消息对 AI 不可见（is_system = true）
class ChatHideMessage extends ChatEvent {
  final String chatId;
  final String messageId;

  const ChatHideMessage({
    required this.chatId,
    required this.messageId,
  });

  @override
  List<Object?> get props => [chatId, messageId];
}

/// 取消隐藏消息（对标 SillyTavern unhideChatMessageRange）
class ChatUnhideMessage extends ChatEvent {
  final String chatId;
  final String messageId;

  const ChatUnhideMessage({
    required this.chatId,
    required this.messageId,
  });

  @override
  List<Object?> get props => [chatId, messageId];
}

/// 删除单条消息（对标 SillyTavern deleteMessage）
class ChatDeleteMessage extends ChatEvent {
  final String chatId;
  final String messageId;

  const ChatDeleteMessage({
    required this.chatId,
    required this.messageId,
  });

  @override
  List<Object?> get props => [chatId, messageId];
}

/// 收藏/取消收藏消息（对标 SillyTavern mes_bookmark）
class ChatToggleBookmark extends ChatEvent {
  final String chatId;
  final String messageId;

  const ChatToggleBookmark({
    required this.chatId,
    required this.messageId,
  });

  @override
  List<Object?> get props => [chatId, messageId];
}

/// 复制消息内容（对标 SillyTavern mes_copy）
class ChatCopyMessage extends ChatEvent {
  final String chatId;
  final String messageId;

  const ChatCopyMessage({
    required this.chatId,
    required this.messageId,
  });

  @override
  List<Object?> get props => [chatId, messageId];
}

/// 上移消息（对标 SillyTavern mes_edit_up）
class ChatMoveMessageUp extends ChatEvent {
  final String chatId;
  final String messageId;

  const ChatMoveMessageUp({
    required this.chatId,
    required this.messageId,
  });

  @override
  List<Object?> get props => [chatId, messageId];
}

/// 下移消息（对标 SillyTavern mes_edit_down）
class ChatMoveMessageDown extends ChatEvent {
  final String chatId;
  final String messageId;

  const ChatMoveMessageDown({
    required this.chatId,
    required this.messageId,
  });

  @override
  List<Object?> get props => [chatId, messageId];
}

/// 创建检查点/分支（对标 SillyTavern mes_create_bookmark / mes_create_branch）
class ChatCreateBranch extends ChatEvent {
  final String chatId;
  final String messageId;

  const ChatCreateBranch({
    required this.chatId,
    required this.messageId,
  });

  @override
  List<Object?> get props => [chatId, messageId];
}

/// 清空上下文（对标 SillyTavern clearContext）
class ChatClearContext extends ChatEvent {
  final String chatId;

  const ChatClearContext({required this.chatId});

  @override
  List<Object?> get props => [chatId];
}

// ── AutoGLM 自动化事件 ──

/// 在聊天中触发 AutoGLM 自动化任务
class ChatRunAutoGlm extends ChatEvent {
  final String chatId;
  final String userId;
  final String task;

  const ChatRunAutoGlm({
    required this.chatId,
    required this.userId,
    required this.task,
  });

  @override
  List<Object?> get props => [chatId, userId, task];
}

/// 取消正在执行的 AutoGLM 任务
class ChatCancelAutoGlm extends ChatEvent {
  final String chatId;

  const ChatCancelAutoGlm({required this.chatId});

  @override
  List<Object?> get props => [chatId];
}
