// ============================================================
// 全生命周期数字生命世界 — Phase 5
// 站队/极化引擎：当冲突发生时驱动朋友圈分裂与立场选择
// ============================================================

import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/life_profile.dart';
import 'ai_relationship_service.dart';
import 'memory_engine.dart';
import 'llm_service.dart';

// ── 站队立场 ──
enum Side {
  sideA,
  sideB,
  neutral,
}

// ── 冲突事件 ──
class ConflictEvent {
  final String id;
  final String sideAId; // 冲突方 A 的角色 ID
  final String sideBId; // 冲突方 B 的角色 ID
  final String description; // 冲突描述
  final double intensity; // 冲突烈度 0.0-1.0
  final String category; // 冲突类别（如 '价值观', '利益', '情感'）
  final DateTime timestamp;
  final Map<String, dynamic> metadata;

  const ConflictEvent({
    required this.id,
    required this.sideAId,
    required this.sideBId,
    required this.description,
    this.intensity = 0.5,
    this.category = 'general',
    required this.timestamp,
    this.metadata = const {},
  });
}

// ── 站队预测 ──
class SidePrediction {
  final Side predicted;
  final double confidence; // 预测置信度 0.0-1.0
  final String reason;

  const SidePrediction({
    required this.predicted,
    required this.confidence,
    required this.reason,
  });
}

// ── 关系变化记录 ──
class RelationshipChange {
  final String characterId;
  final String targetId;
  final double affinityDelta; // 亲密度变化量
  final String reason;

  const RelationshipChange({
    required this.characterId,
    required this.targetId,
    required this.affinityDelta,
    required this.reason,
  });
}

// ── 极化结果 ──
class PolarizationResult {
  final Map<String, Side> decisions; // characterId → 站哪边
  final List<String> neutrals; // 保持中立的人
  final Map<String, String> declarations; // 站队声明
  final List<RelationshipChange> relationshipChanges;

  const PolarizationResult({
    required this.decisions,
    required this.neutrals,
    required this.declarations,
    required this.relationshipChanges,
  });

  /// 获取站 A 方的角色列表
  List<String> get sideAIds =>
      decisions.entries.where((e) => e.value == Side.sideA).map((e) => e.key).toList();

  /// 获取站 B 方的角色列表
  List<String> get sideBIds =>
      decisions.entries.where((e) => e.value == Side.sideB).map((e) => e.key).toList();

  /// 是否产生了真正的分裂（双方都有人站队）
  bool get isPolarized => sideAIds.isNotEmpty && sideBIds.isNotEmpty;
}

/// 站队/极化引擎
///
/// 当两个角色发生冲突时，驱动其他角色选择立场。
///
/// 决策规则优先级：
/// 1. 与冲突双方的亲密度差异 > 0.3 → 站亲密方
/// 2. 亲密度接近 → 看信任度差异（信任度由关系类型+亲密度综合评估）
/// 3. 都接近 → 看性格（高外向性更愿意表态，低外向性倾向中立）
/// 4. 高宜人性倾向调解而非站队
/// 5. 站队后：与对立面关系下降 0.1-0.2
class PolarizationEngine {
  final AIRelationshipService _relationshipService;
  final MemoryEngine _memoryEngine;
  final LlmService _llmService;
  final Random _random = Random();
  final _uuid = const Uuid();

  PolarizationEngine(this._relationshipService, this._memoryEngine, this._llmService);

  /// 检测冲突是否导致朋友圈分裂
  ///
  /// 遍历所有不在冲突双方中的角色，预测其立场，
  /// 生成站队声明，并汇总关系变化。
  Future<PolarizationResult> detect({
    required ConflictEvent conflict,
    required List<LifeProfile> allProfiles,
    required List<AIRelationship> relationships,
  }) async {
    final decisions = <String, Side>{};
    final declarations = <String, String>{};
    final allChanges = <RelationshipChange>[];
    final neutrals = <String>[];

    // 找到冲突双方的档案
    final sideAProfile = _findProfile(allProfiles, conflict.sideAId);
    final sideBProfile = _findProfile(allProfiles, conflict.sideBId);

    if (sideAProfile == null || sideBProfile == null) {
      debugPrint('PolarizationEngine: 冲突方档案缺失，无法执行极化');
      return PolarizationResult(
        decisions: {},
        neutrals: allProfiles
            .where((p) => p.id != conflict.sideAId && p.id != conflict.sideBId)
            .map((p) => p.id)
            .toList(),
        declarations: {},
        relationshipChanges: [],
      );
    }

    // 获取冲突双方的关系
    final relAtoB = await _relationshipService.getRelationship(
        conflict.sideAId, conflict.sideBId);

    // 遍历旁观者
    final bystanders = allProfiles.where(
        (p) => p.id != conflict.sideAId && p.id != conflict.sideBId);

    for (final decider in bystanders) {
      // 获取旁观者与冲突双方的关系
      final relToA = await _relationshipService.getRelationship(
          decider.id, conflict.sideAId);
      final relToB = await _relationshipService.getRelationship(
          decider.id, conflict.sideBId);

      // 预测立场
      final prediction = predictSide(
        decider: decider,
        sideA: sideAProfile,
        sideB: sideBProfile,
        relToA: relToA,
        relToB: relToB,
        conflictIntensity: conflict.intensity,
      );

      decisions[decider.id] = prediction.predicted;

      if (prediction.predicted == Side.neutral) {
        neutrals.add(decider.id);
      } else {
        // 站队后生成声明
        final declaration = await generateDeclaration(
          decider: decider,
          chosenSide: prediction.predicted,
          conflict: conflict,
        );
        declarations[decider.id] = declaration;

        // 站队导致与对立面关系下降
        final targetId = prediction.predicted == Side.sideA
            ? conflict.sideBId
            : conflict.sideAId;
        final drop = _calculateAffinityDrop(decider, conflict.intensity);
        allChanges.add(RelationshipChange(
          characterId: decider.id,
          targetId: targetId,
          affinityDelta: -drop,
          reason: '在冲突中站队导致关系降温',
        ));
      }
    }

    return PolarizationResult(
      decisions: decisions,
      neutrals: neutrals,
      declarations: declarations,
      relationshipChanges: allChanges,
    );
  }

  /// 判断某个角色会站在哪一边
  ///
  /// 综合亲密度、信任度、性格特征进行预测。
  SidePrediction predictSide({
    required LifeProfile decider,
    required LifeProfile sideA,
    required LifeProfile sideB,
    AIRelationship? relToA,
    AIRelationship? relToB,
    double conflictIntensity = 0.5,
  }) {
    final affinityA = relToA?.affinity ?? 0.5;
    final affinityB = relToB?.affinity ?? 0.5;
    final affinityDiff = (affinityA - affinityB).abs();

    // 获取性格特征
    final personality = _extractPersonality(decider);
    final extraversion = personality['extraversion'] ?? 0.5;
    final agreeableness = personality['agreeableness'] ?? 0.5;

    // ── 规则 1: 亲密度差异 > 0.3 → 站亲密方 ──
    if (affinityDiff > 0.3) {
      final chosen = affinityA > affinityB ? Side.sideA : Side.sideB;
      return SidePrediction(
        predicted: chosen,
        confidence: (affinityDiff * 1.5).clamp(0.0, 1.0),
        reason: '与${chosen == Side.sideA ? sideA.name : sideB.name}关系更亲密'
            '（亲密度差 ${affinityDiff.toStringAsFixed(2)}）',
      );
    }

    // ── 规则 2: 亲密度接近 → 看信任度差异 ──
    final trustA = _estimateTrust(relToA, affinityA);
    final trustB = _estimateTrust(relToB, affinityB);
    final trustDiff = (trustA - trustB).abs();

    if (trustDiff > 0.2) {
      final chosen = trustA > trustB ? Side.sideA : Side.sideB;
      return SidePrediction(
        predicted: chosen,
        confidence: (trustDiff * 1.2).clamp(0.0, 0.9),
        reason: '更信任${chosen == Side.sideA ? sideA.name : sideB.name}'
            '（信任度差 ${trustDiff.toStringAsFixed(2)}）',
      );
    }

    // ── 规则 3: 都接近 → 看性格 ──

    // 高宜人性 → 倾向调解，保持中立
    if (agreeableness > 0.7) {
      return SidePrediction(
        predicted: Side.neutral,
        confidence: agreeableness,
        reason: '性格温和，倾向调解而非站队（宜人性 ${agreeableness.toStringAsFixed(2)}）',
      );
    }

    // 低外向性 → 倾向中立，不愿表态
    if (extraversion < 0.3) {
      return SidePrediction(
        predicted: Side.neutral,
        confidence: (1 - extraversion).clamp(0.0, 1.0),
        reason: '性格内敛，不愿卷入纷争（外向性 ${extraversion.toStringAsFixed(2)}）',
      );
    }

    // 高外向性 + 亲密度/信任度微小差异 → 站稍亲近的一方
    if (extraversion > 0.5) {
      final slightPref = affinityA + trustA - affinityB - trustB;
      if (slightPref.abs() > 0.05) {
        final chosen = slightPref > 0 ? Side.sideA : Side.sideB;
        return SidePrediction(
          predicted: chosen,
          confidence: 0.4 + extraversion * 0.2,
          reason: '愿意表态，微倾向${chosen == Side.sideA ? sideA.name : sideB.name}',
        );
      }
    }

    // ── 默认: 中立 ──
    return SidePrediction(
      predicted: Side.neutral,
      confidence: 0.5,
      reason: '与双方关系接近，难以抉择',
    );
  }

  /// 生成站队声明
  ///
  /// 优先使用 LLM 生成个性化声明，失败时使用模板 fallback。
  Future<String> generateDeclaration({
    required LifeProfile decider,
    required Side chosenSide,
    required ConflictEvent conflict,
  }) async {
    // 尝试 LLM 生成
    try {
      final prompt = _buildDeclarationPrompt(decider, chosenSide, conflict);
      final response = await _callLlm(prompt);
      if (response != null && response.isNotEmpty) {
        return response;
      }
    } catch (e) {
      debugPrint('PolarizationEngine: LLM 生成声明失败，使用 fallback: $e');
    }

    // Fallback: 模板生成
    return _fallbackDeclaration(decider, chosenSide, conflict);
  }

  /// 极化后的关系变化写入关系图谱和社交记忆
  Future<void> applyPolarization({
    required PolarizationResult result,
    required List<AIRelationship> relationships,
    required ConflictEvent conflict,
  }) async {
    // 1. 应用关系变化
    for (final change in result.relationshipChanges) {
      final rel = await _relationshipService.getRelationship(
          change.characterId, change.targetId);

      if (rel != null) {
        final newAffinity = (rel.affinity + change.affinityDelta).clamp(0.0, 1.0);
        await _relationshipService.updateRelationship(
          rel.copyWith(affinity: newAffinity),
        );
      } else {
        // 创建新关系（如果之前没有）
        await _relationshipService.createRelationship(
          characterIdA: change.characterId,
          characterIdB: change.targetId,
          type: RelationshipType.rival,
          affinity: (0.5 + change.affinityDelta).clamp(0.0, 1.0),
          description: '因冲突站队而产生的对立关系',
        );
      }
    }

    // 2. 写入社交记忆
    for (final entry in result.declarations.entries) {
      final characterId = entry.key;
      final declaration = entry.value;
      final side = result.decisions[characterId]!;

      try {
        await _memoryEngine.saveSocialMemory(
          characterId: characterId,
          targetCharacterId: side == Side.sideA ? result.decisions.keys.first : result.decisions.keys.last,
          interactionType: 'polarization',
          content: '在一场冲突中选择了立场：$declaration',
          importance: 'important',
          keywords: ['冲突', '站队', side == Side.sideA ? '支持A方' : '支持B方'],
        );
      } catch (e) {
        debugPrint('PolarizationEngine: 保存社交记忆失败: $e');
      }
    }

    // 3. 为中立者也记录记忆
    for (final neutralId in result.neutrals) {
      try {
        await _memoryEngine.saveSocialMemory(
          characterId: neutralId,
          targetCharacterId: conflict.sideAId,
          interactionType: 'polarization',
          content: '在一场冲突中选择保持中立，试图调解双方',
          importance: 'normal',
          keywords: ['冲突', '中立', '调解'],
        );
      } catch (e) {
        debugPrint('PolarizationEngine: 保存中立记忆失败: $e');
      }
    }

    debugPrint('PolarizationEngine: 极化完成 — '
        '${result.sideAIds.length}人站A方, '
        '${result.sideBIds.length}人站B方, '
        '${result.neutrals.length}人中立');
  }

  // ── 私有辅助方法 ──

  /// 从 LifeProfile 中提取人格五因子
  Map<String, double> _extractPersonality(LifeProfile profile) {
    final state = profile.personalityState;
    return {
      'openness': (state['openness'] as num?)?.toDouble() ?? 0.5,
      'conscientiousness': (state['conscientiousness'] as num?)?.toDouble() ?? 0.5,
      'extraversion': (state['extraversion'] as num?)?.toDouble() ?? 0.5,
      'agreeableness': (state['agreeableness'] as num?)?.toDouble() ?? 0.5,
      'neuroticism': (state['neuroticism'] as num?)?.toDouble() ?? 0.5,
    };
  }

  /// 估算信任度（综合关系类型和亲密度）
  double _estimateTrust(AIRelationship? rel, double affinity) {
    if (rel == null) return 0.5;

    // 关系类型对信任的基础加成
    double typeBonus;
    switch (rel.relationshipType) {
      case RelationshipType.lover:
        typeBonus = 0.3;
        break;
      case RelationshipType.bestFriend:
        typeBonus = 0.25;
        break;
      case RelationshipType.friend:
        typeBonus = 0.15;
        break;
      case RelationshipType.sibling:
        typeBonus = 0.2;
        break;
      case RelationshipType.mentor:
        typeBonus = 0.2;
        break;
      case RelationshipType.enemy:
        typeBonus = -0.3;
        break;
      case RelationshipType.rival:
        typeBonus = -0.15;
        break;
      case RelationshipType.crush:
        typeBonus = 0.1;
        break;
      case RelationshipType.stranger:
        typeBonus = 0.0;
        break;
    }

    return (affinity * 0.6 + 0.4 * (0.5 + typeBonus)).clamp(0.0, 1.0);
  }

  /// 计算站队后亲密度下降量（0.1-0.2，受冲突烈度影响）
  double _calculateAffinityDrop(LifeProfile decider, double conflictIntensity) {
    final personality = _extractPersonality(decider);
    final neuroticism = personality['neuroticism'] ?? 0.5;

    // 高神经质 → 更情绪化 → 下降更多
    final base = 0.1 + conflictIntensity * 0.1;
    final neuroticBonus = neuroticism * 0.05;
    return (base + neuroticBonus).clamp(0.1, 0.2);
  }

  /// 在档案列表中查找指定 ID
  LifeProfile? _findProfile(List<LifeProfile> profiles, String id) {
    try {
      return profiles.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  /// 构建 LLM 声明生成 prompt
  String _buildDeclarationPrompt(
    LifeProfile decider,
    Side chosenSide,
    ConflictEvent conflict,
  ) {
    final sideLabel = chosenSide == Side.sideA ? 'A方' : 'B方';
    return '''你是一个虚拟世界的角色 ${decider.name}。
当前发生了一场冲突：${conflict.description}
你需要选择站在$sideLabel。
请用一句话表达你的立场声明，要符合你的性格，语气自然。
只输出声明内容，不要有其他文字。''';
  }

  /// 调用 LLM 生成文本
  Future<String?> _callLlm(String prompt) async {
    try {
      final response = await _llmService.chat(
        userId: 'system',
        message: prompt,
        role: 'user',
      );
      return response.content;
    } catch (e) {
      debugPrint('PolarizationEngine: LLM 调用失败: $e');
      return null;
    }
  }

  /// Fallback 声明模板
  String _fallbackDeclaration(
    LifeProfile decider,
    Side chosenSide,
    ConflictEvent conflict,
  ) {
    final templates = chosenSide == Side.sideA
        ? [
            '${decider.name}选择支持A方：「我认为A方说得有道理。」',
            '${decider.name}站到了A方这边：「这件事我站在A方。」',
            '${decider.name}表态支持A方：「我理解A方的立场。」',
          ]
        : [
            '${decider.name}选择支持B方：「我觉得B方更合理。」',
            '${decider.name}站到了B方这边：「我支持B方的观点。」',
            '${decider.name}表态支持B方：「B方的立场我更认同。」',
          ];
    return templates[_random.nextInt(templates.length)];
  }
}
