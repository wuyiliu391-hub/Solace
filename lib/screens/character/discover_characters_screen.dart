import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../data/character_templates.dart';
import '../../models/ai_character.dart';
import '../../models/chat_session.dart';
import '../../repositories/local_storage_repository.dart';

/// 发现角色 — 浏览并添加预设角色
class DiscoverCharactersScreen extends StatelessWidget {
  const DiscoverCharactersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final templates = CharacterTemplates.templates;

    // 病娇（高阶）vs 日常
    final yandereTemplates = templates.where((t) => t.hasAltMode).toList();
    final normalTemplates = templates.where((t) => !t.hasAltMode).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('发现角色'),
        centerTitle: true,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (yandereTemplates.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Text(
                '🔥 高阶角色',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.error,
                ),
              ),
            ),
            ...yandereTemplates.map((t) => _CharacterCard(template: t)),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Text(
                '陪伴角色',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: colorScheme.onSurface.withOpacity(0.45),
                ),
              ),
            ),
          ],
          ...normalTemplates.map((t) => _CharacterCard(template: t)),
        ],
      ),
    );
  }
}

// ────────────── 卡片 ──────────────

class _CharacterCard extends StatelessWidget {
  final CharacterTemplate template;

  const _CharacterCard({required this.template});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isYandere = template.hasAltMode;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: isYandere
                ? colorScheme.error.withOpacity(0.2)
                : colorScheme.outline.withOpacity(0.08),
          ),
        ),
        color: isYandere
            ? colorScheme.errorContainer.withOpacity(0.15)
            : colorScheme.surfaceContainerLow,
        child: InkWell(
          onTap: () => _onTap(context),
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: isYandere
                      ? colorScheme.error.withOpacity(0.2)
                      : colorScheme.primaryContainer,
                  child: Text(
                    template.name.isNotEmpty
                        ? template.name.substring(0, 1)
                        : '?',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: isYandere ? colorScheme.error : colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        template.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        template.gender == '男' ? '♂ 男性' : '♀ 女性',
                        style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.onSurface.withOpacity(0.4),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: colorScheme.onSurface.withOpacity(0.2),
                ),
              ],
            ),
          ),
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
