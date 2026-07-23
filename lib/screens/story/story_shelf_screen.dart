import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../blocs/story/story_bloc.dart';
import '../../models/story_book.dart';
import '../../repositories/local_storage_repository.dart';
import 'story_editor_screen.dart';
import 'story_read_screen.dart';

/// 题材配色 — 书架条目左边圆标与标签的强调色
const Map<StoryGenre, Color> _genreColors = {
  StoryGenre.romance: Color(0xFFE57399),
  StoryGenre.yandere: Color(0xFFEF5350),
  StoryGenre.darkArt: Color(0xFF7E57C2),
  StoryGenre.free: Color(0xFF26A69A),
};

/// 把更新时间转成「x 天前」式口语标签
String _relativeTime(DateTime t) {
  final diff = DateTime.now().difference(t);
  if (diff.inMinutes < 1) return '刚刚';
  if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
  if (diff.inHours < 24) return '${diff.inHours} 小时前';
  if (diff.inDays < 30) return '${diff.inDays} 天前';
  if (diff.inDays < 365) return '${(diff.inDays / 30).floor()} 个月前';
  return '${(diff.inDays / 365).floor()} 年前';
}

/// 题材小标签
Widget _genreChip(String label, Color color, ColorScheme cs) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
    decoration: BoxDecoration(
      color: color.withOpacity(0.14),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: color,
      ),
    ),
  );
}

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
          // 归档排末尾，其余按最近更新在前
          final books = [...state.books]
            ..sort((a, b) {
              if (a.isArchived != b.isArchived) return a.isArchived ? 1 : -1;
              return b.updatedAt.compareTo(a.updatedAt);
            });
          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            itemCount: books.length,
            itemBuilder: (context, index) {
              final book = books[index];
              return _StoryTile(
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

/// 故事条目 — 横条样式（与通讯录一致），避免封面尺寸报错
class _StoryTile extends StatelessWidget {
  final StoryBook book;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _StoryTile({
    required this.book,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = _genreColors[book.genre] ?? cs.primary;
    final dimmed = book.isArchived;
    final preview = book.lastSegmentPreview;
    final titleColor =
        dimmed ? cs.onSurface.withOpacity(0.5) : cs.onSurface;
    final subColor =
        dimmed ? cs.onSurfaceVariant.withOpacity(0.5) : cs.onSurfaceVariant;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      elevation: 0,
      color: dimmed
          ? cs.surfaceContainerLow.withOpacity(0.55)
          : cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: CircleAvatar(
          backgroundColor: accent.withOpacity(0.15),
          child: Icon(Icons.auto_stories, color: accent, size: 22),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                book.title.isEmpty ? '未命名故事' : book.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.w600, color: titleColor),
              ),
            ),
            if (dimmed) ...[
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: cs.onSurfaceVariant.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('已归档',
                    style: TextStyle(
                        fontSize: 10.5,
                        color: subColor,
                        fontWeight: FontWeight.w500)),
              ),
            ],
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (preview != null && preview.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(
                preview,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: subColor),
              ),
            ],
            const SizedBox(height: 5),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              runSpacing: 4,
              children: [
                _genreChip(book.genre.label, accent, cs),
                Text(_relativeTime(book.updatedAt),
                    style: TextStyle(fontSize: 11.5, color: subColor)),
                if (book.participantCharacterIds.isNotEmpty) ...[
                  Icon(Icons.group_outlined, size: 13, color: subColor),
                  Text('${book.participantCharacterIds.length}',
                      style: TextStyle(fontSize: 11.5, color: subColor)),
                ],
              ],
            ),
          ],
        ),
        trailing: Icon(Icons.chevron_right,
            color: cs.onSurfaceVariant, size: 20),
        onTap: onTap,
        onLongPress: onLongPress,
      ),
    );
  }
}
