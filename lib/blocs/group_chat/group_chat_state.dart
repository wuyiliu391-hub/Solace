part of 'group_chat_bloc.dart';

abstract class GroupChatState extends Equatable {
  const GroupChatState();

  @override
  List<Object?> get props => [];
}

/// 初始状态
class GroupChatInitial extends GroupChatState {}

/// 加载中
class GroupChatLoading extends GroupChatState {}

/// 群聊会话列表已加载
class GroupChatSessionsLoaded extends GroupChatState {
  final List<GroupChatSession> sessions;
  const GroupChatSessionsLoaded(this.sessions);
  @override
  List<Object?> get props => [sessions];
}

/// 群聊错误
class GroupChatError extends GroupChatState {
  final String message;
  const GroupChatError(this.message);
  @override
  List<Object?> get props => [message];
}

/// 群聊消息已加载
class GroupChatMessagesLoaded extends GroupChatState {
  final String groupId;
  final List<GroupChatMessage> messages;
  const GroupChatMessagesLoaded(this.groupId, this.messages);
  @override
  List<Object?> get props => [groupId, messages];
}

/// 群聊已创建
class GroupChatCreated extends GroupChatState {
  final GroupChatSession session;
  const GroupChatCreated(this.session);
  @override
  List<Object?> get props => [session];
}

/// 群聊已删除
class GroupChatDeleted extends GroupChatState {
  final String groupId;
  const GroupChatDeleted(this.groupId);
  @override
  List<Object?> get props => [groupId];
}

/// AI 正在回复中
class GroupChatAIReplying extends GroupChatState {
  final String groupId;
  final String statusText;
  const GroupChatAIReplying(this.groupId, this.statusText);
  @override
  List<Object?> get props => [groupId, statusText];
}

/// 某个 AI 角色正在输入中
class GroupChatTyping extends GroupChatState {
  final String groupId;
  final String characterName;
  final List<GroupChatMessage> messages;
  const GroupChatTyping(
    this.groupId,
    this.characterName, {
    this.messages = const [],
  });
  @override
  List<Object?> get props => [groupId, characterName, messages];
}

/// 某个 AI 角色流式输出中
class GroupChatStreaming extends GroupChatState {
  final String groupId;
  final String characterName;
  final String streamingText;
  final List<GroupChatMessage> messages;

  /// 实时思考内容（思考型模型 reasoning_content 或 content 内嵌 <think>，
  /// 思考阶段 streamingText 为空、reasoning 非空 —— 供 UI 显示「思考中…」）
  final String reasoning;
  const GroupChatStreaming(
    this.groupId,
    this.characterName,
    this.streamingText, {
    this.messages = const [],
    this.reasoning = '',
  });
  @override
  List<Object?> get props =>
      [groupId, characterName, streamingText, messages, reasoning];
}

/// 群聊聊天记录（分支）列表已加载
class GroupChatBranchesLoaded extends GroupChatState {
  final String groupId;
  final List<GroupChatBranch> branches;
  final String currentChatId;

  /// 加载时附带的同批消息。_onLoadMessages 会紧随其后 emit MessagesLoaded，
  /// 两帧合并时中间态可能被吞掉，故分支态自携带消息，供 UI 兜底渲染。
  final List<GroupChatMessage> messages;
  const GroupChatBranchesLoaded({
    required this.groupId,
    required this.branches,
    required this.currentChatId,
    this.messages = const [],
  });
  @override
  List<Object?> get props => [groupId, branches, currentChatId, messages];
}
