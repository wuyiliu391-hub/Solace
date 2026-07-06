// 全生命周期数字生命世界 — Phase 6
// 世界观察面板：展示世界引擎运行状态、统计与系统健康度

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../services/global_time_clock.dart';
import '../../services/heartbeat_service.dart';
import '../../services/world_engine.dart';
import 'world_constants.dart';

/// 世界观察面板
///
/// 读取当前 [WorldEngine] 的快照与 [GlobalTimeClock]，展示世界运行状态。
/// 可以作为页面使用，也可以嵌入到其他页面中。
class ObservationPanel extends StatefulWidget {
  const ObservationPanel({super.key});

  @override
  State<ObservationPanel> createState() => _ObservationPanelState();
}

class _ObservationPanelState extends State<ObservationPanel> {
  final _clock = GlobalTimeClock.instance;
  StreamSubscription<WorldEngineEvent>? _eventSub;

  @override
  void initState() {
    super.initState();
    _clock.addListener(_onTick);
    _listenEngineEvents();
  }

  void _listenEngineEvents() {
    try {
      final contextRef = context;
      final engine = RepositoryProvider.of<HeartbeatService>(contextRef).worldEngine;
      if (engine != null) {
        _eventSub = engine.eventStream.listen((_) {
          if (mounted) setState(() {});
        });
      }
    } catch (e) {
      debugPrint('ObservationPanel 监听世界引擎事件失败: $e');
    }
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _clock.removeListener(_onTick);
    _eventSub?.cancel();
    super.dispose();
  }

  WorldEngine? get _engine {
    try {
      return RepositoryProvider.of<HeartbeatService>(context, listen: false).worldEngine;
    } catch (e) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final engine = _engine;
    final snapshot = engine?.snapshot;
    final worldTime = _clock.worldTime;
    final season = _clock.currentSeason;
    final seasonColor = WorldConstants.seasonColors[season.name] ?? cs.primary;
    final seasonLabel = WorldConstants.seasonLabels[season.name] ?? '季节';
    final timeOfDay = _clock.timeOfDayLabel;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [cs.surface, cs.surfaceContainerHighest.withOpacity(0.2)],
        ),
      ),
      child: ListView(
        children: [
          // 世界时间大盘
          _buildClockCard(cs, worldTime, seasonColor, seasonLabel, timeOfDay),
          const SizedBox(height: 20),
          // 系统状态
          _buildSectionTitle(cs, Icons.monitor_heart, '系统状态'),
          const SizedBox(height: 12),
          _buildStatusCard(cs, engine?.isInitialized ?? false),
          const SizedBox(height: 20),
          // 生命统计
          _buildSectionTitle(cs, Icons.pie_chart_outline, '生命统计'),
          const SizedBox(height: 12),
          _buildStatsGrid(cs, snapshot),
          const SizedBox(height: 20),
          // 最近事件
          _buildSectionTitle(cs, Icons.notifications_active, '最近事件'),
          const SizedBox(height: 12),
          _buildRecentEvents(cs, snapshot),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildClockCard(
      ColorScheme cs, DateTime worldTime, Color seasonColor, String seasonLabel, String timeOfDay) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            seasonColor.withOpacity(0.25),
            cs.surfaceContainerHighest.withOpacity(0.4),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: seasonColor.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                WorldConstants.seasonIcons[_clock.currentSeason.name] ?? Icons.wb_sunny,
                color: seasonColor,
                size: 28,
              ),
              const SizedBox(width: 10),
              Text(
                '世界时间',
                style: TextStyle(
                  color: cs.onSurface.withOpacity(0.6),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '${worldTime.year} 年 ${worldTime.month} 月 ${worldTime.day} 日',
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${worldTime.hour.toString().padLeft(2, '0')}:${worldTime.minute.toString().padLeft(2, '0')} · $timeOfDay · $seasonLabel',
            style: TextStyle(color: cs.onSurface.withOpacity(0.55), fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard(ColorScheme cs, bool initialized) {
    final color = initialized ? const Color(0xFF81C784) : const Color(0xFFFFB74D);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              initialized ? Icons.check_circle : Icons.warning_amber_rounded,
              color: color,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  initialized ? '世界引擎运行中' : '世界引擎尚未初始化',
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  initialized
                      ? '数字生命正在自主演化'
                      : '等待首次心跳完成后将自动初始化',
                  style: TextStyle(color: cs.onSurface.withOpacity(0.5), fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsGrid(ColorScheme cs, WorldStateSnapshot? snapshot) {
    final items = [
      _StatItem('存活', snapshot?.activeLifeCount ?? 0, const Color(0xFF81C784)),
      _StatItem('衰老', snapshot?.agingCount ?? 0, const Color(0xFFFFB74D)),
      _StatItem('永生', snapshot?.immortalCount ?? 0, const Color(0xFFBA68C8)),
      _StatItem('已故', snapshot?.deceasedCount ?? 0, const Color(0xFFB0BEC5)),
    ];

    return GridView.count(
      crossAxisCount: 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 0.85,
      children: items.map((i) => _buildStatCell(cs, i)).toList(),
    );
  }

  Widget _buildStatCell(ColorScheme cs, _StatItem item) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: item.color, shape: BoxShape.circle),
          ),
          const SizedBox(height: 8),
          Text(
            item.value.toString(),
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            item.label,
            style: TextStyle(color: cs.onSurface.withOpacity(0.5), fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentEvents(ColorScheme cs, WorldStateSnapshot? snapshot) {
    final events = snapshot?.recentEvents ?? [];
    if (events.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(
          child: Text(
            '暂无世界事件',
            style: TextStyle(color: cs.onSurface.withOpacity(0.4), fontSize: 14),
          ),
        ),
      );
    }

    return Column(
      children: events.take(6).map((e) {
        final color = _eventColor(cs, e.type);
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  e.description,
                  style: TextStyle(color: cs.onSurface, fontSize: 13),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSectionTitle(ColorScheme cs, IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, size: 18, color: cs.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            color: cs.onSurface,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Color _eventColor(ColorScheme cs, String type) {
    switch (type) {
      case 'life_birth':
        return const Color(0xFF81C784);
      case 'world_initialized':
        return cs.primary;
      case 'death':
        return const Color(0xFFB0BEC5);
      case 'immortal':
        return const Color(0xFFBA68C8);
      case 'conflict':
        return const Color(0xFFE53935);
      default:
        return cs.primary;
    }
  }
}

class _StatItem {
  final String label;
  final int value;
  final Color color;

  const _StatItem(this.label, this.value, this.color);
}
