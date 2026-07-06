abstract class PureAIChatEvent {}

class PureAILoadSessions extends PureAIChatEvent {
  final String userId;
  PureAILoadSessions(this.userId);
}

class PureAICreateSession extends PureAIChatEvent {
  final String userId;
  final String? title;
  PureAICreateSession(this.userId, {this.title});
}

class PureAISendMessage extends PureAIChatEvent {
  final String sessionId;
  final String userId;
  final String content;
  final Map<String, dynamic>? metadata;
  final bool enableWebSearch;
  PureAISendMessage({
    required this.sessionId,
    required this.userId,
    required this.content,
    this.metadata,
    this.enableWebSearch = false,
  });
}

class PureAILoadMessages extends PureAIChatEvent {
  final String sessionId;
  PureAILoadMessages(this.sessionId);
}

class PureAIDeleteSession extends PureAIChatEvent {
  final String sessionId;
  PureAIDeleteSession(this.sessionId);
}

class PureAISendImageMessage extends PureAIChatEvent {
  final String sessionId;
  final String userId;
  final String? caption;
  final String imagePath;
  PureAISendImageMessage({
    required this.sessionId,
    required this.userId,
    this.caption,
    required this.imagePath,
  });
}
