import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../blocs/story/story_play_bloc.dart';
import '../../models/story_book.dart';
import '../../repositories/local_storage_repository.dart';
import '../../services/ai_service.dart';
import 'story_saves_screen.dart';
import 'widgets/story_scene_panel.dart';

/// 故事书 · 剧情阅读/续写
class StoryReadScreen extends StatelessWidget {
  final String bookId;
  const StoryReadScreen({super.key, required this.bookId});

  @override
  Widget build(BuildContext context) {
    final storage = RepositoryProvider.of<LocalStorageRepository>(context);
    return BlocProvider(
      create: (_) => StoryPlayBloc(storage, AIService(storage))
        ..add(StoryPlayOpen(bookId)),
      child: const _StoryReadView(),
    );
  }
}

class _StoryReadView extends StatefulWidget {
  const _StoryReadView();

  @override
  State<_StoryReadView> createState() => _StoryReadViewState();
}

class _StoryReadViewState extends State<_StoryReadView> {
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _panelExpanded = false;

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _advance(BuildContext context, String text) {
    if (text.trim().isEmpty) return;
    context.read<StoryPlayBloc>().add(StoryPlayAdvance(text.trim()));
    _inputCtrl.clear();
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return BlocConsumer<StoryPlayBloc, StoryPlayState>(
      listenWhen: (p, c) =>
          p.segments.length != c.segments.length ||
          p.streamingText != c.streamingText,
      listener: (context, state) => _scrollToBottom(),
      builder: (context, state) {
        final book = state.book;
        return Scaffold(
          backgroundColor:
              isDark ? const Color(0xFF0B0B0B) : const Color(0xFFF7F3EC),
          appBar: AppBar(
            title: Text(book?.title ?? '故事',
                maxLines: 1, overflow: TextOverflow.ellipsis),
            elevation: 0,
            backgroundColor: Colors.transparent,
            actions: [
              if (book != null)
                IconButton(
                  tooltip: '切换视角（当前：${book.narratorRole.label}）',
                  icon: const Icon(Icons.switch_account_outlined),
                  onPressed: () => _switchNarrator(context, book),
                ),
              IconButton(
                tooltip: '存档',
                icon: const Icon(Icons.bookmarks_outlined),
                onPressed: book == null ? null : () => _openSaves(context, book),
              ),
            ],
          ),
          body: state.isLoading
              ? const Center(child: CircularProgressIndicator())
              : Stack(
                  children: [
                    Column(
                      children: [
                        Expanded(child: _buildStoryList(context, state)),
                        _buildBranches(context, state),
                        _buildInputBar(context, state),
                      ],
                    ),
                    Positioned(
                      right: 12,
                      top: 12,
                      child: StoryScenePanel(
                        scene: state.scene,
                        expanded: _panelExpanded,
                        onToggle: () =>
                            setState(() => _panelExpanded = !_panelExpanded),
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }

  Future<void> _switchNarrator(BuildContext context, StoryBook book) async {
    final next = book.narratorRole == NarratorRole.protagonist
        ? NarratorRole.supporting
        : NarratorRole.protagonist;
    context.read<StoryPlayBloc>().add(StoryPlaySwitchNarrator(next));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已切换为「${next.label}」视角'), duration: const Duration(seconds: 1)),
    );
  }

  Future<void> _openSaves(BuildContext context, StoryBook book) async {
    final bloc = context.read<StoryPlayBloc>();
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BlocProvider.value(
          value: bloc,
          child: StorySavesScreen(book: book),
        ),
      ),
    );
  }

  Widget _buildStoryList(BuildContext context, StoryPlayState state) {
    final cs = Theme.of(context).colorScheme;
    final showStreaming = state.isGenerating && state.streamingText.isNotEmpty;
    final itemCount = state.segments.length + (showStreaming ? 1 : 0);

    if (itemCount == 0) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text('输入第一句，开启故事……',
              style: TextStyle(color: cs.onSurface.withOpacity(0.4))),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      // 长文本优化：懒加载 + 固定不缓存过多
      cacheExtent: 600,
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (showStreaming && index == state.segments.length) {
          return _StorySegmentView(
            text: state.streamingText,
            isUser: false,
            streaming: true,
          );
        }
        final seg = state.segments[index];
        return _StorySegmentView(
          text: seg.content,
          isUser: seg.isUser,
          streaming: false,
        );
      },
    );
  }

  Widget _buildBranches(BuildContext context, StoryPlayState state) {
    if (state.isGenerating || state.currentBranches.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: state.currentBranches.map((b) {
          return ActionChip(
            label: Text(b, style: const TextStyle(fontSize: 13)),
            onPressed: () => _advance(context, b),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildInputBar(BuildContext context, StoryPlayState state) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _inputCtrl,
                minLines: 1,
                maxLines: 4,
                enabled: !state.isGenerating,
                decoration: InputDecoration(
                  hintText: state.isGenerating ? '续写中…' : '写下你的行动或对白…',
                  filled: true,
                  fillColor: cs.surfaceContainerHighest.withOpacity(0.4),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                onSubmitted: (v) => _advance(context, v),
              ),
            ),
            const SizedBox(width: 8),
            state.isGenerating
                ? const Padding(
                    padding: EdgeInsets.all(10),
                    child: SizedBox(
                        width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : IconButton.filled(
                    icon: const Icon(Icons.send),
                    onPressed: () => _advance(context, _inputCtrl.text),
                  ),
          ],
        ),
      ),
    );
  }
}

/// 单条剧情段落渲染（长文本优化：SelectableText + 分角色样式）
class _StorySegmentView extends StatelessWidget {
  final String text;
  final bool isUser;
  final bool streaming;

  const _StorySegmentView({
    required this.text,
    required this.isUser,
    required this.streaming,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (isUser) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: cs.primaryContainer.withOpacity(0.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.person_outline, size: 16, color: cs.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text,
                  style: TextStyle(
                      fontSize: 14.5,
                      height: 1.5,
                      color: cs.onSurface.withOpacity(0.85))),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: SelectableText(
        text,
        style: TextStyle(
          fontSize: 16,
          height: 1.85,
          color: cs.onSurface.withOpacity(streaming ? 0.6 : 0.92),
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}
