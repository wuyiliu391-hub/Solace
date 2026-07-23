import 'dart:convert';
import 'dart:collection';

import 'package:shared_preferences/shared_preferences.dart';

import '../config/constants.dart';
import '../models/task_request.dart';

/// 异步任务队列，串行执行 AI 角色行为请求，避免并发冲突
///
/// 由 CoreHub 实例化持有，不使用单例模式。
class TaskQueue {
  final SharedPreferences _prefs;

  final Queue<TaskRequest> _pending = Queue<TaskRequest>();
  TaskRequest? _running;
  final Map<String, TaskLock> _locks = {};
  final List<TaskRequest> _completed = [];

  static const int _maxCompleted = 100;

  TaskQueue({
    required SharedPreferences prefs,
  })  : _prefs = prefs;

  /// 当前等待队列长度
  int get pendingCount => _pending.length;

  /// 待执行任务列表（只读副本）
  List<TaskRequest> get pendingTasks => List.unmodifiable(_pending);

  /// 已完成任务列表（只读副本，最多 100 条）
  List<TaskRequest> get completedTasks => List.unmodifiable(_completed);

  /// 将任务加入队列。
  Future<void> enqueue(TaskRequest task) async {
    _pending.addLast(task);
    await persist();
  }

  /// 从队列取出下一个任务并交由 [executor] 执行，返回已完成的任务。
  ///
  /// 若队列为空或已有任务正在运行，返回 null。
  Future<TaskRequest?> processNext(
    Future<void> Function(TaskRequest task) executor,
  ) async {
    if (_pending.isEmpty || _running != null) return null;

    // 按优先级排序：取最高优先级的任务
    _sortByPriority();
    _running = _pending.removeFirst();
    _running!.status = 'running';

    try {
      await executor(_running!);
      _running!.status = 'completed';
    } catch (e) {
      _running!.status = 'failed';
      _running!.result = e.toString();
    }
    _running!.completedAt = DateTime.now();
    final completed = _running!;
    _running = null;
    _addToCompleted(completed);
    await persist();
    return completed;
  }

  /// 拒绝指定任务，记录原因
  void reject(String taskId, String reason) {
    // 检查待执行队列
    for (final task in _pending) {
      if (task.id == taskId) {
        task.status = 'rejected';
        task.result = reason;
        task.completedAt = DateTime.now();
        _pending.remove(task);
        _addToCompleted(task);
        persist();
        return;
      }
    }

    // 检查正在运行的任务
    if (_running?.id == taskId) {
      _running!.status = 'rejected';
      _running!.result = reason;
      _running!.completedAt = DateTime.now();
      _addToCompleted(_running!);
      _running = null;
      persist();
    }
  }

  /// 取消指定角色发起的所有待执行任务
  void interrupt(String characterId) {
    final toRemove = _pending
        .where((t) => t.sourceCharacterId == characterId)
        .toList();
    for (final task in toRemove) {
      task.status = 'rejected';
      task.result = '被角色中断';
      task.completedAt = DateTime.now();
      _pending.remove(task);
      _addToCompleted(task);
    }
    persist();
  }

  /// 检查资源是否被锁定
  bool isLocked(String resourceKey) {
    return _locks.containsKey(resourceKey);
  }

  /// 锁定资源
  void lock(String resourceKey) {
    _locks[resourceKey] = TaskLock(resourceKey: resourceKey);
  }

  /// 解锁资源
  void unlock(String resourceKey) {
    _locks.remove(resourceKey);
  }

  /// 将队列状态序列化到 SharedPreferences
  Future<void> persist() async {
    final pendingJson = _pending.map((t) => t.toJson()).toList();
    final completedJson = _completed.map((t) => t.toJson()).toList();

    await _prefs.setString(
      PrefKeys.coreHubTaskQueuePending,
      jsonEncode(pendingJson),
    );
    await _prefs.setString(
      PrefKeys.coreHubTaskQueueCompleted,
      jsonEncode(completedJson),
    );
  }

  /// 从 SharedPreferences 恢复队列状态
  Future<void> restore() async {
    final pendingStr = _prefs.getString(PrefKeys.coreHubTaskQueuePending);
    if (pendingStr != null) {
      final List<dynamic> list = jsonDecode(pendingStr) as List<dynamic>;
      _pending.clear();
      for (final item in list) {
        _pending.add(TaskRequest.fromJson(item as Map<String, dynamic>));
      }
    }

    final completedStr = _prefs.getString(PrefKeys.coreHubTaskQueueCompleted);
    if (completedStr != null) {
      final List<dynamic> list = jsonDecode(completedStr) as List<dynamic>;
      _completed.clear();
      for (final item in list) {
        _completed.add(TaskRequest.fromJson(item as Map<String, dynamic>));
      }
    }
  }

  /// 异常恢复：检查卡死的任务和过期的锁。
  ///
  /// - 运行超过 [maxRunningDuration] 的任务标记为 failed 并移入已完成
  /// - 持有超过 [maxLockDuration] 的锁自动释放
  void recoverFromException({
    Duration maxRunningDuration = const Duration(minutes: 10),
    Duration maxLockDuration = const Duration(minutes: 15),
  }) {
    final now = DateTime.now();

    // 检查卡死的运行任务
    if (_running != null) {
      final elapsed = now.difference(_running!.createdAt);
      if (elapsed > maxRunningDuration) {
        _running!.status = 'failed';
        _running!.result = '执行超时（${elapsed.inMinutes}分钟），自动恢复';
        _running!.completedAt = now;
        _addToCompleted(_running!);
        _running = null;
        persist();
      }
    }

    // 检查过期的锁
    final expiredLocks = _locks.entries
        .where((e) => now.difference(e.value.lockedAt) > maxLockDuration)
        .map((e) => e.key)
        .toList();
    for (final key in expiredLocks) {
      _locks.remove(key);
    }
  }

  /// 按优先级降序排列待执行队列
  void _sortByPriority() {
    final sorted = _pending.toList()..sort((a, b) => b.priority.compareTo(a.priority));
    _pending.clear();
    for (final task in sorted) {
      _pending.addLast(task);
    }
  }

  /// 将任务加入已完成列表，超出上限时移除最早的记录
  void _addToCompleted(TaskRequest task) {
    _completed.add(task);
    while (_completed.length > _maxCompleted) {
      _completed.removeAt(0);
    }
  }
}
