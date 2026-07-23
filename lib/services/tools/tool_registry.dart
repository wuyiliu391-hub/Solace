import 'package:flutter/foundation.dart';
import 'tool.dart';

/// 工具注册表
///
/// 维护所有可用工具包和工具，提供 OpenAI function calling 格式的工具描述。
class ToolRegistry {
  final List<ToolPkg> _packages = [];
  final Map<String, Tool> _toolByName = {};

  /// 注册工具包
  void register(ToolPkg pkg) {
    _packages.add(pkg);
    for (final tool in pkg.tools) {
      if (_toolByName.containsKey(tool.name)) {
        debugPrint('[ToolRegistry] 警告：工具 ${tool.name} 重复注册');
      }
      _toolByName[tool.name] = tool;
    }
    debugPrint('[ToolRegistry] 已注册 ${pkg.name}，共 ${pkg.tools.length} 个工具');
  }

  /// 查找工具
  Tool? findTool(String name) => _toolByName[name];

  /// 获取所有工具的 OpenAI 格式
  List<Map<String, dynamic>> toOpenAIFormat() {
    final result = <Map<String, dynamic>>[];
    for (final tool in _toolByName.values) {
      result.add({
        'type': 'function',
        'function': {
          'name': tool.name,
          'description': tool.description,
          'parameters': tool.parametersSchema,
        },
      });
    }
    return result;
  }

  /// 获取工具描述文本（用于非 function calling 模型的提示）
  String toDescriptionText() {
    final buffer = StringBuffer();
    for (final pkg in _packages) {
      buffer.writeln('## ${pkg.name}');
      buffer.writeln(pkg.description);
      for (final tool in pkg.tools) {
        buffer.writeln('');
        buffer.writeln('- ${tool.name}: ${tool.description}');
        buffer.writeln('  参数：${_schemaToText(tool.parametersSchema)}');
      }
      buffer.writeln('');
    }
    return buffer.toString().trim();
  }

  String _schemaToText(Map<String, dynamic> schema) {
    final properties = schema['properties'] as Map<String, dynamic>?;
    if (properties == null) return '无';
    final required = (schema['required'] as List<dynamic>?)?.cast<String>().toSet() ?? <String>{};
    final parts = properties.entries.map((e) {
      final key = e.key;
      final prop = e.value as Map<String, dynamic>;
      final type = prop['type'] as String? ?? 'any';
      final desc = prop['description'] as String? ?? '';
      final req = required.contains(key) ? '必填' : '可选';
      return '$key($type, $req): $desc';
    }).toList();
    return parts.join('; ');
  }

  /// 所有工具数量
  int get toolCount => _toolByName.length;

  /// 所有工具包
  List<ToolPkg> get packages => List.unmodifiable(_packages);
}
