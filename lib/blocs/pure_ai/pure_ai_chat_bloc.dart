import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';
import '../../models/pure_ai_session.dart';
import '../../models/pure_ai_message.dart';
import '../../models/chat_message.dart';
import '../../repositories/local_storage_repository.dart';
import '../../services/pure_ai_service.dart';
import '../../utils/message_sanitizer.dart';
import 'pure_ai_chat_event.dart';
import 'pure_ai_chat_state.dart';

class PureAIChatBloc extends Bloc<PureAIChatEvent, PureAIChatState> {
  final LocalStorageRepository _storage;
  final PureAIService _aiService;
  final _uuid = const Uuid();

  PureAIChatBloc(this._storage, this._aiService) : super(PureAIInitial()) {
    on<PureAILoadSessions>(_onLoadSessions);
    on<PureAICreateSession>(_onCreateSession);
    on<PureAISendMessage>(_onSendMessage);
    on<PureAILoadMessages>(_onLoadMessages);
    on<PureAIDeleteSession>(_onDeleteSession);
  }

  Future<void> _onLoadSessions(
    PureAILoadSessions event,
    Emitter<PureAIChatState> emit,
  ) async {
    final sessions = await _storage.getPureAISessions(event.userId);
    emit(PureAISessionsLoaded(sessions));
  }

  Future<void> _onCreateSession(
    PureAICreateSession event,
    Emitter<PureAIChatState> emit,
  ) async {
    final session = PureAISession(
      id: _uuid.v4(),
      userId: event.userId,
      title: event.title ?? 'AI鍔╂墜',
      createdAt: DateTime.now(),
    );
    await _storage.createPureAISession(session);
    final sessions = await _storage.getPureAISessions(event.userId);
    emit(PureAISessionsLoaded(sessions));
  }

  Future<void> _onSendMessage(
    PureAISendMessage event,
    Emitter<PureAIChatState> emit,
  ) async {
    final now = DateTime.now();

    final cleanedContent = _stripSystemDirective(event.content);
    final isDirectiveOnly = cleanedContent.isEmpty;

    final userMsg = PureAIMessage(
      id: _uuid.v4(),
      sessionId: event.sessionId,
      senderId: event.userId,
      content: isDirectiveOnly ? event.content : cleanedContent,
      type: MessageType.text,
      status: MessageStatus.sent,
      createdAt: now,
      metadata: isDirectiveOnly
          ? {...(event.metadata ?? {}), 'isSystemDirective': true}
          : event.metadata,
    );

    try {
      await _storage.savePureAIMessage(userMsg);
    } catch (_) {
      emit(PureAIError('淇濆瓨鐢ㄦ埛娑堟伅澶辫触'));
      return;
    }

    var messages = await _storage.getPureAIMessages(event.sessionId);
    emit(PureAIMessagesLoaded(messages));

    emit(PureAIMessageSending(messages));

    try {
      String finalContent = '';

      await for (final chunk in _aiService.sendPureAIMessageStream(
        userMessage: event.content,
        chatHistory: messages,
        enableWebSearch: event.enableWebSearch,
      )) {
        finalContent = chunk.content;
        final streamText = MessageSanitizer.sanitizeStream(chunk.content);
        final streamReasoning =
            MessageSanitizer.sanitizeStream(chunk.reasoning);
        if (streamText.isNotEmpty || streamReasoning.isNotEmpty) {
          emit(PureAIStreaming(messages, streamText,
              reasoning: streamReasoning));
        }
      }

      var responseText = MessageSanitizer.sanitizeFinal(
          finalContent.trim().isNotEmpty
              ? finalContent
              : MessageSanitizer.failureFallbackText());
      if (MessageSanitizer.isLikelyUnreadableGibberish(responseText)) {
        responseText = MessageSanitizer.failureFallbackText();
      }
      final webSearchTrace =
          event.enableWebSearch ? _aiService.lastWebSearchTrace : null;

      final aiMsg = PureAIMessage(
        id: _uuid.v4(),
        sessionId: event.sessionId,
        senderId: 'ai',
        senderName: 'AI',
        content: responseText,
        type: MessageType.text,
        status: MessageStatus.sent,
        createdAt: DateTime.now(),
        metadata:
            webSearchTrace != null ? {'webSearchTrace': webSearchTrace} : null,
      );
      await _storage.savePureAIMessage(aiMsg);
    } catch (e) {
      debugPrint('PureAI鍥炲澶辫触: $e');
      final errorMsg = PureAIMessage(
        id: _uuid.v4(),
        sessionId: event.sessionId,
        senderId: 'ai',
        senderName: 'AI',
        content:
            '鎶辨瓑锛岀幇鍦ㄥ嚭浜嗙偣闂: ${e.toString().replaceAll('Exception: ', '')}',
        type: MessageType.text,
        status: MessageStatus.sent,
        createdAt: DateTime.now(),
      );
      await _storage.savePureAIMessage(errorMsg);
    }

    final allMessages = await _storage.getPureAIMessages(event.sessionId);
    emit(PureAIMessagesLoaded(allMessages));
  }

  Future<void> _onLoadMessages(
    PureAILoadMessages event,
    Emitter<PureAIChatState> emit,
  ) async {
    final messages = await _storage.getPureAIMessages(event.sessionId);
    emit(PureAIMessagesLoaded(messages));
  }

  Future<void> _onDeleteSession(
    PureAIDeleteSession event,
    Emitter<PureAIChatState> emit,
  ) async {
    await _storage.deletePureAISession(event.sessionId);
  }

  String _stripSystemDirective(String text) {
    final patterns = [
      RegExp(r'绯荤粺鎻愮ず[\[锛?]?.+?[\]锛?]?', caseSensitive: false),
      RegExp(r'绯荤粺鎻愮ず\s+.+', caseSensitive: false),
    ];
    String cleaned = text;
    for (final pattern in patterns) {
      cleaned = cleaned.replaceAll(pattern, '').trim();
    }
    return cleaned;
  }
}
