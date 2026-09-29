// 【对标来源：KouriChat-1.4.3.2 — src/services/ai/llm_service.py LLM 请求/响应结构】
// 1:1 转译自 KouriChat LLM 请求参数和响应格式
// 参考文件：src/services/ai/llm_service.py:chat()、llm/api.py

/// LLM 请求（对标 KouriChat LLMService.chat() 参数）
class LlmRequest {
  /// 消息列表（对标 messages: [{role, content}]）
  final List<LlmMessage> messages;

  /// 模型名称（对标 config.model）
  final String model;

  /// 温度（对标 config.temperature）
  final double temperature;

  /// 最大 token（对标 config.max_tokens）
  final int? maxTokens;

  /// Top P（对标 config.top_p）
  final double topP;

  /// 频率惩罚（对标 config.frequency_penalty）
  final double frequencyPenalty;

  /// 存在惩罚（对标 config.presence_penalty）
  final double presencePenalty;

  /// 是否流式（对标 stream）
  final bool stream;

  /// 停止序列（对标 stop）
  final List<String>? stop;

  /// 工具定义（Agent function calling）
  final List<Map<String, dynamic>>? tools;

  const LlmRequest({
    required this.messages,
    this.model = '',
    this.temperature = 0.7,
    this.maxTokens = 2048,
    this.topP = 1.0,
    this.frequencyPenalty = 0.0,
    this.presencePenalty = 0.0,
    this.stream = true,
    this.stop,
    this.tools,
  });

  Map<String, dynamic> toJson() => {
        'messages': messages.map((e) => e.toJson()).toList(),
        'model': model,
        'temperature': temperature,
        if (maxTokens != null) 'max_tokens': maxTokens,
        'top_p': topP,
        'frequency_penalty': frequencyPenalty,
        'presence_penalty': presencePenalty,
        'stream': stream,
        if (stop != null) 'stop': stop,
        if (tools != null && tools!.isNotEmpty) 'tools': tools,
      };

  factory LlmRequest.fromJson(Map<String, dynamic> json) {
    return LlmRequest(
      messages: (json['messages'] as List<dynamic>?)
              ?.map((e) => LlmMessage.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      model: json['model'] as String? ?? '',
      temperature: (json['temperature'] as num?)?.toDouble() ?? 0.7,
      maxTokens: json['max_tokens'] as int? ?? 2048,
      topP: (json['top_p'] as num?)?.toDouble() ?? 1.0,
      frequencyPenalty: (json['frequency_penalty'] as num?)?.toDouble() ?? 0.0,
      presencePenalty: (json['presence_penalty'] as num?)?.toDouble() ?? 0.0,
      stream: json['stream'] as bool? ?? true,
      stop: (json['stop'] as List<dynamic>?)?.cast<String>(),
    );
  }
}

/// LLM 消息（对标 KouriChat {role, content}）
class LlmMessage {
  final String role;
  final String? content;
  final List<Map<String, dynamic>>? toolCalls;
  final String? toolCallId;

  const LlmMessage({
    required this.role,
    this.content,
    this.toolCalls,
    this.toolCallId,
  });

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{'role': role};
    if (content != null) json['content'] = content;
    if (toolCalls != null) json['tool_calls'] = toolCalls;
    if (toolCallId != null) json['tool_call_id'] = toolCallId;
    return json;
  }

  factory LlmMessage.fromJson(Map<String, dynamic> json) {
    return LlmMessage(
      role: json['role'] as String? ?? '',
      content: json['content'] as String?,
      toolCalls: (json['tool_calls'] as List<dynamic>?)
          ?.map((e) => e as Map<String, dynamic>)
          .toList(),
      toolCallId: json['tool_call_id'] as String?,
    );
  }
}

/// LLM 响应（对标 KouriChat LLM 响应结构）
class LlmResponse {
  /// 回复内容（对标 response）
  final String content;

  /// 是否成功（对标 status）
  final bool success;

  /// 错误信息
  final String? error;

  /// 耗时毫秒（对标 time）
  final int? durationMs;

  /// 文本内容（content 的别名，兼容部分调用方）
  String get text => content;

  /// Token 使用量
  final int? promptTokens;
  final int? completionTokens;

  /// 工具调用（Agent function calling）
  final List<Map<String, dynamic>>? toolCalls;

  const LlmResponse({
    this.content = '',
    this.success = true,
    this.error,
    this.durationMs,
    this.promptTokens,
    this.completionTokens,
    this.toolCalls,
  });

  factory LlmResponse.fromJson(
    Map<String, dynamic> json, {
    bool includeReasoningFallback = true,
  }) {
    final choices = json['choices'] as List<dynamic>?;
    final firstChoice = choices != null && choices.isNotEmpty
        ? choices.first as Map<String, dynamic>?
        : null;
    final message = firstChoice?['message'] as Map<String, dynamic>?;
    final delta = firstChoice?['delta'] as Map<String, dynamic>?;
    final usage = json['usage'] as Map<String, dynamic>?;

    // 智能提取内容：优先非空 content，回退到 reasoning 字段
    String extractContent() {
      // 顶层字段
      for (final key in ['content', 'response']) {
        final v = json[key] as String?;
        if (v != null && v.trim().isNotEmpty) return v;
      }
      // message 内字段
      if (message != null) {
        final keys = includeReasoningFallback
            ? ['content', 'text', 'reasoning_content', 'reasoning', 'thinking']
            : ['content', 'text'];
        for (final key in keys) {
          final v = message[key] as String?;
          if (v != null && v.trim().isNotEmpty) return v;
        }
      }
      // delta 内字段
      if (delta != null) {
        final keys = includeReasoningFallback
            ? ['content', 'text', 'reasoning_content', 'reasoning', 'thinking']
            : ['content', 'text'];
        for (final key in keys) {
          final v = delta[key] as String?;
          if (v != null && v.trim().isNotEmpty) return v;
        }
      }
      // choice 级别 reasoning
      if (includeReasoningFallback && firstChoice != null) {
        for (final key in ['reasoning_content', 'reasoning', 'thinking']) {
          final v = firstChoice[key] as String?;
          if (v != null && v.trim().isNotEmpty) return v;
        }
      }
      // 最后回退：任何非空字段
      for (final key in ['content', 'response']) {
        final v = json[key] as String?;
        if (v != null) return v;
      }
      if (message != null) {
        final v = message['content'] as String?;
        if (v != null) return v;
      }
      return '';
    }

    // 提取 tool_calls
    List<Map<String, dynamic>>? toolCalls;
    if (message != null && message['tool_calls'] != null) {
      toolCalls = (message['tool_calls'] as List<dynamic>)
          .map((e) => e as Map<String, dynamic>)
          .toList();
    }

    return LlmResponse(
      content: extractContent(),
      success: json['status'] as bool? ?? true,
      error: json['error'] as String?,
      durationMs: json['time'] as int?,
      promptTokens:
          json['prompt_tokens'] as int? ?? usage?['prompt_tokens'] as int?,
      completionTokens: json['completion_tokens'] as int? ??
          usage?['completion_tokens'] as int?,
      toolCalls: toolCalls,
    );
  }
}
