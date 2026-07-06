// ============================================================
// 全生命周期数字生命世界 — Phase 2
// 身份认同系统：自我叙事 + 身份标签 + 演化历史
// ============================================================

import 'dart:convert';
import 'package:equatable/equatable.dart';
import 'life_event.dart';
import 'personality_state.dart';

/// 身份快照 — 某一时刻的自我认知记录
class IdentitySnapshot extends Equatable {
  final DateTime timestamp;
  final String selfDescription;
  final String triggerEvent; // 触发变化的事件

  const IdentitySnapshot({
    required this.timestamp,
    required this.selfDescription,
    required this.triggerEvent,
  });

  IdentitySnapshot copyWith({
    DateTime? timestamp,
    String? selfDescription,
    String? triggerEvent,
  }) {
    return IdentitySnapshot(
      timestamp: timestamp ?? this.timestamp,
      selfDescription: selfDescription ?? this.selfDescription,
      triggerEvent: triggerEvent ?? this.triggerEvent,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'selfDescription': selfDescription,
      'triggerEvent': triggerEvent,
    };
  }

  factory IdentitySnapshot.fromJson(Map<String, dynamic> json) {
    return IdentitySnapshot(
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
      selfDescription: json['selfDescription'] as String? ?? '',
      triggerEvent: json['triggerEvent'] as String? ?? '',
    );
  }

  @override
  List<Object?> get props => [timestamp, selfDescription, triggerEvent];
}

/// 身份认同系统 — 个体如何理解自己、定义自己
class IdentityNarrative extends Equatable {
  // ── 自我认知 ──
  final String selfDescription; // "我是一个被抛弃过的人，但我选择相信爱"
  final String coreMotivation; // "我想要被真正理解"
  final String biggestFear; // "再次被背叛"
  final String lifePhilosophy; // "真诚是最大的勇气"

  // ── 身份标签 ──
  final List<String> identityTags; // ["幸存者", "艺术家", "局外人"]

  // ── 内在矛盾 ──
  final List<String> innerConflicts; // ["想被爱又怕受伤"]

  // ── 演化历史 ──
  final List<IdentitySnapshot> history;

  // ── 临终遗言（死亡时生成） ──
  final String? finalWords;

  const IdentityNarrative({
    required this.selfDescription,
    required this.coreMotivation,
    required this.biggestFear,
    required this.lifePhilosophy,
    this.identityTags = const [],
    this.innerConflicts = const [],
    this.history = const [],
    this.finalWords,
  });

  /// 婴儿空白身份 — 尚未形成自我认知
  factory IdentityNarrative.blank() {
    return const IdentityNarrative(
      selfDescription: '',
      coreMotivation: '',
      biggestFear: '',
      lifePhilosophy: '',
      identityTags: [],
      innerConflicts: [],
      history: [],
    );
  }

  /// 重大事件后重建自我叙事
  IdentityNarrative rebuild(LifeEvent event, PersonalityState personality) {
    if (!event.affects(EventDimension.identity)) return this;

    // 基于事件和当前人格状态，生成新的自我叙事
    final newSelfDescription = _generateSelfDescription(event, personality);
    final newCoreMotivation = _generateCoreMotivation(personality);
    final newBiggestFear = _generateBiggestFear(event, personality);
    final newLifePhilosophy = _generateLifePhilosophy(personality);

    // 更新身份标签
    final newTags = List<String>.from(identityTags);
    _updateIdentityTags(event, personality, newTags);

    // 更新内在矛盾
    final newConflicts = List<String>.from(innerConflicts);
    _updateInnerConflicts(personality, newConflicts);

    // 记录快照
    final snapshot = IdentitySnapshot(
      timestamp: event.timestamp,
      selfDescription: newSelfDescription,
      triggerEvent: event.description,
    );

    return IdentityNarrative(
      selfDescription: newSelfDescription,
      coreMotivation: newCoreMotivation,
      biggestFear: newBiggestFear,
      lifePhilosophy: newLifePhilosophy,
      identityTags: newTags,
      innerConflicts: newConflicts,
      history: [...history, snapshot],
      finalWords: finalWords,
    );
  }

  /// 基于事件和人格生成自我描述
  String _generateSelfDescription(LifeEvent event, PersonalityState p) {
    final buffer = StringBuffer();

    if (event.category == '创伤' &&
        event.severity.index >= EventSeverity.major.index) {
      buffer.write('我是一个经历过"${event.description}"的人');
      if (p.courage > 0.6) {
        buffer.write('，但我选择坚强面对');
      } else if (p.empathy > 0.6) {
        buffer.write('，这让我更懂得珍惜');
      }
    } else if (event.category == '成就') {
      buffer.write('我是一个${event.description}的人');
      if (p.ambition > 0.6) {
        buffer.write('，我还要走得更远');
      }
    } else {
      // 通用描述
      if (p.extraversion > 0.6) {
        buffer.write('我是一个热爱生活、喜欢与人交往的人');
      } else if (p.openness > 0.6) {
        buffer.write('我是一个内心丰富、喜欢探索的人');
      } else {
        buffer.write('我是一个在不断认识自己的人');
      }
    }

    return buffer.toString();
  }

  /// 基于人格生成核心动机
  String _generateCoreMotivation(PersonalityState p) {
    if (p.empathy > 0.7) return '我想要被真正理解';
    if (p.ambition > 0.7) return '我想证明自己的价值';
    if (p.courage > 0.7) return '我想探索未知的可能';
    if (p.agreeableness > 0.7) return '我想与他人建立真诚的连接';
    if (p.openness > 0.7) return '我想理解这个世界的本质';
    return '我想找到属于自己的路';
  }

  /// 基于事件和人格生成最大恐惧
  String _generateBiggestFear(LifeEvent event, PersonalityState p) {
    if (event.category == '背叛') return '再次被背叛';
    if (event.category == '失去') return '再次失去重要的人';
    if (event.category == '失败') return '永远无法证明自己';
    if (p.neuroticism > 0.7) return '被世界抛弃';
    if (p.agreeableness > 0.7) return '伤害到在乎的人';
    if (p.extraversion < 0.3) return '被迫暴露在聚光灯下';
    return '无法找到生命的意义';
  }

  /// 基于人格生成人生哲学
  String _generateLifePhilosophy(PersonalityState p) {
    if (p.courage > 0.7 && p.openness > 0.6) return '真诚是最大的勇气';
    if (p.empathy > 0.7) return '理解比评判更重要';
    if (p.ambition > 0.7) return '不断超越昨天的自己';
    if (p.creativity > 0.7) return '创造是存在的证明';
    if (p.neuroticism < 0.3) return '一切都会过去';
    return '活着本身就是意义';
  }

  /// 更新身份标签
  void _updateIdentityTags(
    LifeEvent event,
    PersonalityState p,
    List<String> tags,
  ) {
    // 基于事件
    if (event.category == '创伤' && !tags.contains('幸存者')) {
      tags.add('幸存者');
    }
    if (event.category == '成就' && !tags.contains('成就者')) {
      tags.add('成就者');
    }

    // 基于人格
    if (p.creativity > 0.7 && !tags.contains('艺术家')) {
      tags.add('艺术家');
    }
    if (p.extraversion < 0.3 && !tags.contains('局外人')) {
      tags.add('局外人');
    }
    if (p.empathy > 0.7 && !tags.contains('共情者')) {
      tags.add('共情者');
    }
    if (p.openness > 0.7 && !tags.contains('探索者')) {
      tags.add('探索者');
    }
    if (p.courage > 0.7 && !tags.contains('勇者')) {
      tags.add('勇者');
    }

    // 限制标签数量，保留最近的
    while (tags.length > 10) {
      tags.removeAt(0);
    }
  }

  /// 更新内在矛盾
  void _updateInnerConflicts(PersonalityState p, List<String> conflicts) {
    // 基于人格特质的矛盾组合
    if (p.agreeableness > 0.6 && p.neuroticism > 0.6) {
      const conflict = '想被爱又怕受伤';
      if (!conflicts.contains(conflict)) conflicts.add(conflict);
    }
    if (p.openness > 0.6 && p.conscientiousness > 0.6) {
      const conflict = '渴望自由又需要秩序';
      if (!conflicts.contains(conflict)) conflicts.add(conflict);
    }
    if (p.extraversion > 0.6 && p.neuroticism > 0.6) {
      const conflict = '想社交又害怕被评判';
      if (!conflicts.contains(conflict)) conflicts.add(conflict);
    }
    if (p.ambition > 0.7 && p.empathy > 0.7) {
      const conflict = '想成功又不想伤害他人';
      if (!conflicts.contains(conflict)) conflicts.add(conflict);
    }

    // 限制矛盾数量
    while (conflicts.length > 5) {
      conflicts.removeAt(0);
    }
  }

  /// 生成临终遗言
  IdentityNarrative withFinalWords(String words) {
    return copyWith(finalWords: words);
  }

  IdentityNarrative copyWith({
    String? selfDescription,
    String? coreMotivation,
    String? biggestFear,
    String? lifePhilosophy,
    List<String>? identityTags,
    List<String>? innerConflicts,
    List<IdentitySnapshot>? history,
    String? finalWords,
    bool clearFinalWords = false,
  }) {
    return IdentityNarrative(
      selfDescription: selfDescription ?? this.selfDescription,
      coreMotivation: coreMotivation ?? this.coreMotivation,
      biggestFear: biggestFear ?? this.biggestFear,
      lifePhilosophy: lifePhilosophy ?? this.lifePhilosophy,
      identityTags: identityTags ?? this.identityTags,
      innerConflicts: innerConflicts ?? this.innerConflicts,
      history: history ?? this.history,
      finalWords: clearFinalWords ? null : (finalWords ?? this.finalWords),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'selfDescription': selfDescription,
      'coreMotivation': coreMotivation,
      'biggestFear': biggestFear,
      'lifePhilosophy': lifePhilosophy,
      'identityTags': identityTags,
      'innerConflicts': innerConflicts,
      'history': history.map((s) => s.toJson()).toList(),
      'finalWords': finalWords,
    };
  }

  factory IdentityNarrative.fromJson(Map<String, dynamic> json) {
    return IdentityNarrative(
      selfDescription: json['selfDescription'] as String? ?? '',
      coreMotivation: json['coreMotivation'] as String? ?? '',
      biggestFear: json['biggestFear'] as String? ?? '',
      lifePhilosophy: json['lifePhilosophy'] as String? ?? '',
      identityTags: (json['identityTags'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      innerConflicts: (json['innerConflicts'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      history: (json['history'] as List<dynamic>?)
              ?.map((s) => IdentitySnapshot.fromJson(s as Map<String, dynamic>))
              .toList() ??
          [],
      finalWords: json['finalWords'] as String?,
    );
  }

  String toJsonString() => jsonEncode(toJson());

  factory IdentityNarrative.fromJsonString(String source) =>
      IdentityNarrative.fromJson(jsonDecode(source) as Map<String, dynamic>);

  @override
  List<Object?> get props => [
        selfDescription,
        coreMotivation,
        biggestFear,
        lifePhilosophy,
        identityTags,
        innerConflicts,
        history,
        finalWords,
      ];
}
