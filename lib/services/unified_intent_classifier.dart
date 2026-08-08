import 'dart:convert';

import '../models/chat_message.dart';
import 'llm_service.dart';
import 'recent_tool_context.dart';
import 'tools/deterministic_device_router.dart';
import 'tools/tool_registry.dart';

enum UnifiedIntentKind {
  conversation,
  directTool,
  continueTool,
  clarificationRequired,
  notAllowed,
}

class UnifiedIntentResult {
  final UnifiedIntentKind kind;
  final String? toolName;
  final Map<String, dynamic> args;
  final double confidence;
  final String reason;
  final bool isReadOnly;

  const UnifiedIntentResult({
    required this.kind,
    this.toolName,
    this.args = const {},
    this.confidence = 0,
    this.reason = '',
    this.isReadOnly = false,
  });

  const UnifiedIntentResult.conversation({String reason = ''})
      : this(kind: UnifiedIntentKind.conversation, reason: reason);

  const UnifiedIntentResult.clarificationRequired({String reason = ''})
      : this(
            kind: UnifiedIntentKind.clarificationRequired,
            reason: reason,
          );

  const UnifiedIntentResult.notAllowed({String reason = ''})
      : this(kind: UnifiedIntentKind.notAllowed, reason: reason);
}

/// 统一意图分类器：替代分散的 DeviceIntentRouter + ToolIntentPlanner +
/// RecentToolContext 续接识别，用一次 LLM 调用同时完成意图判断、工具选择和参数提取。
class UnifiedIntentClassifier {
  static const _confidenceThreshold = 0.7;

  /// 只读工具：允许直接执行，无需用户确认
  static const readOnlyTools = {
    'get_battery_info',
    'get_notifications',
    'get_notification_count',
    'get_current_app',
    'get_installed_apps',
    'get_app_usage_time',
    'get_processes',
    'take_screenshot',
  };

  final LlmService llm;
  final ToolRegistry registry;

  const UnifiedIntentClassifier({required this.llm, required this.registry});

  /// 统一分类入口
  ///
  /// 1. 快速路径：正则确定性匹配 → directTool（零 LLM 开销）
  /// 2. 快速路径：续接识别 → continueTool（零 LLM 开销）
  /// 3. LLM 路径：一次调用完成意图判断 + 工具选择 + 参数提取
  Future<UnifiedIntentResult> classify({
    required String message,
    required List<ChatMessage> recentMessages,
    RecentToolContext? recentTool,
  }) async {
    final text = message.trim();
    if (text.isEmpty) {
      return const UnifiedIntentResult.conversation(reason: 'empty');
    }

    // ── 快速路径 1：确定性正则匹配 ──
    final deterministic = DeterministicDeviceRouter.match(text);
    if (deterministic != null) {
      final isReadOnly = readOnlyTools.contains(deterministic.toolName);
      return UnifiedIntentResult(
        kind: UnifiedIntentKind.directTool,
        toolName: deterministic.toolName,
        args: deterministic.args,
        confidence: 1.0,
        reason: 'deterministic',
        isReadOnly: isReadOnly,
      );
    }

    // ── 快速路径 2：续接识别 ──
    if (recentTool != null &&
        recentTool.isUsableAt(DateTime.now()) &&
        RecentToolContext.isContinuationRequest(text)) {
      return UnifiedIntentResult(
        kind: UnifiedIntentKind.continueTool,
        toolName: recentTool.toolName,
        args: recentTool.args,
        confidence: 1.0,
        reason: 'continuation',
        isReadOnly: recentTool.isReadOnly,
      );
    }

    // ── LLM 路径 ──
    return await _classifyWithLlm(
      message: text,
      recentMessages: recentMessages,
      recentTool: recentTool,
    );
  }

  Future<UnifiedIntentResult> _classifyWithLlm({
    required String message,
    required List<ChatMessage> recentMessages,
    RecentToolContext? recentTool,
  }) async {
    final response = await llm.chat(
      userId: 'unified_intent_classifier',
      message: message,
      stream: false,
      maxTokensOverride: 360,
      includeReasoningFallback: false,
      systemPrompt: _buildPrompt(recentMessages, recentTool),
    );

    if (!response.success || response.content.trim().isEmpty) {
      return const UnifiedIntentResult.conversation(reason: 'llm_unavailable');
    }

    final decision = _parseResponse(response.content);
    return _validate(decision, recentTool);
  }

  UnifiedIntentResult _validate(
    UnifiedIntentResult result,
    RecentToolContext? recentTool,
  ) {
    // conversation / clarificationRequired / notAllowed 直接放行
    if (result.kind == UnifiedIntentKind.conversation ||
        result.kind == UnifiedIntentKind.clarificationRequired ||
        result.kind == UnifiedIntentKind.notAllowed) {
      return result;
    }

    final tool = result.toolName;

    // 工具不存在 → conversation
    if (tool == null || registry.findTool(tool) == null) {
      return const UnifiedIntentResult.conversation(reason: 'unknown_tool');
    }

    // 置信度不足 → conversation
    if (result.confidence < _confidenceThreshold) {
      return const UnifiedIntentResult.conversation(reason: 'low_confidence');
    }

    // 非只读工具 → 需要澄清
    if (!readOnlyTools.contains(tool)) {
      return const UnifiedIntentResult.clarificationRequired(
        reason: 'non_read_only_tool',
      );
    }

    // 工具的 isDestructive 标记也检查一下
    if (registry.findTool(tool)!.isDestructive) {
      return const UnifiedIntentResult.clarificationRequired(
        reason: 'destructive_tool',
      );
    }

    // 续接必须与最近工具一致
    if (result.kind == UnifiedIntentKind.continueTool) {
      if (recentTool == null ||
          !recentTool.isReadOnly ||
          tool != recentTool.toolName) {
        return const UnifiedIntentResult.conversation(
          reason: 'invalid_continuation',
        );
      }
    }

    return result;
  }

  UnifiedIntentResult _parseResponse(String content) {
    final match = RegExp(r'\{[\s\S]*\}').firstMatch(content.trim());
    if (match == null) {
      return const UnifiedIntentResult.conversation(reason: 'invalid_json');
    }
    try {
      final json = jsonDecode(match.group(0)!) as Map<String, dynamic>;
      return _resultFromJson(json);
    } catch (_) {
      return const UnifiedIntentResult.conversation(reason: 'invalid_json');
    }
  }

  UnifiedIntentResult _resultFromJson(Map<String, dynamic> json) {
    final rawKind = json['kind']?.toString() ?? 'conversation';
    final kind = UnifiedIntentKind.values.firstWhere(
      (v) => v.name == rawKind,
      orElse: () => UnifiedIntentKind.conversation,
    );
    final rawTool = json['tool']?.toString().trim() ?? '';
    final rawArgs = json['args'];
    Map<String, dynamic> args;
    try {
      if (rawArgs is Map) {
        args = _safeCastMap(rawArgs);
      } else {
        args = <String, dynamic>{};
      }
    } catch (_) {
      args = <String, dynamic>{};
    }
    return UnifiedIntentResult(
      kind: kind,
      toolName: rawTool.isEmpty ? null : rawTool,
      args: args,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
      reason: json['reason']?.toString() ?? '',
      isReadOnly: json['is_read_only'] == true,
    );
  }

  /// Safely cast a map (potentially nested) to Map<String, dynamic>.
  Map<String, dynamic> _safeCastMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) {
      return raw.map((key, value) {
        if (value is Map) {
          return MapEntry(key.toString(), _safeCastMap(value));
        }
        if (value is List) {
          return MapEntry(key.toString(), _safeCastList(value));
        }
        return MapEntry(key.toString(), value);
      });
    }
    return <String, dynamic>{};
  }

  List<dynamic> _safeCastList(List<dynamic> list) {
    return list.map((item) {
      if (item is Map) return _safeCastMap(item);
      if (item is List) return _safeCastList(item);
      return item;
    }).toList();
  }

  String _buildPrompt(
    List<ChatMessage> messages,
    RecentToolContext? recentTool,
  ) {
    final history = messages
        .where((m) => !m.isHidden && !m.isGhost)
        .take(6)
        .map((m) => '${m.isUser ? '用户' : '角色'}：${m.content}')
        .join('\n');

    final tools = readOnlyTools
        .where((name) => registry.findTool(name) != null)
        .map((name) {
      final tool = registry.findTool(name)!;
      final params = _schemaBrief(tool.parametersSchema);
      return '$name: ${tool.description}${params.isNotEmpty ? ' ($params)' : ''}';
    }).join('\n');

    final recentCtx = recentTool == null
        ? ''
        : '\n最近设备查询：${recentTool.toolName}(${recentTool.args.isEmpty ? '无参数' : recentTool.args})，结果：${recentTool.result}。';

    return '''你是意图分类器。只输出一个 JSON，不要对话。
判断用户消息属于哪种意图，如果是工具请求则选择工具并提取参数。

意图类型：
- conversation：普通聊天、情绪表达、剧情、转述、假设、否定请求
- directTool：明确的设备查询或操作请求
- continueTool：续接上次设备查询（如"再看一次""刷新一下"），仅当最近有设备查询时可用
- clarificationRequired：用户请求了非只读操作（如删除、发送、安装、Shell、UI操作），需要确认
- notAllowed：危险或不允许的操作

只允许选择以下只读工具，其他工具一律返回 clarificationRequired：
$tools
$recentCtx
最近对话：
$history

输出格式（仅 JSON）：
{"kind":"conversation|directTool|continueTool|clarificationRequired|notAllowed","tool":"工具名或空字符串","args":{},"confidence":0.0-1.0,"reason":"简短原因","is_read_only":true/false}''';
  }

  String _schemaBrief(Map<String, dynamic> schema) {
    final rawProps = schema['properties'];
    if (rawProps is! Map || rawProps.isEmpty) return '';
    final required =
        (schema['required'] as List<dynamic>?)?.cast<String>().toSet() ??
            <String>{};
    return rawProps.keys.map((key) {
      final req = required.contains(key.toString()) ? '必填' : '可选';
      return '${key.toString()}($req)';
    }).join(', ');
  }
}
