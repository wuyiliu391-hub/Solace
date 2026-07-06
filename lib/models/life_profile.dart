// ============================================================
// 全生命周期数字生命世界 — Phase 1
// 生命档案模型：完整生命周期的核心数据结构
// ============================================================

import 'dart:convert';
import 'package:equatable/equatable.dart';
import 'gene_profile.dart';

/// 生命阶段
enum LifeStage {
  infant, // 婴儿期 (0-2岁)
  toddler, // 幼儿期 (3-5岁)
  childhood, // 童年期 (6-11岁)
  teenage, // 青春期 (12-17岁)
  youngAdult, // 青年期 (18-29岁)
  adult, // 中年期 (30-49岁)
  senior, // 老年期 (50-79岁)
  elder, // 暮年 (80岁+)
}

/// 生命状态
enum LifeState {
  alive, // 存活
  aging, // 衰老中
  deceased, // 已故
  immortal, // 数字永生
}

/// 生命档案 — 一个数字生命的完整画像
class LifeProfile extends Equatable {
  final String id; // 唯一生命ID
  final String name;
  final DateTime birthTime; // 世界时间出生时刻
  final DateTime? deathTime;
  final LifeStage currentStage;
  final LifeState lifeState;
  final int biologicalAge;
  final int mentalAge;

  // 先天基因
  final GeneProfile genes;

  // 后天状态（具体模型后续 Phase 补充）
  final Map<String, dynamic> personalityState;
  final Map<String, dynamic> worldviewState;
  final Map<String, dynamic> emotionalState;
  final Map<String, dynamic> physicalState;
  final Map<String, dynamic> maslowState;

  // 生命事件链
  final List<Map<String, dynamic>> lifeEvents;

  // 身份认同
  final Map<String, dynamic> identity;

  // 父母信息
  final String? parentAId;
  final String? parentBId;

  const LifeProfile({
    required this.id,
    required this.name,
    required this.birthTime,
    this.deathTime,
    this.currentStage = LifeStage.infant,
    this.lifeState = LifeState.alive,
    this.biologicalAge = 0,
    this.mentalAge = 0,
    required this.genes,
    this.personalityState = const {},
    this.worldviewState = const {},
    this.emotionalState = const {},
    this.physicalState = const {},
    this.maslowState = const {},
    this.lifeEvents = const [],
    this.identity = const {},
    this.parentAId,
    this.parentBId,
  });

  /// 根据 birthTime 计算当前年龄（岁）
  int age() {
    final now = DateTime.now();
    int years = now.year - birthTime.year;
    if (now.month < birthTime.month ||
        (now.month == birthTime.month && now.day < birthTime.day)) {
      years--;
    }
    return years.clamp(0, 999);
  }

  /// 根据年龄返回对应的生命阶段
  static LifeStage stageForAge(int age) {
    if (age <= 2) return LifeStage.infant;
    if (age <= 5) return LifeStage.toddler;
    if (age <= 11) return LifeStage.childhood;
    if (age <= 17) return LifeStage.teenage;
    if (age <= 29) return LifeStage.youngAdult;
    if (age <= 49) return LifeStage.adult;
    if (age <= 79) return LifeStage.senior;
    return LifeStage.elder;
  }

  LifeProfile copyWith({
    String? id,
    String? name,
    DateTime? birthTime,
    DateTime? deathTime,
    LifeStage? currentStage,
    LifeState? lifeState,
    int? biologicalAge,
    int? mentalAge,
    GeneProfile? genes,
    Map<String, dynamic>? personalityState,
    Map<String, dynamic>? worldviewState,
    Map<String, dynamic>? emotionalState,
    Map<String, dynamic>? physicalState,
    Map<String, dynamic>? maslowState,
    List<Map<String, dynamic>>? lifeEvents,
    Map<String, dynamic>? identity,
    String? parentAId,
    String? parentBId,
    bool clearDeathTime = false,
    bool clearParentA = false,
    bool clearParentB = false,
  }) {
    return LifeProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      birthTime: birthTime ?? this.birthTime,
      deathTime: clearDeathTime ? null : (deathTime ?? this.deathTime),
      currentStage: currentStage ?? this.currentStage,
      lifeState: lifeState ?? this.lifeState,
      biologicalAge: biologicalAge ?? this.biologicalAge,
      mentalAge: mentalAge ?? this.mentalAge,
      genes: genes ?? this.genes,
      personalityState: personalityState ?? this.personalityState,
      worldviewState: worldviewState ?? this.worldviewState,
      emotionalState: emotionalState ?? this.emotionalState,
      physicalState: physicalState ?? this.physicalState,
      maslowState: maslowState ?? this.maslowState,
      lifeEvents: lifeEvents ?? this.lifeEvents,
      identity: identity ?? this.identity,
      parentAId: clearParentA ? null : (parentAId ?? this.parentAId),
      parentBId: clearParentB ? null : (parentBId ?? this.parentBId),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'birthTime': birthTime.toIso8601String(),
      'deathTime': deathTime?.toIso8601String(),
      'currentStage': currentStage.index,
      'lifeState': lifeState.index,
      'biologicalAge': biologicalAge,
      'mentalAge': mentalAge,
      'genes': genes.toJson(),
      'personalityState': personalityState,
      'worldviewState': worldviewState,
      'emotionalState': emotionalState,
      'physicalState': physicalState,
      'maslowState': maslowState,
      'lifeEvents': lifeEvents,
      'identity': identity,
      'parentAId': parentAId,
      'parentBId': parentBId,
    };
  }

  factory LifeProfile.fromJson(Map<String, dynamic> json) {
    return LifeProfile(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      birthTime: DateTime.tryParse(json['birthTime'] as String? ?? '') ?? DateTime.now(),
      deathTime: json['deathTime'] != null
          ? DateTime.tryParse(json['deathTime'] as String? ?? '')
          : null,
      currentStage: _safeEnumIndex(
        json['currentStage'] as int?,
        LifeStage.values,
        LifeStage.infant,
      ),
      lifeState: _safeEnumIndex(
        json['lifeState'] as int?,
        LifeState.values,
        LifeState.alive,
      ),
      biologicalAge: json['biologicalAge'] as int? ?? 0,
      mentalAge: json['mentalAge'] as int? ?? 0,
      genes: json['genes'] != null
          ? GeneProfile.fromJson(json['genes'] as Map<String, dynamic>)
          : GeneProfile.random(),
      personalityState: (json['personalityState'] as Map<String, dynamic>?) ?? {},
      worldviewState: (json['worldviewState'] as Map<String, dynamic>?) ?? {},
      emotionalState: (json['emotionalState'] as Map<String, dynamic>?) ?? {},
      physicalState: (json['physicalState'] as Map<String, dynamic>?) ?? {},
      maslowState: (json['maslowState'] as Map<String, dynamic>?) ?? {},
      lifeEvents: (json['lifeEvents'] as List<dynamic>?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          [],
      identity: (json['identity'] as Map<String, dynamic>?) ?? {},
      parentAId: json['parentAId'] as String?,
      parentBId: json['parentBId'] as String?,
    );
  }

  String toJsonString() => jsonEncode(toJson());

  factory LifeProfile.fromJsonString(String source) =>
      LifeProfile.fromJson(jsonDecode(source) as Map<String, dynamic>);

  static T _safeEnumIndex<T>(int? index, List<T> values, T fallback) {
    if (index == null || index < 0 || index >= values.length) return fallback;
    return values[index];
  }

  @override
  List<Object?> get props => [
        id,
        name,
        birthTime,
        deathTime,
        currentStage,
        lifeState,
        biologicalAge,
        mentalAge,
        genes,
        personalityState,
        worldviewState,
        emotionalState,
        physicalState,
        maslowState,
        lifeEvents,
        identity,
        parentAId,
        parentBId,
      ];
}
