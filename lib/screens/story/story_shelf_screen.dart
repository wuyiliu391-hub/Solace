import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../blocs/story/story_bloc.dart';
import '../../models/story_book.dart';
import '../../repositories/local_storage_repository.dart';
import 'story_editor_screen.dart';
import 'story_read_screen.dart';

/// 故事书 · 书架
class StoryShelfScreen extends StatelessWidget {
  const StoryShelfScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final storage = RepositoryProvider.of<LocalStorageRepository>(context);
    return BlocProvider(
      create: (_) {
        final bloc = StoryBloc(storage);
        final auth = context.read<AuthBloc>().state;
        if (auth is AuthAuthenticated) {
          bloc.add(StoryLoadBooks(auth.user.id));
        }
        return bloc;
      },
      child: const _StoryShelfView(),
    );
  }
}

class _StoryShelfView extends StatelessWidget {
  const _StoryShelfView();

  String? _userId(BuildContext context) {
    final auth = context.read<AuthBloc>().state;
    return auth is AuthAuthenticated ? auth.user.id : null;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0D0D0D) : const Color(0xFFF7F5F2),
      appBar: AppBar(
        title: const Text('故事书', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: false,
        elevation: 0,
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '新建故事',
            onPressed: () => _openEditor(context, null),
          ),
        ],
      ),
      body: BlocBuilder<StoryBloc, StoryState>(
        builder: (context, state) {
          if (state.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state.books.isEmpty) {
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
            itemCount: state.books.length,
            itemBuilder: (context, index) {
              final book = state.books[index];
              return _StoryCard(
                book: book,
                onTap: () => _openBook(context, book),
                onLongPress: () => _showOptions(context, book),
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
          Icon(Icons.auto_stories_outlined, size: 64,
              color: cs.primary.withOpacity(0.4)),
          const SizedBox(height: 16),
          Text('书架空空如也',
              style: TextStyle(
                  fontSize: 16, color: cs.onSurface.withOpacity(0.6))),
          const SizedBox(height: 6),
          Text('点击右上角 + 开启一段故事',
              style: TextStyle(
                  fontSize: 13, color: cs.onSurface.withOpacity(0.35))),
        ],
      ),
    );
  }

  Future<void> _openEditor(BuildContext context, StoryBook? book) async {
    final bloc = context.read<StoryBloc>();
    final userId = _userId(context);
    if (userId == null) return;
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => StoryEditorScreen(userId: userId, book: book),
      ),
    );
    if (saved == true) bloc.add(StoryLoadBooks(userId));
  }

  Future<void> _openBook(BuildContext context, StoryBook book) async {
    final bloc = context.read<StoryBloc>();
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => StoryReadScreen(bookId: book.id)),
    );
    final userId = _userId(context);
    if (userId != null) bloc.add(StoryLoadBooks(userId));
  }

  void _showOptions(BuildContext context, StoryBook book) {
    final bloc = context.read<StoryBloc>();
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
                title: const Text('编辑设定'),
                onTap: () {
                  Navigator.pop(ctx);
                  _openEditor(context, book);
                },
              ),
              ListTile(
                leading: const Icon(Icons.copy_outlined),
                title: const Text('复制'),
                onTap: () {
                  Navigator.pop(ctx);
                  bloc.add(StoryDuplicateBook(book.id));
                },
              ),
              ListTile(
                leading: Icon(book.isArchived
                    ? Icons.unarchive_outlined
                    : Icons.archive_outlined),
                title: Text(book.isArchived ? '取消归档' : '归档'),
                onTap: () {
                  Navigator.pop(ctx);
                  bloc.add(StoryArchiveBook(book.id, !book.isArchived));
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Color(0xFFE53935)),
                title: const Text('删除', style: TextStyle(color: Color(0xFFE53935))),
                onTap: () {
                  Navigator.pop(ctx);
                  showDialog(
                    context: context,
                    builder: (d) => AlertDialog(
                      title: const Text('删除故事'),
                      content: Text('确定永久删除《${book.title}》？剧情、存档与记忆将一并清除。'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(d),
                            child: const Text('取消')),
                        TextButton(
                          onPressed: () {
                            Navigator.pop(d);
                            if (userId != null) {
                              bloc.add(StoryDeleteBook(book.id, userId));
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

class _StoryCard extends StatelessWidget {
  final StoryBook book;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _StoryCard({
    required this.book,
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
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
              child: Text(
                book.title.isEmpty ? '未命名故事' : book.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: Text(
                book.lastSegmentPreview ?? book.genre.label,
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

  Widget _buildCover(ColorScheme cs) {
    final cover = book.coverUrl;
    if (cover != null && cover.isNotEmpty) {
      final img = cover.startsWith('http')
          ? Image.network(cover, fit: BoxFit.cover)
          : Image.file(File(cover), fit: BoxFit.cover);
      return img;
    }
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [cs.primary.withOpacity(0.6), cs.tertiary.withOpacity(0.5)],
        ),
      ),
      child: Center(
        child: Icon(Icons.auto_stories,
            color: Colors.white.withOpacity(0.85), size: 40),
      ),
    );
  }
}
