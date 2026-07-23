import 'dart:convert';

/// 通用欲望槽（BDI 中的 Desire 维度）
/// 与具体「病娇」无关：任意人设填权重
enum DesireSlot {
  protect,
  connect,
  control,
  curiosity,
  play,
  respectSpace,
  utility,
}

/// 人设驱动的欲望画像（按角色缓存）
class CharacterDesireProfile {
  final String characterId;
  final String sourceHash;
  final Map<DesireSlot, double> weights;
  final List<String> moralBlocks;
  final DateTime updatedAt;
  final bool llmRefined;
  final String? refineNote;

  const CharacterDesireProfile({
    required this.characterId,
    required this.sourceHash,
    required this.weights,
    this.moralBlocks = const [],
    required this.updatedAt,
    this.llmRefined = false,
    this.refineNote,
  });

  double of(DesireSlot s) => (weights[s] ?? 0).clamp(0.0, 1.0);

  CharacterDesireProfile copyWith({
    Map<DesireSlot, double>? weights,
    List<String>? moralBlocks,
    DateTime? updatedAt,
    bool? llmRefined,
    String? refineNote,
  }) {
    return CharacterDesireProfile(
      characterId: characterId,
      sourceHash: sourceHash,
      weights: weights ?? this.weights,
      moralBlocks: moralBlocks ?? this.moralBlocks,
      updatedAt: updatedAt ?? this.updatedAt,
      llmRefined: llmRefined ?? this.llmRefined,
      refineNote: refineNote ?? this.refineNote,
    );
  }

  Map<String, dynamic> toMap() => {
        'characterId': characterId,
        'sourceHash': sourceHash,
        'weights': {
          for (final e in weights.entries) e.key.name: e.value,
        },
        'moralBlocks': moralBlocks,
        'updatedAt': updatedAt.toIso8601String(),
        'llmRefined': llmRefined,
        'refineNote': refineNote,
      };

  factory CharacterDesireProfile.fromMap(Map<String, dynamic> map) {
    final raw = map['weights'];
    final weights = <DesireSlot, double>{};
    if (raw is Map) {
      for (final s in DesireSlot.values) {
        final v = raw[s.name];
        if (v is num) weights[s] = v.toDouble();
      }
    }
    for (final s in DesireSlot.values) {
      weights.putIfAbsent(s, () => 0.15);
    }
    final blocks = <String>[];
    final mb = map['moralBlocks'];
    if (mb is List) {
      for (final e in mb) {
        blocks.add(e.toString());
      }
    }
    return CharacterDesireProfile(
      characterId: map['characterId']?.toString() ?? '',
      sourceHash: map['sourceHash']?.toString() ?? '',
      weights: weights,
      moralBlocks: blocks,
      updatedAt: DateTime.tryParse(map['updatedAt']?.toString() ?? '') ??
          DateTime.now(),
      llmRefined: map['llmRefined'] == true || map['llmRefined'] == 1,
      refineNote: map['refineNote']?.toString(),
    );
  }

  String toJson() => jsonEncode(toMap());

  factory CharacterDesireProfile.fromJson(String raw) =>
      CharacterDesireProfile.fromMap(
          Map<String, dynamic>.from(jsonDecode(raw) as Map));
}

/// 信念：本轮世界状态（短事实）
class CharacterWorldState {
  final String? foregroundApp;
  final int notificationCount;
  final List<String> notificationSnippets;
  final bool lateNight;
  final bool socialAppForeground;
  final bool intimateNotifyHint;
  final String? lastDeviceFeedback;
  final int hour;

  const CharacterWorldState({
    this.foregroundApp,
    this.notificationCount = 0,
    this.notificationSnippets = const [],
    this.lateNight = false,
    this.socialAppForeground = false,
    this.intimateNotifyHint = false,
    this.lastDeviceFeedback,
    required this.hour,
  });

  String toPromptBlock() {
    final buf = StringBuffer();
    buf.writeln('【世界信念 · 短事实】');
    buf.writeln('时段：${hour.toString().padLeft(2, '0')}:xx'
        '${lateNight ? '（深夜）' : ''}');
    if (foregroundApp != null && foregroundApp!.isNotEmpty) {
      buf.writeln('前台：$foregroundApp'
          '${socialAppForeground ? '（社交类）' : ''}');
    }
    if (notificationCount > 0) {
      buf.writeln('近通知数：$notificationCount');
      for (final s in notificationSnippets.take(3)) {
        buf.writeln('- $s');
      }
      if (intimateNotifyHint) buf.writeln('（含暧昧/亲密向关键词线索）');
    }
    if (lastDeviceFeedback != null && lastDeviceFeedback!.isNotEmpty) {
      buf.writeln('上次设备结果：$lastDeviceFeedback');
    }
    return buf.toString().trim();
  }
}

/// 意图：本轮选中的欲望 + 推荐手段
class CharacterIntention {
  final DesireSlot slot;
  final double score;
  final String motivePrompt;
  final List<String> preferredTools;
  final bool allowDeviceAction;

  const CharacterIntention({
    required this.slot,
    required this.score,
    required this.motivePrompt,
    required this.preferredTools,
    required this.allowDeviceAction,
  });

  String toPromptBlock() {
    final buf = StringBuffer();
    buf.writeln('【本轮意图 · 来自人设欲望，非固定病娇脚本】');
    buf.writeln('主导欲望：${slot.name}（强度 ${score.toStringAsFixed(2)}）');
    buf.writeln('戏剧动机：$motivePrompt');
    if (allowDeviceAction && preferredTools.isNotEmpty) {
      buf.writeln('若动手，优先考虑：${preferredTools.take(6).join('、')}');
      buf.writeln('仍须遵守权限与每轮最多 1 个 DEVICE_ACTION；无把握只演戏不动手。');
    } else {
      buf.writeln('本轮倾向不操作设备，只用台词表达。');
    }
    return buf.toString().trim();
  }
}
