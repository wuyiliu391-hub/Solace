import 'package:equatable/equatable.dart';
import '../../models/ai_character.dart' show AICharacter;
import '../../models/chat_message.dart';
import '../../models/group_chat_session.dart';
import '../../models/group_member_settings.dart';
import '../../models/group_relationship.dart';

abstract class GroupChatState extends Equatable {
  const GroupChatState();
  @override
  List<Object?> get props => [];
}

class GroupChatInitial extends GroupChatState {}

class GroupChatLoading extends GroupChatState {}

class GroupChatSessionsLoaded extends GroupChatState {
  final List<GroupChatSession> sessions;
  const GroupChatSessionsLoaded(this.sessions);
  @override
  List<Object?> get props => [sessions];
}

class GroupChatMessagesLoaded extends GroupChatState {
  final String groupChatId;
  final List<ChatMessage> messages;
  final bool hasMore;
  const GroupChatMessagesLoaded({required this.groupChatId, required this.messages, this.hasMore = true});
  @override
  List<Object?> get props => [groupChatId, messages, hasMore];
}

class GroupChatAITyping extends GroupChatState {
  final String characterName;
  const GroupChatAITyping(this.characterName);
  @override
  List<Object?> get props => [characterName];
}

class GroupChatAIStreaming extends GroupChatState {
  final String groupChatId;
  final List<ChatMessage> messages;
  final String streamingText;
  final String characterName;
  final String reasoning;
  const GroupChatAIStreaming({required this.groupChatId, required this.messages, required this.streamingText, required this.characterName, this.reasoning = ''});
  @override
  List<Object?> get props => [groupChatId, messages, streamingText, characterName, reasoning];
}

class GroupChatSessionCreated extends GroupChatState {
  final GroupChatSession session;
  const GroupChatSessionCreated(this.session);
  @override
  List<Object?> get props => [session];
}

class GroupChatSettingsLoaded extends GroupChatState {
  final GroupChatSession session;
  final List<AICharacter> participants;
  final List<GroupMemberSettings> memberSettings;
  final List<GroupRelationship> relationships;
  const GroupChatSettingsLoaded({required this.session, required this.participants, required this.memberSettings, required this.relationships});
  @override
  List<Object?> get props => [session, participants, memberSettings, relationships];
}

class GroupChatError extends GroupChatState {
  final String message;
  const GroupChatError(this.message);
  @override
  List<Object?> get props => [message];
}
