import 'dart:convert';
import 'package:uuid/uuid.dart';
import '../config/constants.dart';

/// 任务请求，描述一个 AI 角色行为动作
class TaskRequest {
  /// 任务唯一 ID
  final String id;

  /// 发起任务的角色 ID
  final String sourceCharacterId;

  /// 动作类型（如 social_visit, social_friend_request 等）
  final String actionType;

  /// 动作专属数据
  final Map<String, dynamic> payload;

  /// 优先级：0=normal, 1=urgent, 2=user_direct
  final int priority;

  /// 状态：pending / running / completed / failed / rejected
  String status;

  /// 创建时间
  final DateTime createdAt;

  /// 完成时间
  DateTime? completedAt;

  /// 执行结果或拒绝原因
  String? result;

  /// 本次任务消耗的 token 数
  int? tokenUsage;

  TaskRequest({
    String? id,
    required this.sourceCharacterId,
    required this.actionType,
    this.payload = const {},
    this.priority = 0,
    this.status = 'pending',
    DateTime? createdAt,
    this.completedAt,
    this.result,
    this.tokenUsage,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'sourceCharacterId': sourceCharacterId,
        'actionType': actionType,
        'payload': payload,
        'priority': priority,
        'status': status,
        'createdAt': createdAt.toIso8601String(),
        'completedAt': completedAt?.toIso8601String(),
        'result': result,
        'tokenUsage': tokenUsage,
      };

  factory TaskRequest.fromJson(Map<String, dynamic> json) => TaskRequest(
        id: json['id'] as String?,
        sourceCharacterId: json['sourceCharacterId'] as String,
        actionType: json['actionType'] as String,
        payload: (json['payload'] as Map?)?.cast<String, dynamic>() ?? {},
        priority: json['priority'] as int? ?? 0,
        status: json['status'] as String? ?? 'pending',
        createdAt: json['createdAt'] != null
            ? DateTime.parse(json['createdAt'] as String)
            : null,
        completedAt: json['completedAt'] != null
            ? DateTime.parse(json['completedAt'] as String)
            : null,
        result: json['result'] as String?,
        tokenUsage: json['tokenUsage'] as int?,
      );
}

/// 资源锁，防止同一资源被并发操作
class TaskLock {
  /// 资源标识，如 "contact:abc123", "social:charA:charB"
  final String resourceKey;

  /// 加锁时间
  final DateTime lockedAt;

  TaskLock({
    required this.resourceKey,
    DateTime? lockedAt,
  }) : lockedAt = lockedAt ?? DateTime.now();
}
