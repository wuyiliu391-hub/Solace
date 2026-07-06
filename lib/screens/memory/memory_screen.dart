import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../models/memory.dart';
import '../../models/ai_character.dart';
import '../../repositories/local_storage_repository.dart';
import '../../services/memory_engine.dart';
import '../../services/memory_rebuild_service.dart';

// ─────────────────────────────────────────────────────────
// MemoryScreen — 记忆页面完整重构
// 视觉风格：粉色主题、圆润卡片、热度指示、轻量动画
// ─────────────────────────────────────────────────────────

class MemoryScreen extends StatefulWidget {
  const MemoryScreen({super.key});

  @override
  State<MemoryScreen> createState() => _MemoryScreenState();
}

class _MemoryScreenState extends State<MemoryScreen>
    with TickerProviderStateMixin {
  List<AICharacter> _characters = [];
  String? _selectedCharacterId;
  List<Memory> _allMemories = [];
  List<Memory> _filteredMemories = [];
  MemoryType? _selectedType;
  String _searchQuery = '';
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _isSearching = false;
  bool _isRebuildingMemories = false;
  String _rebuildStatus = '';
  bool _hasPendingCheckpoint = false;
  late String _userId;
  StreamSubscription<MemoryRebuildProgress>? _rebuildSub;

  // 分页相关
  static const int _pageSize = 20;
  int _displayCount = _pageSize;
  final ScrollController _scrollController = ScrollController();

  // 缓存分组结果，避免每次 build 重新计算
  List<MapEntry<String, List<Memory>>> _cachedGroupedEntries = [];
  bool _groupByDirty = true;

  // 缓存分类计数，避免每次 build 遍历
  Map<MemoryType?, int> _typeCountCache = {};

  // 搜索防抖
  Timer? _searchDebounce;

  // 动画控制器
  late AnimationController _fabAnimController;
  late AnimationController _listAnimController;
  final TextEditingController _searchEditingController =
      TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  // 记忆类型配置 — 统一管理图标 / 颜色 / 名称
  static const _typeConfigs = <_MemoryTypeConfig>[
    _MemoryTypeConfig(null, '全部', Icons.layers_rounded, null),
    _MemoryTypeConfig(
        MemoryType.preference, '偏好', Icons.favorite_rounded, Color(0xFFF472B6)),
    _MemoryTypeConfig(MemoryType.milestone, '经历', Icons.auto_awesome_rounded,
        Color(0xFFFF9ECB)),
    _MemoryTypeConfig(
        MemoryType.reflection, '摘要', Icons.article_rounded, Color(0xFF9C5A9A)),
    _MemoryTypeConfig(MemoryType.emotion, '情感', Icons.favorite_border_rounded,
        Color(0xFFE879A8)),
    _MemoryTypeConfig(
        MemoryType.state, '状态', Icons.access_time_rounded, Color(0xFF7AA382)),
    _MemoryTypeConfig(MemoryType.rollingSummary, '永久档案', Icons.shield_rounded,
        Color(0xFFBA68C8)),
    _MemoryTypeConfig(MemoryType.conversation, '对话', Icons.chat_bubble_rounded,
        Color(0xFF64B5F6)),
  ];

  @override
  void initState() {
    super.initState();
    _fabAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..forward();
    _listAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    final authState = context.read<AuthBloc>().state;
    _userId = (authState as AuthAuthenticated).user.id;
    // 延迟加载，避免阻塞 UI
    Future.microtask(() => _loadCharacters());
    _searchFocusNode.addListener(() {
      setState(() => _isSearching = _searchFocusNode.hasFocus);
    });
    // 滚动监听，加载更多
    _scrollController.addListener(_onScroll);
    // 同步后台重建状态（用户可能从其他页面返回时重建仍在进行）
    _syncRebuildState();
  }

  void _syncRebuildState() {
    final svc = MemoryRebuildService.instance;
    if (svc.isRebuilding) {
      _isRebuildingMemories = true;
      _rebuildStatus = svc.statusText;
      _rebuildSub?.cancel();
      _rebuildSub = svc.progressStream.listen((progress) {
        if (!mounted) return;
        setState(() {
          _isRebuildingMemories =
              progress.state == MemoryRebuildState.rebuilding;
          _rebuildStatus = progress.statusText;
          _hasPendingCheckpoint = false;
        });
        if (progress.state == MemoryRebuildState.completed ||
            progress.state == MemoryRebuildState.error) {
          setState(() {
            _isRebuildingMemories = false;
            _rebuildStatus = '';
          });
          _loadMemories();
          _rebuildSub?.cancel();
          _rebuildSub = null;
          svc.reset();
        }
      });
    } else {
      // 检查是否有未完成的断点（杀后台恢复场景）
      MemoryRebuildService.hasPendingCheckpoint().then((has) {
        if (has && mounted) {
          setState(() => _hasPendingCheckpoint = true);
        }
      });
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _rebuildSub?.cancel();
    _fabAnimController.dispose();
    _listAnimController.dispose();
    _searchEditingController.dispose();
    _searchFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  void _loadMore() {
    if (_isLoadingMore) return;
    if (_displayCount >= _filteredMemories.length) return;

    setState(() {
      _isLoadingMore = true;
    });

    // 延迟一下，让 UI 有时间渲染
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        setState(() {
          _displayCount =
              (_displayCount + _pageSize).clamp(0, _filteredMemories.length);
          _isLoadingMore = false;
          _groupByDirty = true;
        });
      }
    });
  }

  Future<void> _loadCharacters() async {
    final storage = RepositoryProvider.of<LocalStorageRepository>(context);
    final characters = await storage.getAllAICharacters();
    setState(() {
      _characters = characters;
      if (characters.isNotEmpty) {
        _selectedCharacterId = characters.first.id;
      }
    });
    if (_selectedCharacterId != null) {
      await _loadMemories();
    }
  }

  Future<void> _loadMemories() async {
    if (_selectedCharacterId == null) return;
    setState(() => _isLoading = true);

    final storage = RepositoryProvider.of<LocalStorageRepository>(context);
    final memories = await storage.getMemories(
      characterId: _selectedCharacterId!,
      userId: _userId,
      limit: null,
    );

    // 预计算分类计数
    final countCache = <MemoryType?, int>{null: memories.length};
    for (final m in memories) {
      countCache[m.type] = (countCache[m.type] ?? 0) + 1;
    }

    setState(() {
      _allMemories = memories;
      _typeCountCache = countCache;
      _isLoading = false;
    });
    _applyFilters();
    _listAnimController.forward(from: 0);
  }

  void _applyFilters() {
    var filtered = List<Memory>.from(_allMemories);

    if (_selectedType != null) {
      filtered = filtered.where((m) => m.type == _selectedType).toList();
    }

    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filtered = filtered
          .where((m) =>
              m.content.toLowerCase().contains(query) ||
              m.keywords.any((k) => k.toLowerCase().contains(query)))
          .toList();
    }

    filtered.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _groupByDirty = true;
    setState(() {
      _filteredMemories = filtered;
      _displayCount = _pageSize; // 重置分页
    });
  }

  /// 搜索防抖：300ms 内只触发最后一次
  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      _searchQuery = value;
      _applyFilters();
    });
  }

  List<MapEntry<String, List<Memory>>> _getGroupedEntries() {
    if (!_groupByDirty) return _cachedGroupedEntries;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final weekAgo = today.subtract(const Duration(days: 7));

    // 只取当前分页的数据
    final displayMemories = _filteredMemories.take(_displayCount).toList();

    final groups = <String, List<Memory>>{};
    for (final memory in displayMemories) {
      final date = DateTime(
          memory.createdAt.year, memory.createdAt.month, memory.createdAt.day);
      String key;
      if (date == today) {
        key = '今天';
      } else if (date == yesterday) {
        key = '昨天';
      } else if (date.isAfter(weekAgo)) {
        key = '本周';
      } else {
        key = DateFormat('MM月dd日').format(memory.createdAt);
      }
      groups.putIfAbsent(key, () => []).add(memory);
    }

    _cachedGroupedEntries = groups.entries.toList();
    _groupByDirty = false;
    return _cachedGroupedEntries;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? cs.surface : const Color(0xFFFDF5F7),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(cs, isDark),
            _buildSearchBar(cs, isDark),
            _buildTypeFilter(cs, isDark),
            if (_isRebuildingMemories && _rebuildStatus.isNotEmpty)
              _buildRebuildStatus(cs, isDark),
            if (_hasPendingCheckpoint && !_isRebuildingMemories)
              _buildCheckpointBanner(cs, isDark),
            const SizedBox(height: 8),
            Expanded(child: _buildContent(cs, isDark)),
          ],
        ),
      ),
      floatingActionButton: _buildFAB(cs),
    );
  }

  Widget _buildRebuildStatus(ColorScheme cs, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: cs.primary.withOpacity(isDark ? 0.14 : 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.primary.withOpacity(0.18)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _rebuildStatus,
                style: TextStyle(
                  fontSize: 12,
                  color: cs.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCheckpointBanner(ColorScheme cs, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: GestureDetector(
        onTap: _resumeFromCheckpoint,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.orange.withOpacity(isDark ? 0.14 : 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.orange.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.play_circle_outline_rounded,
                  size: 16, color: Colors.orange),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  '检测到未完成的记忆重建，点击继续',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.orange,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  '继续',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.orange,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 顶部标题栏 ──
  Widget _buildHeader(ColorScheme cs, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 16, 4),
      child: Row(
        children: [
          // 返回按钮
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color:
                    cs.surfaceContainerHighest.withOpacity(isDark ? 0.5 : 0.6),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.arrow_back_ios_new_rounded,
                  size: 18, color: cs.onSurface),
            ),
          ),
          const SizedBox(width: 12),
          // 标题
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '记忆',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                    letterSpacing: -0.5,
                  ),
                ),
                if (_allMemories.isNotEmpty)
                  Text(
                    '共 ${_allMemories.length} 条记忆${_filteredMemories.length != _allMemories.length ? '，匹配 ${_filteredMemories.length} 条' : ''}${_displayCount < _filteredMemories.length ? '（显示 $_displayCount）' : ''}',
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurfaceVariant.withOpacity(0.6),
                    ),
                  ),
              ],
            ),
          ),
          // 角色切换
          if (_characters.length > 1) _buildCharacterSwitcher(cs, isDark),
          const SizedBox(width: 8),
          _buildRebuildButton(cs, isDark),
          if (_hasPendingCheckpoint && !_isRebuildingMemories) ...[
            const SizedBox(width: 4),
            _buildResumeButton(cs, isDark),
          ],
        ],
      ),
    );
  }

  Widget _buildRebuildButton(ColorScheme cs, bool isDark) {
    return Tooltip(
      message: '从聊天记录重建记忆',
      child: GestureDetector(
        onTap: _isRebuildingMemories ? null : _confirmRebuildMemories,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: _isRebuildingMemories
                ? cs.primary.withOpacity(0.12)
                : cs.surfaceContainerHighest.withOpacity(isDark ? 0.5 : 0.6),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _isRebuildingMemories
                  ? cs.primary.withOpacity(0.25)
                  : Colors.transparent,
            ),
          ),
          child: _isRebuildingMemories
              ? Padding(
                  padding: const EdgeInsets.all(9),
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
                  ),
                )
              : Icon(Icons.history_edu_rounded, size: 18, color: cs.primary),
        ),
      ),
    );
  }

  Widget _buildResumeButton(ColorScheme cs, bool isDark) {
    return Tooltip(
      message: '继续上次未完成的重建',
      child: GestureDetector(
        onTap: _resumeFromCheckpoint,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: Colors.orange.withOpacity(isDark ? 0.2 : 0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.orange.withOpacity(0.3)),
          ),
          child: const Icon(Icons.play_arrow_rounded,
              size: 18, color: Colors.orange),
        ),
      ),
    );
  }

  Future<void> _resumeFromCheckpoint() async {
    final storage = RepositoryProvider.of<LocalStorageRepository>(context);
    final engine = MemoryEngine(storage);
    final rebuildService = MemoryRebuildService.instance;

    if (rebuildService.isRebuilding) {
      _showSnackBar('记忆重建已在进行中，请稍候...', isError: false);
      return;
    }

    HapticFeedback.mediumImpact();

    // 监听进度更新
    _rebuildSub?.cancel();
    _rebuildSub = rebuildService.progressStream.listen((progress) {
      if (!mounted) return;
      setState(() {
        _isRebuildingMemories = progress.state == MemoryRebuildState.rebuilding;
        _rebuildStatus = progress.statusText;
        _hasPendingCheckpoint = false;
      });
    });

    setState(() {
      _isRebuildingMemories = true;
      _rebuildStatus = '正在从断点恢复重建...';
      _hasPendingCheckpoint = false;
    });
    _showSnackBar('正在恢复上次未完成的重建...', isError: false);

    // 启动恢复（不 await）
    rebuildService.resumeFromCheckpoint(engine: engine);

    // 监听完成
    rebuildService.stateStream.listen((state) {
      if (state == MemoryRebuildState.completed ||
          state == MemoryRebuildState.error) {
        _rebuildSub?.cancel();
        if (!mounted) return;
        setState(() {
          _isRebuildingMemories = false;
          _rebuildStatus = '';
        });
        _loadMemories();
        final result = rebuildService.lastResult;
        if (result != null) {
          _showSnackBar(
            result.feedbackMessage,
            isError: result.failedBatches > 0 || !result.hasHistory,
          );
        }
        if (rebuildService.errorMessage != null) {
          _showSnackBar(rebuildService.errorMessage!, isError: true);
        }
        rebuildService.reset();
      }
    });
  }

  Future<void> _confirmRebuildMemories() async {
    if (_selectedCharacterId == null) return;
    final character =
        _characters.firstWhere((c) => c.id == _selectedCharacterId);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重建历史记忆'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '将扫描「${character.name}」的本地聊天记录，补回以前没提取到的偏好、经历、情绪和状态。\n\n不会删除现有记忆，已存在的相似内容会自动跳过。',
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withOpacity(0.3)),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded,
                      size: 18, color: Colors.orange),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '本次重建会消耗较多 API Token（每批消息都会调用 AI 提取记忆），请确认额度充足。',
                      style: TextStyle(fontSize: 12, color: Colors.orange),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.withOpacity(0.3)),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.check_circle_outline,
                      size: 18, color: Colors.green),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '重建将在后台自动进行，您可以自由切换其他页面，不会中断。',
                      style: TextStyle(fontSize: 12, color: Colors.green),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('开始重建'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _rebuildMemoriesFromHistory(character);
    }
  }

  Future<void> _rebuildMemoriesFromHistory(AICharacter character) async {
    final storage = RepositoryProvider.of<LocalStorageRepository>(context);
    final engine = MemoryEngine(storage);
    final rebuildService = MemoryRebuildService.instance;

    // 如果正在重建，忽略
    if (rebuildService.isRebuilding) {
      _showSnackBar('记忆重建已在进行中，请稍候...', isError: false);
      return;
    }

    HapticFeedback.mediumImpact();

    // 监听进度更新
    final sub = rebuildService.progressStream.listen((progress) {
      if (!mounted) return;
      setState(() {
        _isRebuildingMemories = progress.state == MemoryRebuildState.rebuilding;
        _rebuildStatus = progress.statusText;
      });
    });

    setState(() {
      _isRebuildingMemories = true;
      _rebuildStatus = '正在扫描历史聊天记录...';
    });
    _showSnackBar('正在后台重建记忆，您可以自由切换页面', isError: false);

    // 启动后台重建（不 await，让服务在后台运行）
    rebuildService.startRebuild(
      engine: engine,
      character: character,
      userId: _userId,
    );

    // 监听完成
    rebuildService.stateStream.listen((state) {
      if (state == MemoryRebuildState.completed ||
          state == MemoryRebuildState.error) {
        sub.cancel();
        if (!mounted) return;
        setState(() {
          _isRebuildingMemories = false;
          _rebuildStatus = '';
        });
        _loadMemories();
        final result = rebuildService.lastResult;
        if (result != null) {
          _showSnackBar(
            result.feedbackMessage,
            isError: result.failedBatches > 0 || !result.hasHistory,
          );
        }
        if (rebuildService.errorMessage != null) {
          _showSnackBar(rebuildService.errorMessage!, isError: true);
        }
        rebuildService.reset();
      }
    });
  }

  void _showSnackBar(String message, {required bool isError}) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: isError ? Colors.red.shade600 : Colors.green.shade600,
        duration: Duration(seconds: isError ? 6 : 4),
      ),
    );
  }

  Widget _buildCharacterSwitcher(ColorScheme cs, bool isDark) {
    return GestureDetector(
      onTap: () => _showCharacterPicker(cs, isDark),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              cs.primary.withOpacity(0.15),
              cs.primary.withOpacity(0.08),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: cs.primary.withOpacity(0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_rounded, size: 16, color: cs.primary),
            const SizedBox(width: 4),
            Text(
              _characters.firstWhere((c) => c.id == _selectedCharacterId).name,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: cs.primary,
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.expand_more_rounded, size: 16, color: cs.primary),
          ],
        ),
      ),
    );
  }

  void _showCharacterPicker(ColorScheme cs, bool isDark) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: cs.onSurfaceVariant.withOpacity(0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text('切换角色',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface)),
            const SizedBox(height: 12),
            ..._characters.map((c) => ListTile(
                  leading: CircleAvatar(
                    backgroundColor: c.id == _selectedCharacterId
                        ? cs.primary.withOpacity(0.2)
                        : cs.surfaceContainerHighest,
                    child: Icon(
                      Icons.person_rounded,
                      color: c.id == _selectedCharacterId
                          ? cs.primary
                          : cs.onSurfaceVariant,
                      size: 20,
                    ),
                  ),
                  title: Text(c.name,
                      style: TextStyle(
                        fontWeight: c.id == _selectedCharacterId
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: cs.onSurface,
                      )),
                  trailing: c.id == _selectedCharacterId
                      ? Icon(Icons.check_circle_rounded,
                          color: cs.primary, size: 20)
                      : null,
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() => _selectedCharacterId = c.id);
                    _loadMemories();
                  },
                )),
            SizedBox(height: MediaQuery.of(ctx).viewInsets.bottom + 20),
          ],
        ),
      ),
    );
  }

  // ── 搜索栏 ──
  Widget _buildSearchBar(ColorScheme cs, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        decoration: BoxDecoration(
          color: _isSearching
              ? cs.surfaceContainerHighest.withOpacity(isDark ? 0.6 : 0.8)
              : cs.surfaceContainerHighest.withOpacity(isDark ? 0.4 : 0.5),
          borderRadius: BorderRadius.circular(14),
          border: _isSearching
              ? Border.all(color: cs.primary.withOpacity(0.3), width: 1.5)
              : null,
        ),
        child: TextField(
          controller: _searchEditingController,
          focusNode: _searchFocusNode,
          style: TextStyle(fontSize: 15, color: cs.onSurface),
          decoration: InputDecoration(
            hintText: '搜索记忆内容或关键词...',
            hintStyle: TextStyle(
              fontSize: 15,
              color: cs.onSurfaceVariant.withOpacity(0.4),
            ),
            prefixIcon: Padding(
              padding: const EdgeInsets.only(left: 14, right: 8),
              child: Icon(
                Icons.search_rounded,
                size: 22,
                color: _isSearching
                    ? cs.primary
                    : cs.onSurfaceVariant.withOpacity(0.5),
              ),
            ),
            suffixIcon: _searchQuery.isNotEmpty
                ? GestureDetector(
                    onTap: () {
                      _searchEditingController.clear();
                      _searchQuery = '';
                      _applyFilters();
                    },
                    child: Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: cs.onSurfaceVariant.withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.close_rounded,
                            size: 14, color: cs.onSurfaceVariant),
                      ),
                    ),
                  )
                : null,
            border: InputBorder.none,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          ),
          onChanged: _onSearchChanged,
        ),
      ),
    );
  }

  // ── 分类标签栏 ──
  Widget _buildTypeFilter(ColorScheme cs, bool isDark) {
    return SizedBox(
      height: 48,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _typeConfigs.length,
        itemBuilder: (context, index) {
          final config = _typeConfigs[index];
          final isSelected = _selectedType == config.type;
          final color = config.color ?? cs.primary;
          final count = _typeCountCache[config.type] ?? 0;

          return GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              setState(() {
                _selectedType = isSelected ? null : config.type;
              });
              _applyFilters();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                gradient: isSelected
                    ? LinearGradient(
                        colors: [
                          color,
                          color.withOpacity(0.8),
                        ],
                      )
                    : null,
                color: isSelected
                    ? null
                    : cs.surfaceContainerHighest
                        .withOpacity(isDark ? 0.3 : 0.5),
                borderRadius: BorderRadius.circular(20),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: color.withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    config.icon,
                    size: 16,
                    color: isSelected ? Colors.white : color,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    config.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w500,
                      color: isSelected
                          ? Colors.white
                          : cs.onSurface.withOpacity(0.7),
                    ),
                  ),
                  if (count > 0) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Colors.white.withOpacity(0.25)
                            : color.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$count',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: isSelected ? Colors.white : color,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── 内容区域 ──
  Widget _buildContent(ColorScheme cs, bool isDark) {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation(cs.primary),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '加载记忆中...',
              style: TextStyle(
                fontSize: 14,
                color: cs.onSurfaceVariant.withOpacity(0.5),
              ),
            ),
          ],
        ),
      );
    }

    if (_filteredMemories.isEmpty) {
      return _buildEmptyState(cs, isDark);
    }

    return _buildGroupedList(cs, isDark);
  }

  // ── 空白状态 ──
  Widget _buildEmptyState(ColorScheme cs, bool isDark) {
    final isSearch = _searchQuery.isNotEmpty || _selectedType != null;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 装饰圆圈
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    cs.primary.withOpacity(0.08),
                    cs.primary.withOpacity(0.03),
                  ],
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isSearch
                    ? Icons.search_off_rounded
                    : Icons.auto_awesome_outlined,
                size: 44,
                color: cs.primary.withOpacity(0.4),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              isSearch ? '没有找到匹配的记忆' : '还没有记忆',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: cs.onSurface.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isSearch ? '试试更换关键词或筛选条件' : '与 AI 的每一次对话都会积累成珍贵的记忆',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: cs.onSurfaceVariant.withOpacity(0.5),
                height: 1.5,
              ),
            ),
            if (!isSearch) ...[
              const SizedBox(height: 24),
              GestureDetector(
                onTap: _showAddMemorySheet,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [cs.primary, cs.primary.withOpacity(0.8)],
                    ),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: cs.primary.withOpacity(0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_rounded, size: 20, color: Colors.white),
                      SizedBox(width: 6),
                      Text(
                        '创建第一条记忆',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (isSearch) ...[
              const SizedBox(height: 20),
              GestureDetector(
                onTap: () {
                  _searchEditingController.clear();
                  _searchQuery = '';
                  _selectedType = null;
                  _applyFilters();
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: cs.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '清除筛选',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: cs.primary,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── 分组列表 ──
  Widget _buildGroupedList(ColorScheme cs, bool isDark) {
    final entries = _getGroupedEntries();
    final hasMore = _displayCount < _filteredMemories.length;

    return AnimatedBuilder(
      animation: _listAnimController,
      builder: (context, child) {
        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 100),
          itemCount: entries.length + (hasMore ? 1 : 0),
          itemBuilder: (context, index) {
            // 加载更多的指示器
            if (index == entries.length) {
              return _buildLoadMoreIndicator(cs);
            }

            final entry = entries[index]; // O(1) 直接索引
            final anim = CurvedAnimation(
              parent: _listAnimController,
              curve: Interval(
                (index * 0.1).clamp(0.0, 0.8),
                ((index * 0.1) + 0.4).clamp(0.0, 1.0),
                curve: Curves.easeOutCubic,
              ),
            );

            return FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.15),
                  end: Offset.zero,
                ).animate(anim),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildDateHeader(entry.key, cs, isDark),
                    ...entry.value.map((m) => _buildMemoryCard(m, cs, isDark)),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildLoadMoreIndicator(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Center(
        child: _isLoadingMore
            ? SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(cs.primary),
                ),
              )
            : Text(
                '上拉加载更多',
                style: TextStyle(
                  fontSize: 13,
                  color: cs.onSurfaceVariant.withOpacity(0.5),
                ),
              ),
      ),
    );
  }

  // ── 日期分组标题 ──
  Widget _buildDateHeader(String label, ColorScheme cs, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 16, bottom: 10),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 16,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [cs.primary, cs.primary.withOpacity(0.4)],
              ),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: cs.onSurface.withOpacity(0.8),
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    cs.outlineVariant.withOpacity(0.3),
                    cs.outlineVariant.withOpacity(0.05),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 记忆卡片 ──
  Widget _buildMemoryCard(Memory memory, ColorScheme cs, bool isDark) {
    final config = _typeConfigs.firstWhere(
      (c) => c.type == memory.type,
      orElse: () => _typeConfigs.last,
    );
    final color = config.color ?? cs.primary;
    final timeStr = _formatTime(memory.createdAt);

    return Dismissible(
      key: Key(memory.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (direction) async {
        HapticFeedback.mediumImpact();
        return await _showDeleteConfirm(cs, isDark, memory);
      },
      onDismissed: (_) => _deleteMemory(memory.id),
      background: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFF6B6B), Color(0xFFFF3B3B)],
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.delete_outline_rounded, color: Colors.white, size: 26),
            SizedBox(height: 2),
            Text('删除',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          _showEditSheet(memory);
        },
        onLongPress: () {
          HapticFeedback.mediumImpact();
          _showMemoryActions(memory, cs, isDark);
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: isDark
                ? cs.surfaceContainerHighest.withOpacity(0.5)
                : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: color.withOpacity(0.12),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: cs.shadow.withOpacity(isDark ? 0.2 : 0.04),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 左侧色条
                  Container(
                    width: 4,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [color, color.withOpacity(0.4)],
                      ),
                    ),
                  ),
                  // 内容区
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 头部：类型标签 + 时间
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: color.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(config.icon, size: 12, color: color),
                                    const SizedBox(width: 4),
                                    Text(
                                      config.label,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: color,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Spacer(),
                              Text(
                                timeStr,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: cs.onSurfaceVariant.withOpacity(0.45),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          // 内容文字
                          Text(
                            memory.content,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.5,
                              color: cs.onSurface.withOpacity(0.85),
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                          // 关键词
                          if (memory.keywords.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: memory.keywords
                                  .take(5)
                                  .map((k) => Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: cs.surfaceContainerHighest
                                              .withOpacity(isDark ? 0.4 : 0.6),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          '#$k',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: cs.onSurfaceVariant
                                                .withOpacity(0.7),
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ))
                                  .toList(),
                            ),
                          ],
                          // 底部：重要度 + 热度 + 操作提示
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              // 重要度指示
                              _buildImportanceIndicator(memory.importance, cs),
                              const SizedBox(width: 12),
                              // 热度指示（艾宾浩斯）
                              _buildHeatIndicator(memory, cs),
                              const Spacer(),
                              // 展开提示
                              Icon(
                                Icons.chevron_right_rounded,
                                size: 18,
                                color: cs.onSurfaceVariant.withOpacity(0.25),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── 重要度指示器 ──
  Widget _buildImportanceIndicator(
      MemoryImportance importance, ColorScheme cs) {
    final config = _importanceConfig(importance);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ...List.generate(4, (i) {
          final isActive = i <= config.level;
          return Container(
            width: 6,
            height: 6 + (i * 2.0),
            margin: const EdgeInsets.only(right: 3),
            decoration: BoxDecoration(
              color: isActive
                  ? config.color
                  : cs.onSurfaceVariant.withOpacity(0.12),
              borderRadius: BorderRadius.circular(2),
            ),
          );
        }),
        const SizedBox(width: 6),
        Text(
          config.label,
          style: TextStyle(
            fontSize: 11,
            color: config.color.withOpacity(0.8),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  // ── 热度指示器（艾宾浩斯权重可视化）──
  Widget _buildHeatIndicator(Memory memory, ColorScheme cs) {
    // weight 范围 0.0~2.0，映射到热度等级
    final w = memory.weight;
    final String label;
    final Color color;
    final IconData icon;

    if (w >= 1.5) {
      label = '炽热';
      color = const Color(0xFFEF5350);
      icon = Icons.whatshot_rounded;
    } else if (w >= 1.0) {
      label = '温热';
      color = const Color(0xFFFF9800);
      icon = Icons.local_fire_department_rounded;
    } else if (w >= 0.5) {
      label = '温暖';
      color = const Color(0xFFFFB74D);
      icon = Icons.wb_sunny_rounded;
    } else {
      label = '冷却';
      color = const Color(0xFF90CAF9);
      icon = Icons.ac_unit_rounded;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color.withOpacity(0.7)),
        const SizedBox(width: 3),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: color.withOpacity(0.7),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  _ImportanceConfig _importanceConfig(MemoryImportance imp) {
    return switch (imp) {
      MemoryImportance.trivial =>
        const _ImportanceConfig(0, '普通', Color(0xFFBDBDBD)),
      MemoryImportance.normal =>
        const _ImportanceConfig(1, '一般', Color(0xFF64B5F6)),
      MemoryImportance.important =>
        const _ImportanceConfig(2, '重要', Color(0xFFFFB74D)),
      MemoryImportance.crucial =>
        const _ImportanceConfig(3, '关键', Color(0xFFEF5350)),
    };
  }

  // ── 长按操作菜单 ──
  void _showMemoryActions(Memory memory, ColorScheme cs, bool isDark) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: cs.onSurfaceVariant.withOpacity(0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            // 预览
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                memory.content,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  color: cs.onSurface.withOpacity(0.7),
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              height: 1,
              margin: const EdgeInsets.symmetric(horizontal: 20),
              color: cs.outlineVariant.withOpacity(0.2),
            ),
            const SizedBox(height: 8),
            _buildActionTile(
              icon: Icons.edit_outlined,
              label: '编辑记忆',
              color: cs.primary,
              onTap: () {
                Navigator.pop(ctx);
                _showEditSheet(memory);
              },
            ),
            _buildActionTile(
              icon: Icons.copy_rounded,
              label: '复制内容',
              color: const Color(0xFF64B5F6),
              onTap: () {
                Navigator.pop(ctx);
                Clipboard.setData(ClipboardData(text: memory.content));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('已复制到剪贴板'),
                    duration: const Duration(seconds: 1),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                );
              },
            ),
            _buildActionTile(
              icon: Icons.delete_outline_rounded,
              label: '删除记忆',
              color: const Color(0xFFEF5350),
              onTap: () async {
                Navigator.pop(ctx);
                final confirmed = await _showDeleteConfirm(cs, isDark, memory);
                if (confirmed == true) _deleteMemory(memory.id);
              },
            ),
            SizedBox(height: MediaQuery.of(ctx).viewInsets.bottom + 20),
          ],
        ),
      ),
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 20, color: color),
      ),
      title: Text(
        label,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: color,
        ),
      ),
      onTap: onTap,
    );
  }

  // ── 删除确认弹窗 ──
  Future<bool?> _showDeleteConfirm(ColorScheme cs, bool isDark, Memory memory) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: cs.surface,
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFFEF5350).withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.delete_outline_rounded,
                  size: 20, color: Color(0xFFEF5350)),
            ),
            const SizedBox(width: 12),
            const Text('删除记忆'),
          ],
        ),
        content: Text(
          '确定要删除这条记忆吗？此操作不可撤销。',
          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('取消', style: TextStyle(color: cs.onSurfaceVariant)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFEF5350),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  // ── FAB ──
  Widget _buildFAB(ColorScheme cs) {
    return ScaleTransition(
      scale: CurvedAnimation(
        parent: _fabAnimController,
        curve: Curves.elasticOut,
      ),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [cs.primary, cs.primary.withOpacity(0.8)],
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: cs.primary.withOpacity(0.4),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () {
              HapticFeedback.mediumImpact();
              _showAddMemorySheet();
            },
            child: const SizedBox(
              width: 56,
              height: 56,
              child: Icon(Icons.add_rounded, color: Colors.white, size: 28),
            ),
          ),
        ),
      ),
    );
  }

  // ── 编辑记忆底部弹窗 ──
  void _showEditSheet(Memory memory) {
    final contentController = TextEditingController(text: memory.content);
    final keywordController =
        TextEditingController(text: memory.keywords.join(', '));
    MemoryImportance selectedImportance = memory.importance;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final sheetCs = Theme.of(ctx).colorScheme;
          return Container(
            decoration: BoxDecoration(
              color: sheetCs.surface,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              top: 16,
              left: 20,
              right: 20,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 拖拽指示条
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: sheetCs.onSurfaceVariant.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // 标题行
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: (_typeConfigs
                                      .firstWhere((c) => c.type == memory.type)
                                      .color ??
                                  sheetCs.primary)
                              .withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          _typeConfigs
                              .firstWhere((c) => c.type == memory.type)
                              .icon,
                          size: 20,
                          color: _typeConfigs
                                  .firstWhere((c) => c.type == memory.type)
                                  .color ??
                              sheetCs.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _typeConfigs
                                  .firstWhere((c) => c.type == memory.type)
                                  .label,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: sheetCs.onSurface,
                              ),
                            ),
                            Text(
                              _formatTime(memory.createdAt),
                              style: TextStyle(
                                fontSize: 12,
                                color:
                                    sheetCs.onSurfaceVariant.withOpacity(0.5),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  // 内容编辑
                  _buildSheetLabel('内容', sheetCs),
                  const SizedBox(height: 8),
                  _buildTextField(
                    controller: contentController,
                    maxLines: 5,
                    minLines: 3,
                    sheetCs: sheetCs,
                  ),
                  const SizedBox(height: 20),
                  // 重要度选择
                  _buildSheetLabel('重要度', sheetCs),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: MemoryImportance.values.map((imp) {
                      final config = _importanceConfig(imp);
                      final isSelected = selectedImportance == imp;
                      return GestureDetector(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          setSheetState(() => selectedImportance = imp);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? config.color.withOpacity(0.15)
                                : sheetCs.surfaceContainerHighest
                                    .withOpacity(0.4),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected
                                  ? config.color.withOpacity(0.4)
                                  : Colors.transparent,
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ...List.generate(4, (i) {
                                final isActive = i <= config.level;
                                return Container(
                                  width: 5,
                                  height: 5 + (i * 1.5),
                                  margin: const EdgeInsets.only(right: 2),
                                  decoration: BoxDecoration(
                                    color: isActive
                                        ? (isSelected
                                            ? config.color
                                            : config.color.withOpacity(0.5))
                                        : sheetCs.onSurfaceVariant
                                            .withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(1.5),
                                  ),
                                );
                              }),
                              const SizedBox(width: 8),
                              Text(
                                config.label,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                  color: isSelected
                                      ? config.color
                                      : sheetCs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                  // 关键词
                  _buildSheetLabel('关键词', sheetCs),
                  const SizedBox(height: 4),
                  Text(
                    '用逗号分隔多个关键词',
                    style: TextStyle(
                        fontSize: 12,
                        color: sheetCs.onSurfaceVariant.withOpacity(0.4)),
                  ),
                  const SizedBox(height: 8),
                  _buildTextField(
                    controller: keywordController,
                    sheetCs: sheetCs,
                    hintText: '关键词1, 关键词2',
                  ),
                  const SizedBox(height: 28),
                  // 操作按钮
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _deleteMemory(memory.id);
                          },
                          icon: const Icon(Icons.delete_outline_rounded,
                              size: 18),
                          label: const Text('删除'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFEF5350),
                            side: const BorderSide(color: Color(0xFFEF5350)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                sheetCs.primary,
                                sheetCs.primary.withOpacity(0.8)
                              ],
                            ),
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: sheetCs.primary.withOpacity(0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: FilledButton(
                            onPressed: () {
                              HapticFeedback.lightImpact();
                              final updated = memory.copyWith(
                                content: contentController.text.trim(),
                                importance: selectedImportance,
                                keywords: keywordController.text
                                    .split(',')
                                    .map((k) => k.trim())
                                    .where((k) => k.isNotEmpty)
                                    .toList(),
                              );
                              _saveMemory(updated);
                              Navigator.pop(ctx);
                            },
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                            ),
                            child: const Text('保存',
                                style: TextStyle(fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── 新增记忆底部弹窗 ──
  void _showAddMemorySheet() {
    final contentController = TextEditingController();
    final keywordController = TextEditingController();
    MemoryType selectedType = MemoryType.preference;
    MemoryImportance selectedImportance = MemoryImportance.normal;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final sheetCs = Theme.of(ctx).colorScheme;
          return Container(
            decoration: BoxDecoration(
              color: sheetCs.surface,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              top: 16,
              left: 20,
              right: 20,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 拖拽指示条
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: sheetCs.onSurfaceVariant.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // 标题
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              sheetCs.primary.withOpacity(0.2),
                              sheetCs.primary.withOpacity(0.08)
                            ],
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.add_rounded,
                            size: 20, color: sheetCs.primary),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '添加记忆',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: sheetCs.onSurface,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  // 类型选择
                  _buildSheetLabel('类型', sheetCs),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      MemoryType.preference,
                      MemoryType.milestone,
                      MemoryType.emotion,
                      MemoryType.state,
                    ].map((t) {
                      final config =
                          _typeConfigs.firstWhere((c) => c.type == t);
                      final color = config.color ?? sheetCs.primary;
                      final isSelected = selectedType == t;
                      return GestureDetector(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          setSheetState(() => selectedType = t);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? color.withOpacity(0.15)
                                : sheetCs.surfaceContainerHighest
                                    .withOpacity(0.4),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected
                                  ? color.withOpacity(0.4)
                                  : Colors.transparent,
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(config.icon,
                                  size: 16,
                                  color: isSelected
                                      ? color
                                      : sheetCs.onSurfaceVariant),
                              const SizedBox(width: 6),
                              Text(
                                config.label,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                  color: isSelected
                                      ? color
                                      : sheetCs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                  // 内容
                  _buildSheetLabel('内容', sheetCs),
                  const SizedBox(height: 8),
                  _buildTextField(
                    controller: contentController,
                    maxLines: 5,
                    minLines: 3,
                    sheetCs: sheetCs,
                    hintText: '让 AI 记住这件事...',
                  ),
                  const SizedBox(height: 20),
                  // 重要度
                  _buildSheetLabel('重要度', sheetCs),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: MemoryImportance.values.map((imp) {
                      final config = _importanceConfig(imp);
                      final isSelected = selectedImportance == imp;
                      return GestureDetector(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          setSheetState(() => selectedImportance = imp);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? config.color.withOpacity(0.15)
                                : sheetCs.surfaceContainerHighest
                                    .withOpacity(0.4),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected
                                  ? config.color.withOpacity(0.4)
                                  : Colors.transparent,
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ...List.generate(4, (i) {
                                final isActive = i <= config.level;
                                return Container(
                                  width: 5,
                                  height: 5 + (i * 1.5),
                                  margin: const EdgeInsets.only(right: 2),
                                  decoration: BoxDecoration(
                                    color: isActive
                                        ? (isSelected
                                            ? config.color
                                            : config.color.withOpacity(0.5))
                                        : sheetCs.onSurfaceVariant
                                            .withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(1.5),
                                  ),
                                );
                              }),
                              const SizedBox(width: 8),
                              Text(
                                config.label,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                  color: isSelected
                                      ? config.color
                                      : sheetCs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                  // 关键词
                  _buildSheetLabel('关键词', sheetCs),
                  const SizedBox(height: 4),
                  Text(
                    '用逗号分隔多个关键词',
                    style: TextStyle(
                        fontSize: 12,
                        color: sheetCs.onSurfaceVariant.withOpacity(0.4)),
                  ),
                  const SizedBox(height: 8),
                  _buildTextField(
                    controller: keywordController,
                    sheetCs: sheetCs,
                    hintText: '关键词1, 关键词2',
                  ),
                  const SizedBox(height: 28),
                  // 添加按钮
                  SizedBox(
                    width: double.infinity,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            sheetCs.primary,
                            sheetCs.primary.withOpacity(0.8)
                          ],
                        ),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: sheetCs.primary.withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: FilledButton(
                        onPressed: () {
                          if (contentController.text.trim().isEmpty) return;
                          HapticFeedback.lightImpact();
                          final memory = Memory(
                            id: const Uuid().v4(),
                            characterId: _selectedCharacterId!,
                            userId: _userId,
                            type: selectedType,
                            content: contentController.text.trim(),
                            importance: selectedImportance,
                            keywords: keywordController.text
                                .split(',')
                                .map((k) => k.trim())
                                .where((k) => k.isNotEmpty)
                                .toList(),
                            createdAt: DateTime.now(),
                          );
                          _saveMemory(memory);
                          Navigator.pop(ctx);
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        child: const Text(
                          '添加记忆',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── 公共组件：弹窗标签 ──
  Widget _buildSheetLabel(String label, ColorScheme cs) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: cs.onSurface.withOpacity(0.7),
      ),
    );
  }

  // ── 公共组件：输入框 ──
  Widget _buildTextField({
    required TextEditingController controller,
    required ColorScheme sheetCs,
    int maxLines = 1,
    int minLines = 1,
    String? hintText,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      minLines: minLines,
      style: TextStyle(fontSize: 15, color: sheetCs.onSurface),
      decoration: InputDecoration(
        filled: true,
        fillColor: sheetCs.surfaceContainerHighest.withOpacity(0.4),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:
              BorderSide(color: sheetCs.outlineVariant.withOpacity(0.2)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:
              BorderSide(color: sheetCs.primary.withOpacity(0.4), width: 1.5),
        ),
        contentPadding: const EdgeInsets.all(14),
        hintText: hintText,
        hintStyle: TextStyle(
            fontSize: 14, color: sheetCs.onSurfaceVariant.withOpacity(0.35)),
      ),
    );
  }

  // ── 数据操作 ──
  Future<void> _saveMemory(Memory memory) async {
    final storage = RepositoryProvider.of<LocalStorageRepository>(context);
    await storage.saveMemory(memory);
    await _loadMemories();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('已保存'),
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  Future<void> _deleteMemory(String id) async {
    final storage = RepositoryProvider.of<LocalStorageRepository>(context);
    await storage.deleteMemory(id);
    await _loadMemories();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('已删除'),
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  // ── 工具方法 ──
  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes}分钟前';
    if (diff.inDays < 1) return '${diff.inHours}小时前';
    if (diff.inDays < 2) return '昨天';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    return DateFormat('MM/dd').format(dt);
  }
}

// ── 数据类 ──

class _MemoryTypeConfig {
  final MemoryType? type;
  final String label;
  final IconData icon;
  final Color? color;

  const _MemoryTypeConfig(this.type, this.label, this.icon, this.color);
}

class _ImportanceConfig {
  final int level;
  final String label;
  final Color color;

  const _ImportanceConfig(this.level, this.label, this.color);
}
