// 全生命周期数字生命世界 — Phase 6
// 角色人生时间线：展示单个角色从出生到现在的关键事件

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../models/ai_character.dart';
import '../../models/life_profile.dart';
import '../../models/life_event.dart';
import '../../repositories/local_storage_repository.dart';
import '../../services/heartbeat_service.dart';
import 'world_constants.dart';

/// 角色人生时间线页面
///
/// 传入 [characterId]，会从 WorldEngine 读取生命档案并展示其人生事件。
class LifeTimelineScreen extends StatefulWidget {
  final String characterId;
  final String? characterName;

  const LifeTimelineScreen({
    super.key,
    required this.characterId,
    this.characterName,
  });

  @override
  State<LifeTimelineScreen> createState() => _LifeTimelineScreenState();
}

class _LifeTimelineScreenState extends State<LifeTimelineScreen> {
  AICharacter? _aiCharacter;
  LifeProfile? _profile;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final storage = RepositoryProvider.of<LocalStorageRepository>(context);
      final heartbeat = RepositoryProvider.of<HeartbeatService>(context);
      final engine = heartbeat.worldEngine;

      final aiChar = await storage.getAICharacter(widget.characterId);
      _aiCharacter = aiChar;
      _profile = engine?.getProfile(widget.characterId);
    } catch (e) {
      debugPrint('LifeTimelineScreen 加载失败: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<_TimelineEvent> get _events {
    final raw = _profile?.lifeEvents ?? [];
    return raw
        .map((e) {
          final map = e as Map<String, dynamic>? ?? {};
          return _TimelineEvent.fromMap(map);
        })
        .where((e) => e.timestamp != null || e.ageAt != null)
        .toList()
      ..sort((a, b) {
        final ta = a.timestamp;
        final tb = b.timestamp;
        if (ta != null && tb != null) return tb.compareTo(ta);
        return (b.ageAt ?? 0).compareTo(a.ageAt ?? 0);
      });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = widget.characterName ?? _aiCharacter?.name ?? _profile?.name ?? '未知角色';

    return Scaffold(
      backgroundColor: cs.surface,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              cs.surface,
              cs.surfaceContainerHighest.withOpacity(0.3),
              cs.surface,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildAppBar(cs, name),
              Expanded(
                child: _loading
                    ? Center(child: CircularProgressIndicator(color: cs.primary))
                    : _events.isEmpty
                        ? _buildEmptyState(cs)
                        : _buildTimeline(cs),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar(ColorScheme cs, String name) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 16, 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(Icons.arrow_back_ios_new, color: cs.onSurface, size: 20),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$name 的人生轨迹',
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _profile != null
                      ? '${_profile!.biologicalAge} 岁 · ${WorldConstants.lifeStageLabels[_profile!.currentStage] ?? ''}'
                      : '暂无生命档案',
                  style: TextStyle(color: cs.onSurface.withOpacity(0.5), fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeline(ColorScheme cs) {
    final events = _events;
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      itemCount: events.length,
      itemBuilder: (context, index) {
        final event = events[index];
        final isFirst = index == 0;
        final isLast = index == events.length - 1;
        return _buildTimelineItem(cs, event, isFirst, isLast);
      },
    );
  }

  Widget _buildTimelineItem(
      ColorScheme cs, _TimelineEvent event, bool isFirst, bool isLast) {
    final color = WorldConstants.eventSeverityColors[event.severity] ?? cs.primary;
    final icon = WorldConstants.eventTypeIcons[event.type] ?? Icons.auto_awesome;
    final typeLabel = WorldConstants.eventTypeLabels[event.type] ?? '事件';
    final ageText = event.ageAt != null ? '${event.ageAt} 岁' : '未知年龄';

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 时间节点
          Column(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  shape: BoxShape.circle,
                  border: Border.all(color: color, width: 2),
                ),
                child: Icon(icon, size: 18, color: color),
              ),
              if (!isLast)
                Expanded(
                  child: Container(width: 2, color: color.withOpacity(0.3)),
                ),
            ],
          ),
          const SizedBox(width: 14),
          // 事件卡片
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: 20),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          typeLabel,
                          style: TextStyle(
                            color: color,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        ageText,
                        style: TextStyle(
                          color: cs.onSurface.withOpacity(0.45),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    event.title.isNotEmpty ? event.title : '未命名事件',
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (event.description.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      event.description,
                      style: TextStyle(
                        color: cs.onSurface.withOpacity(0.6),
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme cs) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.stream, size: 64, color: cs.onSurface.withOpacity(0.15)),
          const SizedBox(height: 16),
          Text(
            '尚未记录人生事件',
            style: TextStyle(color: cs.onSurface.withOpacity(0.4), fontSize: 15),
          ),
          const SizedBox(height: 8),
          Text(
            '随着世界时间推进，角色会自然经历各种事件',
            style: TextStyle(color: cs.onSurface.withOpacity(0.25), fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// 内部时间线事件包装
class _TimelineEvent {
  final String type;
  final String title;
  final String description;
  final EventSeverity severity;
  final DateTime? timestamp;
  final int? ageAt;

  const _TimelineEvent({
    this.type = 'default',
    this.title = '',
    this.description = '',
    this.severity = EventSeverity.minor,
    this.timestamp,
    this.ageAt,
  });

  factory _TimelineEvent.fromMap(Map<String, dynamic> map) {
    final severityRaw = map['severity'];
    EventSeverity severity;
    if (severityRaw is int && severityRaw >= 0 && severityRaw < EventSeverity.values.length) {
      severity = EventSeverity.values[severityRaw];
    } else if (severityRaw is String) {
      severity = _parseSeverity(severityRaw);
    } else {
      severity = EventSeverity.minor;
    }

    DateTime? ts;
    if (map['timestamp'] is DateTime) {
      ts = map['timestamp'] as DateTime;
    } else if (map['timestamp'] is String) {
      ts = DateTime.tryParse(map['timestamp'] as String);
    } else if (map['timestamp'] is int) {
      ts = DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int);
    }

    return _TimelineEvent(
      type: map['type'] as String? ?? 'default',
      title: map['name'] as String? ?? map['title'] as String? ?? '',
      description: map['description'] as String? ?? '',
      severity: severity,
      timestamp: ts,
      ageAt: map['age'] as int? ?? map['ageAt'] as int?,
    );
  }

  static EventSeverity _parseSeverity(String value) {
    switch (value.toLowerCase()) {
      case 'trivial':
        return EventSeverity.trivial;
      case 'minor':
        return EventSeverity.minor;
      case 'moderate':
        return EventSeverity.moderate;
      case 'major':
        return EventSeverity.major;
      case 'life changing':
      case 'life_changing':
      case 'lifeChanging':
        return EventSeverity.lifeChanging;
      default:
        return EventSeverity.minor;
    }
  }
}
