import 'package:flutter_test/flutter_test.dart';
import 'package:solace/models/story_state.dart';
import 'package:solace/models/chat_message.dart';
import 'package:solace/services/proactive_trigger_rules.dart';
import 'package:solace/services/proactive_rate_limiter.dart';
import 'package:solace/services/proactive_action_executor.dart';

/// 测试用的 ChatMessage 工厂
ChatMessage fakeMessage({required bool isUser, DateTime? timestamp}) {
  return ChatMessage(
    id: 'test_${DateTime.now().millisecondsSinceEpoch}',
    senderId: isUser ? 'user1' : 'ai_char1',
    isUser: isUser,
    content: isUser ? 'user message' : 'ai reply',
    timestamp: timestamp ?? DateTime.now(),
  );
}

void main() {
  group('ProactiveTriggerRules', () {
    test('情绪关键词匹配 - 悲伤', () {
      final story = StoryState.initial();
      final messages = [
        fakeMessage(isUser: true),
        fakeMessage(isUser: false),
      ];

      final matched = ProactiveTriggerRules.matchRules(
        userMessage: '我今天好难过',
        storyState: story,
        recentMessages: messages,
      );

      expect(matched, isNotEmpty);
      expect(matched.first.id, 'emotion_care_sad');
      expect(matched.first.actionType, ProactiveActionType.emotionCare);
    });

    test('情绪关键词匹配 - 焦虑', () {
      final story = StoryState.initial();
      final messages = [
        fakeMessage(isUser: true),
      ];

      final matched = ProactiveTriggerRules.matchRules(
        userMessage: '我很焦虑，睡不着',
        storyState: story,
        recentMessages: messages,
      );

      final anxietyRule =
          matched.where((r) => r.id == 'emotion_care_anxiety').toList();
      expect(anxietyRule, isNotEmpty);
    });

    test('思念匹配需要关系阶段', () {
      // 初识阶段不应匹配思念规则
      final acquaintanceStory = StoryState(
        relationshipStage: RelationshipStage.acquaintance,
        updatedAt: DateTime.now(),
      );
      final messages = [
        fakeMessage(isUser: true),
      ];

      final matched = ProactiveTriggerRules.matchRules(
        userMessage: '我好想你',
        storyState: acquaintanceStory,
        recentMessages: messages,
      );

      final missRule = matched.where((r) => r.id == 'intimacy_miss').toList();
      expect(missRule, isEmpty);
    });

    test('思念匹配 - 亲密阶段应匹配', () {
      final intimateStory = StoryState(
        relationshipStage: RelationshipStage.intimate,
        updatedAt: DateTime.now(),
      );
      final messages = [
        fakeMessage(isUser: true),
      ];

      final matched = ProactiveTriggerRules.matchRules(
        userMessage: '我好想你',
        storyState: intimateStory,
        recentMessages: messages,
      );

      final missRule = matched.where((r) => r.id == 'intimacy_miss').toList();
      expect(missRule, isNotEmpty);
    });

    test('告白匹配 - 任何关系阶段', () {
      final story = StoryState.initial();
      final messages = [
        fakeMessage(isUser: true),
      ];

      final matched = ProactiveTriggerRules.matchRules(
        userMessage: '我喜欢你',
        storyState: story,
        recentMessages: messages,
      );

      final confessionRule =
          matched.where((r) => r.id == 'intimacy_love_confession').toList();
      expect(confessionRule, isNotEmpty);
      expect(confessionRule.first.priority, 'high');
    });

    test('冷场打破需要最少消息数', () {
      final story = StoryState.initial();
      // 只有 2 条消息，不够 minRecentMessages=4
      final messages = [
        fakeMessage(isUser: true),
        fakeMessage(isUser: false),
      ];

      final matched = ProactiveTriggerRules.matchRules(
        userMessage: '你好',
        storyState: story,
        recentMessages: messages,
      );

      final silenceRule =
          matched.where((r) => r.id == 'engagement_silence').toList();
      expect(silenceRule, isEmpty);
    });

    test('冷场打破需要时间间隔', () {
      final story = StoryState.initial();
      // 6 条消息，但时间间隔不足 5 分钟
      final now = DateTime.now();
      final messages = List.generate(
        6,
        (i) => fakeMessage(
          isUser: i % 2 == 0,
          timestamp: now,
        ),
      );

      final matched = ProactiveTriggerRules.matchRules(
        userMessage: '你好',
        storyState: story,
        recentMessages: messages,
      );

      final silenceRule =
          matched.where((r) => r.id == 'engagement_silence').toList();
      // 时间间隔不足，不应匹配
      expect(silenceRule, isEmpty);
    });

    test('规则按优先级排序', () {
      final story = StoryState.initial();
      final messages = [
        fakeMessage(isUser: true),
      ];

      final matched = ProactiveTriggerRules.matchRules(
        userMessage: '我爱你，但我好难过',
        storyState: story,
        recentMessages: messages,
      );

      // high 优先级应在 medium 之前
      if (matched.length >= 2) {
        final priorities = matched.map((r) => r.priority).toList();
        final highIndex = priorities.indexOf('high');
        final mediumIndex = priorities.indexOf('medium');
        if (highIndex >= 0 && mediumIndex >= 0) {
          expect(highIndex, lessThan(mediumIndex));
        }
      }
    });

    test('规则参数模板替换', () {
      final rule = ProactiveTriggerRules.getRuleById('emotion_care_sad');
      expect(rule, isNotNull);

      final args = rule!.buildArgs(
        characterName: '小雪',
        userId: 'user123',
        userMessage: '我好难过',
      );

      expect(args['type'], 'comfort');
      expect(args['trigger'], '用户表达了低落情绪');
    });
  });

  group('ProactiveRateLimiter', () {
    test('同一工具在冷却期内不重复调用', () {
      final limiter = ProactiveRateLimiter();

      expect(limiter.canCallTool('test_tool'), isTrue);
      limiter.recordCall('test_tool');

      // 立即再调用应被拒绝
      expect(limiter.canCallTool('test_tool'), isFalse);
    });

    test('不同工具互不影响', () {
      final limiter = ProactiveRateLimiter();

      limiter.recordCall('tool_a');
      // tool_b 不受影响
      expect(limiter.canCallTool('tool_b'), isTrue);
    });

    test('全局频率限制', () {
      final limiter = ProactiveRateLimiter();

      // 连续调用达到上限
      for (var i = 0; i < ProactiveRateLimiter.maxCallsPerWindow; i++) {
        limiter.recordCall('tool_$i');
      }

      // 下一个调用应被全局限制拒绝
      expect(limiter.canCallTool('another_tool'), isFalse);
    });

    test('自定义冷却时间', () {
      final limiter = ProactiveRateLimiter();

      limiter.recordCall('test_tool');
      // 1 分钟冷却不应影响（默认 5 分钟）
      expect(
        limiter.canCallTool('test_tool', cooldownMinutes: 1),
        isFalse,
      );
    });

    test('getStats 返回正确统计', () {
      final limiter = ProactiveRateLimiter();
      limiter.recordCall('tool_a');

      final stats = limiter.getStats();
      expect(stats['globalCallsInWindow'], 1);
      expect(stats['toolCooldowns'], contains('tool_a'));
    });

    test('reset 清除所有记录', () {
      final limiter = ProactiveRateLimiter();
      limiter.recordCall('tool_a');
      limiter.reset();

      expect(limiter.canCallTool('tool_a'), isTrue);
    });
  });

  group('ProactiveActionExecutor', () {
    late FakeStoryStateService storyService;
    late ProactiveActionExecutor executor;

    setUp(() {
      storyService = FakeStoryStateService();
      executor = ProactiveActionExecutor(
        storyStateService: storyService,
        characterId: 'char1',
        userId: 'user1',
      );
    });

    test('emotionCare 执行成功', () async {
      final result = await executor.execute(
        ProactiveActionType.emotionCare,
        {'type': 'comfort'},
        '我好难过',
      );

      expect(result.success, isTrue);
      expect(result.actionType, ProactiveActionType.emotionCare);
      expect(result.contextInjection, contains('温柔'));
      expect(storyService.eventsAdded, contains('用户表达了低落情绪'));
    });

    test('intimacyBoost 执行成功', () async {
      final result = await executor.execute(
        ProactiveActionType.intimacyBoost,
        {'type': 'miss_response'},
        '我好想你',
      );

      expect(result.success, isTrue);
      expect(result.contextInjection, contains('温暖'));
      expect(storyService.eventsAdded, contains('亲密度互动: miss_response'));
    });

    test('proactiveTopic 执行成功', () async {
      final result = await executor.execute(
        ProactiveActionType.proactiveTopic,
        {'type': 'topic_initiate'},
        '...',
      );

      expect(result.success, isTrue);
      expect(result.contextInjection, contains('轻松'));
    });

    test('proactiveTopic welcome_back', () async {
      final result = await executor.execute(
        ProactiveActionType.proactiveTopic,
        {'type': 'welcome_back'},
        '我回来了',
      );

      expect(result.success, isTrue);
      expect(result.contextInjection, contains('惊喜'));
    });
  });
}

/// 测试用的 StoryStateService 替身
class FakeStoryStateService {
  final List<String> eventsAdded = [];

  dynamic get storyState => null;

  Future<void> addRecentEvent({
    required String characterId,
    required String userId,
    required String event,
  }) async {
    eventsAdded.add(event);
  }

  Future<StoryState> getStoryState({
    required String characterId,
    required String userId,
  }) async {
    return StoryState.initial();
  }

  Future<Map<String, dynamic>> getStoryContext({
    required String characterId,
    required String userId,
  }) async {
    return {
      'relationshipStage': 'undefined',
      'atmosphere': 'undefined',
      'progress': 0.0,
      'pendingGoals': <String>[],
      'recentEvents': <String>[],
    };
  }
}
