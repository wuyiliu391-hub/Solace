import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../services/llm_service.dart';
import 'tool.dart';
import 'tool_registry.dart';
import 'tool_executor.dart';

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

/// Agent Loop — 通用工具调用执行循环
///
/// 对标 Operit 的 Agent 执行循环：
/// 1. 构建系统提示，包含工具描述
/// 2. 调用 LLM
/// 3. 解析 tool_calls
/// 4. 执行工具
/// 5. 把结果返回给 LLM，循环直到完成
class AgentLoop {
  final ToolRegistry registry;
  final ToolExecutor executor;

  AgentLoop({
    required this.registry,
    ToolExecutor? executor,
  }) : executor = executor ?? ToolExecutor(registry);

  /// 执行用户请求
  ///
  /// [messages] 初始消息列表，包含 system 和 user 消息
  /// [llmService] 提供 chatWithTools 能力
  /// [maxSteps] 最大工具调用轮数，防止无限循环
  /// [onStep] 每步回调，用于 UI 更新
  Future<AgentLoopResult> run({
    required List<Map<String, dynamic>> messages,
    required LlmService llmService,
    int maxSteps = 10,
    void Function(AgentStep)? onStep,
  }) async {
    final tools = registry.toOpenAIFormat();
    if (tools.isEmpty) {
      return const AgentLoopResult(
        finalContent: '当前没有可用的工具。',
        success: false,
        error: 'NO_TOOLS',
      );
    }

    final executions = <ToolExecutionRecord>[];

    for (var step = 1; step <= maxSteps; step++) {
      debugPrint('[AgentLoop] 第 $step 轮调用 LLM，消息数 ${messages.length}');

      final response = await llmService.chatWithTools(
        messages: messages,
        tools: tools,
        maxTokens: 2048,
      );

      if (response == null) {
        return AgentLoopResult(
          finalContent: 'AI 调用失败，请检查 API 配置。',
          success: false,
          error: 'LLM_NO_RESPONSE',
          executions: executions,
        );
      }

      final content = response['content'] as String? ?? '';
      final reasoning = response['reasoning'] as String? ?? '';
      // 安全转换 tool_calls
      final toolCallsRaw = (response['tool_calls'] as List<dynamic>?)
              ?.map(_safeCastMap)
              .whereType<Map<String, dynamic>>()
              .toList() ??
          [];

      // 没有工具调用，直接返回最终内容
      if (toolCallsRaw.isEmpty) {
        return AgentLoopResult(
          finalContent: content,
          reasoning: reasoning,
          executions: executions,
        );
      }

      // 解析工具调用
      final toolCalls = toolCallsRaw
          .whereType<Map<String, dynamic>>()
          .map(ToolCall.fromOpenAI)
          .toList();

      if (toolCalls.isEmpty) {
        return AgentLoopResult(
          finalContent: content,
          reasoning: reasoning,
          executions: executions,
        );
      }

      // 执行工具
      final assistantMessage = <String, dynamic>{
        'role': 'assistant',
        'content': content,
        if (reasoning.isNotEmpty) 'reasoning_content': reasoning,
        'tool_calls': toolCallsRaw,
      };
      messages.add(assistantMessage);

      for (var i = 0; i < toolCalls.length; i++) {
        final call = toolCalls[i];
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

        messages.add({
          'role': 'tool',
          'tool_call_id': toolCallsRaw[i]['id'] as String? ?? '${call.name}_$i',
          'name': call.name,
          'content': _formatToolResult(result),
        });
      }
    }

    // 达到最大步数，强制返回
    return AgentLoopResult(
      finalContent: '执行步骤过多，已中断。\n\n已执行工具：\n${_formatExecutions(executions)}',
      success: false,
      error: 'MAX_STEPS_REACHED',
      executions: executions,
    );
  }

  String _formatToolResult(ToolResult result) {
    if (result.success) {
      return result.message;
    }
    if (result.needsPermission) {
      return '需要权限: ${result.permissionName ?? "未知权限"}. 错误: ${result.message}';
    }
    return '错误: ${result.message}';
  }

  String _formatExecutions(List<ToolExecutionRecord> executions) {
    return executions
        .map((e) => '- ${e.toolName}: ${e.result.success ? "成功" : "失败"} — ${e.result.message}')
        .join('\n');
  }
}
