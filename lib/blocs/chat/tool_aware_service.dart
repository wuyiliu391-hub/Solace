import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../services/tools/tool.dart';
import '../../services/tools/tool_registry.dart';
import '../../services/tools/tool_executor.dart';
import '../../services/tools/conversation_turn.dart';
import '../../services/llm_service.dart';

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
  final Future<ToolExecutionRecord> Function(String, Map<String, dynamic>)?
      guardedExecute;
  final bool Function()? isCancelled;

  ToolAwareService({
    required this.llmService,
    required this.registry,
    ToolExecutor? executor,
    this.guardedExecute,
    this.isCancelled,
  }) : executor = executor ?? ToolExecutor(registry);

  Future<ToolExecutionRecord> _execute(String name, Map<String, dynamic> args) {
    return guardedExecute?.call(name, args) ?? executor.execute(name, args);
  }

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
  Future<(String finalText, List<ToolExecutionRecord> records, bool hadTools)>
      run({
    required List<ConversationTurn> turns,
    required List<Map<String, dynamic>> llmMessages,
    int maxSteps = 10,
    bool requireToolOnFirstStep = false,
    void Function(AgentStep)? onStep,
    void Function(ToolProcessingState)? onStateChange,
    void Function(String summary)? onContextCompacted,
  }) async {
    final tools = registry.toOpenAIFormat();
    if (tools.isEmpty) {
      _setState(ToolProcessingState.error);
      onStateChange?.call(_state);
      return ('当前没有可用的工具。', <ToolExecutionRecord>[], false);
    }

    final executions = <ToolExecutionRecord>[];
    final executedCalls = <String>{};
    final mutableMessages = List<Map<String, dynamic>>.from(llmMessages);
    final mutableTurns = List<ConversationTurn>.from(turns);

    _setState(ToolProcessingState.preparing);
    onStateChange?.call(_state);

    // 递归核心：调用 LLM -> 解析输出 -> 提取工具 -> 执行 -> 追加结果 -> 再调用
    var finalContent = '';
    var hadTools = false;

    for (var step = 1; step <= maxSteps; step++) {
      _setState(ToolProcessingState.connecting);
      onStateChange?.call(_state);

      debugPrint('[ToolAware] 第 $step 轮 LLM 调用，消息数 ${mutableMessages.length}');

      final response = await llmService.chatWithTools(
        messages: mutableMessages,
        tools: tools,
        maxTokens: 2048,
        toolChoice: step == 1 && requireToolOnFirstStep ? 'required' : 'auto',
      );

      if (response == null) {
        _setState(ToolProcessingState.error);
        onStateChange?.call(_state);
        if (step == 1) {
          // 第一轮就失败：没有工具也没有回复，返回空
          return ('AI 调用失败，请检查 API 配置。', executions, false);
        }
        // 后续轮失败：返回已有内容
        return (
          finalContent.isNotEmpty ? finalContent : 'AI 调用中断',
          executions,
          hadTools
        );
      }

      _setState(ToolProcessingState.receiving);
      onStateChange?.call(_state);

      final content = response['content'] as String? ?? '';
      final reasoning = response['reasoning'] as String? ?? '';

      final visibleContent = _removeXmlToolCalls(content);
      if (visibleContent.isNotEmpty) {
        finalContent = visibleContent;
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
          // 调用方已确认是设备请求时，绝不能把模型的文本输出伪装成执行结果。
          _setState(ToolProcessingState.completed);
          onStateChange?.call(_state);
          if (requireToolOnFirstStep) {
            return (
              '设备请求未执行：当前模型没有发起工具调用。请更换支持 Function Calling 的模型，或使用 Operit 中的快捷操作。',
              executions,
              false,
            );
          }
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
      final toolCalls = allToolCalls.map(ToolCall.fromOpenAI).toList();

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
        final callKey = _callKey(call);
        if (!executedCalls.add(callKey)) {
          final duplicate = ToolExecutionRecord(
            toolName: call.name,
            args: call.args,
            result: ToolResult.error(
              '检测到重复工具调用，已停止重复执行。',
              errorCode: 'DUPLICATE_TOOL_CALL',
            ),
            startedAt: DateTime.now(),
            endedAt: DateTime.now(),
          );
          executions.add(duplicate);
          final duplicateTurn = ConversationTurn.toolResultFromExecution(
            duplicate,
            toolCallId: '${call.name}_duplicate_$i',
          );
          mutableTurns.add(duplicateTurn);
          mutableMessages.add(duplicateTurn.toLlmMessage());
          onStep?.call(AgentStep(
            step: step,
            toolName: call.name,
            args: call.args,
            status: 'failed',
            result: duplicate.result.message,
          ));
          continue;
        }
        final toolCallId = allToolCalls.length > i
            ? (allToolCalls[i]['id'] as String? ?? '${call.name}_$i')
            : '${call.name}_$i';

        onStep?.call(AgentStep(
          step: step,
          toolName: call.name,
          args: call.args,
          status: 'running',
        ));

        if (isCancelled?.call() == true) {
          return (
            finalContent.isNotEmpty ? finalContent : '任务已取消。',
            executions,
            hadTools
          );
        }
        var record = await _executeWithRetry(call.name, call.args);
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
        _compactContextIfNeeded(
            mutableMessages, mutableTurns, onContextCompacted);
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
        return (
          finalContent.isNotEmpty ? finalContent : '工具已执行，但 AI 后续回复失败。',
          executions,
          true
        );
      }

      final continueContent = continueResponse['content'] as String? ?? '';
      final continueReasoning = continueResponse['reasoning'] as String? ?? '';

      final continueVisibleContent = _removeXmlToolCalls(continueContent);
      if (continueVisibleContent.isNotEmpty) {
        finalContent = continueVisibleContent;
      }

      // 检查工具执行后的回复里是否又有新的工具调用
      final continueToolCalls =
          (continueResponse['tool_calls'] as List<dynamic>?)
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

      // 有新的工具调用：先追加 assistant turn 并执行它们。
      final continueAssistantTurn = ConversationTurn.assistantFromResponse(
        continueContent,
        reasoning: continueReasoning,
        toolCalls: continueToolCalls,
      );
      mutableTurns.add(continueAssistantTurn);
      mutableMessages.add(continueAssistantTurn.toLlmMessage());

      final parsedContinueCalls = [
        ...continueToolCalls.map(ToolCall.fromOpenAI),
        ...continueXmlCalls.map((tc) => ToolCall(name: tc.name, args: tc.args)),
      ];
      _setState(ToolProcessingState.executingTool);
      onStateChange?.call(_state);
      for (var i = 0; i < parsedContinueCalls.length; i++) {
        final call = parsedContinueCalls[i];
        final callKey = _callKey(call);
        if (!executedCalls.add(callKey)) {
          final duplicate = ToolExecutionRecord(
            toolName: call.name,
            args: call.args,
            result: ToolResult.error(
              '检测到重复工具调用，已停止重复执行。',
              errorCode: 'DUPLICATE_TOOL_CALL',
            ),
            startedAt: DateTime.now(),
            endedAt: DateTime.now(),
          );
          executions.add(duplicate);
          final duplicateTurn = ConversationTurn.toolResultFromExecution(
            duplicate,
            toolCallId: '${call.name}_duplicate_$i',
          );
          mutableTurns.add(duplicateTurn);
          mutableMessages.add(duplicateTurn.toLlmMessage());
          continue;
        }
        final toolCallId = i < continueToolCalls.length
            ? (continueToolCalls[i]['id'] as String? ?? '${call.name}_$i')
            : '${call.name}_$i';
        onStep?.call(AgentStep(
          step: step,
          toolName: call.name,
          args: call.args,
          status: 'running',
        ));
        if (isCancelled?.call() == true) {
          return (
            finalContent.isNotEmpty ? finalContent : '任务已取消。',
            executions,
            hadTools
          );
        }
        final record = await _executeWithRetry(call.name, call.args);
        executions.add(record);
        onStep?.call(AgentStep(
          step: step,
          toolName: call.name,
          args: call.args,
          status: record.result.success ? 'completed' : 'failed',
          result: record.result.message,
        ));
        mutableTurns.add(ConversationTurn.toolResultFromExecution(
          record,
          toolCallId: toolCallId,
        ));
        mutableMessages.add(mutableTurns.last.toLlmMessage());
        _compactContextIfNeeded(
            mutableMessages, mutableTurns, onContextCompacted);
      }
    }

    // 达到最大步数
    _setState(ToolProcessingState.completed);
    onStateChange?.call(_state);
    return (
      finalContent.isNotEmpty ? finalContent : '工具已执行完毕。',
      executions,
      true
    );
  }

  // ── 辅助方法 ──

  void _compactContextIfNeeded(
    List<Map<String, dynamic>> messages,
    List<ConversationTurn> turns,
    void Function(String summary)? onSummary,
  ) {
    if (messages.length <= 24) return;
    final start = messages.length > 10 ? messages.length - 10 : 0;
    final removed = messages
        .sublist(1, start)
        .where((message) => message['role'] == 'tool')
        .map((message) => message['content']?.toString() ?? '')
        .where((content) => content.isNotEmpty)
        .join('\n');
    if (removed.isEmpty) return;
    final summary = '已压缩早期工具结果：$removed';
    messages.removeRange(1, start);
    messages
        .insert(1, {'role': 'system', 'content': '[AgentSummary] $summary'});
    turns.add(ConversationTurn(
      kind: ConversationTurnKind.summary,
      content: summary,
      createdAt: DateTime.now(),
    ));
    onSummary?.call(summary);
  }

  Future<ToolExecutionRecord> _executeWithRetry(
      String name, Map<String, dynamic> args) async {
    ToolExecutionRecord record = await _execute(name, args);
    for (var attempt = 1; attempt < 3 && record.isRetryable; attempt++) {
      if (isCancelled?.call() == true) break;
      await Future<void>.delayed(Duration(milliseconds: 250 * attempt));
      record = await _execute(name, args);
    }
    return record;
  }

  String _callKey(ToolCall call) =>
      '${call.name}:${jsonEncode(_sortMap(call.args))}';

  Map<String, dynamic> _sortMap(Map<String, dynamic> value) {
    final keys = value.keys.toList()..sort();
    return {
      for (final key in keys)
        key: value[key] is Map<String, dynamic>
            ? _sortMap(value[key] as Map<String, dynamic>)
            : value[key],
    };
  }

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

  String _removeXmlToolCalls(String content) {
    return content
        .replaceAll(
          RegExp(r'<tool\b[^>]*>[\s\S]*?</tool>',
              caseSensitive: false, dotAll: true),
          '',
        )
        .trim();
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
