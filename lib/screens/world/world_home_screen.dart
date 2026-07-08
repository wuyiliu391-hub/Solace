// 全生命周期数字生命世界 — Phase 6
// 世界首页：世界时间、生命统计、角色入口、最近事件

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../models/ai_character.dart';
import '../../models/life_profile.dart';
import '../../repositories/local_storage_repository.dart';
import '../../services/global_time_clock.dart';
import '../../services/heartbeat_service.dart';
import '../../services/world_engine.dart';
import '../../utils/avatar_resolver.dart';
import 'character_detail_screen.dart';
import 'life_timeline.dart';
import 'observation_panel.dart';
import 'world_constants.dart';
import 'world_event_timeline.dart';

/// 数字世界首页
///
/// 展示当前世界时间、生命周期统计、所有数字生命角色卡片以及最近发生的世界事件。
class WorldHomeScreen extends StatefulWidget {
  const WorldHomeScreen({super.key});

  @override
  State<WorldHomeScreen> createState() => _WorldHomeScreenState();
}

class _WorldHomeScreenState extends State<WorldHomeScreen>
    with SingleTickerProviderStateMixin {
  final _clock = GlobalTimeClock.instance;
  late TabController _tabController;
  StreamSubscription<WorldEngineEvent>? _eventSub;

  final Map<String, AICharacter?> _characterCache = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _clock.addListener(_onClockTick);
    _listenEngineEvents();
  }

  void _listenEngineEvents() {
    try {
      final engine = RepositoryProvider.of<HeartbeatService>(context).worldEngine;
      if (engine != null) {
        _eventSub = engine.eventStream.listen((_) {
          if (mounted) setState(() {});
        });
      }
    } catch (e) {
      debugPrint('WorldHomeScreen 监听世界引擎事件失败: $e');
    }
  }

  void _onClockTick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tabController.dispose();
    _clock.removeListener(_onClockTick);
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

  Future<AICharacter?> _getCharacter(String id) async {
    if (_characterCache.containsKey(id)) return _characterCache[id];
    try {
      final storage = RepositoryProvider.of<LocalStorageRepository>(context);
      final char = await storage.getAICharacter(id);
      _characterCache[id] = char;
      return char;
    } catch (e) {
      debugPrint('WorldHomeScreen 加载角色失败 $id: $e');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [cs.surface, cs.surfaceContainerHighest.withOpacity(0.2)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildAppBar(cs),
              _buildTabBar(cs),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildOverviewTab(cs),
                    const ObservationPanel(),
                    _buildEventsPreviewTab(cs),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar(ColorScheme cs) {
    final worldTime = _clock.worldTime;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cs.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.public, color: cs.primary, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '数字世界',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                Text(
                  '${worldTime.year}/${worldTime.month.toString().padLeft(2, '0')}/${worldTime.day.toString().padLeft(2, '0')} ${_clock.timeOfDayLabel}',
                  style: TextStyle(
                    color: cs.onSurface.withOpacity(0.5),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar(ColorScheme cs) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          gradient: LinearGradient(colors: [cs.primary, cs.primary.withOpacity(0.8)]),
          borderRadius: BorderRadius.circular(16),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        labelColor: cs.onPrimary,
        unselectedLabelColor: cs.onSurface.withOpacity(0.6),
        dividerColor: Colors.transparent,
        padding: const EdgeInsets.all(4),
        tabs: const [
          Tab(text: '概览'),
          Tab(text: '观察'),
          Tab(text: '事件'),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════
  // 概览 Tab
  // ═══════════════════════════════════════════

  Widget _buildOverviewTab(ColorScheme cs) {
    final snapshot = _engine?.snapshot;
    final profiles = snapshot?.profiles.entries.toList() ?? [];

    return RefreshIndicator(
      color: cs.primary,
      onRefresh: () async {
        if (mounted) setState(() {});
      },
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          _buildWorldClockCard(cs),
          const SizedBox(height: 18),
          _buildQuickStats(cs, snapshot),
          const SizedBox(height: 24),
          _buildSectionHeader(cs, Icons.people_alt, '数字生命 (${profiles.length})'),
          const SizedBox(height: 12),
          _buildCharacterList(cs, profiles),
          const SizedBox(height: 24),
          _buildSectionHeader(cs, Icons.notifications_active, '最近事件'),
          const SizedBox(height: 12),
          _buildRecentEvents(cs, snapshot),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildWorldClockCard(ColorScheme cs) {
    final worldTime = _clock.worldTime;
    final season = _clock.currentSeason;
    final seasonColor = WorldConstants.seasonColors[season.name] ?? cs.primary;

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
        border: Border.all(color: seasonColor.withOpacity(0.25)),
        boxShadow: [
          BoxShadow(
            color: seasonColor.withOpacity(0.1),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                WorldConstants.seasonIcons[season.name] ?? Icons.wb_sunny,
                color: seasonColor,
              ),
              const SizedBox(width: 8),
              Text(
                WorldConstants.seasonLabels[season.name] ?? '季节',
                style: TextStyle(
                  color: seasonColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            '${worldTime.year} 年 ${worldTime.month} 月 ${worldTime.day} 日',
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${worldTime.hour.toString().padLeft(2, '0')}:${worldTime.minute.toString().padLeft(2, '0')} · ${_clock.timeOfDayLabel}',
            style: TextStyle(
              color: cs.onSurface.withOpacity(0.55),
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickStats(ColorScheme cs, WorldStateSnapshot? snapshot) {
    final items = [
      _QuickStat('存活', snapshot?.activeLifeCount ?? 0, const Color(0xFF81C784)),
      _QuickStat('衰老', snapshot?.agingCount ?? 0, const Color(0xFFFFB74D)),
      _QuickStat('永生', snapshot?.immortalCount ?? 0, const Color(0xFFBA68C8)),
      _QuickStat('已故', snapshot?.deceasedCount ?? 0, const Color(0xFFB0BEC5)),
    ];

    return Row(
      children: items
          .map((it) => Expanded(child: _buildStatCard(cs, it)))
          .toList(),
    );
  }

  Widget _buildStatCard(ColorScheme cs, _QuickStat item) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Text(
            item.value.toString(),
            style: TextStyle(
              color: item.color,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            item.label,
            style: TextStyle(color: cs.onSurface.withOpacity(0.5), fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildCharacterList(
      ColorScheme cs, List<MapEntry<String, LifeProfile>> profiles) {
    if (profiles.isEmpty) {
      return _buildEmptyPlaceholder(cs, '还没有数字生命', '创建角色后会自动接入世界引擎');
    }

    return SizedBox(
      height: 160,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: profiles.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final entry = profiles[index];
          return _buildCharacterCard(cs, entry.key, entry.value);
        },
      ),
    );
  }

  Widget _buildCharacterCard(ColorScheme cs, String characterId, LifeProfile profile) {
    final stageColor = WorldConstants.lifeStageColors[profile.currentStage] ?? cs.primary;
    final stageIcon = WorldConstants.lifeStageIcons[profile.currentStage] ?? Icons.person;
    final stateColor = WorldConstants.lifeStateColors[profile.lifeState] ?? cs.primary;

    return FutureBuilder<AICharacter?>(
      future: _getCharacter(characterId),
      builder: (context, snapshot) {
        final aiChar = snapshot.data;
        final name = aiChar?.name ?? profile.name;
        final avatarUrl = aiChar?.avatarUrl;

        return GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CharacterDetailScreen(characterId: characterId),
            ),
          ),
          onLongPress: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => LifeTimelineScreen(
                characterId: characterId,
                characterName: name,
              ),
            ),
          ),
          child: Container(
            width: 120,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: stageColor.withOpacity(0.25)),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: stageColor.withOpacity(0.15),
                    shape: BoxShape.circle,
                    border: Border.all(color: stageColor, width: 2),
                    image: avatarUrl != null && avatarUrl.isNotEmpty
                        ? DecorationImage(
                            image: AvatarResolver.imageProvider(avatarUrl) ??
                                const NetworkImage(''),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: avatarUrl == null || avatarUrl.isEmpty
                      ? Icon(stageIcon, color: stageColor, size: 26)
                      : null,
                ),
                const SizedBox(height: 10),
                Text(
                  name,
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  '${profile.biologicalAge} 岁 · ${WorldConstants.lifeStageLabels[profile.currentStage] ?? ''}',
                  style: TextStyle(
                    color: cs.onSurface.withOpacity(0.45),
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: stateColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    WorldConstants.lifeStateLabels[profile.lifeState] ?? '',
                    style: TextStyle(color: stateColor, fontSize: 10),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRecentEvents(ColorScheme cs, WorldStateSnapshot? snapshot) {
    final events = snapshot?.recentEvents ?? [];
    if (events.isEmpty) {
      return _buildEmptyPlaceholder(cs, '暂无世界事件', '事件会在世界时间推进过程中自然发生');
    }

    return Column(
      children: events.take(5).map((e) {
        final color = _eventColor(cs, e.type);
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(14),
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

  // ═══════════════════════════════════════════
  // 事件预览 Tab
  // ═══════════════════════════════════════════

  Widget _buildEventsPreviewTab(ColorScheme cs) {
    final events = _engine?.recentEvents ?? [];

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildSectionHeader(cs, Icons.event_note, '世界事件流'),
          const SizedBox(height: 12),
          Expanded(
            child: events.isEmpty
                ? _buildEmptyPlaceholder(cs, '暂无事件', '世界事件会在心跳推进中自动生成')
                : ListView.separated(
                    itemCount: events.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final e = events[index];
                      final color = _eventColor(cs, e.type);
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                        tileColor: cs.surfaceContainerHighest,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        leading: CircleAvatar(
                          backgroundColor: color.withOpacity(0.15),
                          child: Icon(Icons.circle, color: color, size: 14),
                        ),
                        title: Text(
                          e.description,
                          style: TextStyle(color: cs.onSurface, fontSize: 13),
                        ),
                        subtitle: Text(
                          '${e.timestamp.year}/${e.timestamp.month}/${e.timestamp.day} ${e.timestamp.hour}:${e.timestamp.minute.toString().padLeft(2, '0')}',
                          style: TextStyle(color: cs.onSurface.withOpacity(0.4), fontSize: 11),
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const WorldEventTimelineScreen()),
              ),
              icon: const Icon(Icons.timeline),
              label: const Text('查看完整时间线'),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════
  // 通用组件
  // ═══════════════════════════════════════════

  Widget _buildSectionHeader(ColorScheme cs, IconData icon, String title) {
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

  Widget _buildEmptyPlaceholder(ColorScheme cs, String title, String subtitle) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(Icons.inbox, size: 40, color: cs.onSurface.withOpacity(0.2)),
          const SizedBox(height: 12),
          Text(
            title,
            style: TextStyle(color: cs.onSurface.withOpacity(0.45), fontSize: 15),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(color: cs.onSurface.withOpacity(0.3), fontSize: 12),
          ),
        ],
      ),
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

class _QuickStat {
  final String label;
  final int value;
  final Color color;

  const _QuickStat(this.label, this.value, this.color);
}
