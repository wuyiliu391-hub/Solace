import 'dart:convert';

import '../models/chat_message.dart';
import '../models/tool_intent_decision.dart';
import 'llm_service.dart';
import 'recent_tool_context.dart';
import 'tools/tool_registry.dart';

/// Uses a constrained LLM response only for ambiguous or contextual requests.
/// Execution, permissions, rate limits, and auditing remain local.
class ToolIntentPlanner {
  static const minimumConfidence = 0.72;

  static final RegExp _candidateSignal = RegExp(
    r'(手机|设备|软件|应用|app|通知|电量|电池|屏幕|系统|设置|wifi|蓝牙|看看|看一眼|再看看|再查|还是不行|没看到|求求你|担心我)',
    caseSensitive: false,
  );
  static final RegExp _blockedNarrative = RegExp(
    r'^(?:他|她|它|角色|故事里|剧情里|小说里|梦里|想象中|如果|假如|要是|别|不要|别再|别去)',
  );

  final LlmService llm;
  final ToolRegistry registry;

  const ToolIntentPlanner({required this.llm, required this.registry});

  static bool shouldPlan(String message, RecentToolContext? recent) {
    final text = message.trim();
    if (text.isEmpty || text.length > 150 || _blockedNarrative.hasMatch(text)) {
      return false;
    }
    return recent != null || _candidateSignal.hasMatch(text);
  }

  Future<ToolIntentDecision> plan({
    required String message,
    required List<ChatMessage> recentMessages,
    RecentToolContext? recentTool,
  }) async {
    if (!shouldPlan(message, recentTool)) {
      return const ToolIntentDecision.conversation(reason: 'not_a_candidate');
    }

    final response = await llm.chat(
      userId: 'tool_intent_planner',
      message: message,
      stream: false,
      maxTokensOverride: 360,
      includeReasoningFallback: false,
      systemPrompt: _buildPrompt(recentMessages, recentTool),
    );
    if (!response.success || response.content.trim().isEmpty) {
      return const ToolIntentDecision.conversation(
          reason: 'planner_unavailable');
    }
    return validate(_parse(response.content), recentTool);
  }

  ToolIntentDecision validate(
    ToolIntentDecision decision,
    RecentToolContext? recentTool,
  ) {
    if (decision.kind == ToolIntentKind.conversation ||
        decision.kind == ToolIntentKind.clarificationRequired ||
        decision.kind == ToolIntentKind.confirmationRequired ||
        decision.kind == ToolIntentKind.notAllowed) {
      return decision;
    }
    final tool = decision.toolName;
    if (tool == null || registry.findTool(tool) == null) {
      return const ToolIntentDecision.conversation(reason: 'unknown_tool');
    }
    if (decision.confidence < minimumConfidence) {
      return const ToolIntentDecision.conversation(reason: 'low_confidence');
    }
    if (!RecentToolContext.readOnlyTools.contains(tool) ||
        registry.findTool(tool)!.isDestructive) {
      return const ToolIntentDecision(
        kind: ToolIntentKind.clarificationRequired,
        reason: 'implicit_high_impact_action',
      );
    }
    if (decision.kind == ToolIntentKind.continueToolTask &&
        (recentTool == null ||
            !recentTool.isReadOnly ||
            tool != recentTool.toolName)) {
      return const ToolIntentDecision.conversation(
          reason: 'invalid_continuation');
    }
    return decision;
  }

  ToolIntentDecision _parse(String content) {
    final match = RegExp(r'\{[\s\S]*\}').firstMatch(content.trim());
    if (match == null) {
      return const ToolIntentDecision.conversation(reason: 'invalid_json');
    }
    try {
      return ToolIntentDecision.fromJson(
        jsonDecode(match.group(0)!) as Map<String, dynamic>,
      );
    } catch (_) {
      return const ToolIntentDecision.conversation(reason: 'invalid_json');
    }
  }

  String _buildPrompt(
    List<ChatMessage> messages,
    RecentToolContext? recentTool,
  ) {
    final history = messages.reversed
        .where((message) => !message.isHidden && !message.isGhost)
        .take(6)
        .toList()
        .reversed
        .map((message) => '${message.isUser ? '用户' : '角色'}：${message.content}')
        .join('\n');
    final tools = RecentToolContext.readOnlyTools
        .where((name) => registry.findTool(name) != null)
        .map((name) => '$name: ${registry.findTool(name)!.description}')
        .join('\n');
    return '''你是设备意图分类器，不直接与用户对话，不执行工具。只输出一个 JSON 对象。
判断用户是否希望操作其真实设备，或是否在承接最近真实设备查询。
只允许选择只读工具；删除、发送、安装、Shell、输入、UI 操作一律返回 clarificationRequired。
情绪表达、剧情、转述、假设和否定请求必须返回 conversation。
“看看我手机，里面好多软件”是 get_installed_apps；最近查过电量后“再看看呗”可继续 get_battery_info；“求求你了哥哥，你不担心我吗”只有在最近工具语境明确时才可继续，否则是 conversation。
JSON schema: {"decision":"conversation|directTool|continueToolTask|agentToolTask|clarificationRequired","tool":"工具名或空字符串","args":{},"candidate_tools":[],"confidence":0.0,"reason":"简短原因","missing_slots":[],"source":"llm","is_read_only":true}
可用只读工具：
$tools
最近对话：
$history
${recentTool == null ? '没有可续接的最近工具任务。' : recentTool.toPromptText()}''';
  }
}
