import '../models/task_request.dart';
import 'task_queue.dart';

/// Lightweight behavior request generator for AI characters.
///
/// Characters use this to generate [TaskRequest] objects for social actions.
/// The requests are submitted to Core Hub for approval — characters have
/// no direct execution authority.
class ActionRequestBuilder {
  /// The character this builder belongs to.
  final String characterId;

  ActionRequestBuilder({required this.characterId});

  /// Generate a daily activity request (staying home, cooking, reading, etc.)
  TaskRequest generateDailyAction({
    required String activity,
    Map<String, dynamic> extra = const {},
  }) {
    return TaskRequest(
      sourceCharacterId: characterId,
      actionType: 'social_daily_activity',
      payload: {
        'activity': activity,
        ...extra,
      },
    );
  }

  /// Generate a visit request (going to another character's space)
  TaskRequest generateVisitAction({
    required String targetCharacterId,
    String purpose = 'casual_visit',
    Map<String, dynamic> extra = const {},
  }) {
    return TaskRequest(
      sourceCharacterId: characterId,
      actionType: 'social_visit',
      payload: {
        'targetCharacterId': targetCharacterId,
        'purpose': purpose,
        ...extra,
      },
    );
  }

  /// Generate a friend request to another character
  TaskRequest generateFriendRequest({
    required String targetCharacterId,
    String reason = '',
    Map<String, dynamic> extra = const {},
  }) {
    return TaskRequest(
      sourceCharacterId: characterId,
      actionType: 'social_friend_request',
      payload: {
        'targetCharacterId': targetCharacterId,
        'reason': reason,
        ...extra,
      },
    );
  }

  /// Generate a private chat message to another character
  TaskRequest generatePrivateChat({
    required String targetCharacterId,
    required String message,
    Map<String, dynamic> extra = const {},
  }) {
    return TaskRequest(
      sourceCharacterId: characterId,
      actionType: 'social_private_chat',
      payload: {
        'targetCharacterId': targetCharacterId,
        'message': message,
        ...extra,
      },
    );
  }

  /// Generate a moment/post action (publishing a social update)
  /// If [content] is null, the executor will use LLM to generate content
  /// based on the character's persona, memories, and evolution state.
  TaskRequest generateMomentAction({
    String? content,
    String visibility = 'public',
    List<String> imageUrls = const [],
    Map<String, dynamic> extra = const {},
  }) {
    return TaskRequest(
      sourceCharacterId: characterId,
      actionType: 'social_moment',
      payload: {
        if (content != null) 'content': content,
        'visibility': visibility,
        'imageUrls': imageUrls,
        ...extra,
      },
    );
  }

  /// Generate a moment comment action
  /// If [comment] is null, the executor will use LLM to generate a comment
  /// based on the moment content, commenter's persona, and relationship.
  TaskRequest generateMomentComment({
    required String momentId,
    required String targetCharacterId,
    String? comment,
    Map<String, dynamic> extra = const {},
  }) {
    return TaskRequest(
      sourceCharacterId: characterId,
      actionType: 'social_moment_comment',
      payload: {
        'momentId': momentId,
        'targetCharacterId': targetCharacterId,
        if (comment != null) 'comment': comment,
        ...extra,
      },
    );
  }

  /// Generate a moment like action
  TaskRequest generateMomentLike({
    required String momentId,
    required String targetCharacterId,
    Map<String, dynamic> extra = const {},
  }) {
    return TaskRequest(
      sourceCharacterId: characterId,
      actionType: 'social_moment_like',
      payload: {
        'momentId': momentId,
        'targetCharacterId': targetCharacterId,
        ...extra,
      },
    );
  }
}
