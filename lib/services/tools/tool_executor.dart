import 'dart:async';
import 'package:flutter/foundation.dart';
import 'tool.dart';
import 'tool_registry.dart';

/// 工具执行器
///
/// 负责权限检查、工具查找、执行，并返回执行记录。
class ToolExecutor {
  final ToolRegistry registry;
  final bool Function(Tool tool)? permissionChecker;

  const ToolExecutor(this.registry, {this.permissionChecker});

  /// 执行工具
  Future<ToolExecutionRecord> execute(
    String toolName,
    Map<String, dynamic> args, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final startedAt = DateTime.now();
    final tool = registry.findTool(toolName);
    if (tool == null) {
      return ToolExecutionRecord(
        toolName: toolName,
        args: args,
        result: ToolResult.error('未知工具: $toolName', errorCode: 'UNKNOWN_TOOL'),
        startedAt: startedAt,
        endedAt: DateTime.now(),
      );
    }

    // Tool metadata is the last local safety boundary before execution. The
    // caller can still add a stricter policy through guardedExecute.
    if (tool.requiredPermissions.isNotEmpty &&
        permissionChecker != null &&
        !permissionChecker!(tool)) {
      return ToolExecutionRecord(
        toolName: toolName,
        args: args,
        result: ToolResult.error(
          '工具需要授权后才能执行: ${tool.requiredPermissions.join(', ')}',
          errorCode: 'PERMISSION_REQUIRED',
          needsPermission: true,
          permissionName: tool.requiredPermissions.join(','),
        ),
        startedAt: startedAt,
        endedAt: DateTime.now(),
      );
    }

    try {
      final result = await tool.execute(args).timeout(timeout);
      return ToolExecutionRecord(
        toolName: toolName,
        args: args,
        result: result,
        startedAt: startedAt,
        endedAt: DateTime.now(),
      );
    } on TimeoutException {
      return ToolExecutionRecord(
        toolName: toolName,
        args: args,
        result: ToolResult.error('工具执行超时，可稍后重试。', errorCode: 'TIMEOUT'),
        startedAt: startedAt,
        endedAt: DateTime.now(),
      );
    } catch (e, stack) {
      debugPrint('[ToolExecutor] $toolName 执行异常: $e\n$stack');
      return ToolExecutionRecord(
        toolName: toolName,
        args: args,
        result: ToolResult.error('执行异常: $e', errorCode: 'EXECUTION_EXCEPTION'),
        startedAt: startedAt,
        endedAt: DateTime.now(),
      );
    }
  }

  /// 批量执行工具调用
  Future<List<ToolExecutionRecord>> executeAll(List<ToolCall> calls) async {
    final records = <ToolExecutionRecord>[];
    for (final call in calls) {
      records.add(await execute(call.name, call.args));
    }
    return records;
  }
}
