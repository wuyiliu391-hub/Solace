// 【对标来源：KouriChat-1.4.3.2 — data/config/__init__.py Config dataclass】
// 文件名: app_config_data.dart（避免与 lib/config/app_config.dart 冲突）
// 1:1 转译自 KouriChat 配置层级结构
// 参考文件：data/config/__init__.py、data/config/config.json.template

/// 全局配置（对标 KouriChat Config dataclass）
class AppConfigData {
  final LlmSettings llm;
  final BehaviorSettings behavior;
  final MediaSettings media;
  final AuthSettings auth;

  const AppConfigData({
    this.llm = const LlmSettings(),
    this.behavior = const BehaviorSettings(),
    this.media = const MediaSettings(),
    this.auth = const AuthSettings(),
  });

  Map<String, dynamic> toJson() => {
        'llm': llm.toJson(),
        'behavior': behavior.toJson(),
        'media': media.toJson(),
        'auth': auth.toJson(),
      };

  factory AppConfigData.fromJson(Map<String, dynamic> json) {
    return AppConfigData(
      llm: json['llm'] != null
          ? LlmSettings.fromJson(json['llm'] as Map<String, dynamic>)
          : const LlmSettings(),
      behavior: json['behavior'] != null
          ? BehaviorSettings.fromJson(
              json['behavior'] as Map<String, dynamic>)
          : const BehaviorSettings(),
      media: json['media'] != null
          ? MediaSettings.fromJson(json['media'] as Map<String, dynamic>)
          : const MediaSettings(),
      auth: json['auth'] != null
          ? AuthSettings.fromJson(json['auth'] as Map<String, dynamic>)
          : const AuthSettings(),
    );
  }
}

/// LLM 设置（对标 KouriChat LLMSettings）
class LlmSettings {
  final String apiKey;
  final String baseUrl;
  final String model;
  final int maxTokens;
  final double temperature;
  final double topP;
  final double frequencyPenalty;
  final double presencePenalty;
  final int maxGroups;
  final bool autoModelSwitch;

  const LlmSettings({
    this.apiKey = '',
    this.baseUrl = '',
    this.model = '',
    this.maxTokens = 2048,
    this.temperature = 0.7,
    this.topP = 1.0,
    this.frequencyPenalty = 0.0,
    this.presencePenalty = 0.0,
    this.maxGroups = 25,
    this.autoModelSwitch = false,
  });

  Map<String, dynamic> toJson() => {
        'apiKey': apiKey,
        'baseUrl': baseUrl,
        'model': model,
        'maxTokens': maxTokens,
        'temperature': temperature,
        'topP': topP,
        'frequencyPenalty': frequencyPenalty,
        'presencePenalty': presencePenalty,
        'maxGroups': maxGroups,
        'autoModelSwitch': autoModelSwitch,
      };

  factory LlmSettings.fromJson(Map<String, dynamic> json) {
    return LlmSettings(
      apiKey: json['apiKey'] as String? ?? '',
      baseUrl: json['baseUrl'] as String? ?? '',
      model: json['model'] as String? ?? '',
      maxTokens: json['maxTokens'] as int? ?? 2048,
      temperature: (json['temperature'] as num?)?.toDouble() ?? 0.7,
      topP: (json['topP'] as num?)?.toDouble() ?? 1.0,
      frequencyPenalty:
          (json['frequencyPenalty'] as num?)?.toDouble() ?? 0.0,
      presencePenalty:
          (json['presencePenalty'] as num?)?.toDouble() ?? 0.0,
      maxGroups: json['maxGroups'] as int? ?? 25,
      autoModelSwitch: json['autoModelSwitch'] as bool? ?? false,
    );
  }
}

/// 行为设置（对标 KouriChat BehaviorSettings）
class BehaviorSettings {
  final bool autoMessageEnabled;
  final double autoMessageMinHours;
  final double autoMessageMaxHours;
  final bool quietTimeEnabled;
  final int quietTimeStart;
  final int quietTimeEnd;
  final int maxContextGroups;
  final MessageQueueSettings messageQueue;

  const BehaviorSettings({
    this.autoMessageEnabled = false,
    this.autoMessageMinHours = 2.0,
    this.autoMessageMaxHours = 6.0,
    this.quietTimeEnabled = true,
    this.quietTimeStart = 23,
    this.quietTimeEnd = 6,
    this.maxContextGroups = 25,
    this.messageQueue = const MessageQueueSettings(),
  });

  Map<String, dynamic> toJson() => {
        'autoMessageEnabled': autoMessageEnabled,
        'autoMessageMinHours': autoMessageMinHours,
        'autoMessageMaxHours': autoMessageMaxHours,
        'quietTimeEnabled': quietTimeEnabled,
        'quietTimeStart': quietTimeStart,
        'quietTimeEnd': quietTimeEnd,
        'maxContextGroups': maxContextGroups,
        'messageQueue': messageQueue.toJson(),
      };

  factory BehaviorSettings.fromJson(Map<String, dynamic> json) {
    return BehaviorSettings(
      autoMessageEnabled: json['autoMessageEnabled'] as bool? ?? false,
      autoMessageMinHours:
          (json['autoMessageMinHours'] as num?)?.toDouble() ?? 2.0,
      autoMessageMaxHours:
          (json['autoMessageMaxHours'] as num?)?.toDouble() ?? 6.0,
      quietTimeEnabled: json['quietTimeEnabled'] as bool? ?? true,
      quietTimeStart: json['quietTimeStart'] as int? ?? 23,
      quietTimeEnd: json['quietTimeEnd'] as int? ?? 6,
      maxContextGroups: json['maxContextGroups'] as int? ?? 25,
      messageQueue: json['messageQueue'] != null
          ? MessageQueueSettings.fromJson(
              json['messageQueue'] as Map<String, dynamic>)
          : const MessageQueueSettings(),
    );
  }
}

/// 消息队列设置（对标 KouriChat message_queue 配置）
class MessageQueueSettings {
  final int timeout;
  final int maxLength;

  const MessageQueueSettings({
    this.timeout = 5,
    this.maxLength = 20,
  });

  Map<String, dynamic> toJson() => {
        'timeout': timeout,
        'maxLength': maxLength,
      };

  factory MessageQueueSettings.fromJson(Map<String, dynamic> json) {
    return MessageQueueSettings(
      timeout: json['timeout'] as int? ?? 5,
      maxLength: json['maxLength'] as int? ?? 20,
    );
  }
}

/// 媒体设置（对标 KouriChat MediaSettings）
class MediaSettings {
  final bool imageRecognition;
  final bool imageGeneration;
  final bool textToSpeech;
  final String? ttsProvider;
  final String? ttsApiKey;
  final String? ttsApiUrl;
  final String? ttsModelId;

  const MediaSettings({
    this.imageRecognition = false,
    this.imageGeneration = false,
    this.textToSpeech = false,
    this.ttsProvider,
    this.ttsApiKey,
    this.ttsApiUrl,
    this.ttsModelId,
  });

  Map<String, dynamic> toJson() => {
        'imageRecognition': imageRecognition,
        'imageGeneration': imageGeneration,
        'textToSpeech': textToSpeech,
        'ttsProvider': ttsProvider,
        'ttsApiKey': ttsApiKey,
        'ttsApiUrl': ttsApiUrl,
        'ttsModelId': ttsModelId,
      };

  factory MediaSettings.fromJson(Map<String, dynamic> json) {
    return MediaSettings(
      imageRecognition: json['imageRecognition'] as bool? ?? false,
      imageGeneration: json['imageGeneration'] as bool? ?? false,
      textToSpeech: json['textToSpeech'] as bool? ?? false,
      ttsProvider: json['ttsProvider'] as String?,
      ttsApiKey: json['ttsApiKey'] as String?,
      ttsApiUrl: json['ttsApiUrl'] as String?,
      ttsModelId: json['ttsModelId'] as String?,
    );
  }
}

/// 认证设置（对标 KouriChat AuthSettings）
class AuthSettings {
  final String adminPassword;

  const AuthSettings({this.adminPassword = ''});

  Map<String, dynamic> toJson() => {'adminPassword': adminPassword};

  factory AuthSettings.fromJson(Map<String, dynamic> json) {
    return AuthSettings(
      adminPassword: json['adminPassword'] as String? ?? '',
    );
  }
}



