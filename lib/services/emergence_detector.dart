// ============================================================
// 全生命周期数字生命世界 — Phase 5
// 涌现检测器：检测多角色互动中涌现的复杂行为模式
//
// 每次心跳调用 detect()，扫描所有角色的关系网络与近期社交行为，
// 检测以下涌现模式：
//   - 流言：A和B的冲突被C知道了
//   - 极化：两人冲突导致朋友圈分裂
//   - 群体事件：多人共同经历
//   - 关系链反应：A和B好了，B的敌人C可能疏远B
//   - 站队：冲突中有人选择立场
//   - 联盟 / 背叛 / 三角关系
// ============================================================

import 'dart:math';
import 'package:uuid/uuid.dart';

import '../models/life_profile.dart';
import '../models/memory.dart';
import 'ai_relationship_service.dart';

// ─────────────────────────────────────────────
// 涌现事件类型
// ─────────────────────────────────────────────

/// 涌现模式类型
enum EmergenceType {
  rumor,         // 流言
  polarization,  // 极化
  groupEvent,    // 群体事件
  chainReaction, // 关系链反应
  sideTaking,    // 站队
  alliance,      // 联盟
  betrayal,      // 背叛
  loveTriangle,  // 三角关系
}

/// 涌现事件 — 检测到的群体行为模式
class EmergenceEvent {
  final String id;
  final EmergenceType type;
  final List<String> involvedCharacterIds;
  final String description;
  final DateTime timestamp;
  final Map<String, dynamic> metadata;

  const EmergenceEvent({
    required this.id,
    required this.type,
    required this.involvedCharacterIds,
    required this.description,
    required this.timestamp,
    this.metadata = const {},
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'involvedCharacterIds': involvedCharacterIds,
        'description': description,
        'timestamp': timestamp.toIso8601String(),
        'metadata': metadata,
      };
}

// ─────────────────────────────────────────────
// 流言事件（供 RumorEngine 使用）
// ─────────────────────────────────────────────

/// 流言事件
class RumorEvent {
  final String id;
  final String sourceId;          // 流言源头
  final List<String> subjectIds;  // 被谈论的人
  final String content;           // 流言内容
  final double truthfulness;      // 真实度（1=完全真实，0=纯捏造）
  final DateTime createdAt;

  const RumorEvent({
    required this.id,
    required this.sourceId,
    required this.subjectIds,
    required this.content,
    this.truthfulness = 1.0,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'sourceId': sourceId,
        'subjectIds': subjectIds,
        'content': content,
        'truthfulness': truthfulness,
        'createdAt': createdAt.toIso8601String(),
      };
}

// ─────────────────────────────────────────────
// 极化事件
// ─────────────────────────────────────────────

/// 极化事件 — 两人冲突导致朋友圈分裂
class PolarizationEvent {
  final String id;
  final String characterIdA;
  final String characterIdB;
  final List<String> sideA; // 支持A的人
  final List<String> sideB; // 支持B的人
  final double intensity;   // 极化强度 0-1
  final DateTime createdAt;

  const PolarizationEvent({
    required this.id,
    required this.characterIdA,
    required this.characterIdB,
    required this.sideA,
    required this.sideB,
    required this.intensity,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'characterIdA': characterIdA,
        'characterIdB': characterIdB,
        'sideA': sideA,
        'sideB': sideB,
        'intensity': intensity,
        'createdAt': createdAt.toIso8601String(),
      };
}

// ─────────────────────────────────────────────
// 群体事件
// ─────────────────────────────────────────────

/// 群体事件 — 多人共同经历
class GroupEvent {
  final String id;
  final List<String> participantIds;
  final String eventType; // celebration / conflict / gathering / crisis
  final String description;
  final DateTime createdAt;

  const GroupEvent({
    required this.id,
    required this.participantIds,
    required this.eventType,
    required this.description,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'participantIds': participantIds,
        'eventType': eventType,
        'description': description,
        'createdAt': createdAt.toIso8601String(),
      };
}

// ─────────────────────────────────────────────
// 关系链反应
// ─────────────────────────────────────────────

/// 关系链反应 — 一对关系变化引发连锁反应
class ChainReaction {
  final String id;
  final String triggerPairA;      // 触发变化的角色A
  final String triggerPairB;      // 触发变化的角色B
  final String reactionCharacter; // 产生反应的角色
  final String reactionType;      // drift_closer / drift_apart / betray
  final String reason;
  final DateTime createdAt;

  const ChainReaction({
    required this.id,
    required this.triggerPairA,
    required this.triggerPairB,
    required this.reactionCharacter,
    required this.reactionType,
    required this.reason,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'triggerPairA': triggerPairA,
        'triggerPairB': triggerPairB,
        'reactionCharacter': reactionCharacter,
        'reactionType': reactionType,
        'reason': reason,
        'createdAt': createdAt.toIso8601String(),
      };
}

// ─────────────────────────────────────────────
// 站队事件
// ─────────────────────────────────────────────

/// 站队事件 — 冲突中有人选择立场
class SideTakingEvent {
  final String id;
  final String conflictA;   // 冲突方A
  final String conflictB;   // 冲突方B
  final String takerId;     // 站队的人
  final String sidedWith;   // 选择了谁（conflictA 或 conflictB）
  final double confidence;  // 站队坚定程度 0-1
  final DateTime createdAt;

  const SideTakingEvent({
    required this.id,
    required this.conflictA,
    required this.conflictB,
    required this.takerId,
    required this.sidedWith,
    required this.confidence,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'conflictA': conflictA,
        'conflictB': conflictB,
        'takerId': takerId,
        'sidedWith': sidedWith,
        'confidence': confidence,
        'createdAt': createdAt.toIso8601String(),
      };
}

// ─────────────────────────────────────────────
// 涌现检测器
// ─────────────────────────────────────────────

/// 涌现检测器
///
/// 检测多角色互动中涌现的复杂行为模式。
/// 纯逻辑判断，不需要 LLM。
/// 每次心跳调用 [detect]，返回所有检测到的涌现事件。
class EmergenceDetector {
  final Random _random = Random();

  /// 每次心跳调用，检测是否触发群体事件
  Future<List<EmergenceEvent>> detect({
    required List<LifeProfile> profiles,
    required List<AIRelationship> relationships,
    required List<Memory> recentActions,
  }) async {
    final events = <EmergenceEvent>[];

    // 1. 流言检测
    final rumors = _detectRumors(recentActions, profiles);
    for (final rumor in rumors) {
      events.add(EmergenceEvent(
        id: const Uuid().v4(),
        type: EmergenceType.rumor,
        involvedCharacterIds: [rumor.sourceId, ...rumor.subjectIds],
        description: '流言：${rumor.content}',
        timestamp: rumor.createdAt,
        metadata: rumor.toJson(),
      ));
    }

    // 2. 极化检测
    final polarizations = _detectPolarization(relationships);
    for (final p in polarizations) {
      events.add(EmergenceEvent(
        id: const Uuid().v4(),
        type: EmergenceType.polarization,
        involvedCharacterIds: [
          p.characterIdA,
          p.characterIdB,
          ...p.sideA,
          ...p.sideB,
        ],
        description:
            '极化：${p.characterIdA} 与 ${p.characterIdB} 的冲突导致朋友圈分裂',
        timestamp: p.createdAt,
        metadata: p.toJson(),
      ));
    }

    // 3. 群体事件检测
    final groupEvents = _detectGroupEvents(profiles, recentActions);
    for (final g in groupEvents) {
      events.add(EmergenceEvent(
        id: const Uuid().v4(),
        type: EmergenceType.groupEvent,
        involvedCharacterIds: g.participantIds,
        description: g.description,
        timestamp: g.createdAt,
        metadata: g.toJson(),
      ));
    }

    // 4. 关系链反应检测
    final chainReactions = _detectChainReactions(relationships);
    for (final cr in chainReactions) {
      events.add(EmergenceEvent(
        id: const Uuid().v4(),
        type: EmergenceType.chainReaction,
        involvedCharacterIds: [
          cr.triggerPairA,
          cr.triggerPairB,
          cr.reactionCharacter,
        ],
        description: cr.reason,
        timestamp: cr.createdAt,
        metadata: cr.toJson(),
      ));
    }

    // 5. 站队检测
    final sideTakings = _detectSideTaking(profiles, relationships);
    for (final st in sideTakings) {
      events.add(EmergenceEvent(
        id: const Uuid().v4(),
        type: EmergenceType.sideTaking,
        involvedCharacterIds: [st.conflictA, st.conflictB, st.takerId],
        description:
            '站队：${st.takerId} 在 ${st.conflictA} 与 ${st.conflictB} '
            '的冲突中选择了 ${st.sidedWith}',
        timestamp: st.createdAt,
        metadata: st.toJson(),
      ));
    }

    // 6. 三角关系检测
    final triangles = _detectLoveTriangles(relationships);
    for (final t in triangles) {
      events.add(EmergenceEvent(
        id: const Uuid().v4(),
        type: EmergenceType.loveTriangle,
        involvedCharacterIds: t,
        description: '三角关系：${t.join("、")} 之间形成了情感纠葛',
        timestamp: DateTime.now(),
        metadata: {'triangle': t},
      ));
    }

    // 7. 联盟检测
    final alliances = _detectAlliances(relationships);
    for (final a in alliances) {
      events.add(EmergenceEvent(
        id: const Uuid().v4(),
        type: EmergenceType.alliance,
        involvedCharacterIds: a,
        description: '联盟：${a.join("、")} 形成了紧密同盟',
        timestamp: DateTime.now(),
        metadata: {'alliance': a},
      ));
    }

    // 8. 背叛检测
    final betrayals = _detectBetrayals(relationships, recentActions);
    for (final b in betrayals) {
      events.add(EmergenceEvent(
        id: const Uuid().v4(),
        type: EmergenceType.betrayal,
        involvedCharacterIds: b['involved'] as List<String>,
        description: b['description'] as String,
        timestamp: DateTime.now(),
        metadata: b,
      ));
    }

    return events;
  }

  // ───────────────────────────────────────────
  // 流言检测：A和B的冲突被C知道了
  // ───────────────────────────────────────────

  List<RumorEvent> _detectRumors(
    List<Memory> recentActions,
    List<LifeProfile> profiles,
  ) {
    final rumors = <RumorEvent>[];

    // 找出所有涉及冲突/争吵的社交记忆
    final conflicts = recentActions.where((m) {
      final content = m.content.toLowerCase();
      return content.contains('冲突') ||
          content.contains('争吵') ||
          content.contains('吵架') ||
          content.contains('争执') ||
          content.contains('闹翻') ||
          content.contains('决裂') ||
          content.contains('不满') ||
          content.contains('讨厌');
    }).toList();

    if (conflicts.isEmpty) return rumors;

    final profileIds = profiles.map((p) => p.id).toSet();

    for (final conflict in conflicts) {
      // 冲突的当事人
      final subjects = <String>{
        conflict.characterId,
        // 尝试从 keywords 提取目标角色
        ...conflict.keywords.where((k) => profileIds.contains(k)),
      }.toList();

      if (subjects.length < 2) continue;

      // 找第三方知道这件事的人：
      // - 不是当事人
      // - 最近有社交记忆提到了当事人中的任何一个
      for (final observer in recentActions) {
        if (subjects.contains(observer.characterId)) continue;

        // 第三方是否提到了当事人
        final mentionsSubject = subjects.any(
          (s) => observer.content.contains(s) ||
              observer.keywords.contains(s),
        );

        if (!mentionsSubject) continue;

        // 已经是流言了（避免重复）
        final alreadyKnown = rumors.any(
          (r) => r.sourceId == observer.characterId &&
              r.subjectIds.toSet().containsAll(subjects),
        );
        if (alreadyKnown) continue;

        rumors.add(RumorEvent(
          id: const Uuid().v4(),
          sourceId: observer.characterId,
          subjectIds: subjects,
          content: '${subjects.join("和")}之间发生了冲突',
          truthfulness: 0.8 + _random.nextDouble() * 0.2,
          createdAt: DateTime.now(),
        ));
      }
    }

    return rumors;
  }

  // ───────────────────────────────────────────
  // 极化检测：两人冲突导致朋友圈分裂
  // ───────────────────────────────────────────

  List<PolarizationEvent> _detectPolarization(
    List<AIRelationship> relationships,
  ) {
    final polarizations = <PolarizationEvent>[];

    // 找出所有敌对/冲突关系
    final conflicts = relationships.where((r) =>
        r.relationshipType == RelationshipType.enemy ||
        (r.relationshipType == RelationshipType.rival && r.affinity < 0.2));

    for (final conflict in conflicts) {
      final aId = conflict.characterIdA;
      final bId = conflict.characterIdB;

      // 收集A和B各自的朋友
      final aFriends = <String>[];
      final bFriends = <String>[];

      for (final rel in relationships) {
        if (rel.id == conflict.id) continue;

        final isAFriend =
            (rel.characterIdA == aId || rel.characterIdB == aId) &&
                (rel.relationshipType == RelationshipType.friend ||
                    rel.relationshipType == RelationshipType.bestFriend ||
                    rel.relationshipType == RelationshipType.lover) &&
                rel.affinity > 0.5;

        final isBFriend =
            (rel.characterIdA == bId || rel.characterIdB == bId) &&
                (rel.relationshipType == RelationshipType.friend ||
                    rel.relationshipType == RelationshipType.bestFriend ||
                    rel.relationshipType == RelationshipType.lover) &&
                rel.affinity > 0.5;

        if (isAFriend) {
          final friendId =
              rel.characterIdA == aId ? rel.characterIdB : rel.characterIdA;
          aFriends.add(friendId);
        }
        if (isBFriend) {
          final friendId =
              rel.characterIdA == bId ? rel.characterIdB : rel.characterIdA;
          bFriends.add(friendId);
        }
      }

      // 检查是否有交集（共同朋友），交集中的角色面临选边
      final commonFriends =
          aFriends.toSet().intersection(bFriends.toSet()).toList();

      if (commonFriends.isNotEmpty) {
        // 极化强度：取决于冲突的激烈程度和共同朋友数量
        final intensity =
            (1.0 - conflict.affinity).clamp(0.0, 1.0) *
                (commonFriends.length /
                        (aFriends.length + bFriends.length + 1))
                    .clamp(0.0, 1.0);

        if (intensity > 0.2) {
          polarizations.add(PolarizationEvent(
            id: const Uuid().v4(),
            characterIdA: aId,
            characterIdB: bId,
            sideA:
                aFriends.where((f) => !commonFriends.contains(f)).toList(),
            sideB:
                bFriends.where((f) => !commonFriends.contains(f)).toList(),
            intensity: intensity,
            createdAt: DateTime.now(),
          ));
        }
      }
    }

    return polarizations;
  }

  // ───────────────────────────────────────────
  // 群体事件检测：多人共同经历
  // ───────────────────────────────────────────

  List<GroupEvent> _detectGroupEvents(
    List<LifeProfile> profiles,
    List<Memory> recentActions,
  ) {
    final groupEvents = <GroupEvent>[];

    // 按时间段聚类社交记忆（同一时间窗口内 3+ 人参与的事件）
    // 按时间窗口分组（30分钟窗口）
    final windowBuckets = <DateTime, List<Memory>>{};
    for (final action in recentActions) {
      final bucketKey = DateTime(
        action.createdAt.year,
        action.createdAt.month,
        action.createdAt.day,
        action.createdAt.hour,
        (action.createdAt.minute ~/ 30) * 30,
      );
      windowBuckets.putIfAbsent(bucketKey, () => []).add(action);
    }

    for (final entry in windowBuckets.entries) {
      final participants =
          entry.value.map((m) => m.characterId).toSet().toList();

      // 3人以上才算群体事件
      if (participants.length < 3) continue;

      // 判断事件类型
      final contents = entry.value.map((m) => m.content).join(' ');
      String eventType = 'gathering';
      String description = '${participants.join("、")} 聚在了一起';

      if (contents.contains('庆祝') || contents.contains('生日')) {
        eventType = 'celebration';
        description = '${participants.join("、")} 一起庆祝';
      } else if (contents.contains('冲突') || contents.contains('争吵')) {
        eventType = 'conflict';
        description = '${participants.join("、")} 卷入了一场群体冲突';
      } else if (contents.contains('危机') || contents.contains('紧急')) {
        eventType = 'crisis';
        description = '${participants.join("、")} 共同面对一场危机';
      }

      groupEvents.add(GroupEvent(
        id: const Uuid().v4(),
        participantIds: participants,
        eventType: eventType,
        description: description,
        createdAt: entry.key,
      ));
    }

    return groupEvents;
  }

  // ───────────────────────────────────────────
  // 关系链反应：A和B好了 → B的敌人C可能疏远B
  // ───────────────────────────────────────────

  List<ChainReaction> _detectChainReactions(
    List<AIRelationship> relationships,
  ) {
    final reactions = <ChainReaction>[];

    // 找出所有亲密关系（朋友/恋人，亲密度高）
    final closePairs = relationships.where((r) =>
        (r.relationshipType == RelationshipType.friend ||
            r.relationshipType == RelationshipType.bestFriend ||
            r.relationshipType == RelationshipType.lover) &&
        r.affinity > 0.6);

    for (final pair in closePairs) {
      final aId = pair.characterIdA;
      final bId = pair.characterIdB;

      // 检查是否有角色C与其中一方是敌对关系
      for (final rel in relationships) {
        if (rel.id == pair.id) continue;

        // C是A的敌人
        if ((rel.characterIdA == aId || rel.characterIdB == aId) &&
            (rel.relationshipType == RelationshipType.enemy ||
                rel.relationshipType == RelationshipType.rival)) {
          final cId =
              rel.characterIdA == aId ? rel.characterIdB : rel.characterIdA;

          // C和B的关系：如果C和B本来是朋友，B和A好了，C可能疏远B
          final cbRel = _findRelationship(bId, cId, relationships);
          if (cbRel != null &&
              (cbRel.relationshipType == RelationshipType.friend ||
                  cbRel.relationshipType == RelationshipType.bestFriend ||
                  cbRel.relationshipType == RelationshipType.mentor) &&
              cbRel.affinity > 0.3) {
            reactions.add(ChainReaction(
              id: const Uuid().v4(),
              triggerPairA: aId,
              triggerPairB: bId,
              reactionCharacter: cId,
              reactionType: 'drift_apart',
              reason: '$aId 和 $bId 关系变好，但 $cId 是 $aId 的敌人，'
                  '可能因此疏远 $bId',
              createdAt: DateTime.now(),
            ));
          }
        }

        // C是B的敌人（对称检测）
        if ((rel.characterIdA == bId || rel.characterIdB == bId) &&
            (rel.relationshipType == RelationshipType.enemy ||
                rel.relationshipType == RelationshipType.rival)) {
          final cId =
              rel.characterIdA == bId ? rel.characterIdB : rel.characterIdA;

          final caRel = _findRelationship(aId, cId, relationships);
          if (caRel != null &&
              (caRel.relationshipType == RelationshipType.friend ||
                  caRel.relationshipType == RelationshipType.bestFriend ||
                  caRel.relationshipType == RelationshipType.mentor) &&
              caRel.affinity > 0.3) {
            reactions.add(ChainReaction(
              id: const Uuid().v4(),
              triggerPairA: aId,
              triggerPairB: bId,
              reactionCharacter: cId,
              reactionType: 'drift_apart',
              reason: '$bId 和 $aId 关系变好，但 $cId 是 $bId 的敌人，'
                  '可能因此疏远 $aId',
              createdAt: DateTime.now(),
            ));
          }
        }
      }
    }

    return reactions;
  }

  // ───────────────────────────────────────────
  // 站队检测：冲突中有人选择立场
  // ───────────────────────────────────────────

  List<SideTakingEvent> _detectSideTaking(
    List<LifeProfile> profiles,
    List<AIRelationship> relationships,
  ) {
    final events = <SideTakingEvent>[];

    // 找出所有敌对/冲突关系
    final conflicts = relationships.where((r) =>
        r.relationshipType == RelationshipType.enemy ||
        (r.relationshipType == RelationshipType.rival && r.affinity < 0.3));

    for (final conflict in conflicts) {
      final aId = conflict.characterIdA;
      final bId = conflict.characterIdB;

      // 找与双方都有关系的第三方
      final thirdParties = <String>{};
      for (final rel in relationships) {
        if (rel.characterIdA == aId || rel.characterIdA == bId) {
          thirdParties.add(rel.characterIdB);
        }
        if (rel.characterIdB == aId || rel.characterIdB == bId) {
          thirdParties.add(rel.characterIdA);
        }
      }
      thirdParties.remove(aId);
      thirdParties.remove(bId);

      for (final taker in thirdParties) {
        final relWithA = _findRelationship(taker, aId, relationships);
        final relWithB = _findRelationship(taker, bId, relationships);

        // 只有与双方都有关系时才算站队
        if (relWithA == null || relWithB == null) continue;

        // 亲密度差异 > 0.3 才算明确站队
        final diff = (relWithA.affinity - relWithB.affinity).abs();
        if (diff < 0.3) continue;

        final sidedWith =
            relWithA.affinity > relWithB.affinity ? aId : bId;
        final confidence = diff.clamp(0.0, 1.0);

        events.add(SideTakingEvent(
          id: const Uuid().v4(),
          conflictA: aId,
          conflictB: bId,
          takerId: taker,
          sidedWith: sidedWith,
          confidence: confidence,
          createdAt: DateTime.now(),
        ));
      }
    }

    return events;
  }

  // ───────────────────────────────────────────
  // 三角关系检测
  // ───────────────────────────────────────────

  List<List<String>> _detectLoveTriangles(
    List<AIRelationship> relationships,
  ) {
    final triangles = <List<String>>[];

    // 找出所有暗恋/恋人关系
    final romantic = relationships.where((r) =>
        r.relationshipType == RelationshipType.crush ||
        r.relationshipType == RelationshipType.lover);

    // 建立有向浪漫关系图
    final loves = <String, Set<String>>{};
    for (final rel in romantic) {
      loves
          .putIfAbsent(rel.characterIdA, () => {})
          .add(rel.characterIdB);
      // crush/lover 可能是单向的，也检查反向
      loves
          .putIfAbsent(rel.characterIdB, () => {})
          .add(rel.characterIdA);
    }

    // 检测三角：A→B, B→C, C→A 或 A→B, A→C（同时喜欢两个人）
    final allIds = loves.keys.toList();
    for (int i = 0; i < allIds.length; i++) {
      for (int j = i + 1; j < allIds.length; j++) {
        for (int k = j + 1; k < allIds.length; k++) {
          final a = allIds[i];
          final b = allIds[j];
          final c = allIds[k];

          final aLovesB = loves[a]?.contains(b) ?? false;
          final bLovesA = loves[b]?.contains(a) ?? false;
          final aLovesC = loves[a]?.contains(c) ?? false;
          final bLovesC = loves[b]?.contains(c) ?? false;
          final cLovesA = loves[c]?.contains(a) ?? false;
          final cLovesB = loves[c]?.contains(b) ?? false;

          // 至少存在 3 条有向浪漫关系才算三角
          final count = [
            aLovesB,
            bLovesA,
            aLovesC,
            bLovesC,
            cLovesA,
            cLovesB,
          ].where((v) => v).length;

          if (count >= 3) {
            final triangle = [a, b, c]..sort();
            // 去重
            final isDuplicate = triangles.any((t) =>
                t[0] == triangle[0] &&
                t[1] == triangle[1] &&
                t[2] == triangle[2]);
            if (!isDuplicate) {
              triangles.add(triangle);
            }
          }
        }
      }
    }

    return triangles;
  }

  // ───────────────────────────────────────────
  // 联盟检测：多人形成紧密同盟
  // ───────────────────────────────────────────

  List<List<String>> _detectAlliances(
    List<AIRelationship> relationships,
  ) {
    final alliances = <List<String>>[];

    // 构建亲密度图
    final affinityMap = <String, Map<String, double>>{};
    for (final rel in relationships) {
      if (rel.affinity < 0.7) continue;
      if (rel.relationshipType != RelationshipType.friend &&
          rel.relationshipType != RelationshipType.bestFriend &&
          rel.relationshipType != RelationshipType.lover) {
        continue;
      }

      affinityMap
          .putIfAbsent(rel.characterIdA, () => {})[rel.characterIdB] =
          rel.affinity;
      affinityMap
          .putIfAbsent(rel.characterIdB, () => {})[rel.characterIdA] =
          rel.affinity;
    }

    // 找出三角形联盟（三人互相高亲密度）
    final allIds = affinityMap.keys.toList();
    for (int i = 0; i < allIds.length; i++) {
      for (int j = i + 1; j < allIds.length; j++) {
        for (int k = j + 1; k < allIds.length; k++) {
          final a = allIds[i];
          final b = allIds[j];
          final c = allIds[k];

          final ab = affinityMap[a]?[b] ?? 0;
          final bc = affinityMap[b]?[c] ?? 0;
          final ca = affinityMap[c]?[a] ?? 0;

          if (ab > 0.7 && bc > 0.7 && ca > 0.7) {
            final alliance = [a, b, c]..sort();
            final isDuplicate = alliances.any((al) =>
                al[0] == alliance[0] &&
                al[1] == alliance[1] &&
                al[2] == alliance[2]);
            if (!isDuplicate) {
              alliances.add(alliance);
            }
          }
        }
      }
    }

    return alliances;
  }

  // ───────────────────────────────────────────
  // 背叛检测
  // ───────────────────────────────────────────

  List<Map<String, dynamic>> _detectBetrayals(
    List<AIRelationship> relationships,
    List<Memory> recentActions,
  ) {
    final betrayals = <Map<String, dynamic>>[];

    // 找出曾经亲密但最近出现负面社交记忆的关系对
    final closePairs = relationships.where((r) =>
        (r.relationshipType == RelationshipType.friend ||
            r.relationshipType == RelationshipType.bestFriend ||
            r.relationshipType == RelationshipType.lover) &&
        r.affinity > 0.4);

    for (final pair in closePairs) {
      final aId = pair.characterIdA;
      final bId = pair.characterIdB;

      // 检查最近是否有负面互动
      final negativeInteraction = recentActions.any((m) {
        final isBetweenPair =
            (m.characterId == aId && m.keywords.contains(bId)) ||
                (m.characterId == bId && m.keywords.contains(aId));
        if (!isBetweenPair) return false;

        final content = m.content.toLowerCase();
        return content.contains('背叛') ||
            content.contains('欺骗') ||
            content.contains('出卖') ||
            content.contains('背后说坏话') ||
            content.contains('泄露秘密');
      });

      if (negativeInteraction) {
        betrayals.add({
          'involved': [aId, bId],
          'description': '$aId 和 $bId 之间出现了背叛行为',
          'previousType': _relationshipLabel(pair.relationshipType),
          'affinity': pair.affinity,
        });
      }
    }

    return betrayals;
  }

  // ───────────────────────────────────────────
  // 工具方法
  // ───────────────────────────────────────────

  /// 关系类型标签
  String _relationshipLabel(RelationshipType type) {
    switch (type) {
      case RelationshipType.stranger:
        return '陌生人';
      case RelationshipType.friend:
        return '好友';
      case RelationshipType.bestFriend:
        return '挚友';
      case RelationshipType.crush:
        return '暗恋';
      case RelationshipType.rival:
        return '对手';
      case RelationshipType.mentor:
        return '师徒';
      case RelationshipType.sibling:
        return '兄妹';
      case RelationshipType.lover:
        return '恋人';
      case RelationshipType.enemy:
        return '敌对';
    }
  }

  /// 查找两个角色之间的关系（双向）
  AIRelationship? _findRelationship(
    String idA,
    String idB,
    List<AIRelationship> relationships,
  ) {
    for (final rel in relationships) {
      if ((rel.characterIdA == idA && rel.characterIdB == idB) ||
          (rel.characterIdA == idB && rel.characterIdB == idA)) {
        return rel;
      }
    }
    return null;
  }
}
