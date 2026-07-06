// ============================================================
// 全生命周期数字生命世界 — Phase 5
// 群体事件引擎：驱动聚会、运动、合作、旅行、危机等群体活动
// ============================================================

import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/life_profile.dart';
import 'ai_relationship_service.dart';
import 'memory_engine.dart';
import 'llm_service.dart';

// ── 群体事件类型 ──
enum GroupActivityType {
  party, // 聚会
  sports, // 运动/竞技
  project, // 合作项目
  travel, // 旅行
  crisis, // 危机
}

extension GroupActivityTypeX on GroupActivityType {
  String get label {
    switch (this) {
      case GroupActivityType.party:
        return '聚会';
      case GroupActivityType.sports:
        return '运动';
      case GroupActivityType.project:
        return '合作项目';
      case GroupActivityType.travel:
        return '旅行';
      case GroupActivityType.crisis:
        return '危机';
    }
  }

  /// 随机意外概率
  double get accidentProbability {
    switch (this) {
      case GroupActivityType.party:
        return 0.10;
      case GroupActivityType.sports:
        return 0.15;
      case GroupActivityType.project:
        return 0.12;
      case GroupActivityType.travel:
        return 0.18;
      case GroupActivityType.crisis:
        return 0.20;
    }
  }

  /// 基础亲密度变化
  double get baseAffinityDelta {
    switch (this) {
      case GroupActivityType.party:
        return 0.05;
      case GroupActivityType.sports:
        return 0.03;
      case GroupActivityType.project:
        return 0.04;
      case GroupActivityType.travel:
        return 0.06;
      case GroupActivityType.crisis:
        return 0.02; // 危机结果不确定，基础值低
    }
  }

  /// 基础归属感变化
  double get baseBelongingDelta {
    switch (this) {
      case GroupActivityType.party:
        return 0.08;
      case GroupActivityType.sports:
        return 0.05;
      case GroupActivityType.project:
        return 0.07;
      case GroupActivityType.travel:
        return 0.10;
      case GroupActivityType.crisis:
        return 0.03;
    }
  }
}

// ── 意外类型 ──
enum AccidentType {
  argument, // 争吵
  romance, // 暧昧/恋情
  revelation, // 秘密曝光
  injury, // 受伤/意外
}

extension AccidentTypeX on AccidentType {
  String get label {
    switch (this) {
      case AccidentType.argument:
        return '争吵';
      case AccidentType.romance:
        return '暧昧';
      case AccidentType.revelation:
        return '秘密曝光';
      case AccidentType.injury:
        return '意外受伤';
    }
  }
}

/// 群体事件中的意外
class GroupAccident {
  final String type; // 'argument', 'romance', 'revelation', 'injury'
  final String description;
  final List<String> involvedIds;
  final Map<String, double> impact; // characterId → 影响值（正值好，负值坏）

  const GroupAccident({
    required this.type,
    required this.description,
    required this.involvedIds,
    required this.impact,
  });

  Map<String, dynamic> toJson() => {
        'type': type,
        'description': description,
        'involvedIds': involvedIds,
        'impact': impact,
      };

  factory GroupAccident.fromJson(Map<String, dynamic> json) {
    return GroupAccident(
      type: json['type'] as String? ?? 'argument',
      description: json['description'] as String? ?? '',
      involvedIds: (json['involvedIds'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      impact: (json['impact'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, (v as num).toDouble())) ??
          {},
    );
  }
}

/// 群体事件
class GroupEvent {
  final String id;
  final String type; // 'party', 'sports', 'project', 'travel', 'crisis'
  final List<String> participantIds;
  final String description;
  final DateTime timestamp;
  final Map<String, dynamic> effects;
  final GroupAccident? accident;

  const GroupEvent({
    required this.id,
    required this.type,
    required this.participantIds,
    required this.description,
    required this.timestamp,
    this.effects = const {},
    this.accident,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'participantIds': participantIds,
        'description': description,
        'timestamp': timestamp.toIso8601String(),
        'effects': effects,
        'accident': accident?.toJson(),
      };

  factory GroupEvent.fromJson(Map<String, dynamic> json) {
    return GroupEvent(
      id: json['id'] as String? ?? '',
      type: json['type'] as String? ?? 'party',
      participantIds: (json['participantIds'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      description: json['description'] as String? ?? '',
      timestamp:
          DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
      effects: (json['effects'] as Map<String, dynamic>?) ?? {},
      accident: json['accident'] != null
          ? GroupAccident.fromJson(json['accident'] as Map<String, dynamic>)
          : null,
    );
  }
}

/// 群体事件引擎
///
/// 职责：
/// - 触发各类群体活动（聚会、运动、合作项目、旅行、危机）
/// - 计算群体事件对参与者的影响（亲密度、归属感、冲突）
/// - 生成群体事件描述（LLM 优先，fallback 模板）
/// - 随机触发群体意外事件
class GroupEventEngine {
  final AIRelationshipService _relationshipService;
  final MemoryEngine _memoryEngine;
  final LlmService _llmService;
  final Random _random = Random();
  final _uuid = const Uuid();

  GroupEventEngine(this._relationshipService, this._memoryEngine, this._llmService);

  /// 触发群体活动
  ///
  /// 根据 [activityType] 创建群体事件，生成描述，并返回事件对象。
  /// 后续需调用 [applyGroupEffects] 将影响写入系统。
  Future<GroupEvent> triggerActivity({
    required List<LifeProfile> participants,
    required String activityType,
    required String context,
  }) async {
    final type = _parseActivityType(activityType);
    final eventId = _uuid.v4();

    // 生成描述
    final description = await generateDescription(
      participants: participants,
      activityType: type,
      context: context,
    );

    // 掷骰子决定是否有意外
    final accident = _rollAccident(type, participants);

    final event = GroupEvent(
      id: eventId,
      type: type.name,
      participantIds: participants.map((p) => p.id).toList(),
      description: description,
      timestamp: DateTime.now(),
      effects: _calculateBaseEffects(type, participants),
      accident: accident,
    );

    debugPrint('GroupEventEngine: 触发${type.label}事件 '
        '(${participants.length}人参与, 意外: ${accident != null ? accident.type : "无"})');

    return event;
  }

  /// 群体事件对参与者的影响
  ///
  /// 将亲密度变化、归属感变化、意外影响写入关系图谱和社交记忆。
  Future<void> applyGroupEffects({
    required GroupEvent event,
    required List<LifeProfile> participants,
    required List<AIRelationship> relationships,
  }) async {
    final type = _parseActivityType(event.type);

    // 1. 两两之间亲密度变化
    for (int i = 0; i < participants.length; i++) {
      for (int j = i + 1; j < participants.length; j++) {
        final pA = participants[i];
        final pB = participants[j];

        var affinityDelta = type.baseAffinityDelta;

        // 根据性格调整
        affinityDelta *= _personalityAffinityMultiplier(pA, pB, type);

        // 意外影响
        if (event.accident != null) {
          final accident = event.accident!;
          final aInvolved = accident.involvedIds.contains(pA.id);
          final bInvolved = accident.involvedIds.contains(pB.id);

          if (aInvolved && bInvolved) {
            // 双方都在意外中
            final impactA = accident.impact[pA.id] ?? 0.0;
            final impactB = accident.impact[pB.id] ?? 0.0;
            affinityDelta += (impactA + impactB) / 2;
          }

          // 争吵类意外降低亲密度
          if (accident.type == 'argument' && (aInvolved || bInvolved)) {
            affinityDelta -= 0.05;
          }
        }

        // 写入关系
        await _applyAffinityChange(pA.id, pB.id, affinityDelta);
      }
    }

    // 2. 为每位参与者写入社交记忆
    for (final participant in participants) {
      final belongingDelta = type.baseBelongingDelta;
      final memoryContent = _buildEventMemory(event, participant);

      try {
        await _memoryEngine.saveSocialMemory(
          characterId: participant.id,
          targetCharacterId: participant.id,
          interactionType: 'group_event',
          content: memoryContent,
          importance: event.accident != null ? 'important' : 'normal',
          keywords: [type.label, '群体活动', ..._eventKeywords(event)],
        );
      } catch (e) {
        debugPrint('GroupEventEngine: 保存记忆失败 (${participant.name}): $e');
      }
    }

    // 3. 意外涉及者的额外记忆
    if (event.accident != null) {
      for (final involvedId in event.accident!.involvedIds) {
        try {
          await _memoryEngine.saveSocialMemory(
            characterId: involvedId,
            targetCharacterId: involvedId,
            interactionType: 'group_accident',
            content: '在${type.label}中发生了${event.accident!.type}：'
                '${event.accident!.description}',
            importance: 'important',
            keywords: ['意外', event.accident!.type, type.label],
          );
        } catch (e) {
          debugPrint('GroupEventEngine: 保存意外记忆失败: $e');
        }
      }
    }

    debugPrint('GroupEventEngine: 群体效果已应用 — '
        '${participants.length}人参与, '
        '${event.accident != null ? "有意外" : "无意外"}');
  }

  /// 生成群体事件描述
  ///
  /// 优先使用 LLM 生成个性化描述，失败时使用模板 fallback。
  Future<String> generateDescription({
    required List<LifeProfile> participants,
    required GroupActivityType activityType,
    String context = '',
  }) async {
    // 尝试 LLM 生成
    try {
      final prompt = _buildDescriptionPrompt(participants, activityType, context);
      final response = await _llmService.chat(
        userId: 'system',
        message: prompt,
        role: 'user',
      );
      if (response.content.isNotEmpty) {
        return response.content;
      }
    } catch (e) {
      debugPrint('GroupEventEngine: LLM 生成描述失败，使用 fallback: $e');
    }

    // Fallback: 模板生成
    return _fallbackDescription(participants, activityType, context);
  }

  // ── 私有辅助方法 ──

  /// 解析活动类型
  GroupActivityType _parseActivityType(String type) {
    switch (type.toLowerCase()) {
      case 'party':
        return GroupActivityType.party;
      case 'sports':
        return GroupActivityType.sports;
      case 'project':
        return GroupActivityType.project;
      case 'travel':
        return GroupActivityType.travel;
      case 'crisis':
        return GroupActivityType.crisis;
      default:
        return GroupActivityType.party;
    }
  }

  /// 计算基础效果
  Map<String, dynamic> _calculateBaseEffects(
    GroupActivityType type,
    List<LifeProfile> participants,
  ) {
    return {
      'activityType': type.name,
      'participantCount': participants.length,
      'baseAffinityDelta': type.baseAffinityDelta,
      'baseBelongingDelta': type.baseBelongingDelta,
      'timestamp': DateTime.now().toIso8601String(),
    };
  }

  /// 性格对亲密度变化的调节系数
  double _personalityAffinityMultiplier(
    LifeProfile pA,
    LifeProfile pB,
    GroupActivityType type,
  ) {
    final extA = (pA.personalityState['extraversion'] as num?)?.toDouble() ?? 0.5;
    final extB = (pB.personalityState['extraversion'] as num?)?.toDouble() ?? 0.5;
    final agrA = (pA.personalityState['agreeableness'] as num?)?.toDouble() ?? 0.5;
    final agrB = (pB.personalityState['agreeableness'] as num?)?.toDouble() ?? 0.5;

    final avgExt = (extA + extB) / 2;
    final avgAgr = (agrA + agrB) / 2;

    switch (type) {
      case GroupActivityType.party:
        // 外向者在聚会中更投入
        return 0.8 + avgExt * 0.6;
      case GroupActivityType.sports:
        // 运动中外向者更活跃，但竞争性可能降低宜人性低者的亲密度
        return 0.7 + avgExt * 0.4 + avgAgr * 0.2;
      case GroupActivityType.project:
        // 合作项目中尽责性更重要（这里用宜人性近似）
        return 0.8 + avgAgr * 0.5;
      case GroupActivityType.travel:
        // 旅行中开放性和外向性都有帮助
        final avgOpen = (((pA.personalityState['openness'] as num?)?.toDouble() ?? 0.5) +
                ((pB.personalityState['openness'] as num?)?.toDouble() ?? 0.5)) /
            2;
        return 0.7 + avgExt * 0.3 + avgOpen * 0.3;
      case GroupActivityType.crisis:
        // 危机中勇气和同理心更重要
        final courageA = (pA.personalityState['courage'] as num?)?.toDouble() ?? 0.5;
        final courageB = (pB.personalityState['courage'] as num?)?.toDouble() ?? 0.5;
        return 0.6 + ((courageA + courageB) / 2) * 0.5 + avgAgr * 0.3;
    }
  }

  /// 掷骰子决定意外
  GroupAccident? _rollAccident(GroupActivityType type, List<LifeProfile> participants) {
    if (participants.length < 2) return null;

    if (_random.nextDouble() > type.accidentProbability) return null;

    // 选择意外类型
    final accidentType = _pickAccidentType(type);
    // 随机选取 2-3 个涉及者
    final involvedCount = min(participants.length, 2 + _random.nextInt(2));
    final shuffled = List.of(participants)..shuffle(_random);
    final involved = shuffled.take(involvedCount).toList();

    return _generateAccident(accidentType, involved, type);
  }

  /// 根据活动类型选择可能的意外类型
  AccidentType _pickAccidentType(GroupActivityType activityType) {
    switch (activityType) {
      case GroupActivityType.party:
        return _random.nextBool() ? AccidentType.argument : AccidentType.romance;
      case GroupActivityType.sports:
        return _random.nextBool() ? AccidentType.injury : AccidentType.argument;
      case GroupActivityType.project:
        return _random.nextBool() ? AccidentType.argument : AccidentType.revelation;
      case GroupActivityType.travel:
        final roll = _random.nextDouble();
        if (roll < 0.3) return AccidentType.romance;
        if (roll < 0.6) return AccidentType.argument;
        return AccidentType.revelation;
      case GroupActivityType.crisis:
        final roll = _random.nextDouble();
        if (roll < 0.4) return AccidentType.argument;
        if (roll < 0.7) return AccidentType.revelation;
        return AccidentType.injury;
    }
  }

  /// 生成具体意外
  GroupAccident _generateAccident(
    AccidentType type,
    List<LifeProfile> involved,
    GroupActivityType activityType,
  ) {
    final names = involved.map((p) => p.name).join('和');
    String description;
    Map<String, double> impact;

    switch (type) {
      case AccidentType.argument:
        description = _randomArgumentTemplate(names, activityType);
        impact = {
          for (final p in involved) p.id: -(0.05 + _random.nextDouble() * 0.10),
        };
        break;
      case AccidentType.romance:
        description = _randomRomanceTemplate(names, activityType);
        impact = {
          for (final p in involved) p.id: 0.05 + _random.nextDouble() * 0.10,
        };
        break;
      case AccidentType.revelation:
        description = _randomRevelationTemplate(names, activityType);
        impact = {
          for (int i = 0; i < involved.length; i++)
            involved[i].id: i == 0
                ? -(0.08 + _random.nextDouble() * 0.07)
                : 0.02 + _random.nextDouble() * 0.05,
        };
        break;
      case AccidentType.injury:
        description = _randomInjuryTemplate(names, activityType);
        impact = {
          for (final p in involved) p.id: -(0.03 + _random.nextDouble() * 0.05),
        };
        break;
    }

    return GroupAccident(
      type: type.name,
      description: description,
      involvedIds: involved.map((p) => p.id).toList(),
      impact: impact,
    );
  }

  /// 写入亲密度变化
  Future<void> _applyAffinityChange(
    String idA,
    String idB,
    double delta,
  ) async {
    try {
      final rel = await _relationshipService.getRelationship(idA, idB);
      if (rel != null) {
        final newAffinity = (rel.affinity + delta).clamp(0.0, 1.0);
        await _relationshipService.updateRelationship(
          rel.copyWith(affinity: newAffinity),
        );
      } else {
        // 无关系则创建（陌生人默认 0.5）
        await _relationshipService.createRelationship(
          characterIdA: idA,
          characterIdB: idB,
          type: RelationshipType.stranger,
          affinity: (0.5 + delta).clamp(0.0, 1.0),
          description: '通过群体活动建立的联系',
        );
      }
    } catch (e) {
      debugPrint('GroupEventEngine: 更新亲密度失败 $idA↔$idB: $e');
    }
  }

  /// 构建事件记忆文本
  String _buildEventMemory(GroupEvent event, LifeProfile participant) {
    final type = _parseActivityType(event.type);
    final buffer = StringBuffer();
    buffer.write('参加了${type.label}活动');
    if (event.accident != null) {
      buffer.write('，期间发生了${event.accident!.type}');
    }
    return buffer.toString();
  }

  /// 提取事件关键词
  List<String> _eventKeywords(GroupEvent event) {
    final keywords = <String>[event.type];
    if (event.accident != null) {
      keywords.add(event.accident!.type);
    }
    return keywords;
  }

  /// 构建 LLM 描述生成 prompt
  String _buildDescriptionPrompt(
    List<LifeProfile> participants,
    GroupActivityType type,
    String context,
  ) {
    final names = participants.map((p) => p.name).join('、');
    return '''请用2-3句话描述以下群体活动场景：
活动类型：${type.label}
参与者：$names
${context.isNotEmpty ? '背景：$context' : ''}
要求：生动自然，体现角色间互动。只输出描述，不要有其他文字。''';
  }

  /// Fallback 描述模板
  String _fallbackDescription(
    List<LifeProfile> participants,
    GroupActivityType type,
    String context,
  ) {
    final names = participants.map((p) => p.name).join('、');
    final count = participants.length;

    switch (type) {
      case GroupActivityType.party:
        return '$names 一起参加了一场聚会，大家在一起度过了愉快的时光。';
      case GroupActivityType.sports:
        return '$names 一起进行了一场运动竞技，气氛热烈而紧张。';
      case GroupActivityType.project:
        return '$names 合作完成了一个项目，团队配合默契。';
      case GroupActivityType.travel:
        return '$names 一起踏上了旅途，沿途留下了许多美好回忆。';
      case GroupActivityType.crisis:
        return '$names 共同面对了一场危机，考验着彼此的友谊。';
    }
  }

  // ── 意外描述模板 ──

  String _randomArgumentTemplate(String names, GroupActivityType activity) {
    final templates = [
      '$names 因意见不合发生了激烈争吵',
      '$names 在活动中产生了分歧，争执不下',
      '$names 因为一件小事起了冲突',
    ];
    return templates[_random.nextInt(templates.length)];
  }

  String _randomRomanceTemplate(String names, GroupActivityType activity) {
    final templates = [
      '$names 在活动中产生了微妙的暧昧气氛',
      '$names 之间擦出了意想不到的火花',
      '$names 在轻松的氛围中互相产生了好感',
    ];
    return templates[_random.nextInt(templates.length)];
  }

  String _randomRevelationTemplate(String names, GroupActivityType activity) {
    final templates = [
      '$names 无意间发现了一个被隐藏的秘密',
      '$names 在活动中意外曝光了一段不愿提及的往事',
      '$names 的一个隐私在众人面前被揭开',
    ];
    return templates[_random.nextInt(templates.length)];
  }

  String _randomInjuryTemplate(String names, GroupActivityType activity) {
    final templates = [
      '$names 在活动中不慎受伤',
      '$names 意外发生了小事故，所幸并无大碍',
      '$names 在运动中扭伤了脚，需要休息',
    ];
    return templates[_random.nextInt(templates.length)];
  }

}
