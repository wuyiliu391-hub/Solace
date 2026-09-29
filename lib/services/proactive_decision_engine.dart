import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/ai_character.dart';
import '../models/chat_message.dart';
import '../services/llm_service.dart';
import '../services/story_state_service.dart';
import '../services/proactive_rate_limiter.dart';
import '../services/proactive_action_executor.dart';
import '../services/proactive_trigger_rules.dart';
import '../services/prompt/proactive_decision_prompt.dart';

/// 主动决策结果
class ProactiveDecisionResult {
  /// 是否需要执行主动动作
  final bool shouldAct;

  /// 要执行的主动动作类型
  final ProactiveActionType? actionType;

  /// 动作参数
  final Map<String, String> actionArgs;

  /// 决策原因
  final String reason;

  /// 优先级（high/medium/low）
  final String priority;

  /// 置信度（0.0-1.0）
  final double confidence;

  /// 是否被限频拦截
  final bool wasRateLimited;

  const ProactiveDecisionResult({
    required this.shouldAct,
    this.actionType,
    this.actionArgs = const {},
    required this.reason,
    this.priority = 'low',
    this.confidence = 0.0,
    this.wasRateLimited = false,
  });

  /// 无需执行
  const ProactiveDecisionResult.noAction(this.reason)
      : shouldAct = false,
        actionType = null,
        actionArgs = const {},
        priority = 'low',
        confidence = 0.0,
        wasRateLimited = false;

  /// 被限频拦截
  const ProactiveDecisionResult.rateLimited(this.reason)
      : shouldAct = false,
        actionType = null,
        actionArgs = const {},
        priority = 'low',
        confidence = 0.0,
        wasRateLimited = true;
}

/// 主动决策引擎 — 在每次 AI 回复前评估是否需要主动执行动作
///
/// 决策流程：
/// 1. 规则快路径（零 LLM 开销）
/// 2. LLM 决策（结构化 JSON）
/// 3. 限频检查
/// 4. 返回决策结果（由 ChatBloc 执行实际动作）
class ProactiveDecisionEngine {
  ProactiveDecisionEngine();

  final ProactiveRateLimiter _rateLimiter = ProactiveRateLimiter();

  /// 是否启用主动决策（默认关闭，用户可在设置中开启）
  bool enabled = false;

  /// 敏感度等级：low / medium / high
  String sensitivity = 'medium';

  /// 决策日志（用于调试）
  final List<Map<String, dynamic>> _decisionLog = [];
  static const int _maxLogSize = 50;

  /// 最近的决策记录
  List<Map<String, dynamic>> get decisionLog =>
      List.unmodifiable(_decisionLog);

  /// 执行主动决策
  Future<ProactiveDecisionResult> evaluate({
    required AICharacter character,
    required String userId,
    required List<ChatMessage> recentMessages,
    required StoryStateService storyStateService,
    required LlmService llm,
  }) async {
    if (!enabled) {
      return const ProactiveDecisionResult.noAction('主动决策未启用');
    }

    if (recentMessages.isEmpty) {
      return const ProactiveDecisionResult.noAction('无消息上下文');
    }

    try {
      // 0. 快速路径：触发规则匹配（零 LLM 开销）
      final storyState = await storyStateService.getStoryState(
        characterId: character.id,
        userId: userId,
      );
      final lastUserMsg =
          recentMessages.isNotEmpty ? recentMessages.last : null;
      if (lastUserMsg != null && lastUserMsg.isUser) {
        final matchedRules = ProactiveTriggerRules.matchRules(
          userMessage: lastUserMsg.content,
          storyState: storyState,
          recentMessages: recentMessages,
        );
        if (matchedRules.isNotEmpty) {
          final rule = matchedRules.first;
          final cooldown = rule.cooldownMinutes ??
              ProactiveRateLimiter.defaultCooldownMinutes;
          if (_rateLimiter.canCallTool(rule.id,
              cooldownMinutes: cooldown)) {
            _rateLimiter.recordCall(rule.id);
            final decision = ProactiveDecisionResult(
              shouldAct: true,
              actionType: rule.actionType,
              actionArgs: rule.buildArgs(
                characterName: character.name,
                userId: userId,
                userMessage: lastUserMsg.content,
              ),
              reason: '触发规则匹配: ${rule.name}',
              priority: rule.priority,
              confidence: 0.9,
            );
            _logDecision(decision, 'rule_matched');
            return decision;
          }
        }
      }

      // 1. 收集故事状态上下文
      final storyContext = await storyStateService.getStoryContext(
        characterId: character.id,
        userId: userId,
      );

      // 2. 构建最近对话（取最近 5 条）
      final recentMsgs = recentMessages
          .take(5)
          .map((m) => <String, String>{
                'role': m.isUser ? 'user' : 'assistant',
                'content': m.content,
              })
          .toList();

      // 3. 构建决策请求
      final userMessage = ProactiveDecisionPrompt.buildUserMessage(
        characterName: character.name,
        personality: character.personality,
        backgroundStory: character.backgroundStory,
        relationshipStage: storyContext['relationshipStage'] ?? 'undefined',
        atmosphere: storyContext['atmosphere'] ?? 'undefined',
        storyProgress: storyContext['progress'] ?? 0.0,
        pendingGoals: List<String>.from(storyContext['pendingGoals'] ?? []),
        recentEvents: List<String>.from(storyContext['recentEvents'] ?? []),
        recentMessages: recentMsgs,
        availableTools: _buildActionDescriptions(),
      );

      // 4. 调用 LLM 做决策
      final response = await llm.chat(
        userId: 'proactive_decision_$userId',
        message: userMessage,
        systemPrompt: ProactiveDecisionPrompt.systemPrompt,
        stream: false,
        maxTokensOverride: 512,
      );

      final content = response.content;
      if (content.isEmpty) {
        return const ProactiveDecisionResult.noAction('LLM 返回空内容');
      }

      // 5. 解析 JSON 决策
      final decision = _parseDecision(content);

      // 6. 限频检查
      if (decision.shouldAct && decision.actionType != null) {
        final actionName = decision.actionType!.name;
        final cooldown = _getCooldownForSensitivity(decision.priority);

        if (!_rateLimiter.canCallTool(actionName,
            cooldownMinutes: cooldown)) {
          _logDecision(decision, 'rate_limited');
          return ProactiveDecisionResult.rateLimited(
            '动作 $actionName 被限频，冷却时间 $cooldown 分钟',
          );
        }

        _rateLimiter.recordCall(actionName);
      }

      _logDecision(decision, 'accepted');
      return decision;
    } catch (e) {
      debugPrint('ProactiveDecisionEngine: 决策失败 - $e');
      return ProactiveDecisionResult.noAction('决策引擎异常: $e');
    }
  }

  /// 解析 LLM 返回的 JSON 决策
  ProactiveDecisionResult _parseDecision(String content) {
    try {
      final jsonStr = _extractJson(content);
      if (jsonStr == null) {
        return const ProactiveDecisionResult.noAction('无法解析 JSON');
      }

      final json = jsonDecode(jsonStr) as Map<String, dynamic>;

      final shouldAct = json['should_act'] as bool? ?? false;
      if (!shouldAct) {
        return ProactiveDecisionResult.noAction(
          json['reason'] as String? ?? '无需执行主动动作',
        );
      }

      // 映射工具名到动作类型
      final toolName = json['tool_name'] as String?;
      final actionType = _mapToolNameToAction(toolName);

      if (actionType == null) {
        return ProactiveDecisionResult.noAction(
          '未知动作类型: $toolName',
        );
      }

      return ProactiveDecisionResult(
        shouldAct: true,
        actionType: actionType,
        actionArgs: Map<String, String>.from(
          (json['args'] as Map<String, dynamic>?) ?? {},
        ),
        reason: json['reason'] as String? ?? '',
        priority: json['priority'] as String? ?? 'low',
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0.5,
      );
    } catch (e) {
      debugPrint('ProactiveDecisionEngine: JSON 解析失败 - $e');
      return const ProactiveDecisionResult.noAction('JSON 解析失败');
    }
  }

  /// 映射 LLM 返回的工具名到动作类型
  ProactiveActionType? _mapToolNameToAction(String? toolName) {
    switch (toolName) {
      case 'emotion_care':
        return ProactiveActionType.emotionCare;
      case 'intimacy_boost':
        return ProactiveActionType.intimacyBoost;
      case 'story_progression':
        return ProactiveActionType.storyProgression;
      case 'proactive_topic':
        return ProactiveActionType.proactiveTopic;
      default:
        return null;
    }
  }

  /// 从内容中提取 JSON
  String? _extractJson(String content) {
    try {
      jsonDecode(content);
      return content;
    } catch (_) {}

    final jsonBlockRegex = RegExp(r'```json\s*(.*?)\s*```', dotAll: true);
    final match = jsonBlockRegex.firstMatch(content);
    if (match != null) return match.group(1);

    final braceRegex = RegExp(r'\{.*\}', dotAll: true);
    final braceMatch = braceRegex.firstMatch(content);
    if (braceMatch != null) return braceMatch.group(0);

    return null;
  }

  /// 根据敏感度和优先级获取冷却时间
  int _getCooldownForSensitivity(String priority) {
    switch (sensitivity) {
      case 'high':
        return 3;
      case 'medium':
        return priority == 'high' ? 3 : 5;
      case 'low':
        return 10;
      default:
        return ProactiveRateLimiter.defaultCooldownMinutes;
    }
  }

  /// 记录决策日志
  void _logDecision(ProactiveDecisionResult decision, String status) {
    _decisionLog.add({
      'timestamp': DateTime.now().toIso8601String(),
      'shouldAct': decision.shouldAct,
      'actionType': decision.actionType?.name,
      'reason': decision.reason,
      'priority': decision.priority,
      'confidence': decision.confidence,
      'status': status,
      'sensitivity': sensitivity,
    });

    if (_decisionLog.length > _maxLogSize) {
      _decisionLog.removeAt(0);
    }

    debugPrint(
        '[ProactiveDecision] status=$status action=${decision.actionType?.name} '
        'reason=${decision.reason} confidence=${decision.confidence}');
  }

  /// 构建动作描述列表（供 LLM 决策参考）
  List<Map<String, dynamic>> _buildActionDescriptions() {
    return [
      {
        'name': 'emotion_care',
        'description': '情绪关怀：当用户情绪低落或焦虑时，注入关怀上下文',
      },
      {
        'name': 'intimacy_boost',
        'description': '亲密度提升：当用户表达思念或爱意时，注入温暖上下文',
      },
      {
        'name': 'story_progression',
        'description': '故事推进：当故事中存在未完成约定时，注入推进上下文',
      },
      {
        'name': 'proactive_topic',
        'description': '主动话题：当对话冷场时，注入话题建议上下文',
      },
    ];
  }

  /// 重置限频器
  void resetRateLimiter() {
    _rateLimiter.reset();
  }

  /// 获取限频统计
  Map<String, dynamic> getRateLimiterStats() {
    return _rateLimiter.getStats();
  }
}
