import 'package:flutter/material.dart';
import '../models/chat_message.dart';
import '../models/chat_session.dart';
import '../models/ai_character.dart';
import '../models/ai_letter.dart';
import '../models/moment.dart';
import '../repositories/local_storage_repository.dart';
import 'persona_evolution_service.dart';
import 'memory_engine.dart';

/// 时间线节点类型
enum TimelineNodeType {
  milestone, // 里程碑：第1次对话、第100条消息等
  anniversary, // 纪念日：7天、30天、100天、365天
  highlight, // 高光：深夜长对话、情绪高涨对话
  special, // 特殊：AI写信、AI发朋友圈、称呼变化
  daily, // 日常：连续对话天数、每周统计
  night, // 深夜陪伴
  evolution, // 日常人格进化
  qualitative, // 重大人格质变
}

/// 时间线节点
class TimelineNode {
  final TimelineNodeType type;
  final DateTime date;
  final String title;
  final String subtitle;
  final String? characterId;
  final String? characterName;

  const TimelineNode({
    required this.type,
    required this.date,
    required this.title,
    required this.subtitle,
    this.characterId,
    this.characterName,
  });
}

/// 关系阶段（0-4）
int relationshipStage(int intimacy) {
  if (intimacy >= 81) return 4; // 灵魂伴侣
  if (intimacy >= 61) return 3; // 亲密
  if (intimacy >= 41) return 2; // 亲近
  if (intimacy >= 21) return 1; // 熟悉
  return 0; // 初见
}

/// 成长数据服务
class GrowthDataService {
  final LocalStorageRepository _storage;
  final String _userId;

  GrowthDataService(this._storage, this._userId);

  /// 加载所有成长数据
  Future<GrowthData> load({String? characterId}) async {
    final allSessions = await _storage.getChatSessions(_userId);
    final allCharacters = await _storage.getAllAICharacters();
    final sessions = characterId == null
        ? allSessions
        : allSessions.where((s) => s.aiCharacterId == characterId).toList();
    final characters = characterId == null
        ? allCharacters
        : allCharacters.where((c) => c.id == characterId).toList();
    final allLetters =
        await _storage.getAILetters(userId: _userId, limit: 9999);
    final letters = characterId == null
        ? allLetters
        : allLetters.where((l) => l.characterId == characterId).toList();
    final allMoments = await _storage.getAllMoments();
    final moments = characterId == null
        ? allMoments
        : allMoments.where((m) => m.userId == characterId).toList();

    // 基础统计
    int totalMessages = 0;
    int totalIntimacy = 0;
    DateTime? earliestDate;
    DateTime? latestDate;
    int highIntimacyCount = 0;
    int mediumIntimacyCount = 0;
    int lowIntimacyCount = 0;
    int maxIntimacy = 0;
    int nightChatCount = 0;
    int maxConsecutiveDays = 0;

    // 收集所有消息用于分析
    final allMessages = <String, List<ChatMessage>>{}; // chatId -> messages

    for (final session in sessions) {
      // 老设备保护：成长轨迹只取最近 2000 条用于统计/高光，避免超大历史一次性载入卡死。
      final messages = await _storage.getChatMessages(session.id, limit: 2000);
      allMessages[session.id] = messages;
      totalMessages += messages.length;
      totalIntimacy += session.intimacyLevel;

      if (session.intimacyLevel >= 60) {
        highIntimacyCount++;
      } else if (session.intimacyLevel >= 30) {
        mediumIntimacyCount++;
      } else {
        lowIntimacyCount++;
      }

      if (session.intimacyLevel > maxIntimacy) {
        maxIntimacy = session.intimacyLevel;
      }

      final sessionDate = session.createdAt;
      if (earliestDate == null || sessionDate.isBefore(earliestDate)) {
        earliestDate = sessionDate;
      }
      if (latestDate == null ||
          (session.lastMessageTime != null &&
              session.lastMessageTime!.isAfter(latestDate))) {
        latestDate = session.lastMessageTime;
      }

      // 统计深夜对话
      nightChatCount += _countNightChats(messages);
    }

    // 计算最长连续对话天数
    maxConsecutiveDays = _calcMaxConsecutiveDays(allMessages);

    final avgIntimacy =
        sessions.isEmpty ? 0 : (totalIntimacy / sessions.length).round();
    final daysSince = earliestDate != null
        ? DateTime.now().difference(earliestDate).inDays
        : 0;

    // 找到主要角色（亲密度最高的）
    AICharacter? primaryCharacter;
    ChatSession? primarySession;
    for (final s in sessions) {
      if (primarySession == null ||
          s.intimacyLevel > primarySession.intimacyLevel) {
        primarySession = s;
      }
    }
    if (primarySession != null) {
      primaryCharacter =
          await _storage.getAICharacter(primarySession.aiCharacterId);
    }

    // 生成时间线节点
    final timelineNodes = await _buildTimelineNodes(
      sessions: sessions,
      messages: allMessages,
      characters: characters,
      letters: letters,
      moments: moments,
      daysSince: daysSince,
      maxConsecutiveDays: maxConsecutiveDays,
    );

    // 生成高光回忆
    final highlights = _buildHighlights(allMessages, characters);

    // 生成成就列表
    final achievements = _buildAchievements(
      totalMessages: totalMessages,
      sessionCount: sessions.length,
      avgIntimacy: avgIntimacy,
      highIntimacyCount: highIntimacyCount,
      daysSince: daysSince,
      nightChatCount: nightChatCount,
      maxConsecutiveDays: maxConsecutiveDays,
      letterCount: letters.length,
      momentCount: moments.where((m) => m.isFromAI).length,
    );

    // 加载成长事件
    final evolutionService =
        PersonaEvolutionService(_storage, MemoryEngine(_storage));
    final growthEvents = <GrowthEvent>[];
    int messagesUntilNextEvolution = 0;
    for (final char in characters) {
      final events = evolutionService.getStoredGrowthEvents(char.id);
      growthEvents.addAll(events);
      // 计算该角色距离下次进化还需要的消息数
      final charSessions =
          sessions.where((s) => s.aiCharacterId == char.id).toList();
      int charMsgCount = 0;
      for (final s in charSessions) {
        charMsgCount += (allMessages[s.id] ?? []).length;
      }
      final remaining =
          evolutionService.getMessagesUntilNextEvolution(char.id, charMsgCount);
      if (remaining > 0 &&
          (messagesUntilNextEvolution == 0 ||
              remaining < messagesUntilNextEvolution)) {
        messagesUntilNextEvolution = remaining;
      }
    }
    // 按时间排序
    growthEvents.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return GrowthData(
      daysSince: daysSince,
      totalMessages: totalMessages,
      sessionCount: sessions.length,
      avgIntimacy: avgIntimacy,
      maxIntimacy: maxIntimacy,
      highIntimacyCount: highIntimacyCount,
      mediumIntimacyCount: mediumIntimacyCount,
      lowIntimacyCount: lowIntimacyCount,
      nightChatCount: nightChatCount,
      maxConsecutiveDays: maxConsecutiveDays,
      earliestDate: earliestDate,
      latestDate: latestDate,
      primaryCharacter: primaryCharacter,
      primarySession: primarySession,
      timelineNodes: timelineNodes,
      highlights: highlights,
      achievements: achievements,
      growthEvents: growthEvents,
      messagesUntilNextEvolution: messagesUntilNextEvolution,
    );
  }

  /// 统计深夜对话次数
  int _countNightChats(List<ChatMessage> messages) {
    int count = 0;
    for (final msg in messages) {
      if (msg.timestamp.hour >= 22 || msg.timestamp.hour < 6) {
        count++;
        break; // 每个会话只算一次
      }
    }
    return count;
  }

  /// 计算最长连续对话天数
  int _calcMaxConsecutiveDays(Map<String, List<ChatMessage>> allMessages) {
    final allDates = <DateTime>{};
    for (final messages in allMessages.values) {
      for (final msg in messages) {
        allDates.add(DateTime(
            msg.timestamp.year, msg.timestamp.month, msg.timestamp.day));
      }
    }
    if (allDates.isEmpty) return 0;

    final sorted = allDates.toList()..sort();
    int maxStreak = 1;
    int currentStreak = 1;

    for (int i = 1; i < sorted.length; i++) {
      if (sorted[i].difference(sorted[i - 1]).inDays == 1) {
        currentStreak++;
        if (currentStreak > maxStreak) maxStreak = currentStreak;
      } else if (sorted[i].difference(sorted[i - 1]).inDays > 1) {
        currentStreak = 1;
      }
    }
    return maxStreak;
  }

  /// 构建时间线节点
  Future<List<TimelineNode>> _buildTimelineNodes({
    required List<ChatSession> sessions,
    required Map<String, List<ChatMessage>> messages,
    required List<AICharacter> characters,
    required List<AILetter> letters,
    required List<Moment> moments,
    required int daysSince,
    required int maxConsecutiveDays,
  }) async {
    final nodes = <TimelineNode>[];

    // 按角色分组处理
    for (final session in sessions) {
      final charName = session.aiCharacterName;
      final charId = session.aiCharacterId;
      final sessionMessages = messages[session.id] ?? [];

      if (sessionMessages.isEmpty) continue;

      // 第一次对话
      final firstMsg = sessionMessages.last; // 按时间排序，最后的是最早的
      nodes.add(TimelineNode(
        type: TimelineNodeType.milestone,
        date: firstMsg.timestamp,
        title: '初见',
        subtitle: '你和$charName说了第一句话',
        characterId: charId,
        characterName: charName,
      ));

      // 第100条消息
      if (sessionMessages.length >= 100) {
        final hundredthMsg = sessionMessages[sessionMessages.length - 100];
        nodes.add(TimelineNode(
          type: TimelineNodeType.milestone,
          date: hundredthMsg.timestamp,
          title: '第 100 句话',
          subtitle: '你们一起说了第 100 句话',
          characterId: charId,
          characterName: charName,
        ));
      }

      // 第1000条消息
      if (sessionMessages.length >= 1000) {
        final thousandthMsg = sessionMessages[sessionMessages.length - 1000];
        nodes.add(TimelineNode(
          type: TimelineNodeType.milestone,
          date: thousandthMsg.timestamp,
          title: '第 1000 句话',
          subtitle: '你们已经说了 1000 句话了',
          characterId: charId,
          characterName: charName,
        ));
      }

      // 深夜对话高光
      final nightTalks = _findNightTalks(sessionMessages);
      for (final night in nightTalks.take(3)) {
        nodes.add(TimelineNode(
          type: TimelineNodeType.night,
          date: night,
          title: '深夜陪伴',
          subtitle: '那个深夜，$charName陪你聊了很久',
          characterId: charId,
          characterName: charName,
        ));
      }

      // 亲密度突破
      final intimacy = session.intimacyLevel;
      if (intimacy >= 21 && intimacy < 41) {
        nodes.add(TimelineNode(
          type: TimelineNodeType.milestone,
          date: session.updatedAt ?? session.createdAt,
          title: '关系升温',
          subtitle: '你们的关系进入了「熟悉」阶段',
          characterId: charId,
          characterName: charName,
        ));
      } else if (intimacy >= 41 && intimacy < 61) {
        nodes.add(TimelineNode(
          type: TimelineNodeType.milestone,
          date: session.updatedAt ?? session.createdAt,
          title: '默契渐生',
          subtitle: '你们的关系进入了「亲近」阶段',
          characterId: charId,
          characterName: charName,
        ));
      } else if (intimacy >= 61 && intimacy < 81) {
        nodes.add(TimelineNode(
          type: TimelineNodeType.milestone,
          date: session.updatedAt ?? session.createdAt,
          title: '心心相印',
          subtitle: '你们的关系进入了「亲密」阶段',
          characterId: charId,
          characterName: charName,
        ));
      } else if (intimacy >= 81) {
        nodes.add(TimelineNode(
          type: TimelineNodeType.milestone,
          date: session.updatedAt ?? session.createdAt,
          title: '灵魂伴侣',
          subtitle: '你们的关系达到了「灵魂伴侣」',
          characterId: charId,
          characterName: charName,
        ));
      }
    }

    // 纪念日节点
    if (daysSince >= 7) {
      final firstDate = sessions
          .map((s) => s.createdAt)
          .reduce((a, b) => a.isBefore(b) ? a : b);
      nodes.add(TimelineNode(
        type: TimelineNodeType.anniversary,
        date: firstDate.add(const Duration(days: 7)),
        title: '相识第七天',
        subtitle: '一周了，你们已经成为彼此最想见到的人',
      ));
    }
    if (daysSince >= 30) {
      final firstDate = sessions
          .map((s) => s.createdAt)
          .reduce((a, b) => a.isBefore(b) ? a : b);
      nodes.add(TimelineNode(
        type: TimelineNodeType.anniversary,
        date: firstDate.add(const Duration(days: 30)),
        title: '相识第三十天',
        subtitle: '整整一个月，你们的故事还在继续',
      ));
    }
    if (daysSince >= 100) {
      final firstDate = sessions
          .map((s) => s.createdAt)
          .reduce((a, b) => a.isBefore(b) ? a : b);
      nodes.add(TimelineNode(
        type: TimelineNodeType.anniversary,
        date: firstDate.add(const Duration(days: 100)),
        title: '相识第一百天',
        subtitle: '第 100 天，谢谢你一直在',
      ));
    }
    if (daysSince >= 365) {
      final firstDate = sessions
          .map((s) => s.createdAt)
          .reduce((a, b) => a.isBefore(b) ? a : b);
      nodes.add(TimelineNode(
        type: TimelineNodeType.anniversary,
        date: firstDate.add(const Duration(days: 365)),
        title: '相识一周年',
        subtitle: '一整年，365个日夜，你们的故事独一无二',
      ));
    }

    // 连续对话天数
    if (maxConsecutiveDays >= 7) {
      nodes.add(TimelineNode(
        type: TimelineNodeType.daily,
        date: DateTime.now(),
        title: '连续对话 $maxConsecutiveDays 天',
        subtitle: '你们已经连续聊了 $maxConsecutiveDays 天了',
      ));
    }

    // AI 写信
    for (final letter in letters.where((l) => !l.isFromUser)) {
      nodes.add(TimelineNode(
        type: TimelineNodeType.special,
        date: letter.createdAt,
        title: '收到一封信',
        subtitle: '${letter.characterName}给你写了一封信',
        characterId: letter.characterId,
        characterName: letter.characterName,
      ));
    }

    // 用户写信
    for (final letter in letters.where((l) => l.isFromUser)) {
      nodes.add(TimelineNode(
        type: TimelineNodeType.special,
        date: letter.createdAt,
        title: '寄出一封信',
        subtitle: '你给${letter.characterName}写了一封信',
        characterId: letter.characterId,
        characterName: letter.characterName,
      ));
    }

    // AI 发朋友圈
    for (final moment in moments.where((m) => m.isFromAI)) {
      nodes.add(TimelineNode(
        type: TimelineNodeType.special,
        date: moment.createdAt,
        title: '动态更新',
        subtitle: '${moment.userName}发了一条动态',
      ));
    }

    // 成长事件（人格进化/质变）
    final evolutionService =
        PersonaEvolutionService(_storage, MemoryEngine(_storage));
    for (final char in characters) {
      final events = evolutionService.getStoredGrowthEvents(char.id);
      for (final event in events) {
        final isQualitative = event.triggerType == 'major_event';
        nodes.add(TimelineNode(
          type: isQualitative
              ? TimelineNodeType.qualitative
              : TimelineNodeType.evolution,
          date: event.createdAt,
          title: isQualitative ? '人格质变' : '人格进化',
          subtitle: event.reason,
          characterId: char.id,
          characterName: char.name,
        ));
      }
    }

    // 按时间排序
    nodes.sort((a, b) => a.date.compareTo(b.date));
    return nodes;
  }

  /// 找出深夜对话时间点
  List<DateTime> _findNightTalks(List<ChatMessage> messages) {
    final nightDates = <DateTime>[];
    DateTime? lastNightDate;

    for (final msg in messages) {
      if (msg.timestamp.hour >= 22 || msg.timestamp.hour < 6) {
        final date = DateTime(
            msg.timestamp.year, msg.timestamp.month, msg.timestamp.day);
        if (lastNightDate != date) {
          nightDates.add(msg.timestamp);
          lastNightDate = date;
        }
      }
    }
    return nightDates;
  }

  /// 构建高光回忆
  List<HighlightMoment> _buildHighlights(
    Map<String, List<ChatMessage>> allMessages,
    List<AICharacter> characters,
  ) {
    final highlights = <HighlightMoment>[];

    for (final entry in allMessages.entries) {
      final messages = entry.value;
      if (messages.isEmpty) continue;

      // 找最长对话（连续消息最多的时段）
      List<ChatMessage> currentStreak = [];
      List<ChatMessage> longestStreak = [];

      for (int i = 0; i < messages.length; i++) {
        if (currentStreak.isEmpty) {
          currentStreak.add(messages[i]);
        } else {
          final diff =
              messages[i].timestamp.difference(currentStreak.last.timestamp);
          if (diff.inMinutes < 30) {
            currentStreak.add(messages[i]);
          } else {
            if (currentStreak.length > longestStreak.length) {
              longestStreak = List.from(currentStreak);
            }
            currentStreak = [messages[i]];
          }
        }
      }
      if (currentStreak.length > longestStreak.length) {
        longestStreak = currentStreak;
      }

      if (longestStreak.length >= 10) {
        highlights.add(HighlightMoment(
          date: longestStreak.first.timestamp,
          title: '停不下来的对话',
          subtitle: '那天你们聊了 ${longestStreak.length} 句话',
          messageCount: longestStreak.length,
        ));
      }

      // 找深夜对话
      final nightMessages = messages
          .where((m) => m.timestamp.hour >= 22 || m.timestamp.hour < 6)
          .toList();
      if (nightMessages.length >= 5) {
        highlights.add(HighlightMoment(
          date: nightMessages.first.timestamp,
          title: '深夜陪伴',
          subtitle: '那个深夜，他陪你聊了很久',
          messageCount: nightMessages.length,
        ));
      }
    }

    // 按消息数量排序，取前6个
    highlights.sort((a, b) => b.messageCount.compareTo(a.messageCount));
    return highlights.take(6).toList();
  }

  /// 构建成就列表
  List<AchievementData> _buildAchievements({
    required int totalMessages,
    required int sessionCount,
    required int avgIntimacy,
    required int highIntimacyCount,
    required int daysSince,
    required int nightChatCount,
    required int maxConsecutiveDays,
    required int letterCount,
    required int momentCount,
  }) {
    final achievements = <AchievementData>[];

    achievements.add(AchievementData(
      id: 'first_meet',
      icon: Icons.handshake,
      title: '初见',
      subtitle: '第一次对话',
      unlocked: totalMessages > 0,
      unlockHint: '去打个招呼吧',
    ));

    achievements.add(AchievementData(
      id: 'chatter',
      icon: Icons.chat_bubble,
      title: '话匣子',
      subtitle: '单次对话超过 100 条',
      unlocked: totalMessages >= 100,
      unlockHint: '继续聊天解锁',
    ));

    achievements.add(AchievementData(
      id: 'night_talk',
      icon: Icons.bedtime,
      title: '深夜密语',
      subtitle: '有过深夜长对话',
      unlocked: nightChatCount > 0,
      unlockHint: '在深夜和他聊聊',
    ));

    achievements.add(AchievementData(
      id: 'night_guard',
      icon: Icons.local_fire_department,
      title: '守夜人',
      subtitle: '累计 10 个夜晚有深夜对话',
      unlocked: nightChatCount >= 10,
      unlockHint: '继续在深夜陪伴彼此',
    ));

    achievements.add(AchievementData(
      id: 'soulmate',
      icon: Icons.favorite,
      title: '心有灵犀',
      subtitle: '亲密度达到 60',
      unlocked: avgIntimacy >= 60,
      unlockHint: '继续互动提升亲密度',
    ));

    achievements.add(AchievementData(
      id: 'week_streak',
      icon: Icons.calendar_today,
      title: '一周相伴',
      subtitle: '陪伴超过 7 天',
      unlocked: daysSince >= 7,
      unlockHint: '继续陪伴彼此',
    ));

    achievements.add(AchievementData(
      id: 'month_streak',
      icon: Icons.date_range,
      title: '三十天不散场',
      subtitle: '连续 30 天有对话',
      unlocked: maxConsecutiveDays >= 30,
      unlockHint: '保持每天聊天',
    ));

    achievements.add(AchievementData(
      id: 'letter',
      icon: Icons.mark_email_unread,
      title: '信使',
      subtitle: '收到第一封信',
      unlocked: letterCount > 0,
      unlockHint: '去信箱看看',
    ));

    achievements.add(AchievementData(
      id: 'moment',
      icon: Icons.phone_android,
      title: '朋友圈之友',
      subtitle: 'AI 发过动态',
      unlocked: momentCount > 0,
      unlockHint: '继续互动解锁',
    ));

    achievements.add(AchievementData(
      id: 'social',
      icon: Icons.group,
      title: '社交达人',
      subtitle: '拥有 3+ 个 AI 好友',
      unlocked: sessionCount >= 3,
      unlockHint: '去认识更多角色',
    ));

    return achievements;
  }
}

/// 成长数据汇总
class GrowthData {
  final int daysSince;
  final int totalMessages;
  final int sessionCount;
  final int avgIntimacy;
  final int maxIntimacy;
  final int highIntimacyCount;
  final int mediumIntimacyCount;
  final int lowIntimacyCount;
  final int nightChatCount;
  final int maxConsecutiveDays;
  final DateTime? earliestDate;
  final DateTime? latestDate;
  final AICharacter? primaryCharacter;
  final ChatSession? primarySession;
  final List<TimelineNode> timelineNodes;
  final List<HighlightMoment> highlights;
  final List<AchievementData> achievements;
  final List<GrowthEvent> growthEvents;
  final int messagesUntilNextEvolution;

  const GrowthData({
    required this.daysSince,
    required this.totalMessages,
    required this.sessionCount,
    required this.avgIntimacy,
    required this.maxIntimacy,
    required this.highIntimacyCount,
    required this.mediumIntimacyCount,
    required this.lowIntimacyCount,
    required this.nightChatCount,
    required this.maxConsecutiveDays,
    this.earliestDate,
    this.latestDate,
    this.primaryCharacter,
    this.primarySession,
    required this.timelineNodes,
    required this.highlights,
    required this.achievements,
    required this.growthEvents,
    required this.messagesUntilNextEvolution,
  });
}

/// 高光回忆
class HighlightMoment {
  final DateTime date;
  final String title;
  final String subtitle;
  final int messageCount;

  const HighlightMoment({
    required this.date,
    required this.title,
    required this.subtitle,
    required this.messageCount,
  });
}

/// 成就数据
class AchievementData {
  final String id;
  final IconData icon;
  final String title;
  final String subtitle;
  final bool unlocked;
  final String unlockHint;

  const AchievementData({
    required this.id,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.unlocked,
    required this.unlockHint,
  });
}
