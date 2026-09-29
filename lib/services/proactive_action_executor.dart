import 'package:flutter/foundation.dart';

/// 主动动作类型 — 定义 AI 可以主动执行的内部动作
///
/// 这些不是设备工具调用，而是 AI 根据上下文自主判断后触发的内部行为。
/// 每种动作对应一种上下文注入或轻量级服务调用，用于增强 AI 回复。
enum ProactiveActionType {
  /// 情绪关怀 — 检测到用户情绪低落时，注入关怀上下文
  emotionCare,

  /// 亲密度提升 — 检测到亲密互动信号时，记录事件并注入温暖上下文
  intimacyBoost,

  /// 故事推进 — 检测到剧情关键节点时，更新故事状态
  storyProgression,

  /// 主动话题 — 检测到对话冷场时，注入话题建议上下文
  proactiveTopic,
}

/// 主动动作执行结果
class ProactiveActionResult {
  /// 执行的动作类型
  final ProactiveActionType actionType;

  /// 动作是否成功执行
  final bool success;

  /// 要注入到 AI 回复系统提示中的上下文文本
  /// 如果为 null，不注入额外上下文
  final String? contextInjection;

  /// 人类可读的执行日志
  final String log;

  const ProactiveActionResult({
    required this.actionType,
    this.success = true,
    this.contextInjection,
    required this.log,
  });

  /// 无需执行
  const ProactiveActionResult.skip(String reason)
      : actionType = ProactiveActionType.emotionCare,
        success = false,
        contextInjection = null,
        log = reason;
}

/// 主动动作执行器 — 将主动决策转化为实际的服务调用和上下文注入
class ProactiveActionExecutor {
  ProactiveActionExecutor({
    required this.storyStateService,
    required this.characterId,
    required this.userId,
  });

  final dynamic storyStateService; // StoryStateService
  final String characterId;
  final String userId;

  /// 执行主动动作
  Future<ProactiveActionResult> execute(
    ProactiveActionType actionType,
    Map<String, dynamic> args,
    String userMessage,
  ) async {
    switch (actionType) {
      case ProactiveActionType.emotionCare:
        return _executeEmotionCare(args, userMessage);
      case ProactiveActionType.intimacyBoost:
        return _executeIntimacyBoost(args, userMessage);
      case ProactiveActionType.storyProgression:
        return _executeStoryProgression(args, userMessage);
      case ProactiveActionType.proactiveTopic:
        return _executeProactiveTopic(args, userMessage);
    }
  }

  /// 情绪关怀：记录事件，注入关怀上下文
  Future<ProactiveActionResult> _executeEmotionCare(
    Map<String, dynamic> args,
    String userMessage,
  ) async {
    try {
      // 记录事件到故事状态
      await storyStateService.addRecentEvent(
        characterId: characterId,
        userId: userId,
        event: '用户表达了${args['type'] == 'comfort' ? '低落情绪' : '焦虑情绪'}',
      );

      // 注入关怀上下文
      final context = _buildCareContext(args, userMessage);

      return ProactiveActionResult(
        actionType: ProactiveActionType.emotionCare,
        contextInjection: context,
        log: '情绪关怀: ${args['type']}',
      );
    } catch (e) {
      debugPrint('[ProactiveAction] emotionCare 失败: $e');
      return ProactiveActionResult.skip('情绪关怀执行失败: $e');
    }
  }

  /// 亲密度提升：记录事件，注入温暖上下文
  Future<ProactiveActionResult> _executeIntimacyBoost(
    Map<String, dynamic> args,
    String userMessage,
  ) async {
    try {
      await storyStateService.addRecentEvent(
        characterId: characterId,
        userId: userId,
        event: '亲密度互动: ${args['type']}',
      );

      final context = _buildIntimacyContext(args, userMessage);

      return ProactiveActionResult(
        actionType: ProactiveActionType.intimacyBoost,
        contextInjection: context,
        log: '亲密度提升: ${args['type']}',
      );
    } catch (e) {
      debugPrint('[ProactiveAction] intimacyBoost 失败: $e');
      return ProactiveActionResult.skip('亲密度提升执行失败: $e');
    }
  }

  /// 故事推进：更新故事状态，注入推进上下文
  Future<ProactiveActionResult> _executeStoryProgression(
    Map<String, dynamic> args,
    String userMessage,
  ) async {
    try {
      await storyStateService.addRecentEvent(
        characterId: characterId,
        userId: userId,
        event: '故事节点检查: ${args['type']}',
      );

      final context = _buildStoryContext(args, userMessage);

      return ProactiveActionResult(
        actionType: ProactiveActionType.storyProgression,
        contextInjection: context,
        log: '故事推进: ${args['type']}',
      );
    } catch (e) {
      debugPrint('[ProactiveAction] storyProgression 失败: $e');
      return ProactiveActionResult.skip('故事推进执行失败: $e');
    }
  }

  /// 主动话题：注入话题建议上下文
  Future<ProactiveActionResult> _executeProactiveTopic(
    Map<String, dynamic> args,
    String userMessage,
  ) async {
    try {
      final context = _buildTopicContext(args, userMessage);

      return ProactiveActionResult(
        actionType: ProactiveActionType.proactiveTopic,
        contextInjection: context,
        log: '主动话题: ${args['type']}',
      );
    } catch (e) {
      debugPrint('[ProactiveAction] proactiveTopic 失败: $e');
      return ProactiveActionResult.skip('主动话题执行失败: $e');
    }
  }

  // ─── 上下文构建 ─────────────────────────────────────

  String _buildCareContext(Map<String, dynamic> args, String userMessage) {
    final type = args['type'] ?? 'comfort';
    if (type == 'comfort') {
      return '[系统提示] 用户当前情绪低落，请用温柔、关怀的语气回复。'
          '可以适当询问发生了什么，给予安慰和陪伴感。'
          '不要急于给建议，先倾听和共情。';
    } else {
      return '[系统提示] 用户当前感到焦虑/紧张，请用平静、安定的语气回复。'
          '可以帮助用户放松，适当引导深呼吸或转移注意力。'
          '不要否定用户的感受。';
    }
  }

  String _buildIntimacyContext(Map<String, dynamic> args, String userMessage) {
    final type = args['type'] ?? 'miss_response';
    if (type == 'miss_response') {
      return '[系统提示] 用户表达了对你的思念，请用温暖、亲密的语气回复。'
          '可以表达你也想念对方，回忆共同的美好时刻。';
    } else {
      return '[系统提示] 用户向你表白了，请根据你们当前的关系阶段做出回应。'
          '如果关系还不深，可以害羞地接受；如果关系已深，可以甜蜜地回应。';
    }
  }

  String _buildStoryContext(Map<String, dynamic> args, String userMessage) {
    return '[系统提示] 故事中存在未完成的约定或承诺，'
        '可以在回复中自然地提及或推进这些剧情线，'
        '但不要生硬地切换话题。';
  }

  String _buildTopicContext(Map<String, dynamic> args, String userMessage) {
    final type = args['type'] ?? 'topic_initiate';
    if (type == 'welcome_back') {
      return '[系统提示] 用户很久没来了，'
          '请用惊喜和开心的语气回归，表达想念之情，'
          '询问对方最近过得怎么样。';
    } else {
      return '[系统提示] 对话氛围比较平淡，'
          '请主动找一个轻松有趣的话题发起讨论，'
          '可以从天气、近况、兴趣爱好等方面切入。';
    }
  }
}
