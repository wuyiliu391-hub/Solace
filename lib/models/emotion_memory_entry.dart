// 【对标来源：Muice-Chatbot-1.4 — llm/faiss_memory.py 文档结构】
// 1:1 转译自 Muice FAISS 向量记忆文档结构
// 参考文件：llm/faiss_memory.py:insert_memory()、search_memory()

/// 情绪记忆条目（对标 Muice FAISS 文档 {input, output}）
class EmotionMemoryEntry {
  /// 唯一 ID
  final String id;

  /// 角色 ID
  final String characterId;

  /// 用户 ID
  final String userId;

  /// 用户输入文本（对标 input）
  final String input;

  /// AI 回复文本（对标 output）
  final String output;

  /// 情绪标签（扩展：Muice 原生无此字段，用于情绪记忆池）
  final String? emotionTag;

  /// 情绪效价 -1.0 ~ 1.0（扩展）
  final double? valence;

  /// 情绪唤醒度 0.0 ~ 1.0（扩展）
  final double? arousal;

  /// 时间戳
  final DateTime timestamp;

  /// 向量嵌入（对标 FAISS embedding，序列化存储）
  final List<double>? embedding;

  /// 记忆权重（对标 Muice FAISS L2 距离）
  final double weight;

  const EmotionMemoryEntry({
    required this.id,
    required this.characterId,
    required this.userId,
    this.input = '',
    this.output = '',
    this.emotionTag,
    this.valence,
    this.arousal,
    required this.timestamp,
    this.embedding,
    this.weight = 1.0,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'characterId': characterId,
        'userId': userId,
        'input': input,
        'output': output,
        'emotionTag': emotionTag,
        'valence': valence,
        'arousal': arousal,
        'timestamp': timestamp.toIso8601String(),
        'embedding': embedding,
        'weight': weight,
      };

  factory EmotionMemoryEntry.fromJson(Map<String, dynamic> json) {
    return EmotionMemoryEntry(
      id: json['id'] as String? ?? '',
      characterId: json['characterId'] as String? ?? '',
      userId: json['userId'] as String? ?? '',
      input: json['input'] as String? ?? '',
      output: json['output'] as String? ?? '',
      emotionTag: json['emotionTag'] as String?,
      valence: (json['valence'] as num?)?.toDouble(),
      arousal: (json['arousal'] as num?)?.toDouble(),
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'] as String)
          : DateTime.now(),
      embedding: (json['embedding'] as List<dynamic>?)
          ?.map((e) => (e as num).toDouble())
          .toList(),
      weight: (json['weight'] as num?)?.toDouble() ?? 1.0,
    );
  }
}
