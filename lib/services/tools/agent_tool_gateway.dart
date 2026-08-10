import 'tool.dart';
import 'tool_executor.dart';
import 'tool_registry.dart';

/// 统一的 Agent 工具执行闸门。
///
/// 所有声明了 requiredPermissions 的工具都必须明确经过 permissionChecker；
/// 没有检查器时默认拒绝，避免新执行入口意外绕过权限。
class AgentToolGateway {
  final ToolRegistry registry;
  final bool Function(Tool tool) permissionChecker;
  final ToolExecutor _executor;

  AgentToolGateway({
    required this.registry,
    bool Function(Tool tool)? permissionChecker,
    ToolExecutor? executor,
  })  : permissionChecker = permissionChecker ?? _denyDeclaredPermissions,
        _executor = executor ??
            ToolExecutor(
              registry,
              permissionChecker: permissionChecker ?? _denyDeclaredPermissions,
            );

  static bool _denyDeclaredPermissions(Tool tool) =>
      tool.requiredPermissions.isEmpty;

  Future<ToolExecutionRecord> execute(
    String toolName,
    Map<String, dynamic> args, {
    Duration timeout = const Duration(seconds: 30),
  }) =>
      _executor.execute(toolName, args, timeout: timeout);

  Future<List<ToolExecutionRecord>> executeAll(
    List<ToolCall> calls, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final records = <ToolExecutionRecord>[];
    for (final call in calls) {
      records.add(await execute(call.name, call.args, timeout: timeout));
    }
    return records;
  }
}
