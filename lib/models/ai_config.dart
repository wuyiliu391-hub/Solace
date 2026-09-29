import 'package:equatable/equatable.dart';

/// 模型族：用于法功能等按供应商调整伪装/重试策略
enum ModelFamily {
  openai,
  anthropic,
  google,
  xai,
  domestic,
  other;

  bool get isOverseas =>
      this == openai || this == anthropic || this == google || this == xai;
}

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
  /// 是否多模态（支持看图）。用户手动勾选；为 true 时发图走 OpenAI vision content 数组。
  final bool isMultimodal;
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
    this.isMultimodal = false,
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
    bool? isMultimodal,
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
      isMultimodal: isMultimodal ?? this.isMultimodal,
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
      'isMultimodal': isMultimodal ? 1 : 0,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'sync_seq': syncSeq,
    };
  }

  factory AIConfig.fromMap(Map<String, dynamic> map) {
    final extraKeysStr = map['extraApiKeys'] as String? ?? '';
    final extraKeys = extraKeysStr.isEmpty ? <String>[] : extraKeysStr.split(',');
    DateTime? tryParseDateTime(dynamic val) {
      if (val == null || (val is String && val.trim().isEmpty)) return null;
      if (val is String) return DateTime.tryParse(val);
      if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
      return null;
    }
    return AIConfig(
      id: (map['id'] as String?) ?? '',
      providerName: (map['providerName'] as String?) ?? '',
      baseUrl: (map['baseUrl'] as String?) ?? '',
      apiKey: (map['apiKey'] as String?) ?? '',
      extraApiKeys: extraKeys,
      modelName: (map['modelName'] as String?) ?? '',
      temperature: (map['temperature'] as double?) ?? 0.7,
      maxTokens: (map['maxTokens'] as int?) ?? 2048,
      isActive: map['isActive'] == 1,
      isThinkingModel: map['isThinkingModel'] == null ? true : map['isThinkingModel'] == 1,
      isMultimodal: map['isMultimodal'] == 1,
      createdAt: tryParseDateTime(map['createdAt']) ?? DateTime.now(),
      updatedAt: tryParseDateTime(map['updatedAt']),
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
    // 海外常见非推理/低推理型号
    'gpt-4o-mini', 'gpt-4o', 'gpt-3.5', 'gpt-4-turbo', 'gpt-4.1', 'gpt-4.1-mini',
    'gpt-4.1-nano', 'gpt-5-mini', 'gpt-5-nano', 'gpt-5-chat',
    'claude-3-haiku', 'claude-3-5-haiku', 'claude-3-opus',
    'claude-3-5-sonnet', 'claude-sonnet-4', 'claude-haiku',
    'gemini-1.5', 'gemini-2.0-flash', 'gemini-2.5-flash',
    'grok-2', 'grok-3-mini', 'grok-4-fast',
  ];

  /// 自动检测模型是否为非推理模型（根据模型名称关键词判断）
  static bool isKnownNonThinkingModel(String modelName) {
    final lower = modelName.toLowerCase();
    return _nonThinkingKeywords.any((kw) => lower.contains(kw));
  }

  /// 按模型名 / baseURL 推断模型族（法功能海外策略用）
  static ModelFamily detectModelFamily({
    required String modelName,
    String baseUrl = '',
    String providerName = '',
  }) {
    final m = modelName.toLowerCase();
    final b = baseUrl.toLowerCase();
    final p = providerName.toLowerCase();
    final blob = '$m $b $p';

    if (m.contains('claude') || blob.contains('anthropic')) {
      return ModelFamily.anthropic;
    }
    if (m.contains('gemini') ||
        blob.contains('generativelanguage') ||
        blob.contains('googleapis')) {
      return ModelFamily.google;
    }
    if (m.contains('grok') || blob.contains('x.ai') || blob.contains('api.x.ai')) {
      return ModelFamily.xai;
    }
    if (m.contains('gpt-') ||
        blob.contains('openai.com') ||
        blob.contains('api.openai')) {
      return ModelFamily.openai;
    }
    const domestic = [
      'deepseek', 'qwen', 'glm', 'chatglm', 'hunyuan', 'minimax', 'abab',
      'moonshot', 'kimi', 'yi-', 'spark', 'ernie', 'internlm', 'step-',
      'doubao', '豆包',
    ];
    if (domestic.any((k) => blob.contains(k))) {
      return ModelFamily.domestic;
    }
    return ModelFamily.other;
  }

  /// 当前配置对应的模型族
  ModelFamily get modelFamily => detectModelFamily(
        modelName: modelName,
        baseUrl: baseUrl,
        providerName: providerName,
      );

  /// 法功能是否应对该配置启用「海外加强伪装」
  /// 海外模型安全分类器更敏感：推理/非推理都加强，不再只看 isThinkingModel
  bool get faOverseasBoost => modelFamily.isOverseas;

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
        isMultimodal,
        createdAt,
        updatedAt,
        syncSeq,
      ];
}
