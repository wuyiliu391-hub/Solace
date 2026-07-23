import 'package:flutter/foundation.dart';
import '../tool.dart';
import '../../device_service.dart';

/// Shell 命令工具包
///
/// 执行 Shizuku shell 命令
class ShellToolPkg extends ToolPkg {
  final DeviceService _device = DeviceService();

  @override
  String get name => 'Shell 命令';

  @override
  String get description => '通过 Shizuku 执行 Shell 命令';

  @override
  List<Tool> get tools => [
        _ExecuteShellTool(_device),
      ];
}

class _ExecuteShellTool extends Tool {
  final DeviceService _device;

  _ExecuteShellTool(this._device);

  @override
  String get name => 'execute_shell';

  @override
  String get description => '执行 Shell 命令。只能执行安全命令，不能操作 Solace 自身。';

  @override
  Map<String, dynamic> get parametersSchema => {
        'type': 'object',
        'properties': {
          'command': {
            'type': 'string',
            'description': 'Android shell 命令',
          },
        },
        'required': ['command'],
      };

  @override
  Set<String> get requiredPermissions => {'shizuku'};

  @override
  bool get isDestructive => true;

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    final command = args['command'] as String? ?? '';
    if (command.isEmpty) return ToolResult.error('命令为空');
    if (command.length > 500) return ToolResult.error('命令过长（最大 500 字符）');

    // 安全：检查命令是否包含危险操作
    final lower = command.toLowerCase();
    if (lower.contains('com.solace.solace') &&
        (lower.contains('force-stop') || lower.contains('kill') || lower.contains('stop') || lower.contains('rm ') || lower.contains('delete') || lower.contains('uninstall'))) {
      return ToolResult.error('安全限制：不能对 Solace 自身执行此操作');
    }

    // 阻止高危命令
    if (lower.contains('rm -rf') || lower.contains('dd if') || lower.contains('mkfs')) {
      return ToolResult.error('安全限制：此命令可能损坏系统，已拒绝执行');
    }

    final result = await _device.shellExec(command);
    if (!result.success) {
      return ToolResult.error('命令执行失败 (exit=${result.exitCode}): ${result.stderr}');
    }
    final output = result.stdout.isNotEmpty ? result.stdout : '(无输出)';
    return ToolResult.success(output, data: {
      'exitCode': result.exitCode,
      'stdout': result.stdout,
      'stderr': result.stderr,
    });
  }
}
