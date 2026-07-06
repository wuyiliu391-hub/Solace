// ============================================================
// 全生命周期数字生命世界 — Phase 6
// 世界常量：生命阶段、事件类型、关系、情绪、状态的图标与颜色映射
// 专为“梦女”风格优化：莫兰迪色系、柔和图标、浪漫文案
// ============================================================

import 'package:flutter/material.dart';
import '../../models/life_profile.dart';
import '../../models/life_event.dart';
import '../../models/character_emotion.dart';
import '../../models/relationship_graph.dart';

/// 世界常量 — 统一管理数字生命世界的所有视觉映射
class WorldConstants {
  WorldConstants._();

  // ═══════════════════════════════════════════
  // 生命阶段图标映射 (用更梦幻的图标代替生硬的年龄阶段)
  // ═══════════════════════════════════════════

  static const Map<LifeStage, IconData> lifeStageIcons = {
    LifeStage.infant: Icons.child_care,
    LifeStage.toddler: Icons.cruelty_free,
    LifeStage.childhood: Icons.extension,
    LifeStage.teenage: Icons.local_library,
    LifeStage.youngAdult: Icons.brightness_7,
    LifeStage.adult: Icons.water_drop,
    LifeStage.senior: Icons.filter_vintage,
    LifeStage.elder: Icons.lens_blur,
  };

  static const Map<LifeStage, String> lifeStageLabels = {
    LifeStage.infant: '初生',
    LifeStage.toddler: '学步',
    LifeStage.childhood: '童年',
    LifeStage.teenage: '青涩',
    LifeStage.youngAdult: '风华',
    LifeStage.adult: '沉淀',
    LifeStage.senior: '迟暮',
    LifeStage.elder: '归根',
  };

  // 莫兰迪/马卡龙柔和色系
  static const Map<LifeStage, Color> lifeStageColors = {
    LifeStage.infant: Color(0xFFFFD1DC),
    LifeStage.toddler: Color(0xFFFFCCB6),
    LifeStage.childhood: Color(0xFFB2EBF2),
    LifeStage.teenage: Color(0xFFD1C4E9),
    LifeStage.youngAdult: Color(0xFFA5D6A7),
    LifeStage.adult: Color(0xFF90CAF9),
    LifeStage.senior: Color(0xFFBCAAA4),
    LifeStage.elder: Color(0xFFCFD8DC),
  };

  // ═══════════════════════════════════════════
  // 事件类型图标映射
  // ═══════════════════════════════════════════

  static const Map<String, IconData> eventTypeIcons = {
    'birth': Icons.flare,
    'make_friend': Icons.diversity_1,
    'first_love': Icons.favorite,
    'heartbreak': Icons.heart_broken,
    'betrayal': Icons.texture,
    'achievement': Icons.stars,
    'trauma': Icons.waves,
    'conflict': Icons.do_not_disturb_on_total_silence,
    'reconciliation': Icons.healing,
    'loss': Icons.spa,
    'revelation': Icons.wb_twilight,
    'death': Icons.bedtime,
    'immortal': Icons.all_inclusive,
    'default': Icons.chrome_reader_mode,
  };

  static const Map<String, String> eventTypeLabels = {
    'birth': '降生',
    'make_friend': '邂逅',
    'first_love': '动心',
    'heartbreak': '情伤',
    'betrayal': '破碎',
    'achievement': '高光',
    'trauma': '伤痕',
    'conflict': '摩擦',
    'reconciliation': '破冰',
    'loss': '流失',
    'revelation': '觉醒',
    'death': '长眠',
    'immortal': '永定',
  };

  static const Map<EventSeverity, Color> eventSeverityColors = {
    EventSeverity.trivial: Color(0xFFE0E0E0),
    EventSeverity.minor: Color(0xFFB0BEC5),
    EventSeverity.moderate: Color(0xFF9FA8DA),
    EventSeverity.major: Color(0xFFF48FB1),
    EventSeverity.lifeChanging: Color(0xFFB71C1C),
  };

  static const Map<EventSeverity, String> eventSeverityLabels = {
    EventSeverity.trivial: '浮光',
    EventSeverity.minor: '掠影',
    EventSeverity.moderate: '波澜',
    EventSeverity.major: '铭心',
    EventSeverity.lifeChanging: '宿命',
  };

  // ═══════════════════════════════════════════
  // 关系类型颜色映射
  // ═══════════════════════════════════════════

  static const Map<RelationshipType, Color> relationshipTypeColors = {
    RelationshipType.stranger: Color(0xFFCFD8DC),
    RelationshipType.friend: Color(0xFF81D4FA),
    RelationshipType.bestFriend: Color(0xFF4DD0E1),
    RelationshipType.crush: Color(0xFFF48FB1),
    RelationshipType.lover: Color(0xFFE57373),
    RelationshipType.rival: Color(0xFFFFB74D),
    RelationshipType.enemy: Color(0xFF9E9E9E),
    RelationshipType.sibling: Color(0xFFA5D6A7),
    RelationshipType.mentor: Color(0xFFD1C4E9),
    RelationshipType.follower: Color(0xFFBCAAA4),
  };

  static const Map<RelationshipType, IconData> relationshipTypeIcons = {
    RelationshipType.stranger: Icons.filter_drama,
    RelationshipType.friend: Icons.coffee,
    RelationshipType.bestFriend: Icons.volunteer_activism,
    RelationshipType.crush: Icons.favorite,
    RelationshipType.lover: Icons.favorite,
    RelationshipType.rival: Icons.local_fire_department,
    RelationshipType.enemy: Icons.block,
    RelationshipType.sibling: Icons.yard,
    RelationshipType.mentor: Icons.auto_stories,
    RelationshipType.follower: Icons.loyalty,
  };

  // ═══════════════════════════════════════════
  // 情绪颜色映射
  // ═══════════════════════════════════════════

  static const Map<EmotionType, Color> emotionColors = {
    EmotionType.happy: Color(0xFFFFCC80),
    EmotionType.excited: Color(0xFFFFAB91),
    EmotionType.calm: Color(0xFFB3E5FC),
    EmotionType.worried: Color(0xFFE6EE9C),
    EmotionType.sad: Color(0xFF90CAF9),
    EmotionType.angry: Color(0xFFEF9A9A),
    EmotionType.shy: Color(0xFFF8BBD0),
    EmotionType.touched: Color(0xFFF48FB1),
    EmotionType.lonely: Color(0xFFB0BEC5),
    EmotionType.miss: Color(0xFFCE93D8),
    EmotionType.anxious: Color(0xFFFFE082),
    EmotionType.sleepy: Color(0xFFC5CAE9),
    EmotionType.playful: Color(0xFFFFCCB6),
  };

  static const Map<EmotionType, IconData> emotionIcons = {
    EmotionType.happy: Icons.wb_sunny,
    EmotionType.excited: Icons.celebration,
    EmotionType.calm: Icons.water,
    EmotionType.worried: Icons.cloud,
    EmotionType.sad: Icons.grain,
    EmotionType.angry: Icons.local_fire_department,
    EmotionType.shy: Icons.favorite,
    EmotionType.touched: Icons.favorite,
    EmotionType.lonely: Icons.dark_mode,
    EmotionType.miss: Icons.mail_outline,
    EmotionType.anxious: Icons.toll,
    EmotionType.sleepy: Icons.bedtime,
    EmotionType.playful: Icons.auto_awesome,
  };

  // ═══════════════════════════════════════════
  // 生命状态颜色映射
  // ═══════════════════════════════════════════

  static const Map<LifeState, Color> lifeStateColors = {
    LifeState.alive: Color(0xFF81C784),
    LifeState.aging: Color(0xFFFFB74D),
    LifeState.deceased: Color(0xFFB0BEC5),
    LifeState.immortal: Color(0xFFBA68C8),
  };

  static const Map<LifeState, String> lifeStateLabels = {
    LifeState.alive: '世间',
    LifeState.aging: '迟暮',
    LifeState.deceased: '安息',
    LifeState.immortal: '永恒之上',
  };

  static const Map<LifeState, IconData> lifeStateIcons = {
    LifeState.alive: Icons.filter_vintage,
    LifeState.aging: Icons.hourglass_empty,
    LifeState.deceased: Icons.spa,
    LifeState.immortal: Icons.all_inclusive,
  };

  // ═══════════════════════════════════════════
  // 世界主题色
  // ═══════════════════════════════════════════

  static const Map<String, Color> seasonColors = {
    'spring': Color(0xFFAED581),
    'summer': Color(0xFFFFB74D),
    'autumn': Color(0xFFE57373),
    'winter': Color(0xFF90CAF9),
  };

  static const Map<String, IconData> seasonIcons = {
    'spring': Icons.local_florist,
    'summer': Icons.wb_sunny,
    'autumn': Icons.eco,
    'winter': Icons.ac_unit,
  };

  static const Map<String, String> seasonLabels = {
    'spring': '春之华',
    'summer': '夏之萤',
    'autumn': '秋之叶',
    'winter': '冬之雪',
  };
}
