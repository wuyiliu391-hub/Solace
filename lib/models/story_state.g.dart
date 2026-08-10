// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'story_state.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

StoryNode _$StoryNodeFromJson(Map<String, dynamic> json) => StoryNode(
      id: json['id'] as String,
      name: json['name'] as String,
      type: $enumDecode(_$StoryNodeTypeEnumMap, json['type']),
      description: json['description'] as String,
      reached: json['reached'] as bool? ?? false,
      reachedAt: json['reachedAt'] == null
          ? null
          : DateTime.parse(json['reachedAt'] as String),
      prerequisites: (json['prerequisites'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      nextNodes: (json['nextNodes'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      triggerCondition: json['triggerCondition'] as String?,
      metadata: json['metadata'] as Map<String, dynamic>?,
    );

Map<String, dynamic> _$StoryNodeToJson(StoryNode instance) => <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'type': _$StoryNodeTypeEnumMap[instance.type]!,
      'description': instance.description,
      'reached': instance.reached,
      'reachedAt': instance.reachedAt?.toIso8601String(),
      'prerequisites': instance.prerequisites,
      'nextNodes': instance.nextNodes,
      'triggerCondition': instance.triggerCondition,
      'metadata': instance.metadata,
    };

const _$StoryNodeTypeEnumMap = {
  StoryNodeType.start: 'start',
  StoryNodeType.normal: 'normal',
  StoryNodeType.key: 'key',
  StoryNodeType.milestone: 'milestone',
  StoryNodeType.ending: 'ending',
};

StoryState _$StoryStateFromJson(Map<String, dynamic> json) => StoryState(
      relationshipStage: $enumDecodeNullable(
              _$RelationshipStageEnumMap, json['relationshipStage']) ??
          RelationshipStage.undefined,
      atmosphere:
          $enumDecodeNullable(_$StoryAtmosphereEnumMap, json['atmosphere']) ??
              StoryAtmosphere.undefined,
      nodes: (json['nodes'] as Map<String, dynamic>?)?.map(
            (k, e) =>
                MapEntry(k, StoryNode.fromJson(e as Map<String, dynamic>)),
          ) ??
          const {},
      currentNodeId: json['currentNodeId'] as String?,
      completedNodeIds: (json['completedNodeIds'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      mainStoryline: json['mainStoryline'] as String?,
      progress: (json['progress'] as num?)?.toDouble() ?? 0.0,
      pendingGoals: (json['pendingGoals'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      recentEvents: (json['recentEvents'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      userActions: (json['userActions'] as List<dynamic>?)
              ?.map((e) => StoryUserAction.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );

Map<String, dynamic> _$StoryStateToJson(StoryState instance) =>
    <String, dynamic>{
      'relationshipStage':
          _$RelationshipStageEnumMap[instance.relationshipStage]!,
      'atmosphere': _$StoryAtmosphereEnumMap[instance.atmosphere]!,
      'nodes': instance.nodes,
      'currentNodeId': instance.currentNodeId,
      'completedNodeIds': instance.completedNodeIds,
      'mainStoryline': instance.mainStoryline,
      'progress': instance.progress,
      'pendingGoals': instance.pendingGoals,
      'recentEvents': instance.recentEvents,
      'updatedAt': instance.updatedAt.toIso8601String(),
      'userActions': instance.userActions,
    };

const _$RelationshipStageEnumMap = {
  RelationshipStage.acquaintance: 'acquaintance',
  RelationshipStage.friend: 'friend',
  RelationshipStage.intimate: 'intimate',
  RelationshipStage.passionate: 'passionate',
  RelationshipStage.crisis: 'crisis',
  RelationshipStage.repairing: 'repairing',
  RelationshipStage.stable: 'stable',
  RelationshipStage.undefined: 'undefined',
};

const _$StoryAtmosphereEnumMap = {
  StoryAtmosphere.warm: 'warm',
  StoryAtmosphere.sweet: 'sweet',
  StoryAtmosphere.tense: 'tense',
  StoryAtmosphere.sad: 'sad',
  StoryAtmosphere.mysterious: 'mysterious',
  StoryAtmosphere.casual: 'casual',
  StoryAtmosphere.adventurous: 'adventurous',
  StoryAtmosphere.undefined: 'undefined',
};

StoryUserAction _$StoryUserActionFromJson(Map<String, dynamic> json) =>
    StoryUserAction(
      id: json['id'] as String,
      type: json['type'] as String,
      description: json['description'] as String?,
      data: json['data'] as Map<String, dynamic>?,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );

Map<String, dynamic> _$StoryUserActionToJson(StoryUserAction instance) =>
    <String, dynamic>{
      'id': instance.id,
      'type': instance.type,
      'description': instance.description,
      'data': instance.data,
      'timestamp': instance.timestamp.toIso8601String(),
    };
