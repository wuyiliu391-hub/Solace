import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../models/ai_character.dart';
import '../../models/character_emotion.dart';
import '../../models/life/daily_schedule.dart';
import '../../models/life/life_log.dart';
import '../../repositories/local_storage_repository.dart';
import '../../services/emotion_engine.dart';
import '../../services/life/daily_schedule_service.dart';
import '../../services/life/life_log_service.dart';
import '../../utils/character_color.dart' as cc;

/// 生活日志时间轴 — 翻阅角色最近 N 天的生活记录
///
/// 入口建议：聊天详情页「更多」菜单 →「她的生活日志」
class LifeLogScreen extends StatefulWidget {
  final AICharacter character;
  final String userId;

  const LifeLogScreen({
    super.key,
    required this.character,
    required this.userId,
  });

  @override
  State<LifeLogScreen> createState() => _LifeLogScreenState();
}

class _LifeLogScreenState extends State<LifeLogScreen> {
  bool _loading = true;
  List<LifeLog> _logs = const [];
  int _days = 7;
  bool _generating = false;
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      _loaded = true;
      _load();
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final storage = RepositoryProvider.of<LocalStorageRepository>(context);
      final db = storage.database;
      if (db == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final service = LifeLogService(db);
      final logs = await service.getRecent(
        characterId: widget.character.id,
        userId: widget.userId,
        days: _days,
      );
      if (mounted) {
        setState(() {
          _logs = logs;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 手动触发一次「生成当前时间块日志」（用于用户立即体验）
  Future<void> _generateNow() async {
    if (_generating) return;
    setState(() => _generating = true);
    try {
      final storage = RepositoryProvider.of<LocalStorageRepository>(context);
      final db = storage.database;
      if (db == null) return;

      final scheduleSvc = DailyScheduleService(db);
      final logSvc = LifeLogService(db);

      final schedule = await scheduleSvc.getOrGenerate(
        character: widget.character,
        userId: widget.userId,
        date: DateTime.now(),
      );

      final now = DateTime.now();
      final hhmm = '${now.hour.toString().padLeft(2, '0')}:'
          '${now.minute.toString().padLeft(2, '0')}';

      // 优先匹配当前块，否则匹配即将到来的块（方便用户提前看到内容）
      ScheduleBlock? target;
      for (final b in schedule.blocks) {
        if (b.contains(hhmm)) {
          target = b;
          break;
        }
      }
      target ??= schedule.blocks.firstWhere(
        (b) => b.startMinutes >= now.hour * 60 + now.minute,
        orElse: () => schedule.blocks.isNotEmpty
            ? schedule.blocks.last
            : schedule.blocks.first,
      );

      if (target == null) return;

      CharacterEmotion? emotion;
      try {
        emotion = await EmotionEngine(storage).getCurrentEmotion(
          character: widget.character,
          userId: widget.userId,
        );
      } catch (_) {}

      await logSvc.appendFromSchedule(
        characterId: widget.character.id,
        userId: widget.userId,
        block: target,
        emotion: emotion,
      );
      await _load();
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = cc.characterColor(
      colorHex: widget.character.colorHex,
      name: widget.character.name,
      cs: Theme.of(context).colorScheme,
    );
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.character.name} 的生活日志'),
        actions: [
          PopupMenuButton<int>(
            icon: const Icon(Icons.calendar_today_outlined, size: 20),
            tooltip: '时间范围',
            initialValue: _days,
            onSelected: (v) {
              setState(() => _days = v);
              _load();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 1, child: Text('仅今天')),
              PopupMenuItem(value: 3, child: Text('最近 3 天')),
              PopupMenuItem(value: 7, child: Text('最近 7 天')),
              PopupMenuItem(value: 30, child: Text('最近 30 天')),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _logs.isEmpty
                ? _buildEmpty(color)
                : _buildList(color),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _generating ? null : _generateNow,
        icon: _generating
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.auto_awesome),
        label: const Text('生成一条'),
      ),
    );
  }

  Widget _buildEmpty(Color color) {
    return ListView(
      // 保证 RefreshIndicator 能下拉
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.25),
        Icon(Icons.menu_book_outlined, size: 56, color: color.withValues(alpha: 0.5)),
        const SizedBox(height: 12),
        const Center(
          child: Text(
            '还没有日志',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 6),
        const Center(
          child: Text(
            '点右下角生成一条，或等待心跳自动写入',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ),
      ],
    );
  }

  Widget _buildList(Color color) {
    // 按日期分组
    final grouped = <String, List<LifeLog>>{};
    for (final log in _logs) {
      grouped.putIfAbsent(log.date, () => []).add(log);
    }
    final dates = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
      itemCount: dates.length,
      itemBuilder: (context, i) {
        final date = dates[i];
        final logs = grouped[date]!;
        logs.sort((a, b) => b.time.compareTo(a.time));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 8),
              child: Text(
                _dateLabel(date),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ),
            ...logs.map((l) => _buildItem(l, color)),
          ],
        );
      },
    );
  }

  Widget _buildItem(LifeLog log, Color color) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 52,
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                log.time,
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 10, right: 10),
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.85),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    log.content,
                    style: const TextStyle(fontSize: 14, height: 1.4),
                  ),
                  if ((log.mood ?? '').isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.mood, size: 12, color: color.withValues(alpha: 0.7)),
                        const SizedBox(width: 4),
                        Text(
                          log.mood!,
                          style: TextStyle(
                            fontSize: 11,
                            color: color.withValues(alpha: 0.9),
                          ),
                        ),
                        if (log.source == LifeLogSource.crossVisit) ...[
                          const SizedBox(width: 8),
                          Text(
                            '· 串门',
                            style: TextStyle(
                              fontSize: 11,
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.5),
                            ),
                          ),
                        ] else if (log.source == LifeLogSource.share) ...[
                          const SizedBox(width: 8),
                          Text(
                            '· 分享',
                            style: TextStyle(
                              fontSize: 11,
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.5),
                            ),
                          ),
                        ],
                      ],
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

  String _dateLabel(String date) {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final yesterday = DateFormat('yyyy-MM-dd')
        .format(DateTime.now().subtract(const Duration(days: 1)));
    if (date == today) return '今天';
    if (date == yesterday) return '昨天';
    try {
      final d = DateTime.parse(date);
      return DateFormat('M月d日 EEEE', 'zh_CN').format(d);
    } catch (_) {
      return date;
    }
  }
}
