/// 流式输出的增量数据 — 包含思考过程和正文回答
class AIStreamChunk {
  final String reasoning; // 深度思考内容（累积）
  final String content; // 正文回答（累积）
  final String? finishReason; // OpenAI兼容流式结束原因，例如 length/stop

  const AIStreamChunk({
    this.reasoning = '',
    this.content = '',
    this.finishReason,
  });

  bool get isEmpty => reasoning.isEmpty && content.isEmpty;
  bool get isThinkingOnly => content.isEmpty && reasoning.isNotEmpty;

  AIStreamChunk copyWith({
    String? reasoning,
    String? content,
    String? finishReason,
  }) {
    return AIStreamChunk(
      reasoning: reasoning ?? this.reasoning,
      content: content ?? this.content,
      finishReason: finishReason ?? this.finishReason,
    );
  }
}
