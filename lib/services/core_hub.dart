import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/constants.dart';
import '../models/bt_agent_action.dart';
import '../models/task_request.dart';
import 'task_queue.dart';
import 'persona_rule_registry.dart';
import 'admin_guard.dart';
import 'bt_agent_execution_service.dart';
import 'bt_operation_lock_service.dart';
import 'audit_service.dart';

/// Core Hub — 全局中枢调度大脑
///
/// 单例模式，通过 [CoreHub.init] 初始化。
class CoreHub {
  CoreHub._(this._prefs);

  static CoreHub? _instance;

  /// 全局单例访问。必须在 [init] 完成后调用。
  static CoreHub get instance => _instance!;

  final SharedPreferences _prefs;
  late final TaskQueue _taskQueue;
  late final PersonaRuleRegistry _ruleRegistry;
  late final AdminGuard _adminGuard;
  late final AuditService _audit;
  BtAgentExecutionService? Function()? _btExecutionServiceFactory;
  String? _currentUserId;

  /// 初始化 Core Hub 单例。
  ///
  /// 加载持久化配置，创建子模块实例并恢复状态。
  ///
  /// [btExecutionServiceFactory] 为可选的工厂函数，返回
  /// [BtAgentExecutionService] 实例（需要外部 DI 绑定
  /// [LocalStorageRepository]）。不传则 BT 动作执行时会标记失败。
  static Future<CoreHub> init(
    SharedPreferences prefs, {
    BtAgentExecutionService? Function()? btExecutionServiceFactory,
  }) async {
    final hub = CoreHub._(prefs);

    hub._btExecutionServiceFactory = btExecutionServiceFactory;

    hub._adminGuard = AdminGuard();
    hub._ruleRegistry = PersonaRuleRegistry(prefs);
    await hub._ruleRegistry.init();

    hub._audit = AuditService(prefs);
    await hub._audit.init();

    hub._taskQueue = TaskQueue(prefs: prefs);
    await hub._taskQueue.restore();

    await hub._audit.log(
      category: 'system',
      action: 'core_hub_initialized',
    );

    _instance = hub;
    return hub;
  }

  /// 审计日志服务。
  AuditService get audit => _audit;

  // ────────────────────── Task submission ──────────────────────

  /// 提交行为任务，返回更新状态后的任务。
  ///
  /// 流程：AdminGuard 权限校验 → 人设规则校验 → 入队等待执行。
  Future<TaskRequest> submitTask(TaskRequest task) async {
    final isAdmin = _adminGuard.isAdmin(
      task.sourceCharacterId,
      _currentUserId,
    );

    final request = AdminRequest(
      source: isAdmin ? RequestSource.user : RequestSource.character,
      sourceId: task.sourceCharacterId,
      targetAction: task.actionType,
    );

    final decision = _adminGuard.checkAccess(request);
    if (decision == AccessDecision.denied) {
      task.status = 'rejected';
      task.result = 'AdminGuard 拒绝：无权执行该操作';
      task.completedAt = DateTime.now();
      return task;
    }

    if (decision == AccessDecision.needsApproval) {
      // 缺少规则时自动生成（兼容首次使用或新角色）
      if (_ruleRegistry.getRule(task.sourceCharacterId) == null) {
        final rule = _ruleRegistry.generateFromCharacter({
          'id': task.sourceCharacterId,
        });
        await _ruleRegistry.setRule(rule);
        debugPrint('CoreHub: auto-gen rule for ${task.sourceCharacterId}');
      }

      final allowed = _ruleRegistry.isActionAllowed(
        task.sourceCharacterId,
        task.actionType,
      );
      if (!allowed) {
        task.status = 'rejected';
        task.result = '人设规则拒绝：该角色不被允许执行此操作';
        task.completedAt = DateTime.now();
        await _audit.log(
          category: 'task',
          action: 'task_rejected',
          characterId: task.sourceCharacterId,
          detail: '${task.actionType} — 人设规则拒绝',
        );
        return task;
      }
    }

    await _taskQueue.enqueue(task);
    await _audit.log(
      category: 'task',
      action: 'task_enqueued',
      characterId: task.sourceCharacterId,
      detail: '${task.actionType} (priority: ${task.priority})',
    );
    return task;
  }

  // ────────────────────── Task execution ──────────────────────

  /// 处理队列中的下一个待执行任务。
  Future<void> processQueue() async {
    await _taskQueue.processNext(_executeTask);
  }

  /// 实际执行单个任务。
  ///
  /// BT 类型动作委托给 [BtAgentExecutionService]。
  Future<void> _executeTask(TaskRequest task) async {
    try {
      if (_isBtActionType(task.actionType)) {
        await _executeBtAction(task);
      } else {
        task.status = 'failed';
        task.result = 'SocialActionExecutor 未绑定';
      }

      await _audit.log(
        category: 'task',
        action: 'task_completed',
        characterId: task.sourceCharacterId,
        detail: '${task.actionType} — ${task.result ?? "ok"}',
      );
    } catch (e) {
      task.status = 'failed';
      task.result = '执行异常: $e';
      await _audit.log(
        category: 'task',
        action: 'task_failed',
        characterId: task.sourceCharacterId,
        detail: '${task.actionType} — $e',
      );
      rethrow;
    }
  }

  /// 执行 BT 动作：构建 JSON 并通过 [BtAgentExecutionService] 执行。
  Future<void> _executeBtAction(TaskRequest task) async {
    if (_btExecutionServiceFactory == null) {
      task.status = 'failed';
      task.result = 'BtAgentExecutionService 工厂未绑定';
      return;
    }
    final btExecutor = _btExecutionServiceFactory!();
    if (btExecutor == null) {
      task.status = 'failed';
      task.result = 'BtAgentExecutionService 未绑定';
      return;
    }

    final actionJson = jsonEncode([
      {
        'action': task.actionType,
        'target_id': task.sourceCharacterId,
        ...task.payload,
      }
    ]);

    await btExecutor.executeFromJson(
      actionJson,
      characterId: task.sourceCharacterId,
      sessionId: task.payload['sessionId'] as String? ?? '',
      chatType: task.payload['chatType'] as String? ?? 'single',
    );
  }

  /// 判断动作类型是否属于 BT 操作枚举。
  static bool _isBtActionType(String actionType) {
    return BtActionType.values.any((bt) => bt.name == actionType);
  }

  // ────────────────────── Dependency binding ──────────────────────

  /// 绑定 BT 执行服务工厂。可在 [init] 之后调用，用于延迟注入。
  void bindBtExecutionServiceFactory(
    BtAgentExecutionService? Function() factory,
  ) {
    _btExecutionServiceFactory = factory;
  }

  // ────────────────────── Rule management ──────────────────────

  /// 人设规则注册表。
  PersonaRuleRegistry get ruleRegistry => _ruleRegistry;

  /// 更新指定角色的规则，从角色数据重新生成。
  Future<void> updateCharacterRule(
    String characterId,
    Map<String, dynamic> characterData,
  ) async {
    final rule = _ruleRegistry.generateFromCharacter(characterData);
    await _ruleRegistry.setRule(rule);
  }

  // ────────────────────── User management ──────────────────────

  /// 设置当前用户 ID，用于 AdminGuard 权限判定。
  void setCurrentUserId(String userId) {
    _currentUserId = userId;
  }

  /// 当前用户 ID。
  String? get currentUserId => _currentUserId;

  // ────────────────────── Cleanup ──────────────────────

  /// 清理 AI 输出中的 BT 内部标签和 payload，返回清洗后的文本。
  String cleanOutput(String rawOutput) {
    return stripBtAgentPayloads(rawOutput);
  }

  /// 中断指定角色的所有待执行任务。
  void interruptCharacter(String characterId) {
    _taskQueue.interrupt(characterId);
    BtOperationLockService.instance.interruptAll(
      reason: '角色 $characterId 被中断',
    );
  }

  // ────────────────────── Queue access ──────────────────────

  /// 任务队列实例。
  TaskQueue get taskQueue => _taskQueue;

  /// 当前等待执行的任务数量。
  int get pendingTaskCount => _taskQueue.pendingCount;
}
