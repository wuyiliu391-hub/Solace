// ============================================================
// 全生命周期数字生命世界 — Phase 2
// 三观系统：核心价值观光谱 + 世界观标签 + 固化机制
// ============================================================

import 'dart:convert';
import 'package:equatable/equatable.dart';
import 'life_event.dart';

/// 三观系统 — 个体对世界的认知与价值判断
class Worldview extends Equatable {
  // ── 核心价值观（0-1 连续光谱） ──
  final double individualismVsCollectivism; // 0=集体主义, 1=个人主义
  final double idealismVsPragmatism; // 0=理想主义, 1=实用主义
  final double trustVsSuspicion; // 0=怀疑, 1=信任
  final double hedonismVsAsceticism; // 0=禁欲, 1=享乐
  final double nihilismVsMeaning; // 0=虚无, 1=意义

  // ── 世界观标签 ──
  final List<String> beliefs; // ["人性本善", "努力就会有回报"]

  // ── 固化程度（0=完全可塑, 1=完全固化） ──
  final double crystallization;

  const Worldview({
    required this.individualismVsCollectivism,
    required this.idealismVsPragmatism,
    required this.trustVsSuspicion,
    required this.hedonismVsAsceticism,
    required this.nihilismVsMeaning,
    this.beliefs = const [],
    required this.crystallization,
  });

  /// 婴儿空白三观 — 所有维度居中，完全可塑
  factory Worldview.blank() {
    return const Worldview(
      individualismVsCollectivism: 0.5,
      idealismVsPragmatism: 0.5,
      trustVsSuspicion: 0.5,
      hedonismVsAsceticism: 0.5,
      nihilismVsMeaning: 0.5,
      beliefs: [],
      crystallization: 0.0,
    );
  }

  /// 受冲击阈值 — 超过此值的事件才能改变三观
  double get shockThreshold => 0.3 + crystallization * 0.5;

  /// 尝试更新三观，返回是否成功（事件冲击力需超过阈值）
  bool canUpdate(LifeEvent event) {
    if (!event.affects(EventDimension.worldview)) return false;
    final severityValue = event.severity.index / EventSeverity.values.length;
    return severityValue >= shockThreshold;
  }

  /// 尝试更新三观，返回新的 Worldview 和是否更新成功
  ({Worldview worldview, bool updated}) tryUpdate(LifeEvent event) {
    if (!canUpdate(event)) {
      // 未达到阈值，但轻微固化
      return (
        worldview: copyWith(
          crystallization: (crystallization + 0.01).clamp(0.0, 1.0),
        ),
        updated: false,
      );
    }

    double clamp01(double v) => v.clamp(0.0, 1.0);

    // 根据事件冲击力计算变化量
    final impact = event.severity.index / EventSeverity.values.length;
    final resistance = 1.0 - crystallization; // 固化越高，变化越小
    final change = impact * resistance * 0.3; // 最大变化幅度

    var updated = copyWith(
      individualismVsCollectivism: clamp01(
        individualismVsCollectivism + event.impactOf('individualismVsCollectivism') * change,
      ),
      idealismVsPragmatism: clamp01(
        idealismVsPragmatism + event.impactOf('idealismVsPragmatism') * change,
      ),
      trustVsSuspicion: clamp01(
        trustVsSuspicion + event.impactOf('trustVsSuspicion') * change,
      ),
      hedonismVsAsceticism: clamp01(
        hedonismVsAsceticism + event.impactOf('hedonismVsAsceticism') * change,
      ),
      nihilismVsMeaning: clamp01(
        nihilismVsMeaning + event.impactOf('nihilismVsMeaning') * change,
      ),
      crystallization: (crystallization + 0.05).clamp(0.0, 1.0),
    );

    // 自动添加世界观标签
    final newBeliefs = List<String>.from(beliefs);
    _autoTag(updated, newBeliefs);
    updated = updated.copyWith(beliefs: newBeliefs);

    return (worldview: updated, updated: true);
  }

  /// 根据三观值自动标记世界观标签
  void _autoTag(Worldview wv, List<String> tags) {
    if (wv.trustVsSuspicion > 0.7 && !tags.contains('人性本善')) {
      tags.add('人性本善');
    }
    if (wv.trustVsSuspicion < 0.3 && !tags.contains('人心叵测')) {
      tags.add('人心叵测');
    }
    if (wv.nihilismVsMeaning > 0.7 && !tags.contains('人生有意义')) {
      tags.add('人生有意义');
    }
    if (wv.nihilismVsMeaning < 0.3 && !tags.contains('一切皆空')) {
      tags.add('一切皆空');
    }
    if (wv.idealismVsPragmatism < 0.3 && !tags.contains('理想至上')) {
      tags.add('理想至上');
    }
    if (wv.idealismVsPragmatism > 0.7 && !tags.contains('务实为本')) {
      tags.add('务实为本');
    }
  }

  /// 生成三观描述文本
  String get summary {
    final parts = <String>[];

    if (individualismVsCollectivism > 0.7) {
      parts.add('崇尚个人自由与独立');
    } else if (individualismVsCollectivism < 0.3) {
      parts.add('重视集体与归属感');
    }

    if (idealismVsPragmatism > 0.7) {
      parts.add('务实理性');
    } else if (idealismVsPragmatism < 0.3) {
      parts.add('怀揣理想主义');
    }

    if (trustVsSuspicion > 0.7) {
      parts.add('倾向于信任他人');
    } else if (trustVsSuspicion < 0.3) {
      parts.add('对人保持警惕');
    }

    if (hedonismVsAsceticism > 0.7) {
      parts.add('追求当下的快乐');
    } else if (hedonismVsAsceticism < 0.3) {
      parts.add('克制欲望，追求精神境界');
    }

    if (nihilismVsMeaning > 0.7) {
      parts.add('相信生命有其意义');
    } else if (nihilismVsMeaning < 0.3) {
      parts.add('对意义本身持怀疑态度');
    }

    if (beliefs.isNotEmpty) {
      parts.add('信奉"${beliefs.join('、')}"');
    }

    if (crystallization > 0.8) {
      parts.add('三观已高度固化');
    } else if (crystallization < 0.2) {
      parts.add('三观尚在形成中');
    }

    return parts.isEmpty ? '世界观尚未成型' : parts.join('，');
  }

  Worldview copyWith({
    double? individualismVsCollectivism,
    double? idealismVsPragmatism,
    double? trustVsSuspicion,
    double? hedonismVsAsceticism,
    double? nihilismVsMeaning,
    List<String>? beliefs,
    double? crystallization,
  }) {
    return Worldview(
      individualismVsCollectivism:
          individualismVsCollectivism ?? this.individualismVsCollectivism,
      idealismVsPragmatism: idealismVsPragmatism ?? this.idealismVsPragmatism,
      trustVsSuspicion: trustVsSuspicion ?? this.trustVsSuspicion,
      hedonismVsAsceticism: hedonismVsAsceticism ?? this.hedonismVsAsceticism,
      nihilismVsMeaning: nihilismVsMeaning ?? this.nihilismVsMeaning,
      beliefs: beliefs ?? this.beliefs,
      crystallization: crystallization ?? this.crystallization,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'individualismVsCollectivism': individualismVsCollectivism,
      'idealismVsPragmatism': idealismVsPragmatism,
      'trustVsSuspicion': trustVsSuspicion,
      'hedonismVsAsceticism': hedonismVsAsceticism,
      'nihilismVsMeaning': nihilismVsMeaning,
      'beliefs': beliefs,
      'crystallization': crystallization,
    };
  }

  factory Worldview.fromJson(Map<String, dynamic> json) {
    return Worldview(
      individualismVsCollectivism:
          (json['individualismVsCollectivism'] as num?)?.toDouble() ?? 0.5,
      idealismVsPragmatism:
          (json['idealismVsPragmatism'] as num?)?.toDouble() ?? 0.5,
      trustVsSuspicion: (json['trustVsSuspicion'] as num?)?.toDouble() ?? 0.5,
      hedonismVsAsceticism:
          (json['hedonismVsAsceticism'] as num?)?.toDouble() ?? 0.5,
      nihilismVsMeaning: (json['nihilismVsMeaning'] as num?)?.toDouble() ?? 0.5,
      beliefs: (json['beliefs'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      crystallization: (json['crystallization'] as num?)?.toDouble() ?? 0.0,
    );
  }

  String toJsonString() => jsonEncode(toJson());

  factory Worldview.fromJsonString(String source) =>
      Worldview.fromJson(jsonDecode(source) as Map<String, dynamic>);

  @override
  List<Object?> get props => [
        individualismVsCollectivism,
        idealismVsPragmatism,
        trustVsSuspicion,
        hedonismVsAsceticism,
        nihilismVsMeaning,
        beliefs,
        crystallization,
      ];
}
