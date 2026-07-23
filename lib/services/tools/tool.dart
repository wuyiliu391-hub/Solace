import 'dart:convert';
import 'package:flutter/foundation.dart';

/// 工具执行结果
class ToolResult {
  final bool success;
  final String message;
  final Map<String, dynamic>? data;
  final String? errorCode;
  final bool needsPermission;
  final String? permissionName;

  const ToolResult({
    required this.success,
    required this.message,
    this.data,
    this.errorCode,
    this.needsPermission = false,
    this.permissionName,
  });

  factory ToolResult.success(String message, {Map<String, dynamic>? data}) {
    return ToolResult(success: true, message: message, data: data);
  }

  factory ToolResult.error(String message, {String? errorCode, bool needsPermission = false, String? permissionName}) {
    return ToolResult(
      success: false,
      message: message,
      errorCode: errorCode,
      needsPermission: needsPermission,
      permissionName: permissionName,
    );
  }
}

/// 单次工具执行记录
class ToolExecutionRecord {
  final String toolName;
  final Map<String, dynamic> args;
  final ToolResult result;
  final DateTime startedAt;
  final DateTime endedAt;

  const ToolExecutionRecord({
    required this.toolName,
    required this.args,
    required this.result,
    required this.startedAt,
    required this.endedAt,
  });

  Duration get duration => endedAt.difference(startedAt);
}

/// 工具抽象
abstract class Tool {
  String get name;
  String get description;
  Map<String, dynamic> get parametersSchema;
  Set<String> get requiredPermissions;
  bool get isDestructive;

  Future<ToolResult> execute(Map<String, dynamic> args);
}

/// 工具包抽象
abstract class ToolPkg {
  String get name;
  String get description;
  List<Tool> get tools;
}

/// 工具调用
class ToolCall {
  final String name;
  final Map<String, dynamic> args;

  const ToolCall({required this.name, required this.args});

  factory ToolCall.fromOpenAI(Map<String, dynamic> call) {
    // function 字段可能是 Map<dynamic, dynamic>，需要安全转换
    final functionRaw = call['function'];
    Map<String, dynamic>? function;
    if (functionRaw is Map<String, dynamic>) {
      function = functionRaw;
    } else if (functionRaw is Map) {
      function = Map<String, dynamic>.from(functionRaw);
    }

    final name = function?['name'] as String? ?? '';
    final argumentsRaw = function?['arguments'];

    // arguments 可能是 String（标准 OpenAI 格式）或 Map（部分 API 直接返回对象）
    Map<String, dynamic> args = {};
    try {
      if (argumentsRaw is String) {
        args = Map<String, dynamic>.from(
            jsonDecode(argumentsRaw) as Map? ?? {});
      } else if (argumentsRaw is Map<String, dynamic>) {
        args = argumentsRaw;
      } else if (argumentsRaw is Map) {
        args = Map<String, dynamic>.from(argumentsRaw);
      }
    } catch (e) {
      debugPrint('[ToolCall] 解析参数失败: $e, arguments=$argumentsRaw');
    }
    return ToolCall(name: name, args: args);
  }

  static dynamic _jsonDecode(String s) {
    // 简单兼容：有些模型返回的 arguments 不是 JSON，而是类似 "key=value" 的字符串
    try {
      return _parseJsonLike(s);
    } catch (_) {
      return {};
    }
  }

  /// 兼容模型返回的伪 JSON：把 "key='value'" 转成 JSON
  static dynamic _parseJsonLike(String s) {
    s = s.trim();
    if (s.startsWith('{') && s.endsWith('}')) {
      return _parseJsonObject(s.substring(1, s.length - 1));
    }
    return {};
  }

  static Map<String, dynamic> _parseJsonObject(String s) {
    final result = <String, dynamic>{};
    final pairs = _splitTopLevel(s, ',');
    for (final pair in pairs) {
      final kv = _splitTopLevel(pair.trim(), ':');
      if (kv.length != 2) continue;
      final key = _stripQuotes(kv[0].trim());
      final value = _parseValue(kv[1].trim());
      result[key] = value;
    }
    return result;
  }

  static dynamic _parseValue(String s) {
    s = s.trim();
    if (s.startsWith('"') && s.endsWith('"')) {
      return s.substring(1, s.length - 1).replaceAll(r'\', '');
    }
    if (s.startsWith("'") && s.endsWith("'")) {
      return s.substring(1, s.length - 1).replaceAll(r'\', '');
    }
    if (s.toLowerCase() == 'true') return true;
    if (s.toLowerCase() == 'false') return false;
    if (s == 'null') return null;
    if (s.startsWith('{') && s.endsWith('}')) {
      return _parseJsonObject(s.substring(1, s.length - 1));
    }
    if (s.startsWith('[') && s.endsWith(']')) {
      final items = _splitTopLevel(s.substring(1, s.length - 1), ',');
      return items.map(_parseValue).toList();
    }
    final n = num.tryParse(s);
    if (n != null) return n;
    return s;
  }

  static String _stripQuotes(String s) {
    if ((s.startsWith('"') && s.endsWith('"')) ||
        (s.startsWith("'") && s.endsWith("'"))) {
      return s.substring(1, s.length - 1);
    }
    return s;
  }

  static List<String> _splitTopLevel(String s, String separator) {
    final result = <String>[];
    var depth = 0;
    var inQuotes = false;
    var quoteChar = '';
    var current = '';
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      if (inQuotes) {
        if (c == quoteChar) {
          inQuotes = false;
        }
        current += c;
      } else {
        if (c == '"' || c == "'") {
          inQuotes = true;
          quoteChar = c;
          current += c;
        } else if (c == '{' || c == '[' || c == '(') {
          depth++;
          current += c;
        } else if (c == '}' || c == ']' || c == ')') {
          depth--;
          current += c;
        } else if (c == separator && depth == 0) {
          result.add(current.trim());
          current = '';
        } else {
          current += c;
        }
      }
    }
    if (current.isNotEmpty) result.add(current.trim());
    return result;
  }
}

/// Agent Loop 执行结果
class AgentLoopResult {
  final String finalContent;
  final String reasoning;
  final List<ToolExecutionRecord> executions;
  final bool success;
  final String? error;

  const AgentLoopResult({
    required this.finalContent,
    this.reasoning = '',
    this.executions = const [],
    this.success = true,
    this.error,
  });
}

/// Agent Loop 单步回调
class AgentStep {
  final int step;
  final String toolName;
  final Map<String, dynamic> args;
  final String status;
  final String? result;

  const AgentStep({
    required this.step,
    required this.toolName,
    required this.args,
    required this.status,
    this.result,
  });
}
