import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../blocs/novel/novel_bloc.dart';
import '../../models/novel.dart';
import '../../repositories/local_storage_repository.dart';
import '../../services/ai_service.dart';
import 'novel_read_screen.dart';

/// 小说编辑器：左侧章节目录 + 右侧正文编辑
class NovelWriteScreen extends StatelessWidget {
  final Novel novel;
  const NovelWriteScreen({super.key, required this.novel});

  @override
  Widget build(BuildContext context) {
    final storage = RepositoryProvider.of<LocalStorageRepository>(context);
    final aiService = context.read<AIService>();
    return BlocProvider(
      create: (_) =>
          NovelBloc(storage, aiService)..add(NovelLoadChapters(novel.id)),
      child: _NovelWriteView(novel: novel),
    );
  }
}

class _NovelWriteView extends StatefulWidget {
  final Novel novel;
  const _NovelWriteView({required this.novel});

  @override
  State<_NovelWriteView> createState() => _NovelWriteViewState();
}

class _NovelWriteViewState extends State<_NovelWriteView> {
  NovelChapter? _selectedChapter;
  final TextEditingController _contentCtrl = TextEditingController();
  final TextEditingController _titleCtrl = TextEditingController();
  bool _isDirty = false;

  @override
  void dispose() {
    _contentCtrl.dispose();
    _titleCtrl.dispose();
    super.dispose();
  }

  void _selectChapter(NovelChapter chapter) {
    if (_isDirty && _selectedChapter != null) {
      _saveCurrentChapter();
    }
    setState(() {
      _selectedChapter = chapter;
      _contentCtrl.text = chapter.content;
      _titleCtrl.text = chapter.title;
      _isDirty = false;
    });
  }

  void _saveCurrentChapter() {
    final chapter = _selectedChapter;
    if (chapter == null) return;
    final updated = chapter.copyWith(
      title: _titleCtrl.text.trim().isEmpty ? chapter.title : _titleCtrl.text.trim(),
      content: _contentCtrl.text,
      updatedAt: DateTime.now(),
    );
    context.read<NovelBloc>().add(NovelUpdateChapter(updated));
    setState(() => _isDirty = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return BlocConsumer<NovelBloc, NovelState>(
      listener: (context, state) {
        if (state.error != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.error!),
                duration: const Duration(seconds: 2)),
          );
        }
        // AI 生成完成后自动填充编辑区
        if (!state.isGenerating && _selectedChapter != null) {
          final fresh = state.chapters
              .where((c) => c.id == _selectedChapter!.id)
              .firstOrNull;
          if (fresh != null &&
              fresh.content != _selectedChapter!.content &&
              !_isDirty) {
            setState(() {
              _selectedChapter = fresh;
              _contentCtrl.text = fresh.content;
            });
          }
        }
      },
      builder: (context, state) {
        final chapters = state.chapters;
        return Scaffold(
          backgroundColor:
              isDark ? const Color(0xFF0D0D0D) : const Color(0xFFF9F9F6),
          appBar: AppBar(
            title: Text(widget.novel.title,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            centerTitle: false,
            elevation: 0,
            backgroundColor: Colors.transparent,
            actions: [
              if (_selectedChapter != null) ...[
                // 阅读模式
                IconButton(
                  icon: const Icon(Icons.chrome_reader_mode_outlined),
                  tooltip: '阅读模式',
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => NovelReadScreen(
                        chapter: _selectedChapter!,
                        novelTitle: widget.novel.title,
                      ),
                    ),
                  ),
                ),
                // 保存
                IconButton(
                  icon: Icon(
                    Icons.save_outlined,
                    color: _isDirty ? cs.primary : cs.onSurface.withOpacity(0.4),
                  ),
                  tooltip: '保存',
                  onPressed: _isDirty ? _saveCurrentChapter : null,
                ),
              ],
            ],
          ),
          body: Row(
            children: [
              // ── 左侧章节目录 ──────────────────────────────────────
              SizedBox(
                width: 200,
                child: _ChapterList(
                  chapters: chapters,
                  selected: _selectedChapter,
                  isLoading: state.isLoadingChapters,
                  isGenerating: state.isGenerating,
                  generatingId: state.generatingChapterId,
                  novelId: widget.novel.id,
                  onSelect: _selectChapter,
                ),
              ),
              VerticalDivider(
                  width: 1, color: cs.outline.withOpacity(0.2)),
              // ── 右侧编辑区 ────────────────────────────────────────
              Expanded(
                child: _selectedChapter == null
                    ? _buildPlaceholder(context)
                    : _buildEditor(context, state),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPlaceholder(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.arrow_back_outlined,
              size: 40, color: cs.onSurface.withOpacity(0.25)),
          const SizedBox(height: 12),
          Text('选择或新建章节开始创作',
              style: TextStyle(
                  color: cs.onSurface.withOpacity(0.4), fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildEditor(BuildContext context, NovelState state) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        // 标题栏
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: TextField(
            controller: _titleCtrl,
            style: const TextStyle(
                fontSize: 18, fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              hintText: '章节标题',
              border: InputBorder.none,
              hintStyle: TextStyle(color: cs.onSurface.withOpacity(0.3)),
            ),
            onChanged: (_) => setState(() => _isDirty = true),
          ),
        ),
        Divider(height: 1, color: cs.outline.withOpacity(0.15)),
        // 正文编辑
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _contentCtrl,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              style: const TextStyle(fontSize: 15.5, height: 1.8),
              decoration: InputDecoration(
                hintText: '在这里写你的故事...',
                border: InputBorder.none,
                hintStyle: TextStyle(color: cs.onSurface.withOpacity(0.3)),
              ),
              onChanged: (_) => setState(() => _isDirty = true),
            ),
          ),
        ),
        // 底部工具栏
        _buildBottomBar(context, state),
      ],
    );
  }

  Widget _buildBottomBar(BuildContext context, NovelState state) {
    final cs = Theme.of(context).colorScheme;
    final chapter = _selectedChapter!;
    final wc = _contentCtrl.text.replaceAll(RegExp(r'\s+'), '').length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: cs.outline.withOpacity(0.15))),
      ),
      child: Row(
        children: [
          Text('$wc 字',
              style: TextStyle(
                  fontSize: 12, color: cs.onSurface.withOpacity(0.4))),
          const Spacer(),
          if (state.isGenerating && state.generatingChapterId == chapter.id)
            Row(
              children: [
                SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: cs.primary)),
                const SizedBox(width: 8),
                Text('AI 创作中…',
                    style: TextStyle(fontSize: 12, color: cs.primary)),
              ],
            )
          else
            _AiGenerateButton(
              chapter: chapter,
              novel: widget.novel,
              onGenerate: (instruction, targetWords) {
                context.read<NovelBloc>().add(NovelGenerateChapter(
                      chapterId: chapter.id,
                      chapterTitle: _titleCtrl.text.trim(),
                      instruction: instruction,
                      targetWords: targetWords,
                    ));
              },
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// 章节目录侧栏
// ─────────────────────────────────────────────────────────────────

class _ChapterList extends StatelessWidget {
  final List<NovelChapter> chapters;
  final NovelChapter? selected;
  final bool isLoading;
  final bool isGenerating;
  final String? generatingId;
  final String novelId;
  final ValueChanged<NovelChapter> onSelect;

  const _ChapterList({
    required this.chapters,
    required this.selected,
    required this.isLoading,
    required this.isGenerating,
    required this.generatingId,
    required this.novelId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 4),
          child: Row(
            children: [
              Text('章节',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface.withOpacity(0.5))),
              const Spacer(),
              InkWell(
                onTap: () => _addChapter(context),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(Icons.add, size: 18,
                      color: cs.onSurface.withOpacity(0.6)),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: isLoading
              ? const Center(
                  child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2)))
              : chapters.isEmpty
                  ? Center(
                      child: Text('暂无章节',
                          style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurface.withOpacity(0.35))))
                  : ListView.builder(
                      itemCount: chapters.length,
                      itemBuilder: (context, i) {
                        final c = chapters[i];
                        final isSelected = selected?.id == c.id;
                        final isGen = isGenerating && generatingId == c.id;
                        return InkWell(
                          onTap: () => onSelect(c),
                          onLongPress: () => _showChapterOptions(context, c),
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? cs.primaryContainer.withOpacity(0.4)
                                  : null,
                              border: Border(
                                left: BorderSide(
                                  color: isSelected
                                      ? cs.primary
                                      : Colors.transparent,
                                  width: 3,
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        c.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: isSelected
                                              ? FontWeight.w600
                                              : FontWeight.normal,
                                          color: isSelected
                                              ? cs.primary
                                              : cs.onSurface,
                                        ),
                                      ),
                                      Text(
                                        '${c.wordCount} 字',
                                        style: TextStyle(
                                            fontSize: 10,
                                            color: cs.onSurface
                                                .withOpacity(0.4)),
                                      ),
                                    ],
                                  ),
                                ),
                                if (isGen)
                                  SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 1.5,
                                        color: cs.primary),
                                  ),
                                if (c.isAiGenerated && !isGen)
                                  Icon(Icons.auto_awesome,
                                      size: 12,
                                      color: cs.tertiary.withOpacity(0.7)),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  void _addChapter(BuildContext context) {
    final ctrl = TextEditingController();
    final cs = Theme.of(context).colorScheme;
    final defaultTitle = '第${chapters.length + 1}章';
    ctrl.text = defaultTitle;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新增章节'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(
            labelText: '章节名',
            hintStyle: TextStyle(color: cs.onSurface.withOpacity(0.35)),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消')),
          FilledButton(
            onPressed: () {
              final title =
                  ctrl.text.trim().isEmpty ? defaultTitle : ctrl.text.trim();
              context
                  .read<NovelBloc>()
                  .add(NovelAddChapter(novelId: novelId, title: title));
              Navigator.pop(ctx);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _showChapterOptions(BuildContext context, NovelChapter chapter) {
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
                  color: Theme.of(ctx)
                      .colorScheme
                      .onSurfaceVariant
                      .withOpacity(0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.delete_outline,
                    color: Color(0xFFE53935)),
                title: const Text('删除此章',
                    style: TextStyle(color: Color(0xFFE53935))),
                onTap: () {
                  Navigator.pop(ctx);
                  context.read<NovelBloc>().add(NovelDeleteChapter(
                      chapterId: chapter.id, novelId: chapter.novelId));
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
// AI 生成按钮
// ─────────────────────────────────────────────────────────────────

class _AiGenerateButton extends StatelessWidget {
  final NovelChapter chapter;
  final Novel novel;
  final void Function(String? instruction, int targetWords) onGenerate;

  const _AiGenerateButton({
    required this.chapter,
    required this.novel,
    required this.onGenerate,
  });

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonal(
      style: FilledButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
      onPressed: () => _showGenerateDialog(context),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.auto_awesome, size: 14),
          SizedBox(width: 4),
          Text('AI 续写', style: TextStyle(fontSize: 13)),
        ],
      ),
    );
  }

  Future<void> _showGenerateDialog(BuildContext context) async {
    final instructionCtrl = TextEditingController();
    final wordsCtrl = TextEditingController(text: '2000');
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('AI 续写'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('AI 将根据小说设定和前文内容续写本章。',
                style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(ctx).colorScheme.onSurface.withOpacity(0.6))),
            const SizedBox(height: 12),
            TextField(
              controller: wordsCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '目标字数',
                hintText: '例如：2000',
                border: OutlineInputBorder(),
                suffixText: '字',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: instructionCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: '额外要求（选填）',
                hintText: '例如：加入一场激烈的对话，情绪要紧张...',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消')),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              final targetWords = int.tryParse(wordsCtrl.text.trim()) ?? 2000;
              final instruction = instructionCtrl.text.trim().isEmpty
                  ? null
                  : instructionCtrl.text.trim();
              onGenerate(instruction, targetWords.clamp(200, 20000));
            },
            child: const Text('开始生成'),
          ),
        ],
      ),
    );
  }
}