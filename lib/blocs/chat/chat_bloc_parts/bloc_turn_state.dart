// 轮次状态持久化（拆分生成，同库 part）
part of '../chat_bloc.dart';

mixin _BlocTurnState on Bloc<ChatEvent, ChatState>, ChatBlocUtils, ChatBlocIntimacy, _ChatBlocCore, _BlocCallsBase, _BlocAiBridge, _BlocMemoryIntimacy, _BlocPromptContext {
  Future<void> _persistTurnState({
    required String chatId,
    required AICharacter character,
    required String userId,
    required String userMessage,
    required String aiReply,
    required String sentimentLabel,
    required Emitter<ChatState> emit,
  }) async {
    final state = _completedTurnStates.remove(chatId) ?? _bridgeLastTurnState;
    final now = DateTime.now();
    var effectiveState =
        state?.isValid == true && state?.hasExplicitEmoji == true
            ? state!
            : AiTurnState.fallbackForTurn(
                userMessage: userMessage,
                aiReply: aiReply,
                sentimentLabel: sentimentLabel,
                previous: state,
              );
    String? previousEmoji;
    try {
      final raw = _storage.getString('turn_state_$chatId');
      if (raw != null && raw.isNotEmpty) {
        final data = jsonDecode(raw);
        if (data is Map) previousEmoji = data['emoji']?.toString().trim();
      }
    } catch (_) {
      // 状态历史损坏时不影响当前回合保存。
    }
    if (previousEmoji != null &&
        previousEmoji.isNotEmpty &&
        effectiveState.emoji == previousEmoji) {
      effectiveState = AiTurnState.fallbackForTurn(
        userMessage: userMessage,
        aiReply: aiReply,
        sentimentLabel: effectiveState.emotion,
        previous: effectiveState,
      ).copyWith(
        emotion: effectiveState.emotion,
        intensity: effectiveState.intensity,
        thought: effectiveState.thought,
      );
    }

    // 每轮均写入独立记录，不覆盖旧内心状态，也不把用户可见回复混入内部状态。
    await _storage.saveInnerThought({
      'id': _uuid.v4(),
      'characterId': character.id,
      'userId': userId,
      'content': effectiveState.thought,
      'type': 1,
      'emotionValence': 0.0,
      'emotionArousal': effectiveState.intensity,
      'isRead': 0,
      'createdAt': now.toIso8601String(),
    });
    await _storage.setString(
        'turn_state_$chatId',
        jsonEncode({
          'emoji': effectiveState.emoji,
          'emotion': effectiveState.emotion,
          'intensity': effectiveState.intensity,
          'thought': effectiveState.thought,
          'updatedAt': now.toIso8601String(),
        }));
    await _emotionEngine.applyTurnState(
      character: character,
      userId: userId,
      turnState: effectiveState,
    );
    emit(ChatTurnStateUpdated(
      chatId: chatId,
      emoji: effectiveState.emoji,
      emotion: effectiveState.emotion,
      intensity: effectiveState.intensity,
      thought: effectiveState.thought,
      updatedAt: now,
    ));
  }

}
