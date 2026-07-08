import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../blocs/novel/novel_bloc.dart';
import '../../models/novel.dart';
import '../../repositories/local_storage_repository.dart';
import '../../services/ai_service.dart';
import 'novel_write_screen.dart';

/// 小说书架
class NovelShelfScreen extends StatelessWidget {
  const NovelShelfScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final storage = RepositoryProvider.of<LocalStorageRepository>(context);
    final aiService = context.read<AIService>();
    return BlocProvider(
      create: (_) {
        final bloc = NovelBloc(storage, aiService);
        final auth = context.read<AuthBloc>().state;
        if (auth is AuthAuthenticated) {
          bloc.add(NovelLoadList(auth.user.id));
        }
        return bloc;
      },
      child: const _NovelShelfView(),
    );
  }
}

class _NovelShelfView extends StatelessWidget {
  const _NovelShelfView();

  String? _userId(BuildContext context) {
    final auth = context.read<AuthBloc>().state;
    return auth is AuthAuthenticated ? auth.user.id : null;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0D0D0D) : const Color(0xFFF7F5F2),
      appBar: AppBar(
        title: const Text('小说', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: false,
        elevation: 0,
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '新建小说',
            onPressed: () => _showCreateDialog(context),
          ),
        ],
      ),
      body: BlocConsumer<NovelBloc, NovelState>(
        listener: (context, state) {
          if (state.error != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(state.error!), duration: const Duration(seconds: 2)),
            );
          }
        },
        builder: (context, state) {
          if (state.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          final novels = state.novels.where((n) => !n.isArchived).toList();
          if (novels.isEmpty) {
            return _buildEmpty(context);
          }
          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.68,
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
            ),
            itemCount: novels.length,
            itemBuilder: (context, index) {
              final novel = novels[index];
              return _NovelCard(
                novel: novel,
                onTap: () => _openWrite(context, novel),
                onLongPress: () => _showOptions(context, novel),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.menu_book_outlined,
              size: 64, color: cs.primary.withOpacity(0.4)),
          const SizedBox(height: 16),
          Text('书架空空如也',
              style: TextStyle(
                  fontSize: 16, color: cs.onSurface.withOpacity(0.6))),
          const SizedBox(height: 6),
          Text('点击右上角 + 开始创作',
              style: TextStyle(
                  fontSize: 13, color: cs.onSurface.withOpacity(0.35))),
          const SizedBox(height: 24),
          FilledButton.tonal(
            onPressed: () => _showCreateDialog(context),
            child: const Text('新建小说'),
          ),
        ],
      ),
    );
  }

  Future<void> _showCreateDialog(BuildContext context) async {
    final bloc = context.read<NovelBloc>();
    final userId = _userId(context);
    if (userId == null) return;

    final titleCtrl = TextEditingController();
    final synopsisCtrl = TextEditingController();
    NovelGenre selectedGenre = NovelGenre.free;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('新建小说'),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: '标题',
                    hintText: '给你的小说起个名字',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: synopsisCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: '简介（选填）',
                    hintText: '一句话介绍故事',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<NovelGenre>(
                  value: selectedGenre,
                  decoration: const InputDecoration(labelText: '类型'),
                  items: NovelGenre.values
                      .map((g) => DropdownMenuItem(value: g, child: Text(g.label)))
                      .toList(),
                  onChanged: (v) => setS(() => selectedGenre = v ?? NovelGenre.free),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final title = titleCtrl.text.trim();
                if (title.isEmpty) return;
                final now = DateTime.now();
                final novel = Novel(
                  id: const Uuid().v4(),
                  userId: userId,
                  title: title,
                  synopsis: synopsisCtrl.text.trim(),
                  genre: selectedGenre,
                  createdAt: now,
                  updatedAt: now,
                );
                bloc.add(NovelCreate(novel));
                Navigator.pop(ctx);
                // 创建后进入编辑器
                Future.delayed(const Duration(milliseconds: 300), () {
                  if (context.mounted) _openWrite(context, novel);
                });
              },
              child: const Text('创建'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openWrite(BuildContext context, Novel novel) async {
    final bloc = context.read<NovelBloc>();
    final userId = _userId(context);
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => NovelWriteScreen(novel: novel)),
    );
    if (userId != null) bloc.add(NovelLoadList(userId));
  }

  void _showOptions(BuildContext context, Novel novel) {
    final bloc = context.read<NovelBloc>();
    final userId = _userId(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: Theme.of(ctx).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(ctx).colorScheme.onSurfaceVariant.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('编辑'),
                onTap: () {
                  Navigator.pop(ctx);
                  _openWrite(context, novel);
                },
              ),
              ListTile(
                leading: const Icon(Icons.archive_outlined),
                title: const Text('归档'),
                onTap: () {
                  Navigator.pop(ctx);
                  bloc.add(NovelArchive(novelId: novel.id, archived: true));
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline,
                    color: Color(0xFFE53935)),
                title: const Text('删除',
                    style: TextStyle(color: Color(0xFFE53935))),
                onTap: () {
                  Navigator.pop(ctx);
                  showDialog(
                    context: context,
                    builder: (d) => AlertDialog(
                      title: const Text('删除小说'),
                      content: Text('确定永久删除《${novel.title}》？所有章节将一并删除。'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(d),
                          child: const Text('取消'),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.pop(d);
                            if (userId != null) {
                              bloc.add(NovelDelete(
                                  novelId: novel.id, userId: userId));
                            }
                          },
                          style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFFE53935)),
                          child: const Text('删除'),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// 书卡
// ─────────────────────────────────────────────────────────────────

class _NovelCard extends StatelessWidget {
  final Novel novel;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _NovelCard({
    required this.novel,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: cs.surfaceContainerHighest.withOpacity(0.4),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _buildCover(cs)),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 2),
              child: Text(
                novel.title.isEmpty ? '未命名小说' : novel.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 4),
              child: Text(
                '${novel.chapterCount} 章 · ${_fmtWords(novel.totalWords)}',
                style: TextStyle(
                    fontSize: 11, color: cs.onSurface.withOpacity(0.45)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: Text(
                novel.lastChapterPreview != null || novel.synopsis.isNotEmpty
                    ? (novel.lastChapterPreview ?? novel.synopsis)
                    : novel.genre.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11.5, color: cs.onSurface.withOpacity(0.5)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _fmtWords(int w) {
    if (w >= 10000) return '${(w / 10000).toStringAsFixed(1)}万字';
    return '$w 字';
  }

  Widget _buildCover(ColorScheme cs) {
    // 暂不支持本地封面图，用渐变占位
    final colors = _genreColors(novel.genre, cs);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
      ),
      child: Stack(
        children: [
          Center(
            child: Text(
              novel.title.isNotEmpty ? novel.title[0] : '书',
              style: TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.bold,
                  color: Colors.white.withOpacity(0.9)),
            ),
          ),
          Positioned(
            bottom: 6,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.35),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                novel.genre.label,
                style: const TextStyle(
                    fontSize: 10,
                    color: Colors.white,
                    fontWeight: FontWeight.w500),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Color> _genreColors(NovelGenre genre, ColorScheme cs) {
    switch (genre) {
      case NovelGenre.romance:
        return [const Color(0xFFFF6B9D), const Color(0xFFFF8E53)];
      case NovelGenre.fantasy:
        return [const Color(0xFF4A00E0), const Color(0xFF8E2DE2)];
      case NovelGenre.urban:
        return [const Color(0xFF1A237E), const Color(0xFF283593)];
      case NovelGenre.suspense:
        return [const Color(0xFF212121), const Color(0xFF424242)];
      case NovelGenre.historical:
        return [const Color(0xFF5D4037), const Color(0xFF8D6E63)];
      case NovelGenre.scifi:
        return [const Color(0xFF006064), const Color(0xFF00BCD4)];
      case NovelGenre.horror:
        return [const Color(0xFF1A0000), const Color(0xFF4E0000)];
      case NovelGenre.free:
        return [cs.primary.withOpacity(0.7), cs.tertiary.withOpacity(0.6)];
    }
  }
}