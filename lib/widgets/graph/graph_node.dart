import 'dart:ui';
import 'package:equatable/equatable.dart';

/// 图节点 — 一个记忆卡片在图中的表示
class GraphNode extends Equatable {
  final String id;
  final String label;
  final String? subtitle;
  final String? summary;
  final int typeIndex;
  final double importance;
  final double weight;

  // 渲染位置（画布坐标）
  double x;
  double y;

  // 力学速度
  double vx = 0;
  double vy = 0;

  // 是否被固定（用户拖拽中）
  bool pinned = false;

  // 渲染半径
  double get radius => 28 + importance * 12;

  GraphNode({
    required this.id,
    required this.label,
    this.subtitle,
    this.summary,
    required this.typeIndex,
    this.importance = 0,
    this.weight = 1.0,
    required this.x,
    required this.y,
  });

  @override
  List<Object?> get props => [id, label, summary, typeIndex, importance, x, y, pinned];

  Offset get center => Offset(x, y);
}

/// 图连线 — 节点间的关系
class GraphEdge extends Equatable {
  final String id;
  final String sourceId;
  final String targetId;
  final String? label;
  final double strength;

  const GraphEdge({
    required this.id,
    required this.sourceId,
    required this.targetId,
    this.label,
    this.strength = 0.5,
  });

  @override
  List<Object?> get props => [id, sourceId, targetId, strength];
}