import 'package:flutter_test/flutter_test.dart';
import 'package:solace/services/tools/agent_tool_gateway.dart';
import 'package:solace/services/tools/tool.dart';
import 'package:solace/services/tools/tool_registry.dart';

class _GatewayTool extends Tool {
  int executions = 0;

  @override
  String get name => 'gateway_tool';

  @override
  String get description => 'test';

  @override
  Map<String, dynamic> get parametersSchema => {
        'type': 'object',
        'properties': <String, dynamic>{},
      };

  @override
  Set<String> get requiredPermissions => {'gateway_permission'};

  @override
  bool get isDestructive => false;

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    executions++;
    return ToolResult.success('executed');
  }
}

class _GatewayPkg extends ToolPkg {
  final Tool tool;

  _GatewayPkg(this.tool);

  @override
  String get name => 'gateway_test';

  @override
  String get description => 'test';

  @override
  List<Tool> get tools => [tool];
}

void main() {
  test('gateway denies declared permissions without checker', () async {
    final tool = _GatewayTool();
    final registry = ToolRegistry()..register(_GatewayPkg(tool));
    final record = await AgentToolGateway(registry: registry).execute(
      tool.name,
      {},
    );

    expect(record.result.success, isFalse);
    expect(record.result.needsPermission, isTrue);
    expect(record.result.errorCode, 'PERMISSION_REQUIRED');
    expect(tool.executions, 0);
  });

  test('gateway delegates to explicit permission checker', () async {
    final tool = _GatewayTool();
    final registry = ToolRegistry()..register(_GatewayPkg(tool));
    final gateway = AgentToolGateway(
      registry: registry,
      permissionChecker: (_) => true,
    );
    final record = await gateway.execute(tool.name, {});

    expect(record.result.success, isTrue);
    expect(tool.executions, 1);
  });

  test('gateway keeps unknown tools as structured failures', () async {
    final registry = ToolRegistry();
    final record = await AgentToolGateway(registry: registry).execute(
      'missing_tool',
      {},
    );

    expect(record.result.success, isFalse);
    expect(record.result.errorCode, 'UNKNOWN_TOOL');
  });
}
