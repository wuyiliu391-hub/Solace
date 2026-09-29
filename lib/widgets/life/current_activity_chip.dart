import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../models/ai_character.dart';
import '../../models/life/daily_schedule.dart';
import '../../repositories/local_storage_repository.dart';
import '../../services/life/daily_schedule_service.dart';

/// 当前活动状态条 — 显示「此刻：正在工作 · 有点累」
///
/// 用法：
/// ```dart
/// CurrentActivityChip(character: c, userId: uid)
/// ```
///
/// 设计：异步读今日日程的当前时间块；未生成日程时自动触发一次规则生成。
class CurrentActivityChip extends StatefulWidget {
  final AICharacter character;
  final String userId;
  final EdgeInsets padding;
  final bool compact;

  const CurrentActivityChip({
    super.key,
    required this.character,
    required this.userId,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    this.compact = false,
  });

  @override
  State<CurrentActivityChip> createState() => _CurrentActivityChipState();
}

class _CurrentActivityChipState extends State<CurrentActivityChip> {
  ScheduleBlock? _block;
  bool _loading = true;
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // RepositoryProvider.of 依赖 InheritedWidget，必须在
    // didChangeDependencies 之后才能安全查找
    if (!_loaded) {
      _loaded = true;
      _load();
    }
  }

  @override
  void didUpdateWidget(covariant CurrentActivityChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.character.id != widget.character.id ||
        oldWidget.userId != widget.userId) {
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final storage = RepositoryProvider.of<LocalStorageRepository>(context);
      final db = storage.database;
      if (db == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final service = DailyScheduleService(db);
      final block = await service.getCurrentBlock(
        character: widget.character,
        userId: widget.userId,
      );
      if (mounted) {
        setState(() {
          _block = block;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _block == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.04);
    final fg = theme.colorScheme.onSurface.withValues(alpha: 0.72);

    return Container(
      padding: widget.padding,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_iconFor(_block!.activity), size: 13, color: fg),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              widget.compact
                  ? _block!.label
                  : '此刻：${_block!.label}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: fg),
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconFor(LifeActivity a) {
    switch (a) {
      case LifeActivity.sleep:
        return Icons.bedtime_outlined;
      case LifeActivity.wake:
        return Icons.wb_twilight;
      case LifeActivity.commute:
        return Icons.directions_bus_outlined;
      case LifeActivity.work:
        return Icons.work_outline;
      case LifeActivity.meal:
        return Icons.restaurant_outlined;
      case LifeActivity.rest:
        return Icons.self_improvement;
      case LifeActivity.hobby:
        return Icons.videogame_asset_outlined;
      case LifeActivity.social:
        return Icons.people_outline;
      case LifeActivity.exercise:
        return Icons.fitness_center;
      case LifeActivity.relax:
        return Icons.weekend_outlined;
      case LifeActivity.outing:
        return Icons.directions_walk;
    }
  }
}
