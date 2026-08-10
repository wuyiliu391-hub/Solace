import '../models/story_state.dart';
import '../models/chat_message.dart';
import 'proactive_action_executor.dart';

/// 触发规则 — 定义在什么上下文下应该主动执行什么动作
class ProactiveTriggerRule {
  /// 规则唯一 ID
  final String id;

  /// 规则名称
  final String name;

  /// 规则描述
  final String description;

  /// 要执行的主动动作类型
  final ProactiveActionType actionType;

  /// 触发条件：情绪关键词列表（用户消息包含任一关键词则触发）
  final List<String> emotionKeywords;

  /// 触发条件：故事氛围匹配
  final List<StoryAtmosphere> atmosphereMatch;

  /// 触发条件：关系阶段匹配
  final List<RelationshipStage> stageMatch;

  /// 触发条件：未完成目标关键词
  final List<String> goalKeywords;

  /// 触发条件：最近事件关键词
  final List<String> eventKeywords;

  /// 触发条件：最近消息数量下限（用于检测冷场）
  final int? minRecentMessages;

  /// 触发条件：最近消息时间间隔下限（分钟，用于检测冷场）
  final int? silenceMinutes;

  /// 动作参数模板
  final Map<String, String> argsTemplate;

  /// 规则优先级（high/medium/low）
  final String priority;

  /// 冷却时间（分钟），覆盖全局默认值
  final int? cooldownMinutes;

  const ProactiveTriggerRule({
    required this.id,
    required this.name,
    required this.description,
    required this.actionType,
    this.emotionKeywords = const [],
    this.atmosphereMatch = const [],
    this.stageMatch = const [],
    this.goalKeywords = const [],
    this.eventKeywords = const [],
    this.minRecentMessages,
    this.silenceMinutes,
    this.argsTemplate = const {},
    this.priority = 'medium',
    this.cooldownMinutes,
  });

  /// 检查规则是否匹配当前上下文
  bool matches({
    required String userMessage,
    required StoryState storyState,
    required List<ChatMessage> recentMessages,
  }) {
    // 检查情绪关键词
    if (emotionKeywords.isNotEmpty) {
      final lowerMsg = userMessage.toLowerCase();
      final hasEmotionMatch = emotionKeywords.any(
        (kw) => lowerMsg.contains(kw.toLowerCase()),
      );
      if (!hasEmotionMatch) return false;
    }

    // 检查故事氛围
    if (atmosphereMatch.isNotEmpty) {
      if (!atmosphereMatch.contains(storyState.atmosphere)) return false;
    }

    // 检查关系阶段
    if (stageMatch.isNotEmpty) {
      if (!stageMatch.contains(storyState.relationshipStage)) return false;
    }

    // 检查未完成目标关键词
    if (goalKeywords.isNotEmpty) {
      final hasGoalMatch = goalKeywords.any(
        (kw) => storyState.pendingGoals.any(
          (goal) => goal.toLowerCase().contains(kw.toLowerCase()),
        ),
      );
      if (!hasGoalMatch) return false;
    }

    // 检查最近事件关键词
    if (eventKeywords.isNotEmpty) {
      final hasEventMatch = eventKeywords.any(
        (kw) => storyState.recentEvents.any(
          (event) => event.toLowerCase().contains(kw.toLowerCase()),
        ),
      );
      if (!hasEventMatch) return false;
    }

    // 检查最近消息数量（冷场检测需要足够的消息上下文）
    if (minRecentMessages != null) {
      if (recentMessages.length < minRecentMessages!) return false;
    }

    // 检查沉默时间间隔（冷场检测）
    if (silenceMinutes != null && recentMessages.length >= 2) {
      final lastUserMsg = recentMessages
          .where((m) => m.isUser)
          .toList();
      if (lastUserMsg.length >= 2) {
        final gap = lastUserMsg.last.timestamp
            .difference(lastUserMsg[lastUserMsg.length - 2].timestamp);
        if (gap.inMinutes < silenceMinutes!) return false;
      }
    }

    return true;
  }

  /// 构建动作参数（替换占位符）
  Map<String, String> buildArgs({
    required String characterName,
    required String userId,
    required String userMessage,
  }) {
    return argsTemplate.map(
      (key, value) => MapEntry(
        key,
        value
            .replaceAll('{character_name}', characterName)
            .replaceAll('{user_id}', userId)
            .replaceAll('{user_message}', userMessage),
      ),
    );
  }
}

/// 内置触发规则库
class ProactiveTriggerRules {
  ProactiveTriggerRules._();

  /// 所有内置规则
  static final List<ProactiveTriggerRule> builtinRules = [
    // ── 情绪关怀规则 ──
    ProactiveTriggerRule(
      id: 'emotion_care_sad',
      name: '情绪低落关怀',
      description: '用户表达悲伤/低落时，注入关怀上下文',
      actionType: ProactiveActionType.emotionCare,
      emotionKeywords: [
        '难过', '伤心', '悲伤', '哭', '痛苦', '失望', '沮丧',
        '心痛', '不开心', '郁闷', '低落', '消沉', '崩溃',
        'sad', 'cry', 'pain', 'hurt', 'upset', 'depressed',
      ],
      argsTemplate: {
        'type': 'comfort',
        'trigger': '用户表达了低落情绪',
      },
      priority: 'high',
      cooldownMinutes: 10,
    ),

    ProactiveTriggerRule(
      id: 'emotion_care_anxiety',
      name: '焦虑安抚',
      description: '用户表达焦虑/压力时，注入安抚上下文',
      actionType: ProactiveActionType.emotionCare,
      emotionKeywords: [
        '焦虑', '紧张', '压力大', '担心', '害怕', '恐惧',
        '失眠', '睡不着', 'anxiety', 'stress', 'worried', 'afraid',
      ],
      argsTemplate: {
        'type': 'calm',
        'trigger': '用户表达了焦虑情绪',
      },
      priority: 'high',
      cooldownMinutes: 10,
    ),

    // ── 亲密度提升规则 ──
    ProactiveTriggerRule(
      id: 'intimacy_miss',
      name: '思念回应',
      description: '用户表达思念时，注入温暖上下文',
      actionType: ProactiveActionType.intimacyBoost,
      emotionKeywords: [
        '想你', '想念', '思念', '好久不见',
        'miss you',
      ],
      stageMatch: [
        RelationshipStage.intimate,
        RelationshipStage.passionate,
        RelationshipStage.stable,
      ],
      argsTemplate: {
        'type': 'miss_response',
        'trigger': '用户表达了思念',
      },
      priority: 'medium',
    ),

    ProactiveTriggerRule(
      id: 'intimacy_love_confession',
      name: '告白回应',
      description: '用户表白时，注入亲密互动上下文',
      actionType: ProactiveActionType.intimacyBoost,
      emotionKeywords: [
        '喜欢你', '爱你', '我爱你', '在一起', '表白',
        'love you', 'i love you',
      ],
      argsTemplate: {
        'type': 'confession_response',
        'trigger': '用户向角色表白',
      },
      priority: 'high',
      cooldownMinutes: 30,
    ),

    // ── 故事推进规则 ──
    ProactiveTriggerRule(
      id: 'story_milestone',
      name: '里程碑触发',
      description: '故事中存在未完成约定时，注入推进上下文',
      actionType: ProactiveActionType.storyProgression,
      eventKeywords: ['约定', '承诺', '目标', '计划'],
      argsTemplate: {
        'type': 'milestone_check',
        'trigger': '故事中存在未完成的约定/承诺',
      },
      priority: 'medium',
      cooldownMinutes: 60,
    ),

    // ── 主动话题规则 ──
    ProactiveTriggerRule(
      id: 'engagement_greeting',
      name: '回归问候',
      description: '用户回归对话时，注入惊喜问候上下文',
      actionType: ProactiveActionType.proactiveTopic,
      eventKeywords: ['好久不见', '回来了', '在吗'],
      argsTemplate: {
        'type': 'welcome_back',
        'trigger': '用户回归对话',
      },
      priority: 'medium',
      cooldownMinutes: 30,
    ),

    ProactiveTriggerRule(
      id: 'engagement_silence',
      name: '冷场打破',
      description: '对话沉默超过 5 分钟时，注入话题建议上下文',
      actionType: ProactiveActionType.proactiveTopic,
      minRecentMessages: 4, // 至少有 4 条消息才判断冷场
      silenceMinutes: 5, // 最近两条用户消息间隔 > 5 分钟
      argsTemplate: {
        'type': 'topic_initiate',
        'trigger': '对话陷入沉默，主动发起话题',
      },
      priority: 'low',
      cooldownMinutes: 15,
    ),
  ];

  /// 根据上下文匹配所有触发的规则（按优先级排序）
  static List<ProactiveTriggerRule> matchRules({
    required String userMessage,
    required StoryState storyState,
    required List<ChatMessage> recentMessages,
  }) {
    final matched = builtinRules
        .where((rule) => rule.matches(
              userMessage: userMessage,
              storyState: storyState,
              recentMessages: recentMessages,
            ))
        .toList();

    // 按优先级排序：high > medium > low
    matched.sort((a, b) {
      const order = {'high': 0, 'medium': 1, 'low': 2};
      return (order[a.priority] ?? 2).compareTo(order[b.priority] ?? 2);
    });

    return matched;
  }

  /// 获取指定 ID 的规则
  static ProactiveTriggerRule? getRuleById(String id) {
    try {
      return builtinRules.firstWhere((r) => r.id == id);
    } catch (_) {
      return null;
    }
  }
}
