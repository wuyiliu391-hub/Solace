import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../services/tools/tool.dart';
import '../../services/tools/tool_registry.dart';
import '../../services/tools/tool_executor.dart';
import '../../services/tools/conversation_turn.dart';
import '../../services/llm_service.dart';
import '../../models/app_config_data.dart';
import '../../utils/message_sanitizer.dart';

/// 工具感知的 LLM 调用服务 — 重写版
///
/// 对标 Operit EnhancedAIService 的设计：
/// - 不另起 LLM 调用做前置"检测"，而是从同一次模型输出中解析工具调用
/// - 工具调用是对话的一部分，执行结果作为 TOOL_RESULT Turn 持久化
/// - 递归 processStreamCompletion 直到没有工具调用为止
/// - 显式状态机：idle -> preparing -> connecting -> receiving -> executingTool -> processingToolResult -> completed/error
///
/// 关键差异 vs 旧版：
/// - 旧版: detectAndExecute(前置检测) -> null 回退角色聊天
/// - 新版: 模型一次输出 -> parseToolCalls(输出后解析) -> execute -> appendResult -> 再请求模型 -> 递归
class ToolAwareService {
  final LlmService llmService;
  final ToolRegistry registry;
  final ToolExecutor executor;

  ToolAwareService({
    required this.llmService,
    required this.registry,
    ToolExecutor? executor,
  }) : executor = executor ?? ToolExecutor(registry);

  // ── 状态机 ──

  ToolProcessingState _state = ToolProcessingState.idle;
  ToolProcessingState get state => _state;

  void _setState(ToolProcessingState newState) {
    _state = newState;
    debugPrint('[ToolAware] state -> ${newState.name}');
  }

  // ── 主入口：执行工具感知的 LLM 调用 ──

  /// 执行一次完整的工具感知 LLM 调用
  ///
  /// [turns] 当前对话回合列表（含系统提示、角色提示、工具描述、历史）
  /// [llmMessages] 给 LLM API 的原始消息列表（并行维护，用于实际 API 调用）
  /// [maxSteps] 最大工具调用轮数，防止无限循环
  /// [onStep] 每步回调，用于 UI 更新
  /// [onStateChange] 状态变更回调
  ///
  /// 返回 (finalText, executionRecords, hadTools)
  Future<(String finalText, List<ToolExecutionRecord> records, bool hadTools)> run({
    required List<ConversationTurn> turns,
    required List<Map<String, dynamic>> llmMessages,
    int maxSteps = 10,
    void Function(AgentStep)? onStep,
    void Function(ToolProcessingState)? onStateChange,
  }) async {
    final tools = registry.toOpenAIFormat();
    if (tools.isEmpty) {
      _setState(ToolProcessingState.error);
      onStateChange?.call(_state);
      return ('当前没有可用的工具。', <ToolExecutionRecord>[], false);
    }

    final executions = <ToolExecutionRecord>[];
    final mutableMessages = List<Map<String, dynamic>>.from(llmMessages);
    final mutableTurns = List<ConversationTurn>.from(turns);

    _setState(ToolProcessingState.preparing);
    onStateChange?.call(_state);

    // 递归核心：调用 LLM -> 解析输出 -> 提取工具 -> 执行 -> 追加结果 -> 再调用
    var finalContent = '';
    var finalReasoning = '';
    var hadTools = false;

    for (var step = 1; step <= maxSteps; step++) {
      _setState(ToolProcessingState.connecting);
      onStateChange?.call(_state);

      debugPrint('[ToolAware] 第 $step 轮 LLM 调用，消息数 ${mutableMessages.length}');

      final response = await llmService.chatWithTools(
        messages: mutableMessages,
        tools: tools,
        maxTokens: 2048,
      );

      if (response == null) {
        _setState(ToolProcessingState.error);
        onStateChange?.call(_state);
        if (step == 1) {
          // 第一轮就失败：没有工具也没有回复，返回空
          return ('AI 调用失败，请检查 API 配置。', executions, false);
        }
        // 后续轮失败：返回已有内容
        return (finalContent.isNotEmpty ? finalContent : 'AI 调用中断',
            executions, hadTools);
      }

      _setState(ToolProcessingState.receiving);
      onStateChange?.call(_state);

      final content = response['content'] as String? ?? '';
      final reasoning = response['reasoning'] as String? ?? '';

      if (content.isNotEmpty) {
        finalContent = content;
        finalReasoning = reasoning;
      }

      // ── 关键：从同一次输出中解析工具调用 ──
      final toolCallsRaw = (response['tool_calls'] as List<dynamic>?)
              ?.map((e) => _safeCastMap(e))
              .whereType<Map<String, dynamic>>()
              .toList() ??
          [];

      // 同时尝试从文本内容中提取 Operit 风格 XML 工具标签
      final xmlToolCalls = _extractXmlToolCalls(content);
      final allToolCalls = [...toolCallsRaw];

      if (allToolCalls.isEmpty && xmlToolCalls.isEmpty) {
        // 没有工具调用：完成
        if (step == 1) {
          // 第一轮就没有工具调用：不是工具请求
          _setState(ToolProcessingState.completed);
          onStateChange?.call(_state);
          return (finalContent, executions, false);
        }
        // 工具执行后的后续轮：模型给了文本回复，结束循环
        _setState(ToolProcessingState.completed);
        onStateChange?.call(_state);
        return (finalContent, executions, true);
      }

      // ── 有工具调用 ──
      hadTools = true;

      // 解析 OpenAI 格式的 tool calls
      final toolCalls = allToolCalls
          .map(ToolCall.fromOpenAI)
          .toList();

      // 追加 XML 工具调用
      final parsedXmlCalls = xmlToolCalls
          .map((tc) => ToolCall(name: tc.name, args: tc.args))
          .toList();
      final allParsedCalls = [...toolCalls, ...parsedXmlCalls];

      if (allParsedCalls.isEmpty) {
        _setState(ToolProcessingState.completed);
        onStateChange?.call(_state);
        return (finalContent, executions, true);
      }

      // ── 追加 assistant turn ──
      final assistantTurn = ConversationTurn.assistantFromResponse(
        content,
        reasoning: reasoning,
        toolCalls: allToolCalls,
      );
      mutableTurns.add(assistantTurn);
      mutableMessages.add(assistantTurn.toLlmMessage());

      // ── 执行每个工具 ──
      _setState(ToolProcessingState.executingTool);
      onStateChange?.call(_state);

      for (var i = 0; i < allParsedCalls.length; i++) {
        final call = allParsedCalls[i];
        final toolCallId = allToolCalls.length > i
            ? (allToolCalls[i]['id'] as String? ?? '${call.name}_$i')
            : '${call.name}_$i';

        onStep?.call(AgentStep(
          step: step,
          toolName: call.name,
          args: call.args,
          status: 'running',
        ));

        final record = await executor.execute(call.name, call.args);
        executions.add(record);

        final result = record.result;
        onStep?.call(AgentStep(
          step: step,
          toolName: call.name,
          args: call.args,
          status: result.success ? 'completed' : 'failed',
          result: result.message,
        ));

        // ── 追加 tool_result turn ──
        final toolResultTurn = ConversationTurn.toolResultFromExecution(
          record,
          toolCallId: toolCallId,
        );
        mutableTurns.add(toolResultTurn);
        mutableMessages.add(toolResultTurn.toLlmMessage());
      }

      _setState(ToolProcessingState.processingToolResult);
      onStateChange?.call(_state);

      // ── 继续循环：让 LLM 看到工具结果后再生成 ──
      // 需要再请求一次 LLM，把 tool_result 消息发给模型
      final continueResponse = await llmService.chatWithTools(
        messages: mutableMessages,
        tools: tools,
        maxTokens: 2048,
      );

      if (continueResponse == null) {
        _setState(ToolProcessingState.error);
        onStateChange?.call(_state);
        return (finalContent.isNotEmpty ? finalContent : '工具已执行，但 AI 后续回复失败。',
            executions, true);
      }

      final continueContent = continueResponse['content'] as String? ?? '';
      final continueReasoning = continueResponse['reasoning'] as String? ?? '';

      if (continueContent.isNotEmpty) {
        finalContent = continueContent;
        finalReasoning = continueReasoning;
      }

      // 检查工具执行后的回复里是否又有新的工具调用
      final continueToolCalls = (continueResponse['tool_calls'] as List<dynamic>?)
              ?.map((e) => _safeCastMap(e))
              .whereType<Map<String, dynamic>>()
              .toList() ??
          [];
      final continueXmlCalls = _extractXmlToolCalls(continueContent);

      if (continueToolCalls.isEmpty && continueXmlCalls.isEmpty) {
        // 没有新的工具调用：完成
        _setState(ToolProcessingState.completed);
        onStateChange?.call(_state);
        return (finalContent, executions, true);
      }

      // 有新的工具调用：下一轮循环继续
      // 追加 assistant turn
      final continueAssistantTurn = ConversationTurn.assistantFromResponse(
        continueContent,
        reasoning: continueReasoning,
        toolCalls: continueToolCalls,
      );
      mutableTurns.add(continueAssistantTurn);
      mutableMessages.add(continueAssistantTurn.toLlmMessage());
    }

    // 达到最大步数
    _setState(ToolProcessingState.completed);
    onStateChange?.call(_state);
    return (finalContent.isNotEmpty ? finalContent : '工具已执行完毕。',
        executions, true);
  }

  // ── 辅助方法 ──

  /// 从文本内容中提取 Operit 风格 XML 工具标签
  /// 格式: <tool name="tool_name"><param name="param_name">value</param></tool>
  List<ExtractedToolCall> _extractXmlToolCalls(String content) {
    if (content.isEmpty) return [];

    final results = <ExtractedToolCall>[];
    final toolPattern = RegExp(
      r'<tool\b[^>]*name="([^"]+)"[^>]*>([\s\S]*?)</tool>',
      caseSensitive: false,
      dotAll: true,
    );

    for (final match in toolPattern.allMatches(content)) {
      final toolName = match.group(1) ?? '';
      final toolBody = match.group(2) ?? '';
      if (toolName.isEmpty) continue;

      final args = <String, dynamic>{};
      final paramPattern = RegExp(
        r'<param\b[^>]*name="([^"]+)"[^>]*>([\s\S]*?)</param>',
        caseSensitive: false,
        dotAll: true,
      );

      for (final paramMatch in paramPattern.allMatches(toolBody)) {
        final paramName = paramMatch.group(1) ?? '';
        final paramValue = paramMatch.group(2) ?? '';
        args[paramName] = paramValue;
      }

      results.add(ExtractedToolCall(
        name: toolName,
        args: args,
        rawText: match.group(0) ?? '',
      ));
    }

    if (results.isNotEmpty) {
      debugPrint('[ToolAware] 从文本中提取了 ${results.length} 个 XML 工具调用: '
          '${results.map((e) => e.name).join(', ')}');
    }

    return results;
  }

  /// 安全将任意 Map 转换为 Map<String, dynamic>
  Map<String, dynamic>? _safeCastMap(dynamic raw) {
    if (raw == null) return null;
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) {
      final result = <String, dynamic>{};
      raw.forEach((key, value) {
        final stringKey = key is String ? key : key.toString();
        result[stringKey] = value;
      });
      return result;
    }
    return null;
  }
}

/// 工具感知 LLM 调用的结果
class ToolAwareResult {
  final String finalContent;
  final List<ToolExecutionRecord> executions;
  final bool success;
  final String? error;
  final bool hadTools;

  const ToolAwareResult({
    required this.finalContent,
    this.executions = const [],
    this.success = true,
    this.error,
    this.hadTools = false,
  });
}