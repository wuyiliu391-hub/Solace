import 'package:equatable/equatable.dart';
import '../../models/ai_character.dart' show AICharacter;
import '../../models/group_chat_session.dart';
import '../../models/group_relationship.dart';

abstract class GroupChatEvent extends Equatable {
  const GroupChatEvent();
  @override
  List<Object?> get props => [];
}

class GroupChatLoadSessions extends GroupChatEvent {
  final String userId;
  const GroupChatLoadSessions(this.userId);
  @override
  List<Object?> get props => [userId];
}

class GroupChatCreateSession extends GroupChatEvent {
  final String userId;
  final String name;
  final String? scenario;
  final String? scenarioTemplate;
  final List<AICharacter> participants;
  final ReplyMode replyMode;
  final ActivationStrategy activationStrategy;
  final TavernMode tavernMode;
  final TavernImmersion immersion;
  final TavernInteractionFrequency interactionFrequency;
  final Map<String, List<String>> memberKeywords;
  const GroupChatCreateSession({
    required this.userId,
    required this.name,
    this.scenario,
    this.scenarioTemplate,
    required this.participants,
    this.replyMode = ReplyMode.flash,
    this.activationStrategy = ActivationStrategy.natural,
    this.tavernMode = TavernMode.group,
    this.immersion = TavernImmersion.daily,
    this.interactionFrequency = TavernInteractionFrequency.natural,
    this.memberKeywords = const {},
  });
  @override
  List<Object?> get props => [
        userId,
        name,
        scenario,
        scenarioTemplate,
        participants,
        replyMode,
        activationStrategy,
        tavernMode,
        immersion,
        interactionFrequency,
        memberKeywords,
      ];
}

class GroupChatDeleteSession extends GroupChatEvent {
  final String groupChatId;
  final String userId;
  const GroupChatDeleteSession(this.groupChatId, this.userId);
  @override
  List<Object?> get props => [groupChatId, userId];
}

class GroupChatLoadMessages extends GroupChatEvent {
  final String groupChatId;
  const GroupChatLoadMessages(this.groupChatId);
  @override
  List<Object?> get props => [groupChatId];
}

class GroupChatSendMessage extends GroupChatEvent {
  final String groupChatId;
  final String userId;
  final String content;
  const GroupChatSendMessage({required this.groupChatId, required this.userId, required this.content});
  @override
  List<Object?> get props => [groupChatId, userId, content];
}

class GroupChatForceReply extends GroupChatEvent {
  final String groupChatId;
  final String userId;
  final String characterId;
  final bool observeContinue;
  const GroupChatForceReply({
    required this.groupChatId,
    required this.userId,
    required this.characterId,
    this.observeContinue = false,
  });
  @override
  List<Object?> get props => [groupChatId, userId, characterId, observeContinue];
}

class GroupChatUpdateMember extends GroupChatEvent {
  final String groupChatId;
  final String characterId;
  final int? talkativeness;
  final bool? isMuted;
  final List<String>? triggerKeywords;
  const GroupChatUpdateMember({required this.groupChatId, required this.characterId, this.talkativeness, this.isMuted, this.triggerKeywords});
  @override
  List<Object?> get props => [groupChatId, characterId, talkativeness, isMuted, triggerKeywords];
}

class GroupChatUpdateRelationship extends GroupChatEvent {
  final String groupChatId;
  final String characterIdA;
  final String characterIdB;
  final CharacterRelationship relationship;
  const GroupChatUpdateRelationship({required this.groupChatId, required this.characterIdA, required this.characterIdB, required this.relationship});
  @override
  List<Object?> get props => [groupChatId, characterIdA, characterIdB, relationship];
}

class GroupChatUpdateSettings extends GroupChatEvent {
  final String groupChatId;
  final String? name;
  final String? scenario;
  final String? scenarioTemplate;
  final ReplyMode? replyMode;
  final ActivationStrategy? activationStrategy;
  final bool? autoModeEnabled;
  final bool? allowSelfResponse;
  const GroupChatUpdateSettings({required this.groupChatId, this.name, this.scenario, this.scenarioTemplate, this.replyMode, this.activationStrategy, this.autoModeEnabled, this.allowSelfResponse});
  @override
  List<Object?> get props => [groupChatId, name, scenario, scenarioTemplate, replyMode, activationStrategy, autoModeEnabled, allowSelfResponse];
}
