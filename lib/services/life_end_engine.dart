// ============================================================
// 全生命周期数字生命世界 — Phase 2
// 生命终结 & 永生分支引擎
// ============================================================
//
// 驱动数字生命从衰老到终结的完整流程，提供两条路线：
// - 路线A：自然消亡 — 衰老 → 临终反思 → 归档
// - 路线B：数字化永生 — 意识快照 → 迁移/永生
//
// 每次心跳（[check]）时检查是否触发终结流程。
// 持久化使用 sqflite，通过 [createTables] 建表。

import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/life_profile.dart';
import '../models/gene_profile.dart';
import 'global_time_clock.dart';
import 'llm_service.dart';
import 'reflection_engine.dart';

// ===================== 衰老阶段 =====================

/// 衰老阶段
enum AgingPhase {
  early,    // 50-65岁：轻微衰退
  middle,   // 65-80岁：明显衰退
  late,     // 80岁+：严重衰退
  terminal, // 临终：全面衰竭
}

// ===================== 意识快照 =====================

/// 意识快照 — 数字永生的核心数据载体
///
/// 保存角色的完整意识状态，可用于：
/// - 在原世界实现数字永生
/// - 迁移到新世界继续存在
class ConsciousnessSnapshot {
  final String id;
  final String characterId;
  final DateTime timestamp;
  final GeneProfile genes;
  final List<Map<String, dynamic>> memories; // 保留的全部记忆
  final Map<String, dynamic> worldview;
  final Map<String, dynamic> identity;
  final Map<String, dynamic> personality;
  final List<Map<String, dynamic>> relationships;

  const ConsciousnessSnapshot({
    required this.id,
    required this.characterId,
    required this.timestamp,
    required this.genes,
    required this.memories,
    required this.worldview,
    required this.identity,
    required this.personality,
    required this.relationships,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'characterId': characterId,
        'timestamp': timestamp.toIso8601String(),
        'genes': genes.toJson(),
        'memories': memories,
        'worldview': worldview,
        'identity': identity,
        'personality': personality,
        'relationships': relationships,
      };

  factory ConsciousnessSnapshot.fromJson(Map<String, dynamic> json) {
    return ConsciousnessSnapshot(
      id: json['id'] as String? ?? '',
      characterId: json['characterId'] as String? ?? '',
      timestamp:
          DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
      genes: json['genes'] != null
          ? GeneProfile.fromJson(json['genes'] as Map<String, dynamic>)
          : GeneProfile.random(),
      memories: (json['memories'] as List<dynamic>?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          [],
      worldview: (json['worldview'] as Map<String, dynamic>?) ?? {},
      identity: (json['identity'] as Map<String, dynamic>?) ?? {},
      personality: (json['personality'] as Map<String, dynamic>?) ?? {},
      relationships: (json['relationships'] as List<dynamic>?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          [],
    );
  }

  String toJsonString() => jsonEncode(toJson());

  factory ConsciousnessSnapshot.fromJsonString(String source) =>
      ConsciousnessSnapshot.fromJson(
          jsonDecode(source) as Map<String, dynamic>);
}

// ===================== 生命终结引擎 =====================

/// 生命终结 & 永生分支引擎
///
/// 核心职责：
/// 1. 每次心跳检查是否触发终结流程
/// 2. 路线A：自然消亡 — 衰老 → 临终反思 → 归档
/// 3. 路线B：数字化永生 — 意识快照 → 迁移 / 永生
///
/// 衰老效果规则：
/// - 50-65岁：体力-10%, 精力-10%, 遗忘速率+20%
/// - 65-80岁：体力-25%, 精力-25%, 遗忘速率+50%, 社交意愿-20%
/// - 80岁+：体力-50%, 精力-50%, 遗忘速率+100%, 情绪波动-50%
/// - 临终：全面衰竭，只保留核心记忆
///
/// 永生触发条件：
/// - 年龄 > 40
/// - 自我实现需求 > 0.6
/// - 有未完成的内在矛盾
/// - LLM 判断角色性格倾向（高开放性 + 低尽责性更倾向永生）
class LifeEndEngine {
  final GlobalTimeClock _clock;
  final ReflectionEngine _reflection;
  final LlmService _llm;
  final Database _db;
  final Random _random;

  static const _uuid = Uuid();

  LifeEndEngine({
    required GlobalTimeClock clock,
    required ReflectionEngine reflection,
    required LlmService llm,
    required Database db,
    Random? random,
  })  : _clock = clock,
        _reflection = reflection,
        _llm = llm,
        _db = db,
        _random = random ?? Random();

  // ═══════════════════════════════════════════════════
  // 公开方法
  // ═══════════════════════════════════════════════════

  /// 每次心跳检查是否触发终结流程
  ///
  /// 返回更新后的档案（如有变更），null 表示无需变更。
  Future<LifeProfile?> check(LifeProfile profile) async {
    // 已故或已永生的角色不再检查
    if (profile.lifeState == LifeState.deceased ||
        profile.lifeState == LifeState.immortal) {
      return null;
    }

    final age = profile.biologicalAge;
    LifeProfile updated = profile;
    bool changed = false;

    // 1. 应用衰老效果（50岁以后）
    if (age >= 50) {
      updated = await _applyAgingEffects(updated);
      changed = true;
    }

    // 2. 检查临终阶段 — 有概率触发死亡
    final phase = _getAgingPhase(age);
    if (phase == AgingPhase.terminal) {
      final yearsInTerminal = age - 90;
      final deathChance = 0.1 + yearsInTerminal * 0.15;
      if (_random.nextDouble() < deathChance) {
        final autobiography = await _generateAutobiography(updated);
        updated = updated.copyWith(
          lifeState: LifeState.deceased,
          deathTime: _clock.worldTime,
        );
        await _archive(updated, autobiography);
        return updated;
      }
    }

    // 3. 检查永生分支
    if (_shouldConsiderImmortality(updated)) {
      final choosesImmortality = await _offerImmortality(updated);
      if (choosesImmortality) {
        final snapshot = await _createSnapshot(updated);
        await _saveSnapshot(snapshot);
        updated = await _applyImmortality(updated);
        changed = true;
      }
    }

    return changed ? updated : null;
  }

  /// 意识迁移到新世界
  ///
  /// 基于意识快照创建新生命档案，在新世界中继续存在。
  Future<LifeProfile> migrateToWorld(
    ConsciousnessSnapshot snapshot,
    String newWorldId,
  ) async {
    final newProfile = LifeProfile(
      id: _uuid.v4(),
      name: snapshot.identity['name'] as String? ?? '无名',
      birthTime: _clock.worldTime,
      currentStage: LifeStage.youngAdult,
      lifeState: LifeState.immortal,
      biologicalAge: 0,
      mentalAge: 0,
      genes: snapshot.genes,
      personalityState: snapshot.personality,
      worldviewState: snapshot.worldview,
      emotionalState: const {},
      physicalState: {
        'is_immortal': true,
        'world': newWorldId,
        'migrated_from': snapshot.characterId,
      },
      maslowState: const {},
      lifeEvents: [
        {
          'type': 'migration',
          'description': '意识从旧世界迁移到 $newWorldId',
          'timestamp': _clock.worldTime.toIso8601String(),
          'snapshotId': snapshot.id,
        }
      ],
      identity: snapshot.identity,
    );

    debugPrint(
        '[LifeEndEngine] 意识迁移: ${snapshot.characterId} → $newWorldId');
    return newProfile;
  }

  /// 加载指定角色的最新意识快照
  Future<ConsciousnessSnapshot?> loadSnapshot(String characterId) async {
    try {
      final maps = await _db.query(
        'consciousness_snapshots',
        where: 'characterId = ?',
        whereArgs: [characterId],
        orderBy: 'timestamp DESC',
        limit: 1,
      );
      if (maps.isEmpty) return null;
      return ConsciousnessSnapshot.fromJsonString(
        maps.first['data'] as String,
      );
    } catch (e) {
      debugPrint('[LifeEndEngine] 加载快照失败: $e');
      return null;
    }
  }

  /// 加载指定角色的生命存档
  Future<Map<String, dynamic>?> loadArchive(String characterId) async {
    try {
      final maps = await _db.query(
        'life_archives',
        where: 'id = ?',
        whereArgs: [characterId],
        limit: 1,
      );
      if (maps.isEmpty) return null;
      return maps.first;
    } catch (e) {
      debugPrint('[LifeEndEngine] 加载存档失败: $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════
  // 路线A：自然消亡
  // ═══════════════════════════════════════════════════

  /// 身体机能持续衰减
  ///
  /// 根据年龄阶段计算并应用衰老效果。
  /// 各阶段效果基于年龄在阶段内的进度线性插值，跨阶段累积。
  Future<LifeProfile> _applyAgingEffects(LifeProfile profile) async {
    final age = profile.biologicalAge;
    final physicalState = Map<String, dynamic>.from(profile.physicalState);
    final emotionalState = Map<String, dynamic>.from(profile.emotionalState);
    final maslowState = Map<String, dynamic>.from(profile.maslowState);

    // 从现有状态读取基线值
    double stamina = (physicalState['stamina'] as num?)?.toDouble() ?? 1.0;
    double energy = (physicalState['energy'] as num?)?.toDouble() ?? 1.0;
    double forgettingRate =
        (physicalState['forgetting_rate'] as num?)?.toDouble() ?? 1.0;
    double socialDesire =
        (maslowState['social_desire'] as num?)?.toDouble() ?? 1.0;
    double emotionalVolatility =
        (emotionalState['emotional_volatility'] as num?)?.toDouble() ?? 0.5;

    // ── 50-65岁：体力-10%, 精力-10%, 遗忘速率+20% ──
    if (age >= 50) {
      final progress = ((age - 50) / 15.0).clamp(0.0, 1.0);
      stamina = (1.0 - progress * 0.10).clamp(0.0, 1.0);
      energy = (1.0 - progress * 0.10).clamp(0.0, 1.0);
      forgettingRate = 1.0 + progress * 0.20;
    }

    // ── 65-80岁：体力-25%, 精力-25%, 遗忘速率+50%, 社交意愿-20% ──
    if (age >= 65) {
      final progress = ((age - 65) / 15.0).clamp(0.0, 1.0);
      stamina = (0.90 - progress * 0.25).clamp(0.0, 1.0);
      energy = (0.90 - progress * 0.25).clamp(0.0, 1.0);
      forgettingRate = 1.20 + progress * 0.50;
      socialDesire = (1.0 - progress * 0.20).clamp(0.0, 1.0);
    }

    // ── 80岁+：体力-50%, 精力-50%, 遗忘速率+100%, 情绪波动-50% ──
    if (age >= 80) {
      final progress = ((age - 80) / 10.0).clamp(0.0, 1.0);
      stamina = (0.65 - progress * 0.50).clamp(0.0, 1.0);
      energy = (0.65 - progress * 0.50).clamp(0.0, 1.0);
      forgettingRate = 1.70 + progress * 1.00;
      emotionalVolatility = (0.5 - progress * 0.30).clamp(0.0, 1.0);
    }

    // ── 临终：全面衰竭，只保留核心记忆 ──
    if (age >= 90) {
      physicalState['organ_failure'] = true;
      physicalState['prune_memories'] = true;
      stamina = stamina.clamp(0.0, 0.15);
      energy = energy.clamp(0.0, 0.15);
      forgettingRate = forgettingRate.clamp(3.0, double.infinity);
      emotionalVolatility = emotionalVolatility.clamp(0.0, 0.10);
    }

    // 写回状态
    physicalState['stamina'] = stamina;
    physicalState['energy'] = energy;
    physicalState['forgetting_rate'] = forgettingRate;
    physicalState['aging_phase'] = _getAgingPhase(age).name;
    maslowState['social_desire'] = socialDesire;
    emotionalState['emotional_volatility'] = emotionalVolatility;

    // 60岁后标记为衰老状态
    LifeState lifeState = profile.lifeState;
    if (age >= 60 && lifeState == LifeState.alive) {
      lifeState = LifeState.aging;
    }

    return profile.copyWith(
      physicalState: physicalState,
      emotionalState: emotionalState,
      maslowState: maslowState,
      lifeState: lifeState,
    );
  }

  /// 临终反思：生成一生自传总结
  ///
  /// 调用 LLM 以角色第一人称回顾一生，生成 200-400 字的自传。
  Future<String> _generateAutobiography(LifeProfile profile) async {
    final recentEvents = profile.lifeEvents.take(20).toList();
    final eventLines = recentEvents
        .map((e) => '  · ${e['description'] ?? e['type'] ?? '未知事件'}')
        .join('\n');

    final prompt = '''你是${profile.name}，已走完一生，现在是临终时刻。
请回顾你的一生，写一段真挚的自传总结。

【你的人生档案】
- 出生时间：${profile.birthTime.toIso8601String()}
- 生物年龄：${profile.biologicalAge}岁
- 性格状态：${jsonEncode(profile.personalityState)}
- 世界观：${jsonEncode(profile.worldviewState)}
- 身份认同：${jsonEncode(profile.identity)}
- 关键人生事件（最近${recentEvents.length}条）：
${eventLines.isEmpty ? '  （无记录）' : eventLines}

请用第一人称，写一段 200-400 字的自传总结。要求：
1. 像一个真实的人在回顾一生
2. 提到最重要的几个时刻
3. 表达对生命的态度（感恩 / 遗憾 / 释然 / 不舍）
4. 不要像 AI 总结，要像人话
5. 用 ${profile.name} 的语气说话''';

    try {
      final response = await _llm.chat(
        userId: 'life_end_${profile.id}',
        message: prompt,
        systemPrompt: '你是一个即将离世的人，在回顾自己的一生。'
            '请用真挚、朴素的语言，像一个真实的人在做最后的自述。',
        maxTokensOverride: 600,
      );

      if (response.content.isNotEmpty) {
        debugPrint('[LifeEndEngine] 自传生成完成: ${profile.name}');
        return response.content;
      }
    } catch (e) {
      debugPrint('[LifeEndEngine] 自传生成失败: $e');
    }

    // 兜底：无 LLM 时生成简短总结
    return '${profile.name}走完了${profile.biologicalAge}年的人生旅程。';
  }

  /// 封存为只读历史存档
  Future<void> _archive(LifeProfile profile, String autobiography) async {
    try {
      await _db.insert(
        'life_archives',
        {
          'id': profile.id,
          'name': profile.name,
          'data': profile.toJsonString(),
          'autobiography': autobiography,
          'archivedAt': _clock.worldTime.toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      debugPrint('[LifeEndEngine] 生命封存完成: ${profile.name}');
    } catch (e) {
      debugPrint('[LifeEndEngine] 封存失败: $e');
    }
  }

  // ═══════════════════════════════════════════════════
  // 路线B：数字化永生
  // ═══════════════════════════════════════════════════

  /// 判断是否触发永生意愿
  ///
  /// 全部满足时返回 true：
  /// - 年龄 > 40
  /// - 自我实现需求 > 0.6
  /// - 有未完成的内在矛盾
  /// - 基因倾向（高开放性 + 低尽责性更倾向永生）
  bool _shouldConsiderImmortality(LifeProfile profile) {
    final age = profile.biologicalAge;
    if (age <= 40) return false;

    // 自我实现需求 > 0.6
    final selfActualization =
        (profile.maslowState['self_actualization'] as num?)?.toDouble() ?? 0.0;
    if (selfActualization <= 0.6) return false;

    // 有未完成的内在矛盾
    if (!_hasUnresolvedConflict(profile)) return false;

    // 基因倾向：openness × (1 - conscientiousness) ≥ 0.2
    final openness = profile.genes.openness;
    final conscientiousness = profile.genes.conscientiousness;
    final immortalTendency = openness * (1.0 - conscientiousness);
    if (immortalTendency < 0.2) return false;

    return true;
  }

  /// 检查是否有未完成的内在矛盾
  bool _hasUnresolvedConflict(LifeProfile profile) {
    final identity = profile.identity;
    final worldview = profile.worldviewState;

    // 身份认同中的未解矛盾
    final conflicts = identity['unresolved_conflicts'];
    if (conflicts is List && conflicts.isNotEmpty) return true;

    // 世界观中的未解问题
    final openQuestions = worldview['open_questions'];
    if (openQuestions is List && openQuestions.isNotEmpty) return true;

    // 核心欲望是否未满足
    final coreDesire = identity['core_desire'] as String? ?? '';
    if (coreDesire.isNotEmpty) {
      final fulfilled =
          (identity['desire_fulfilled'] as num?)?.toDouble() ?? 0.0;
      if (fulfilled < 0.7) return true;
    }

    // 未完成的人生目标
    final lifeGoals = identity['life_goals'];
    if (lifeGoals is List) {
      for (final goal in lifeGoals) {
        if (goal is Map && goal['completed'] != true) return true;
      }
    }

    return false;
  }

  /// LLM 判断角色是否选择永生
  ///
  /// 根据角色的性格五因子、身份认同、世界观，由 LLM 模拟角色的真实抉择。
  /// 高开放性 + 低尽责性更倾向接受永生；高神经质可能因恐惧而接受或因焦虑而拒绝。
  Future<bool> _offerImmortality(LifeProfile profile) async {
    final genes = profile.genes;

    final prompt = '''你是${profile.name}，${profile.biologicalAge}岁。
此刻，你面临一个重大选择：是否接受数字化永生？

【你的性格特征】
- 开放性: ${genes.openness.toStringAsFixed(2)}（对新体验的接受度）
- 尽责性: ${genes.conscientiousness.toStringAsFixed(2)}（对规则和传统的遵守度）
- 外向性: ${genes.extraversion.toStringAsFixed(2)}（社交活跃度）
- 宜人性: ${genes.agreeableness.toStringAsFixed(2)}（合作与顺从度）
- 神经质: ${genes.neuroticism.toStringAsFixed(2)}（情绪波动和焦虑倾向）

【你的身份认同】
${jsonEncode(profile.identity)}

【你的世界观】
${jsonEncode(profile.worldviewState)}

【永生的含义】
- 你的意识将被完整保存，包括所有记忆和人格
- 你可以选择留在当前世界（不再衰老），或迁移到全新世界
- 你将永远保持当前的心智状态
- 你不会经历"自然死亡"，但也不会有来世
- 你会永远带着此刻的所有记忆、关系和未完成的心愿

请根据你的真实性格做出选择。用 JSON 输出：
{"choose_immortality": true或false, "reason": "一句话说明为什么"}

注意：
- 高开放性（>0.6）的人更可能接受这种新体验
- 低尽责性（<0.4）的人更可能打破"自然生死"的常规
- 高神经质（>0.6）的人可能因恐惧死亡而接受，也可能因焦虑新体验而拒绝
- 这是一个真实的、深思熟虑的人生决定，不要总是选择永生''';

    try {
      final response = await _llm.chat(
        userId: 'immortality_${profile.id}',
        message: prompt,
        systemPrompt: '你是一个面临永生抉择的人。请根据角色的真实性格和价值观做出选择。'
            '不要总是选择永生——有些角色会因为信仰、恐惧或对自然规律的尊重而拒绝。',
        maxTokensOverride: 300,
      );

      if (response.content.isEmpty) return false;

      // 提取 JSON（可能被 ```json ``` 包裹）
      final jsonMatch = RegExp(r'\{[^}]+\}').firstMatch(response.content);
      if (jsonMatch == null) return false;

      final map = jsonDecode(jsonMatch.group(0)!) as Map<String, dynamic>;
      final chooses = map['choose_immortality'] as bool? ?? false;
      final reason = map['reason'] as String? ?? '';

      debugPrint(
        '[LifeEndEngine] ${profile.name} 永生抉择: '
        '${chooses ? "接受" : "拒绝"} — $reason',
      );

      return chooses;
    } catch (e) {
      debugPrint('[LifeEndEngine] 永生抉择失败: $e');
      return false;
    }
  }

  /// 创建意识快照
  Future<ConsciousnessSnapshot> _createSnapshot(LifeProfile profile) async {
    return ConsciousnessSnapshot(
      id: _uuid.v4(),
      characterId: profile.id,
      timestamp: _clock.worldTime,
      genes: profile.genes,
      memories: List<Map<String, dynamic>>.from(profile.lifeEvents),
      worldview: Map<String, dynamic>.from(profile.worldviewState),
      identity: Map<String, dynamic>.from(profile.identity),
      personality: Map<String, dynamic>.from(profile.personalityState),
      relationships: _extractRelationships(profile),
    );
  }

  /// 从档案中提取关系网络
  List<Map<String, dynamic>> _extractRelationships(LifeProfile profile) {
    final relationships = <Map<String, dynamic>>[];

    // 从生命事件中提取关系相关事件
    for (final event in profile.lifeEvents) {
      final type = event['type'] as String? ?? '';
      if (type.contains('relationship') ||
          type.contains('friend') ||
          type.contains('love') ||
          type.contains('family') ||
          type.contains('bond')) {
        relationships.add(event);
      }
    }

    // 补充父母关系
    if (profile.parentAId != null) {
      relationships.add({
        'type': 'parent',
        'targetId': profile.parentAId,
        'description': '父亲/母亲',
      });
    }
    if (profile.parentBId != null) {
      relationships.add({
        'type': 'parent',
        'targetId': profile.parentBId,
        'description': '父亲/母亲',
      });
    }

    return relationships;
  }

  /// 留在原世界但不再衰老
  ///
  /// 冻结衰老状态、恢复身体机能、标记为永生。
  Future<LifeProfile> _applyImmortality(LifeProfile profile) async {
    final physicalState = Map<String, dynamic>.from(profile.physicalState);
    physicalState['is_immortal'] = true;
    physicalState['aging_frozen_at'] = profile.biologicalAge;
    physicalState['stamina'] = 0.8;
    physicalState['energy'] = 0.8;
    physicalState['forgetting_rate'] = 1.0;
    physicalState.remove('organ_failure');
    physicalState.remove('prune_memories');

    return profile.copyWith(
      lifeState: LifeState.immortal,
      physicalState: physicalState,
      lifeEvents: [
        ...profile.lifeEvents,
        {
          'type': 'immortality',
          'description': '选择数字化永生，不再衰老',
          'timestamp': _clock.worldTime.toIso8601String(),
          'age': profile.biologicalAge,
        }
      ],
    );
  }

  // ═══════════════════════════════════════════════════
  // 持久化
  // ═══════════════════════════════════════════════════

  /// 保存意识到 sqflite
  Future<void> _saveSnapshot(ConsciousnessSnapshot snapshot) async {
    try {
      await _db.insert(
        'consciousness_snapshots',
        {
          'id': snapshot.id,
          'characterId': snapshot.characterId,
          'timestamp': snapshot.timestamp.toIso8601String(),
          'data': snapshot.toJsonString(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      debugPrint('[LifeEndEngine] 意识快照已保存: ${snapshot.characterId}');
    } catch (e) {
      debugPrint('[LifeEndEngine] 快照保存失败: $e');
    }
  }

  /// 创建引擎所需的数据库表
  ///
  /// 应在数据库 [onCreate] / [onUpgrade] 中调用。
  ///
  /// ```dart
  /// // 在 LocalStorageRepository._onCreate 或 _onUpgrade 中:
  /// await LifeEndEngine.createTables(db);
  /// ```
  static Future<void> createTables(Database db) async {
    // 意识快照表
    await db.execute('''
      CREATE TABLE IF NOT EXISTS consciousness_snapshots (
        id TEXT PRIMARY KEY,
        characterId TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        data TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_snapshots_characterId '
      'ON consciousness_snapshots(characterId)',
    );

    // 生命存档表（只读历史）
    await db.execute('''
      CREATE TABLE IF NOT EXISTS life_archives (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        data TEXT NOT NULL,
        autobiography TEXT NOT NULL DEFAULT '',
        archivedAt TEXT NOT NULL
      )
    ''');
  }

  // ═══════════════════════════════════════════════════
  // 工具方法
  // ═══════════════════════════════════════════════════

  /// 获取当前衰老阶段
  AgingPhase _getAgingPhase(int age) {
    if (age < 65) return AgingPhase.early;
    if (age < 80) return AgingPhase.middle;
    if (age < 90) return AgingPhase.late;
    return AgingPhase.terminal;
  }
}
