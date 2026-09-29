// 状态统计与延迟（拆分生成，同库 part）
part of '../chat_bloc.dart';

mixin _BlocStatusStats on Bloc<ChatEvent, ChatState>, ChatBlocUtils, ChatBlocIntimacy, _ChatBlocCore, _BlocCallsBase, _BlocAiBridge, _BlocMemoryIntimacy, _BlocPromptContext, _BlocTurnState, _BlocBtAgent, _BlocNovel, _BlocMessagesLoad {
  void _updateAIStatus(AICharacter character, {required String chatId}) {
    final statusText = _bridgeLastParsedStatus;

    bool isOnline = true;
    String? status;
    if (statusText == null || statusText.trim().isEmpty) {
      // Providers may omit structured status tags. Still rotate a real
      // activity label so the status bar does not remain permanently stale.
      AIStatusService(_storage).refreshActivityStatus(
        chatId: chatId,
        characterId: character.id,
      );
      return;
    }
    final lower = statusText.toLowerCase();
    if (lower.contains('离线') || lower.startsWith('offline')) {
      isOnline = false;
      status = statusText
          .replaceAll(
              RegExp(r'^(离线|offline)\s*[路\s]*', caseSensitive: false), '')
          .trim();
      if (status.isEmpty) status = '离线';
    } else {
      status = statusText
          .replaceAll(
              RegExp(r'^(在线|online)\s*[路\s]*', caseSensitive: false), '')
          .trim();
      if (status.isEmpty) status = null;
    }

    AIStatusService(_storage).updateCharacterStatus(
      characterId: character.id,
      isOnline: isOnline,
      currentStatus: status,
    );
  }


  /// 判断 AI 是否应该自然跳过本次回复（不说一句回一句）
  bool _shouldSkipReply({
    required String personality,
    required int intimacyLevel,
    required String messageContent,
    required int consecutiveAiReplies,
    required MessageType messageType,
  }) {
    // 从来没回过的一定回
    if (consecutiveAiReplies == 0) return false;

    // 用户发图片→几乎总是回复
    if (messageType == MessageType.image) return false;

    // 带问号的问题→必须回
    if (messageContent.contains('?') || messageContent.contains('？')) {
      return false;
    }

    // 连续跳过不超过上限
    if (consecutiveAiReplies >= IntimacyRules.maxConsecutiveSkips) return false;

    double skipProbability = 0.0;

    // 短敷衍词→高概率跳过（如"嗯""哦""好的""哈哈"）
    final trimmed = messageContent.trim();
    if (RegExp(r'^(嗯|哦|好的|知道了|ok|OK|哈哈|好吧|嗯嗯|哦哦|行|可以|对|是|没事)$')
        .hasMatch(trimmed)) {
      skipProbability += IntimacyRules.skipFromShortReply;
    }

    // 极短消息（1-2 字）→ 中概率跳过
    if (trimmed.length <= 2) {
      skipProbability += IntimacyRules.skipFromVeryShort;
    }

    // 性格因素
    final p = personality.toLowerCase();
    if (p.contains('活泼') || p.contains('热情') || p.contains('开朗')) {
      skipProbability += IntimacyRules.skipFromPersonalityBouncy;
    } else if (p.contains('高冷') || p.contains('冷淡')) {
      skipProbability += IntimacyRules.skipFromPersonalityCool;
    } else if (p.contains('温柔') || p.contains('体贴')) {
      skipProbability += IntimacyRules.skipFromPersonalityWarm;
    }

    // 亲密度高→自在沉默更自然
    if (intimacyLevel > IntimacyRules.intimacySkipThreshold) {
      skipProbability += IntimacyRules.skipFromHighIntimacy;
    }

    // 已连续回复 AI 几条 → 增加跳过概率
    skipProbability += consecutiveAiReplies * IntimacyRules.skipPerConsecutive;

    return Random().nextDouble() <
        skipProbability.clamp(0.0, IntimacyRules.skipCap);
  }


  /// 应用回复延迟（根据 replyMode 和角色性格）
  Future<void> _applyReplyDelay({
    required AICharacter? character,
    required ReplyMode replyMode,
    required Emitter<ChatState> emit,
    required List<ChatMessage> messages,
    required String characterName,
    int? msgLength,
    SentimentResult? sentiment,
  }) async {
    if (replyMode == ReplyMode.instant) {
      emit(ChatAITyping(messages, characterName));
      await Future.delayed(AppDurations.instantReplyDelay);
    } else if (replyMode == ReplyMode.delayed) {
      final delay =
          (character?.interactionConfig?.replyDelaySeconds ?? 5).clamp(1, 8);
      emit(ChatAITyping(messages, characterName));
      await Future.delayed(Duration(seconds: delay));
    } else {
      // 轻量拟人延迟（与 _onSendMessage 一致，上限约 1.8s）
      final random = Random();
      final len = msgLength ?? 10;
      int baseMs = 200 + (len * 18).clamp(0, 900);

      double emotionMultiplier = 1.0;
      if (sentiment != null) {
        if (sentiment.type == SentimentType.veryNegative ||
            sentiment.type == SentimentType.negative) {
          emotionMultiplier = 1.2 + random.nextDouble() * 0.4;
        } else if (sentiment.type == SentimentType.veryPositive ||
            sentiment.type == SentimentType.positive) {
          emotionMultiplier = 0.7 + random.nextDouble() * 0.25;
        } else {
          emotionMultiplier = 0.85 + random.nextDouble() * 0.35;
        }
      }
      if (random.nextDouble() < 0.12) emotionMultiplier = 0.45;

      final totalMs = (baseMs * emotionMultiplier)
          .toInt()
          .clamp(AppDurations.typingDelayMinMs, AppDurations.typingDelayMaxMs);
      emit(ChatAITyping(messages, characterName));
      await Future.delayed(Duration(milliseconds: totalMs));
    }
  }


  // 行为风控统计更新
  void _updateMessageStats(String chatId, String content) {
    final now = DateTime.now();
    final todayKey =
        '${chatId}_${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final hourKey =
        '${chatId}_${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}_${now.hour}';

    _dailyMsgCount[todayKey] = (_dailyMsgCount[todayKey] ?? 0) + 1;
    _hourlyMsgCount[hourKey] = (_hourlyMsgCount[hourKey] ?? 0) + 1;

    _msgLengths[chatId] = [...(_msgLengths[chatId] ?? []), content.length];
    if ((_msgLengths[chatId]?.length ?? 0) > 50) {
      _msgLengths[chatId] =
          _msgLengths[chatId]!.sublist(_msgLengths[chatId]!.length - 50);
    }

    // 清理旧数据（保留最近 N 天）
    final cutoff = now.subtract(const Duration(days: 3));
    _dailyMsgCount.removeWhere((key, _) {
      try {
        final parts = key.split('_');
        if (parts.length < 2) return false;
        final date = DateTime.parse(parts[1]);
        return date.isBefore(cutoff);
      } catch (_) {
        return false;
      }
    });
    _hourlyMsgCount.removeWhere((key, _) {
      try {
        final parts = key.split('_');
        if (parts.length < 3) return false;
        final dateStr = parts[1];
        final date = DateTime.parse(dateStr);
        return date.isBefore(cutoff);
      } catch (_) {
        return false;
      }
    });
  }

}
