import 'dart:convert';

/// 在场人物的即时状态简讯
class ScenePresence {
  final String characterId;
  final String name;
  final int affinity; // 好感度 0~100
  final String emotion; // 情绪文字标签
  final String state; // 状态简讯

  const ScenePresence({
    required this.characterId,
    required this.name,
    this.affinity = 50,
    this.emotion = '',
    this.state = '',
  });

  Map<String, dynamic> toJson() => {
        'characterId': characterId,
        'name': name,
        'affinity': affinity,
        'emotion': emotion,
        'state': state,
      };

  factory ScenePresence.fromJson(Map<String, dynamic> json) => ScenePresence(
        characterId: json['characterId'] as String? ?? '',
        name: json['name'] as String? ?? '',
        affinity: (json['affinity'] as num?)?.toInt() ?? 50,
        emotion: json['emotion'] as String? ?? '',
        state: json['state'] as String? ?? '',
      );
}

/// 实时动态参数面板快照 — 每句剧情输出后刷新，可随存档恢复
class StoryScene {
  final String storyId;
  final String saveId;

  // ── 主视角人物核心数值 ──
  final int affinity; // 好感度 0~100
  final int emotionValue; // 情绪度 0~100
  final String emotionLabel; // 情绪文字标签

  // ── 主视角人物状态 ──
  final String bodyState; // 身体状态
  final String psychState; // 心理状态
  final String actionState; // 行动状态

  // ── 场景环境 ──
  final String location; // 当前所处地点
  final String atmosphere; // 场景环境氛围

  // ── 在场所有人物 ──
  final List<ScenePresence> presentCharacters;

  final DateTime updatedAt;

  const StoryScene({
    required this.storyId,
    required this.saveId,
    this.affinity = 50,
    this.emotionValue = 50,
    this.emotionLabel = '平静',
    this.bodyState = '',
    this.psychState = '',
    this.actionState = '',
    this.location = '',
    this.atmosphere = '',
    this.presentCharacters = const [],
    required this.updatedAt,
  });

  StoryScene copyWith({
    String? storyId,
    String? saveId,
    int? affinity,
    int? emotionValue,
    String? emotionLabel,
    String? bodyState,
    String? psychState,
    String? actionState,
    String? location,
    String? atmosphere,
    List<ScenePresence>? presentCharacters,
    DateTime? updatedAt,
  }) {
    return StoryScene(
      storyId: storyId ?? this.storyId,
      saveId: saveId ?? this.saveId,
      affinity: affinity ?? this.affinity,
      emotionValue: emotionValue ?? this.emotionValue,
      emotionLabel: emotionLabel ?? this.emotionLabel,
      bodyState: bodyState ?? this.bodyState,
      psychState: psychState ?? this.psychState,
      actionState: actionState ?? this.actionState,
      location: location ?? this.location,
      atmosphere: atmosphere ?? this.atmosphere,
      presentCharacters: presentCharacters ?? this.presentCharacters,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() => {
        'storyId': storyId,
        'saveId': saveId,
        'affinity': affinity,
        'emotionValue': emotionValue,
        'emotionLabel': emotionLabel,
        'bodyState': bodyState,
        'psychState': psychState,
        'actionState': actionState,
        'location': location,
        'atmosphere': atmosphere,
        'presentCharacters':
            jsonEncode(presentCharacters.map((p) => p.toJson()).toList()),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory StoryScene.fromMap(Map<String, dynamic> map) {
    List<ScenePresence> presences = [];
    final raw = map['presentCharacters'];
    if (raw is String && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List<dynamic>;
        presences = list
            .map((e) => ScenePresence.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {}
    }
    return StoryScene(
      storyId: map['storyId'] as String? ?? '',
      saveId: map['saveId'] as String? ?? '',
      affinity: (map['affinity'] as num?)?.toInt() ?? 50,
      emotionValue: (map['emotionValue'] as num?)?.toInt() ?? 50,
      emotionLabel: map['emotionLabel'] as String? ?? '平静',
      bodyState: map['bodyState'] as String? ?? '',
      psychState: map['psychState'] as String? ?? '',
      actionState: map['actionState'] as String? ?? '',
      location: map['location'] as String? ?? '',
      atmosphere: map['atmosphere'] as String? ?? '',
      presentCharacters: presences,
      updatedAt:
          DateTime.tryParse(map['updatedAt'] as String? ?? '') ?? DateTime.now(),
    );
  }

  factory StoryScene.initial(String storyId, String saveId) => StoryScene(
        storyId: storyId,
        saveId: saveId,
        updatedAt: DateTime.now(),
      );
}
