// ============================================================
// 全生命周期数字生命世界 — Phase 5
// 关系链反应引擎：当两个角色之间的关系变化时，
// 像多米诺骨牌一样引发对其他角色的连锁影响
// ============================================================

import 'package:flutter/foundation.dart';
import '../models/relationship_graph.dart';
import '../models/life_profile.dart';

// ─────────────────────────────────────────────────
// 数据模型
// ─────────────────────────────────────────────────

/// 单跳传播结果
///
/// 描述 A-B 关系变化对邻居 C 的一次影响
class SingleHop {
  /// 被评估的邻居 ID
  final String neighborId;

  /// 受影响的角色 ID（neighborId 或 otherId，取决于哪条边被修改）
  final String affectedId;

  /// 反应类型
  final String reactionType;

  /// 关系变化量
  final double delta;

  /// 变化原因（人类可读）
  final String reason;

  const SingleHop({
    required this.neighborId,
    required this.affectedId,
    required this.reactionType,
    required this.delta,
    required this.reason,
  });

  @override
  String toString() =>
      'SingleHop($neighborId → $affectedId, $reactionType, '
      'Δ${delta.toStringAsFixed(3)}, "$reason")';
}

/// 链反应结果
///
/// 一次关系变化可能引发多条链反应，每条链反应描述：
/// - 源关系（哪对角色的变化触发的）
/// - 受影响的角色
/// - 反应类型和描述
/// - 关系变化量
/// - 传播了几跳
class ChainReaction {
  /// 源关系 ID
  final String sourceRelId;

  /// 受影响的角色 ID
  final String affectedCharId;

  /// 受影响的关系中，另一端的角色 ID
  final String otherCharId;

  /// 反应类型：distance / approach / side_take / jealousy / support
  final String reactionType;

  /// 人类可读的反应描述
  final String description;

  /// 关系变化量（可正可负）
  final double relationshipDelta;

  /// 第几跳（1 = 直接邻居，2 = 二跳……）
  final int hopCount;

  const ChainReaction({
    required this.sourceRelId,
    required this.affectedCharId,
    required this.otherCharId,
    required this.reactionType,
    required this.description,
    required this.relationshipDelta,
    required this.hopCount,
  });

  @override
  String toString() =>
      'ChainReaction(src=$sourceRelId, $affectedCharId↔$otherCharId, '
      '$reactionType, Δ${relationshipDelta.toStringAsFixed(3)}, '
      'hop=$hopCount, "$description")';
}

// ─────────────────────────────────────────────────
// 链反应引擎
// ─────────────────────────────────────────────────

/// 关系链反应引擎
///
/// 当两个角色之间的关系发生变化时，检测并应用多跳连锁反应。
///
/// 传播规则：
/// - 每跳影响衰减 50%
/// - 最多传播 3 跳
/// - 亲密度 < 0.2 的关系不触发链反应
/// - 同一对角色不会被同一源事件重复影响
class ChainReactionEngine {
  // ── 衰减与阈值常量 ──

  /// 每跳衰减系数
  static const double _hopDecay = 0.5;

  /// 关系亲密度最低触发阈值
  static const double _intimacyThreshold = 0.2;

  /// 默认最大传播跳数
  static const int _defaultMaxHops = 3;

  // ═══════════════════════════════════════════════
  // 公共 API
  // ═══════════════════════════════════════════════

  /// 检测关系变化引发的链反应
  ///
  /// [changedRelationship] — 发生变化的关系图谱
  /// [allRelationships] — 当前所有关系图谱
  /// [allProfiles] — 所有角色的生命档案
  /// [maxHops] — 最多传播几跳（默认 3）
  ///
  /// 返回所有检测到的链反应列表（已按 hopCount 排序）
  Future<List<ChainReaction>> detect({
    required RelationshipGraph changedRelationship,
    required List<RelationshipGraph> allRelationships,
    required List<LifeProfile> allProfiles,
    int maxHops = _defaultMaxHops,
  }) async {
    final reactions = <ChainReaction>[];
    final visited = <String>{};

    // 标记源关系对，避免自环
    final sourcePairKey = _pairKey(
      changedRelationship.personIdA,
      changedRelationship.personIdB,
    );
    visited.add(sourcePairKey);

    // 推断本次变化类型
    final changeType = _inferChangeType(changedRelationship);

    // BFS 多跳传播
    // 当前跳的关系列表
    var currentFrontier = <RelationshipGraph>[changedRelationship];
    var currentHop = 1;

    while (currentHop <= maxHops && currentFrontier.isNotEmpty) {
      final nextFrontier = <RelationshipGraph>[];

      for (final rel in currentFrontier) {
        // 跳过亲密度过低的关系
        if (rel.compositeAffinity.abs() < _intimacyThreshold &&
            rel.intimacy.abs() < _intimacyThreshold) {
          continue;
        }

        final hops = _propagateOneHop(
          changedRel: rel,
          allRels: allRelationships,
          profiles: allProfiles,
          changeType: changeType,
          hopCount: currentHop,
          decayFactor: _hopDecay.pow(currentHop - 1),
          visited: visited,
        );

        for (final hop in hops) {
          reactions.add(ChainReaction(
            sourceRelId: changedRelationship.id,
            affectedCharId: hop.neighborId,
            otherCharId: hop.affectedId,
            reactionType: hop.reactionType,
            description: hop.reason,
            relationshipDelta: hop.delta,
            hopCount: currentHop,
          ));

          // 把受影响的关系加入下一跳前沿
          final affectedRel = _findRel(
            hop.neighborId,
            hop.affectedId,
            allRelationships,
          );
          if (affectedRel != null) {
            final pk = _pairKey(hop.neighborId, hop.affectedId);
            if (!visited.contains(pk)) {
              nextFrontier.add(affectedRel);
            }
          }
        }
      }

      currentFrontier = nextFrontier;
      currentHop++;
    }

    // 按 hopCount 排序，近的优先
    reactions.sort((a, b) => a.hopCount.compareTo(b.hopCount));

    debugPrint(
      'ChainReactionEngine: detected ${reactions.length} reactions '
      'from ${changedRelationship.personIdA}↔${changedRelationship.personIdB} '
      '($changeType)',
    );

    return reactions;
  }

  /// 应用链反应到关系图谱
  ///
  /// 将检测到的链反应写入对应的关系图谱，
  /// 并返回需要写入社交记忆的事件列表。
  ///
  /// 返回值：每个元素为 {characterId, content}，供调用方写入 MemoryEngine。
  Future<List<Map<String, String>>> apply({
    required List<ChainReaction> reactions,
    required List<RelationshipGraph> relationships,
    required List<LifeProfile> profiles,
  }) async {
    final memoryEvents = <Map<String, String>>[];

    for (final reaction in reactions) {
      // 找到受影响的关系图谱
      final rel = _findRel(
        reaction.affectedCharId,
        reaction.otherCharId,
        relationships,
      );
      if (rel == null) continue;

      // 应用变化
      final oldIntimacy = rel.intimacy;
      rel.intimacy = (rel.intimacy + reaction.relationshipDelta).clamp(-1.0, 1.0);

      // 根据反应类型同步调整其他维度
      _applySecondaryEffects(rel, reaction);

      rel.updatedAt = DateTime.now();

      // 记录关系事件
      final event = RelationshipEvent(
        id: 'chain_${reaction.sourceRelId}_${reaction.hopCount}',
        timestamp: DateTime.now(),
        description: '[链反应] ${reaction.description}',
        impact: reaction.relationshipDelta,
        type: _reactionTypeToEventType(reaction.reactionType),
        intensity: reaction.relationshipDelta.abs().clamp(0.0, 1.0),
        isPublic: false,
      );
      rel.events = [...rel.events, event];

      debugPrint(
        'ChainReactionEngine: applied ${reaction.reactionType} to '
        '${reaction.affectedCharId}↔${reaction.otherCharId} '
        '(Δ${reaction.relationshipDelta.toStringAsFixed(3)}, '
        'intimacy ${oldIntimacy.toStringAsFixed(2)}→${rel.intimacy.toStringAsFixed(2)})',
      );

      // 生成社交记忆事件
      final otherName = _getName(reaction.otherCharId, profiles);

      memoryEvents.add({
        'characterId': reaction.affectedCharId,
        'content': '因为${reaction.description}，对$otherName的感觉发生了变化'
            '（${reaction.reactionType}，亲密度'
            '${reaction.relationshipDelta > 0 ? '+' : ''}'
            '${reaction.relationshipDelta.toStringAsFixed(2)}）',
      });
    }

    return memoryEvents;
  }

  // ═══════════════════════════════════════════════
  // 单跳传播
  // ═══════════════════════════════════════════════

  /// 单跳传播：A 和 B 的关系变化如何影响 C
  ///
  /// 遍历 A 和 B 的所有邻居 C，评估 C 的反应。
  List<SingleHop> _propagateOneHop({
    required RelationshipGraph changedRel,
    required List<RelationshipGraph> allRels,
    required List<LifeProfile> profiles,
    required String changeType,
    required int hopCount,
    required double decayFactor,
    required Set<String> visited,
  }) {
    final hops = <SingleHop>[];
    final aId = changedRel.personIdA;
    final bId = changedRel.personIdB;

    // 收集 A 的所有邻居（排除 B）
    final aNeighbors = _getNeighborRels(aId, bId, allRels);
    // 收集 B 的所有邻居（排除 A）
    final bNeighbors = _getNeighborRels(bId, aId, allRels);

    // 评估 A 的邻居对 A-B 关系变化的反应
    for (final cRelToA in aNeighbors) {
      final cId = _otherId(cRelToA, aId);
      final pk = _pairKey(cId, bId);

      // 跳过已访问的对
      if (visited.contains(pk)) continue;
      // 跳过亲密度过低的邻居
      if (cRelToA.intimacy.abs() < _intimacyThreshold) continue;

      // C 对 B 有没有关系？
      final cRelToB = _findRel(cId, bId, allRels);

      final neighbor = _findProfile(cId, profiles);
      if (neighbor == null) continue;

      final hop = _evaluateNeighbor(
        neighbor: neighbor,
        relToOther: cRelToA,
        relToTarget: cRelToB,
        changeType: changeType,
        sourceAId: aId,
        sourceBId: bId,
        decayFactor: decayFactor,
        isFromA: true,
      );

      if (hop != null) {
        hops.add(hop);
        visited.add(pk);
      }
    }

    // 评估 B 的邻居对 A-B 关系变化的反应
    for (final cRelToB in bNeighbors) {
      final cId = _otherId(cRelToB, bId);
      final pk = _pairKey(cId, aId);

      if (visited.contains(pk)) continue;
      if (cRelToB.intimacy.abs() < _intimacyThreshold) continue;

      final cRelToA = _findRel(cId, aId, allRels);
      final neighbor = _findProfile(cId, profiles);
      if (neighbor == null) continue;

      final hop = _evaluateNeighbor(
        neighbor: neighbor,
        relToOther: cRelToB,
        relToTarget: cRelToA,
        changeType: changeType,
        sourceAId: bId,
        sourceBId: aId,
        decayFactor: decayFactor,
        isFromA: false,
      );

      if (hop != null) {
        hops.add(hop);
        visited.add(pk);
      }
    }

    return hops;
  }

  // ═══════════════════════════════════════════════
  // 邻居反应评估
  // ═══════════════════════════════════════════════

  /// 判断 C 对"source 与 target 的关系变化"的反应
  ///
  /// [neighbor] — C 的生命档案
  /// [relToOther] — C 与 source 的关系
  /// [relToTarget] — C 与 target 的关系（可能为 null）
  /// [changeType] — 变化类型
  /// [sourceAId] — 变化的一方
  /// [sourceBId] — 变化的另一方
  /// [decayFactor] — 衰减系数
  /// [isFromA] — C 是 A 的邻居还是 B 的邻居
  SingleHop? _evaluateNeighbor({
    required LifeProfile neighbor,
    required RelationshipGraph relToOther,
    required RelationshipGraph? relToTarget,
    required String changeType,
    required String sourceAId,
    required String sourceBId,
    required double decayFactor,
    required bool isFromA,
  }) {
    final cId = neighbor.id;
    final intimacyToOther = relToOther.intimacy;
    final trustToOther = relToOther.trust;

    switch (changeType) {
      // ── 关系改善 ──
      case 'improved':
        return _reactImproved(
          cId: cId,
          sourceId: sourceAId,
          targetId: sourceBId,
          intimacyToSource: intimacyToOther,
          relToTarget: relToTarget,
          decayFactor: decayFactor,
        );

      // ── 关系恶化 ──
      case 'deteriorated':
        return _reactDeteriorated(
          cId: cId,
          sourceId: sourceAId,
          targetId: sourceBId,
          intimacyToSource: intimacyToOther,
          trustToSource: trustToOther,
          relToTarget: relToTarget,
          decayFactor: decayFactor,
        );

      // ── 冲突 ──
      case 'conflict':
        return _reactConflict(
          cId: cId,
          sourceId: sourceAId,
          targetId: sourceBId,
          intimacyToSource: intimacyToOther,
          trustToSource: trustToOther,
          relToTarget: relToTarget,
          decayFactor: decayFactor,
        );

      // ── 恋爱 ──
      case 'romance':
        return _reactRomance(
          cId: cId,
          sourceId: sourceAId,
          targetId: sourceBId,
          intimacyToSource: intimacyToOther,
          relToOther: relToOther,
          relToTarget: relToTarget,
          decayFactor: decayFactor,
        );

      // ── 分手 ──
      case 'breakup':
        return _reactBreakup(
          cId: cId,
          sourceId: sourceAId,
          targetId: sourceBId,
          intimacyToSource: intimacyToOther,
          relToTarget: relToTarget,
          decayFactor: decayFactor,
        );

      default:
        return null;
    }
  }

  // ─── 具体反应逻辑 ───

  /// 关系改善反应
  SingleHop? _reactImproved({
    required String cId,
    required String sourceId,
    required String targetId,
    required double intimacyToSource,
    required RelationshipGraph? relToTarget,
    required double decayFactor,
  }) {
    // 规则：A 和 B 成为好友 → A 的好友 C 可能对 B 产生好感（+0.1）
    if (intimacyToSource > 0.3) {
      final delta = (0.1 * decayFactor).clamp(-1.0, 1.0);
      return SingleHop(
        neighborId: cId,
        affectedId: targetId,
        reactionType: 'approach',
        delta: delta,
        reason: '$sourceId 与 $targetId 关系改善，'
            '${_pronoun(cId)}对 $targetId 产生好感',
      );
    }
    return null;
  }

  /// 关系恶化反应
  SingleHop? _reactDeteriorated({
    required String cId,
    required String sourceId,
    required String targetId,
    required double intimacyToSource,
    required double trustToSource,
    required RelationshipGraph? relToTarget,
    required double decayFactor,
  }) {
    // 规则：A 和 B 冲突 → A 的好友 C 可能对 B 产生敌意（-0.1）
    if (intimacyToSource > 0.3) {
      final delta = (-0.1 * decayFactor).clamp(-1.0, 1.0);
      return SingleHop(
        neighborId: cId,
        affectedId: targetId,
        reactionType: 'side_take',
        delta: delta,
        reason: '$sourceId 与 $targetId 关系恶化，'
            '${_pronoun(cId)}站在 $sourceId 一边，对 $targetId 产生敌意',
      );
    }
    return null;
  }

  /// 冲突反应
  SingleHop? _reactConflict({
    required String cId,
    required String sourceId,
    required String targetId,
    required double intimacyToSource,
    required double trustToSource,
    required RelationshipGraph? relToTarget,
    required double decayFactor,
  }) {
    // 规则 1：冲突方的亲密好友 C 站队（对另一方产生敌意）
    if (intimacyToSource > 0.4 && trustToSource > 0.2) {
      final delta = (-0.15 * decayFactor).clamp(-1.0, 1.0);
      return SingleHop(
        neighborId: cId,
        affectedId: targetId,
        reactionType: 'side_take',
        delta: delta,
        reason: '$sourceId 与 $targetId 发生冲突，'
            '${_pronoun(cId)}支持 $sourceId，疏远 $targetId',
      );
    }

    // 规则 2：冲突方的普通朋友 C 保持距离（疏远双方中较弱的一方）
    if (intimacyToSource > 0.2 && intimacyToSource <= 0.4) {
      final delta = (-0.05 * decayFactor).clamp(-1.0, 1.0);
      return SingleHop(
        neighborId: cId,
        affectedId: targetId,
        reactionType: 'distance',
        delta: delta,
        reason: '$sourceId 与 $targetId 发生冲突，'
            '${_pronoun(cId)}不想卷入，与 $targetId 保持距离',
      );
    }

    return null;
  }

  /// 恋爱反应
  SingleHop? _reactRomance({
    required String cId,
    required String sourceId,
    required String targetId,
    required double intimacyToSource,
    required RelationshipGraph relToOther,
    required RelationshipGraph? relToTarget,
    required double decayFactor,
  }) {
    // 规则 1：三角关系 — C 暗恋 source，source 和 target 恋爱 → C 嫉妒 target
    if (relToOther.passion > 0.4 && relToOther.commitment < 0.3 &&
        intimacyToSource > 0.3) {
      final delta = (-0.3 * decayFactor).clamp(-1.0, 1.0);
      return SingleHop(
        neighborId: cId,
        affectedId: targetId,
        reactionType: 'jealousy',
        delta: delta,
        reason: '${_pronoun(cId)}暗恋 $sourceId，'
            '但 $sourceId 和 $targetId 在一起了，${_pronoun(cId)}嫉妒 $targetId',
      );
    }

    // 规则 2：source 的好友 C 祝福（+0.05）或吃醋（-0.05）
    if (intimacyToSource > 0.4) {
      // 如果 C 也对 target 有好感，祝福
      if (relToTarget != null && relToTarget.intimacy > 0.2) {
        final delta = (0.05 * decayFactor).clamp(-1.0, 1.0);
        return SingleHop(
          neighborId: cId,
          affectedId: targetId,
          reactionType: 'support',
          delta: delta,
          reason: '$sourceId 和 $targetId 恋爱了，'
              '${_pronoun(cId)}为他们感到高兴',
        );
      }

      // 如果 C 对 target 不熟或有点嫉妒
      final jealousyFactor = (intimacyToSource - 0.4) / 0.6; // 0~1
      final delta = (-0.05 * jealousyFactor * decayFactor).clamp(-1.0, 1.0);
      if (delta.abs() > 0.005) {
        return SingleHop(
          neighborId: cId,
          affectedId: targetId,
          reactionType: 'jealousy',
          delta: delta,
          reason: '$sourceId 和 $targetId 恋爱了，'
              '${_pronoun(cId)}有点失落',
        );
      }
    }

    // 规则 3：C 和 source 是好友 → B 和 C 成为好友 → A 可能被冷落
    // 这个规则在 B 的好友圈评估时触发（isFromA=false）
    // 当 isFromA=false 且 source=target, target=source 时对称处理
    if (intimacyToSource > 0.3 && relToTarget != null &&
        relToTarget.intimacy > 0.3) {
      // C 和恋爱双方都是好友 → 关系可能被稀释（被冷落）
      final delta = (-0.03 * decayFactor).clamp(-1.0, 1.0);
      return SingleHop(
        neighborId: cId,
        affectedId: sourceId,
        reactionType: 'distance',
        delta: delta,
        reason: '$sourceId 和 $targetId 恋爱后，'
            '${_pronoun(cId)}感觉被冷落了',
      );
    }

    return null;
  }

  /// 分手反应
  SingleHop? _reactBreakup({
    required String cId,
    required String sourceId,
    required String targetId,
    required double intimacyToSource,
    required RelationshipGraph? relToTarget,
    required double decayFactor,
  }) {
    // 规则：共同好友被迫站队
    if (relToTarget != null) {
      final intimacyToTarget = relToTarget.intimacy;
      final isMutualFriend = intimacyToSource > 0.3 && intimacyToTarget > 0.3;

      if (isMutualFriend) {
        // 共同好友被迫选边 — 倾向关系更亲密的一方
        final preference = intimacyToSource - intimacyToTarget;
        // 对较疏远的一方产生轻微疏远
        if (preference > 0.1) {
          // C 更亲近 source → 疏远 target
          final delta = (-0.1 * decayFactor).clamp(-1.0, 1.0);
          return SingleHop(
            neighborId: cId,
            affectedId: targetId,
            reactionType: 'side_take',
            delta: delta,
            reason: '$sourceId 和 $targetId 分手了，'
                '${_pronoun(cId)}更偏向 $sourceId，与 $targetId 保持距离',
          );
        } else if (preference < -0.1) {
          // C 更亲近 target → 疏远 source
          final delta = (-0.1 * decayFactor).clamp(-1.0, 1.0);
          return SingleHop(
            neighborId: cId,
            affectedId: sourceId,
            reactionType: 'side_take',
            delta: delta,
            reason: '$sourceId 和 $targetId 分手了，'
                '${_pronoun(cId)}更偏向 $targetId，与 $sourceId 保持距离',
          );
        } else {
          // 差不多亲近 → 两边都稍微疏远（夹在中间的尴尬）
          final delta = (-0.04 * decayFactor).clamp(-1.0, 1.0);
          return SingleHop(
            neighborId: cId,
            affectedId: targetId,
            reactionType: 'distance',
            delta: delta,
            reason: '$sourceId 和 $targetId 分手了，'
                '${_pronoun(cId)}夹在中间很为难',
          );
        }
      }
    }

    // 非共同好友：对分手方的亲密好友产生轻微影响
    if (intimacyToSource > 0.5) {
      final delta = (-0.03 * decayFactor).clamp(-1.0, 1.0);
      return SingleHop(
        neighborId: cId,
        affectedId: targetId,
        reactionType: 'distance',
        delta: delta,
        reason: '$sourceId 和 $targetId 分手了，'
            '${_pronoun(cId)}对 $targetId 有些不满',
      );
    }

    return null;
  }

  // ═══════════════════════════════════════════════
  // 辅助方法
  // ═══════════════════════════════════════════════

  /// 推断关系变化类型
  String _inferChangeType(RelationshipGraph rel) {
    // 冲突状态
    if (rel.isInConflict) return 'conflict';

    // 恋爱状态
    if (rel.inferredType == RelationshipType.lover) return 'romance';

    // 暗恋
    if (rel.inferredType == RelationshipType.crush) return 'romance';

    // 高亲密 = 改善
    if (rel.intimacy > 0.4) return 'improved';

    // 低亲密 = 恶化
    if (rel.intimacy < -0.2) return 'deteriorated';

    // 默认：改善（正向变化）
    return 'improved';
  }

  /// 获取角色 A 的邻居关系（排除 B）
  List<RelationshipGraph> _getNeighborRels(
    String aId,
    String excludeId,
    List<RelationshipGraph> allRels,
  ) {
    return allRels.where((r) {
      final isA = r.personIdA == aId || r.personIdB == aId;
      final hasExclude = r.personIdA == excludeId || r.personIdB == excludeId;
      return isA && !hasExclude;
    }).toList();
  }

  /// 获取关系中"另一边"的角色 ID
  String _otherId(RelationshipGraph rel, String id) {
    return rel.personIdA == id ? rel.personIdB : rel.personIdA;
  }

  /// 查找两个角色之间的关系
  RelationshipGraph? _findRel(
    String aId,
    String bId,
    List<RelationshipGraph> allRels,
  ) {
    final pk = _pairKey(aId, bId);
    for (final r in allRels) {
      if (_pairKey(r.personIdA, r.personIdB) == pk) return r;
    }
    return null;
  }

  /// 生成排序后的 pair key
  String _pairKey(String a, String b) {
    return a.compareTo(b) < 0 ? '${a}_$b' : '${b}_$a';
  }

  /// 查找角色名
  String _getName(String id, List<LifeProfile> profiles) {
    for (final p in profiles) {
      if (p.id == id) return p.name;
    }
    return id;
  }

  /// 查找生命档案
  LifeProfile? _findProfile(String id, List<LifeProfile> profiles) {
    for (final p in profiles) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// 代词辅助
  String _pronoun(String id) => 'TA';

  /// 将反应类型映射到关系事件类型
  RelationshipEventType _reactionTypeToEventType(String reactionType) {
    switch (reactionType) {
      case 'approach':
        return RelationshipEventType.kindness;
      case 'distance':
        return RelationshipEventType.misunderstanding;
      case 'side_take':
        return RelationshipEventType.conflict;
      case 'jealousy':
        return RelationshipEventType.argument;
      case 'support':
        return RelationshipEventType.support;
      default:
        return RelationshipEventType.kindness;
    }
  }

  /// 应用次要效果（根据反应类型同步调整 trust / tension 等）
  void _applySecondaryEffects(
    RelationshipGraph rel,
    ChainReaction reaction,
  ) {
    switch (reaction.reactionType) {
      case 'approach':
        // 好感增加 → 信任微增、紧张微降
        rel.trust = (rel.trust + reaction.relationshipDelta * 0.3).clamp(-1.0, 1.0);
        rel.tension = (rel.tension - reaction.relationshipDelta.abs() * 0.1).clamp(0.0, 1.0);
        break;
      case 'distance':
        // 疏远 → 熟悉度微降
        rel.familiarity = (rel.familiarity + reaction.relationshipDelta * 0.2).clamp(0.0, 1.0);
        break;
      case 'side_take':
        // 站队 → 紧张度上升、信任下降
        rel.trust = (rel.trust + reaction.relationshipDelta * 0.2).clamp(-1.0, 1.0);
        rel.tension = (rel.tension + reaction.relationshipDelta.abs() * 0.15).clamp(0.0, 1.0);
        break;
      case 'jealousy':
        // 嫉妒 → 紧张度上升、激情微增
        rel.tension = (rel.tension + reaction.relationshipDelta.abs() * 0.1).clamp(0.0, 1.0);
        rel.passion = (rel.passion + reaction.relationshipDelta.abs() * 0.05).clamp(0.0, 1.0);
        break;
      case 'support':
        // 支持 → 信任增加、承诺微增
        rel.trust = (rel.trust + reaction.relationshipDelta * 0.3).clamp(-1.0, 1.0);
        rel.commitment = (rel.commitment + reaction.relationshipDelta * 0.1).clamp(-1.0, 1.0);
        break;
    }
  }
}

// ─────────────────────────────────────────────────
// 扩展：double 的 pow 辅助
// ─────────────────────────────────────────────────

extension _DoublePow on double {
  double pow(int exponent) {
    double result = 1.0;
    for (int i = 0; i < exponent; i++) {
      result *= this;
    }
    return result;
  }
}
