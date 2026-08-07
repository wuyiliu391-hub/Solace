import 'package:flutter_test/flutter_test.dart';
import 'package:solace/services/tools/tool.dart';
import 'package:solace/services/tools/tool_executor.dart';
import 'package:solace/services/tools/tool_registry.dart';

class _PermissionTool extends Tool {
  var executions = 0;

  @override
  String get name => 'permission_tool';

  @override
  String get description => 'test';

  @override
  Map<String, dynamic> get parametersSchema => {
        'type': 'object',
        'properties': <String, dynamic>{},
      };

  @override
  Set<String> get requiredPermissions => {'test_permission'};

  @override
  bool get isDestructive => false;

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    executions++;
    return ToolResult.success('executed');
  }
}

class _PermissionPkg extends ToolPkg {
  final Tool tool;

  _PermissionPkg(this.tool);

  @override
  String get name => 'test';

  @override
  String get description => 'test';

  @override
  List<Tool> get tools => [tool];
}

void main() {
  test('permission policy blocks tools before execution', () async {
    final tool = _PermissionTool();
    final registry = ToolRegistry()..register(_PermissionPkg(tool));
    final executor = ToolExecutor(
      registry,
      permissionChecker: (_) => false,
    );

    final record = await executor.execute(tool.name, {});

    expect(record.result.success, isFalse);
    expect(record.result.needsPermission, isTrue);
    expect(record.result.errorCode, 'PERMISSION_REQUIRED');
    expect(tool.executions, 0);
  });

  test('trace includes structured args and timing metadata', () async {
    final tool = _PermissionTool();
    final registry = ToolRegistry()..register(_PermissionPkg(tool));
    final record = await ToolExecutor(registry).execute(tool.name, {});
    final trace = record.toTraceJson();

    expect(trace['tool'], tool.name);
    expect(trace['args'], isA<Map<String, dynamic>>());
    expect(trace['duration_ms'], isA<int>());
  });
}
