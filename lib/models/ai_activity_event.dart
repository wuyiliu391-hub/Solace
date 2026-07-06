import 'package:flutter/material.dart';

/// AI 活动事件类型
enum AIActivityType {
  emotionChange, // 情绪变化
  innerThought, // 内心独白
  momentPost, // 发布动态
  memoryFormed, // 形成新记忆
  evolution, // 人格进化
  letterSent, // 自动来信
  milestone, // 里程碑（纪念日等）
  weatherMood, // 天气影响心情
}

/// AI 活动事件 — 用于活动动态流展示
class AIActivityEvent {
  final String id;
  final String characterId;
  final String characterName;
  final String? characterAvatar;
  final AIActivityType type;
  final String title;
  final String subtitle;
  final String? detail;
  final DateTime createdAt;

  const AIActivityEvent({
    required this.id,
    required this.characterId,
    required this.characterName,
    this.characterAvatar,
    required this.type,
    required this.title,
    required this.subtitle,
    this.detail,
    required this.createdAt,
  });

  /// 获取事件图标
  IconData get icon {
    switch (type) {
      case AIActivityType.emotionChange:
        return Icons.psychology;
      case AIActivityType.innerThought:
        return Icons.lightbulb_outline;
      case AIActivityType.momentPost:
        return Icons.edit_note;
      case AIActivityType.memoryFormed:
        return Icons.memory;
      case AIActivityType.evolution:
        return Icons.spa;
      case AIActivityType.letterSent:
        return Icons.mark_email_unread;
      case AIActivityType.milestone:
        return Icons.emoji_events;
      case AIActivityType.weatherMood:
        return Icons.cloud;
    }
  }

  /// 获取事件颜色
  Color get color {
    switch (type) {
      case AIActivityType.emotionChange:
        return const Color(0xFF9C27B0);
      case AIActivityType.innerThought:
        return const Color(0xFF2196F3);
      case AIActivityType.momentPost:
        return const Color(0xFF4CAF50);
      case AIActivityType.memoryFormed:
        return const Color(0xFFFF9800);
      case AIActivityType.evolution:
        return const Color(0xFF009688);
      case AIActivityType.letterSent:
        return const Color(0xFFE91E63);
      case AIActivityType.milestone:
        return const Color(0xFFF44336);
      case AIActivityType.weatherMood:
        return const Color(0xFF00BCD4);
    }
  }
}
