import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../models/ai_character.dart';
import '../../models/character_emotion.dart';
import '../../repositories/local_storage_repository.dart';
import '../../services/ai_behavior_engine.dart';
import '../../services/emotion_engine.dart';

/// 虚拟双人地图 — 完整重构版
///
/// AI 行为由 记忆×人设×情绪 联合驱动，持久化存储
/// UI 全新设计，适配 App 粉紫主题
class VirtualMapScreen extends StatefulWidget {
  const VirtualMapScreen({super.key});

  @override
  State<VirtualMapScreen> createState() => _VirtualMapScreenState();
}

class _VirtualMapScreenState extends State<VirtualMapScreen>
    with TickerProviderStateMixin {
  // ── 状态 ──
  bool _isLoading = true;
  bool _isRefreshing = false;
  bool _showEncounter = false;
  bool _showTrajectory = true;

  // ── 坐标 (0~100 归一化) ──
  double _userX = 50.0;
  double _userY = 50.0;
  double _aiX = 50.0;
  double _aiY = 50.0;
  double _distance = 0;

  // ── 行为计划 ──
  AIBehaviorPlan? _plan;
  List<Offset> _routePoints = [];

  // ── 角色 ──
  AICharacter? _character;
  CharacterEmotion? _emotion;
  late String _userId;

  // ── 动画 ──
  late AnimationController _moveController;
  late AnimationController _routeFlowController;
  late AnimationController _encounterController;
  late AnimationController _pulseController;
  late AnimationController _refreshController;

  // ── POI 标记点击 ──
  String? _selectedPoi;

  @override
  void initState() {
    super.initState();

    _moveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _routeFlowController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    _encounterController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          setState(() => _showEncounter = false);
          _encounterController.reset();
        }
      });

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _refreshController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    final authState = context.read<AuthBloc>().state;
    _userId = (authState as AuthAuthenticated).user.id;

    _initialize();
  }

  @override
  void dispose() {
    _moveController.dispose();
    _routeFlowController.dispose();
    _encounterController.dispose();
    _pulseController.dispose();
    _refreshController.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    final storage = RepositoryProvider.of<LocalStorageRepository>(context);
    final characters = await storage.getAllAICharacters();
    if (characters.isEmpty) {
      setState(() => _isLoading = false);
      return;
    }

    _character = characters.first;
    if (!mounted) return;

    // 读取情绪
    final emotionEngine = RepositoryProvider.of<EmotionEngine>(context);
    _emotion = await emotionEngine.getCurrentEmotion(character: _character!, userId: _userId);

    // 创建行为引擎
    final engine = AIBehaviorEngine(
      storage: storage,
      character: _character!,
      emotion: _emotion!,
      userId: _userId,
    );

    // 尝试加载持久化数据
    final persisted = await engine.loadPersistedPlan();
    if (persisted != null && mounted) {
      _plan = persisted;
      _aiX = persisted.persistedAiLat ?? persisted.aiPosition.dx;
      _aiY = persisted.persistedAiLng ?? persisted.aiPosition.dy;
      _routePoints = persisted.route;
    } else {
      // 首次进入，生成新计划
      _plan = await engine.generatePlan();
      _routePoints = _plan!.route;
      _aiX = _routePoints.last.dx;
      _aiY = _routePoints.last.dy;
      // 持久化
      await engine.persistLocation(
        aiLat: _aiX, aiLng: _aiY,
        destination: _plan!.destination,
      );
    }

    _calculateDistance();
    if (mounted) setState(() => _isLoading = false);
  }

  void _calculateDistance() {
    final dx = _aiX - _userX;
    final dy = _aiY - _userY;
    _distance = sqrt(dx * dx + dy * dy) / 141.0 * 100.0;
  }

  Future<void> _refresh() async {
    if (_isRefreshing || _character == null) return;
    setState(() => _isRefreshing = true);
    _refreshController.forward(from: 0);

    final storage = RepositoryProvider.of<LocalStorageRepository>(context);
    final emotionEngine = RepositoryProvider.of<EmotionEngine>(context);

    // 重新读取情绪（可能已变化）
    _emotion = await emotionEngine.getCurrentEmotion(character: _character!, userId: _userId);

    final engine = AIBehaviorEngine(
      storage: storage,
      character: _character!,
      emotion: _emotion!,
      userId: _userId,
    );

    // 生成新计划（基于记忆+人设+情绪，不是纯随机）
    _plan = await engine.generatePlan();
    _routePoints = _plan!.route;

    // 动画移动到新位置
    final target = _plan!.aiPosition;

    _moveController.reset();
    await _moveController.forward();

    if (mounted) {
      setState(() {
        _aiX = target.dx;
        _aiY = target.dy;
      });

      // 持久化新位置
      await engine.persistLocation(
        aiLat: _aiX, aiLng: _aiY,
        destination: _plan!.destination,
      );

      _calculateDistance();

      // 检查偶遇
      if (_distance < 5) {
        setState(() => _showEncounter = true);
        _encounterController.forward();
      }
    }

    setState(() => _isRefreshing = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mq = MediaQuery.of(context);

    if (_isLoading) {
      return _buildLoadingScreen(cs, isDark);
    }

    return Scaffold(
      backgroundColor: isDark ? cs.surface : const Color(0xFFFDF5F7),
      body: Stack(
        children: [
          // 地图背景
          _buildMapBackground(isDark),

          // 路线绘制
          if (_showTrajectory && _routePoints.length >= 2)
            _buildRouteLayer(cs, isDark),

          // POI 标记
          _buildPoiMarkers(cs, isDark, mq),

          // 用户标记
          _buildUserMarker(cs, isDark, mq),

          // AI 标记
          _buildAiMarker(cs, isDark, mq),

          // 偶遇动画
          if (_showEncounter) _buildEncounterAnimation(mq),

          // 顶部操作栏
          _buildTopBar(cs, isDark, mq),

          // 距离指示器
          _buildDistanceChip(cs, isDark, mq),

          // 底部信息卡
          _buildBottomCard(cs, isDark, mq),
        ],
      ),
    );
  }

  // ── 加载页 ──
  Widget _buildLoadingScreen(ColorScheme cs, bool isDark) {
    return Scaffold(
      backgroundColor: isDark ? cs.surface : const Color(0xFFFDF5F7),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [cs.primary.withOpacity(0.15), cs.primary.withOpacity(0.05)],
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.map_rounded, size: 36, color: cs.primary),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: cs.primary),
            ),
            const SizedBox(height: 16),
            Text(
              '正在分析 AI 的出行计划...',
              style: TextStyle(
                fontSize: 14,
                color: cs.onSurfaceVariant.withOpacity(0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 地图背景 ──
  Widget _buildMapBackground(bool isDark) {
    return CustomPaint(
      painter: _MapBackgroundPainter(isDark: isDark),
      size: Size.infinite,
    );
  }

  // ── 路线层（带流动光效）──
  Widget _buildRouteLayer(ColorScheme cs, bool isDark) {
    final mq = MediaQuery.of(context);
    final mapTop = mq.padding.top + 100;
    const mapHeightScale = 0.45;

    return AnimatedBuilder(
      animation: _routeFlowController,
      builder: (context, _) {
        return CustomPaint(
          painter: _RoutePainter(
            points: _routePoints,
            flowProgress: _routeFlowController.value,
            primaryColor: cs.primary,
            secondaryColor: const Color(0xFF64B5F6),
            isDark: isDark,
            mapTopOffset: mapTop,
            mapHeightScale: mapHeightScale,
          ),
          size: Size.infinite,
        );
      },
    );
  }

  // ── POI 地图标记 ──
  Widget _buildPoiMarkers(ColorScheme cs, bool isDark, MediaQueryData mq) {
    // 只显示路线途经的 POI 区域
    const poiZones = AIBehaviorEngine.poiZones;
    final dest = _plan?.destination ?? 'home';

    return Stack(
      children: poiZones.entries.map((entry) {
        final zone = entry.value;
        final isDest = entry.key == dest;
        final isSelected = _selectedPoi == entry.key;

        // 归一化坐标 → 屏幕坐标
        final left = (zone.x / 100.0) * mq.size.width;
        final top = mq.padding.top + 100 + (zone.y / 100.0) * (mq.size.height * 0.45);

        return Positioned(
          left: left - 16,
          top: top - 16,
          child: GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              setState(() {
                _selectedPoi = isSelected ? null : entry.key;
              });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: isDest ? 36 : 32,
              height: isDest ? 36 : 32,
              decoration: BoxDecoration(
                color: isDest
                    ? cs.primary.withOpacity(isDark ? 0.3 : 0.2)
                    : cs.surfaceContainerHighest.withOpacity(isDark ? 0.5 : 0.7),
                shape: BoxShape.circle,
                border: Border.all(
                  color: isDest ? cs.primary.withOpacity(0.5) : cs.outlineVariant.withOpacity(0.3),
                  width: isDest ? 2 : 1,
                ),
                boxShadow: isDest
                    ? [BoxShadow(color: cs.primary.withOpacity(0.2), blurRadius: 8)]
                    : null,
              ),
              child: Center(
                child: Icon(
                  zone.icon,
                  size: isDest ? 16 : 14,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ── 用户标记 ──
  Widget _buildUserMarker(ColorScheme cs, bool isDark, MediaQueryData mq) {
    final left = (_userX / 100.0) * mq.size.width;
    final top = mq.padding.top + 100 + (_userY / 100.0) * (mq.size.height * 0.45);

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutCubic,
      left: left - 24,
      top: top - 24,
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF64B5F6), Color(0xFF42A5F5)],
              ),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF64B5F6).withOpacity(0.4),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(Icons.person_rounded, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF64B5F6), Color(0xFF42A5F5)],
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF64B5F6).withOpacity(0.3),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Text(
              '你',
              style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── AI 标记（带脉冲动效）──
  Widget _buildAiMarker(ColorScheme cs, bool isDark, MediaQueryData mq) {
    final left = (_aiX / 100.0) * mq.size.width;
    final top = mq.padding.top + 100 + (_aiY / 100.0) * (mq.size.height * 0.45);

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 1500),
      curve: Curves.easeInOutCubic,
      left: left - 24,
      top: top - 24,
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
          final scale = 1.0 + _pulseController.value * 0.08;
          return Transform.scale(
            scale: scale,
            child: child,
          );
        },
        child: Column(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [cs.primary, cs.primary.withOpacity(0.8)],
                ),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: [
                  BoxShadow(
                    color: cs.primary.withOpacity(0.4),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(Icons.favorite_rounded, color: Colors.white, size: 22),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [cs.primary, cs.primary.withOpacity(0.8)],
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: cs.primary.withOpacity(0.3),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                _character?.name ?? 'TA',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 偶遇动画 ──
  Widget _buildEncounterAnimation(MediaQueryData mq) {
    return AnimatedBuilder(
      animation: _encounterController,
      builder: (ctx, _) {
        return Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _HeartBurstPainter(
                progress: _encounterController.value,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        );
      },
    );
  }

  // ── 顶部操作栏 ──
  Widget _buildTopBar(ColorScheme cs, bool isDark, MediaQueryData mq) {
    return Positioned(
      top: mq.padding.top + 8,
      left: 16,
      right: 16,
      child: Row(
        children: [
          // 返回
          _glassButton(
            icon: Icons.arrow_back_ios_new_rounded,
            onTap: () => Navigator.pop(context),
            cs: cs,
            isDark: isDark,
          ),
          const Spacer(),
          // 轨迹开关
          _glassButton(
            icon: _showTrajectory ? Icons.route_rounded : Icons.route_outlined,
            onTap: () {
              HapticFeedback.lightImpact();
              setState(() => _showTrajectory = !_showTrajectory);
            },
            cs: cs,
            isDark: isDark,
            isActive: _showTrajectory,
          ),
          const SizedBox(width: 8),
          // 刷新
          _glassButton(
            icon: Icons.refresh_rounded,
            onTap: _isRefreshing ? null : _refresh,
            cs: cs,
            isDark: isDark,
            isLoading: _isRefreshing,
          ),
          const SizedBox(width: 8),
          // 设置位置
          _glassButton(
            icon: Icons.my_location_rounded,
            onTap: () => _showPositionSetter(cs, isDark),
            cs: cs,
            isDark: isDark,
          ),
        ],
      ),
    );
  }

  Widget _glassButton({
    required IconData icon,
    VoidCallback? onTap,
    required ColorScheme cs,
    required bool isDark,
    bool isActive = false,
    bool isLoading = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: isActive
              ? cs.primary.withOpacity(isDark ? 0.3 : 0.2)
              : (isDark ? cs.surfaceContainerHighest.withOpacity(0.7) : cs.surfaceContainerLow.withOpacity(0.9)),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive ? cs.primary.withOpacity(0.3) : cs.outlineVariant.withOpacity(0.2),
          ),
          boxShadow: [
            BoxShadow(
              color: cs.shadow.withOpacity(isDark ? 0.2 : 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Center(
          child: isLoading
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: cs.primary,
                  ),
                )
              : Icon(
                  icon,
                  size: 20,
                  color: isActive ? cs.primary : (onTap != null ? cs.onSurface : cs.onSurfaceVariant.withOpacity(0.3)),
                ),
        ),
      ),
    );
  }

  // ── 距离指示器 ──
  Widget _buildDistanceChip(ColorScheme cs, bool isDark, MediaQueryData mq) {
    final isClose = _distance < 5;

    return Positioned(
      top: mq.padding.top + 60,
      left: 0,
      right: 0,
      child: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            gradient: isClose
                ? LinearGradient(
                    colors: [cs.primary.withOpacity(0.15), cs.primary.withOpacity(0.08)],
                  )
                : null,
            color: isClose ? null : (isDark ? cs.surfaceContainerHighest.withOpacity(0.8) : cs.surfaceContainerLow.withOpacity(0.92)),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isClose ? cs.primary.withOpacity(0.3) : cs.outlineVariant.withOpacity(0.2),
            ),
            boxShadow: [
              BoxShadow(
                color: cs.shadow.withOpacity(isDark ? 0.2 : 0.06),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isClose ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                color: isClose ? cs.primary : cs.onSurfaceVariant.withOpacity(0.5),
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                '相距 ${_distance.toStringAsFixed(1)} km',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: isClose ? cs.primary : cs.onSurface.withOpacity(0.8),
                ),
              ),
              if (isClose) ...[
                const SizedBox(width: 4),
                const Icon(Icons.favorite, size: 16, color: Colors.pink),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── 底部信息卡 ──
  Widget _buildBottomCard(ColorScheme cs, bool isDark, MediaQueryData mq) {
    final plan = _plan;

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.fromLTRB(20, 16, 20, mq.padding.bottom + 16),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(
            color: cs.outlineVariant.withOpacity(isDark ? 0.15 : 0.1),
          ),
          boxShadow: [
            BoxShadow(
              color: cs.shadow.withOpacity(isDark ? 0.3 : 0.08),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 拖拽条
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: cs.onSurfaceVariant.withOpacity(0.15),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 14),

            // 行为描述
            if (plan != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      cs.primary.withOpacity(isDark ? 0.12 : 0.06),
                      cs.primary.withOpacity(isDark ? 0.06 : 0.02),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: cs.primary.withOpacity(isDark ? 0.15 : 0.1),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: cs.primary.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.psychology_rounded, size: 12, color: cs.primary),
                              const SizedBox(width: 4),
                              Text(
                                'AI 行为决策',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: cs.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        // 情绪标签
                        if (_emotion != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: _emotionColor(_emotion!.effectiveEmotion).withOpacity(0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _emotionLabel(_emotion!.effectiveEmotion),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: _emotionColor(_emotion!.effectiveEmotion),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      plan.description,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.5,
                        color: cs.onSurface.withOpacity(0.85),
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 14),

            // 操作按钮
            Row(
              children: [
                Expanded(
                  child: _actionButton(
                    icon: Icons.near_me_rounded,
                    label: '靠近一点',
                    onTap: _isRefreshing ? null : _moveCloser,
                    cs: cs,
                    isDark: isDark,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _actionButton(
                    icon: Icons.auto_awesome_rounded,
                    label: '新出行计划',
                    onTap: _isRefreshing ? null : _refresh,
                    cs: cs,
                    isDark: isDark,
                    isPrimary: true,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    VoidCallback? onTap,
    required ColorScheme cs,
    required bool isDark,
    bool isPrimary = false,
  }) {
    final enabled = onTap != null;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          gradient: isPrimary && enabled
              ? LinearGradient(colors: [cs.primary, cs.primary.withOpacity(0.8)])
              : null,
          color: isPrimary
              ? null
              : (enabled
                  ? cs.primary.withOpacity(isDark ? 0.12 : 0.08)
                  : cs.surfaceContainerHighest.withOpacity(0.3)),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isPrimary && enabled
                ? Colors.transparent
                : cs.primary.withOpacity(enabled ? 0.2 : 0.08),
          ),
          boxShadow: isPrimary && enabled
              ? [BoxShadow(color: cs.primary.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 3))]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: isPrimary && enabled
                  ? Colors.white
                  : (enabled ? cs.primary : cs.onSurfaceVariant.withOpacity(0.3)),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isPrimary && enabled
                    ? Colors.white
                    : (enabled ? cs.primary : cs.onSurfaceVariant.withOpacity(0.3)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 靠近操作 ──
  Future<void> _moveCloser() async {
    if (_isRefreshing) return;
    HapticFeedback.lightImpact();

    final dx = _userX - _aiX;
    final dy = _userY - _aiY;
    final dist = sqrt(dx * dx + dy * dy);

    if (dist > 0.5) {
      final step = dist * 0.3;
      final ratio = step / dist;

      setState(() {
        _aiX += dx * ratio;
        _aiY += dy * ratio;
      });

      _calculateDistance();

      // 持久化新位置
      if (_character != null && _emotion != null) {
        final storage = RepositoryProvider.of<LocalStorageRepository>(context);
        final engine = AIBehaviorEngine(
          storage: storage,
          character: _character!,
          emotion: _emotion!,
          userId: _userId,
        );
        await engine.persistLocation(
          aiLat: _aiX, aiLng: _aiY,
          destination: _plan?.destination ?? 'home',
        );
      }

      if (_distance < 5 && mounted) {
        setState(() => _showEncounter = true);
        _encounterController.forward();
      }
    }
  }

  // ── 位置设置弹窗 ──
  void _showPositionSetter(ColorScheme cs, bool isDark) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return Container(
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: cs.onSurfaceVariant.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF64B5F6).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.my_location_rounded, size: 20, color: Color(0xFF64B5F6)),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '设置你的虚拟位置',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _buildSlider(
                  label: '纬度',
                  value: _userX,
                  cs: cs,
                  onChanged: (v) {
                    setSheetState(() => _userX = v);
                    setState(() => _userX = v);
                  },
                ),
                const SizedBox(height: 16),
                _buildSlider(
                  label: '经度',
                  value: _userY,
                  cs: cs,
                  onChanged: (v) {
                    setSheetState(() => _userY = v);
                    setState(() => _userY = v);
                  },
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [cs.primary, cs.primary.withOpacity(0.8)]),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(color: cs.primary.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 3)),
                      ],
                    ),
                    child: FilledButton(
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        Navigator.pop(ctx);
                        _calculateDistance();
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text('确认位置', style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSlider({
    required String label,
    required double value,
    required ColorScheme cs,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 40,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: cs.onSurface.withOpacity(0.7),
            ),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              activeTrackColor: cs.primary,
              inactiveTrackColor: cs.primary.withOpacity(0.15),
              thumbColor: cs.primary,
              overlayColor: cs.primary.withOpacity(0.1),
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            ),
            child: Slider(
              value: value,
              min: 0,
              max: 100,
              divisions: 100,
              onChanged: onChanged,
            ),
          ),
        ),
        SizedBox(
          width: 45,
          child: Text(
            value.toStringAsFixed(1),
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: cs.primary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }

  // ── 情绪工具 ──
  Color _emotionColor(EmotionType emotion) {
    return switch (emotion) {
      EmotionType.happy => const Color(0xFF4CAF50),
      EmotionType.excited => const Color(0xFFFF9800),
      EmotionType.calm => const Color(0xFF64B5F6),
      EmotionType.sad => const Color(0xFF90A4AE),
      EmotionType.angry => const Color(0xFFEF5350),
      EmotionType.shy => const Color(0xFFF48FB1),
      EmotionType.touched => const Color(0xFFCE93D8),
      EmotionType.lonely => const Color(0xFF78909C),
      EmotionType.miss => const Color(0xFFE91E63),
      EmotionType.anxious => const Color(0xFFFFB74D),
      EmotionType.sleepy => const Color(0xFFB39DDB),
      EmotionType.playful => const Color(0xFFFF80AB),
      EmotionType.worried => const Color(0xFFFFCC02),
    };
  }

  String _emotionLabel(EmotionType emotion) {
    return switch (emotion) {
      EmotionType.happy => '开心',
      EmotionType.excited => '兴奋',
      EmotionType.calm => '平静',
      EmotionType.sad => '低落',
      EmotionType.angry => '生气',
      EmotionType.shy => '害羞',
      EmotionType.touched => '感动',
      EmotionType.lonely => '孤独',
      EmotionType.miss => '想念',
      EmotionType.anxious => '焦虑',
      EmotionType.sleepy => '困倦',
      EmotionType.playful => '调皮',
      EmotionType.worried => '担心',
    };
  }
}

// ─────────────────────────────────────────────────
// Custom Painters
// ─────────────────────────────────────────────────

/// 地图背景绘制器（渐变 + 道路网格 + 装饰）
class _MapBackgroundPainter extends CustomPainter {
  final bool isDark;
  _MapBackgroundPainter({required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    // 渐变背景
    final bgPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: isDark
            ? [
                const Color(0xFF1A1520),
                const Color(0xFF1E1828),
                const Color(0xFF201A2A),
              ]
            : [
                const Color(0xFFFDF5F7),
                const Color(0xFFF8F0F4),
                const Color(0xFFF5EDF2),
              ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // 道路网格
    final roadPaint = Paint()
      ..color = isDark
          ? Colors.white.withOpacity(0.04)
          : const Color(0xFFD8C2CC).withOpacity(0.2)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    final gridSpacing = size.width / 8;
    for (double x = 0; x < size.width; x += gridSpacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), roadPaint);
    }
    for (double y = 0; y < size.height; y += gridSpacing * 1.2) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), roadPaint);
    }

    // 装饰虚线路径
    final dashPaint = Paint()
      ..color = (isDark ? const Color(0xFF914463) : const Color(0xFFF472B6)).withOpacity(0.15)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();
    path.moveTo(size.width * 0.05, size.height * 0.25);
    path.quadraticBezierTo(
      size.width * 0.3, size.height * 0.15,
      size.width * 0.5, size.height * 0.3,
    );
    path.quadraticBezierTo(
      size.width * 0.7, size.height * 0.45,
      size.width * 0.95, size.height * 0.35,
    );
    _drawDashedPath(canvas, path, dashPaint, dashLength: 8, gapLength: 6);

    // 装饰小圆点
    final dotPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = (isDark ? const Color(0xFF914463) : const Color(0xFFF472B6)).withOpacity(0.08);

    final rng = Random(42);
    for (int i = 0; i < 15; i++) {
      final x = rng.nextDouble() * size.width;
      final y = rng.nextDouble() * size.height;
      final r = 2.0 + rng.nextDouble() * 4;
      canvas.drawCircle(Offset(x, y), r, dotPaint);
    }
  }

  void _drawDashedPath(Canvas canvas, Path path, Paint paint, {
    required double dashLength,
    required double gapLength,
  }) {
    final metrics = path.computeMetrics();
    for (final metric in metrics) {
      double distance = 0;
      while (distance < metric.length) {
        final end = (distance + dashLength).clamp(0, metric.length).toDouble();
        final extractPath = metric.extractPath(distance, end);
        canvas.drawPath(extractPath, paint);
        distance = end + gapLength;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 路线绘制器（双色渐变 + 流动光效）
class _RoutePainter extends CustomPainter {
  final List<Offset> points;
  final double flowProgress;
  final Color primaryColor;
  final Color secondaryColor;
  final bool isDark;
  final double mapTopOffset;
  final double mapHeightScale;

  _RoutePainter({
    required this.points,
    required this.flowProgress,
    required this.primaryColor,
    required this.secondaryColor,
    required this.isDark,
    this.mapTopOffset = 100,
    this.mapHeightScale = 0.45,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    // 将归一化坐标转为屏幕坐标（与 POI 标记 / AI 标记坐标系一致）
    final mapHeight = size.height * mapHeightScale;
    final screenPoints = points.map((p) => Offset(
      (p.dx / 100.0) * size.width,
      mapTopOffset + (p.dy / 100.0) * mapHeight,
    )).toList();

    // 构建贝塞尔曲线路径
    final path = Path();
    path.moveTo(screenPoints[0].dx, screenPoints[0].dy);

    if (screenPoints.length == 2) {
      path.lineTo(screenPoints[1].dx, screenPoints[1].dy);
    } else {
      for (int i = 1; i < screenPoints.length - 1; i++) {
        final prev = screenPoints[i - 1];
        final curr = screenPoints[i];
        final next = screenPoints[i + 1];

        final cp1 = Offset(
          prev.dx + (curr.dx - prev.dx) * 0.5,
          prev.dy + (curr.dy - prev.dy) * 0.5,
        );
        final cp2 = Offset(
          curr.dx + (next.dx - curr.dx) * 0.5,
          curr.dy + (next.dy - curr.dy) * 0.5,
        );

        if (i == 1) {
          path.quadraticBezierTo(curr.dx, curr.dy, cp2.dx, cp2.dy);
        } else {
          path.cubicTo(cp1.dx, cp1.dy, curr.dx, curr.dy, cp2.dx, cp2.dy);
        }
      }
      path.lineTo(screenPoints.last.dx, screenPoints.last.dy);
    }

    // 主路线（半透明粗线）
    final mainPaint = Paint()
      ..color = (isDark ? primaryColor.withOpacity(0.4) : primaryColor.withOpacity(0.25))
      ..strokeWidth = 6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, mainPaint);

    // 内芯路线（更亮更细）
    final corePaint = Paint()
      ..color = primaryColor.withOpacity(isDark ? 0.7 : 0.5)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, corePaint);

    // 流动光点
    final metrics = path.computeMetrics().first;
    final totalLength = metrics.length;
    final dotPos = (flowProgress * totalLength).clamp(0, totalLength).toDouble();
    final tangent = metrics.getTangentForOffset(dotPos);

    if (tangent != null) {
      final dotPaint = Paint()
        ..color = primaryColor
        ..style = PaintingStyle.fill;
      canvas.drawCircle(tangent.position, 5, dotPaint);

      // 光晕
      final glowPaint = Paint()
        ..color = primaryColor.withOpacity(0.3)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(tangent.position, 12, glowPaint);
    }

    // 路线端点圆圈
    for (final p in screenPoints) {
      final dotPaint = Paint()
        ..color = primaryColor.withOpacity(0.5)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(p, 4, dotPaint);

      final ringPaint = Paint()
        ..color = primaryColor.withOpacity(0.2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawCircle(p, 7, ringPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _RoutePainter oldDelegate) =>
      oldDelegate.flowProgress != flowProgress ||
      oldDelegate.points != points;
}

/// 偶遇心跳爆发绘制器
class _HeartBurstPainter extends CustomPainter {
  final double progress;
  final Color color;

  _HeartBurstPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;

    final center = Offset(size.width / 2, size.height * 0.42);

    // 外圈光晕
    final glowPaint = Paint()
      ..color = color.withOpacity((0.3 * (1 - progress)).clamp(0, 1))
      ..style = PaintingStyle.fill;
    final glowRadius = 60.0 + progress * 100;
    canvas.drawCircle(center, glowRadius, glowPaint);

    // 散射心形
    for (int i = 0; i < 10; i++) {
      final angle = (i / 10) * 2 * pi + progress * 2;
      final dist = 50.0 + progress * 120;
      final hx = center.dx + cos(angle) * dist;
      final hy = center.dy + sin(angle) * dist;

      final opacity = (1.0 - progress).clamp(0.0, 1.0);
      final heartPaint = Paint()
        ..color = color.withOpacity(opacity * 0.8)
        ..style = PaintingStyle.fill;

      _drawHeart(canvas, Offset(hx, hy), 8 + progress * 5, heartPaint);
    }

    // 中心大心
    if (progress < 0.6) {
      final scale = 1.0 + sin(progress * pi) * 0.5;
      final centerPaint = Paint()
        ..color = color.withOpacity(0.9)
        ..style = PaintingStyle.fill;
      _drawHeart(canvas, center, 22 * scale, centerPaint);
    }
  }

  void _drawHeart(Canvas canvas, Offset center, double size, Paint paint) {
    final path = Path();
    final w = size;
    final h = size;
    path.moveTo(center.dx, center.dy + h * 0.3);
    path.cubicTo(center.dx, center.dy, center.dx - w, center.dy, center.dx - w, center.dy + h * 0.3);
    path.cubicTo(center.dx - w, center.dy + h * 0.7, center.dx, center.dy + h, center.dx, center.dy + h);
    path.cubicTo(center.dx, center.dy + h, center.dx + w, center.dy + h * 0.7, center.dx + w, center.dy + h * 0.3);
    path.cubicTo(center.dx + w, center.dy, center.dx, center.dy, center.dx, center.dy + h * 0.3);
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _HeartBurstPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
