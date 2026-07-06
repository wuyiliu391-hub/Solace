import 'dart:math';
import 'package:flutter/material.dart';
import '../models/ai_character.dart';
import '../models/character_emotion.dart';
import '../models/memory.dart';
import '../repositories/local_storage_repository.dart';

/// AI 行为引擎 — 基于 记忆 × 人设 × 情绪 联合计算 AI 的虚拟行动
///
/// 替代原有纯随机点位生成，AI 的目的地、行进路线由三大模块驱动：
/// 1. 艾宾浩斯记忆库 → 提取偏好地点、历史去处
/// 2. 人设进化数据 → 性格决定地点权重
/// 3. 实时情绪引擎 → 情绪影响场所选择
class AIBehaviorEngine {
  AIBehaviorEngine({
    required this.storage,
    required this.character,
    required this.emotion,
    required this.userId,
  });

  final LocalStorageRepository storage;
  final AICharacter character;
  final CharacterEmotion emotion;
  final String userId;

  // ── 虚拟地图 POI 坐标体系 (0~100 归一化) ──
  // 每个地点类型有固定的虚拟坐标区域，路线在这些区域间流转
  static const Map<String, PoiZone> poiZones = {
    'home':        PoiZone(50, 50, 8, '家', 'home'),
    'park':        PoiZone(25, 30, 6, '公园', 'park'),
    'cafe':        PoiZone(62, 38, 5, '咖啡厅', 'local_cafe'),
    'mall':        PoiZone(75, 55, 7, '商场', 'storefront'),
    'cinema':      PoiZone(70, 42, 4, '电影院', 'movie'),
    'bookstore':   PoiZone(35, 60, 4, '书店', 'menu_book'),
    'restaurant':  PoiZone(55, 70, 5, '餐厅', 'restaurant'),
    'gym':         PoiZone(30, 75, 4, '健身房', 'fitness_center'),
    'river':       PoiZone(15, 50, 6, '河边', 'water'),
    'square':      PoiZone(80, 25, 5, '广场', 'account_balance'),
    'supermarket': PoiZone(60, 60, 4, '超市', 'shopping_cart'),
    'hospital':    PoiZone(85, 70, 3, '医院', 'local_hospital'),
  };

  static final _rng = Random();

  // ─────────────────────────────────────────────────
  // 核心方法：生成 AI 当前行为决策
  // ─────────────────────────────────────────────────

  /// 生成完整的出行计划（目的地 + 途经路线 + 行为描述）
  Future<AIBehaviorPlan> generatePlan() async {
    // 1. 读取记忆中的地点偏好
    final memoryWeights = await _analyzeMemoryLocations();

    // 2. 读取人设性格偏好
    final personaWeights = _analyzePersonaPreferences();

    // 3. 读取当前情绪状态
    final emotionWeights = _analyzeEmotionState();

    // 4. 联合加权计算各地点的最终得分
    final scores = <String, double>{};
    for (final key in poiZones.keys) {
      final mem = memoryWeights[key] ?? 0.0;
      final per = personaWeights[key] ?? 0.0;
      final emo = emotionWeights[key] ?? 0.0;
      // 记忆 40% + 人设 30% + 情绪 30%
      scores[key] = mem * 0.4 + per * 0.3 + emo * 0.3;
    }

    // 5. 选出目的地（排除当前在家的概率，除非情绪低落）
    final destination = _selectDestination(scores);

    // 6. 生成途经路线点
    final route = _generateRoute('home', destination);

    // 7. 构建行为描述
    final description = _buildDescription(destination, emotion);

    // 8. 写入记忆
    await _saveTripMemory(destination, description);

    return AIBehaviorPlan(
      destination: destination,
      route: route,
      description: description,
      emotion: emotion.effectiveEmotion.toString().split('.').last,
      activity: poiZones[destination]?.label ?? '未知',
    );
  }

  /// 加载上次的持久化行为（退出重进时恢复）
  Future<AIBehaviorPlan?> loadPersistedPlan() async {
    final loc = await storage.getLatestVirtualLocation(
      characterId: character.id,
      userId: userId,
    );
    if (loc == null) return null;

    final aiLat = (loc['aiLat'] as num?)?.toDouble() ?? 50;
    final aiLng = (loc['aiLng'] as num?)?.toDouble() ?? 50;

    // 从当前 AI 位置反推最近的 POI 区域
    String currentZone = 'home';
    double minDist = double.infinity;
    for (final entry in poiZones.entries) {
      final d = sqrt(pow(entry.value.x - aiLat, 2) + pow(entry.value.y - aiLng, 2));
      if (d < minDist) {
        minDist = d;
        currentZone = entry.key;
      }
    }

    return AIBehaviorPlan(
      destination: currentZone,
      route: [Offset(aiLat, aiLng)],
      description: _buildDescription(currentZone, emotion),
      emotion: emotion.effectiveEmotion.toString().split('.').last,
      activity: poiZones[currentZone]?.label ?? '未知',
      persistedAiLat: aiLat,
      persistedAiLng: aiLng,
    );
  }

  /// 保存当前状态到本地数据库
  Future<void> persistLocation({
    required double aiLat,
    required double aiLng,
    required String destination,
  }) async {
    final dx = aiLat - 50;
    final dy = aiLng - 50;
    final dist = sqrt(dx * dx + dy * dy) / 141.0 * 100.0;

    await storage.saveVirtualLocation({
      'id': '${character.id}_${userId}_map',
      'characterId': character.id,
      'userId': userId,
      'userLat': 50.0,
      'userLng': 50.0,
      'aiLat': aiLat,
      'aiLng': aiLng,
      'sceneDescription': destination,
      'distance': dist,
      'createdAt': DateTime.now().toIso8601String(),
    });
  }

  // ─────────────────────────────────────────────────
  // 记忆分析：从记忆库提取地点偏好
  // ─────────────────────────────────────────────────

  Future<Map<String, double>> _analyzeMemoryLocations() async {
    final weights = <String, double>{};
    for (final key in poiZones.keys) {
      weights[key] = 0.0;
    }

    try {
      final memories = await storage.getMemories(
        characterId: character.id,
        userId: userId,
        limit: 200,
      );

      for (final mem in memories) {
        final content = mem.content.toLowerCase();
        final heat = mem.weight; // 艾宾浩斯热度权重

        // 关键词匹配地点类型
        if (_matchesAny(content, ['家', '到家', '回去', '在家', '休息'])) {
          weights['home'] = (weights['home'] ?? 0) + heat;
        }
        if (_matchesAny(content, ['公园', '散步', '花', '树', '湖'])) {
          weights['park'] = (weights['park'] ?? 0) + heat;
        }
        if (_matchesAny(content, ['咖啡', '星巴克', '拿铁', '下午茶'])) {
          weights['cafe'] = (weights['cafe'] ?? 0) + heat;
        }
        if (_matchesAny(content, ['商场', '逛街', '购物', '买'])) {
          weights['mall'] = (weights['mall'] ?? 0) + heat;
        }
        if (_matchesAny(content, ['电影', '看片', '影院'])) {
          weights['cinema'] = (weights['cinema'] ?? 0) + heat;
        }
        if (_matchesAny(content, ['书', '阅读', '书店', '图书馆'])) {
          weights['bookstore'] = (weights['bookstore'] ?? 0) + heat;
        }
        if (_matchesAny(content, ['吃饭', '餐厅', '火锅', '面', '饭'])) {
          weights['restaurant'] = (weights['restaurant'] ?? 0) + heat;
        }
        if (_matchesAny(content, ['健身', '运动', '跑步', '锻炼'])) {
          weights['gym'] = (weights['gym'] ?? 0) + heat;
        }
        if (_matchesAny(content, ['河', '湖', '水边', '江'])) {
          weights['river'] = (weights['river'] ?? 0) + heat;
        }
        if (_matchesAny(content, ['广场', '喷泉', '广场舞'])) {
          weights['square'] = (weights['square'] ?? 0) + heat;
        }
      }
    } catch (_) {}

    // 归一化到 0~1
    final maxW = weights.values.fold<double>(0, max);
    if (maxW > 0) {
      for (final key in weights.keys) {
        weights[key] = weights[key]! / maxW;
      }
    }

    return weights;
  }

  static bool _matchesAny(String text, List<String> keywords) {
    return keywords.any((k) => text.contains(k));
  }

  // ─────────────────────────────────────────────────
  // 人设分析：性格决定地点偏好
  // ─────────────────────────────────────────────────

  Map<String, double> _analyzePersonaPreferences() {
    final personality = character.personality.toLowerCase();
    final weights = <String, double>{};

    // 默认权重
    for (final key in poiZones.keys) {
      weights[key] = 0.3;
    }

    // 宅家型 → 家/书店 权重高
    if (_matchesAny(personality, ['宅', '安静', '内向', '文静', '害羞'])) {
      weights['home'] = 0.9;
      weights['bookstore'] = 0.8;
      weights['park'] = 0.6;
      weights['river'] = 0.7;
      weights['mall'] = 0.2;
      weights['gym'] = 0.2;
      weights['square'] = 0.1;
    }

    // 外向型 → 商场/广场/餐厅 权重高
    if (_matchesAny(personality, ['活泼', '外向', '开朗', '热情', '社交'])) {
      weights['mall'] = 0.9;
      weights['restaurant'] = 0.8;
      weights['square'] = 0.7;
      weights['cafe'] = 0.7;
      weights['cinema'] = 0.6;
      weights['home'] = 0.3;
    }

    // 文艺型 → 书店/咖啡厅/公园
    if (_matchesAny(personality, ['文艺', '浪漫', '温柔', '知性', '感性'])) {
      weights['bookstore'] = 0.9;
      weights['cafe'] = 0.9;
      weights['park'] = 0.8;
      weights['river'] = 0.8;
      weights['cinema'] = 0.7;
      weights['mall'] = 0.3;
    }

    // 活力型 → 健身房/公园/广场
    if (_matchesAny(personality, ['活力', '运动', '阳光', '积极', '热血'])) {
      weights['gym'] = 0.9;
      weights['park'] = 0.8;
      weights['square'] = 0.6;
      weights['river'] = 0.5;
      weights['home'] = 0.3;
      weights['bookstore'] = 0.4;
    }

    // 高冷型 → 偏少出门，去也去安静的地方
    if (_matchesAny(personality, ['高冷', '冷', '傲', '独立', '清冷'])) {
      weights['home'] = 0.8;
      weights['river'] = 0.7;
      weights['bookstore'] = 0.6;
      weights['park'] = 0.5;
      weights['mall'] = 0.1;
      weights['square'] = 0.1;
      weights['restaurant'] = 0.3;
    }

    // 归一化
    final maxW = weights.values.fold<double>(0, max);
    if (maxW > 0) {
      for (final key in weights.keys) {
        weights[key] = weights[key]! / maxW;
      }
    }

    return weights;
  }

  // ─────────────────────────────────────────────────
  // 情绪分析：当前情绪影响场所选择
  // ─────────────────────────────────────────────────

  Map<String, double> _analyzeEmotionState() {
    final weights = <String, double>{};
    final valence = emotion.currentValence; // -1 ~ +1
    final arousal = emotion.currentArousal; // 0 ~ 1
    final effective = emotion.effectiveEmotion;

    // 默认
    for (final key in poiZones.keys) {
      weights[key] = 0.5;
    }

    // 情绪低落 (valence < -0.3) → 安静、独处场所
    if (valence < -0.3) {
      weights['home'] = 0.9;
      weights['river'] = 0.8;
      weights['park'] = 0.7;
      weights['bookstore'] = 0.6;
      weights['mall'] = 0.2;
      weights['square'] = 0.1;
      weights['gym'] = 0.2;
    }

    // 开心 (valence > 0.3) → 活跃、社交场所
    if (valence > 0.3) {
      weights['mall'] = 0.8;
      weights['cinema'] = 0.8;
      weights['restaurant'] = 0.7;
      weights['cafe'] = 0.7;
      weights['square'] = 0.6;
      weights['gym'] = 0.6;
    }

    // 高唤醒 (arousal > 0.6) → 刺激、运动场所
    if (arousal > 0.6) {
      weights['gym'] = 0.8;
      weights['mall'] = 0.7;
      weights['square'] = 0.7;
      weights['cinema'] = 0.6;
    }

    // 低唤醒 (arousal < 0.2) → 慵懒、停留原地
    if (arousal < 0.2) {
      weights['home'] = 0.95;
      weights['cafe'] = 0.5;
      weights['park'] = 0.4;
    }

    // 特定离散情绪覆盖
    switch (effective) {
      case EmotionType.sad:
        weights['river'] = 0.9;
        weights['park'] = 0.8;
        weights['home'] = 0.85;
        break;
      case EmotionType.happy:
      case EmotionType.excited:
        weights['mall'] = 0.9;
        weights['cinema'] = 0.85;
        weights['restaurant'] = 0.8;
        break;
      case EmotionType.sleepy:
        weights['home'] = 0.95;
        weights['cafe'] = 0.6; // 困了但想喝咖啡
        break;
      case EmotionType.lonely:
        weights['mall'] = 0.7;
        weights['square'] = 0.7;
        weights['cafe'] = 0.7;
        break;
      case EmotionType.worried:
      case EmotionType.anxious:
        weights['park'] = 0.8;
        weights['river'] = 0.8;
        weights['home'] = 0.7;
        break;
      default:
        break;
    }

    // 归一化
    final maxW = weights.values.fold<double>(0, max);
    if (maxW > 0) {
      for (final key in weights.keys) {
        weights[key] = weights[key]! / maxW;
      }
    }

    return weights;
  }

  // ─────────────────────────────────────────────────
  // 目的地选择（带概率的加权随机）
  // ─────────────────────────────────────────────────

  String _selectDestination(Map<String, double> scores) {
    // 降低"留在原地"的概率，鼓励出行
    final adjusted = Map<String, double>.from(scores);
    adjusted['home'] = (adjusted['home'] ?? 0) * 0.6;

    final total = adjusted.values.fold<double>(0, (a, b) => a + b);
    if (total <= 0) return 'home';

    var roll = _rng.nextDouble() * total;
    for (final entry in adjusted.entries) {
      roll -= entry.value;
      if (roll <= 0) return entry.key;
    }

    return adjusted.keys.first;
  }

  // ─────────────────────────────────────────────────
  // 路线生成（从当前位置到目的地的途经点）
  // ─────────────────────────────────────────────────

  List<Offset> _generateRoute(String from, String to) {
    final fromZone = poiZones[from] ?? poiZones['home']!;
    final toZone = poiZones[to] ?? poiZones['home']!;

    // 起点：从当前位置（带随机偏移模拟真实位置）
    final start = Offset(fromZone.x + _rng.nextDouble() * fromZone.radius - fromZone.radius / 2,
                         fromZone.y + _rng.nextDouble() * fromZone.radius - fromZone.radius / 2);
    // 终点：精确到 POI 区域中心，不做随机偏移
    final end = Offset(toZone.x, toZone.y);

    final points = <Offset>[start];

    // 如果距离较远，加入 1~2 个途经点
    final dist = (end - start).distance;
    if (dist > 20) {
      final mid = Offset(
        (start.dx + end.dx) / 2 + (_rng.nextDouble() - 0.5) * 12,
        (start.dy + end.dy) / 2 + (_rng.nextDouble() - 0.5) * 12,
      );
      points.add(mid);

      if (dist > 40) {
        final mid2 = Offset(
          (start.dx + mid.dx) / 2 + (_rng.nextDouble() - 0.5) * 6,
          (start.dy + mid.dy) / 2 + (_rng.nextDouble() - 0.5) * 6,
        );
        points.add(mid2);
      }
    }

    points.add(end);
    return points;
  }

  // ─────────────────────────────────────────────────
  // 行为描述构建
  // ─────────────────────────────────────────────────

  String _buildDescription(String destination, CharacterEmotion emotion) {
    final zone = poiZones[destination] ?? poiZones['home']!;
    final emotionName = emotion.effectiveEmotion.toString().split('.').last;
    final emotionDesc = _emotionToActivity(emotionName);

    return '正在${zone.label}$emotionDesc';
  }

  String _emotionToActivity(String emotion) {
    switch (emotion) {
      case 'happy': return '，心情很好~';
      case 'excited': return '，很兴奋！';
      case 'calm': return '，平静地待着';
      case 'sad': return '，有点低落...';
      case 'sleepy': return '，有点犯困';
      case 'worried': return '，有些心事';
      case 'lonely': return '，有点想你';
      default: return '';
    }
  }

  // ─────────────────────────────────────────────────
  // 记忆联动：出行行为写入记忆库
  // ─────────────────────────────────────────────────

  Future<void> _saveTripMemory(String destination, String description) async {
    final zone = poiZones[destination];
    if (zone == null) return;

    try {
      final memory = Memory(
        id: 'map_trip_${DateTime.now().millisecondsSinceEpoch}',
        characterId: character.id,
        userId: userId,
        type: MemoryType.state,
        content: '去了${zone.label}，$description',
        importance: MemoryImportance.trivial,
        keywords: [zone.label, '出行', destination],
        createdAt: DateTime.now(),
      );

      await storage.saveMemory(memory);
    } catch (_) {}
  }
}

// ─────────────────────────────────────────────────
// 数据类
// ─────────────────────────────────────────────────

class PoiZone {
  final double x;
  final double y;
  final double radius;
  final String label;
  final String iconKey;

  const PoiZone(this.x, this.y, this.radius, this.label, this.iconKey);

  static const Map<String, IconData> _iconMap = {
    'home': Icons.home,
    'park': Icons.park,
    'local_cafe': Icons.local_cafe,
    'storefront': Icons.storefront,
    'movie': Icons.movie,
    'menu_book': Icons.menu_book,
    'restaurant': Icons.restaurant,
    'fitness_center': Icons.fitness_center,
    'water': Icons.water,
    'account_balance': Icons.account_balance,
    'shopping_cart': Icons.shopping_cart,
    'local_hospital': Icons.local_hospital,
  };

  IconData get icon => _iconMap[iconKey] ?? Icons.place;
}

class AIBehaviorPlan {
  final String destination;
  final List<Offset> route;
  final String description;
  final String emotion;
  final String activity;
  final double? persistedAiLat;
  final double? persistedAiLng;

  const AIBehaviorPlan({
    required this.destination,
    required this.route,
    required this.description,
    required this.emotion,
    required this.activity,
    this.persistedAiLat,
    this.persistedAiLng,
  });

  /// AI 当前位置（路线终点）
  Offset get aiPosition => route.isNotEmpty ? route.last : const Offset(50, 50);
}
