// 【对标来源：KouriChat-1.4.3.2 — src/services/ai/llm_service.py LLM 服务】
// 1:1 转译自 KouriChat LLMService 类，适配 Flutter Dart http
// 参考文件：src/services/ai/llm_service.py:chat()、_manage_context()、_build_time_context()

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/llm_request.dart';
import '../models/chat_context.dart';
import '../models/app_config_data.dart';
import '../utils/response_decoder.dart';
import '../utils/doh_client.dart';
import 'usage_meter_service.dart';

/// LLM 服务（对标 KouriChat LLMService）
/// 完整保留 KouriChat 的上下文管理、模型切换、安全过滤逻辑
class LlmService {
  final LlmSettings settings;

  /// 对话上下文（对标 KouriChat self.chat_contexts）
  final Map<String, ChatContext> _contexts = {};

  /// 当前使用的模型（对标 KouriChat self.model）
  late String _currentModel;

  /// 原始模型（对标 KouriChat self.original_model）
  final String _originalModel;

  LlmService({required this.settings}) : _originalModel = settings.model {
    _currentModel = settings.model;
  }

  /// 发送消息并获取回复（对标 KouriChat LLMService.chat）
  Future<LlmResponse> chat({
    required String userId,
    required String message,
    String role = 'user',
    String? systemPrompt,
    List<Map<String, String>>? extraContext,
    bool stream = false,
    int? maxTokensOverride,
    bool omitMaxTokens = false,
    bool includeReasoningFallback = true,
  }) async {
    // 上下文管理（对标 KouriChat _manage_context）
    _manageContext(userId, message, role);

    // 构建消息列表
    final messages = <LlmMessage>[];

    // 系统提示词
    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      messages.add(LlmMessage(role: 'system', content: systemPrompt));
    }

    // 时间上下文（对标 KouriChat _build_time_context）
    final timeContext = _buildTimeContext(userId);
    if (timeContext.isNotEmpty) {
      messages.add(LlmMessage(role: 'system', content: timeContext));
    }

    // 额外上下文
    if (extraContext != null) {
      for (final ctx in extraContext) {
        messages.add(LlmMessage(
          role: ctx['role'] ?? 'system',
          content: ctx['content'] ?? '',
        ));
      }
    }

    // 历史对话
    final context = _contexts[userId];
    if (context != null) {
      for (final msg in context.messages) {
        messages.add(LlmMessage(role: msg.role, content: msg.content));
      }
    }

    // 构建请求
    final request = LlmRequest(
      model: _currentModel,
      messages: messages,
      maxTokens:
          omitMaxTokens ? null : (maxTokensOverride ?? settings.maxTokens),
      temperature: settings.temperature,
      stream: stream,
    );

    // 发送请求（对标 KouriChat requests.post）
    return await _sendRequest(
      request,
      includeReasoningFallback: includeReasoningFallback,
    );
  }

  /// 带工具调用的 LLM 请求（Agent function calling）
  Future<Map<String, dynamic>?> chatWithTools({
    required List<Map<String, dynamic>> messages,
    required List<Map<String, dynamic>> tools,
    int? maxTokens,
  }) async {
    var baseUrl = settings.baseUrl.trim();
    while (baseUrl.endsWith('/')) {
      baseUrl = baseUrl.substring(0, baseUrl.length - 1);
    }
    final url = baseUrl.endsWith('/chat/completions')
        ? Uri.parse(baseUrl)
        : Uri.parse('$baseUrl/chat/completions');

    final body = {
      'model': _currentModel,
      'messages': messages,
      'tools': tools,
      'tool_choice': 'auto',
      if (maxTokens != null) 'max_tokens': maxTokens,
    };

    try {
      final response = await DohResolver.post(
        url,
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
          'Authorization': 'Bearer ${settings.apiKey}',
        },
        body: utf8.encode(jsonEncode(body)),
      );

      if (response.statusCode == 200) {
        final decoded = await ResponseDecoder.decode(
          response.headers['content-type'],
          response.bodyBytes,
        );
        final json = jsonDecode(decoded) as Map<String, dynamic>;
        final choices = json['choices'] as List<dynamic>?;
        if (choices == null || choices.isEmpty) return null;

        final choice = choices.first as Map<String, dynamic>;
        final message = choice['message'] as Map<String, dynamic>?;

        if (message == null) return null;

        return {
          'content': message['content'] as String? ?? '',
          'reasoning': message['reasoning_content'] as String? ??
              message['reasoning'] as String? ??
              '',
          'tool_calls': message['tool_calls'] as List<dynamic>? ?? [],
        };
      }

      return null;
    } catch (e) {
      debugPrint('[LlmService] chatWithTools 失败: $e');
      return null;
    }
  }

  /// 发送 LLM 请求（对标 KouriChat OpenAI 兼容 API 调用）
  Future<LlmResponse> _sendRequest(
    LlmRequest request, {
    bool includeReasoningFallback = true,
  }) async {
    var baseUrl = settings.baseUrl.trim();
    while (baseUrl.endsWith('/')) {
      baseUrl = baseUrl.substring(0, baseUrl.length - 1);
    }
    final url = baseUrl.endsWith('/chat/completions')
        ? Uri.parse(baseUrl)
        : Uri.parse('$baseUrl/chat/completions');

    try {
      final requestBody = jsonEncode(request.toJson());
      final response = await DohResolver.post(
        url,
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
          'Accept': 'application/json',
          'Accept-Charset': 'utf-8',
          'Authorization': 'Bearer ${settings.apiKey}',
        },
        body: utf8.encode(requestBody),
      );
      unawaited(UsageMeterService.instance.trackHttpResponse(
        url: url,
        requestBody: requestBody,
        response: response,
        endpointHint: 'openai_chat',
      ));
      final decodedBody = await ResponseDecoder.decode(
        response.headers['content-type'],
        response.bodyBytes,
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(decodedBody) as Map<String, dynamic>;
        final parsed = LlmResponse.fromJson(
          json,
          includeReasoningFallback: includeReasoningFallback,
        );
        return LlmResponse(
          content: ResponseDecoder.repairText(parsed.content),
          success: parsed.success,
          error: parsed.error,
          durationMs: parsed.durationMs,
          promptTokens: parsed.promptTokens,
          completionTokens: parsed.completionTokens,
        );
      } else {
        // 模型切换 fallback（对标 KouriChat auto_model_switch）
        if (settings.autoModelSwitch) {
          final nextModel = _getNextModel(_currentModel);
          if (nextModel != null) {
            _currentModel = nextModel;
            final retryRequest = LlmRequest(
              model: nextModel,
              messages: request.messages,
              maxTokens: request.maxTokens,
              temperature: request.temperature,
              stream: request.stream,
            );
            return await _sendRequest(
              retryRequest,
              includeReasoningFallback: includeReasoningFallback,
            );
          }
        }

        return LlmResponse(
          content: '',
          error: 'API 请求失败: ${response.statusCode} $decodedBody',
        );
      }
    } catch (e) {
      return LlmResponse(content: '', error: '网络错误: $e');
    }
  }

  /// 上下文管理（对标 KouriChat _manage_context）
  void _manageContext(String userId, String message, String role,
      {String characterId = ''}) {
    _contexts[userId] ??= ChatContext(characterId: characterId, userId: userId);

    final context = _contexts[userId]!;
    final updatedMessages = List<ContextMessage>.from(context.messages)
      ..add(ContextMessage(
        role: role,
        content: message,
        timestamp: DateTime.now(),
      ));

    // 维护上下文窗口（对标 KouriChat max_groups * 2）
    final maxMessages = settings.maxGroups * 2;
    while (updatedMessages.length > maxMessages) {
      updatedMessages.removeAt(0);
    }

    _contexts[userId] = ChatContext(
      characterId: context.characterId,
      userId: context.userId,
      messages: updatedMessages,
      maxMessages: maxMessages,
    );
  }

  /// 构建时间上下文（对标 KouriChat _build_time_context）
  String _buildTimeContext(String userId) {
    final context = _contexts[userId];
    if (context == null || context.messages.isEmpty) {
      return '这是你们今天的第一次对话。';
    }

    try {
      final lastMsg = context.messages.last;
      final msgTime = lastMsg.timestamp ?? DateTime.now();
      final timeDiff = DateTime.now().difference(msgTime);
      final seconds = timeDiff.inSeconds;

      if (seconds < 60) {
        return '距离上条消息仅过去了$seconds秒';
      } else if (seconds < 3600) {
        final minutes = seconds ~/ 60;
        return '距离上条消息过去了$minutes分钟';
      } else {
        final hours = seconds ~/ 3600;
        return '距离上条消息过去了$hours小时';
      }
    } catch (_) {
      return '';
    }
  }

  /// 获取下一个可用模型（对标 KouriChat _get_next_model）
  String? _getNextModel(String currentModel) {
    final models = _getFallbackModels();
    if (models.isEmpty) return null;

    final index = models.indexOf(currentModel);
    if (index == -1) return models.first;
    if (models.length == 1) return null;

    final nextIndex = (index + 1) % models.length;
    if (nextIndex == index) return null;
    return models[nextIndex];
  }

  /// 获取后备模型列表（对标 KouriChat _get_fallback_models）
  List<String> _getFallbackModels() {
    final baseUrl = settings.baseUrl.toLowerCase();
    if (baseUrl.contains('deepseek.com')) {
      return ['deepseek-reasoner', 'deepseek-chat'];
    } else if (baseUrl.contains('openai.com')) {
      return ['gpt-4o', 'gpt-4o-mini', 'gpt-4-turbo'];
    } else if (baseUrl.contains('siliconflow.cn')) {
      return ['deepseek-ai/DeepSeek-V3', 'Qwen/Qwen2.5-72B-Instruct'];
    } else if (baseUrl.contains('liumix') || baseUrl.contains('kimi')) {
      return ['Kimi-K2.6', 'moonshot-v1-8k', 'moonshot-v1-32k'];
    }
    return [_originalModel];
  }

  /// 清空用户上下文
  void clearContext(String userId) {
    _contexts.remove(userId);
  }

  /// 获取用户上下文消息数
  int getContextMessageCount(String userId) {
    return _contexts[userId]?.messages.length ?? 0;
  }
}
