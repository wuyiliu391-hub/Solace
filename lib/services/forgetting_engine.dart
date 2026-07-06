// ============================================================
// 全生命周期数字生命世界 — Phase 3
// 遗忘引擎：基于 Ebbinghaus 遗忘曲线的记忆衰减系统
// ============================================================

import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:yaml/yaml.dart';
import '../models/lifecycle_memory.dart';
import '../models/life_profile.dart';

/// 遗忘引擎
///
/// 核心理念：
/// - 记忆不是永恒的，它会随时间自然衰减（Ebbinghaus 遗忘曲线）
/// - 情感越强烈的记忆越不容易被遗忘
/// - 被反复回忆的记忆会被强化（用进废退）
/// - 创伤记忆受特殊保护，永不完全遗忘
/// - 不同生命阶段的遗忘速率不同（婴幼儿快速遗忘，老年加速遗忘）
/// - 被遗忘的记忆不是删除，而是归档，可以恢复
///
/// 遗忘曲线公式：
///   R = e^(-t/S)
///   R = 保留率（0.0 ~ 1.0）
///   t = 记忆年龄（小时）
///   S = 稳定性（小时）= baseRetentionHours + emotionalWeight × emotionalMultiplier + recallCount × recallBonus
///
/// 年龄修正：
///   婴幼儿（0-5岁）：遗忘速率 ×5
///   老年（50岁+）：遗忘速率 ×1.5 ~ ×3（随年龄线性递增）
class ForgettingEngine {
  // ── 默认参数（可被 world_config.yaml 覆盖） ──
  double _baseRetentionHours = 24.0;
  double _emotionalWeightMultiplier = 3.0; // 情感权重乘数（×72h 上限）
  double _recallBonus = 12.0;              // 每次回忆增加的稳定性（小时）
  double _traumaMinRetention = 0.2;        // 创伤记忆最低保留率
  double _archiveThreshold = 0.05;         // 归档阈值

  // ── 年龄遗忘倍率常量 ──
  static const double _infantForgettingMultiplier = 5.0;   // 0-5岁
  static const double _seniorBaseMultiplier = 1.5;         // 50岁起始
  static const double _seniorMaxMultiplier = 3.0;          // 80岁+
  static const int _seniorStartAge = 50;
  static const int _seniorMaxAge = 80;

  bool _configLoaded = false;

  // ─────────────────────────────────────────────────
  // 配置加载
  // ─────────────────────────────────────────────────

  /// 从 world_config.yaml 的 memory 节加载参数
  Future<void> loadConfig() async {
    if (_configLoaded) return;

    try {
      final yamlString =
          await rootBundle.loadString('world/world_config.yaml');
      final yaml = loadYaml(yamlString);

      if (yaml is YamlMap && yaml.containsKey('memory')) {
        final memory = yaml['memory'] as YamlMap;

        _baseRetentionHours =
            (memory['baseRetentionHours'] as num?)?.toDouble() ?? 24.0;
        _emotionalWeightMultiplier =
            (memory['emotionalWeightMultiplier'] as num?)?.toDouble() ?? 3.0;
        _recallBonus =
            (memory['recallBonus'] as num?)?.toDouble() ?? 12.0;
        _traumaMinRetention =
            (memory['traumaMinRetention'] as num?)?.toDouble() ?? 0.2;
        _archiveThreshold =
            (memory['archiveThreshold'] as num?)?.toDouble() ?? 0.05;

        debugPrint(
          '[ForgettingEngine] 配置已加载: '
          'baseRetention=${_baseRetentionHours}h, '
          'emotionalMultiplier=${_emotionalWeightMultiplier}x, '
          'recallBonus=${_recallBonus}h, '
          'traumaMinRetention=${_traumaMinRetention}, '
          'archiveThreshold=${_archiveThreshold}',
        );
      }

      _configLoaded = true;
    } catch (e) {
      debugPrint('[ForgettingEngine] 配置加载失败，使用默认值: $e');
      _configLoaded = true; // 标记为已加载，避免重复尝试
    }
  }

  /// 运行时注入配置（用于测试或无 asset 环境）
  void configure({
    double? baseRetentionHours,
    double? emotionalWeightMultiplier,
    double? recallBonus,
    double? traumaMinRetention,
    double? archiveThreshold,
  }) {
    if (baseRetentionHours != null) {
      _baseRetentionHours = baseRetentionHours;
    }
    if (emotionalWeightMultiplier != null) {
      _emotionalWeightMultiplier = emotionalWeightMultiplier;
    }
    if (recallBonus != null) _recallBonus = recallBonus;
    if (traumaMinRetention != null) {
      _traumaMinRetention = traumaMinRetention;
    }
    if (archiveThreshold != null) _archiveThreshold = archiveThreshold;
    _configLoaded = true;
  }

  // ─────────────────────────────────────────────────
  // 核心方法
  // ─────────────────────────────────────────────────

  /// 计算记忆保留率（Ebbinghaus 遗忘曲线 + 情感修正）
  ///
  /// 公式：R = e^(-t/S)
  ///
  /// 其中：
  /// - t = 记忆年龄（小时）
  /// - S = 稳定性 = baseRetentionHours + emotionalWeight × emotionalMultiplier + recallCount × recallBonus
  ///
  /// 特殊规则：
  /// - 创伤记忆最低保留 20%，永不完全遗忘
  /// - 年龄修正会放大衰减速率
  static double calculateRetention(
    LifecycleMemory memory,
    DateTime now, {
    double baseRetentionHours = 24.0,
    double emotionalWeightMultiplier = 3.0,
    double recallBonus = 12.0,
    double traumaMinRetention = 0.2,
    int? ownerAge,
  }) {
    // t = 记忆年龄（小时）
    final t = memory.ageInHours(now);
    if (t <= 0) return 1.0;

    // S = 稳定性（小时）
    // 基础稳定性 + 情感加成 + 回忆加成
    final S = baseRetentionHours +
        memory.emotionalWeight.clamp(0.0, 1.0) *
            emotionalWeightMultiplier *
            baseRetentionHours +
        memory.recallCount * recallBonus;

    // 稳定性不能为零（防止除零）
    if (S <= 0) return 0.0;

    // 基础保留率 R = e^(-t/S)
    double R = exp(-t / S);

    // 年龄修正：不同生命阶段遗忘速率不同
    if (ownerAge != null) {
      final multiplier = ageForgettingMultiplier(ownerAge);
      if (multiplier > 1.0) {
        // 加速遗忘：等效于缩短稳定性
        // R' = e^(-t*multiplier/S) = R^multiplier
        R = pow(R, multiplier).toDouble();
      }
    }

    // 创伤记忆保护：最低保留 20%
    if (memory.isTrauma) {
      R = max(R, traumaMinRetention);
    }

    return R.clamp(0.0, 1.0);
  }

  /// 定期清理已遗忘的记忆（归档不删除）
  ///
  /// 扫描所有记忆，保留率低于阈值的记忆标记为归档。
  /// 归档的记忆不参与日常检索，但可被恢复。
  ///
  /// 返回被归档的记忆列表。
  Future<List<LifecycleMemory>> cullMemories(
    LifeProfile profile,
    List<LifecycleMemory> memories,
  ) async {
    await loadConfig();

    final now = DateTime.now();
    final ownerAge = profile.biologicalAge;
    final archived = <LifecycleMemory>[];

    for (final memory in memories) {
      // 已归档的跳过
      if (memory.archived) continue;

      final retention = calculateRetention(
        memory,
        now,
        baseRetentionHours: _baseRetentionHours,
        emotionalWeightMultiplier: _emotionalWeightMultiplier,
        recallBonus: _recallBonus,
        traumaMinRetention: _traumaMinRetention,
        ownerAge: ownerAge,
      );

      // 保留率低于阈值 → 归档
      if (retention < _archiveThreshold) {
        memory.archived = true;
        memory.currentStrength = retention;
        archived.add(memory);
      } else {
        // 更新当前强度
        memory.currentStrength = retention;
      }
    }

    if (archived.isNotEmpty) {
      debugPrint(
        '[ForgettingEngine] ${profile.name} 归档了 '
        '${archived.length} 条已遗忘的记忆',
      );
    }

    return archived;
  }

  /// 强化记忆（回忆时调用）
  ///
  /// 被回忆时：
  /// - recallCount +1
  /// - 更新 lastRecallTime
  /// - 重新计算当前强度（即时更新，不等到下次 cull）
  ///
  /// 返回更新后的记忆副本。
  static LifecycleMemory reinforce(
    LifecycleMemory memory, {
    DateTime? now,
  }) {
    final currentTime = now ?? DateTime.now();

    return memory.copyWith(
      recallCount: memory.recallCount + 1,
      lastRecallTime: currentTime,
    );
  }

  /// 创伤记忆保护（永不完全遗忘，最低保留 20%）
  ///
  /// 硬性规则：创伤记忆类型的记忆始终受保护。
  static bool isProtected(LifecycleMemory memory) {
    return memory.isTrauma;
  }

  /// 根据年龄调整遗忘速率
  ///
  /// - 婴幼儿（0-5岁）：×5（快速遗忘，符合发育规律）
  /// - 儿童-青年（6-29岁）：×1.0（标准速率）
  /// - 中年（30-49岁）：×1.0（标准速率）
  /// - 老年（50岁+）：×1.5 ~ ×3.0（随年龄线性递增）
  static double ageForgettingMultiplier(int age) {
    // 婴幼儿：快速遗忘
    if (age <= 5) return _infantForgettingMultiplier;

    // 儿童到中年：标准速率
    if (age < _seniorStartAge) return 1.0;

    // 老年：线性递增
    // age=50 → 1.5, age=80 → 3.0
    final seniorYears = (age - _seniorStartAge).toDouble();
    final range = (_seniorMaxAge - _seniorStartAge).toDouble();
    final progress = (seniorYears / range).clamp(0.0, 1.0);

    return _seniorBaseMultiplier +
        progress * (_seniorMaxMultiplier - _seniorBaseMultiplier);
  }

  // ─────────────────────────────────────────────────
  // 批量操作
  // ─────────────────────────────────────────────────

  /// 批量计算所有活跃记忆的保留率
  ///
  /// 用于 UI 展示或调试。返回 {memoryId: retention}。
  Map<String, double> batchCalculateRetention(
    List<LifecycleMemory> memories,
    DateTime now, {
    int? ownerAge,
  }) {
    final result = <String, double>{};
    for (final memory in memories) {
      if (memory.archived) {
        result[memory.id] = 0.0;
        continue;
      }
      result[memory.id] = calculateRetention(
        memory,
        now,
        baseRetentionHours: _baseRetentionHours,
        emotionalWeightMultiplier: _emotionalWeightMultiplier,
        recallBonus: _recallBonus,
        traumaMinRetention: _traumaMinRetention,
        ownerAge: ownerAge,
      );
    }
    return result;
  }

  /// 更新所有记忆的 currentStrength（不归档，仅刷新数值）
  ///
  /// 适合在每次世界时钟推进时调用。
  void refreshStrengths(
    List<LifecycleMemory> memories,
    DateTime now, {
    int? ownerAge,
  }) {
    for (final memory in memories) {
      if (memory.archived) continue;
      memory.currentStrength = calculateRetention(
        memory,
        now,
        baseRetentionHours: _baseRetentionHours,
        emotionalWeightMultiplier: _emotionalWeightMultiplier,
        recallBonus: _recallBonus,
        traumaMinRetention: _traumaMinRetention,
        ownerAge: ownerAge,
      );
    }
  }

  /// 从归档中恢复记忆
  ///
  /// 被恢复的记忆重新获得一定强度。
  static LifecycleMemory restore(LifecycleMemory memory) {
    return memory.copyWith(
      archived: false,
      currentStrength: max(memory.currentStrength, 0.1),
    );
  }

  // ─────────────────────────────────────────────────
  // 统计
  // ─────────────────────────────────────────────────

  /// 获取记忆遗忘统计（调试/UI 用）
  Map<String, dynamic> getStats(
    List<LifecycleMemory> memories,
    DateTime now, {
    int? ownerAge,
  }) {
    if (memories.isEmpty) return {'total': 0};

    final active = memories.where((m) => !m.archived).toList();
    final archivedCount = memories.where((m) => m.archived).length;
    final protected = memories.where((m) => m.isTrauma).length;

    if (active.isEmpty) {
      return {
        'total': memories.length,
        'active': 0,
        'archived': archivedCount,
        'protected': protected,
      };
    }

    final retentions = active
        .map((m) => calculateRetention(
              m,
              now,
              baseRetentionHours: _baseRetentionHours,
              emotionalWeightMultiplier: _emotionalWeightMultiplier,
              recallBonus: _recallBonus,
              traumaMinRetention: _traumaMinRetention,
              ownerAge: ownerAge,
            ))
        .toList();

    final avgRetention = retentions.reduce((a, b) => a + b) / retentions.length;
    final fading = retentions.where((r) => r < 0.3).length;
    final strong = retentions.where((r) => r > 0.7).length;

    return {
      'total': memories.length,
      'active': active.length,
      'archived': archivedCount,
      'protected': protected,
      'avgRetention': avgRetention.toStringAsFixed(3),
      'strong': strong,   // 保留率 > 70%
      'fading': fading,   // 保留率 < 30%
    };
  }
}
