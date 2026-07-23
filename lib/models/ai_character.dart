import 'dart:convert';
import 'package:equatable/equatable.dart';

class DialogueExample extends Equatable {
  final String userMessage;
  final String aiResponse;

  const DialogueExample({
    required this.userMessage,
    required this.aiResponse,
  });

  Map<String, dynamic> toMap() {
    return {
      'userMessage': userMessage,
      'aiResponse': aiResponse,
    };
  }

  factory DialogueExample.fromMap(Map<String, dynamic> map) {
    return DialogueExample(
      userMessage: map['userMessage'] as String,
      aiResponse: map['aiResponse'] as String,
    );
  }

  @override
  List<Object?> get props => [userMessage, aiResponse];
}

enum ReplyMode { instant, normal, delayed, manual }

class AIInteractionConfig extends Equatable {
  final bool enableMorningGreeting;
  final bool enableNightGreeting;
  final bool enableFestivalGreeting;
  final bool enableCareReminder;
  final int activeMessageFrequency;
  final bool enableMomentInteraction;
  final bool enableUserMomentInteraction;
  final String? morningGreetingTime;
  final String? nightGreetingTime;
  final ReplyMode replyMode;
  final int replyDelaySeconds;
  final bool voiceReplyEnabled;
  final bool enableStickerReply;
  /// 该角色是否允许主动设备操控（仍受全局 Device Agent 总开关约束）
  final bool enableProactiveDevice;
  /// 该角色是否允许读通知（查岗/好奇类）
  final bool enableReadNotifications;
  /// 是否用 LLM 精炼欲望画像（人设变更时）
  final bool enableLlmDesireRefine;

  const AIInteractionConfig({
    this.enableMorningGreeting = true,
    this.enableNightGreeting = true,
    this.enableFestivalGreeting = true,
    this.enableCareReminder = true,
    this.activeMessageFrequency = 2,
    this.enableMomentInteraction = true,
    this.enableUserMomentInteraction = true,
    this.morningGreetingTime,
    this.nightGreetingTime,
    this.replyMode = ReplyMode.normal,
    this.replyDelaySeconds = 5,
    this.voiceReplyEnabled = false,
    this.enableStickerReply = true,
    this.enableProactiveDevice = true,
    this.enableReadNotifications = true,
    this.enableLlmDesireRefine = true,
  });

  Map<String, dynamic> toMap() {
    return {
      'enableMorningGreeting': enableMorningGreeting ? 1 : 0,
      'enableNightGreeting': enableNightGreeting ? 1 : 0,
      'enableFestivalGreeting': enableFestivalGreeting ? 1 : 0,
      'enableCareReminder': enableCareReminder ? 1 : 0,
      'activeMessageFrequency': activeMessageFrequency,
      'enableMomentInteraction': enableMomentInteraction ? 1 : 0,
      'enableUserMomentInteraction': enableUserMomentInteraction ? 1 : 0,
      'morningGreetingTime': morningGreetingTime,
      'nightGreetingTime': nightGreetingTime,
      'replyMode': replyMode.index,
      'replyDelaySeconds': replyDelaySeconds,
      'voiceReplyEnabled': voiceReplyEnabled ? 1 : 0,
      'enableStickerReply': enableStickerReply ? 1 : 0,
      'enableProactiveDevice': enableProactiveDevice ? 1 : 0,
      'enableReadNotifications': enableReadNotifications ? 1 : 0,
      'enableLlmDesireRefine': enableLlmDesireRefine ? 1 : 0,
    };
  }

  static bool _asBool(dynamic v, {required bool defaultValue}) {
    if (v == null) return defaultValue;
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) {
      final s = v.trim().toLowerCase();
      if (s == '1' || s == 'true' || s == 'yes') return true;
      if (s == '0' || s == 'false' || s == 'no') return false;
    }
    return defaultValue;
  }

  static int _asInt(dynamic v, {required int defaultValue}) {
    if (v == null) return defaultValue;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? defaultValue;
    return defaultValue;
  }

  factory AIInteractionConfig.fromMap(Map<String, dynamic> map) {
    final replyModeIndex = _asInt(map['replyMode'], defaultValue: 1)
        .clamp(0, ReplyMode.values.length - 1);
    return AIInteractionConfig(
      enableMorningGreeting:
          _asBool(map['enableMorningGreeting'], defaultValue: true),
      enableNightGreeting:
          _asBool(map['enableNightGreeting'], defaultValue: true),
      enableFestivalGreeting:
          _asBool(map['enableFestivalGreeting'], defaultValue: true),
      enableCareReminder:
          _asBool(map['enableCareReminder'], defaultValue: true),
      activeMessageFrequency:
          _asInt(map['activeMessageFrequency'], defaultValue: 2),
      enableMomentInteraction:
          _asBool(map['enableMomentInteraction'], defaultValue: true),
      enableUserMomentInteraction:
          _asBool(map['enableUserMomentInteraction'], defaultValue: true),
      morningGreetingTime: map['morningGreetingTime']?.toString(),
      nightGreetingTime: map['nightGreetingTime']?.toString(),
      replyMode: ReplyMode.values[replyModeIndex],
      replyDelaySeconds: _asInt(map['replyDelaySeconds'], defaultValue: 5),
      voiceReplyEnabled:
          _asBool(map['voiceReplyEnabled'], defaultValue: false),
      enableStickerReply:
          _asBool(map['enableStickerReply'], defaultValue: true),
      enableProactiveDevice:
          _asBool(map['enableProactiveDevice'], defaultValue: true),
      enableReadNotifications:
          _asBool(map['enableReadNotifications'], defaultValue: true),
      enableLlmDesireRefine:
          _asBool(map['enableLlmDesireRefine'], defaultValue: true),
    );
  }

  AIInteractionConfig copyWith({
    bool? enableMorningGreeting,
    bool? enableNightGreeting,
    bool? enableFestivalGreeting,
    bool? enableCareReminder,
    int? activeMessageFrequency,
    bool? enableMomentInteraction,
    bool? enableUserMomentInteraction,
    String? morningGreetingTime,
    String? nightGreetingTime,
    ReplyMode? replyMode,
    int? replyDelaySeconds,
    bool? voiceReplyEnabled,
    bool? enableStickerReply,
    bool? enableProactiveDevice,
    bool? enableReadNotifications,
    bool? enableLlmDesireRefine,
  }) {
    return AIInteractionConfig(
      enableMorningGreeting:
          enableMorningGreeting ?? this.enableMorningGreeting,
      enableNightGreeting: enableNightGreeting ?? this.enableNightGreeting,
      enableFestivalGreeting:
          enableFestivalGreeting ?? this.enableFestivalGreeting,
      enableCareReminder: enableCareReminder ?? this.enableCareReminder,
      activeMessageFrequency:
          activeMessageFrequency ?? this.activeMessageFrequency,
      enableMomentInteraction:
          enableMomentInteraction ?? this.enableMomentInteraction,
      enableUserMomentInteraction:
          enableUserMomentInteraction ?? this.enableUserMomentInteraction,
      morningGreetingTime: morningGreetingTime ?? this.morningGreetingTime,
      nightGreetingTime: nightGreetingTime ?? this.nightGreetingTime,
      replyMode: replyMode ?? this.replyMode,
      replyDelaySeconds: replyDelaySeconds ?? this.replyDelaySeconds,
      voiceReplyEnabled: voiceReplyEnabled ?? this.voiceReplyEnabled,
      enableStickerReply: enableStickerReply ?? this.enableStickerReply,
      enableProactiveDevice:
          enableProactiveDevice ?? this.enableProactiveDevice,
      enableReadNotifications:
          enableReadNotifications ?? this.enableReadNotifications,
      enableLlmDesireRefine:
          enableLlmDesireRefine ?? this.enableLlmDesireRefine,
    );
  }

  @override
  List<Object?> get props => [
        enableMorningGreeting,
        enableNightGreeting,
        enableFestivalGreeting,
        enableCareReminder,
        activeMessageFrequency,
        enableMomentInteraction,
        enableUserMomentInteraction,
        morningGreetingTime,
        nightGreetingTime,
        replyMode,
        replyDelaySeconds,
        voiceReplyEnabled,
        enableStickerReply,
        enableProactiveDevice,
        enableReadNotifications,
        enableLlmDesireRefine,
      ];
}

class AICharacter extends Equatable {
  final String id;
  final String name;
  final String? avatarUrl;
  final String personality;
  final String coreDesire;
  final String moralBoundary;
  final String? backgroundStory;
  final String? gender;
  final DateTime createdAt;
  final DateTime? updatedAt;

  // 新增字段
  final String? worldSetting;
  final String? languageStyle;
  final String? tabooTopics;
  final String? userNickname;
  final String? userAlias;
  final String? userPersona;
  final String? catchphrases;
  final String? openingLine;
  final List<DialogueExample> dialogueExamples;
  final AIInteractionConfig? interactionConfig;
  final bool isHidden;
  final bool isOnline;
  final String? currentStatus;
  final DateTime? lastOnlineAt;
  final int syncSeq;
  final String? immutableAnchor;
  final double deviationRadius;
  final bool evolutionEnabled;
  final bool qualitativeEvolutionEnabled;
  final String? currentAnchor;

  // ─── 角色视觉锚定字段（v39） ───
  /// 参考图本地路径（用于记录角色外貌参考）
  final String? referenceImg;

  /// 固定随机种子（-1 表示随机，其他值锁定种子）
  final int fixedSeed;

  /// 固化外貌标签（发色、瞳色、脸型、标志性配饰、体型、基础穿搭）
  final String? characterTag;

  /// 画风锁定：anime / realistic
  final String styleLock;

  /// 角色年龄（用户设定，从背景故事自动提取或手动设置）
  final int? age;

  /// 结构化特征（兴趣/作息/口癖/时区）— JSON 编码
  final String? structuredTraits;

  const AICharacter({
    required this.id,
    required this.name,
    this.avatarUrl,
    required this.personality,
    required this.coreDesire,
    required this.moralBoundary,
    this.backgroundStory,
    this.gender,
    required this.createdAt,
    this.updatedAt,
    this.worldSetting,
    this.languageStyle,
    this.tabooTopics,
    this.userNickname,
    this.userAlias,
    this.userPersona,
    this.catchphrases,
    this.openingLine,
    this.dialogueExamples = const [],
    this.interactionConfig,
    this.isHidden = false,
    this.isOnline = true,
    this.currentStatus,
    this.lastOnlineAt,
    this.syncSeq = 0,
    this.immutableAnchor,
    this.deviationRadius = 0.4,
    this.evolutionEnabled = true,
    this.qualitativeEvolutionEnabled = false,
    this.currentAnchor,
    this.referenceImg,
    this.fixedSeed = -1,
    this.characterTag,
    this.styleLock = 'anime',
    this.age,
    this.structuredTraits,
  });

  AICharacter copyWith({
    String? id,
    String? name,
    String? avatarUrl,
    String? personality,
    String? coreDesire,
    String? moralBoundary,
    String? backgroundStory,
    String? gender,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? worldSetting,
    String? languageStyle,
    String? tabooTopics,
    String? userNickname,
    String? userAlias,
    String? userPersona,
    String? catchphrases,
    String? openingLine,
    List<DialogueExample>? dialogueExamples,
    AIInteractionConfig? interactionConfig,
    bool? isHidden,
    bool? isOnline,
    String? currentStatus,
    DateTime? lastOnlineAt,
    int? syncSeq,
    String? immutableAnchor,
    double? deviationRadius,
    bool? evolutionEnabled,
    bool? qualitativeEvolutionEnabled,
    String? currentAnchor,
    String? referenceImg,
    int? fixedSeed,
    String? characterTag,
    String? styleLock,
    int? age,
    String? structuredTraits,
    bool clearBackgroundStory = false,
    bool clearWorldSetting = false,
    bool clearLanguageStyle = false,
    bool clearTabooTopics = false,
    bool clearUserNickname = false,
    bool clearUserAlias = false,
    bool clearUserPersona = false,
    bool clearCharacterTag = false,
  }) {
    return AICharacter(
      id: id ?? this.id,
      name: name ?? this.name,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      personality: personality ?? this.personality,
      coreDesire: coreDesire ?? this.coreDesire,
      moralBoundary: moralBoundary ?? this.moralBoundary,
      backgroundStory: clearBackgroundStory
          ? null
          : (backgroundStory ?? this.backgroundStory),
      gender: gender ?? this.gender,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      worldSetting:
          clearWorldSetting ? null : (worldSetting ?? this.worldSetting),
      languageStyle:
          clearLanguageStyle ? null : (languageStyle ?? this.languageStyle),
      tabooTopics: clearTabooTopics ? null : (tabooTopics ?? this.tabooTopics),
      userNickname:
          clearUserNickname ? null : (userNickname ?? this.userNickname),
      userAlias: clearUserAlias ? null : (userAlias ?? this.userAlias),
      userPersona: clearUserPersona ? null : (userPersona ?? this.userPersona),
      catchphrases: catchphrases ?? this.catchphrases,
      openingLine: openingLine ?? this.openingLine,
      dialogueExamples: dialogueExamples ?? this.dialogueExamples,
      interactionConfig: interactionConfig ?? this.interactionConfig,
      isHidden: isHidden ?? this.isHidden,
      isOnline: isOnline ?? this.isOnline,
      currentStatus: currentStatus ?? this.currentStatus,
      lastOnlineAt: lastOnlineAt ?? this.lastOnlineAt,
      syncSeq: syncSeq ?? this.syncSeq,
      immutableAnchor: immutableAnchor ?? this.immutableAnchor,
      deviationRadius: deviationRadius ?? this.deviationRadius,
      evolutionEnabled: evolutionEnabled ?? this.evolutionEnabled,
      qualitativeEvolutionEnabled:
          qualitativeEvolutionEnabled ?? this.qualitativeEvolutionEnabled,
      currentAnchor: currentAnchor ?? this.currentAnchor,
      referenceImg: referenceImg ?? this.referenceImg,
      fixedSeed: fixedSeed ?? this.fixedSeed,
      characterTag:
          clearCharacterTag ? null : (characterTag ?? this.characterTag),
      styleLock: styleLock ?? this.styleLock,
      age: age ?? this.age,
      structuredTraits: structuredTraits ?? this.structuredTraits,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'avatarUrl': avatarUrl,
      'personality': personality,
      'coreDesire': coreDesire,
      'moralBoundary': moralBoundary,
      'backgroundStory': backgroundStory,
      'gender': gender,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'worldSetting': worldSetting,
      'languageStyle': languageStyle,
      'tabooTopics': tabooTopics,
      'userNickname': userNickname,
      'userAlias': userAlias,
      'userPersona': userPersona,
      'catchphrases': catchphrases,
      'openingLine': openingLine,
      'dialogueExamples': dialogueExamples.isNotEmpty
          ? jsonEncode(dialogueExamples.map((e) => e.toMap()).toList())
          : null,
      'interactionConfig': interactionConfig != null
          ? jsonEncode(interactionConfig!.toMap())
          : null,
      'isHidden': isHidden ? 1 : 0,
      'isOnline': isOnline ? 1 : 0,
      'currentStatus': currentStatus,
      'lastOnlineAt': lastOnlineAt?.toIso8601String(),
      'sync_seq': syncSeq,
      'immutableAnchor': immutableAnchor,
      'deviationRadius': deviationRadius,
      'evolutionEnabled': evolutionEnabled ? 1 : 0,
      'qualitativeEvolutionEnabled': qualitativeEvolutionEnabled ? 1 : 0,
      'currentAnchor': currentAnchor,
      'referenceImg': referenceImg,
      'fixedSeed': fixedSeed,
      'characterTag': characterTag,
      'styleLock': styleLock,
      'age': age,
      'structuredTraits': structuredTraits,
    };
  }

  factory AICharacter.fromMap(Map<String, dynamic> map) {
    List<DialogueExample> parseDialogueExamples(dynamic data) {
      if (data == null || data.toString().isEmpty || data.toString() == '[]') {
        return [];
      }
      try {
        final List<dynamic> list = jsonDecode(data.toString());
        return list
            .map((e) => DialogueExample.fromMap(e as Map<String, dynamic>))
            .toList();
      } catch (e) {
        return [];
      }
    }

    AIInteractionConfig? parseInteractionConfig(dynamic data) {
      if (data == null || data.toString().isEmpty) {
        return null;
      }
      try {
        final Map<String, dynamic> configMap = jsonDecode(data.toString());
        return AIInteractionConfig.fromMap(configMap);
      } catch (e) {
        return null;
      }
    }

    return AICharacter(
      id: map['id'] as String,
      name: map['name'] as String,
      avatarUrl: map['avatarUrl'] as String?,
      personality: map['personality'] as String,
      coreDesire: map['coreDesire'] as String,
      moralBoundary: map['moralBoundary'] as String,
      backgroundStory: map['backgroundStory'] as String?,
      gender: map['gender'] as String?,
      // 修复：处理 int 类型的时间戳
      createdAt: _parseDateTime(map['createdAt']) ?? DateTime.now(),
      updatedAt: _parseDateTime(map['updatedAt']),
      worldSetting: map['worldSetting'] as String?,
      languageStyle: map['languageStyle'] as String?,
      tabooTopics: map['tabooTopics'] as String?,
      userNickname: map['userNickname'] as String?,
      userAlias: map['userAlias'] as String?,
      userPersona: map['userPersona'] as String?,
      catchphrases: map['catchphrases'] as String?,
      openingLine: map['openingLine'] as String?,
      dialogueExamples: parseDialogueExamples(map['dialogueExamples']),
      interactionConfig: parseInteractionConfig(map['interactionConfig']),
      isHidden: map['isHidden'] == 1 || map['isHidden'] == true,
      isOnline: map['isOnline'] == 1 || map['isOnline'] == true,
      currentStatus: map['currentStatus'] as String?,
      lastOnlineAt: _parseDateTime(map['lastOnlineAt']),
      syncSeq: (map['sync_seq'] ?? map['syncSeq']) as int? ?? 0,
      immutableAnchor: map['immutableAnchor'] as String?,
      deviationRadius: (map['deviationRadius'] as num?)?.toDouble() ?? 0.4,
      evolutionEnabled: map.containsKey('evolutionEnabled')
          ? (map['evolutionEnabled'] == 1 || map['evolutionEnabled'] == true)
          : true,
      qualitativeEvolutionEnabled:
          map.containsKey('qualitativeEvolutionEnabled')
              ? (map['qualitativeEvolutionEnabled'] == 1 ||
                  map['qualitativeEvolutionEnabled'] == true)
              : false,
      currentAnchor: map['currentAnchor'] as String?,
      referenceImg: map['referenceImg'] as String?,
      fixedSeed: (map['fixedSeed'] as int?) ?? -1,
      characterTag: map['characterTag'] as String?,
      styleLock: (map['styleLock'] as String?) ?? 'anime',
      age: map['age'] as int?,
      structuredTraits: map['structuredTraits'] as String?,
    );
  }

  // 辅助方法：处理 String、int 或 null 的日期时间
  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is String) return DateTime.tryParse(value);
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    return null;
  }

  @override
  List<Object?> get props => [
        id,
        name,
        avatarUrl,
        personality,
        coreDesire,
        moralBoundary,
        backgroundStory,
        gender,
        createdAt,
        updatedAt,
        worldSetting,
        languageStyle,
        tabooTopics,
        userNickname,
        userAlias,
        userPersona,
        catchphrases,
        openingLine,
        dialogueExamples,
        interactionConfig,
        isHidden,
        isOnline,
        currentStatus,
        lastOnlineAt,
        syncSeq,
        immutableAnchor,
        deviationRadius,
        evolutionEnabled,
        qualitativeEvolutionEnabled,
        currentAnchor,
        referenceImg,
        fixedSeed,
        characterTag,
        styleLock,
        age,
      ];
}
