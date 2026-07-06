// ============================================================
// 全生命周期数字生命世界 — Phase 5
// 流言传播引擎：模拟流言在角色网络中的传播、失真与影响
//
// 流言传播规则：
//   - 外向性 > 0.6 的角色更爱传播
//   - 宜人性 < 0.4 的角色更爱传播负面流言
//   - 与当事人关系越远，越敢传播
//   - 每传播一跳，真实度衰减 10-30%
//   - 被传谣者可能产生愤怒、委屈情绪
// ============================================================

import 'dart:math';
import 'package:flutter/foundation.dart';

import '../models/life_profile.dart';
import 'ai_relationship_service.dart';
import 'emergence_detector.dart';
import 'memory_engine.dart';

// ─────────────────────────────────────────────
// 流言传播结果
// ─────────────────────────────────────────────

/// 流言传播记录 — 一次传播行为
class RumorSpread {
  final String spreaderId;  // 传播者
  final String listenerId;  // 听到的人
  final String content;     // 可能失真后的版本
  final int hopCount;       // 第几手
  final double truthfulnessAtHop; // 当前真实度
  final DateTime timestamp;

  const RumorSpread({
    required this.spreaderId,
    required this.listenerId,
    required this.content,
    required this.hopCount,
    required this.truthfulnessAtHop,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'spreaderId': spreaderId,
        'listenerId': listenerId,
        'content': content,
        'hopCount': hopCount,
        'truthfulnessAtHop': truthfulnessAtHop,
        'timestamp': timestamp.toIso8601String(),
      };
}

// ─────────────────────────────────────────────
// 流言传播引擎
// ─────────────────────────────────────────────

/// 流言传播引擎
///
/// 模拟流言在角色社交网络中的传播过程：
///   1. 判断某个角色是否会传播流言
///   2. 流言传播过程中内容失真
///   3. 被传谣者产生情绪影响
///   4. 传播结果写入社交记忆
class RumorEngine {
  final MemoryEngine _memoryEngine;
  final Random _random = Random();

  // ── 传播失真模板 ──
  // 每一跳，内容会被这些模板之一变形
  static const List<String> _distortionTemplates = [
    '听说%s',
    '据说是%s',
    '好像%s的样子',
    '有人说%s',
    '我也不确定，但好像是%s',
    '大家都在传%s',
    '别告诉别人，%s',
    '我不信，但有人说%s',
  ];

  // ── 情绪影响关键词 ──
  static const List<String> _negativeEmotionKeywords = [
    '冲突', '争吵', '吵架', '打架', '闹翻',
    '背叛', '欺骗', '出卖', '说坏话', '不满',
    '讨厌', '恨', '愤怒', '委屈', '失望',
    '嫉妒', '竞争', '批评', '指责', '嘲笑',
  ];

  RumorEngine(this._memoryEngine);

  /// 传播流言：A知道了B和C的冲突，可能告诉D
  ///
  /// 返回所有传播记录（谁告诉了谁什么版本）
  Future<List<RumorSpread>> spread({
    required RumorEvent rumor,
    required List<LifeProfile> allProfiles,
    required List<AIRelationship> relationships,
  }) async {
    final spreads = <RumorSpread>[];
    final profileMap = {for (final p in allProfiles) p.id: p};

    // 找到流言源头角色
    final sourceProfile = profileMap[rumor.sourceId];
    if (sourceProfile == null) return spreads;

    // 收集所有可能的听众（非当事人）
    final listeners = allProfiles
        .where((p) =>
            p.id != rumor.sourceId &&
            !rumor.subjectIds.contains(p.id))
        .toList();

    if (listeners.isEmpty) return spreads;

    // 源头传播第一跳
    for (final listener in listeners) {
      if (!_willSpread(sourceProfile, rumor, relationships)) continue;

      final distortedContent = _distortMessage(rumor.content, 1);
      final truthfulness = _decayTruthfulness(rumor.truthfulness, 1);

      final spread = RumorSpread(
        spreaderId: rumor.sourceId,
        listenerId: listener.id,
        content: distortedContent,
        hopCount: 1,
        truthfulnessAtHop: truthfulness,
        timestamp: DateTime.now(),
      );
      spreads.add(spread);

      // 写入社交记忆：传播者的记忆
      await _memoryEngine.saveSocialMemory(
        characterId: rumor.sourceId,
        targetCharacterId: listener.id,
        interactionType: 'rumor_spread',
        content: '告诉了${listener.name}关于${rumor.subjectIds.join("和")}的事',
        emotionTag: 'gossip',
        importance: 'normal',
        keywords: ['流言', '传播', ...rumor.subjectIds],
      );

      // 写入社交记忆：听众的记忆
      await _memoryEngine.saveSocialMemory(
        characterId: listener.id,
        targetCharacterId: rumor.sourceId,
        interactionType: 'rumor_received',
        content: '从${sourceProfile.name}那里听说了$distortedContent',
        emotionTag: 'curious',
        importance: 'normal',
        keywords: ['流言', '听说', ...rumor.subjectIds],
      );

      // 对被谈论者产生影响
      for (final subjectId in rumor.subjectIds) {
        final subject = profileMap[subjectId];
        if (subject != null) {
          await _applyRumorEffect(
            rumor: rumor,
            subject: subject,
            heardFrom: sourceProfile,
          );
        }
      }
    }

    // 后续跳：听众可能继续传播（衰减概率）
    if (spreads.isNotEmpty) {
      await _spreadFurther(
        spreads: spreads,
        rumor: rumor,
        allProfiles: allProfiles,
        profileMap: profileMap,
        relationships: relationships,
        currentHop: 1,
        maxHops: 3,
      );
    }

    return spreads;
  }

  /// 递归传播后续跳
  Future<void> _spreadFurther({
    required List<RumorSpread> spreads,
    required RumorEvent rumor,
    required List<LifeProfile> allProfiles,
    required Map<String, LifeProfile> profileMap,
    required List<AIRelationship> relationships,
    required int currentHop,
    required int maxHops,
  }) async {
    if (currentHop >= maxHops) return;

    // 当前跳的听众成为下一跳的潜在传播者
    final currentListeners = spreads
        .where((s) => s.hopCount == currentHop)
        .map((s) => s.listenerId)
        .toSet();

    // 已经听过流言的人不再重复传播
    final alreadyHeard = spreads.map((s) => s.listenerId).toSet();

    for (final listenerId in currentListeners) {
      final listenerProfile = profileMap[listenerId];
      if (listenerProfile == null) continue;

      // 构造一个衰减后的流言事件用于判断
      final decayedRumor = RumorEvent(
        id: rumor.id,
        sourceId: listenerId,
        subjectIds: rumor.subjectIds,
        content: spreads
            .firstWhere((s) =>
                s.listenerId == listenerId && s.hopCount == currentHop)
            .content,
        truthfulness:
            _decayTruthfulness(rumor.truthfulness, currentHop + 1),
        createdAt: DateTime.now(),
      );

      // 找到还没听过流言的潜在听众
      final potentialListeners = allProfiles
          .where((p) =>
              p.id != listenerId &&
              !rumor.subjectIds.contains(p.id) &&
              !alreadyHeard.contains(p.id))
          .toList();

      for (final nextListener in potentialListeners) {
        // 传播概率随跳数衰减
        final spreadChance = _willSpreadChance(
                listenerProfile, decayedRumor, relationships) /
            (currentHop + 1);
        if (_random.nextDouble() > spreadChance) continue;

        final nextHop = currentHop + 1;
        final distortedContent =
            _distortMessage(decayedRumor.content, nextHop);
        final truthfulness =
            _decayTruthfulness(decayedRumor.truthfulness, nextHop);

        final spread = RumorSpread(
          spreaderId: listenerId,
          listenerId: nextListener.id,
          content: distortedContent,
          hopCount: nextHop,
          truthfulnessAtHop: truthfulness,
          timestamp: DateTime.now(),
        );
        spreads.add(spread);
        alreadyHeard.add(nextListener.id);

        // 写入社交记忆
        await _memoryEngine.saveSocialMemory(
          characterId: listenerId,
          targetCharacterId: nextListener.id,
          interactionType: 'rumor_spread',
          content:
              '告诉了${nextListener.name}关于${rumor.subjectIds.join("和")}的事',
          emotionTag: 'gossip',
          importance: 'normal',
          keywords: ['流言', '传播', ...rumor.subjectIds],
        );

        await _memoryEngine.saveSocialMemory(
          characterId: nextListener.id,
          targetCharacterId: listenerId,
          interactionType: 'rumor_received',
          content: '从${listenerProfile.name}那里听说了$distortedContent',
          emotionTag: 'curious',
          importance: 'normal',
          keywords: ['流言', '听说', ...rumor.subjectIds],
        );
      }
    }

    // 继续下一跳
    await _spreadFurther(
      spreads: spreads,
      rumor: rumor,
      allProfiles: allProfiles,
      profileMap: profileMap,
      relationships: relationships,
      currentHop: currentHop + 1,
      maxHops: maxHops,
    );
  }

  /// 判断某个角色是否会传播流言
  ///
  /// 基于：
  /// - 外向性（越高越爱传）
  /// - 宜人性（越低越爱传负面流言）
  /// - 与当事人的关系（越远越敢传）
  bool _willSpread(
    LifeProfile spreader,
    RumorEvent rumor,
    List<AIRelationship> relationships,
  ) {
    final chance = _willSpreadChance(spreader, rumor, relationships);
    return _random.nextDouble() < chance;
  }

  /// 计算传播概率（0.0 ~ 1.0）
  double _willSpreadChance(
    LifeProfile spreader,
    RumorEvent rumor,
    List<AIRelationship> relationships,
  ) {
    // 从人格状态中提取外向性和宜人性
    final personalityState = spreader.personalityState;
    final extraversion =
        (personalityState['extraversion'] as num?)?.toDouble() ?? 0.5;
    final agreeableness =
        (personalityState['agreeableness'] as num?)?.toDouble() ?? 0.5;

    // 基础传播概率：外向性贡献
    double chance = 0.0;

    // 外向性 > 0.6 更爱传播
    if (extraversion > 0.6) {
      chance += 0.3 + (extraversion - 0.6) * 0.5; // 最高 0.5
    } else {
      chance += extraversion * 0.3; // 最高 0.18
    }

    // 宜人性 < 0.4 更爱传播负面流言
    final isNegativeRumor = _isNegativeContent(rumor.content);
    if (isNegativeRumor && agreeableness < 0.4) {
      chance += (0.4 - agreeableness) * 0.5; // 最高 0.2
    } else if (!isNegativeRumor) {
      // 正面流言（八卦但不恶意），宜人性影响较小
      chance += 0.1;
    }

    // 与当事人关系越远，越敢传播
    final closeness = _calculateCloseness(
        spreader.id, rumor.subjectIds, relationships);
    // closeness 0（陌生人）= 最敢传，closeness 1（亲密）= 不太敢传
    chance += (1.0 - closeness) * 0.3; // 最高 0.3

    return chance.clamp(0.0, 1.0);
  }

  /// 流言对被谈论者的影响
  ///
  /// 被传谣者产生愤怒、委屈等情绪，写入社交记忆
  Future<void> _applyRumorEffect({
    required RumorEvent rumor,
    required LifeProfile subject,
    required LifeProfile heardFrom,
  }) async {
    // 判断流言内容的负面程度
    final negativity = _calculateNegativity(rumor.content);

    // 情绪影响程度取决于：负面程度 × (1 - 真实度)
    // 越假的负面流言越让人愤怒
    final impact = negativity * (1.0 - rumor.truthfulness * 0.5);

    String emotionTag;
    String emotionDesc;

    if (impact > 0.7) {
      emotionTag = 'angry';
      emotionDesc = '愤怒';
    } else if (impact > 0.5) {
      emotionTag = 'wronged';
      emotionDesc = '委屈';
    } else if (impact > 0.3) {
      emotionTag = 'uncomfortable';
      emotionDesc = '不舒服';
    } else {
      emotionTag = 'indifferent';
      emotionDesc = '无所谓';
    }

    // 写入被谈论者的社交记忆
    await _memoryEngine.saveSocialMemory(
      characterId: subject.id,
      targetCharacterId: heardFrom.id,
      interactionType: 'rumor_awareness',
      content: '得知有人在背后谈论自己，感到$emotionDesc',
      emotionTag: emotionTag,
      importance: impact > 0.5 ? 'important' : 'normal',
      keywords: ['流言', '被谈论', emotionTag],
    );

    // 如果影响足够大，可能影响关系
    if (impact > 0.6) {
      debugPrint(
          'RumorEngine: ${subject.name} 因流言对传播者产生负面情绪 ($emotionTag)');
    }
  }

  /// 流言失真 — 传播过程中信息变形
  ///
  /// 每传播一跳，真实度衰减 10-30%，内容被模板包裹或细节模糊化
  String _distortMessage(String original, int hops) {
    if (hops <= 0) return original;

    String distorted = original;

    // 每一跳应用一次失真
    for (int i = 0; i < hops; i++) {
      // 1. 用失真模板包裹
      final template =
          _distortionTemplates[_random.nextInt(_distortionTemplates.length)];
      distorted = template.replaceAll('%s', distorted);

      // 2. 随机模糊细节
      distorted = _fuzzyDetails(distorted);

      // 3. 限制长度（信息越传越精简）
      if (distorted.length > 100) {
        distorted = distorted.substring(0, 100);
      }
    }

    return distorted;
  }

  /// 真实度衰减：每跳衰减 10-30%
  double _decayTruthfulness(double original, int hops) {
    double result = original;
    for (int i = 0; i < hops; i++) {
      final decay = 0.1 + _random.nextDouble() * 0.2; // 10%-30%
      result = result * (1.0 - decay);
    }
    return result.clamp(0.0, 1.0);
  }

  /// 模糊化细节
  String _fuzzyDetails(String content) {
    // 替换具体数字为模糊表达
    content = content.replaceAllMapped(
      RegExp(r'\d+'),
      (m) {
        final n = int.tryParse(m.group(0)!) ?? 0;
        if (n <= 2) return '一两个';
        if (n <= 5) return '几个';
        if (n <= 10) return '好几个';
        return '很多';
      },
    );

    // 随机添加不确定性词汇
    if (_random.nextDouble() < 0.3) {
      const uncertain = ['大概', '好像', '似乎', '可能', '据说'];
      final word = uncertain[_random.nextInt(uncertain.length)];
      content = '$word$content';
    }

    return content;
  }

  /// 判断内容是否负面
  bool _isNegativeContent(String content) {
    final lower = content.toLowerCase();
    return _negativeEmotionKeywords.any((kw) => lower.contains(kw));
  }

  /// 计算内容的负面程度 (0.0 ~ 1.0)
  double _calculateNegativity(String content) {
    final lower = content.toLowerCase();
    int matchCount = 0;
    for (final kw in _negativeEmotionKeywords) {
      if (lower.contains(kw)) matchCount++;
    }
    return (matchCount / 3).clamp(0.0, 1.0);
  }

  /// 计算传播者与当事人之间的关系亲密度 (0.0 ~ 1.0)
  ///
  /// 0 = 陌生人（最敢传），1 = 亲密（不太敢传）
  double _calculateCloseness(
    String spreaderId,
    List<String> subjectIds,
    List<AIRelationship> relationships,
  ) {
    double maxCloseness = 0.0;

    for (final subjectId in subjectIds) {
      for (final rel in relationships) {
        final isPair = (rel.characterIdA == spreaderId &&
                rel.characterIdB == subjectId) ||
            (rel.characterIdB == spreaderId &&
                rel.characterIdA == subjectId);

        if (!isPair) continue;

        // 亲密度由关系类型和亲和度共同决定
        double typeMultiplier = 1.0;
        switch (rel.relationshipType) {
          case RelationshipType.lover:
            typeMultiplier = 1.5;
            break;
          case RelationshipType.friend:
          case RelationshipType.bestFriend:
            typeMultiplier = 1.2;
            break;
          case RelationshipType.sibling:
            typeMultiplier = 1.3;
            break;
          case RelationshipType.mentor:
            typeMultiplier = 1.1;
            break;
          case RelationshipType.enemy:
            typeMultiplier = 0.3; // 敌人反而更敢传
            break;
          case RelationshipType.rival:
            typeMultiplier = 0.5;
            break;
          default:
            typeMultiplier = 0.8;
        }

        final closeness =
            (rel.affinity * typeMultiplier).clamp(0.0, 1.0);
        if (closeness > maxCloseness) {
          maxCloseness = closeness;
        }
      }
    }

    return maxCloseness;
  }
}
