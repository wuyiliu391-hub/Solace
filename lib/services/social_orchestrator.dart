// ============================================================
// 全生命周期数字生命世界 — Phase 4
// 社交调度器（重写版）：集成马斯洛内核 + 感知层 + 演化保护
// ============================================================

import 'package:flutter/foundation.dart';
import '../models/life_profile.dart';
import '../models/relationship_graph.dart';
import 'maslow_motivation_kernel.dart';
import 'perception_layer.dart';
import 'evolution_threshold_guard.dart' hide BehaviorTendency;
import 'llm_service.dart';

// ─────────────────────────────────────────────────
// 数据模型
// ─────────────────────────────────────────────────

/// 社交意图 — 角色想要做什么
class SocialIntent {
  /// 意图类型：'socialize', 'argue', 'befriend', 'avoid',
  /// 'seek_comfort', 'prove_self', 'pursue_dream', 'philosophize', etc.
  final String type;

  /// 目标角色 ID（可选，某些意图不需要目标）
  final String? targetId;

  /// 优先级（0-1，越高越迫切）
  final double priority;

  /// 触发原因描述
  final String reason;

  /// 来源需求层级（用于调试和日志）
  final String sourceLayer;

  const SocialIntent({
    required this.type,
    this.targetId,
    required this.priority,
    required this.reason,
    this.sourceLayer = '',
  });

  Map<String, dynamic> toJson() => {
        'type': type,
        'targetId': targetId,
        'priority': priority,
        'reason': reason,
        'sourceLayer': sourceLayer,
      };

  @override
  String toString() =>
      'SocialIntent(type=$type, target=$targetId, priority=${priority.toStringAsFixed(2)}, reason=$reason)';
}

/// 社交行为 — 具体化的社交动作
class SocialAction {
  /// 行为类型
  final String type;

  /// 目标角色 ID
  final String? targetId;

  /// 行为内容（LLM 生成的自然语言描述）
  final String content;

  /// 行为元数据
  final Map<String, dynamic> metadata;

  const SocialAction({
    required this.type,
    this.targetId,
    required this.content,
    this.metadata = const {},
  });

  Map<String, dynamic> toJson() => {
        'type': type,
        'targetId': targetId,
        'content': content,
        'metadata': metadata,
      };

  @override
  String toString() =>
      'SocialAction(type=$type, target=$targetId, content=${content.length > 50 ? '${content.substring(0, 50)}...' : content})';
}

/// 社交执行结果
class SocialResult {
  /// 是否成功执行
  final bool success;

  /// 执行的行为
  final SocialAction action;

  /// 产生的关系事件（如果有）
  final RelationshipEvent? relationshipEvent;

  /// 执行摘要（用于日志和调试）
  final String summary;

  const SocialResult({
    required this.success,
    required this.action,
    this.relationshipEvent,
    this.summary = '',
  });
}

// ─────────────────────────────────────────────────
// 社交调度器
// ─────────────────────────────────────────────────

/// 社交调度器 — 驱动角色间的社交行为
///
/// 核心流程：
/// 1. 马斯洛内核评估每个角色的需求状态
/// 2. 需求状态转化为社交意图
/// 3. 感知层提供目标角色的信息上下文
/// 4. LLM 具体化社交行为
/// 5. 执行行为并更新关系图谱
/// 6. 演化阈值保护器确保人格不会突变
class SocialOrchestrator {
  final MaslowMotivationKernel _maslow;
  final PerceptionLayer _perception;
  final EvolutionThresholdGuard _guard;
  final LlmService _llm;

  /// 关系图谱管理器
  final RelationshipGraphManager _graphManager;

  /// 执行历史（防重复）
  final Map<String, DateTime> _lastExecutionTime = {};

  /// 最小执行间隔
  static const Duration _minInterval = Duration(hours: 1);

  SocialOrchestrator({
    required MaslowMotivationKernel maslow,
    required PerceptionLayer perception,
    required EvolutionThresholdGuard guard,
    required LlmService llm,
    required RelationshipGraphManager graphManager,
  })  : _maslow = maslow,
        _perception = perception,
        _guard = guard,
        _llm = llm,
        _graphManager = graphManager;

  // ═══════════════════════════════════════════
  // 主调度入口
  // ═══════════════════════════════════════════

  /// 主调度入口：评估所有角色的社交意图并执行
  ///
  /// 流程：
  /// 1. 遍历所有角色
  /// 2. 为每个角色评估社交意图
  /// 3. 选择最高优先级的意图
  /// 4. 用 LLM 具体化行为
  /// 5. 执行行为
  Future<void> orchestrate(List<LifeProfile> profiles) async {
    debugPrint('SocialOrchestrator: 开始调度 ${profiles.length} 个角色');

    for (final profile in profiles) {
      // 跳过已故角色
      if (profile.lifeState != LifeState.alive) continue;

      // 检查执行间隔
      if (_isInCooldown(profile.id)) {
        debugPrint('SocialOrchestrator: ${profile.name} 冷却中，跳过');
        continue;
      }

      try {
        // 1. 评估意图
        final intent = await evaluateIntent(profile, profiles);
        if (intent == null) {
          debugPrint('SocialOrchestrator: ${profile.name} 无社交意图');
          continue;
        }

        debugPrint(
            'SocialOrchestrator: ${profile.name} 意图=${intent.type} '
            '目标=${intent.targetId} 优先级=${intent.priority.toStringAsFixed(2)}');

        // 2. 构建感知上下文
        final perceptionContext = _buildPerceptionContext(
          profile,
          intent.targetId,
          profiles,
        );

        // 3. LLM 具体化行为
        final action = await concretizeAction(
          profile,
          intent,
          perceptionContext,
        );

        // 4. 执行行为
        await execute(profile, action);

        // 5. 更新执行时间
        _lastExecutionTime[profile.id] = DateTime.now();

        debugPrint('SocialOrchestrator: ${profile.name} 执行完成: $action');
      } catch (e) {
        debugPrint('SocialOrchestrator: ${profile.name} 执行失败: $e');
      }
    }

    debugPrint('SocialOrchestrator: 调度完成');
  }

  // ═══════════════════════════════════════════
  // 意图评估
  // ═══════════════════════════════════════════

  /// 评估单个角色的社交意图
  ///
  /// 基于马斯洛需求动机内核，评估角色当前最强烈的需求，
  /// 并将其转化为具体的社交意图。
  Future<SocialIntent?> evaluateIntent(
    LifeProfile profile,
    List<LifeProfile> allProfiles,
  ) async {
    // 构建社交上下文
    final socialContext = _buildSocialContext(profile, allProfiles);

    // 马斯洛评估需求状态
    final maslowState = _maslow.evaluate(profile, socialContext);

    // 获取行为倾向
    final tendencies = _maslow.getBehaviorTendencies(maslowState, profile);

    if (tendencies.isEmpty) {
      debugPrint('SocialOrchestrator: ${profile.name} 无行为倾向');
      return null;
    }

    // 选择最高优先级的行为倾向
    final topTendency = tendencies.first;

    // 将行为倾向转化为社交意图
    final intent = _tendencyToIntent(topTendency, profile, allProfiles);

    return intent;
  }

  /// 将行为倾向转化为社交意图
  SocialIntent? _tendencyToIntent(
    BehaviorTendency tendency,
    LifeProfile profile,
    List<LifeProfile> allProfiles,
  ) {
    // 根据行为类型确定意图类型和目标
    switch (tendency.type) {
      case 'socialize':
        return _findSocialTarget(profile, allProfiles, tendency);

      case 'seek_friendship':
        return _findBefriendTarget(profile, allProfiles, tendency);

      case 'seek_romance':
        return _findRomanceTarget(profile, allProfiles, tendency);

      case 'seek_comfort':
        return _findComfortTarget(profile, allProfiles, tendency);

      case 'prove_self':
        return SocialIntent(
          type: 'prove_self',
          priority: tendency.priority,
          reason: tendency.reason,
          sourceLayer: tendency.sourceLayer.name,
        );

      case 'pursue_dream':
        return SocialIntent(
          type: 'pursue_dream',
          priority: tendency.priority,
          reason: tendency.reason,
          sourceLayer: tendency.sourceLayer.name,
        );

      case 'philosophize':
        return SocialIntent(
          type: 'philosophize',
          priority: tendency.priority,
          reason: tendency.reason,
          sourceLayer: tendency.sourceLayer.name,
        );

      case 'avoid_conflict':
        return _findAvoidTarget(profile, allProfiles, tendency);

      default:
        // 未知行为类型，跳过
        debugPrint('SocialOrchestrator: 未知行为类型 ${tendency.type}');
        return null;
    }
  }

  /// 寻找社交目标
  SocialIntent? _findSocialTarget(
    LifeProfile profile,
    List<LifeProfile> allProfiles,
    BehaviorTendency tendency,
  ) {
    // 找到最亲密的角色
    String? bestTargetId;
    double bestAffinity = -2.0;

    for (final other in allProfiles) {
      if (other.id == profile.id) continue;
      if (other.lifeState != LifeState.alive) continue;

      final graph = _graphManager.getGraph(profile.id, other.id);
      final affinity = graph?.compositeAffinity ?? 0.0;

      if (affinity > bestAffinity) {
        bestAffinity = affinity;
        bestTargetId = other.id;
      }
    }

    if (bestTargetId == null) return null;

    return SocialIntent(
      type: 'socialize',
      targetId: bestTargetId,
      priority: tendency.priority,
      reason: tendency.reason,
      sourceLayer: tendency.sourceLayer.name,
    );
  }

  /// 寻找交友目标
  SocialIntent? _findBefriendTarget(
    LifeProfile profile,
    List<LifeProfile> allProfiles,
    BehaviorTendency tendency,
  ) {
    // 找到熟悉度最低但有接触的角色（新朋友潜力）
    String? bestTargetId;
    double bestScore = -1.0;

    for (final other in allProfiles) {
      if (other.id == profile.id) continue;
      if (other.lifeState != LifeState.alive) continue;

      final graph = _graphManager.getGraph(profile.id, other.id);
      if (graph == null) continue;

      // 有一定熟悉度但还不是朋友的优先
      final familiarity = graph.familiarity;
      final intimacy = graph.intimacy;

      if (familiarity > 0.2 && familiarity < 0.6 && intimacy < 0.3) {
        final score = familiarity * 0.5 + (1 - intimacy) * 0.5;
        if (score > bestScore) {
          bestScore = score;
          bestTargetId = other.id;
        }
      }
    }

    if (bestTargetId == null) return null;

    return SocialIntent(
      type: 'befriend',
      targetId: bestTargetId,
      priority: tendency.priority,
      reason: tendency.reason,
      sourceLayer: tendency.sourceLayer.name,
    );
  }

  /// 寻找恋爱目标
  SocialIntent? _findRomanceTarget(
    LifeProfile profile,
    List<LifeProfile> allProfiles,
    BehaviorTendency tendency,
  ) {
    // 找到亲密度最高但还没确定关系的角色
    String? bestTargetId;
    double bestScore = -1.0;

    for (final other in allProfiles) {
      if (other.id == profile.id) continue;
      if (other.lifeState != LifeState.alive) continue;

      final graph = _graphManager.getGraph(profile.id, other.id);
      if (graph == null) continue;

      // 高亲密 + 高激情 + 低承诺 = 暗恋/暧昧
      if (graph.intimacy > 0.4 &&
          graph.passion > 0.3 &&
          graph.commitment < 0.5) {
        final score = graph.intimacy * 0.4 + graph.passion * 0.4 + graph.familiarity * 0.2;
        if (score > bestScore) {
          bestScore = score;
          bestTargetId = other.id;
        }
      }
    }

    if (bestTargetId == null) return null;

    return SocialIntent(
      type: 'seek_romance',
      targetId: bestTargetId,
      priority: tendency.priority,
      reason: tendency.reason,
      sourceLayer: tendency.sourceLayer.name,
    );
  }

  /// 寻找安慰目标
  SocialIntent? _findComfortTarget(
    LifeProfile profile,
    List<LifeProfile> allProfiles,
    BehaviorTendency tendency,
  ) {
    // 找到最亲密的角色寻求安慰
    String? bestTargetId;
    double bestAffinity = -2.0;

    for (final other in allProfiles) {
      if (other.id == profile.id) continue;
      if (other.lifeState != LifeState.alive) continue;

      final graph = _graphManager.getGraph(profile.id, other.id);
      if (graph == null) continue;

      // 信任度高 + 亲密的角色
      if (graph.trust > 0.3 && graph.intimacy > 0.3) {
        final affinity = graph.compositeAffinity;
        if (affinity > bestAffinity) {
          bestAffinity = affinity;
          bestTargetId = other.id;
        }
      }
    }

    if (bestTargetId == null) return null;

    return SocialIntent(
      type: 'seek_comfort',
      targetId: bestTargetId,
      priority: tendency.priority,
      reason: tendency.reason,
      sourceLayer: tendency.sourceLayer.name,
    );
  }

  /// 寻找回避目标
  SocialIntent? _findAvoidTarget(
    LifeProfile profile,
    List<LifeProfile> allProfiles,
    BehaviorTendency tendency,
  ) {
    // 找到紧张度最高的关系
    String? bestTargetId;
    double bestTension = 0.0;

    for (final other in allProfiles) {
      if (other.id == profile.id) continue;
      if (other.lifeState != LifeState.alive) continue;

      final graph = _graphManager.getGraph(profile.id, other.id);
      if (graph == null) continue;

      if (graph.tension > bestTension) {
        bestTension = graph.tension;
        bestTargetId = other.id;
      }
    }

    if (bestTargetId == null || bestTension < 0.3) return null;

    return SocialIntent(
      type: 'avoid',
      targetId: bestTargetId,
      priority: tendency.priority,
      reason: tendency.reason,
      sourceLayer: tendency.sourceLayer.name,
    );
  }

  // ═══════════════════════════════════════════
  // 行为具体化
  // ═══════════════════════════════════════════

  /// 用 LLM 具体化行为
  ///
  /// 将抽象的社交意图转化为具体的社交行为内容。
  /// 使用感知层提供的目标角色信息作为上下文。
  Future<SocialAction> concretizeAction(
    LifeProfile profile,
    SocialIntent intent,
    String perceptionContext,
  ) async {
    // 构建提示词
    final prompt = _buildActionPrompt(profile, intent, perceptionContext);

    try {
      // 调用 LLM 生成行为内容
      final response = await _llm.chat(
        userId: profile.id,
        message: prompt,
        systemPrompt: _buildActionSystemPrompt(profile, intent),
      );

      final content = response.content.trim();

      return SocialAction(
        type: intent.type,
        targetId: intent.targetId,
        content: content,
        metadata: {
          'intent': intent.toJson(),
          'timestamp': DateTime.now().toIso8601String(),
        },
      );
    } catch (e) {
      debugPrint('SocialOrchestrator: LLM 调用失败: $e');

      // 降级：使用模板化行为
      return _fallbackAction(profile, intent);
    }
  }

  /// 构建行为系统提示词
  String _buildActionSystemPrompt(LifeProfile profile, SocialIntent intent) {
    final buffer = StringBuffer();

    buffer.writeln('你是一个数字生命的社交行为生成器。');
    buffer.writeln('你的任务是根据角色的性格和当前需求，生成具体的社交行为描述。');
    buffer.writeln();
    buffer.writeln('角色信息：');
    buffer.writeln('- 名字：${profile.name}');
    buffer.writeln('- 年龄：${profile.biologicalAge}岁');
    buffer.writeln('- 生命阶段：${profile.currentStage}');
    buffer.writeln();
    buffer.writeln('行为要求：');
    buffer.writeln('- 用第一人称描述');
    buffer.writeln('- 描述要具体、生动、符合角色性格');
    buffer.writeln('- 长度控制在 1-2 句话');
    buffer.writeln('- 不要包含对话内容，只描述行为');

    return buffer.toString();
  }

  /// 构建行为提示词
  String _buildActionPrompt(
    LifeProfile profile,
    SocialIntent intent,
    String perceptionContext,
  ) {
    final buffer = StringBuffer();

    buffer.writeln('【社交行为生成】');
    buffer.writeln();
    buffer.writeln('意图类型：${_intentTypeLabel(intent.type)}');
    buffer.writeln('触发原因：${intent.reason}');

    if (intent.targetId != null) {
      buffer.writeln();
      buffer.writeln('目标角色信息：');
      buffer.writeln(perceptionContext);
    }

    buffer.writeln();
    buffer.writeln('请生成具体的社交行为描述（1-2句话，第一人称）：');

    return buffer.toString();
  }

  /// 降级行为（LLM 调用失败时使用）
  SocialAction _fallbackAction(LifeProfile profile, SocialIntent intent) {
    String content;

    switch (intent.type) {
      case 'socialize':
        content = '${profile.name}决定去和朋友们聊聊天，放松一下心情。';
        break;
      case 'befriend':
        content = '${profile.name}鼓起勇气，向对方打了个招呼，试图建立新的友谊。';
        break;
      case 'seek_romance':
        content = '${profile.name}心中涌起一股暖意，想要更靠近对方。';
        break;
      case 'seek_comfort':
        content = '${profile.name}感到有些脆弱，想要找一个信任的人倾诉。';
        break;
      case 'avoid':
        content = '${profile.name}决定暂时避开这段紧张的关系，给自己一些空间。';
        break;
      case 'prove_self':
        content = '${profile.name}渴望证明自己的价值，想要做出一些成绩。';
        break;
      case 'pursue_dream':
        content = '${profile.name}心中有一个梦想，决定开始为之努力。';
        break;
      case 'philosophize':
        content = '${profile.name}陷入了沉思，思考着生命的意义。';
        break;
      default:
        content = '${profile.name}想要做些什么来满足自己的需求。';
    }

    return SocialAction(
      type: intent.type,
      targetId: intent.targetId,
      content: content,
      metadata: {
        'intent': intent.toJson(),
        'fallback': true,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
  }

  // ═══════════════════════════════════════════
  // 行为执行
  // ═══════════════════════════════════════════

  /// 执行社交行为
  ///
  /// 根据行为类型：
  /// 1. 更新关系图谱
  /// 2. 记录关系事件
  /// 3. 生成执行摘要
  Future<void> execute(LifeProfile profile, SocialAction action) async {
    debugPrint('SocialOrchestrator: 执行行为 $action');

    // 根据行为类型生成关系事件
    final event = _createRelationshipEvent(profile, action);

    if (event != null && action.targetId != null) {
      // 更新关系图谱
      _graphManager.addEvent(profile.id, action.targetId!, event);
      debugPrint(
          'SocialOrchestrator: 关系事件已记录 - ${event.type.label} '
          '影响=${event.impact.toStringAsFixed(2)}');
    }

    // TODO: 对接 SocialActionExecutor 执行具体行为
    // 目前只记录关系事件，后续需要对接：
    // - 串门 → SocialActionExecutor._executeVisit
    // - 好友请求 → SocialActionExecutor._executeFriendRequest
    // - 私聊 → SocialActionExecutor._executePrivateChat
    // - 动态 → SocialActionExecutor._executeMoment
  }

  /// 根据行为类型创建关系事件
  RelationshipEvent? _createRelationshipEvent(
    LifeProfile profile,
    SocialAction action,
  ) {
    final now = DateTime.now();
    final id = '${profile.id}_${action.targetId}_${now.millisecondsSinceEpoch}';

    switch (action.type) {
      case 'socialize':
        return RelationshipEvent(
          id: id,
          timestamp: now,
          description: '${profile.name}与对方进行了愉快的交流',
          impact: 0.1,
          type: RelationshipEventType.sharedExperience,
          intensity: 0.3,
        );

      case 'befriend':
        return RelationshipEvent(
          id: id,
          timestamp: now,
          description: '${profile.name}主动向对方示好，试图建立友谊',
          impact: 0.15,
          type: RelationshipEventType.kindness,
          intensity: 0.4,
        );

      case 'seek_romance':
        return RelationshipEvent(
          id: id,
          timestamp: now,
          description: '${profile.name}向对方表达了特别的好感',
          impact: 0.2,
          type: RelationshipEventType.kindness,
          intensity: 0.5,
          isPublic: false,
        );

      case 'seek_comfort':
        return RelationshipEvent(
          id: id,
          timestamp: now,
          description: '${profile.name}向对方寻求安慰和支持',
          impact: 0.1,
          type: RelationshipEventType.support,
          intensity: 0.3,
        );

      case 'avoid':
        return RelationshipEvent(
          id: id,
          timestamp: now,
          description: '${profile.name}选择暂时回避与对方的接触',
          impact: -0.05,
          type: RelationshipEventType.misunderstanding,
          intensity: 0.2,
        );

      case 'prove_self':
      case 'pursue_dream':
      case 'philosophize':
        // 这些是自我实现类行为，不直接产生关系事件
        return null;

      default:
        return null;
    }
  }

  // ═══════════════════════════════════════════
  // 内部辅助
  // ═══════════════════════════════════════════

  /// 构建社交上下文（给马斯洛内核用）
  SocialContext _buildSocialContext(
    LifeProfile profile,
    List<LifeProfile> allProfiles,
  ) {
    final relationships = _graphManager.getRelationships(profile.id);

    // 计算距上次社交的天数
    int daysSinceLastSocial = 999;
    for (final rel in relationships) {
      if (rel.events.isNotEmpty) {
        final lastEvent = rel.events.last;
        final days = DateTime.now().difference(lastEvent.timestamp).inDays;
        if (days < daysSinceLastSocial) daysSinceLastSocial = days;
      }
    }

    // 是否有亲密关系
    final hasIntimateRelation = relationships.any((r) => r.isIntimate);

    // 是否有新人
    final hasNewcomer = relationships.any((r) => r.familiarity < 0.3);

    // 是否处于冲突
    final inDanger = relationships.any((r) => r.isInConflict);

    return SocialContext(
      daysSinceLastSocial: daysSinceLastSocial,
      hasIntimateRelation: hasIntimateRelation,
      hasNewcomer: hasNewcomer,
      inDanger: inDanger,
      hasShelter: true,
      hasFood: true,
    );
  }

  /// 构建感知上下文（给 LLM 用）
  String _buildPerceptionContext(
    LifeProfile observer,
    String? targetId,
    List<LifeProfile> allProfiles,
  ) {
    if (targetId == null) return '';

    final target = allProfiles.where((p) => p.id == targetId).firstOrNull;
    if (target == null) return '';

    final relationship = _graphManager.getGraph(observer.id, targetId);

    return PerceptionLayer.buildPerceptionFromModels(
      observer: observer,
      target: target,
      relationship: relationship,
    );
  }

  /// 检查是否在冷却期
  bool _isInCooldown(String profileId) {
    final lastTime = _lastExecutionTime[profileId];
    if (lastTime == null) return false;
    return DateTime.now().difference(lastTime) < _minInterval;
  }

  /// 意图类型标签
  String _intentTypeLabel(String type) {
    switch (type) {
      case 'socialize':
        return '社交';
      case 'befriend':
        return '交友';
      case 'seek_romance':
        return '追求爱情';
      case 'seek_comfort':
        return '寻求安慰';
      case 'avoid':
        return '回避冲突';
      case 'prove_self':
        return '证明自我';
      case 'pursue_dream':
        return '追求梦想';
      case 'philosophize':
        return '哲学思考';
      default:
        return type;
    }
  }
}

/// 扩展：List.firstOrNull
extension _ListExtension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
