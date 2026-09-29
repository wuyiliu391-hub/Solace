import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../repositories/local_storage_repository.dart';
import '../../services/storage_cleanup_service.dart';
import '../../utils/avatar_resolver.dart';

/// 存储管理：按会话/类型精细勾选 + 批量清理
class StorageCleanupScreen extends StatefulWidget {
  const StorageCleanupScreen({super.key});

  @override
  State<StorageCleanupScreen> createState() => _StorageCleanupScreenState();
}

class _StorageCleanupScreenState extends State<StorageCleanupScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  StorageAnalysis? _analysis;
  bool _loading = true;
  bool _cleaning = false;
  final Set<String> _selected = {};
  int _keepDays = 30;
  int _keepPerChat = 200;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final storage = RepositoryProvider.of<LocalStorageRepository>(context);
    final a = await StorageCleanupService.analyze(storage);
    if (!mounted) return;
    setState(() {
      _analysis = a;
      _loading = false;
      _selected.removeWhere((k) => !a.buckets.any((b) => b.key == k));
    });
  }

  List<StorageBucket> _tabBuckets(int index) {
    final a = _analysis;
    if (a == null) return const [];
    switch (index) {
      case 0:
        return a.byCategory('session').toList()
          ..sort((x, y) => y.bytes.compareTo(x.bytes));
      case 1:
        return a.byCategory('character').toList()
          ..sort((x, y) => y.bytes.compareTo(x.bytes));
      default:
        return a.buckets
            .where((b) =>
                b.category == 'type' ||
                b.category == 'file' ||
                b.category == 'system')
            .toList()
          ..sort((x, y) => y.bytes.compareTo(x.bytes));
    }
  }

  void _toggleAll(int tab, bool select) {
    final list = _tabBuckets(tab);
    setState(() {
      if (select) {
        _selected.addAll(list.where((b) => b.canClean).map((b) => b.key));
      } else {
        _selected.removeAll(list.map((b) => b.key));
      }
    });
  }

  void _invert(int tab) {
    final list = _tabBuckets(tab);
    setState(() {
      for (final b in list) {
        if (!b.canClean) continue;
        if (_selected.contains(b.key)) {
          _selected.remove(b.key);
        } else {
          _selected.add(b.key);
        }
      }
    });
  }

  int _selectedBytes(int? tab) {
    final a = _analysis;
    if (a == null) return 0;
    final list = tab == null ? a.buckets : _tabBuckets(tab);
    return list
        .where((b) => _selected.contains(b.key))
        .fold<int>(0, (s, b) => s + b.bytes);
  }

  Future<void> _runClean() async {
    if (_selected.isEmpty || _analysis == null) return;
    final storage = RepositoryProvider.of<LocalStorageRepository>(context);
    final n = _selected.length;
    final bytes = _selectedBytes(null);

    final warnings = <String>[];
    if (_selected.any((k) => k.startsWith('voice_model:sensevoice'))) {
      warnings.add('将删除本地语音识别模型，离线听写需重新导入');
    }
    if (_selected.any((k) => k == 'dir_chat_images' || k == 'dir_backup_files')) {
      warnings.add('聊天图片/备份还原附件将被删除，界面里对应图可能无法显示');
    }
    if (_selected.any((k) => k == 'dir_avatars' || k == 'dir_ai_avatars')) {
      warnings.add('头像文件将被删除');
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('批量清理 $n 项'),
        content: Text(
          '预计涉及约 ${StorageCleanupService.formatBytes(bytes)}。\n'
          '保留最近 $_keepDays 天；每会话最多保留 $_keepPerChat 条。\n'
          '「收藏」消息尽量保留；记忆会保留置顶/关键条目。\n'
          '${warnings.isEmpty ? '' : '\n⚠ ${warnings.join('\n⚠ ')}\n'}'
          '\n此操作不可撤销，建议先导出备份。',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('开始清理')),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _cleaning = true);
    final freed = await StorageCleanupService.cleanMany(
      storage,
      _selected.toList(),
      keepDays: _keepDays,
      keepMessagesPerChat: _keepPerChat,
      vacuumAfter: true,
    );
    if (!mounted) return;
    setState(() {
      _cleaning = false;
      _selected.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content:
          Text('清理完成，约释放 ${StorageCleanupService.formatBytes(freed)}'),
    ));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final a = _analysis;
    final selectedBytes = _selectedBytes(null);

    return Scaffold(
      appBar: AppBar(
        title: const Text('存储管理'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: '按会话'),
            Tab(text: '按角色记忆'),
            Tab(text: '按类型/文件'),
          ],
        ),
      ),
      floatingActionButton: _selected.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _cleaning ? null : _runClean,
              icon: _cleaning
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cleaning_services_outlined),
              label: Text(_cleaning
                  ? '清理中…'
                  : '清理 ${_selected.length} 项'),
            ),
      body: _loading || a == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _SummaryBar(
                  analysis: a,
                  selectedBytes: selectedBytes,
                  selectedCount: _selected.length,
                  keepDays: _keepDays,
                  keepPerChat: _keepPerChat,
                  onKeepDays: (d) => setState(() => _keepDays = d),
                  onKeepPerChat: (n) => setState(() => _keepPerChat = n),
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tab,
                    children: [
                      _buildList(0, cs),
                      _buildList(1, cs),
                      _buildList(2, cs),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildList(int tab, ColorScheme cs) {
    final list = _tabBuckets(tab);
    if (list.isEmpty) {
      return const Center(child: Text('暂无数据'));
    }
    final allSelected =
        list.where((b) => b.canClean).every((b) => _selected.contains(b.key));

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
        itemCount: list.length + 1,
        itemBuilder: (context, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: () => _toggleAll(tab, !allSelected),
                    icon: Icon(
                      allSelected
                          ? Icons.deselect
                          : Icons.select_all_rounded,
                      size: 18,
                    ),
                    label: Text(allSelected ? '取消全选' : '全选本页'),
                  ),
                  TextButton.icon(
                    onPressed: () => _invert(tab),
                    icon: const Icon(Icons.swap_vert, size: 18),
                    label: const Text('反选'),
                  ),
                  const Spacer(),
                  Text(
                    '本页已选 ${_selectedBytes(tab) == 0 ? 0 : list.where((b) => _selected.contains(b.key)).length}',
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurfaceVariant.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            );
          }
          final b = list[i - 1];
          return _BucketTile(
            bucket: b,
            selected: _selected.contains(b.key),
            onChanged: (v) {
              setState(() {
                if (v == true) {
                  _selected.add(b.key);
                } else {
                  _selected.remove(b.key);
                }
              });
            },
          );
        },
      ),
    );
  }
}

class _SummaryBar extends StatelessWidget {
  final StorageAnalysis analysis;
  final int selectedBytes;
  final int selectedCount;
  final int keepDays;
  final int keepPerChat;
  final ValueChanged<int> onKeepDays;
  final ValueChanged<int> onKeepPerChat;

  const _SummaryBar({
    required this.analysis,
    required this.selectedBytes,
    required this.selectedCount,
    required this.keepDays,
    required this.keepPerChat,
    required this.onKeepDays,
    required this.onKeepPerChat,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant.withOpacity(0.4)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '本地约 ${StorageCleanupService.formatBytes(analysis.totalBytes)}'
            '${selectedCount > 0 ? ' · 已选 $selectedCount 项 ≈ ${StorageCleanupService.formatBytes(selectedBytes)}' : ''}',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                const Text('保留最近', style: TextStyle(fontSize: 12)),
                const SizedBox(width: 6),
                SegmentedButton<int>(
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  segments: const [
                    ButtonSegment(value: 7, label: Text('7天')),
                    ButtonSegment(value: 30, label: Text('30天')),
                    ButtonSegment(value: 90, label: Text('90天')),
                  ],
                  selected: {keepDays},
                  onSelectionChanged: (s) => onKeepDays(s.first),
                ),
                const SizedBox(width: 12),
                const Text('每会话留', style: TextStyle(fontSize: 12)),
                const SizedBox(width: 6),
                SegmentedButton<int>(
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  segments: const [
                    ButtonSegment(value: 50, label: Text('50')),
                    ButtonSegment(value: 200, label: Text('200')),
                    ButtonSegment(value: 500, label: Text('500')),
                  ],
                  selected: {keepPerChat},
                  onSelectionChanged: (s) => onKeepPerChat(s.first),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BucketTile extends StatelessWidget {
  final StorageBucket bucket;
  final bool selected;
  final ValueChanged<bool?> onChanged;
  const _BucketTile({
    required this.bucket,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isSession = bucket.category == 'session';
    final isChar = bucket.category == 'character';

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: CheckboxListTile(
        value: selected,
        onChanged: bucket.canClean ? onChanged : null,
        controlAffinity: ListTileControlAffinity.leading,
        title: Row(
          children: [
            if (isSession || isChar) ...[
              CircleAvatar(
                radius: 14,
                backgroundColor: cs.surfaceContainerHighest,
                child: bucket.avatarUrl != null &&
                        bucket.avatarUrl!.isNotEmpty
                    ? ClipOval(
                        child: SizedBox(
                          width: 28,
                          height: 28,
                          child: AvatarResolver.imageWidget(
                            bucket.avatarUrl!,
                            fit: BoxFit.cover,
                            onError: () => Text(
                              (bucket.entityName ?? '?').isEmpty
                                  ? '?'
                                  : bucket.entityName![0],
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                      )
                    : Text(
                        (bucket.entityName ?? bucket.label).isEmpty
                            ? '?'
                            : (bucket.entityName ?? bucket.label)[0],
                        style: const TextStyle(fontSize: 12),
                      ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text(
                bucket.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        subtitle: Text(
          '${StorageCleanupService.formatBytes(bucket.bytes)} · ${bucket.hint}',
          style: TextStyle(
            fontSize: 12,
            color: cs.onSurfaceVariant.withOpacity(0.7),
          ),
        ),
        secondary: Text(
          StorageCleanupService.formatBytes(bucket.bytes),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: cs.primary,
          ),
        ),
      ),
    );
  }
}
