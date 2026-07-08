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
    };
  }

  factory AIInteractionConfig.fromMap(Map<String, dynamic> map) {
    return AIInteractionConfig(
      enableMorningGreeting: map['enableMorningGreeting'] == 1 ||
          map['enableMorningGreeting'] == true,
      enableNightGreeting:
          map['enableNightGreeting'] == 1 || map['enableNightGreeting'] == true,
      enableFestivalGreeting: map['enableFestivalGreeting'] == 1 ||
          map['enableFestivalGreeting'] == true,
      enableCareReminder:
          map['enableCareReminder'] == 1 || map['enableCareReminder'] == true,
      activeMessageFrequency: map['activeMessageFrequency'] as int? ?? 2,
      enableMomentInteraction: map['enableMomentInteraction'] == 1 ||
          map['enableMomentInteraction'] == true,
      enableUserMomentInteraction:
          map.containsKey('enableUserMomentInteraction')
              ? (map['enableUserMomentInteraction'] == 1 ||
                  map['enableUserMomentInteraction'] == true)
              : true,
      morningGreetingTime: map['morningGreetingTime'] as String?,
      nightGreetingTime: map['nightGreetingTime'] as String?,
      replyMode: ReplyMode.values[(map['replyMode'] as int?) ?? 1],
      replyDelaySeconds: map['replyDelaySeconds'] as int? ?? 5,
      voiceReplyEnabled: map.containsKey('voiceReplyEnabled')
          ? (map['voiceReplyEnabled'] == 1 || map['voiceReplyEnabled'] == true)
          : false,
      enableStickerReply: map.containsKey('enableStickerReply')
          ? (map['enableStickerReply'] == 1 ||
              map['enableStickerReply'] == true)
          : true,
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
      createdAt: DateTime.tryParse(map['createdAt'] as String? ?? '') ??
          DateTime.now(),
      updatedAt: map['updatedAt'] != null
          ? DateTime.tryParse(map['updatedAt'] as String? ?? '')
          : null,
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
      lastOnlineAt: map['lastOnlineAt'] != null
          ? DateTime.tryParse(map['lastOnlineAt'] as String? ?? '')
          : null,
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
