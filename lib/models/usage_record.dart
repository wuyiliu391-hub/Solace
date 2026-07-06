class UsageRecord {
  final String id;
  final DateTime timestamp;
  final String endpointType;
  final String provider;
  final String model;
  final int inputTokens;
  final int outputTokens;
  final int cacheHitTokens;
  final int systemTokens;
  final int historyTokens;
  final int userMessageTokens;
  final int otherInputTokens;
  final double inputCost;
  final double outputCost;
  final double totalCost;

  const UsageRecord({
    required this.id,
    required this.timestamp,
    required this.endpointType,
    required this.provider,
    required this.model,
    required this.inputTokens,
    required this.outputTokens,
    required this.cacheHitTokens,
    this.systemTokens = 0,
    this.historyTokens = 0,
    this.userMessageTokens = 0,
    this.otherInputTokens = 0,
    required this.inputCost,
    required this.outputCost,
    required this.totalCost,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'endpointType': endpointType,
        'provider': provider,
        'model': model,
        'inputTokens': inputTokens,
        'outputTokens': outputTokens,
        'cacheHitTokens': cacheHitTokens,
        'systemTokens': systemTokens,
        'historyTokens': historyTokens,
        'userMessageTokens': userMessageTokens,
        'otherInputTokens': otherInputTokens,
        'inputCost': inputCost,
        'outputCost': outputCost,
        'totalCost': totalCost,
      };

  factory UsageRecord.fromJson(Map<String, dynamic> json) => UsageRecord(
        id: json['id'] as String? ?? '',
        timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        endpointType: json['endpointType'] as String? ?? 'unknown',
        provider: json['provider'] as String? ?? 'unknown',
        model: json['model'] as String? ?? '',
        inputTokens: (json['inputTokens'] as num?)?.toInt() ?? 0,
        outputTokens: (json['outputTokens'] as num?)?.toInt() ?? 0,
        cacheHitTokens: (json['cacheHitTokens'] as num?)?.toInt() ?? 0,
        systemTokens: (json['systemTokens'] as num?)?.toInt() ?? 0,
        historyTokens: (json['historyTokens'] as num?)?.toInt() ?? 0,
        userMessageTokens: (json['userMessageTokens'] as num?)?.toInt() ?? 0,
        otherInputTokens: (json['otherInputTokens'] as num?)?.toInt() ?? 0,
        inputCost: (json['inputCost'] as num?)?.toDouble() ?? 0,
        outputCost: (json['outputCost'] as num?)?.toDouble() ?? 0,
        totalCost: (json['totalCost'] as num?)?.toDouble() ?? 0,
      );
}

class UsagePricing {
  final double inputPricePerMillion;
  final double outputPricePerMillion;

  const UsagePricing({
    required this.inputPricePerMillion,
    required this.outputPricePerMillion,
  });

  static const defaults = UsagePricing(
    inputPricePerMillion: 4.0,
    outputPricePerMillion: 16.0,
  );
}

class UsageSummary {
  final int inputTokens;
  final int outputTokens;
  final int cacheHitTokens;
  final int systemTokens;
  final int historyTokens;
  final int userMessageTokens;
  final int otherInputTokens;
  final double totalCost;
  final int requestCount;

  const UsageSummary({
    required this.inputTokens,
    required this.outputTokens,
    required this.cacheHitTokens,
    required this.systemTokens,
    required this.historyTokens,
    required this.userMessageTokens,
    required this.otherInputTokens,
    required this.totalCost,
    required this.requestCount,
  });

  int get totalTokens => inputTokens + outputTokens;

  int get avgTokensPerRequest {
    if (requestCount <= 0) return 0;
    return (totalTokens / requestCount).round();
  }

  double get avgCostPerRequest {
    if (requestCount <= 0) return 0;
    return totalCost / requestCount;
  }

  double get inputTokenShare {
    if (totalTokens <= 0) return 0;
    return inputTokens / totalTokens;
  }

  double get outputTokenShare {
    if (totalTokens <= 0) return 0;
    return outputTokens / totalTokens;
  }

  double inputPartShare(int tokens) {
    if (inputTokens <= 0) return 0;
    return tokens / inputTokens;
  }

  static const empty = UsageSummary(
    inputTokens: 0,
    outputTokens: 0,
    cacheHitTokens: 0,
    systemTokens: 0,
    historyTokens: 0,
    userMessageTokens: 0,
    otherInputTokens: 0,
    totalCost: 0,
    requestCount: 0,
  );
}

enum UsageRange { today, yesterday, week, all }
