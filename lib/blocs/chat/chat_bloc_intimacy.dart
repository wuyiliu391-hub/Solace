import 'dart:math';
import 'package:intl/intl.dart';
import '../../models/chat_message.dart';
import '../../models/chat_session.dart';
import '../../models/ai_character.dart';
import '../../models/character_emotion.dart';
import '../../utils/sentiment_analyzer.dart';
import '../../config/business_rules.dart';

/// ChatBloc 的亲密度与情绪相关方法 mixin
mixin ChatBlocIntimacy {
  final Map<String, int> _dailyMsgCount = {};
  final Map<String, int> _hourlyMsgCount = {};
  final Map<String, List<int>> _msgLengths = {};

  /// 计算亲密度变化
  ({
    int newLevel,
    int dailyCount,
    String? date,
  }) calculateIntimacy({
    required ChatSession session,
    required String messageContent,
    required SentimentResult sentiment,
    required bool faModeActive,
  }) {
    final now = DateTime.now();
    final todayStr = DateFormat('yyyy-MM-dd').format(now);

    int level = session.intimacyLevel;
    int dailyCount = session.dailyIntimacyCount;
    String? lastDate = session.lastIntimacyDate;

    // 1. 新的一天重置每日计数
    if (lastDate != todayStr) {
      dailyCount = 0;
    }

    // 2. 超过 7 天未聊天才衰减
    if (session.lastMessageTime != null) {
      final hoursSince = now.difference(session.lastMessageTime!).inHours;
      if (hoursSince > IntimacyRules.decayAfterHours) {
        final weeks = (hoursSince ~/ 24) ~/ 7;
        final decay = weeks.clamp(0, IntimacyRules.maxDecaySteps);
        level = (level - decay).clamp(0, 100);
      }
    }

    // 3. 负面情绪不再跳过亲密度计算；反而带情绪的消息意味着交心
    //    FA 模式下额外跳过负面词误判保护
    //    （移除旧逻辑：负面情绪直接 return）

    // 4. 太短的消息不算有意义对话
    if (messageContent.trim().length < IntimacyRules.minMessageLength) {
      return (
        newLevel: level,
        dailyCount: dailyCount,
        date: lastDate ?? todayStr,
      );
    }

    // 5. 每日亲密度上限
    if (dailyCount >= IntimacyRules.dailyCap) {
      return (
        newLevel: level,
        dailyCount: dailyCount,
        date: lastDate ?? todayStr,
      );
    }

    // 6. 基础加分：高级别减速
    final key = '${session.id}_$todayStr';
    final msgsToday = (_dailyMsgCount[key] ?? 0) + 1;
    _dailyMsgCount[key] = msgsToday;

    int pointsToAdd = 0;
    final msgsPerPoint = IntimacyRules.msgsPerPoint(level);
    if ((msgsToday - 1) % msgsPerPoint == 0) {
      pointsToAdd += 1;
    }

    // 7. 深度对话额外加分：消息超过 50 字 +2
    if (messageContent.trim().length >= IntimacyRules.deepTalkThreshold) {
      pointsToAdd += IntimacyRules.deepTalkBonus;
    }

    // 8. 强情绪额外加分：正面或负面情绪很重 = 交心了 +1
    final absScore = sentiment.score.abs();
    if (absScore >= EmotionEngineRules.strongEmotionThreshold) {
      pointsToAdd += IntimacyRules.emotionalBonus;
    }

    if (pointsToAdd > 0) {
      level = (level + pointsToAdd).clamp(0, 100);
      dailyCount += 1; // 只计一次 dailyCount，不管加了多少分
    }

    return (newLevel: level, dailyCount: dailyCount, date: todayStr);
  }

  /// 判断 AI 是否应该自然跳过本次回复
  bool shouldSkipReply({
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

    // 短敷衍词→高概率跳过
    final trimmed = messageContent.trim();
    if (RegExp(
            r'^(嗯|哦|好的|知道了|ok|OK|哈哈|好吧|嗯嗯|哦哦|行|可以|对|是|没事)$')
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

    // 已连续回复几条→增加跳过概率
    skipProbability += consecutiveAiReplies * IntimacyRules.skipPerConsecutive;

    return Random().nextDouble() <
        skipProbability.clamp(0.0, IntimacyRules.skipCap);
  }

  /// 获取输入延迟（秒）
  int getTypingDelay(String personality) {
    return 2;
  }

  /// 计算原谅概率
  double calculateForgiveChance({
    required int pendingCount,
    required Duration blockDuration,
    required double emotionIntensity,
  }) {
    double chance = 0.25;

    // 用户坚持发消息越多越容易原谅
    chance += pendingCount * 0.05;

    // 时间推移增加原谅概率
    chance += blockDuration.inMinutes * 0.01;

    // 情绪强度降低时更容易原谅
    chance += (1.0 - emotionIntensity) * 0.2;

    // 超过10分钟大幅增加
    if (blockDuration.inMinutes > 10) {
      chance += 0.3;
    }

    return chance.clamp(0.0, 0.95);
  }

  /// 计算已读延迟（毫秒）
  int calculateReadDelay(EmotionType emotion, double intensity) {
    final baseMs = 800;
    if (emotion == EmotionType.angry) {
      return baseMs + (intensity * 5000).toInt(); // 生气时延迟更久
    }
    if (emotion == EmotionType.sad) {
      return baseMs + (intensity * 3000).toInt();
    }
    return baseMs;
  }

  /// 更新消息统计
  void updateMessageStats(String chatId, String content) {
    final now = DateTime.now();
    final hourKey = '${chatId}_${DateFormat('yyyy-MM-dd-HH').format(now)}';
    _hourlyMsgCount[hourKey] = (_hourlyMsgCount[hourKey] ?? 0) + 1;

    _msgLengths.putIfAbsent(chatId, () => []);
    _msgLengths[chatId]!.add(content.length);
    if (_msgLengths[chatId]!.length > 50) {
      _msgLengths[chatId]!.removeAt(0);
    }
  }

  /// 计算平均消息长度
  double avgMessageLength(String chatId) {
    final lengths = _msgLengths[chatId];
    if (lengths == null || lengths.isEmpty) return 0;
    return lengths.reduce((a, b) => a + b) / lengths.length;
  }
}
