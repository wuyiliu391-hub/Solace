import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../blocs/story/story_play_bloc.dart';
import '../../models/story_book.dart';
import '../../repositories/local_storage_repository.dart';
import '../../services/ai_service.dart';
import '../../utils/avatar_resolver.dart';
import '../../widgets/typing_indicator.dart';
import 'story_saves_screen.dart';
import 'widgets/story_scene_panel.dart';

/// 题材配色（与书架保持一致）
const Map<StoryGenre, Color> _genreColors = {
  StoryGenre.romance: Color(0xFFE57399),
  StoryGenre.yandere: Color(0xFFEF5350),
  StoryGenre.darkArt: Color(0xFF7E57C2),
  StoryGenre.free: Color(0xFF26A69A),
};

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
    return BlocConsumer<StoryPlayBloc, StoryPlayState>(
      listenWhen: (p, c) =>
          p.segments.length != c.segments.length ||
          p.streamingText != c.streamingText,
      listener: (context, state) => _scrollToBottom(),
      builder: (context, state) {
        final book = state.book;
        return Scaffold(
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
                        _buildBookHeader(context, state),
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
      SnackBar(
          content: Text('已切换为「${next.label}」视角'),
          duration: const Duration(seconds: 1)),
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
    final book = state.book;
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

    // 故事书封面（AI）的头像：优先用参与角色第一个，其次用书本封面
    final aiAvatarUrl = book?.coverUrl;
    final aiName = book?.title ?? '叙事者';

    // 读取用户自定义的小说对白颜色（null 时回退默认蓝色）
    final storage = RepositoryProvider.of<LocalStorageRepository>(context);
    final customColor = storage.getNovelDialogueColor();

    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
      cacheExtent: 600,
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (showStreaming && index == state.segments.length) {
          return _StoryStreamingBubble(
            text: state.streamingText,
            avatarUrl: aiAvatarUrl,
            name: aiName,
            customDialogueColor: customColor,
          );
        }
        final seg = state.segments[index];
        return _StoryBubble(
          text: seg.content,
          isUser: seg.isUser,
          aiAvatarUrl: aiAvatarUrl,
          aiName: aiName,
          customDialogueColor: customColor,
        );
      },
    );
  }

  /// 书本上下文信息条：题材 / 叙事视角 / 登场人数
  Widget _buildBookHeader(BuildContext context, StoryPlayState state) {
    final book = state.book;
    if (book == null) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final accent = _genreColors[book.genre] ?? cs.primary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest.withOpacity(0.5),
        border: Border(
          bottom: BorderSide(
              color: cs.outline.withOpacity(0.12), width: 0.5),
        ),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 6,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: accent.withOpacity(0.14),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text(book.genre.label,
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: accent)),
          ),
          _headerItem(Icons.visibility_outlined, book.narratorRole.label, cs),
          if (book.participantCharacterIds.isNotEmpty)
            _headerItem(Icons.group_outlined,
                '${book.participantCharacterIds.length} 位角色', cs),
        ],
      ),
    );
  }

  Widget _headerItem(IconData icon, String text, ColorScheme cs) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: cs.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(text,
            style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant)),
      ],
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
      child: Container(
        decoration: BoxDecoration(
          color: cs.surface,
          border: Border(
            top: BorderSide(color: cs.outline.withOpacity(0.15), width: 0.5),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
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
                  hintStyle: TextStyle(color: cs.onSurfaceVariant),
                  filled: true,
                  fillColor: cs.surfaceContainerHighest.withOpacity(0.5),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                textInputAction: TextInputAction.send,
                onSubmitted: (v) => _advance(context, v),
              ),
            ),
            const SizedBox(width: 8),
            state.isGenerating
                ? const Padding(
                    padding: EdgeInsets.all(10),
                    child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : IconButton.filled(
                    icon: const Icon(Icons.arrow_upward, size: 20),
                    style: IconButton.styleFrom(
                      backgroundColor: cs.primary,
                      foregroundColor: cs.onPrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    onPressed: () => _advance(context, _inputCtrl.text),
                  ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 故事段落气泡 — 与聊天页 _MessageBubble 一致的视觉规范
// ─────────────────────────────────────────────────────────────────────────────

/// 匹配对白：ASCII 直双引号 "…"、中文弯引号 "…"、直角引号 「」/『』
final RegExp _dialogueRe = RegExp(
  '\u0022[^\u0022]*\u0022|'           // "…"（ASCII 直双引号）
  '\u201C[^\u201C\u201D]*\u201D|'    // "…"（U+201C → U+201D 标准中文配对标点）
  '\u201D[^\u201D]*\u201D|'           // "…"（U+201D 自身配自身）
  '\u300C[^\u300D]*\u300D|'          // 「…」
  '\u300E[^\u300F]*\u300F'           // 『…』
);

/// 引号对内字符超过此长度时，视为旁白被模型误包，跳过对白着色（与聊天页保持一致）。
const int _maxDialogueLen = 40;

/// 把文本按对白/旁白拆成富文本片段（与聊天页逻辑相同）
List<InlineSpan>? _buildDialogueSpans(
    String text, TextStyle baseStyle, Color dialogueColor) {
  final matches = _dialogueRe.allMatches(text).toList();
  if (matches.isEmpty) return null;
  final spans = <InlineSpan>[];
  var cursor = 0;
  for (final m in matches) {
    if (m.start > cursor) {
      spans.add(TextSpan(text: text.substring(cursor, m.start), style: baseStyle));
    }
    final inner = text.substring(m.start, m.end);
    final isLikelyNarration = inner.length > _maxDialogueLen;
    spans.add(TextSpan(
      text: inner,
      style: isLikelyNarration
          ? baseStyle
          : baseStyle.copyWith(color: dialogueColor, fontWeight: FontWeight.w600),
    ));
    cursor = m.end;
  }
  if (cursor < text.length) {
    spans.add(TextSpan(text: text.substring(cursor), style: baseStyle));
  }
  return spans;
}

// 与聊天页保持一致的颜色常量
const Color _douyinBlue = Color(0xFF2B7BF5);
const Color _douyinBlueDark = Color(0xFF4A90F7);
const Color _bubbleLight = Color(0xFFFFFFFF);
const Color _bubbleDark = Color(0xFF2C2C2C);
const Color _textOnBlue = Colors.white;
const Color _textOnWhite = Color(0xFF1A1A1A);
const Color _textOnDark = Color(0xFFE8EAED);
const double _avatarSize = 32.0;
const double _bubbleRadius = 12.0;
const double _hPad = 16.0;

class _StoryBubble extends StatelessWidget {
  final String text;
  final bool isUser;
  final String? aiAvatarUrl;
  final String aiName;
  final Color? customDialogueColor;

  const _StoryBubble({
    required this.text,
    required this.isUser,
    this.aiAvatarUrl,
    this.aiName = '叙事者',
    this.customDialogueColor,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = brightness == Brightness.dark;

    final userBubbleColor = isDark ? _douyinBlueDark : _douyinBlue;
    final aiBubbleColor = isDark ? _bubbleDark : _bubbleLight;
    final userTextColor = _textOnBlue;
    final aiTextColor = isDark ? _textOnDark : _textOnWhite;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _hPad, vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isUser) ...[
            _buildAvatar(isDark, colorScheme),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isUser ? userBubbleColor : aiBubbleColor,
                borderRadius: BorderRadius.circular(_bubbleRadius),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: _buildText(
                  brightness, isUser ? userTextColor : aiTextColor),
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 8),
            _buildUserAvatar(colorScheme),
          ],
        ],
      ),
    );
  }

  Widget _buildText(Brightness brightness, Color textColor) {
    final baseStyle = TextStyle(
      fontSize: 15,
      height: 1.6,
      color: textColor,
    );
    // AI 叙事文字使用对白高亮（故事书天然是小说模式）
    if (!isUser) {
      final dialogueColor = customDialogueColor ?? (brightness == Brightness.dark
          ? _douyinBlueDark
          : _douyinBlue);
      final spans = _buildDialogueSpans(text, baseStyle, dialogueColor);
      if (spans != null) {
        return SelectableText.rich(TextSpan(children: spans));
      }
    }
    return SelectableText(text, style: baseStyle);
  }

  Widget _buildAvatar(bool isDark, ColorScheme cs) {
    final imgProvider = AvatarResolver.imageProvider(aiAvatarUrl);
    return CircleAvatar(
      radius: _avatarSize / 2,
      backgroundColor: cs.primary.withOpacity(0.12),
      backgroundImage: imgProvider,
      child: imgProvider == null
          ? Icon(Icons.auto_stories, size: 16, color: cs.primary)
          : null,
    );
  }

  Widget _buildUserAvatar(ColorScheme cs) {
    return CircleAvatar(
      radius: _avatarSize / 2,
      backgroundColor: cs.primaryContainer,
      child: Icon(Icons.person_outline, size: 16, color: cs.primary),
    );
  }
}

/// 流式生成中的叙事气泡（打字效果）
class _StoryStreamingBubble extends StatelessWidget {
  final String text;
  final String? avatarUrl;
  final String name;
  final Color? customDialogueColor;

  const _StoryStreamingBubble({
    required this.text,
    this.avatarUrl,
    this.name = '叙事者',
    this.customDialogueColor,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final imgProvider = AvatarResolver.imageProvider(avatarUrl);

    return Padding(
      padding: const EdgeInsets.fromLTRB(_hPad, 4, _hPad, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: _avatarSize / 2,
            backgroundColor: colorScheme.primary.withOpacity(0.12),
            backgroundImage: imgProvider,
            child: imgProvider == null
                ? Icon(Icons.auto_stories,
                    size: 16, color: colorScheme.primary)
                : null,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: brightness == Brightness.dark ? _bubbleDark : _bubbleLight,
                borderRadius: BorderRadius.circular(_bubbleRadius),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: text.isEmpty
                  ? TypingIndicator()
                  : Builder(builder: (ctx) {
                      final isDark = brightness == Brightness.dark;
                      final textColor = isDark ? _textOnDark : _textOnWhite;
                      final dialogueColor =
                          customDialogueColor ?? (isDark ? _douyinBlueDark : _douyinBlue);
                      final baseStyle = TextStyle(
                        fontSize: 15,
                        height: 1.6,
                        color: textColor.withOpacity(0.75),
                      );
                      final spans =
                          _buildDialogueSpans(text, baseStyle, dialogueColor);
                      if (spans != null) {
                        return Text.rich(TextSpan(children: spans));
                      }
                      return Text(text, style: baseStyle);
                    }),
            ),
          ),
        ],
      ),
    );
  }
}