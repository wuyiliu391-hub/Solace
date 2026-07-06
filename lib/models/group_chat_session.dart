import 'dart:convert';
import 'package:equatable/equatable.dart';

enum ReplyMode { sequential, flash }

enum ActivationStrategy { natural, list, manual }

enum TavernMode { group, story, observe }

enum TavernImmersion { quiet, daily, lively, carnival }

enum TavernInteractionFrequency { gentle, natural, vivid }

extension TavernModeX on TavernMode {
  String get label {
    switch (this) {
      case TavernMode.group:
        return '群聊';
      case TavernMode.story:
        return '剧情';
      case TavernMode.observe:
        return '旁观';
    }
  }
}

extension TavernImmersionX on TavernImmersion {
  String get label {
    switch (this) {
      case TavernImmersion.quiet:
        return '安静';
      case TavernImmersion.daily:
        return '日常';
      case TavernImmersion.lively:
        return '热闹';
      case TavernImmersion.carnival:
        return '狂欢';
    }
  }

  int get minMessages {
    switch (this) {
      case TavernImmersion.quiet:
        return 1;
      case TavernImmersion.daily:
        return 1;
      case TavernImmersion.lively:
        return 2;
      case TavernImmersion.carnival:
        return 4;
    }
  }

  int get maxMessages {
    switch (this) {
      case TavernImmersion.quiet:
        return 1;
      case TavernImmersion.daily:
        return 2;
      case TavernImmersion.lively:
        return 3;
      case TavernImmersion.carnival:
        return 5;
    }
  }
}

extension TavernInteractionFrequencyX on TavernInteractionFrequency {
  String get label {
    switch (this) {
      case TavernInteractionFrequency.gentle:
        return '轻轻接话';
      case TavernInteractionFrequency.natural:
        return '自然互动';
      case TavernInteractionFrequency.vivid:
        return '热烈聊天';
    }
  }

  String get description {
    switch (this) {
      case TavernInteractionFrequency.gentle:
        return '主要回应你，偶尔互相接一句';
      case TavernInteractionFrequency.natural:
        return '自然接话，有真实群聊感';
      case TavernInteractionFrequency.vivid:
        return '角色之间互动更频繁';
    }
  }
}

class StorySceneState extends Equatable {
  final String emotion;
  final String location;
  final String atmosphere;
  final int playerArousal;
  final int characterArousal;

  const StorySceneState({
    this.emotion = '',
    this.location = '',
    this.atmosphere = '',
    this.playerArousal = 0,
    this.characterArousal = 0,
  });

  bool get isEmpty => emotion.trim().isEmpty && location.trim().isEmpty &&
      atmosphere.trim().isEmpty && playerArousal <= 0 && characterArousal <= 0;

  StorySceneState copyWith({
    String? emotion,
    String? location,
    String? atmosphere,
    int? playerArousal,
    int? characterArousal,
  }) {
    return StorySceneState(
      emotion: emotion ?? this.emotion,
      location: location ?? this.location,
      atmosphere: atmosphere ?? this.atmosphere,
      playerArousal: playerArousal ?? this.playerArousal,
      characterArousal: characterArousal ?? this.characterArousal,
    );
  }

  Map<String, dynamic> toMap() => {
    'emotion': emotion,
    'location': location,
    'atmosphere': atmosphere,
    'playerArousal': playerArousal,
    'characterArousal': characterArousal,
  };

  factory StorySceneState.fromMap(Map<String, dynamic> map) {
    return StorySceneState(
      emotion: map['emotion'] as String? ?? '',
      location: map['location'] as String? ?? '',
      atmosphere: map['atmosphere'] as String? ?? '',
      playerArousal: map['playerArousal'] as int? ?? 0,
      characterArousal: map['characterArousal'] as int? ?? 0,
    );
  }

  @override
  List<Object?> get props => [emotion, location, atmosphere, playerArousal, characterArousal];
}

class GroupChatSession extends Equatable {
  final String id;
  final String userId;
  final String name;
  final String? avatarUrl;
  final String? scenario;
  final String? scenarioTemplate;
  final List<String> participantIds;
  final List<String> participantNames;
  final List<String?> participantAvatars;
  final ActivationStrategy activationStrategy;
  final ReplyMode replyMode;
  final TavernMode tavernMode;
  final TavernImmersion immersion;
  final TavernInteractionFrequency interactionFrequency;
  final bool autoModeEnabled;
  final bool allowSelfResponse;
  final String? lastMessage;
  final DateTime? lastMessageTime;
  final int unreadCount;
  final String? conversationSummary;
  final int summaryMessageCount;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final bool isMuted;
  final bool isPinned;
  final bool isHidden;
  final int syncSeq;
  
  // 酒馆功能模式设置
  final bool loverModeEnabled;
  final bool openModeEnabled;
  final bool faModeEnabled;
  final bool daoModeEnabled;
  final String? progressMetrics;
  final StorySceneState? sceneState;

  const GroupChatSession({
    required this.id,
    required this.userId,
    required this.name,
    this.avatarUrl,
    this.scenario,
    this.scenarioTemplate,
    required this.participantIds,
    required this.participantNames,
    this.participantAvatars = const [],
    this.activationStrategy = ActivationStrategy.natural,
    this.replyMode = ReplyMode.flash,
    this.tavernMode = TavernMode.group,
    this.immersion = TavernImmersion.daily,
    this.interactionFrequency = TavernInteractionFrequency.natural,
    this.autoModeEnabled = false,
    this.allowSelfResponse = false,
    this.lastMessage,
    this.lastMessageTime,
    this.unreadCount = 0,
    this.conversationSummary,
    this.summaryMessageCount = 0,
    required this.createdAt,
    this.updatedAt,
    this.isMuted = false,
    this.isPinned = false,
    this.isHidden = false,
    this.syncSeq = 0,
    this.loverModeEnabled = false,
    this.openModeEnabled = false,
    this.faModeEnabled = false,
    this.daoModeEnabled = false,
    this.progressMetrics,
    this.sceneState,
  });

  GroupChatSession copyWith({
    String? id,
    String? userId,
    String? name,
    String? avatarUrl,
    String? scenario,
    String? scenarioTemplate,
    List<String>? participantIds,
    List<String>? participantNames,
    List<String?>? participantAvatars,
    ActivationStrategy? activationStrategy,
    ReplyMode? replyMode,
    TavernMode? tavernMode,
    TavernImmersion? immersion,
    TavernInteractionFrequency? interactionFrequency,
    bool? autoModeEnabled,
    bool? allowSelfResponse,
    String? lastMessage,
    DateTime? lastMessageTime,
    int? unreadCount,
    String? conversationSummary,
    int? summaryMessageCount,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isMuted,
    bool? isPinned,
    bool? isHidden,
    int? syncSeq,
    bool? loverModeEnabled,
    bool? openModeEnabled,
    bool? faModeEnabled,
    bool? daoModeEnabled,
    String? progressMetrics,
    StorySceneState? sceneState,
  }) {
    return GroupChatSession(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      scenario: scenario ?? this.scenario,
      scenarioTemplate: scenarioTemplate ?? this.scenarioTemplate,
      participantIds: participantIds ?? this.participantIds,
      participantNames: participantNames ?? this.participantNames,
      participantAvatars: participantAvatars ?? this.participantAvatars,
      activationStrategy: activationStrategy ?? this.activationStrategy,
      replyMode: replyMode ?? this.replyMode,
      tavernMode: tavernMode ?? this.tavernMode,
      immersion: immersion ?? this.immersion,
      interactionFrequency: interactionFrequency ?? this.interactionFrequency,
      autoModeEnabled: autoModeEnabled ?? this.autoModeEnabled,
      allowSelfResponse: allowSelfResponse ?? this.allowSelfResponse,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      unreadCount: unreadCount ?? this.unreadCount,
      conversationSummary: conversationSummary ?? this.conversationSummary,
      summaryMessageCount: summaryMessageCount ?? this.summaryMessageCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isMuted: isMuted ?? this.isMuted,
      isPinned: isPinned ?? this.isPinned,
      isHidden: isHidden ?? this.isHidden,
      syncSeq: syncSeq ?? this.syncSeq,
      loverModeEnabled: loverModeEnabled ?? this.loverModeEnabled,
      openModeEnabled: openModeEnabled ?? this.openModeEnabled,
      faModeEnabled: faModeEnabled ?? this.faModeEnabled,
      daoModeEnabled: daoModeEnabled ?? this.daoModeEnabled,
      progressMetrics: progressMetrics ?? this.progressMetrics,
      sceneState: sceneState ?? this.sceneState,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'userId': userId,
      'name': name,
      'avatarUrl': avatarUrl,
      'scenario': scenario,
      'scenarioTemplate': scenarioTemplate,
      'participantIds': jsonEncode(participantIds),
      'participantNames': jsonEncode(participantNames),
      'participantAvatars': jsonEncode(participantAvatars),
      'activationStrategy': activationStrategy.index,
      'replyMode': replyMode.index,
      'tavernMode': tavernMode.index,
      'immersion': immersion.index,
      'interactionFrequency': interactionFrequency.index,
      'autoModeEnabled': autoModeEnabled ? 1 : 0,
      'allowSelfResponse': allowSelfResponse ? 1 : 0,
      'lastMessage': lastMessage,
      'lastMessageTime': lastMessageTime?.toIso8601String(),
      'unreadCount': unreadCount,
      'conversationSummary': conversationSummary,
      'summaryMessageCount': summaryMessageCount,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'isMuted': isMuted ? 1 : 0,
      'isPinned': isPinned ? 1 : 0,
      'isHidden': isHidden ? 1 : 0,
      'sync_seq': syncSeq,
      'loverModeEnabled': loverModeEnabled ? 1 : 0,
      'openModeEnabled': openModeEnabled ? 1 : 0,
      'faModeEnabled': faModeEnabled ? 1 : 0,
      'daoModeEnabled': daoModeEnabled ? 1 : 0,
      'progressMetrics': progressMetrics,
      'sceneState': sceneState != null ? jsonEncode(sceneState!.toMap()) : null,
    };
  }

  factory GroupChatSession.fromMap(Map<String, dynamic> map) {
    List<String> _parseStringList(dynamic v) {
      if (v == null) return [];
      if (v is List) return v.cast<String>();
      if (v is String) {
        try {
          final decoded = jsonDecode(v);
          if (decoded is List) return decoded.cast<String>();
        } catch (_) {}
      }
      return [];
    }

    List<String?> _parseNullableStringList(dynamic v) {
      if (v == null) return [];
      if (v is List) return v.cast<String?>();
      if (v is String) {
        try {
          final decoded = jsonDecode(v);
          if (decoded is List) return decoded.cast<String?>();
        } catch (_) {}
      }
      return [];
    }

    int _intValue(String key, int fallback) {
      final value = map[key];
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse('$value') ?? fallback;
    }

    final actIdx = _intValue('activationStrategy', 0);
    final repIdx = _intValue('replyMode', 0);
    final tavernModeIdx = _intValue('tavernMode', 0);
    final immersionIdx = _intValue('immersion', 1);
    final interactionIdx = _intValue('interactionFrequency', 1);

    return GroupChatSession(
      id: map['id'] as String,
      userId: map['userId'] as String,
      name: map['name'] as String,
      avatarUrl: map['avatarUrl'] as String?,
      scenario: map['scenario'] as String?,
      scenarioTemplate: map['scenarioTemplate'] as String?,
      participantIds: _parseStringList(map['participantIds']),
      participantNames: _parseStringList(map['participantNames']),
      participantAvatars: _parseNullableStringList(map['participantAvatars']),
      activationStrategy: actIdx < ActivationStrategy.values.length
          ? ActivationStrategy.values[actIdx]
          : ActivationStrategy.natural,
      replyMode: repIdx < ReplyMode.values.length
          ? ReplyMode.values[repIdx]
          : ReplyMode.flash,
      tavernMode: tavernModeIdx < TavernMode.values.length
          ? TavernMode.values[tavernModeIdx]
          : TavernMode.group,
      immersion: immersionIdx < TavernImmersion.values.length
          ? TavernImmersion.values[immersionIdx]
          : TavernImmersion.daily,
      interactionFrequency: interactionIdx < TavernInteractionFrequency.values.length
          ? TavernInteractionFrequency.values[interactionIdx]
          : TavernInteractionFrequency.natural,
      autoModeEnabled: map['autoModeEnabled'] == 1 || map['autoModeEnabled'] == true,
      allowSelfResponse: map['allowSelfResponse'] == 1 || map['allowSelfResponse'] == true,
      lastMessage: map['lastMessage'] as String?,
      lastMessageTime: map['lastMessageTime'] != null
          ? DateTime.tryParse(map['lastMessageTime'] as String? ?? '')
          : null,
      unreadCount: map['unreadCount'] as int? ?? 0,
      conversationSummary: map['conversationSummary'] as String?,
      summaryMessageCount: map['summaryMessageCount'] as int? ?? 0,
      createdAt: DateTime.tryParse(map['createdAt'] as String? ?? '') ?? DateTime.now(),
      updatedAt: map['updatedAt'] != null
          ? DateTime.tryParse(map['updatedAt'] as String? ?? '')
          : null,
      isMuted: map['isMuted'] == 1 || map['isMuted'] == true,
      isPinned: map['isPinned'] == 1 || map['isPinned'] == true,
      isHidden: map['isHidden'] == 1 || map['isHidden'] == true,
      syncSeq: (map['sync_seq'] ?? map['syncSeq']) as int? ?? 0,
      loverModeEnabled: map['loverModeEnabled'] == 1 || map['loverModeEnabled'] == true,
      openModeEnabled: map['openModeEnabled'] == 1 || map['openModeEnabled'] == true,
      faModeEnabled: map['faModeEnabled'] == 1 || map['faModeEnabled'] == true,
      daoModeEnabled: map['daoModeEnabled'] == 1 || map['daoModeEnabled'] == true,
      progressMetrics: map['progressMetrics'] as String?,
      sceneState: map['sceneState'] != null
          ? StorySceneState.fromMap(jsonDecode(map['sceneState'] as String))
          : null,
    );
  }

  @override
  List<Object?> get props => [
        id,
        userId,
        name,
        avatarUrl,
        scenario,
        scenarioTemplate,
        participantIds,
        participantNames,
        participantAvatars,
        activationStrategy,
        replyMode,
        tavernMode,
        immersion,
        interactionFrequency,
        autoModeEnabled,
        allowSelfResponse,
        lastMessage,
        lastMessageTime,
        unreadCount,
        conversationSummary,
        summaryMessageCount,
        createdAt,
        updatedAt,
        isMuted,
        isPinned,
        isHidden,
        syncSeq,
        loverModeEnabled,
        openModeEnabled,
        faModeEnabled,
        daoModeEnabled,
        progressMetrics,
        sceneState,
      ];
}
