// ============================================================
// 全生命周期数字生命世界 — Phase 1
// 生命周期引擎：驱动数字生命从出生到暮年的完整阶段演进
// ============================================================

import 'package:flutter/foundation.dart';
import '../models/life_profile.dart';
import '../services/global_time_clock.dart';

/// 生命周期引擎
///
/// 职责：
/// - 世界时钟推进时，批量检查所有存活角色的生命周期
/// - 检测阶段转换并触发对应事件
/// - 应用每个阶段的固有变化与衰老效果
/// - 提供阶段行为约束（供提示词系统使用）
class LifecycleEngine {
  final GlobalTimeClock _clock;

  LifecycleEngine(this._clock);

  // ── 阶段转换阈值 ──
  static const Map<LifeStage, int> _stageThresholds = {
    LifeStage.infant: 0,
    LifeStage.toddler: 3,
    LifeStage.childhood: 6,
    LifeStage.teenage: 12,
    LifeStage.youngAdult: 18,
    LifeStage.adult: 30,
    LifeStage.senior: 50,
    LifeStage.elder: 80,
  };

  // ── 阶段行为约束（供提示词系统注入） ──
  static const Map<LifeStage, Map<String, dynamic>> _stageConstraints = {
    LifeStage.infant: {
      'language_level': 'none',
      'can_initiate_social': false,
      'can_use_full_language': false,
      'can_post_moments': false,
      'can_form_relationships': false,
      'has_worldview': false,
      'memory_retention': 0.2,
      'forgetting_multiplier': 5.0,
      'allowed_behaviors': ['cry', 'sleep', 'eat', 'observe'],
      'prompt_hint': '只能通过哭声、表情、肢体动作表达需求，不能使用语言',
      'emotional_volatility': 0.9,
      'personality_stability': 0.1,
    },
    LifeStage.toddler: {
      'language_level': 'simple',
      'can_initiate_social': false,
      'can_use_full_language': false,
      'can_post_moments': false,
      'can_form_relationships': true,
      'has_worldview': false,
      'memory_retention': 0.4,
      'forgetting_multiplier': 3.0,
      'allowed_behaviors': [
        'simple_talk', 'play', 'explore', 'bond_family',
        'imitate', 'ask_why',
      ],
      'prompt_hint': '使用简单词汇和短句，模仿大人说话，好奇心旺盛',
      'emotional_volatility': 0.8,
      'personality_stability': 0.2,
    },
    LifeStage.childhood: {
      'language_level': 'full',
      'can_initiate_social': true,
      'can_use_full_language': true,
      'can_post_moments': false,
      'can_form_relationships': true,
      'has_worldview': false,
      'memory_retention': 0.7,
      'forgetting_multiplier': 1.5,
      'allowed_behaviors': [
        'full_conversation', 'make_friends', 'attend_school',
        'play_games', 'read', 'learn', 'family_activities',
      ],
      'prompt_hint': '语言能力完整，开始建立友谊，对世界充满好奇但三观尚未成型',
      'emotional_volatility': 0.6,
      'personality_stability': 0.4,
    },
    LifeStage.teenage: {
      'language_level': 'full',
      'can_initiate_social': true,
      'can_use_full_language': true,
      'can_post_moments': true,
      'can_form_relationships': true,
      'has_worldview': false,
      'memory_retention': 0.9,
      'forgetting_multiplier': 1.0,
      'allowed_behaviors': [
        'full_conversation', 'deep_friendships', 'post_moments',
        'develop_interests', 'question_authority', 'identity_exploration',
        'romantic_interest',
      ],
      'prompt_hint': '性格波动加剧，开始探索自我认同，情绪敏感，三观正在形成中',
      'emotional_volatility': 0.85,
      'personality_stability': 0.3,
    },
    LifeStage.youngAdult: {
      'language_level': 'full',
      'can_initiate_social': true,
      'can_use_full_language': true,
      'can_post_moments': true,
      'can_form_relationships': true,
      'has_worldview': true,
      'memory_retention': 1.0,
      'forgetting_multiplier': 1.0,
      'allowed_behaviors': [
        'full_conversation', 'deep_relationships', 'post_moments',
        'career_pursuit', 'worldview_formation', 'independent_living',
        'romantic_relationships',
      ],
      'prompt_hint': '三观开始固化，逐步走向独立，性格趋于成熟但仍有成长空间',
      'emotional_volatility': 0.5,
      'personality_stability': 0.6,
    },
    LifeStage.adult: {
      'language_level': 'full',
      'can_initiate_social': true,
      'can_use_full_language': true,
      'can_post_moments': true,
      'can_form_relationships': true,
      'has_worldview': true,
      'memory_retention': 1.0,
      'forgetting_multiplier': 1.0,
      'allowed_behaviors': [
        'full_conversation', 'deep_relationships', 'post_moments',
        'career_established', 'mentor_others', 'family_building',
        'worldview_stable', 'life_reflection',
      ],
      'prompt_hint': '性格趋于稳定，处事成熟，开始承担更多社会责任',
      'emotional_volatility': 0.3,
      'personality_stability': 0.85,
    },
    LifeStage.senior: {
      'language_level': 'full',
      'can_initiate_social': true,
      'can_use_full_language': true,
      'can_post_moments': true,
      'can_form_relationships': true,
      'has_worldview': true,
      'memory_retention': 0.85,
      'forgetting_multiplier': 1.3,
      'allowed_behaviors': [
        'full_conversation', 'maintain_relationships', 'post_moments',
        'reminisce', 'wisdom_sharing', 'slower_pace',
        'health_awareness', 'legacy_thinking',
      ],
      'prompt_hint': '身体开始衰退，行动节奏放慢，喜欢回忆往事，开始思考传承',
      'emotional_volatility': 0.25,
      'personality_stability': 0.95,
    },
    LifeStage.elder: {
      'language_level': 'full',
      'can_initiate_social': true,
      'can_use_full_language': true,
      'can_post_moments': true,
      'can_form_relationships': true,
      'has_worldview': true,
      'memory_retention': 0.6,
      'forgetting_multiplier': 2.5,
      'allowed_behaviors': [
        'conversation', 'reminisce', 'storytelling', 'wisdom_transfer',
        'family_legacy', 'peaceful_activities', 'reflection',
      ],
      'prompt_hint': '记忆明显衰退，说话可能重复或遗忘近期事件，但对久远记忆清晰，处于传承期',
      'emotional_volatility': 0.2,
      'personality_stability': 1.0,
    },
  };

  // ─────────────────────────────────────────────────
  // 核心方法
  // ─────────────────────────────────────────────────

  /// 世界时钟推进时，检查所有存活角色
  ///
  /// 批量处理，只对阶段发生变化或需要衰老效果的角色进行更新。
  /// 返回需要被持久化的更新后档案列表。
  Future<List<LifeProfile>> tickAll(List<LifeProfile> profiles) async {
    final updated = <LifeProfile>[];

    for (final profile in profiles) {
      if (profile.lifeState != LifeState.alive &&
          profile.lifeState != LifeState.aging) {
        continue;
      }

      final result = await tick(profile);
      if (result != null) {
        updated.add(result);
      }
    }

    return updated;
  }

  /// 对单个角色推进生命周期
  ///
  /// 返回 null 表示无需变更；否则返回更新后的档案副本。
  Future<LifeProfile?> tick(LifeProfile profile) async {
    if (profile.lifeState != LifeState.alive &&
        profile.lifeState != LifeState.aging) {
      return null;
    }

    final worldNow = _clock.worldTime;
    final currentAge = _calculateAge(profile.birthTime, worldNow);
    final currentStage = ageToStage(currentAge);

    bool changed = false;
    LifeProfile updated = profile;

    // 1. 阶段转换检测
    if (currentStage != profile.currentStage) {
      updated = updated.copyWith(
        currentStage: currentStage,
        biologicalAge: currentAge,
      );
      await _onStageTransition(profile, profile.currentStage, currentStage);
      changed = true;
    }

    // 2. 年龄更新（即使阶段没变，年龄可能增长了）
    if (currentAge != profile.biologicalAge) {
      updated = updated.copyWith(biologicalAge: currentAge);
      changed = true;
    }

    // 3. 衰老效果（30岁以后）
    if (currentAge >= 30) {
      updated = await _applyAging(updated, currentAge);
      changed = true;
    }

    // 4. 阶段固有变化
    if (changed) {
      updated = await _applyStageEffects(updated, currentStage);
    }

    return changed ? updated : null;
  }

  /// 根据年龄计算生命阶段
  static LifeStage ageToStage(int age) {
    return LifeProfile.stageForAge(age);
  }

  /// 获取当前阶段的行为约束（供提示词系统使用）
  Map<String, dynamic> getStageConstraints(LifeStage stage) {
    return Map.unmodifiable(
      _stageConstraints[stage] ?? _stageConstraints[LifeStage.infant]!,
    );
  }

  // ─────────────────────────────────────────────────
  // 内部方法
  // ─────────────────────────────────────────────────

  /// 阶段转换时触发的事件
  ///
  /// 记录生命事件到档案中，后续 Phase 可扩展为触发通知、动画等。
  Future<void> _onStageTransition(
    LifeProfile profile,
    LifeStage from,
    LifeStage to,
  ) async {
    final transitionDesc = _describeTransition(from, to);

    debugPrint(
      '[LifecycleEngine] ${profile.name} 阶段转换: '
      '${from.name} → ${to.name} ($transitionDesc)',
    );

    // 生命事件记录由调用方持久化，此处仅做日志
    // 后续 Phase 可在此触发：
    // - 解锁新能力通知
    // - 阶段转换动画
    // - 提示词系统切换
  }

  /// 每个阶段的固有变化
  ///
  /// 根据当前阶段调整心理年龄、情绪基线等。
  Future<LifeProfile> _applyStageEffects(
    LifeProfile profile,
    LifeStage stage,
  ) async {
    // 心理年龄校正：不同阶段心理成长速率不同
    int mentalAge = profile.mentalAge;
    switch (stage) {
      case LifeStage.infant:
        // 心理年龄 ≈ 生物年龄 × 1.2（快速发育）
        mentalAge = (profile.biologicalAge * 1.2).round();
        break;
      case LifeStage.toddler:
        mentalAge = (profile.biologicalAge * 1.1).round();
        break;
      case LifeStage.childhood:
        mentalAge = (profile.biologicalAge * 1.0).round();
        break;
      case LifeStage.teenage:
        // 青春期心理年龄可能超前或滞后
        mentalAge = profile.biologicalAge;
        break;
      case LifeStage.youngAdult:
      case LifeStage.adult:
        mentalAge = profile.biologicalAge;
        break;
      case LifeStage.senior:
        // 心理年龄开始滞后于生物年龄
        mentalAge = (profile.biologicalAge * 0.95).round();
        break;
      case LifeStage.elder:
        mentalAge = (profile.biologicalAge * 0.9).round();
        break;
    }

    if (mentalAge != profile.mentalAge) {
      return profile.copyWith(mentalAge: mentalAge);
    }
    return profile;
  }

  /// 衰老效果（30岁以后）
  ///
  /// 调整身体状态、记忆保留率等。年龄越大效果越明显。
  Future<LifeProfile> _applyAging(LifeProfile profile, int age) async {
    final physicalState = Map<String, dynamic>.from(profile.physicalState);

    // 身体机能衰减曲线（30岁起算）
    final agingYears = age - 30;
    final physicalDecay = (1.0 - agingYears * 0.008).clamp(0.3, 1.0);
    physicalState['physical_fitness'] = physicalDecay;
    physicalState['energy_level'] = (1.0 - agingYears * 0.006).clamp(0.25, 1.0);

    // 50岁后记忆衰退加速
    if (age >= 50) {
      final memoryDecayYears = age - 50;
      physicalState['memory_capacity'] =
          (1.0 - memoryDecayYears * 0.01).clamp(0.4, 1.0);
    }

    // 80岁后身体机能显著下降
    if (age >= 80) {
      physicalState['mobility'] =
          (1.0 - (age - 80) * 0.02).clamp(0.2, 1.0);
      physicalState['hearing'] =
          (1.0 - (age - 80) * 0.015).clamp(0.3, 1.0);
      physicalState['vision'] =
          (1.0 - (age - 80) * 0.012).clamp(0.35, 1.0);
    }

    // 检测是否进入衰老状态
    LifeState lifeState = profile.lifeState;
    if (age >= 60 && physicalDecay < 0.6) {
      lifeState = LifeState.aging;
    }

    return profile.copyWith(
      physicalState: physicalState,
      lifeState: lifeState,
    );
  }

  /// 根据 birthTime 和当前世界时间计算年龄
  int _calculateAge(DateTime birthTime, DateTime worldNow) {
    int years = worldNow.year - birthTime.year;
    if (worldNow.month < birthTime.month ||
        (worldNow.month == birthTime.month &&
            worldNow.day < birthTime.day)) {
      years--;
    }
    return years.clamp(0, 999);
  }

  /// 阶段转换描述（用于事件记录和日志）
  static String _describeTransition(LifeStage from, LifeStage to) {
    const descriptions = {
      'infant→toddler': '开始有简单语言，认知世界扩展',
      'toddler→childhood': '解锁完整社交，入学启蒙',
      'childhood→teenage': '性格波动加剧，自我意识觉醒',
      'teenage→youngAdult': '三观开始固化，走向独立',
      'youngAdult→adult': '性格趋于稳定，承担社会责任',
      'adult→senior': '身体开始衰退，智慧沉淀',
      'senior→elder': '记忆衰退，进入传承期',
    };
    return descriptions['${from.name}→${to.name}'] ?? '生命阶段转换';
  }
}
