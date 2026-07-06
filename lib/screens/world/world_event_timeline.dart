// 全生命周期数字生命世界 -- Phase 6
// 世界事件时间线 -- 简洁事件列表

import 'package:flutter/material.dart';
import '../../services/global_time_clock.dart';
import 'world_constants.dart';

/// 世界事件时间线 -- 简洁事件列表
class WorldEventTimelineScreen extends StatefulWidget {
  const WorldEventTimelineScreen({super.key});

  @override
  State<WorldEventTimelineScreen> createState() =>
      _WorldEventTimelineScreenState();
}

class _WorldEventTimelineScreenState extends State<WorldEventTimelineScreen> {
  final _clock = GlobalTimeClock.instance;
  WorldEventType? _filter;

  @override
  void initState() {
    super.initState();
    _clock.addListener(_onClockTick);
  }

  @override
  void dispose() {
    _clock.removeListener(_onClockTick);
    super.dispose();
  }

  void _onClockTick() {
    if (mounted) setState(() {});
  }

  List<WorldEvent> get _filteredEvents {
    final events = _clock.recentEvents;
    if (_filter == null) return events;
    return events.where((e) => e.type == _filter).toList();
  }

  // ═══════════════════════════════════════════
  // 主构建
  // ═══════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final events = _filteredEvents;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('事件时间线'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // 筛选 Chips
          _buildFilterChips(cs),
          // 事件列表
          Expanded(
            child: events.isEmpty
                ? _buildEmptyState(cs)
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: events.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      return _buildEventTile(cs, events[index]);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════
  // 筛选 Chips
  // ═══════════════════════════════════════════

  Widget _buildFilterChips(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _filterChip(cs, null, '全部', Icons.all_inclusive),
            const SizedBox(width: 8),
            _filterChip(cs, WorldEventType.holiday, '节日', Icons.celebration),
            const SizedBox(width: 8),
            _filterChip(cs, WorldEventType.disaster, '灾难', Icons.bolt),
            const SizedBox(width: 8),
            _filterChip(cs, WorldEventType.eraChange, '时代', Icons.auto_awesome),
            const SizedBox(width: 8),
            _filterChip(cs, WorldEventType.pandemic, '疫病', Icons.coronavirus),
            const SizedBox(width: 8),
            _filterChip(cs, WorldEventType.seasonal, '季节', Icons.local_florist),
          ],
        ),
      ),
    );
  }

  Widget _filterChip(ColorScheme cs, WorldEventType? type, String label, IconData icon) {
    final selected = _filter == type;
    final color = type != null ? _eventTypeColor(type) : cs.primary;

    return FilterChip(
      avatar: Icon(icon, size: 16, color: selected ? cs.onSurface : color),
      label: Text(label),
      selected: selected,
      selectedColor: color,
      onSelected: (_) => setState(() => _filter = type),
    );
  }

  // ═══════════════════════════════════════════
  // 事件 Tile
  // ═══════════════════════════════════════════

  Widget _buildEventTile(ColorScheme cs, WorldEvent event) {
    final typeColor = _eventTypeColor(event.type);
    final typeIcon = _eventTypeIcon(event.type);
    final typeLabel = _eventTypeLabel(event.type);

    return Card(
      color: cs.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 顶部: 类型标签 + 时间
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: typeColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(typeIcon, size: 14, color: typeColor),
                      const SizedBox(width: 4),
                      Text(
                        typeLabel,
                        style: TextStyle(color: typeColor, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Text(
                  _formatEventTime(event.timestamp),
                  style: TextStyle(color: cs.onSurface.withOpacity(0.4), fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // 事件名称
            Text(
              event.name,
              style: TextStyle(color: cs.onSurface, fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            // 事件描述
            Text(
              event.description,
              style: TextStyle(color: cs.onSurface.withOpacity(0.6), fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 12),
            // 影响范围
            Row(
              children: [
                Icon(Icons.radar, size: 14, color: cs.onSurface.withOpacity(0.4)),
                const SizedBox(width: 6),
                Text('影响范围', style: TextStyle(color: cs.onSurface.withOpacity(0.4), fontSize: 12)),
                const SizedBox(width: 8),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: event.impactScope,
                      backgroundColor: cs.onSurface.withOpacity(0.08),
                      valueColor: AlwaysStoppedAnimation<Color>(typeColor),
                      minHeight: 4,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${(event.impactScope * 100).toInt()}%',
                  style: TextStyle(color: typeColor, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            // 影响效果标签
            if (event.effects.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: event.effects.entries.map((e) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: cs.onSurface.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${e.key}: ${e.value}',
                      style: TextStyle(color: cs.onSurface.withOpacity(0.5), fontSize: 11, fontFamily: 'monospace'),
                    ),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════
  // 空状态
  // ═══════════════════════════════════════════

  Widget _buildEmptyState(ColorScheme cs) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.event_note, size: 64, color: cs.onSurface.withOpacity(0.15)),
          const SizedBox(height: 16),
          Text(
            _filter == null ? '暂无世界事件' : '没有 ${_eventTypeLabel(_filter!)} 类型的事件',
            style: TextStyle(color: cs.onSurface.withOpacity(0.4), fontSize: 15),
          ),
          const SizedBox(height: 8),
          Text(
            '事件会在世界时间推进过程中自然发生',
            style: TextStyle(color: cs.onSurface.withOpacity(0.25), fontSize: 12),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════
  // 工具方法
  // ═══════════════════════════════════════════

  Color _eventTypeColor(WorldEventType type) {
    switch (type) {
      case WorldEventType.disaster:
        return const Color(0xFFE53935);
      case WorldEventType.holiday:
        return const Color(0xFFFFD54F);
      case WorldEventType.eraChange:
        return const Color(0xFF9C27B0);
      case WorldEventType.pandemic:
        return const Color(0xFFFF9800);
      case WorldEventType.seasonal:
        return const Color(0xFF66BB6A);
    }
  }

  IconData _eventTypeIcon(WorldEventType type) {
    switch (type) {
      case WorldEventType.disaster:
        return Icons.bolt;
      case WorldEventType.holiday:
        return Icons.celebration;
      case WorldEventType.eraChange:
        return Icons.auto_awesome;
      case WorldEventType.pandemic:
        return Icons.coronavirus;
      case WorldEventType.seasonal:
        return Icons.local_florist;
    }
  }

  String _eventTypeLabel(WorldEventType type) {
    switch (type) {
      case WorldEventType.disaster:
        return '灾难';
      case WorldEventType.holiday:
        return '节日';
      case WorldEventType.eraChange:
        return '时代';
      case WorldEventType.pandemic:
        return '疫病';
      case WorldEventType.seasonal:
        return '季节';
    }
  }

  String _formatEventTime(DateTime dt) {
    return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
