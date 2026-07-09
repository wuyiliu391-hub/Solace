import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';
import '../../models/ai_character.dart';
import '../../models/chat_session.dart';
import '../../services/game_service.dart';
import '../../repositories/local_storage_repository.dart';
import '../../utils/avatar_resolver.dart';
import '../../config/constants.dart';
import '../chat/chat_detail_screen.dart';

/// 娱乐互动页面 — 角色互动小游戏集合
class EntertainmentScreen extends StatefulWidget {
  final Function(String)? onNavigate;
  const EntertainmentScreen({super.key, this.onNavigate});

  @override
  State<EntertainmentScreen> createState() => _EntertainmentScreenState();
}

class _EntertainmentScreenState extends State<EntertainmentScreen>
    with SingleTickerProviderStateMixin {
  List<AICharacter> _characters = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCharacters();
  }

  Future<void> _loadCharacters() async {
    final storage = RepositoryProvider.of<LocalStorageRepository>(context);
    final characters = await storage.getAllAICharacters();
    if (mounted) {
      setState(() {
        _characters = characters.where((c) => !c.isHidden).toList();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('娱乐互动'),
        backgroundColor: cs.surface,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadCharacters,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // ── 角色选择横滑列表 ──
                  if (_characters.isNotEmpty) ...[
                    Text('选择角色开始互动', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 100,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: _characters.length,
                        itemBuilder: (context, index) {
                          final c = _characters[index];
                          return _CharacterPickerCard(character: c);
                        },
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                  // ── 互动游戏卡片网格 ──
                  Text('互动游戏', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.85,
                    children: [
                      _GameCard(
                        icon: Icons.emoji_emotions_rounded,
                        title: '真心话大冒险',
                        subtitle: '和角色互相提问',
                        gradientColors: isDark
                            ? [const Color(0xFFE91E63), const Color(0xFFAD1457)]
                            : [const Color(0xFFF06292), const Color(0xFFEC407A)],
                        onTap: () => _openTruthOrDare(context),
                      ),
                      _GameCard(
                        icon: Icons.psychology_alt_rounded,
                        title: '默契度测试',
                        subtitle: '你有多了解 TA？',
                        gradientColors: isDark
                            ? [const Color(0xFF7C4DFF), const Color(0xFF4527A0)]
                            : [const Color(0xFF9575CD), const Color(0xFF7E57C2)],
                        onTap: () => _openCompatibilityTest(context),
                      ),
                      _GameCard(
                        icon: Icons.favorite_rounded,
                        title: '心有灵犀',
                        subtitle: '猜 TA 会怎么回答',
                        gradientColors: isDark
                            ? [const Color(0xFFEF5350), const Color(0xFFC62828)]
                            : [const Color(0xFFEF9A9A), const Color(0xFFE57373)],
                        onTap: () => _openTelepathyGame(context),
                      ),
                      _GameCard(
                        icon: Icons.auto_awesome_rounded,
                        title: '角色印象',
                        subtitle: 'TA 对你的看法',
                        gradientColors: isDark
                            ? [const Color(0xFF26A69A), const Color(0xFF00695C)]
                            : [const Color(0xFF80CBC4), const Color(0xFF4DB6AC)],
                        onTap: () => _openImpressionCard(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  // ── 快捷娱乐入口 ──
                  Text('更多娱乐', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                  _QuickEntryTile(
                    icon: Icons.casino,
                    title: '幸运转盘',
                    subtitle: '转一转，看看今日运势',
                    color: const Color(0xFFFF7043),
                    onTap: () => widget.onNavigate?.call('/lucky_wheel'),
                  ),
                  _QuickEntryTile(
                    icon: Icons.auto_fix_high,
                    title: '塔罗牌',
                    subtitle: '每日占卜，预见未来',
                    color: const Color(0xFF7E57C2),
                    onTap: () => widget.onNavigate?.call('/tarot'),
                  ),
                  _QuickEntryTile(
                    icon: Icons.auto_stories,
                    title: '故事书',
                    subtitle: '与角色共创故事',
                    color: const Color(0xFF42A5F5),
                    onTap: () => widget.onNavigate?.call('/story'),
                  ),
                ],
              ),
            ),
    );
  }

  // ─── 带游戏模式的实时交互 ───
  // 不进自定义 UI，直接进 ChatDetailScreen，
  // 靠 AI 角色在对话中自然扮演游戏主持人。

  Future<void> _startGameWithCharacter(
    BuildContext context, {
    required String gameTitle,
    required String gamePrompt,
  }) async {
    if (_characters.isEmpty) return;

    final character = await showModalBottomSheet<AICharacter>(
      context: context,
      builder: (ctx) => _CharacterPickerSheet(characters: _characters),
    );
    if (character == null || !context.mounted) return;

    final storage = RepositoryProvider.of<LocalStorageRepository>(context);
    final userId = storage.getString(PrefKeys.currentUserId) ?? 'default';

    var sessions = await storage.getChatSessionsByCharacterId(character.id);
    var session = sessions.isNotEmpty ? sessions.first : null;

    if (session == null) {
      final uuid = const Uuid();
      session = ChatSession(
        id: uuid.v4(),
        userId: userId,
        aiCharacterId: character.id,
        aiCharacterName: character.userAlias ?? character.name,
        aiCharacterAvatar: character.avatarUrl,
        createdAt: DateTime.now(),
        sessionType: 'private',
        intimacyMode: 'quick',
      );
      await storage.saveChatSession(session);
    }

    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatDetailScreen(
          session: session!,
          initialMessage: gamePrompt,
        ),
      ),
    );
  }

  void _openTruthOrDare(BuildContext context) {
    _startGameWithCharacter(
      context,
      gameTitle: '真心话大冒险',
      gamePrompt: '我们来玩真心话大冒险吧！你选真心话还是大冒险？还是让我来决定？😊',
    );
  }

  void _openCompatibilityTest(BuildContext context) {
    _startGameWithCharacter(
      context,
      gameTitle: '默契度测试',
      gamePrompt: '来测测我们有多了解彼此吧！我先来问你几个问题，看看你会怎么回答～',
    );
  }

  void _openTelepathyGame(BuildContext context) {
    _startGameWithCharacter(
      context,
      gameTitle: '心有灵犀',
      gamePrompt: '我心里想了一个词，你来猜猜看是什么！你可以问我问题，我回答"是"或"不是"。开始吧！',
    );
  }

  void _openImpressionCard(BuildContext context) {
    _startGameWithCharacter(
      context,
      gameTitle: '角色印象',
      gamePrompt: '其实我一直想跟你说说，在我眼里你是个什么样的人……你准备好听了吗？',
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 角色选择卡片
// ═══════════════════════════════════════════════════════════════
class _CharacterPickerCard extends StatelessWidget {
  final AICharacter character;
  const _CharacterPickerCard({required this.character});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final displayName = character.userAlias ?? character.name;

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => _CharacterDetailSheet(character: character),
          ),
        );
      },
      child: Container(
        width: 72,
        margin: const EdgeInsets.only(right: 12),
        child: Column(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDark ? const Color(0xFF2C2C2C) : const Color(0xFFE8E4EC),
                border: Border.all(
                  color: character.isOnline ? Colors.green : cs.outline,
                  width: 2,
                ),
              ),
              child: ClipOval(
                child: AvatarResolver.imageWidget(character.avatarUrl,
                        fit: BoxFit.cover) ??
                    Center(
                      child: Text(
                        displayName.isNotEmpty ? displayName[0] : '?',
                        style: TextStyle(
                          fontSize: 24,
                          color: cs.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              displayName,
              style: TextStyle(
                fontSize: 11,
                color: cs.onSurface.withOpacity(0.8),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// 点击角色卡片后的详情面板 — 显示角色信息和互动入口
class _CharacterDetailSheet extends StatelessWidget {
  final AICharacter character;
  const _CharacterDetailSheet({required this.character});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final displayName = character.userAlias ?? character.name;

    return Scaffold(
      appBar: AppBar(title: Text(displayName), backgroundColor: cs.surface),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // 头像 + 基本信息
          Center(
            child: Column(
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isDark ? const Color(0xFF2C2C2C) : const Color(0xFFE8E4EC),
                  ),
                  child: ClipOval(
                    child: AvatarResolver.imageWidget(character.avatarUrl,
                            fit: BoxFit.cover) ??
                        Center(
                          child: Text(
                            displayName.isNotEmpty ? displayName[0] : '?',
                            style: TextStyle(fontSize: 36, color: cs.primary),
                          ),
                        ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(displayName,
                    style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                if (character.gender != null || character.age != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    [
                      if (character.gender != null) character.gender,
                      if (character.age != null) '${character.age}岁',
                    ].join(' · '),
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
          // 人设摘要
          _InfoCard(
            icon: Icons.person_outline,
            title: '人设',
            content: character.personality,
            cs: cs,
          ),
          if (character.catchphrases != null &&
              character.catchphrases!.isNotEmpty) ...[
            const SizedBox(height: 12),
            _InfoCard(
              icon: Icons.format_quote,
              title: '口头禅',
              content: character.catchphrases!,
              cs: cs,
            ),
          ],
          if (character.coreDesire.isNotEmpty) ...[
            const SizedBox(height: 12),
            _InfoCard(
              icon: Icons.favorite_outline,
              title: '核心渴望',
              content: character.coreDesire,
              cs: cs,
            ),
          ],
          const SizedBox(height: 24),
          // 互动入口
          FilledButton.icon(
            onPressed: () async {
              final storage = RepositoryProvider.of<LocalStorageRepository>(context);
              final userId = storage.getString(PrefKeys.currentUserId) ?? '';
              final sessions = await storage.getChatSessions(userId);
              ChatSession? session;
              try {
                session = sessions.firstWhere(
                  (s) => s.aiCharacterId == character.id,
                );
              } catch (_) {
                // 没有会话则创建
                final now = DateTime.now();
                session = ChatSession(
                  id: 'session_${DateTime.now().millisecondsSinceEpoch}',
                  userId: userId,
                  aiCharacterId: character.id,
                  aiCharacterName: displayName,
                  aiCharacterAvatar: character.avatarUrl,
                  createdAt: now,
                  updatedAt: now,
                );
                await storage.saveChatSession(session);
              }
              if (context.mounted) {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChatDetailScreen(session: session!),
                  ),
                );
              }
            },
            icon: const Icon(Icons.chat_bubble_outline),
            label: const Text('开始聊天'),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 游戏卡片组件
// ═══════════════════════════════════════════════════════════════
class _GameCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final List<Color> gradientColors;
  final VoidCallback onTap;

  const _GameCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.gradientColors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: gradientColors,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: gradientColors[0].withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: Colors.white, size: 28),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      )),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.85),
                        fontSize: 12,
                      )),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 快捷入口
// ═══════════════════════════════════════════════════════════════
class _QuickEntryTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _QuickEntryTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color, size: 24),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
      trailing: Icon(Icons.chevron_right, color: cs.onSurfaceVariant, size: 20),
      onTap: onTap,
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 信息卡片
// ═══════════════════════════════════════════════════════════════
class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String content;
  final ColorScheme cs;

  const _InfoCard({
    required this.icon,
    required this.title,
    required this.content,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: cs.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurfaceVariant,
                    )),
                const SizedBox(height: 4),
                Text(content, style: TextStyle(fontSize: 14, color: cs.onSurface)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 真心话大冒险

// ═══════════════════════════════════════════════════════════════
// 角色选择底部弹窗（游戏专用）
// ═══════════════════════════════════════════════════════════════
class _CharacterPickerSheet extends StatelessWidget {
  final List<AICharacter> characters;
  const _CharacterPickerSheet({required this.characters});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.only(top: 12, bottom: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: cs.onSurfaceVariant.withOpacity(0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Text('选择一个角色', style: TextStyle(
            fontSize: 16, fontWeight: FontWeight.w600, color: cs.onSurface,
          )),
          const SizedBox(height: 12),
          ...characters.map((c) {
            final name = c.userAlias ?? c.name;
            return ListTile(
              leading: CircleAvatar(
                backgroundImage: AvatarResolver.imageProvider(c.avatarUrl),
                child: AvatarResolver.imageProvider(c.avatarUrl) == null
                    ? Text(name.isNotEmpty ? name[0] : '?')
                    : null,
              ),
              title: Text(name),
              subtitle: Text(c.personality.length > 30
                  ? '${c.personality.substring(0, 30)}...'
                  : c.personality),
              onTap: () => Navigator.pop(context, c),
            );
          }),
        ],
      ),
    );
  }
}
