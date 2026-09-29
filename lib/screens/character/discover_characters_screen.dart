import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../config/app_colors.dart';
import '../../data/character_templates.dart';
import '../../models/ai_character.dart';
import '../../models/chat_session.dart';
import '../../repositories/local_storage_repository.dart';
import '../../utils/character_color.dart';

/// 角色广场 — Shine 风格卡片流：顶部分类筛选 + 渐变封面卡片。
class DiscoverCharactersScreen extends StatefulWidget {
  const DiscoverCharactersScreen({super.key});

  @override
  State<DiscoverCharactersScreen> createState() =>
      _DiscoverCharactersScreenState();
}

class _DiscoverCharactersScreenState extends State<DiscoverCharactersScreen> {
  /// 当前筛选：null = 全部；'__advanced__' = 高阶；其余为 category 值
  String? _filter;

  static const String _advancedFilter = '__advanced__';

  List<String> get _categories {
    final seen = <String>{};
    final result = <String>[];
    for (final t in CharacterTemplates.templates) {
      if (!t.hasAltMode && seen.add(t.category)) result.add(t.category);
    }
    return result;
  }

  List<CharacterTemplate> get _filtered {
    final all = CharacterTemplates.templates;
    final List<CharacterTemplate> list;
    if (_filter == null) {
      // 全部：高阶（病娇）置顶，其余保持模板顺序
      list = [
        ...all.where((t) => t.hasAltMode),
        ...all.where((t) => !t.hasAltMode),
      ];
    } else if (_filter == _advancedFilter) {
      list = all.where((t) => t.hasAltMode).toList();
    } else {
      list = all.where((t) => t.category == _filter).toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? ImmersiveColors.background : null,
      appBar: AppBar(
        title: const Text('角色广场'),
        centerTitle: true,
        elevation: 0,
        backgroundColor: isDark ? ImmersiveColors.background : null,
      ),
      body: Column(
        children: [
          _buildFilterBar(colorScheme, isDark),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.66,
              ),
              itemCount: _filtered.length,
              itemBuilder: (context, index) =>
                  _CharacterCard(template: _filtered[index]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(ColorScheme colorScheme, bool isDark) {
    final filters = <String?>[null, _advancedFilter, ..._categories];
    final labels = <String>[
      '全部',
      '🔥 高阶',
      ..._categories,
    ];
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final selected = _filter == filters[index];
          final label = labels[index];
          return FilterChip(
            label: Text(label),
            selected: selected,
            showCheckmark: false,
            backgroundColor:
                isDark ? ImmersiveColors.card : colorScheme.surfaceContainerLow,
            selectedColor: isDark
                ? ImmersiveColors.accent.withOpacity(0.25)
                : colorScheme.primaryContainer,
            labelStyle: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected
                  ? (isDark ? ImmersiveColors.accent : colorScheme.primary)
                  : (isDark
                      ? ImmersiveColors.textSecondary
                      : colorScheme.onSurfaceVariant),
            ),
            side: BorderSide(
              color: selected
                  ? (isDark
                      ? ImmersiveColors.accent.withOpacity(0.5)
                      : colorScheme.primary.withOpacity(0.4))
                  : (isDark ? ImmersiveColors.border : colorScheme.outlineVariant),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            onSelected: (_) => setState(() => _filter = filters[index]),
          );
        },
      ),
    );
  }
}

// ────────────── 卡片 ──────────────

class _CharacterCard extends StatelessWidget {
  final CharacterTemplate template;

  const _CharacterCard({required this.template});

  /// 点赞数格式化：1.2w 风格
  static String _formatLikes(int likes) {
    if (likes >= 10000) {
      final w = likes / 10000;
      final text = w.toStringAsFixed(1);
      // 12.0w → 12w，避免多余的小数位
      return text.endsWith('.0') ? '${text.substring(0, text.length - 2)}w' : '${text}w';
    }
    return '$likes';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isYandere = template.hasAltMode;

    // 封面渐变：角色主题色（按名字哈希）压暗后混入深底，氛围感铺满
    final base = characterColor(name: template.name, cs: colorScheme);
    final hsv = HSVColor.fromColor(base);
    final coverTop = isDark
        ? Color.alphaBlend(
            hsv.withSaturation(0.5).withValue(0.55).toColor().withOpacity(0.85),
            ImmersiveColors.backgroundUp)
        : Color.alphaBlend(
            hsv.withSaturation(0.35).withValue(0.85).toColor().withOpacity(0.7),
            Colors.white);
    final coverBottom = isDark
        ? Color.alphaBlend(
            hsv.withSaturation(0.6).withValue(0.22).toColor().withOpacity(0.9),
            ImmersiveColors.background)
        : Color.alphaBlend(
            hsv.withSaturation(0.45).withValue(0.6).toColor().withOpacity(0.75),
            Colors.white);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _onTap(context),
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            color: isDark
                ? ImmersiveColors.card
                : colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isYandere
                  ? colorScheme.error.withOpacity(isDark ? 0.35 : 0.25)
                  : (isDark ? ImmersiveColors.border : colorScheme.outlineVariant),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── 封面区：渐变 + 大字首字 + 角标 ──
              Expanded(
                flex: 3,
                child: ClipRRect(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(15)),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [coverTop, coverBottom],
                      ),
                    ),
                    child: Stack(
                      children: [
                        Center(
                          child: Text(
                            template.name.isNotEmpty
                                ? template.name[0]
                                : '?',
                            style: TextStyle(
                              fontSize: 56,
                              fontFamily: 'serif',
                              fontWeight: FontWeight.w700,
                              color: Colors.white.withOpacity(isDark ? 0.9 : 0.85),
                              shadows: [
                                Shadow(
                                  color: Colors.black.withOpacity(0.25),
                                  blurRadius: 12,
                                ),
                              ],
                            ),
                          ),
                        ),
                        Positioned(
                          top: 8,
                          left: 8,
                          child: Row(
                            children: [
                              if (isYandere)
                                _badge(context, '🔥 高阶',
                                    colorScheme.error, isDark),
                              if (isYandere && template.isNew)
                                const SizedBox(width: 4),
                              if (template.isNew)
                                _badge(context, '新',
                                    isDark ? ImmersiveColors.accentSoft : colorScheme.primary, isDark),
                            ],
                          ),
                        ),
                        Positioned(
                          left: 10,
                          right: 10,
                          bottom: 8,
                          child: Text(
                            template.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              fontFamily: 'serif',
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.0,
                              color: Colors.white.withOpacity(0.95),
                              shadows: [
                                Shadow(
                                  color: Colors.black.withOpacity(0.35),
                                  blurRadius: 6,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // ── 信息区：卖点 + 点赞/性别 ──
              Expanded(
                flex: 2,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          template.tagline ?? template.personality,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            height: 1.35,
                            color: isDark
                                ? ImmersiveColors.textSecondary
                                : colorScheme.onSurface.withOpacity(0.7),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.favorite_rounded,
                            size: 13,
                            color: isDark
                                ? ImmersiveColors.accent
                                : colorScheme.primary,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            _formatLikes(template.displayLikes),
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark
                                  ? ImmersiveColors.textTertiary
                                  : colorScheme.onSurface.withOpacity(0.5),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            template.gender == '男' ? '♂' : '♀',
                            style: TextStyle(
                              fontSize: 12,
                              color: template.gender == '男'
                                  ? const Color(0xFF6C8CFF)
                                  : const Color(0xFFE88EA0),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _badge(
      BuildContext context, String text, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(isDark ? 0.35 : 0.25),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.6), width: 0.5),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  void _onTap(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _CharacterEditorScreen(template: template),
      ),
    );
  }
}

// ────────────── 完整编辑页 ──────────────

class _CharacterEditorScreen extends StatefulWidget {
  final CharacterTemplate template;
  const _CharacterEditorScreen({required this.template});

  @override
  State<_CharacterEditorScreen> createState() => _CharacterEditorScreenState();
}

class _CharacterEditorScreenState extends State<_CharacterEditorScreen> {
  late bool _useAltMode;
  bool _isLoading = false;

  final _nameController = TextEditingController();
  final _personalityController = TextEditingController();
  final _coreDesireController = TextEditingController();
  final _moralBoundaryController = TextEditingController();
  final _backgroundStoryController = TextEditingController();
  final _languageStyleController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _useAltMode = false;
    _syncControllers();
  }

  void _syncControllers() {
    final t = widget.template;
    _nameController.text = t.name;
    if (_useAltMode) {
      _personalityController.text = t.altPersonality ?? t.personality;
      _coreDesireController.text = t.altCoreDesire ?? t.coreDesire;
      _moralBoundaryController.text = t.altMoralBoundary ?? t.moralBoundary;
      _backgroundStoryController.text = t.altBackgroundStory ?? t.backgroundStory ?? '';
      _languageStyleController.text = t.altLanguageStyle ?? t.languageStyle ?? '';
    } else {
      _personalityController.text = t.personality;
      _coreDesireController.text = t.coreDesire;
      _moralBoundaryController.text = t.moralBoundary;
      _backgroundStoryController.text = t.backgroundStory ?? '';
      _languageStyleController.text = t.languageStyle ?? '';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _personalityController.dispose();
    _coreDesireController.dispose();
    _moralBoundaryController.dispose();
    _backgroundStoryController.dispose();
    _languageStyleController.dispose();
    super.dispose();
  }

  Future<void> _addCharacter() async {
    if (_nameController.text.trim().isEmpty) return;
    setState(() => _isLoading = true);

    try {
      final storage = RepositoryProvider.of<LocalStorageRepository>(context);
      String? userId;
      try {
        final authState = context.read<AuthBloc>().state;
        if (authState is AuthAuthenticated) userId = authState.user.id;
      } catch (_) {}

      final character = widget.template.toAICharacter(
        id: const Uuid().v4(),
        customName: _nameController.text.trim(),
        useAltMode: _useAltMode,
      );

      await storage.saveAICharacter(character);

      if (userId != null) {
        final now = DateTime.now();
        final session = ChatSession(
          id: const Uuid().v4(),
          userId: userId,
          aiCharacterId: character.id,
          aiCharacterName: character.name,
          aiCharacterAvatar: character.avatarUrl,
          lastMessage: character.openingLine ?? '我们已经是好友了，开始聊天吧！',
          lastMessageTime: now,
          createdAt: now,
          updatedAt: now,
        );
        await storage.saveChatSession(session);
      }

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已添加 ${character.name} 为好友')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('添加失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = widget.template;
    final canSwitch = t.hasAltMode;

    return Scaffold(
      appBar: AppBar(
        title: Text(_useAltMode ? '${t.name} · 暴戾' : t.name),
        centerTitle: true,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // ── 模式切换（仅病娇角色） ──
          if (canSwitch) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withOpacity(0.4),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() {
                        _useAltMode = false;
                        _syncControllers();
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: !_useAltMode ? cs.surface : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.favorite_outline,
                                size: 16,
                                color: !_useAltMode
                                    ? cs.error
                                    : cs.onSurface.withOpacity(0.4)),
                            const SizedBox(width: 6),
                            Text(
                              '普通',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: !_useAltMode
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: !_useAltMode
                                    ? cs.onSurface
                                    : cs.onSurface.withOpacity(0.4),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() {
                        _useAltMode = true;
                        _syncControllers();
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: _useAltMode ? cs.surface : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.whatshot,
                                size: 16,
                                color: _useAltMode
                                    ? cs.error
                                    : cs.onSurface.withOpacity(0.4)),
                            const SizedBox(width: 6),
                            Text(
                              '暴戾',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: _useAltMode
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: _useAltMode
                                    ? cs.onSurface
                                    : cs.onSurface.withOpacity(0.4),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],

          // ── 欲望度雷达（仅病娇角色） ──
          if (canSwitch) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withOpacity(0.25),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  _desireBar('占有欲', _useAltMode ? t.altPossessiveness : t.possessiveness, cs, Colors.red),
                  const SizedBox(height: 8),
                  _desireBar('监视欲', _useAltMode ? t.altSurveillance : t.surveillance, cs, Colors.orange),
                  const SizedBox(height: 8),
                  _desireBar('病态依恋', _useAltMode ? t.altDependency : t.dependency, cs, Colors.purple),
                  const SizedBox(height: 8),
                  _desireBar('身体渴望', _useAltMode ? t.altBodyDesire : t.bodyDesire, cs, Colors.pink),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],

          // ── 头像 ──
          Center(
            child: CircleAvatar(
              radius: 44,
              backgroundColor: _useAltMode
                  ? cs.error.withOpacity(0.15)
                  : cs.primaryContainer,
              child: Text(
                _nameController.text.isNotEmpty
                    ? _nameController.text.substring(0, 1)
                    : (t.name.isNotEmpty ? t.name.substring(0, 1) : '?'),
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: _useAltMode
                      ? cs.error
                      : cs.primary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // ── 名字 ──
          _buildField('名字', _nameController, hint: '输入角色名称'),
          const SizedBox(height: 16),

          // ── 性格 ──
          _buildField('性格', _personalityController, maxLines: 4),
          const SizedBox(height: 16),

          // ── 心愿 ──
          _buildField('心愿', _coreDesireController, maxLines: 3),
          const SizedBox(height: 16),

          // ── 原则 ──
          _buildField('原则', _moralBoundaryController, maxLines: 3),
          const SizedBox(height: 16),

          // ── 背景故事 ──
          _buildField('背景故事', _backgroundStoryController, maxLines: 4),
          const SizedBox(height: 16),

          // ── 语言风格 ──
          _buildField('语言风格', _languageStyleController, maxLines: 2),
          const SizedBox(height: 24),

          // ── 添加按钮 ──
          SizedBox(
            height: 50,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _addCharacter,
              style: ElevatedButton.styleFrom(
                backgroundColor: _useAltMode ? cs.error : cs.primary,
                foregroundColor: cs.onError,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('添加好友', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildField(String label, TextEditingController controller,
      {int maxLines = 1, String? hint}) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: cs.primary.withOpacity(0.8),
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          maxLines: maxLines,
          style: TextStyle(fontSize: 14, color: cs.onSurface),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: cs.onSurface.withOpacity(0.25)),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: cs.outline.withOpacity(0.15)),
            ),
            filled: true,
            fillColor: cs.surfaceContainerHighest.withOpacity(0.2),
            contentPadding: const EdgeInsets.all(12),
          ),
        ),
      ],
    );
  }

  Widget _desireBar(String label, int value, ColorScheme cs, Color color) {
    final pct = value.clamp(0, 100);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: cs.onSurface.withOpacity(0.7))),
            const Spacer(),
            Text('$pct%',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: color)),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: pct / 100,
            minHeight: 6,
            backgroundColor: color.withOpacity(0.12),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}
