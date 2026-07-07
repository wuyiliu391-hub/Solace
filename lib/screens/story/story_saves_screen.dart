import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../blocs/story/story_play_bloc.dart';
import '../../models/story_book.dart';
import '../../models/story_save.dart';
import '../../repositories/local_storage_repository.dart';

/// 故事书 · 存档管理
class StorySavesScreen extends StatefulWidget {
  final StoryBook book;
  const StorySavesScreen({super.key, required this.book});

  @override
  State<StorySavesScreen> createState() => _StorySavesScreenState();
}

class _StorySavesScreenState extends State<StorySavesScreen> {
  List<StorySave> _saves = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final storage = RepositoryProvider.of<LocalStorageRepository>(context);
    final saves = await storage.getStorySaves(widget.book.id);
    if (mounted) {
      setState(() {
        _saves = saves;
        _loading = false;
      });
    }
  }

  Future<void> _createSave() async {
    final nameCtrl = TextEditingController(
        text: '存档 ${DateFormat('MM-dd HH:mm').format(DateTime.now())}');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建存档'),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: '存档名称'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, nameCtrl.text),
              child: const Text('保存')),
        ],
      ),
    );
    if (name == null) return;
    if (!mounted) return;
    context.read<StoryPlayBloc>().add(StoryPlayCreateSave(name.trim()));
    Navigator.pop(context);
  }

  void _loadSave(StorySave save) {
    context.read<StoryPlayBloc>().add(StoryPlayLoadSave(save.id));
    Navigator.pop(context);
  }

  Future<void> _deleteSave(StorySave save) async {
    final storage = RepositoryProvider.of<LocalStorageRepository>(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除存档'),
        content: Text('确定删除「${save.name}」？该存档的剧情将被清除。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFE53935)),
              child: const Text('删除')),
        ],
      ),
    );
    if (ok == true) {
      await storage.deleteStorySave(save.id);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final currentId = widget.book.currentSaveId;
    return Scaffold(
      appBar: AppBar(
        title: const Text('存档'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '新建存档',
            onPressed: _createSave,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _saves.isEmpty
              ? Center(
                  child: Text('暂无存档',
                      style:
                          TextStyle(color: cs.onSurface.withOpacity(0.4))))
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: _saves.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final save = _saves[index];
                    final isCurrent = save.id == currentId;
                    return Card(
                      elevation: 0,
                      color: isCurrent
                          ? cs.primaryContainer.withOpacity(0.4)
                          : cs.surfaceContainerHighest.withOpacity(0.3),
                      child: ListTile(
                        leading: Icon(
                          isCurrent ? Icons.bookmark : Icons.bookmark_border,
                          color: isCurrent ? cs.primary : null,
                        ),
                        title: Text(save.name.isEmpty ? '未命名存档' : save.name),
                        subtitle: Text(
                            '${save.segmentCount} 段 · ${DateFormat('yyyy-MM-dd HH:mm').format(save.updatedAt)}'),
                        trailing: PopupMenuButton<String>(
                          onSelected: (v) {
                            if (v == 'load') _loadSave(save);
                            if (v == 'delete') _deleteSave(save);
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(
                                value: 'load', child: Text('读取此存档')),
                            const PopupMenuItem(
                                value: 'delete', child: Text('删除')),
                          ],
                        ),
                        onTap: isCurrent ? null : () => _loadSave(save),
                      ),
                    );
                  },
                ),
    );
  }
}
