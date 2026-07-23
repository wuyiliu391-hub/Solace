part of 'group_chat_bloc.dart';

abstract class GroupChatEvent extends Equatable {
  const GroupChatEvent();

  @override
  List<Object?> get props => [];
}

/// 加载群聊会话列表
class GroupChatLoadSessions extends GroupChatEvent {
  final String userId;
  const GroupChatLoadSessions(this.userId);
  @override
  List<Object?> get props => [userId];
}

/// 创建新群聊
class GroupChatCreate extends GroupChatEvent {
  final String userId;
  final String name;
  final String? avatarUrl;
  final List<String> memberIds;
  final List<String> aiCharacterIds;
  const GroupChatCreate({
    required this.userId,
    required this.name,
    this.avatarUrl,
    required this.memberIds,
    required this.aiCharacterIds,
  });
  @override
  List<Object?> get props => [userId, name, avatarUrl, memberIds, aiCharacterIds];
}

/// 删除群聊
class GroupChatDelete extends GroupChatEvent {
  final String groupId;
  const GroupChatDelete(this.groupId);
  @override
  List<Object?> get props => [groupId];
}

/// 加载群聊消息
class GroupChatLoadMessages extends GroupChatEvent {
  final String groupId;
  const GroupChatLoadMessages(this.groupId);
  @override
  List<Object?> get props => [groupId];
}

/// 发送群聊消息
class GroupChatSendMessage extends GroupChatEvent {
  final String groupId;
  final String userId;
  final String content;
  const GroupChatSendMessage({
    required this.groupId,
    required this.userId,
    required this.content,
  });
  @override
  List<Object?> get props => [groupId, userId, content];
}

/// 更新群聊信息
class GroupChatUpdateSession extends GroupChatEvent {
  final String groupId;
  final String? name;
  final String? avatarUrl;
  final bool? isMuted;
  final bool? isPinned;
  final String? backgroundImage;
  const GroupChatUpdateSession({
    required this.groupId,
    this.name,
    this.avatarUrl,
    this.isMuted,
    this.isPinned,
    this.backgroundImage,
  });
  @override
  List<Object?> get props => [groupId, name, avatarUrl, isMuted, isPinned, backgroundImage];
}

/// 添加成员到群聊
class GroupChatAddMember extends GroupChatEvent {
  final String groupId;
  final String memberId;
  const GroupChatAddMember(this.groupId, this.memberId);
  @override
  List<Object?> get props => [groupId, memberId];
}

/// 移除群聊成员
class GroupChatRemoveMember extends GroupChatEvent {
  final String groupId;
  final String memberId;
  const GroupChatRemoveMember(this.groupId, this.memberId);
  @override
  List<Object?> get props => [groupId, memberId];
}

/// 标记群聊已读
class GroupChatMarkRead extends GroupChatEvent {
  final String groupId;
  const GroupChatMarkRead(this.groupId);
  @override
  List<Object?> get props => [groupId];
}
