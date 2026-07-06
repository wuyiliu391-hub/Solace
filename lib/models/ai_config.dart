import 'package:equatable/equatable.dart';

class AIConfig extends Equatable {
  final String id;
  final String providerName;
  final String baseUrl;
  final String apiKey;
  final List<String> extraApiKeys;
  final String modelName;
  final double temperature;
  final int maxTokens;
  final bool isActive;
  final bool isThinkingModel;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final int syncSeq;

  const AIConfig({
    required this.id,
    required this.providerName,
    required this.baseUrl,
    required this.apiKey,
    this.extraApiKeys = const [],
    required this.modelName,
    this.temperature = 0.7,
    this.maxTokens = 2000,
    this.isActive = true,
    this.isThinkingModel = true,
    required this.createdAt,
    this.updatedAt,
    this.syncSeq = 0,
  });

  List<String> get allApiKeys => [apiKey, ...extraApiKeys];

  AIConfig copyWith({
    String? id,
    String? providerName,
    String? baseUrl,
    String? apiKey,
    List<String>? extraApiKeys,
    String? modelName,
    double? temperature,
    int? maxTokens,
    bool? isActive,
    bool? isThinkingModel,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? syncSeq,
  }) {
    return AIConfig(
      id: id ?? this.id,
      providerName: providerName ?? this.providerName,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      extraApiKeys: extraApiKeys ?? this.extraApiKeys,
      modelName: modelName ?? this.modelName,
      temperature: temperature ?? this.temperature,
      maxTokens: maxTokens ?? this.maxTokens,
      isActive: isActive ?? this.isActive,
      isThinkingModel: isThinkingModel ?? this.isThinkingModel,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncSeq: syncSeq ?? this.syncSeq,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'providerName': providerName,
      'baseUrl': baseUrl,
      'apiKey': apiKey,
      'extraApiKeys': extraApiKeys.join(','),
      'modelName': modelName,
      'temperature': temperature,
      'maxTokens': maxTokens,
      'isActive': isActive ? 1 : 0,
      'isThinkingModel': isThinkingModel ? 1 : 0,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'sync_seq': syncSeq,
    };
  }

  factory AIConfig.fromMap(Map<String, dynamic> map) {
    final extraKeysStr = map['extraApiKeys'] as String? ?? '';
    final extraKeys = extraKeysStr.isEmpty ? <String>[] : extraKeysStr.split(',');
    return AIConfig(
      id: map['id'] as String,
      providerName: map['providerName'] as String,
      baseUrl: map['baseUrl'] as String,
      apiKey: map['apiKey'] as String,
      extraApiKeys: extraKeys,
      modelName: map['modelName'] as String,
      temperature: map['temperature'] as double,
      maxTokens: map['maxTokens'] as int,
      isActive: map['isActive'] == 1,
      isThinkingModel: map['isThinkingModel'] == null ? true : map['isThinkingModel'] == 1,
      createdAt: DateTime.parse(map['createdAt'] as String),
      updatedAt: map['updatedAt'] != null
          ? DateTime.parse(map['updatedAt'] as String)
          : null,
      syncSeq: (map['sync_seq'] ?? map['syncSeq']) as int? ?? 0,
    );
  }

  /// 已知非推理模型名称关键词（不区分大小写）
  /// 匹配到任一关键词的模型会自动关闭 isThinkingModel，启用 PromptRewriter
  static const _nonThinkingKeywords = [
    'deepseek-v3', 'deepseek-chat', 'deepseek-v2',
    'deepseek-v4', 'deepseek-v4-flash', 'deepseek-v4-pro',
    'qwen-max', 'qwen-plus', 'qwen-turbo', 'qwen-long', 'qwen2.5', 'qwen3', 'qwen3.7',
    'minimax', 'abab',
    'glm-4', 'glm-3', 'chatglm',
    'hunyuan',
    'yi-1.5', 'yi-lightning', 'yi-large', 'yi-medium',
    'spark', 'general',
    'ernie', 'baidu',
    'moonshot', 'kimi',
    'step-',
    'internlm',
    'llama-3', 'llama3', 'mistral', 'mixtral', 'command-r',
    'gpt-4o-mini', 'gpt-4o', 'gpt-3.5', 'gpt-4-turbo',
    'claude-3-haiku', 'claude-3-5-haiku',
  ];

  /// 自动检测模型是否为非推理模型（根据模型名称关键词判断）
  static bool isKnownNonThinkingModel(String modelName) {
    final lower = modelName.toLowerCase();
    return _nonThinkingKeywords.any((kw) => lower.contains(kw));
  }

  @override
  List<Object?> get props => [
        id,
        providerName,
        baseUrl,
        apiKey,
        extraApiKeys,
        modelName,
        temperature,
        maxTokens,
        isActive,
        isThinkingModel,
        createdAt,
        updatedAt,
        syncSeq,
      ];
}
