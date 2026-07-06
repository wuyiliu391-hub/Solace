import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

/// AI 角色的情绪类型
enum EmotionType {
  happy('开心', '心情不错', Icons.sentiment_very_satisfied, Color(0xFFFFB74D)),
  excited('兴奋', '特别兴奋', Icons.celebration, Color(0xFFFF9800)),
  calm('平静', '状态平稳', Icons.sentiment_satisfied, Color(0xFF90CAF9)),
  worried('担心', '有点担心', Icons.sentiment_dissatisfied, Color(0xFFFFCC02)),
  sad('难过', '有些难过', Icons.sentiment_very_dissatisfied, Color(0xFF64B5F6)),
  angry('生气', '有点生气', Icons.sentiment_very_dissatisfied, Color(0xFFEF5350)),
  shy('害羞', '有点害羞', Icons.face_retouching_natural, Color(0xFFF48FB1)),
  touched('感动', '很感动', Icons.favorite, Color(0xFFE91E63)),
  lonely('孤独', '有点孤独', Icons.person_outline, Color(0xFF90CAF9)),
  miss('想念', '在想你', Icons.favorite_border, Color(0xFFF48FB1)),
  anxious('焦虑', '有些焦虑', Icons.psychology, Color(0xFFFFCC02)),
  sleepy('困倦', '有点困', Icons.bedtime, Color(0xFF9FA8DA)),
  playful('调皮', '想调皮一下', Icons.emoji_emotions, Color(0xFFFF8A65)),
  ;

  final String label;
  final String description;
  final IconData icon;
  final Color color;

  const EmotionType(this.label, this.description, this.icon, this.color);

  /// 兼容旧代码的 emoji 字符串（用于存储/序列化）
  String get emoji => label;
}

/// AI 角色的情绪状态（v2 — 增加连续维度 + 情感惯性）
///
/// 双轨模型：
/// - 离散情绪（primaryEmotion）→ 用于UI显示和表情动作
/// - 连续维度（valence/arousal）→ 用于行为决策和情感惯性
///
/// 借鉴 AICO 的情感惯性模型：
/// - 情绪不会突变，新事件只是把旧情绪"推"向新方向
/// - 85%保留旧状态 + 15%接受新事件
/// - 每小时向性格基线回拉 10%
class CharacterEmotion extends Equatable {
  final String characterId;
  final String userId;
  final EmotionType primaryEmotion;
  final double intensity; // 0.0 ~ 1.0（离散情绪强度）
  final String? trigger;  // 触发原因
  final DateTime updatedAt;

  // ── v2 新增：连续维度 ──
  final double valence; // -1.0（极度消极）~ +1.0（极度积极）
  final double arousal; // 0.0（平静）~ 1.0（激动）
  final DateTime? lastInteractionTime; // 上次互动时间（用于孤独追踪）

  const CharacterEmotion({
    required this.characterId,
    required this.userId,
    required this.primaryEmotion,
    required this.intensity,
    this.trigger,
    required this.updatedAt,
    this.valence = 0.0,
    this.arousal = 0.3,
    this.lastInteractionTime,
  });

  /// 情绪会随时间自然衰减
  /// 衰减速率：每小时降低 0.03，大约 33 小时回到基准
  double get currentIntensity {
    final hoursElapsed = DateTime.now().difference(updatedAt).inMinutes / 60.0;
    final decayed = intensity - hoursElapsed * 0.03;
    return decayed.clamp(0.0, 1.0);
  }

  /// 情绪是否已衰减到基准（平静）
  bool get hasDecayed => currentIntensity < 0.1;

  /// 获取当前有效的情绪（如果衰减完毕则返回平静）
  EmotionType get effectiveEmotion =>
      hasDecayed ? EmotionType.calm : primaryEmotion;

  // ── v2 新增：连续维度属性 ──

  /// 当前 valence（考虑基线回拉）
  ///
  /// 回拉规则：每小时向 0.0 移动 0.1，但不会越过 0（不会从正变负或从负变正）
  /// 这保证了情绪的长期惯性——悲伤不会突然变开心，只是慢慢淡化
  double get currentValence {
    final hours = DateTime.now().difference(updatedAt).inMinutes / 60.0;
    final pull = hours * 0.1;
    if (valence > 0) {
      // 正向情绪：回拉但不低于 0
      return (valence - pull).clamp(0.0, 1.0);
    }
    if (valence < 0) {
      // 负向情绪：回拉但不高于 0
      return (valence + pull).clamp(-1.0, 0.0);
    }
    return 0.0;
  }

  /// 当前 arousal（考虑衰减）
  double get currentArousal {
    final hours = DateTime.now().difference(updatedAt).inMinutes / 60.0;
    // 每小时向 0.3（中等活跃）回拉
    final target = 0.3;
    final decay = hours * 0.08;
    if (arousal > target) return (arousal - decay).clamp(0.0, 1.0);
    if (arousal < target) return (arousal + decay).clamp(0.0, 1.0);
    return arousal;
  }

  /// 孤独度（0-1）：长时间不互动 + 情绪低落 = 更孤独
  double get loneliness {
    final hoursSinceInteraction = lastInteractionTime != null
        ? DateTime.now().difference(lastInteractionTime!).inMinutes / 60.0
        : 24.0; // 默认24小时
    final timeFactor = (hoursSinceInteraction / 4).clamp(0.0, 1.0);
    final moodFactor = ((1.0 - currentValence) / 2).clamp(0.0, 1.0);
    final energyFactor = currentArousal;
    return (timeFactor * 0.5 + moodFactor * 0.3 + energyFactor * 0.2).clamp(0.0, 1.0);
  }

  /// 紧迫度（0-1）：用于 ASE 主动行为决策
  double get urgency {
    final lon = loneliness;
    final negativeMood = ((-currentValence + 1) / 2).clamp(0.0, 1.0);
    return (lon * 0.6 + negativeMood * 0.4).clamp(0.0, 1.0);
  }

  /// 是否应该主动找用户（紧迫度 > 阈值）
  bool get shouldReachOut => urgency > 0.35;

  CharacterEmotion copyWith({
    EmotionType? primaryEmotion,
    double? intensity,
    String? trigger,
    DateTime? updatedAt,
    double? valence,
    double? arousal,
    DateTime? lastInteractionTime,
  }) {
    return CharacterEmotion(
      characterId: characterId,
      userId: userId,
      primaryEmotion: primaryEmotion ?? this.primaryEmotion,
      intensity: intensity ?? this.intensity,
      trigger: trigger ?? this.trigger,
      updatedAt: updatedAt ?? this.updatedAt,
      valence: valence ?? this.valence,
      arousal: arousal ?? this.arousal,
      lastInteractionTime: lastInteractionTime ?? this.lastInteractionTime,
    );
  }

  @override
  List<Object?> get props => [characterId, userId, primaryEmotion, intensity, trigger, updatedAt, valence, arousal, lastInteractionTime];
}