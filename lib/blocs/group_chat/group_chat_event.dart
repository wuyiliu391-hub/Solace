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
  List<Object?> get props =>
      [userId, name, avatarUrl, memberIds, aiCharacterIds];
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

/// 加载更早的群聊消息（上滑分页）
class GroupChatLoadMoreMessages extends GroupChatEvent {
  final String groupId;
  const GroupChatLoadMoreMessages(this.groupId);
  @override
  List<Object?> get props => [groupId];
}

/// 发送群聊消息
class GroupChatSendMessage extends GroupChatEvent {
  final String groupId;
  final String userId;
  final String content;
  final List<String>? imagePaths;

  /// 消息元数据（引用 replyTo / 动作标记等）
  final Map<String, dynamic>? metadata;
  const GroupChatSendMessage({
    required this.groupId,
    required this.userId,
    required this.content,
    this.imagePaths,
    this.metadata,
  });
  @override
  List<Object?> get props => [groupId, userId, content, imagePaths, metadata];
}

/// 删除单条群聊消息
class GroupChatDeleteMessage extends GroupChatEvent {
  final String groupId;
  final String messageId;
  const GroupChatDeleteMessage(
      {required this.groupId, required this.messageId});
  @override
  List<Object?> get props => [groupId, messageId];
}

/// 收藏 / 取消收藏群聊消息
class GroupChatToggleBookmark extends GroupChatEvent {
  final String groupId;
  final String messageId;
  const GroupChatToggleBookmark(
      {required this.groupId, required this.messageId});
  @override
  List<Object?> get props => [groupId, messageId];
}

/// 编辑 AI 回复内容（仅 AI 消息）
class GroupChatEditAIReply extends GroupChatEvent {
  final String groupId;
  final String messageId;
  final String newContent;
  const GroupChatEditAIReply({
    required this.groupId,
    required this.messageId,
    required this.newContent,
  });
  @override
  List<Object?> get props => [groupId, messageId, newContent];
}

/// 重新生成 AI 回复（删旧消息 + 该角色重新回复）
class GroupChatRegenerateMessage extends GroupChatEvent {
  final String groupId;
  final String messageId;
  const GroupChatRegenerateMessage({
    required this.groupId,
    required this.messageId,
  });
  @override
  List<Object?> get props => [groupId, messageId];
}

class GroupChatSelectSwipe extends GroupChatEvent {
  final String groupId;
  final String messageId;
  final int index;
  const GroupChatSelectSwipe(
      {required this.groupId, required this.messageId, required this.index});
  @override
  List<Object?> get props => [groupId, messageId, index];
}

class GroupChatSaveLorebookEntry extends GroupChatEvent {
  final GroupChatLorebookEntry entry;
  const GroupChatSaveLorebookEntry(this.entry);
  @override
  List<Object?> get props => [entry.id, entry.content, entry.keywords];
}

class GroupChatDeleteLorebookEntry extends GroupChatEvent {
  final String groupId;
  final String entryId;
  const GroupChatDeleteLorebookEntry(
      {required this.groupId, required this.entryId});
  @override
  List<Object?> get props => [groupId, entryId];
}

/// 撤回用户消息（2 分钟内，改为「已撤回」占位）
class GroupChatRecallMessage extends GroupChatEvent {
  final String groupId;
  final String messageId;
  const GroupChatRecallMessage(
      {required this.groupId, required this.messageId});
  @override
  List<Object?> get props => [groupId, messageId];
}

/// 更新群聊信息
class GroupChatUpdateSession extends GroupChatEvent {
  final String groupId;
  final String? name;
  final String? avatarUrl;
  final bool? isMuted;
  final bool? isPinned;
  final String? backgroundImage;
  final String? notice; // 群公告（存 metadata['notice']）
  final bool? isHidden;
  const GroupChatUpdateSession({
    required this.groupId,
    this.name,
    this.avatarUrl,
    this.isMuted,
    this.isPinned,
    this.backgroundImage,
    this.notice,
    this.isHidden,
  });
  @override
  List<Object?> get props => [
        groupId,
        name,
        avatarUrl,
        isMuted,
        isPinned,
        backgroundImage,
        notice,
        isHidden,
      ];
}

/// AI 角色回复完成（内部触发接话/接力）
class GroupChatAIMessageSaved extends GroupChatEvent {
  final String groupId;
  final String characterId;
  final String content;
  const GroupChatAIMessageSaved({
    required this.groupId,
    required this.characterId,
    required this.content,
  });
  @override
  List<Object?> get props => [groupId, characterId, content];
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

/// 手动锁定发言人（内存态，对标 ST 手动激活；不落库）
class GroupChatSetSpeakers extends GroupChatEvent {
  final String groupId;
  final List<String> speakerIds;
  const GroupChatSetSpeakers({
    required this.groupId,
    required this.speakerIds,
  });
  @override
  List<Object?> get props => [groupId, speakerIds];
}

/// 更新群聊引擎配置（激活策略/生成模式/禁言/允自答/自动接话）
class GroupChatUpdateConfig extends GroupChatEvent {
  final String groupId;
  final GroupActivationStrategy? activationStrategy;
  final GroupGenerationMode? generationMode;
  final bool? allowSelfResponses;
  final List<String>? disabledMemberIds;
  final int? autoModeDelay;
  final bool? autoModeEnabled;
  final Map<String, int>? autoModeDelaysByCharacter;
  const GroupChatUpdateConfig({
    required this.groupId,
    this.activationStrategy,
    this.generationMode,
    this.allowSelfResponses,
    this.disabledMemberIds,
    this.autoModeDelay,
    this.autoModeEnabled,
    this.autoModeDelaysByCharacter,
  });
  @override
  List<Object?> get props => [
        groupId,
        activationStrategy,
        generationMode,
        allowSelfResponses,
        disabledMemberIds,
        autoModeDelay,
        autoModeEnabled,
        autoModeDelaysByCharacter,
      ];
}

/// 新建聊天记录（分支）
class GroupChatCreateBranch extends GroupChatEvent {
  final String groupId;
  final String name;
  final String? forkMessageId;
  const GroupChatCreateBranch(
      {required this.groupId, required this.name, this.forkMessageId});
  @override
  List<Object?> get props => [groupId, name, forkMessageId];
}

/// 切换聊天记录
class GroupChatSwitchBranch extends GroupChatEvent {
  final String groupId;
  final String chatId;
  const GroupChatSwitchBranch({required this.groupId, required this.chatId});
  @override
  List<Object?> get props => [groupId, chatId];
}

/// 删除聊天记录
class GroupChatDeleteBranch extends GroupChatEvent {
  final String groupId;
  final String chatId;
  const GroupChatDeleteBranch({required this.groupId, required this.chatId});
  @override
  List<Object?> get props => [groupId, chatId];
}
