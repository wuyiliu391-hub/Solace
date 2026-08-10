import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../device_service.dart';
import '../../workspace_service.dart';
import '../tool.dart';

class WorkspaceToolPkg extends ToolPkg {
  final WorkspaceService workspace;
  final String chatId;

  WorkspaceToolPkg({required this.workspace, required this.chatId});

  @override
  String get name => '工作区与代码';

  @override
  String get description => '读取、写入、精确编辑当前聊天绑定的本地工作区，并运行受限项目命令。';

  @override
  List<Tool> get tools => [
        _ListDirectoryTool(workspace, chatId),
        _ReadFileTool(workspace, chatId),
        _WriteFileTool(workspace, chatId),
        _EditFileTool(workspace, chatId),
        _RunCommandTool(workspace, chatId),
        _RollbackFileTool(workspace, chatId),
      ];
}

abstract class _WorkspaceTool extends Tool {
  final WorkspaceService workspace;
  final String chatId;

  _WorkspaceTool(this.workspace, this.chatId);

  @override
  Set<String> get requiredPermissions => const {};

  @override
  bool get isDestructive => false;

  bool get supported => !kIsWeb;

  ToolResult unsupported() => ToolResult.error(
        '当前平台不支持工作区工具。',
        errorCode: 'WORKSPACE_UNSUPPORTED',
      );
}

class _RollbackFileTool extends _WorkspaceTool {
  _RollbackFileTool(super.workspace, super.chatId);

  @override
  String get name => 'rollback_file';

  @override
  String get description => '使用最近一次写入或编辑生成的工作区内快照回滚文件。';

  @override
  Map<String, dynamic> get parametersSchema => {
        'type': 'object',
        'properties': {
          'path': {'type': 'string'},
          'snapshot_id': {
            'type': 'string',
            'description': '写入/编辑结果中返回的不透明快照 ID，不是文件路径',
          },
        },
        'required': ['path', 'snapshot_id'],
      };

  @override
  Set<String> get requiredPermissions => {'workspace_write'};

  @override
  bool get isDestructive => true;

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    if (!supported) return unsupported();
    try {
      await workspace.rollback(
        chatId,
        args['path']?.toString() ?? '',
        args['snapshot_id']?.toString() ?? '',
      );
      return ToolResult.success('已回滚 ${args['path']}');
    } catch (e) {
      return ToolResult.error('$e', errorCode: 'ROLLBACK_FAILED');
    }
  }
}

class _ListDirectoryTool extends _WorkspaceTool {
  _ListDirectoryTool(super.workspace, super.chatId);

  @override
  String get name => 'list_directory';

  @override
  String get description => '列出当前工作区或指定子目录中的文件和文件夹。';

  @override
  Map<String, dynamic> get parametersSchema => {
        'type': 'object',
        'properties': {
          'path': {
            'type': 'string',
            'description': '相对工作区根目录的目录路径，留空表示工作区根目录',
          },
          'max_entries': {'type': 'integer', 'minimum': 1, 'maximum': 200},
        },
      };

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    if (!supported) return unsupported();
    try {
      final path = args['path']?.toString().trim() ?? '';
      final requestedMax = int.tryParse(args['max_entries']?.toString() ?? '');
      final maxEntries = (requestedMax ?? 200).clamp(1, 200);
      final entries = await workspace.listDirectory(
        chatId,
        path,
        maxEntries: maxEntries,
      );
      final lines = entries.map((entry) {
        final prefix = entry['type'] == 'directory' ? '[目录]' : '[文件]';
        final size = entry['size'] == null ? '' : ' (${entry['size']} bytes)';
        return '$prefix ${entry['name']}$size';
      }).join('\n');
      return ToolResult.success(
        lines.isEmpty ? '目录为空。' : lines,
        data: {'path': path, 'entries': entries},
      );
    } catch (e) {
      return ToolResult.error('$e', errorCode: 'LIST_DIRECTORY_FAILED');
    }
  }
}

class _ReadFileTool extends _WorkspaceTool {
  _ReadFileTool(super.workspace, super.chatId);

  @override
  String get name => 'read_file';

  @override
  String get description => '读取工作区内的文本文件。';

  @override
  Map<String, dynamic> get parametersSchema => _pathSchema();

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    if (!supported) return unsupported();
    try {
      final path = args['path']?.toString().trim() ?? '';
      final content = await workspace.read(chatId, path);
      return ToolResult.success(content, data: {'path': path});
    } catch (e) {
      return ToolResult.error('$e', errorCode: 'READ_FAILED');
    }
  }
}

class _WriteFileTool extends _WorkspaceTool {
  _WriteFileTool(super.workspace, super.chatId);

  @override
  String get name => 'write_file';

  @override
  String get description => '创建或完整覆盖工作区内的文本文件；已有文件会先生成快照。';

  @override
  Map<String, dynamic> get parametersSchema => {
        ..._pathSchema(),
        'properties': {
          'path': {'type': 'string'},
          'content': {'type': 'string'},
        },
        'required': ['path', 'content'],
      };

  @override
  Set<String> get requiredPermissions => {'workspace_write'};

  @override
  bool get isDestructive => true;

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    if (!supported) return unsupported();
    try {
      final path = args['path']?.toString().trim() ?? '';
      final content = args['content']?.toString() ?? '';
      final result = await workspace.write(chatId, path, content);
      return ToolResult.success('已写入 $path', data: result);
    } catch (e) {
      return ToolResult.error('$e', errorCode: 'WRITE_FAILED');
    }
  }
}

class _EditFileTool extends _WorkspaceTool {
  _EditFileTool(super.workspace, super.chatId);

  @override
  String get name => 'edit_file';

  @override
  String get description => '用唯一原文片段精确修改工作区内的文件；修改前会生成快照。';

  @override
  Map<String, dynamic> get parametersSchema => {
        'type': 'object',
        'properties': {
          'path': {'type': 'string'},
          'old_text': {'type': 'string'},
          'new_text': {'type': 'string'},
        },
        'required': ['path', 'old_text', 'new_text'],
      };

  @override
  Set<String> get requiredPermissions => {'workspace_write'};

  @override
  bool get isDestructive => true;

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    if (!supported) return unsupported();
    try {
      final result = await workspace.edit(
        chatId,
        args['path']?.toString() ?? '',
        args['old_text']?.toString() ?? '',
        args['new_text']?.toString() ?? '',
      );
      return ToolResult.success('已精确修改 ${result['path']}', data: result);
    } catch (e) {
      return ToolResult.error('$e', errorCode: 'EDIT_FAILED');
    }
  }
}

class _RunCommandTool extends _WorkspaceTool {
  _RunCommandTool(super.workspace, super.chatId);

  @override
  String get name => 'run_command';

  @override
  String get description =>
      '在工作区根目录运行项目命令，例如 flutter test、dart analyze 或 npm test。';

  @override
  Map<String, dynamic> get parametersSchema => {
        'type': 'object',
        'properties': {
          'command': {'type': 'string'},
        },
        'required': ['command'],
      };

  @override
  Set<String> get requiredPermissions => {'workspace_command'};

  @override
  bool get isDestructive => true;

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    if (!supported) return unsupported();
    final root = workspace.directoryForChat(chatId);
    if (root == null) {
      return ToolResult.error('当前聊天尚未绑定工作区。', errorCode: 'NO_WORKSPACE');
    }
    final command = args['command']?.toString().trim() ?? '';
    if (command.isEmpty || command.length > 500) {
      return ToolResult.error('命令为空或过长。', errorCode: 'INVALID_COMMAND');
    }
    if (Platform.isAndroid && !DeviceService().isShizukuReady) {
      await DeviceService().getShizukuStatus();
      if (!DeviceService().isShizukuReady) {
        return ToolResult.error('Android 工作区命令需要 Shizuku 已启动并授权。',
            errorCode: 'NO_SHIZUKU');
      }
    }
    if (_looksDangerous(command)) {
      return ToolResult.error('命令包含高风险操作，已拒绝执行。',
          errorCode: 'DANGEROUS_COMMAND');
    }
    try {
      final parts = _splitCommand(command);
      if (parts.isEmpty) {
        return ToolResult.error('命令为空。', errorCode: 'INVALID_COMMAND');
      }
      final result = Platform.isAndroid
          ? await DeviceService()
              .shellExec('cd ${_quote(root.path)} && ${_quoteCommand(parts)}')
          : await _runDesktop(parts, root.path);
      final output = '${result.stdout}${result.stderr}'.trim();
      return result.exitCode == 0
          ? ToolResult.success(
              output.isEmpty ? '命令执行完成。' : output,
              data: {'exitCode': result.exitCode},
            )
          : ToolResult.error(
              output.isEmpty ? 'exit=${result.exitCode}' : output,
              errorCode: 'COMMAND_FAILED',
            );
    } on TimeoutException {
      return ToolResult.error('命令执行超时。', errorCode: 'TIMEOUT');
    } catch (e) {
      return ToolResult.error('$e', errorCode: 'COMMAND_FAILED');
    }
  }

  Future<ShellResult> _runDesktop(List<String> parts, String root) async {
    final result = await Process.run(
      parts.first,
      parts.skip(1).toList(),
      workingDirectory: root,
    ).timeout(const Duration(minutes: 5));
    return ShellResult(
      success: result.exitCode == 0,
      stdout: result.stdout.toString(),
      stderr: result.stderr.toString(),
      exitCode: result.exitCode,
    );
  }

  String _quote(String value) => "'${value.replaceAll("'", "'\\''")}'";

  String _quoteCommand(List<String> parts) => parts.map(_quote).join(' ');

  bool _looksDangerous(String command) => RegExp(
        r'(^|\s)(rm\s+-rf|del\s+/|format\s+|shutdown|reboot|diskpart|:\s*\(\)|git\s+reset\s+--hard)(\s|$)',
        caseSensitive: false,
      ).hasMatch(command);

  List<String> _splitCommand(String command) =>
      RegExp(r'"[^"]*"|\S+').allMatches(command).map((m) {
        final value = m.group(0)!;
        return value.length >= 2 && value.startsWith('"') && value.endsWith('"')
            ? value.substring(1, value.length - 1)
            : value;
      }).toList();
}

Map<String, dynamic> _pathSchema() => {
      'type': 'object',
      'properties': {
        'path': {'type': 'string', 'description': '相对工作区根目录的文件路径'},
      },
      'required': ['path'],
    };
