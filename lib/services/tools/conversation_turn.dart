import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'tool.dart';
import '../../models/chat_message.dart';

/// 对话回合类型，对标 Operit PromptTurnKind
///
/// 工具调用不是聊天的分支，而是对话协议里的一种语法元素。
/// SYSTEM/USER/ASSISTANT 是常规角色，TOOL_CALL/TOOL_RESULT 是结构化工具回合。
enum ConversationTurnKind {
  system,
  user,
  assistant,
  toolCall,
  toolResult,
  summary,
}

/// 单个对话回合，持久化到历史并参与 LLM 上下文构建
class ConversationTurn {
  final ConversationTurnKind kind;
  final String content;
  final String? toolName;
  final Map<String, dynamic> metadata;
  final DateTime createdAt;

  const ConversationTurn({
    required this.kind,
    required this.content,
    this.toolName,
    this.metadata = const {},
    required this.createdAt,
  });

  /// 从 ChatMessage 角色字符串推断 TurnKind
  static ConversationTurnKind kindFromRole(String role) {
    switch (role.trim().toLowerCase()) {
      case 'system':
        return ConversationTurnKind.system;
      case 'user':
        return ConversationTurnKind.user;
      case 'assistant':
      case 'ai':
        return ConversationTurnKind.assistant;
      case 'tool':
      case 'tool_result':
        return ConversationTurnKind.toolResult;
      case 'tool_call':
      case 'tool_use':
        return ConversationTurnKind.toolCall;
      case 'summary':
        return ConversationTurnKind.summary;
      default:
        return ConversationTurnKind.user;
    }
  }

  /// 转换为 LLM API 需要的消息格式
  Map<String, dynamic> toLlmMessage() {
    switch (kind) {
      case ConversationTurnKind.system:
        return {'role': 'system', 'content': content};
      case ConversationTurnKind.user:
        return {'role': 'user', 'content': content};
      case ConversationTurnKind.assistant:
        return {'role': 'assistant', 'content': content};
      case ConversationTurnKind.toolCall:
        // tool_call 回合：assistant 消息里带 tool_calls
        return {
          'role': 'assistant',
          'content': content,
          'tool_calls': metadata['tool_calls'] ?? [],
        };
      case ConversationTurnKind.toolResult:
        // tool_result 回合：tool 角色消息
        return {
          'role': 'tool',
          'tool_call_id': metadata['tool_call_id'] ?? toolName ?? 'unknown',
          'name': toolName ?? 'unknown',
          'content': content,
        };
      case ConversationTurnKind.summary:
        return {'role': 'system', 'content': '[Summary] $content'};
    }
  }

  /// 从 LLM API 响应构建 assistant turn
  static ConversationTurn assistantFromResponse(
    String content, {
    String reasoning = '',
    List<dynamic> toolCalls = const [],
  }) {
    return ConversationTurn(
      kind: toolCalls.isNotEmpty
          ? ConversationTurnKind.toolCall
          : ConversationTurnKind.assistant,
      content: content,
      metadata: {
        if (reasoning.isNotEmpty) 'reasoning': reasoning,
        if (toolCalls.isNotEmpty) 'tool_calls': toolCalls,
      },
      createdAt: DateTime.now(),
    );
  }

  /// 从工具执行记录构建 tool_result turn
  static ConversationTurn toolResultFromExecution(
    ToolExecutionRecord record, {
    String? toolCallId,
  }) {
    return ConversationTurn(
      kind: ConversationTurnKind.toolResult,
      content: record.result.message,
      toolName: record.toolName,
      metadata: {
        'tool_call_id': toolCallId ?? record.toolName,
        'success': record.result.success,
        'error_code': record.result.errorCode,
        'duration_ms': record.duration.inMilliseconds,
      },
      createdAt: DateTime.now(),
    );
  }

  /// 复制并替换内容
  ConversationTurn withContent(String newContent) {
    return ConversationTurn(
      kind: kind,
      content: newContent,
      toolName: toolName,
      metadata: metadata,
      createdAt: createdAt,
    );
  }

  /// 序列化到 JSON（用于持久化）
  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'content': content,
        'tool_name': toolName,
        'metadata': metadata,
        'created_at': createdAt.toIso8601String(),
      };

  /// 从 JSON 反序列化
  factory ConversationTurn.fromJson(Map<String, dynamic> json) {
    return ConversationTurn(
      kind: ConversationTurnKind.values.byName(
        (json['kind'] as String? ?? 'user').toLowerCase(),
      ),
      content: json['content'] as String? ?? '',
      toolName: json['tool_name'] as String?,
      metadata: (json['metadata'] as Map<String, dynamic>?) ?? const {},
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

/// 从 ChatMessage 列表构建 ConversationTurn 列表
/// 将 ChatMessage 的 system 类型消息和工具 trace 转换为结构化 Turn
List<ConversationTurn> buildTurnsFromChatMessages(
  List<ChatMessage> messages, {
  required String systemPrompt,
  required String? characterPrompt,
  required String toolDescription,
}) {
  final turns = <ConversationTurn>[];

  // 系统提示作为第一个 turn
  turns.add(ConversationTurn(
    kind: ConversationTurnKind.system,
    content: systemPrompt,
    createdAt: messages.isNotEmpty ? messages.first.createdAt : DateTime.now(),
  ));

  // 工具描述注入（作为系统提示的一部分，不单独发请求）
  if (toolDescription.isNotEmpty) {
    turns.add(ConversationTurn(
      kind: ConversationTurnKind.system,
      content: toolDescription,
      createdAt: DateTime.now(),
    ));
  }

  // 角色提示
  if (characterPrompt != null && characterPrompt.isNotEmpty) {
    turns.add(ConversationTurn(
      kind: ConversationTurnKind.system,
      content: characterPrompt,
      createdAt: DateTime.now(),
    ));
  }

  // 转换历史消息
  for (final msg in messages) {
    if (msg.isHidden || msg.isGhost) continue;

    if (msg.isSystem) {
      // 系统消息可能是工具 trace
      if (msg.metadata?['isToolTrace'] == true) {
        // 工具 trace 转换为 tool_result turns
        final trace = msg.metadata?['toolTrace'] as List<dynamic>?;
        if (trace != null) {
          for (final entry in trace) {
            final e = entry as Map<String, dynamic>;
            turns.add(ConversationTurn(
              kind: ConversationTurnKind.toolResult,
              content: e['result'] as String? ?? '',
              toolName: e['tool'] as String?,
              metadata: {
                'success': e['success'] ?? false,
                'from_trace': true,
              },
              createdAt: msg.createdAt,
            ));
          }
        }
      } else {
        turns.add(ConversationTurn(
          kind: ConversationTurnKind.system,
          content: msg.content,
          createdAt: msg.createdAt,
        ));
      }
    } else if (msg.isUser) {
      turns.add(ConversationTurn(
        kind: ConversationTurnKind.user,
        content: msg.content,
        createdAt: msg.createdAt,
      ));
    } else {
      // AI 消息
      turns.add(ConversationTurn(
        kind: ConversationTurnKind.assistant,
        content: msg.content,
        createdAt: msg.createdAt,
      ));
    }
  }

  return turns;
}

/// 合并相邻同角色回合（减少 token 消耗）
List<ConversationTurn> mergeAdjacentTurns(List<ConversationTurn> turns) {
  if (turns.isEmpty) return turns;
  final result = <ConversationTurn>[turns.first];
  for (var i = 1; i < turns.length; i++) {
    final prev = result.last;
    final curr = turns[i];
    if (prev.kind == curr.kind &&
        prev.kind != ConversationTurnKind.toolCall &&
        prev.kind != ConversationTurnKind.toolResult) {
      result[result.length - 1] = ConversationTurn(
        kind: prev.kind,
        content: '${prev.content}\n\n${curr.content}',
        toolName: prev.toolName,
        metadata: {...prev.metadata, ...curr.metadata},
        createdAt: prev.createdAt,
      );
    } else {
      result.add(curr);
    }
  }
  return result;
}

/// 处理状态，对标 Operit InputProcessingState
enum ToolProcessingState {
  idle,
  preparing,
  connecting,
  receiving,
  executingTool,
  processingToolResult,
  completed,
  error,
}

/// 工具调用从 assistant 输出中提取的原始表示
class ExtractedToolCall {
  final String name;
  final Map<String, dynamic> args;
  final String rawText;

  const ExtractedToolCall({
    required this.name,
    required this.args,
    required this.rawText,
  });
}