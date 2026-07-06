import '../../models/pure_ai_session.dart';
import '../../models/pure_ai_message.dart';

abstract class PureAIChatState {}

class PureAIInitial extends PureAIChatState {}

class PureAISessionsLoaded extends PureAIChatState {
  final List<PureAISession> sessions;
  PureAISessionsLoaded(this.sessions);
}

class PureAIMessagesLoaded extends PureAIChatState {
  final List<PureAIMessage> messages;
  PureAIMessagesLoaded(this.messages);
}

class PureAIMessageSending extends PureAIChatState {
  final List<PureAIMessage> messages;
  PureAIMessageSending(this.messages);
}

class PureAIStreaming extends PureAIChatState {
  final List<PureAIMessage> messages;
  final String streamingText;
  final String reasoning;
  PureAIStreaming(this.messages, this.streamingText, {this.reasoning = ''});
}

class PureAIError extends PureAIChatState {
  final String message;
  PureAIError(this.message);
}
