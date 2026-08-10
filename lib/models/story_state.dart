import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'story_state.g.dart';

/// 关系阶段 — AI 与用户当前的关系发展阶段
enum RelationshipStage {
  /// 初识 — 刚刚认识，还在互相了解
  acquaintance,
  
  /// 朋友 — 建立了基本信任和友谊
  friend,
  
  /// 亲密 — 情感连接深入，有默契
  intimate,
  
  /// 热恋 — 强烈的情感连接（恋人模式）
  passionate,
  
  /// 危机 — 关系出现摩擦或冲突
  crisis,
  
  /// 修复 — 正在修复关系
  repairing,
  
  /// 稳定 — 长期稳定的陪伴关系
  stable,
  
  /// 未定义 — 尚未设定
  undefined,
}

/// 故事氛围 — 当前对话/剧情的情绪基调
enum StoryAtmosphere {
  /// 温馨治愈
  warm,
  
  /// 甜蜜恋爱
  sweet,
  
  /// 紧张冲突
  tense,
  
  /// 悲伤忧郁
  sad,
  
  /// 悬疑神秘
  mysterious,
  
  /// 轻松日常
  casual,
  
  /// 冒险探索
  adventurous,
  
  /// 未定义
  undefined,
}

/// 故事节点类型
enum StoryNodeType {
  /// 起始节点
  start,
  
  /// 普通节点
  normal,
  
  /// 关键节点（剧情转折点）
  key,
  
  /// 里程碑节点（关系升级等）
  milestone,
  
  /// 结局节点
  ending,
}

/// 单个故事节点
@JsonSerializable()
class StoryNode extends Equatable {
  /// 节点唯一 ID
  final String id;
  
  /// 节点名称
  final String name;
  
  /// 节点类型
  final StoryNodeType type;
  
  /// 节点描述（供 AI 理解当前节点内容）
  final String description;
  
  /// 是否已到达
  final bool reached;
  
  /// 到达时间
  final DateTime? reachedAt;
  
  /// 前置节点 ID 列表（依赖关系）
  final List<String> prerequisites;
  
  /// 后置节点 ID 列表
  final List<String> nextNodes;
  
  /// 触发条件描述（供 AI 判断是否应推进到该节点）
  final String? triggerCondition;
  
  /// 节点元数据（扩展字段）
  final Map<String, dynamic>? metadata;

  const StoryNode({
    required this.id,
    required this.name,
    required this.type,
    required this.description,
    this.reached = false,
    this.reachedAt,
    this.prerequisites = const [],
    this.nextNodes = const [],
    this.triggerCondition,
    this.metadata,
  });

  /// 创建一个已到达的节点副本
  StoryNode copyWithReached() {
    return copyWith(
      reached: true,
      reachedAt: DateTime.now(),
    );
  }

  StoryNode copyWith({
    String? id,
    String? name,
    StoryNodeType? type,
    String? description,
    bool? reached,
    DateTime? reachedAt,
    List<String>? prerequisites,
    List<String>? nextNodes,
    String? triggerCondition,
    Map<String, dynamic>? metadata,
  }) {
    return StoryNode(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      description: description ?? this.description,
      reached: reached ?? this.reached,
      reachedAt: reachedAt ?? this.reachedAt,
      prerequisites: prerequisites ?? this.prerequisites,
      nextNodes: nextNodes ?? this.nextNodes,
      triggerCondition: triggerCondition ?? this.triggerCondition,
      metadata: metadata ?? this.metadata,
    );
  }

  factory StoryNode.fromJson(Map<String, dynamic> json) =>
      _$StoryNodeFromJson(json);
  Map<String, dynamic> toJson() => _$StoryNodeToJson(this);

  @override
  List<Object?> get props => [
        id,
        name,
        type,
        description,
        reached,
        reachedAt,
        prerequisites,
        nextNodes,
        triggerCondition,
        metadata,
      ];
}

/// 完整的故事状态
@JsonSerializable()
class StoryState extends Equatable {
  /// 当前关系阶段
  final RelationshipStage relationshipStage;
  
  /// 当前故事氛围
  final StoryAtmosphere atmosphere;
  
  /// 所有故事节点（按 ID 索引）
  final Map<String, StoryNode> nodes;
  
  /// 当前所在节点 ID
  final String? currentNodeId;
  
  /// 已完成的节点 ID 列表
  final List<String> completedNodeIds;
  
  /// 故事标题/主线名称
  final String? mainStoryline;
  
  /// 故事进度（0.0 - 1.0）
  final double progress;
  
  /// 未完成的剧情目标/承诺列表
  final List<String> pendingGoals;
  
  /// 最近的重大事件（用于上下文）
  final List<String> recentEvents;
  
  /// 最后更新时间
  final DateTime updatedAt;
  
  /// 用户主动调用的故事修改记录
  final List<StoryUserAction> userActions;

  const StoryState({
    this.relationshipStage = RelationshipStage.undefined,
    this.atmosphere = StoryAtmosphere.undefined,
    this.nodes = const {},
    this.currentNodeId,
    this.completedNodeIds = const [],
    this.mainStoryline,
    this.progress = 0.0,
    this.pendingGoals = const [],
    this.recentEvents = const [],
    required this.updatedAt,
    this.userActions = const [],
  });

  /// 创建初始故事状态
  factory StoryState.initial() {
    return StoryState(
      updatedAt: DateTime.now(),
    );
  }

  /// 获取当前节点
  StoryNode? get currentNode {
    if (currentNodeId == null || !nodes.containsKey(currentNodeId)) {
      return null;
    }
    return nodes[currentNodeId];
  }

  /// 检查是否所有前置节点都已到达
  bool canReachNode(StoryNode node) {
    return node.prerequisites.every((id) => completedNodeIds.contains(id));
  }

  /// 获取当前可到达的下一个节点列表
  List<StoryNode> getAvailableNextNodes() {
    if (currentNodeId == null) return [];
    final current = currentNode;
    if (current == null) return [];
    return current.nextNodes
        .map((id) => nodes[id])
        .whereType<StoryNode>()
        .where((node) => canReachNode(node))
        .toList();
  }

  StoryState copyWith({
    RelationshipStage? relationshipStage,
    StoryAtmosphere? atmosphere,
    Map<String, StoryNode>? nodes,
    String? currentNodeId,
    List<String>? completedNodeIds,
    String? mainStoryline,
    double? progress,
    List<String>? pendingGoals,
    List<String>? recentEvents,
    DateTime? updatedAt,
    List<StoryUserAction>? userActions,
  }) {
    return StoryState(
      relationshipStage: relationshipStage ?? this.relationshipStage,
      atmosphere: atmosphere ?? this.atmosphere,
      nodes: nodes ?? this.nodes,
      currentNodeId: currentNodeId ?? this.currentNodeId,
      completedNodeIds: completedNodeIds ?? this.completedNodeIds,
      mainStoryline: mainStoryline ?? this.mainStoryline,
      progress: progress ?? this.progress,
      pendingGoals: pendingGoals ?? this.pendingGoals,
      recentEvents: recentEvents ?? this.recentEvents,
      updatedAt: updatedAt ?? DateTime.now(),
      userActions: userActions ?? this.userActions,
    );
  }

  /// 标记节点为已完成
  StoryState markNodeCompleted(String nodeId) {
    if (completedNodeIds.contains(nodeId)) return this;
    final node = nodes[nodeId];
    if (node == null) return this;
    final updatedNode = node.copyWithReached();
    final newNodes = Map<String, StoryNode>.from(nodes);
    newNodes[nodeId] = updatedNode;
    return copyWith(
      nodes: newNodes,
      completedNodeIds: [...completedNodeIds, nodeId],
      currentNodeId: node.nextNodes.isNotEmpty ? node.nextNodes.first : currentNodeId,
    );
  }

  /// 添加事件到最近事件列表（保留最近 20 条）
  StoryState addRecentEvent(String event) {
    final events = [event, ...recentEvents];
    if (events.length > 20) {
      events.removeLast();
    }
    return copyWith(recentEvents: events);
  }

  factory StoryState.fromJson(Map<String, dynamic> json) =>
      _$StoryStateFromJson(json);
  Map<String, dynamic> toJson() => _$StoryStateToJson(this);

  @override
  List<Object?> get props => [
        relationshipStage,
        atmosphere,
        nodes,
        currentNodeId,
        completedNodeIds,
        mainStoryline,
        progress,
        pendingGoals,
        recentEvents,
        updatedAt,
        userActions,
      ];
}

/// 用户主动对故事进行的操作记录
@JsonSerializable()
class StoryUserAction extends Equatable {
  final String id;
  final String type; // 'add_goal', 'complete_goal', 'set_stage', 'add_event', 'custom'
  final String? description;
  final Map<String, dynamic>? data;
  final DateTime timestamp;

  const StoryUserAction({
    required this.id,
    required this.type,
    this.description,
    this.data,
    required this.timestamp,
  });

  factory StoryUserAction.fromJson(Map<String, dynamic> json) =>
      _$StoryUserActionFromJson(json);
  Map<String, dynamic> toJson() => _$StoryUserActionToJson(this);

  @override
  List<Object?> get props => [id, type, description, data, timestamp];
}
