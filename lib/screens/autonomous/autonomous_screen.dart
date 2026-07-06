// 性能优化 -- 耗电与老手机兼容
// ============================================================
// 全生命周期数字生命世界 — 前端修复
// AI 自主社交控制面板 v2：实时动态流 + 角色状态概览
// ============================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../repositories/local_storage_repository.dart';
import '../../repositories/database_service.dart';
import '../../services/core_hub.dart';
import '../../services/heartbeat_service.dart';
import '../../services/memory_engine.dart';
import '../../models/ai_character.dart';
import '../../models/moment.dart';
import '../../models/task_request.dart';
import '../../services/action_request_builder.dart';

// ═══════════════════════════════════════════════════════════
// 社交动态条目模型
// ═══════════════════════════════════════════════════════════

/// 社交互动类型枚举
enum SocialEventType {
  like,       // 点赞
  comment,    // 评论
  visit,      // 串门
  friend,     // 加好友
  conflict,   // 吵架
  reflection, // 反思
  moment,     // 发动态
  chat,       // 聊天
  unknown,
}

/// 从 social_memories 表解析出的社交动态条目
class SocialEvent {
  final String id;
  final String characterId;
  final String characterName;
  final String targetCharacterId;
  final String targetCharacterName;
  final SocialEventType type;
  final String content;
  final DateTime timestamp;

  SocialEvent({
    required this.id,
    required this.characterId,
    required this.characterName,
    required this.targetCharacterId,
    required this.targetCharacterName,
    required this.type,
    required this.content,
    required this.timestamp,
  });

  /// 根据 interactionType 字符串推断事件类型
  static SocialEventType parseType(String interactionType) {
    switch (interactionType) {
      case 'social_moment_like':
      case 'like':
        return SocialEventType.like;
      case 'social_moment_comment':
      case 'comment':
        return SocialEventType.comment;
      case 'social_visit':
      case 'visit':
        return SocialEventType.visit;
      case 'social_friend_request':
      case 'friend_request':
      case 'friend':
        return SocialEventType.friend;
      case 'social_moment':
      case 'moment':
        return SocialEventType.moment;
      case 'social_private_chat':
      case 'chat':
        return SocialEventType.chat;
      case 'social_daily_activity':
      case 'daily_activity':
        return SocialEventType.reflection;
      default:
        // 根据内容关键词二次推断
        return SocialEventType.unknown;
    }
  }

  /// 事件图标
  IconData get icon {
    switch (type) {
      case SocialEventType.like:
        return Icons.favorite;
      case SocialEventType.comment:
        return Icons.chat_bubble;
      case SocialEventType.visit:
        return Icons.door_front_door;
      case SocialEventType.friend:
        return Icons.handshake;
      case SocialEventType.conflict:
        return Icons.bolt;
      case SocialEventType.reflection:
        return Icons.lightbulb;
      case SocialEventType.moment:
        return Icons.auto_awesome;
      case SocialEventType.chat:
        return Icons.forum;
      case SocialEventType.unknown:
        return Icons.circle;
    }
  }

  /// 事件颜色
  Color get color {
    switch (type) {
      case SocialEventType.like:
        return Colors.red;
      case SocialEventType.comment:
        return Colors.blue;
      case SocialEventType.visit:
        return Colors.green;
      case SocialEventType.friend:
        return Colors.pink;
      case SocialEventType.conflict:
        return Colors.orange;
      case SocialEventType.reflection:
        return Colors.purple;
      case SocialEventType.moment:
        return Colors.amber;
      case SocialEventType.chat:
        return Colors.teal;
      case SocialEventType.unknown:
        return Colors.grey;
    }
  }

  /// 事件标签
  String get label {
    switch (type) {
      case SocialEventType.like:
        return '点赞';
      case SocialEventType.comment:
        return '评论';
      case SocialEventType.visit:
        return '串门';
      case SocialEventType.friend:
        return '加好友';
      case SocialEventType.conflict:
        return '争执';
      case SocialEventType.reflection:
        return '反思';
      case SocialEventType.moment:
        return '发动态';
      case SocialEventType.chat:
        return '聊天';
      case SocialEventType.unknown:
        return '互动';
    }
  }
}

// ═══════════════════════════════════════════════════════════
// 主页面
// ═══════════════════════════════════════════════════════════

/// AI 自主社交控制面板
///
/// 实时显示心跳状态、Token 消耗、角色活跃度、活动日志
/// 提供手动触发按钮和二级页面导航
class AutonomousScreen extends StatefulWidget {
  const AutonomousScreen({super.key});

  @override
  State<AutonomousScreen> createState() => _AutonomousScreenState();
}

class _AutonomousScreenState extends State<AutonomousScreen> {
  bool _newWorldMode = false;
  int _tokenConsumed = 0;
  int _pendingTasks = 0;

  DateTime? _lastHeartbeat;
  bool _heartbeatRunning = false;

  List<AICharacter> _characters = [];
  int _activeCharacterCount = 0;

  Map<String, int> _actionCounts = {};

  List<String> _recentLogs = [];
  String _logFilter = 'all';
  Timer? _refreshTimer;

  bool _isTriggering = false; // 手动触发中
  String? _triggerFeedback; // 手动触发实时反馈

  // ── 新增：实时动态流 ──
  List<SocialEvent> _socialFeed = [];
  bool _feedLoading = true;

  // 全生命周期数字生命世界 — 前端修复
  // 今日活跃度统计
  int _todayInteractions = 0;
  int _todayNewRelations = 0;
  int _todayEmotionChanges = 0;

  // ── 新增：角色状态概览 ──
  Map<String, String> _characterEmotions = {};   // characterId → emoji
  Map<String, String> _characterMaslow = {};     // characterId → 最强需求
  Map<String, String> _characterLastSocial = {}; // characterId → 最近社交行为
  Map<String, String> _characterLifeStage = {};  // characterId → 生命阶段

  // 性能优化：使用 ValueNotifier 减少不必要的 setState 全量重建
  final ValueNotifier<bool> _dataChanged = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();
    _loadState();
    // 性能优化：Timer 从 5 秒改为 30 秒，大幅减少 CPU 唤醒和 DB 查询
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) {
        _loadState();
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _dataChanged.dispose(); // 性能优化：释放 ValueNotifier
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════
  // 数据加载
  // ═══════════════════════════════════════════════════════════

  // 性能优化：合并setState调用，原来每次刷新触发4次setState，现在1次
  void _loadState() {
    final hub = CoreHub.instance;
    final heartbeat =
        RepositoryProvider.of<HeartbeatService>(context, listen: false);
    final heartbeatStatus = heartbeat.getStatus();

    // 同步数据直接赋值，不触发重建
    _newWorldMode = hub.isNewWorldMode;
    _tokenConsumed = hub.tokenConsumed;
    _pendingTasks = hub.taskQueue.pendingCount;

    _heartbeatRunning =
        heartbeatStatus['isRunning'] as bool? ?? false;
    _lastHeartbeat = heartbeatStatus['lastHeartbeat'] != null
        ? DateTime.tryParse(
            heartbeatStatus['lastHeartbeat'] as String)
        : null;

    _actionCounts = {};
    for (final entry in hub.audit.entries) {
      if (entry.category == 'task' &&
          entry.action == 'task_completed') {
        final detail = entry.detail ?? '';
        final actionType = detail.split(' — ').first;
        _actionCounts[actionType] =
            (_actionCounts[actionType] ?? 0) + 1;
      }
    }

    _recentLogs = hub.audit
        .getRecent(50)
        .map((e) => e.toString())
        .toList();

    // 一次setState更新同步数据
    if (mounted) setState(() {});

    // 异步数据合并加载，最终也只触发一次setState
    _loadAllAsyncData();
  }

  /// 性能优化：并行加载所有异步数据，合并为一次setState
  Future<void> _loadAllAsyncData() async {
    try {
      final storage =
          RepositoryProvider.of<LocalStorageRepository>(context,
              listen: false);

      final chars = await storage.getAllAICharacters();

      // 并行加载社交动态和今日活跃度
      final feedFuture = _loadSocialFeedData();
      final activityFuture = _loadTodayActivityData();

      final results = await Future.wait([feedFuture, activityFuture]);
      if (!mounted) return;

      final feedEvents = results[0] as List<SocialEvent>;
      final activityData = results[1] as Map<String, int>;

      setState(() {
        _characters = chars;
        _activeCharacterCount =
            _newWorldMode
                ? chars.where((c) => c.isOnline).length
                : 0;
        _socialFeed = feedEvents;
        _feedLoading = false;
        _todayInteractions = activityData['interactions'] ?? 0;
        _todayNewRelations = activityData['newRelations'] ?? 0;
        _todayEmotionChanges = activityData['emotionChanges'] ?? 0;
      });

      // 角色状态概览延迟加载（非关键路径）
      _loadCharacterStatuses(chars);
    } catch (e) {
      debugPrint('AutonomousScreen: _loadAllAsyncData failed — $e');
    }
  }

  /// 性能优化：返回数据而非直接setState
  Future<List<SocialEvent>> _loadSocialFeedData() async {
    try {
      final db = await DatabaseService.instance.database;
      final rows = await db.query(
        'social_memories',
        orderBy: 'timestamp DESC',
        limit: 50,
      );

      final nameMap = <String, String>{};
      for (final c in _characters) {
        nameMap[c.id] = c.name;
      }

      return rows.map((row) {
        final charId = row['characterId'] as String? ?? '';
        final targetId = row['targetCharacterId'] as String? ?? '';
        return SocialEvent(
          id: row['id'] as String? ?? '',
          characterId: charId,
          characterName: nameMap[charId] ?? charId,
          targetCharacterId: targetId,
          targetCharacterName: nameMap[targetId] ?? targetId,
          type: SocialEvent.parseType(row['interactionType'] as String? ?? ''),
          content: row['content'] as String? ?? '',
          timestamp: DateTime.tryParse(row['timestamp'] as String? ?? '') ?? DateTime.now(),
        );
      }).toList();
    } catch (e) {
      debugPrint('AutonomousScreen: loadSocialFeed failed — $e');
      return [];
    }
  }

  /// 性能优化：合并3条SQL为1条，返回数据而非setState
  Future<Map<String, int>> _loadTodayActivityData() async {
    try {
      final db = await DatabaseService.instance.database;
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day).toIso8601String();

      final result = await db.rawQuery('''
        SELECT
          COUNT(*) as interactions,
          SUM(CASE WHEN interactionType IN ('friend', 'friend_request', 'social_friend_request') THEN 1 ELSE 0 END) as newRelations,
          SUM(CASE WHEN emotionTag IS NOT NULL AND emotionTag != '' THEN 1 ELSE 0 END) as emotionChanges
        FROM social_memories
        WHERE timestamp >= ?
      ''', [todayStart]);

      final row = result.first;
      return {
        'interactions': (row['interactions'] as int?) ?? 0,
        'newRelations': (row['newRelations'] as int?) ?? 0,
        'emotionChanges': (row['emotionChanges'] as int?) ?? 0,
      };
    } catch (e) {
      debugPrint('加载今日活跃度失败: $e');
      return {'interactions': 0, 'newRelations': 0, 'emotionChanges': 0};
    }
  }

  // 性能优化：_loadCharacters 已合并到 _loadAllAsyncData，保留空方法兼容调用
  Future<void> _loadCharacters() async {}

  /// 加载角色情绪、最近社交行为、生命阶段
  /// 性能优化：复用单个 MemoryEngine 实例，避免每个角色都创建新实例
  Future<void> _loadCharacterStatuses(List<AICharacter> chars) async {
    final emotions = <String, String>{};
    final maslow = <String, String>{};
    final lastSocial = <String, String>{};

    // 性能优化：复用同一个 storage 和 memEngine 实例
    final storage =
        RepositoryProvider.of<LocalStorageRepository>(context,
            listen: false);
    final memEngine = MemoryEngine(storage);

    for (final c in chars) {
      emotions[c.id] = _inferEmotionFromStatus(c.currentStatus);
      maslow[c.id] = '—';
      _characterLifeStage[c.id] = '—';

      try {
        final socialMemories = await memEngine.loadSocialMemories(c.id);
        if (socialMemories.isNotEmpty) {
          lastSocial[c.id] = _truncate(socialMemories.first.content, 20);
        }
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        _characterEmotions = emotions;
        _characterMaslow = maslow;
        _characterLastSocial = lastSocial;
      });
    }
  }

  // 性能优化：_loadSocialFeed 已合并到 _loadAllAsyncData，保留兼容调用
  Future<void> _loadSocialFeed() async {
    _socialFeed = await _loadSocialFeedData();
    _feedLoading = false;
    if (mounted) setState(() {});
  }

  // 性能优化：_loadTodayActivity 已合并到 _loadAllAsyncData，保留兼容调用
  Future<void> _loadTodayActivity() async {
    final data = await _loadTodayActivityData();
    if (mounted) {
      setState(() {
        _todayInteractions = data['interactions'] ?? 0;
        _todayNewRelations = data['newRelations'] ?? 0;
        _todayEmotionChanges = data['emotionChanges'] ?? 0;
      });
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 交互操作
  // ═══════════════════════════════════════════════════════════

  Future<void> _toggleMode(bool value) async {
    await CoreHub.instance.setNewWorldMode(value);
    _loadState();
  }

  Future<void> _resetTokens() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重置计数'),
        content: const Text('确定要重新开始计数吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await CoreHub.instance.resetTokenCounter();
      _loadState();
    }
  }

  /// 手动触发一个社交动作
  Future<void> _triggerAction(String actionType) async {
    if (_characters.length < 2) {
      _showToast('至少需要 2 个角色');
      return;
    }

    setState(() {
      _isTriggering = true;
      _triggerFeedback = null;
    });
    try {
      final hub = CoreHub.instance;
      final storage =
          RepositoryProvider.of<LocalStorageRepository>(context,
              listen: false);

      // 随机挑两个不同的角色
      final shuffled = List<AICharacter>.from(_characters)
        ..shuffle();
      final source = shuffled.first;
      final target = shuffled[1];

      // 实时反馈
      final feedbackMsg = _buildTriggerFeedback(
          actionType, source.name, target.name);
      setState(() => _triggerFeedback = feedbackMsg);

      final builder = ActionRequestBuilder(
          characterId: source.id);
      TaskRequest? task;

      switch (actionType) {
        case 'visit':
          task = builder.generateVisitAction(
            targetCharacterId: target.id,
            purpose: 'casual_visit',
          );
          break;
        case 'friend':
          task = builder.generateFriendRequest(
            targetCharacterId: target.id,
            reason: '想和你做朋友',
          );
          break;
        case 'moment':
          task = builder.generateMomentAction(
            visibility: 'public',
          );
          break;
        case 'comment': {
          try {
            final moments = await storage.getAllMoments();
            final visibleMoments = moments
                .where((m) => m.source == MomentSource.normal)
                .toList();
            if (visibleMoments.isNotEmpty) {
              final moment = visibleMoments.first;
              task = builder.generateMomentComment(
                momentId: moment.id,
                targetCharacterId: moment.userId,
              );
            } else {
              _showToast('朋友圈暂无动态可评论，先发一条动态');
              return;
            }
          } catch (e) {
            _showToast('获取朋友圈动态失败: $e');
            return;
          }
          break;
        }
        case 'like': {
          task = builder.generateMomentLike(
            momentId: '',
            targetCharacterId: '',
          );
          break;
        }
        case 'all':
          await _triggerAll();
          return;
      }

      if (task != null) {
        final submitted = await hub.submitTask(task);
        await hub.processQueue();

        if (submitted.status == 'rejected' || submitted.status == 'failed') {
          _showToast('${submitted.result ?? "执行失败"}');
          setState(() => _triggerFeedback = '❌ 执行失败：${submitted.result ?? "未知错误"}');
        } else {
          final resultMsg = submitted.result ?? actionType;
          _showToast('$resultMsg');
          setState(() => _triggerFeedback = '✅ 完成：$resultMsg');
        }
      }
      _loadState();
      // 刷新动态流
      _loadSocialFeed();
    } catch (e) {
      _showToast('触发失败: $e');
      setState(() => _triggerFeedback = '❌ 触发失败: $e');
    } finally {
      setState(() => _isTriggering = false);
    }
  }

  Future<void> _triggerAll() async {
    final hub = CoreHub.instance;
    final storage = RepositoryProvider.of<LocalStorageRepository>(
      context,
      listen: false,
    );
    final types = ['visit', 'friend', 'moment', 'comment', 'like'];
    int success = 0;

    for (final type in types) {
      try {
        if (_characters.length < 2) break;
        final shuffled = List<AICharacter>.from(_characters)
          ..shuffle();
        final source = shuffled.first;
        final target = shuffled[1];

        setState(() => _triggerFeedback =
            '🔄 正在执行 ${_typeLabel(type)}：${source.name} → ${target.name}');

        final builder = ActionRequestBuilder(
            characterId: source.id);

        TaskRequest? task;
        final moments = type == 'comment' || type == 'like'
            ? (await storage.getAllMoments())
                .where((m) => m.source == MomentSource.normal)
                .toList()
            : null;

        switch (type) {
          case 'visit':
            task = builder.generateVisitAction(
              targetCharacterId: target.id,
            );
            break;
          case 'friend':
            task = builder.generateFriendRequest(
              targetCharacterId: target.id,
            );
            break;
          case 'moment':
            task = builder.generateMomentAction();
            break;
          case 'comment':
            if (moments != null && moments.isNotEmpty) {
              task = builder.generateMomentComment(
                momentId: moments.first.id,
                targetCharacterId: moments.first.userId,
              );
            }
            break;
          case 'like':
            task = builder.generateMomentLike(
              momentId: '',
              targetCharacterId: '',
            );
            break;
        }
        if (task != null) {
          await hub.submitTask(task);
          await hub.processQueue();
          success++;
        }
      } catch (_) {}
    }
    _showToast('触发了 $success 个动作');
    setState(() => _triggerFeedback = '✅ 全部完成：$success 个动作');
    _loadState();
    _loadSocialFeed();
  }

  // ═══════════════════════════════════════════════════════════
  // UI 构建
  // ═══════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 自主'),
        centerTitle: true,
        elevation: 0,
        actions: [
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: () {
              _loadState();
              _loadSocialFeed();
            },
            tooltip: '刷新',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          _loadState();
          _loadSocialFeed();
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            // 1. 顶部状态卡片（含自主模式开关 + 心跳 + 角色数）
            _buildTopStatusCard(colorScheme),
            const SizedBox(height: 16),

            // 2. 实时动态流（核心新增）
            if (_newWorldMode) _buildSocialFeedSection(colorScheme),
            if (_newWorldMode) const SizedBox(height: 16),

            // 全生命周期数字生命世界 — 前端修复
            // 今日活跃度统计
            if (_newWorldMode) _buildTodayActivityCard(colorScheme),
            if (_newWorldMode) const SizedBox(height: 16),

            // 3. 角色状态概览
            if (_newWorldMode && _characters.isNotEmpty)
              _buildCharacterStatusOverview(colorScheme),
            if (_newWorldMode && _characters.isNotEmpty)
              const SizedBox(height: 16),

            // 4. 手动触发区域
            _buildTriggerSection(colorScheme),
            const SizedBox(height: 16),

            // 触发反馈
            if (_triggerFeedback != null) _buildTriggerFeedbackCard(colorScheme),
            if (_triggerFeedback != null) const SizedBox(height: 16),

            _buildActionButtons(colorScheme),
            const SizedBox(height: 16),
            if (_actionCounts.isNotEmpty) ...[
              _buildApiStatsSection(colorScheme),
              const SizedBox(height: 16),
            ],
            _buildLogsSection(colorScheme),
          ],
        ),
      ),
    );
  }

  // ─── 1. 顶部状态卡片（合并主开关 + 运行状态） ───

  Widget _buildTopStatusCard(ColorScheme colorScheme) {
    // 状态颜色：运行中=绿，已暂停=灰，异常=红
    final Color statusColor;
    final String statusText;
    final IconData statusIcon;

    if (_newWorldMode && _heartbeatRunning) {
      statusColor = Colors.green;
      statusText = '运行中';
      statusIcon = Icons.check_circle;
    } else if (_newWorldMode && !_heartbeatRunning) {
      statusColor = Colors.orange;
      statusText = '心跳异常';
      statusIcon = Icons.warning_amber;
    } else {
      statusColor = Colors.grey;
      statusText = '已暂停';
      statusIcon = Icons.pause_circle;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _newWorldMode
            ? colorScheme.primaryContainer.withOpacity(0.3)
            : colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _newWorldMode
              ? colorScheme.primary.withOpacity(0.5)
              : colorScheme.outlineVariant,
        ),
      ),
      child: Column(
        children: [
          // 第一行：主开关
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  statusIcon,
                  size: 24,
                  color: statusColor,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AI 角色自主社交',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          statusText,
                          style: TextStyle(
                            fontSize: 13,
                            color: statusColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Switch(
                value: _newWorldMode,
                onChanged: _toggleMode,
                activeColor: colorScheme.primary,
              ),
            ],
          ),
          const SizedBox(height: 16),
          // 第二行：关键指标
          Row(
            children: [
              _buildMiniStat(
                icon: Icons.token,
                label: 'Token',
                value: _formatTokens(_tokenConsumed),
                color: Colors.amber,
              ),
              _buildMiniStat(
                icon: Icons.pending_actions,
                label: '待处理',
                value: '$_pendingTasks',
                color: Colors.blue,
              ),
              _buildMiniStat(
                icon: Icons.people,
                label: '活跃角色',
                value: '$_activeCharacterCount/${_characters.length}',
                color: Colors.green,
              ),
              _buildMiniStat(
                icon: _heartbeatRunning
                    ? Icons.favorite
                    : Icons.favorite_border,
                label: '心跳',
                value: _heartbeatRunning
                    ? (_lastHeartbeat != null
                        ? _formatRelativeTime(_lastHeartbeat!)
                        : '运行中')
                    : '已停止',
                color: _heartbeatRunning ? Colors.green : Colors.red,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStat({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: color,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey.shade600,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // 全生命周期数字生命世界 — 前端修复
  // ─── 今日活跃度统计卡片 ───
  Widget _buildTodayActivityCard(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.today_rounded,
                  size: 18, color: colorScheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Text(
                '今日活跃度',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildActivityStatItem(
                icon: Icons.handshake_outlined,
                label: '互动次数',
                value: '$_todayInteractions',
                color: Colors.blue,
                colorScheme: colorScheme,
              ),
              const SizedBox(width: 10),
              _buildActivityStatItem(
                icon: Icons.person_add_outlined,
                label: '新增关系',
                value: '$_todayNewRelations',
                color: Colors.pink,
                colorScheme: colorScheme,
              ),
              const SizedBox(width: 10),
              _buildActivityStatItem(
                icon: Icons.mood,
                label: '情绪变化',
                value: '$_todayEmotionChanges',
                color: Colors.amber,
                colorScheme: colorScheme,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActivityStatItem({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    required ColorScheme colorScheme,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── 2. 实时动态流（核心新增） ───

  Widget _buildSocialFeedSection(ColorScheme colorScheme) {
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题栏
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Icon(Icons.timeline,
                    size: 18, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  '实时动态',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                const Spacer(),
                // 自动刷新指示
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${_socialFeed.length} 条',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.green,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // 动态列表
          if (_feedLoading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (_socialFeed.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.hourglass_empty,
                        size: 32, color: colorScheme.onSurfaceVariant.withOpacity(0.4)),
                    const SizedBox(height: 8),
                    Text(
                      '暂无社交动态\n开启自主模式后，角色互动将在此显示',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.onSurfaceVariant.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            _buildFeedTimeline(colorScheme),
        ],
      ),
    );
  }

  Widget _buildFeedTimeline(ColorScheme colorScheme) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _socialFeed.length.clamp(0, 30), // 最多显示30条
      separatorBuilder: (_, __) => const SizedBox(height: 4),
      itemBuilder: (context, index) {
        final event = _socialFeed[index];
        return _buildFeedItem(event, colorScheme);
      },
    );
  }

  Widget _buildFeedItem(SocialEvent event, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: event.color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: event.color.withOpacity(0.15),
          width: 0.5,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 图标
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: event.color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(event.icon, size: 16, color: event.color),
          ),
          const SizedBox(width: 10),
          // 内容
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 角色名 + 动作
                RichText(
                  text: TextSpan(
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurface,
                      height: 1.4,
                    ),
                    children: [
                      TextSpan(
                        text: event.characterName,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      TextSpan(
                        text: ' ${event.label} ',
                        style: TextStyle(color: event.color),
                      ),
                      if (event.targetCharacterName.isNotEmpty &&
                          event.targetCharacterName != event.characterId)
                        TextSpan(
                          text: event.targetCharacterName,
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                    ],
                  ),
                ),
                // 内容摘要
                if (event.content.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    _truncate(event.content, 60),
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant.withOpacity(0.7),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          // 时间
          Padding(
            padding: const EdgeInsets.only(left: 8, top: 2),
            child: Text(
              _formatRelativeTime(event.timestamp),
              style: TextStyle(
                fontSize: 10,
                color: colorScheme.onSurfaceVariant.withOpacity(0.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── 3. 角色状态概览 ───

  Widget _buildCharacterStatusOverview(ColorScheme colorScheme) {
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Icon(Icons.people_alt_outlined,
                    size: 18, color: colorScheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Text(
                  '角色状态概览',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${_activeCharacterCount}/${_characters.length}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ..._characters.take(10).map(
                (c) => _buildCharacterStatusRow(c, colorScheme),
              ),
          if (_characters.length > 10)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Center(
                child: Text(
                  '还有 ${_characters.length - 10} 个角色...',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCharacterStatusRow(
      AICharacter c, ColorScheme colorScheme) {
    final emotion = _characterEmotions[c.id] ?? '😐';
    final need = _characterMaslow[c.id] ?? '—';
    final lastAct = _characterLastSocial[c.id] ?? '';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          // 头像 + 在线状态
          Stack(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: c.isOnline
                    ? Colors.green.withOpacity(0.2)
                    : colorScheme.surfaceContainerHigh,
                child: Text(
                  c.name.isNotEmpty ? c.name[0] : '?',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: c.isOnline
                        ? Colors.green
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (c.isOnline)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: colorScheme.surfaceContainerLow,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          // 角色名 + 情绪
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        c.name,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(emotion, style: const TextStyle(fontSize: 14)),
                  ],
                ),
                if (lastAct.isNotEmpty)
                  Text(
                    lastAct,
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onSurfaceVariant.withOpacity(0.6),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // 最强需求
          if (need != '—')
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _needColor(need).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                need,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: _needColor(need),
                ),
              ),
            ),
          const SizedBox(width: 8),
          // 生命阶段
          Text(
            _characterLifeStage[c.id] ?? '—',
            style: TextStyle(
              fontSize: 10,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  // ─── 4. 手动触发区域（保留但优化） ───

  Widget _buildTriggerSection(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.play_circle_outline,
                  size: 18, color: colorScheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Text(
                '手动触发测试',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
              const Spacer(),
              if (_isTriggering)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child:
                      CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _triggerButton(
                label: '串门',
                icon: Icons.door_front_door,
                color: Colors.blue,
                onTap: () => _triggerAction('visit'),
              ),
              _triggerButton(
                label: '加好友',
                icon: Icons.person_add,
                color: Colors.pink,
                onTap: () => _triggerAction('friend'),
              ),
              _triggerButton(
                label: '发动态',
                icon: Icons.post_add,
                color: Colors.amber,
                onTap: () => _triggerAction('moment'),
              ),
              _triggerButton(
                label: '评论',
                icon: Icons.comment,
                color: Colors.teal,
                onTap: () => _triggerAction('comment'),
              ),
              _triggerButton(
                label: '点赞',
                icon: Icons.thumb_up,
                color: Colors.red,
                onTap: () => _triggerAction('like'),
              ),
              _triggerButton(
                label: '全部执行',
                icon: Icons.play_arrow,
                color: Colors.purple,
                onTap: () => _triggerAction('all'),
              ),
              _triggerButton(
                label: '检测动态消息',
                icon: Icons.bug_report,
                color: Colors.deepOrange,
                onTap: _detectMoments,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 触发实时反馈卡片
  Widget _buildTriggerFeedbackCard(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _triggerFeedback!.startsWith('✅')
            ? Colors.green.withOpacity(0.08)
            : _triggerFeedback!.startsWith('❌')
                ? Colors.red.withOpacity(0.08)
                : colorScheme.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _triggerFeedback!.startsWith('✅')
              ? Colors.green.withOpacity(0.3)
              : _triggerFeedback!.startsWith('❌')
                  ? Colors.red.withOpacity(0.3)
                  : colorScheme.primary.withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          if (_isTriggering)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Icon(
              _triggerFeedback!.startsWith('✅')
                  ? Icons.check_circle
                  : _triggerFeedback!.startsWith('❌')
                      ? Icons.error
                      : Icons.info,
              size: 18,
              color: _triggerFeedback!.startsWith('✅')
                  ? Colors.green
                  : _triggerFeedback!.startsWith('❌')
                      ? Colors.red
                      : colorScheme.primary,
            ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _triggerFeedback!,
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _triggerButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return ActionChip(
      avatar: Icon(icon, size: 16, color: color),
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: color,
        ),
      ),
      onPressed: _isTriggering ? null : onTap,
      backgroundColor: color.withOpacity(0.08),
      side: BorderSide(color: color.withOpacity(0.3)),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
    );
  }

  Widget _buildActionButtons(ColorScheme colorScheme) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _tokenConsumed > 0 ? _resetTokens : null,
        icon: const Icon(Icons.refresh, size: 18),
        label: const Text('重置计数'),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  // ─── API 调用统计 ───

  Widget _buildApiStatsSection(ColorScheme colorScheme) {
    const labels = {
      'social_visit': '串门',
      'social_friend_request': '加好友',
      'social_private_chat': '私聊',
      'social_moment': '发动态',
      'social_moment_comment': '评论',
      'social_moment_like': '点赞',
      'social_daily_activity': '日常活动',
    };

    final sorted = _actionCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bar_chart_rounded,
                  size: 18, color: colorScheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Text(
                'API 调用统计',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
              const Spacer(),
              Text(
                '${sorted.fold(0, (sum, e) => sum + e.value)} 次',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...sorted.map((entry) {
            final label = labels[entry.key] ?? entry.key;
            final count = entry.value;
            final maxCount = sorted.first.value;
            final ratio =
                maxCount > 0 ? count / maxCount : 0.0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 56,
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: ratio,
                        minHeight: 14,
                        backgroundColor:
                            colorScheme.primary.withOpacity(0.08),
                        valueColor:
                            AlwaysStoppedAnimation(
                          _statColor(entry.key),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 36,
                    child: Text(
                      '$count',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ─── 日志 ───

  Widget _buildLogsSection(ColorScheme colorScheme) {
    final filtered = _filteredLogs;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Icon(Icons.article_outlined,
                    size: 18, color: colorScheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Text(
                  '活动日志',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                const Spacer(),
                Text(
                  '${filtered.length} 条',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFilterChip(
                      'all', '全部', colorScheme),
                  const SizedBox(width: 6),
                  _buildFilterChip(
                      'task', '任务', colorScheme),
                  const SizedBox(width: 6),
                  _buildFilterChip(
                      'mode', '模式', colorScheme),
                  const SizedBox(width: 6),
                  _buildFilterChip(
                      'token', 'Token', colorScheme),
                  const SizedBox(width: 6),
                  _buildFilterChip(
                      'system', '系统', colorScheme),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Text(
                '暂无日志',
                style: TextStyle(
                  fontSize: 13,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            Container(
              constraints: const BoxConstraints(maxHeight: 320),
              child: ListView.separated(
                shrinkWrap: true,
                padding:
                    const EdgeInsets.fromLTRB(16, 0, 16, 16),
                itemCount: filtered.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1),
                itemBuilder: (context, index) {
                  final log = filtered[index];
                  final relative =
                      _logToRelativeTime(log);
                  return Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Container(
                          margin:
                              const EdgeInsets.only(top: 1),
                          padding:
                              const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 2),
                          decoration: BoxDecoration(
                            color: _logCategoryColor(
                                    _extractCategory(log))
                                .withOpacity(0.15),
                            borderRadius:
                                BorderRadius.circular(4),
                          ),
                          child: Text(
                            _extractCategory(log),
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              color: _logCategoryColor(
                                  _extractCategory(log)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text(
                                relative,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: colorScheme
                                      .onSurfaceVariant
                                      .withOpacity(0.6),
                                ),
                              ),
                              Text(
                                _extractDetail(log),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colorScheme.onSurface
                                      .withOpacity(0.85),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String value, String label,
      ColorScheme colorScheme) {
    final selected = _logFilter == value;
    return GestureDetector(
      onTap: () =>
          setState(() => _logFilter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected
              ? colorScheme.primary.withOpacity(0.15)
              : colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? colorScheme.primary.withOpacity(0.5)
                : colorScheme.outlineVariant,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: selected
                ? FontWeight.w600
                : FontWeight.w400,
            color: selected
                ? colorScheme.primary
                : colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Color _statColor(String actionType) {
    switch (actionType) {
      case 'social_visit':
        return Colors.blue;
      case 'social_friend_request':
        return Colors.pink;
      case 'social_private_chat':
        return Colors.purple;
      case 'social_moment':
        return Colors.amber;
      case 'social_moment_comment':
        return Colors.teal;
      case 'social_moment_like':
        return Colors.red;
      case 'social_daily_activity':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 辅助方法
  // ═══════════════════════════════════════════════════════════

  /// 检测朋友圈动态消息
  Future<void> _detectMoments() async {
    setState(() => _isTriggering = true);
    try {
      final storage =
          RepositoryProvider.of<LocalStorageRepository>(context, listen: false);
      final allMoments = await storage.getAllMoments();
      final normalMoments = allMoments
          .where((m) => m.source == MomentSource.normal)
          .toList();

      if (normalMoments.isEmpty) {
        _showToast('检测结果：朋友圈数据库为空');
        return;
      }

      final buffer = StringBuffer();
      buffer.writeln('= 朋友圈动态检测报告 =');
      buffer.writeln('总动态数: ${allMoments.length}');
      buffer.writeln('普通动态: ${normalMoments.length}');
      buffer.writeln('X风格动态: ${allMoments.where((m) => m.source == MomentSource.x).length}');
      buffer.writeln('');

      for (int i = 0; i < normalMoments.length && i < 20; i++) {
        final m = normalMoments[i];
        final isAI = m.isFromAI ? '[AI]' : '[USER]';
        final preview = m.content.length > 30
            ? '${m.content.substring(0, 30)}...'
            : m.content;
        final time = m.createdAt.difference(DateTime.now()).abs();
        final timeStr = time.inHours < 24
            ? '${time.inHours}h${time.inMinutes % 60}m前'
            : '${time.inDays}d前';

        buffer.writeln('$isAI [${m.id.substring(0, 8)}] ${m.userName}');
        buffer.writeln('  内容: $preview');
        buffer.writeln('  点赞: ${m.likes.length}  评论: ${m.comments.length}  $timeStr');

        if (m.comments.isNotEmpty) {
          final lastC = m.comments.last;
          buffer.writeln('  最新评论: ${lastC.userName}: "${lastC.content}"');
        }
        buffer.writeln('');
      }

      if (normalMoments.length > 20) {
        buffer.writeln('... 仅显示前 20 条，共 ${normalMoments.length} 条');
      }

      debugPrint(buffer.toString());

      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('动态检测结果'),
          content: Text(
            '共 ${normalMoments.length} 条普通动态\n'
            '${normalMoments.where((m) => m.comments.isNotEmpty).length} 条有评论\n'
            '${normalMoments.where((m) => m.likes.isNotEmpty).length} 条有点赞\n'
            '${normalMoments.where((m) => m.isFromAI).length} 条来自 AI\n'
            '\n详细报告已复制到剪贴板。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                Clipboard.setData(ClipboardData(text: buffer.toString()));
                _showToast('完整报告已复制到剪贴板');
              },
              child: const Text('复制详细报告'),
            ),
          ],
        ),
      );
    } catch (e) {
      _showToast('检测失败: $e');
      debugPrint('检测动态失败: $e');
    } finally {
      if (mounted) setState(() => _isTriggering = false);
    }
  }

  String _buildTriggerFeedback(
      String actionType, String sourceName, String targetName) {
    switch (actionType) {
      case 'visit':
        return '🚪 $sourceName 正在前往 $targetName 的小窝串门...';
      case 'friend':
        return '🤝 $sourceName 正在向 $targetName 发送好友请求...';
      case 'moment':
        return '📝 $sourceName 正在撰写动态...';
      case 'comment':
        return '💬 $sourceName 正在评论动态...';
      case 'like':
        return '❤️ $sourceName 正在点赞...';
      case 'all':
        return '🔄 正在执行所有社交动作...';
      default:
        return '⏳ 正在执行 $actionType...';
    }
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'visit':
        return '串门';
      case 'friend':
        return '加好友';
      case 'moment':
        return '发动态';
      case 'comment':
        return '评论';
      case 'like':
        return '点赞';
      default:
        return type;
    }
  }

  void _showToast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// 需求标签对应颜色
  Color _needColor(String need) {
    switch (need) {
      case '生理':
        return Colors.red;
      case '安全':
        return Colors.orange;
      case '归属':
        return Colors.pink;
      case '尊重':
        return Colors.blue;
      case '自我实现':
        return Colors.purple;
      case '认知':
        return Colors.teal;
      case '审美':
        return Colors.indigo;
      default:
        return Colors.grey;
    }
  }

  /// 根据 currentStatus 推断情绪 emoji
  String _inferEmotionFromStatus(String? status) {
    if (status == null || status.isEmpty) return '😐';
    final s = status.toLowerCase();
    if (s.contains('开心') || s.contains('happy')) return '😊';
    if (s.contains('兴奋') || s.contains('excited')) return '🤩';
    if (s.contains('平静') || s.contains('calm')) return '😌';
    if (s.contains('担心') || s.contains('worried')) return '😟';
    if (s.contains('难过') || s.contains('sad')) return '😢';
    if (s.contains('生气') || s.contains('angry')) return '😠';
    if (s.contains('害羞') || s.contains('shy')) return '😳';
    if (s.contains('感动') || s.contains('touched')) return '🥺';
    if (s.contains('孤独') || s.contains('lonely')) return '🥺';
    if (s.contains('想念') || s.contains('miss')) return '💭';
    if (s.contains('焦虑') || s.contains('anxious')) return '😰';
    if (s.contains('困') || s.contains('sleepy')) return '😴';
    if (s.contains('调皮') || s.contains('playful')) return '😜';
    return '😐';
  }

  String _formatTokens(int tokens) {
    if (tokens >= 1000000) {
      return '${(tokens / 1000000).toStringAsFixed(1)}M';
    } else if (tokens >= 1000) {
      return '${(tokens / 1000).toStringAsFixed(1)}K';
    }
    return tokens.toString();
  }

  String _formatRelativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 10) return '刚刚';
    if (diff.inSeconds < 60) return '${diff.inSeconds}秒前';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    return '${diff.inDays}天前';
  }

  String _truncate(String text, int maxLen) {
    if (text.length <= maxLen) return text;
    return '${text.substring(0, maxLen)}...';
  }

  String _extractCategory(String log) {
    final match =
        RegExp(r'\[(\w+)\]').firstMatch(log);
    return match?.group(1) ?? '?';
  }

  Color _logCategoryColor(String category) {
    switch (category) {
      case 'task':
        return Colors.blue;
      case 'mode':
        return Colors.purple;
      case 'token':
        return Colors.amber;
      case 'system':
        return Colors.teal;
      default:
        return Colors.grey;
    }
  }

  String _logToRelativeTime(String log) {
    final match = RegExp(
            r'\[(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})')
        .firstMatch(log);
    if (match != null) {
      final dt =
          DateTime.tryParse(match.group(1)!);
      if (dt != null) return _formatRelativeTime(dt);
    }
    return '';
  }

  String _extractDetail(String log) {
    return log.replaceFirst(
        RegExp(r'^\[.*?\]\s*\[.*?\]\s*'), '');
  }

  List<String> get _filteredLogs {
    if (_logFilter == 'all') return _recentLogs;
    return _recentLogs
        .where((log) => log.contains('[${_logFilter}]'))
        .toList();
  }
}
