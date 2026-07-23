import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';

/// 崽崽角色配置
///
/// 用户从 AI 角色中选择一个，把他的头像作为桌面悬浮窗崽崽形象。
/// 本配置描述崽崽的显示样式、动画参数、气泡台词池。
@immutable
class PetCharacterConfig {
  /// 角色 ID
  final String characterId;

  /// 角色名字
  final String name;

  /// 头像 URL（支持 asset:/network:/file:/solace://，由 AvatarResolver 解析）
  final String avatarUrl;

  /// 当前情绪标签：calm / happy / shy / angry / surprised / sleepy
  final String emotion;

  /// 头像框样式：none / gold / pink / blue / purple / neon
  final String frameStyle;

  /// 气泡样式：classic / rounded / cloud / heart
  final String bubbleStyle;

  /// 气泡台词池（从角色 catchphrases / openingLine / currentStatus 聚合）
  final List<String> bubbleLines;

  /// 是否启用主动气泡（待机时随机弹出）
  final bool enableIdleBubble;

  /// 主动气泡间隔（秒）
  final int idleBubbleIntervalSeconds;

  const PetCharacterConfig({
    required this.characterId,
    required this.name,
    required this.avatarUrl,
    this.emotion = 'calm',
    this.frameStyle = 'gold',
    this.bubbleStyle = 'rounded',
    this.bubbleLines = const [],
    this.enableIdleBubble = true,
    this.idleBubbleIntervalSeconds = 30,
  });

  bool get hasAvatar => avatarUrl.isNotEmpty;

  /// 随机取一条气泡台词
  String? randomLine() {
    if (bubbleLines.isEmpty) return null;
    return bubbleLines[Random().nextInt(bubbleLines.length)];
  }

  Map<String, dynamic> toJson() => {
        'characterId': characterId,
        'name': name,
        'avatarUrl': avatarUrl,
        'emotion': emotion,
        'frameStyle': frameStyle,
        'bubbleStyle': bubbleStyle,
        'bubbleLines': bubbleLines,
        'enableIdleBubble': enableIdleBubble,
        'idleBubbleIntervalSeconds': idleBubbleIntervalSeconds,
      };

  factory PetCharacterConfig.fromJson(Map<String, dynamic> json) {
    return PetCharacterConfig(
      characterId: json['characterId'] as String? ?? '',
      name: json['name'] as String? ?? '',
      avatarUrl: json['avatarUrl'] as String? ?? '',
      emotion: json['emotion'] as String? ?? 'calm',
      frameStyle: json['frameStyle'] as String? ?? 'gold',
      bubbleStyle: json['bubbleStyle'] as String? ?? 'rounded',
      bubbleLines: (json['bubbleLines'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      enableIdleBubble: json['enableIdleBubble'] as bool? ?? true,
      idleBubbleIntervalSeconds:
          (json['idleBubbleIntervalSeconds'] as int?) ?? 30,
    );
  }

  String toRawJson() => jsonEncode(toJson());

  factory PetCharacterConfig.fromRawJson(String raw) {
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return PetCharacterConfig.fromJson(map);
    } catch (_) {
      return PetCharacterConfig.empty();
    }
  }

  factory PetCharacterConfig.empty() => const PetCharacterConfig(
        characterId: '',
        name: '',
        avatarUrl: '',
      );

  PetCharacterConfig copyWith({
    String? characterId,
    String? name,
    String? avatarUrl,
    String? emotion,
    String? frameStyle,
    String? bubbleStyle,
    List<String>? bubbleLines,
    bool? enableIdleBubble,
    int? idleBubbleIntervalSeconds,
  }) {
    return PetCharacterConfig(
      characterId: characterId ?? this.characterId,
      name: name ?? this.name,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      emotion: emotion ?? this.emotion,
      frameStyle: frameStyle ?? this.frameStyle,
      bubbleStyle: bubbleStyle ?? this.bubbleStyle,
      bubbleLines: bubbleLines ?? this.bubbleLines,
      enableIdleBubble: enableIdleBubble ?? this.enableIdleBubble,
      idleBubbleIntervalSeconds:
          idleBubbleIntervalSeconds ?? this.idleBubbleIntervalSeconds,
    );
  }
}
