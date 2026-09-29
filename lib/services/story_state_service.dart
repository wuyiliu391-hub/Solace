import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/story_state.dart';
import '../repositories/local_storage_repository.dart';

/// 故事状态服务 — 管理角色与用户之间的故事状态
///
/// 职责：
/// - 维护每个角色-用户对的 StoryState（关系阶段、剧情节点、未完成目标等）
/// - 提供状态读写与转换接口
/// - 为 ProactiveDecisionEngine 提供上下文数据
class StoryStateService {
  StoryStateService(this._storage);

  final LocalStorageRepository _storage;

  /// 内存缓存：{(characterId_userId): StoryState}
  final Map<String, StoryState> _cache = {};

  final _uuid = const Uuid();

  /// SharedPreferences key 前缀
  static const String _prefPrefix = 'story_state_';

  String _cacheKey(String characterId, String userId) =>
      '${characterId}_$userId';

  String _prefKey(String characterId, String userId) =>
      '$_prefPrefix${characterId}_$userId';

  // ─── 读取 ──────────────────────────────────────────────

  /// 获取角色的故事状态，不存在则返回初始状态
  Future<StoryState> getStoryState({
    required String characterId,
    required String userId,
  }) async {
    final key = _cacheKey(characterId, userId);

    // 先查缓存
    if (_cache.containsKey(key)) {
      return _cache[key]!;
    }

    // 从持久化存储加载
    try {
      final raw = _storage.sharedPreferences?.getString(_prefKey(characterId, userId));
      if (raw != null && raw.isNotEmpty) {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        final state = StoryState.fromJson(json);
        _cache[key] = state;
        return state;
      }
    } catch (e) {
      debugPrint('StoryStateService: 加载失败 ($characterId) - $e');
    }

    // 返回初始状态
    return StoryState.initial();
  }

  // ─── 保存 ──────────────────────────────────────────────

  /// 保存故事状态到缓存和持久化存储
  Future<void> saveStoryState({
    required String characterId,
    required String userId,
    required StoryState state,
  }) async {
    final key = _cacheKey(characterId, userId);
    final updated = state.copyWith(updatedAt: DateTime.now());
    _cache[key] = updated;

    try {
      final json = jsonEncode(updated.toJson());
      await _storage.sharedPreferences?.setString(
        _prefKey(characterId, userId),
        json,
      );
    } catch (e) {
      debugPrint('StoryStateService: 保存失败 ($characterId) - $e');
    }
  }

  // ─── 关系阶段 ─────────────────────────────────────────

  /// 更新关系阶段
  Future<void> setRelationshipStage({
    required String characterId,
    required String userId,
    required RelationshipStage stage,
  }) async {
    final current = await getStoryState(
      characterId: characterId,
      userId: userId,
    );
    final updated = current.copyWith(
      relationshipStage: stage,
      updatedAt: DateTime.now(),
    );
    await saveStoryState(
      characterId: characterId,
      userId: userId,
      state: updated,
    );
  }

  // ─── 故事氛围 ─────────────────────────────────────────

  /// 更新故事氛围
  Future<void> setAtmosphere({
    required String characterId,
    required String userId,
    required StoryAtmosphere atmosphere,
  }) async {
    final current = await getStoryState(
      characterId: characterId,
      userId: userId,
    );
    final updated = current.copyWith(
      atmosphere: atmosphere,
      updatedAt: DateTime.now(),
    );
    await saveStoryState(
      characterId: characterId,
      userId: userId,
      state: updated,
    );
  }

  // ─── 故事节点 ─────────────────────────────────────────

  /// 添加故事节点
  Future<void> addNode({
    required String characterId,
    required String userId,
    required StoryNode node,
  }) async {
    final current = await getStoryState(
      characterId: characterId,
      userId: userId,
    );
    final newNodes = Map<String, StoryNode>.from(current.nodes);
    newNodes[node.id] = node;
    final updated = current.copyWith(
      nodes: newNodes,
      updatedAt: DateTime.now(),
    );
    await saveStoryState(
      characterId: characterId,
      userId: userId,
      state: updated,
    );
  }

  /// 标记节点为已完成
  Future<void> completeNode({
    required String characterId,
    required String userId,
    required String nodeId,
  }) async {
    final current = await getStoryState(
      characterId: characterId,
      userId: userId,
    );
    final updated = current.markNodeCompleted(nodeId);
    await saveStoryState(
      characterId: characterId,
      userId: userId,
      state: updated,
    );
  }

  // ─── 目标管理 ─────────────────────────────────────────

  /// 添加未完成目标
  Future<void> addPendingGoal({
    required String characterId,
    required String userId,
    required String goal,
  }) async {
    final current = await getStoryState(
      characterId: characterId,
      userId: userId,
    );
    if (current.pendingGoals.contains(goal)) return;
    final updated = current.copyWith(
      pendingGoals: [...current.pendingGoals, goal],
      updatedAt: DateTime.now(),
    );
    await saveStoryState(
      characterId: characterId,
      userId: userId,
      state: updated,
    );
  }

  /// 完成目标
  Future<void> completePendingGoal({
    required String characterId,
    required String userId,
    required String goal,
  }) async {
    final current = await getStoryState(
      characterId: characterId,
      userId: userId,
    );
    final updated = current.copyWith(
      pendingGoals: current.pendingGoals.where((g) => g != goal).toList(),
      updatedAt: DateTime.now(),
    );
    await saveStoryState(
      characterId: characterId,
      userId: userId,
      state: updated,
    );
  }

  // ─── 事件记录 ─────────────────────────────────────────

  /// 添加最近事件
  Future<void> addRecentEvent({
    required String characterId,
    required String userId,
    required String event,
  }) async {
    final current = await getStoryState(
      characterId: characterId,
      userId: userId,
    );
    final updated = current.addRecentEvent(event);
    await saveStoryState(
      characterId: characterId,
      userId: userId,
      state: updated,
    );
  }

  // ─── 主线故事 ─────────────────────────────────────────

  /// 设置主线故事名称
  Future<void> setMainStoryline({
    required String characterId,
    required String userId,
    required String storyline,
  }) async {
    final current = await getStoryState(
      characterId: characterId,
      userId: userId,
    );
    final updated = current.copyWith(
      mainStoryline: storyline,
      updatedAt: DateTime.now(),
    );
    await saveStoryState(
      characterId: characterId,
      userId: userId,
      state: updated,
    );
  }

  /// 更新故事进度
  Future<void> setProgress({
    required String characterId,
    required String userId,
    required double progress,
  }) async {
    final current = await getStoryState(
      characterId: characterId,
      userId: userId,
    );
    final updated = current.copyWith(
      progress: progress.clamp(0.0, 1.0),
      updatedAt: DateTime.now(),
    );
    await saveStoryState(
      characterId: characterId,
      userId: userId,
      state: updated,
    );
  }

  // ─── 用户操作记录 ─────────────────────────────────────

  /// 记录用户对故事的操作
  Future<void> recordUserAction({
    required String characterId,
    required String userId,
    required String type,
    String? description,
    Map<String, dynamic>? data,
  }) async {
    final current = await getStoryState(
      characterId: characterId,
      userId: userId,
    );
    final action = StoryUserAction(
      id: _uuid.v4(),
      type: type,
      description: description,
      data: data,
      timestamp: DateTime.now(),
    );
    final updated = current.copyWith(
      userActions: [...current.userActions, action],
      updatedAt: DateTime.now(),
    );
    await saveStoryState(
      characterId: characterId,
      userId: userId,
      state: updated,
    );
  }

  // ─── 批量更新 ─────────────────────────────────────────

  /// 一次性更新多个字段
  Future<void> updateStoryState({
    required String characterId,
    required String userId,
    RelationshipStage? relationshipStage,
    StoryAtmosphere? atmosphere,
    String? mainStoryline,
    double? progress,
    List<String>? pendingGoals,
    List<String>? recentEvents,
  }) async {
    final current = await getStoryState(
      characterId: characterId,
      userId: userId,
    );
    final updated = current.copyWith(
      relationshipStage: relationshipStage,
      atmosphere: atmosphere,
      mainStoryline: mainStoryline,
      progress: progress,
      pendingGoals: pendingGoals,
      recentEvents: recentEvents,
      updatedAt: DateTime.now(),
    );
    await saveStoryState(
      characterId: characterId,
      userId: userId,
      state: updated,
    );
  }

  // ─── 查询 ─────────────────────────────────────────────

  /// 获取故事状态的简要摘要（供 AI 决策使用）
  Future<Map<String, dynamic>> getStoryContext({
    required String characterId,
    required String userId,
  }) async {
    final state = await getStoryState(
      characterId: characterId,
      userId: userId,
    );
    return {
      'relationshipStage': state.relationshipStage.name,
      'atmosphere': state.atmosphere.name,
      'mainStoryline': state.mainStoryline,
      'progress': state.progress,
      'pendingGoals': state.pendingGoals,
      'recentEvents': state.recentEvents.take(5).toList(),
      'currentNode': state.currentNode?.name,
      'completedNodes': state.completedNodeIds.length,
      'totalNodes': state.nodes.length,
    };
  }

  // ─── 清除 ─────────────────────────────────────────────

  /// 清除角色的故事状态
  Future<void> clearStoryState({
    required String characterId,
    required String userId,
  }) async {
    final key = _cacheKey(characterId, userId);
    _cache.remove(key);
    await _storage.sharedPreferences?.remove(_prefKey(characterId, userId));
  }
}
