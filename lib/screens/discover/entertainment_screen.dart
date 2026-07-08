import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../models/ai_character.dart';
import '../../models/chat_session.dart';
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

  // ─── 打开真心话大冒险 ───
  void _openTruthOrDare(BuildContext context) {
    if (_characters.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TruthOrDareGame(characters: _characters),
        fullscreenDialog: true,
      ),
    );
  }

  // ─── 打开默契度测试 ───
  void _openCompatibilityTest(BuildContext context) {
    if (_characters.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CompatibilityTestGame(characters: _characters),
        fullscreenDialog: true,
      ),
    );
  }

  // ─── 打开心有灵犀 ───
  void _openTelepathyGame(BuildContext context) {
    if (_characters.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TelepathyGame(characters: _characters),
        fullscreenDialog: true,
      ),
    );
  }

  // ─── 打开角色印象 ───
  void _openImpressionCard(BuildContext context) {
    if (_characters.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ImpressionCardGame(characters: _characters),
        fullscreenDialog: true,
      ),
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
class TruthOrDareGame extends StatefulWidget {
  final List<AICharacter> characters;
  const TruthOrDareGame({super.key, required this.characters});

  @override
  State<TruthOrDareGame> createState() => _TruthOrDareGameState();
}

class _TruthOrDareGameState extends State<TruthOrDareGame> {
  AICharacter? _selectedCharacter;
  bool _isTruth = true;
  String? _currentPrompt;
  final _random = Random();

  static const _truths = [
    '你觉得我最大的优点是什么？',
    '你最害怕失去什么？',
    '你有没有对我撒过谎？',
    '你最想和我一起做什么事？',
    '你觉得我们之间最大的默契是什么？',
    '你心里最深的秘密是什么？',
    '你最珍惜的回忆是哪个？',
    '如果世界末日只能带一个人，你选谁？',
    '你觉得我什么地方最让你心动？',
    '你有没有偷偷吃醋过？',
    '你最想对我说但一直没说出口的话？',
    '你觉得我们第一次见面时你对我的印象？',
  ];

  static const _dares = [
    '用三个词形容你现在的心情',
    '模仿我平时说话的语气说一句话',
    '唱一句你最喜欢的歌',
    '做一个搞怪表情',
    '说出你最近做的一件傻事',
    '用撒娇的语气说"我想你了"',
    '假装生气三秒钟',
    '说出你最糗的一个经历',
    '模仿一只猫叫',
    '说出你藏在心里的一个小愿望',
    '用播音腔念一段话',
    '做一个你觉得最帅/最美的姿势',
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('真心话大冒险'),
        backgroundColor: cs.surface,
      ),
      body: Column(
        children: [
          // 角色选择
          if (_selectedCharacter == null)
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: widget.characters.length,
                itemBuilder: (context, index) {
                  final c = widget.characters[index];
                  final name = c.userAlias ?? c.name;
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundImage: AvatarResolver.imageProvider(c.avatarUrl),
                      child: AvatarResolver.imageProvider(c.avatarUrl) == null
                          ? Text(name.isNotEmpty ? name[0] : '?')
                          : null,
                    ),
                    title: Text(name),
                    subtitle: Text(c.gender ?? '未知',
                        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                    onTap: () => setState(() => _selectedCharacter = c),
                  );
                },
              ),
            )
          else ...[
            // 已选角色信息
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                border: Border(
                    bottom: BorderSide(color: cs.outline.withOpacity(0.2))),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundImage:
                        AvatarResolver.imageProvider(_selectedCharacter!.avatarUrl),
                    child: AvatarResolver.imageProvider(
                                _selectedCharacter!.avatarUrl) ==
                            null
                        ? Text((_selectedCharacter!.userAlias ??
                                _selectedCharacter!.name)[0])
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _selectedCharacter!.userAlias ?? _selectedCharacter!.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      _selectedCharacter = null;
                      _currentPrompt = null;
                    }),
                    child: const Text('换角色'),
                  ),
                ],
              ),
            ),
            // 模式切换
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() {
                        _isTruth = true;
                        _currentPrompt = null;
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: _isTruth
                              ? const Color(0xFFEC407A)
                              : (isDark ? cs.surfaceContainerHigh : cs.surfaceContainerLow),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Text('真心话',
                              style: TextStyle(
                                color: _isTruth ? Colors.white : cs.onSurface,
                                fontWeight: FontWeight.w600,
                              )),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() {
                        _isTruth = false;
                        _currentPrompt = null;
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: !_isTruth
                              ? const Color(0xFF7C4DFF)
                              : (isDark ? cs.surfaceContainerHigh : cs.surfaceContainerLow),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Text('大冒险',
                              style: TextStyle(
                                color: !_isTruth ? Colors.white : cs.onSurface,
                                fontWeight: FontWeight.w600,
                              )),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // 抽题区域
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: _currentPrompt == null
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _isTruth ? Icons.emoji_emotions_rounded : Icons.local_fire_department_rounded,
                              size: 64,
                              color: _isTruth ? const Color(0xFFEC407A) : const Color(0xFF7C4DFF),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _isTruth ? '准备好了吗？' : '胆子够大吗？',
                              style: TextStyle(fontSize: 18, color: cs.onSurfaceVariant),
                            ),
                            const SizedBox(height: 24),
                            FilledButton.icon(
                              onPressed: _draw,
                              icon: const Icon(Icons.casino),
                              label: Text(_isTruth ? '抽真心话' : '抽大冒险'),
                            ),
                          ],
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(28),
                              decoration: BoxDecoration(
                                color: cs.surfaceContainerLow,
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(
                                  color: (_isTruth
                                          ? const Color(0xFFEC407A)
                                          : const Color(0xFF7C4DFF))
                                      .withOpacity(0.3),
                                  width: 2,
                                ),
                              ),
                              child: Column(
                                children: [
                                  Icon(
                                    _isTruth ? Icons.emoji_emotions_rounded : Icons.local_fire_department_rounded,
                                    size: 40,
                                    color: _isTruth ? const Color(0xFFEC407A) : const Color(0xFF7C4DFF),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    _currentPrompt!,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w600,
                                      color: cs.onSurface,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: _draw,
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('换一题'),
                                ),
                                const SizedBox(width: 12),
                                FilledButton.icon(
                                  onPressed: () => setState(() => _currentPrompt = null),
                                  icon: const Icon(Icons.check),
                                  label: const Text('完成'),
                                ),
                              ],
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _draw() {
    final pool = _isTruth ? _truths : _dares;
    setState(() {
      _currentPrompt = pool[_random.nextInt(pool.length)];
    });
  }
}

// ═══════════════════════════════════════════════════════════════
// 默契度测试
// ═══════════════════════════════════════════════════════════════
class CompatibilityTestGame extends StatefulWidget {
  final List<AICharacter> characters;
  const CompatibilityTestGame({super.key, required this.characters});

  @override
  State<CompatibilityTestGame> createState() => _CompatibilityTestGameState();
}

class _CompatibilityTestGameState extends State<CompatibilityTestGame> {
  AICharacter? _selectedCharacter;
  int _currentQuestion = 0;
  int _score = 0;
  bool _finished = false;

  static const _questions = [
    {'q': 'TA 的性别是？', 'hint': '看看角色信息'},
    {'q': 'TA 的核心渴望是什么？', 'hint': '每个人内心深处最想要的东西'},
    {'q': 'TA 有什么口头禅？', 'hint': '经常说的话'},
    {'q': 'TA 的人格特质是什么？', 'hint': 'TA 是怎样的人'},
    {'q': 'TA 的道德底线包含什么？', 'hint': 'TA 绝对不会做的事'},
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('默契度测试'), backgroundColor: cs.surface),
      body: _selectedCharacter == null
          ? _buildCharacterPicker()
          : _finished
              ? _buildResult(cs)
              : _buildQuestion(cs),
    );
  }

  Widget _buildCharacterPicker() {
    final cs = Theme.of(context).colorScheme;
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: widget.characters.length,
      itemBuilder: (context, index) {
        final c = widget.characters[index];
        final name = c.userAlias ?? c.name;
        return ListTile(
          leading: CircleAvatar(
            backgroundImage: AvatarResolver.imageProvider(c.avatarUrl),
            child: AvatarResolver.imageProvider(c.avatarUrl) == null
                ? Text(name.isNotEmpty ? name[0] : '?')
                : null,
          ),
          title: Text(name),
          subtitle: Text('来测测你有多了解 TA',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          onTap: () => setState(() => _selectedCharacter = c),
        );
      },
    );
  }

  Widget _buildQuestion(ColorScheme cs) {
    final q = _questions[_currentQuestion];
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 进度条
          LinearProgressIndicator(
            value: (_currentQuestion + 1) / _questions.length,
            backgroundColor: cs.surfaceContainerHigh,
          ),
          const SizedBox(height: 8),
          Text('第 ${_currentQuestion + 1} / ${_questions.length} 题',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          const Spacer(),
          Text(q['q']!,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: cs.onSurface)),
          const SizedBox(height: 8),
          Text(q['hint']!,
              style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant)),
          const SizedBox(height: 24),
          // 答案输入区 — 简化为自评
          Text('回忆一下，你觉得自己答对了吗？',
              style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant)),
          const Spacer(),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _next(false),
                  icon: const Icon(Icons.close),
                  label: const Text('不太确定'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _next(true),
                  icon: const Icon(Icons.check),
                  label: const Text('我知道！'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  void _next(bool correct) {
    if (correct) _score++;
    if (_currentQuestion < _questions.length - 1) {
      setState(() => _currentQuestion++);
    } else {
      setState(() => _finished = true);
    }
  }

  Widget _buildResult(ColorScheme cs) {
    final total = _questions.length;
    final percent = (_score / total * 100).round();
    String level;
    String comment;
    IconData emoji;
    Color color;

    if (percent >= 80) {
      level = '心有灵犀';
      comment = '你对 TA 的了解已经到了灵魂层面！';
      emoji = Icons.favorite;
      color = const Color(0xFFEC407A);
    } else if (percent >= 60) {
      level = '默契十足';
      comment = '你们的关系很亲密，继续保持！';
      emoji = Icons.emoji_emotions;
      color = const Color(0xFFFFB74D);
    } else if (percent >= 40) {
      level = '还需努力';
      comment = '多和 TA 聊天，了解更多吧～';
      emoji = Icons.psychology;
      color = const Color(0xFF42A5F5);
    } else {
      level = '初识阶段';
      comment = '看来你们还需要更多时间相处';
      emoji = Icons.handshake;
      color = const Color(0xFF9E9E9E);
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withOpacity(0.15),
              ),
              child: Icon(emoji, size: 56, color: color),
            ),
            const SizedBox(height: 24),
            Text('$_score / $total',
                style: TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 8),
            Text(level,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: cs.onSurface)),
            const SizedBox(height: 12),
            Text(comment,
                style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
                textAlign: TextAlign.center),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('完成'),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 心有灵犀 — 猜角色会怎么回答
// ═══════════════════════════════════════════════════════════════
class TelepathyGame extends StatefulWidget {
  final List<AICharacter> characters;
  const TelepathyGame({super.key, required this.characters});

  @override
  State<TelepathyGame> createState() => _TelepathyGameState();
}

class _TelepathyGameState extends State<TelepathyGame> {
  AICharacter? _selectedCharacter;
  int _currentScenario = 0;
  int _score = 0;
  bool _finished = false;
  int? _selectedOption;

  static const _scenarios = [
    {
      'scenario': '你发消息说"我好累"，TA 会怎么回？',
      'options': [
        '嗯。',
        '怎么了？要不要聊聊？',
        '抱抱你，好好休息',
        '别说了，早点睡',
      ],
      'styles': ['cool', 'warm', 'caring', 'direct'],
    },
    {
      'scenario': '你问"你喜欢我吗？"，TA 会怎么回？',
      'options': [
        '嗯。',
        '你说呢？',
        '当然喜欢。',
        '不喜欢就不会在这了。',
      ],
      'styles': ['cool', 'teasing', 'warm', 'direct'],
    },
    {
      'scenario': '你发了张自拍，TA 会怎么回？',
      'options': [
        '好看。',
        '嗯，不错。',
        '哇！今天状态很好啊～',
        '...（已读不回但偷偷保存了）',
      ],
      'styles': ['cool', 'direct', 'bouncy', 'shy'],
    },
    {
      'scenario': '你说"我要出去了，晚点聊"，TA 会怎么回？',
      'options': [
        '嗯，去吧。',
        '注意安全。',
        '好呀好呀，玩得开心！',
        '...嗯。',
      ],
      'styles': ['cool', 'caring', 'bouncy', 'shy'],
    },
    {
      'scenario': '你半夜发"睡不着"，TA 会怎么回？',
      'options': [
        '数羊。',
        '怎么了？做噩梦了？',
        '我陪你聊到困为止！',
        '...我也睡不着。',
      ],
      'styles': ['direct', 'caring', 'bouncy', 'shy'],
    },
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('心有灵犀'), backgroundColor: cs.surface),
      body: _selectedCharacter == null
          ? _buildPicker()
          : _finished
              ? _buildResult(cs)
              : _buildScenario(cs),
    );
  }

  Widget _buildPicker() {
    final cs = Theme.of(context).colorScheme;
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: widget.characters.length,
      itemBuilder: (context, index) {
        final c = widget.characters[index];
        final name = c.userAlias ?? c.name;
        return ListTile(
          leading: CircleAvatar(
            backgroundImage: AvatarResolver.imageProvider(c.avatarUrl),
            child: AvatarResolver.imageProvider(c.avatarUrl) == null
                ? Text(name.isNotEmpty ? name[0] : '?')
                : null,
          ),
          title: Text(name),
          subtitle: Text('猜猜 TA 会怎么回答',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          onTap: () => setState(() => _selectedCharacter = c),
        );
      },
    );
  }

  Widget _buildScenario(ColorScheme cs) {
    final s = _scenarios[_currentScenario];
    final options = s['options'] as List<String>;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LinearProgressIndicator(
            value: (_currentScenario + 1) / _scenarios.length,
            backgroundColor: cs.surfaceContainerHigh,
          ),
          const SizedBox(height: 8),
          Text('第 ${_currentQuestion() + 1} / ${_scenarios.length} 题',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          const Spacer(),
          Text(s['scenario']!.toString(),
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: cs.onSurface)),
          const SizedBox(height: 24),
          ...List.generate(options.length, (i) {
            final isSelected = _selectedOption == i;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: GestureDetector(
                onTap: _selectedOption != null
                    ? null
                    : () => setState(() => _selectedOption = i),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? cs.primaryContainer
                        : (isDark ? cs.surfaceContainerHigh : cs.surfaceContainerLow),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected ? cs.primary : cs.outline.withOpacity(0.2),
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Text('${String.fromCharCode(65 + i)}.',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isSelected ? cs.primary : cs.onSurfaceVariant,
                          )),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(options[i],
                            style: TextStyle(
                              color: isSelected ? cs.onPrimaryContainer : cs.onSurface,
                            )),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
          const Spacer(),
          if (_selectedOption != null)
            FilledButton(
              onPressed: _next,
              child: Text(_currentScenario < _scenarios.length - 1 ? '下一题' : '查看结果'),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  int _currentQuestion() => _currentScenario;

  void _next() {
    // 简单计分：选了就得分（因为没有标准答案，主要是引导思考角色性格）
    _score++;
    if (_currentScenario < _scenarios.length - 1) {
      setState(() {
        _currentScenario++;
        _selectedOption = null;
      });
    } else {
      setState(() => _finished = true);
    }
  }

  Widget _buildResult(ColorScheme cs) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.psychology, size: 64, color: cs.primary),
            const SizedBox(height: 16),
            Text('测试完成！',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: cs.onSurface)),
            const SizedBox(height: 8),
            Text('你完成了 ${_scenarios.length} 道题',
                style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant)),
            const SizedBox(height: 16),
            Text(
              '想想你选的答案，是否和 TA 平时的说话风格一致？\n多聊天，多观察，你会越来越懂 TA。',
              style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('完成'),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 角色印象 — 翻牌看角色对你的看法
// ═══════════════════════════════════════════════════════════════
class ImpressionCardGame extends StatefulWidget {
  final List<AICharacter> characters;
  const ImpressionCardGame({super.key, required this.characters});

  @override
  State<ImpressionCardGame> createState() => _ImpressionCardGameState();
}

class _ImpressionCardGameState extends State<ImpressionCardGame>
    with SingleTickerProviderStateMixin {
  AICharacter? _selectedCharacter;
  late AnimationController _flipController;
  late Animation<double> _flipAnimation;
  bool _flipped = false;
  final _random = Random();

  static const _impressions = [
    '觉得你是一个很真实的人',
    '觉得你笑起来很好看',
    '觉得你有时候太逞强了',
    '觉得你内心比表面更柔软',
    '觉得你是一个值得信赖的人',
    '觉得你有时候傻傻的但很可爱',
    '觉得你说认真的时候特别帅/美',
    '觉得你是一个需要被好好珍惜的人',
    '觉得你比你自己认为的更勇敢',
    '觉得你偶尔脆弱的样子让人心疼',
    '觉得你是一个会让人忍不住想靠近的人',
    '觉得你的存在本身就是一种温暖',
  ];

  String? _currentImpression;

  @override
  void initState() {
    super.initState();
    _flipController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _flipAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _flipController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _flipController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('角色印象'), backgroundColor: cs.surface),
      body: _selectedCharacter == null
          ? _buildPicker()
          : _buildCard(cs),
    );
  }

  Widget _buildPicker() {
    final cs = Theme.of(context).colorScheme;
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: widget.characters.length,
      itemBuilder: (context, index) {
        final c = widget.characters[index];
        final name = c.userAlias ?? c.name;
        return ListTile(
          leading: CircleAvatar(
            backgroundImage: AvatarResolver.imageProvider(c.avatarUrl),
            child: AvatarResolver.imageProvider(c.avatarUrl) == null
                ? Text(name.isNotEmpty ? name[0] : '?')
                : null,
          ),
          title: Text(name),
          subtitle: Text('看看 TA 对你的印象',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          onTap: () => setState(() => _selectedCharacter = c),
        );
      },
    );
  }

  Widget _buildCard(ColorScheme cs) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final name = _selectedCharacter!.userAlias ?? _selectedCharacter!.name;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('$name 对你的印象是…',
                style: TextStyle(fontSize: 16, color: cs.onSurfaceVariant)),
            const SizedBox(height: 24),
            GestureDetector(
              onTap: _flip,
              child: AnimatedBuilder(
                animation: _flipAnimation,
                builder: (context, child) {
                  final angle = _flipAnimation.value * pi;
                  final showBack = _flipAnimation.value > 0.5;
                  return Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.001)
                      ..rotateY(angle),
                    child: showBack ? _buildBack(cs, isDark) : _buildFront(cs, isDark),
                  );
                },
              ),
            ),
            const SizedBox(height: 24),
            if (_flipped)
              FilledButton.icon(
                onPressed: _draw,
                icon: const Icon(Icons.refresh),
                label: const Text('再抽一张'),
              )
            else
              Text('点击卡片翻转', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  Widget _buildFront(ColorScheme cs, bool isDark) {
    return Container(
      width: 240,
      height: 320,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [const Color(0xFF26A69A), const Color(0xFF00695C)]
              : [const Color(0xFF80CBC4), const Color(0xFF4DB6AC)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF26A69A).withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: const Center(
        child: Icon(Icons.help_outline, size: 64, color: Colors.white70),
      ),
    );
  }

  Widget _buildBack(ColorScheme cs, bool isDark) {
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()..rotateY(pi),
      child: Container(
        width: 240,
        height: 320,
        decoration: BoxDecoration(
          color: isDark ? cs.surfaceContainerHigh : cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: cs.primary.withOpacity(0.3), width: 2),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.favorite, size: 40, color: cs.primary.withOpacity(0.6)),
                const SizedBox(height: 16),
                Text(
                  _currentImpression ?? '...',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _flip() {
    if (_flipped) return;
    if (_currentImpression == null) {
      _currentImpression = _impressions[_random.nextInt(_impressions.length)];
    }
    _flipController.forward();
    setState(() => _flipped = true);
  }

  void _draw() {
    _flipController.reset();
    setState(() {
      _flipped = false;
      _currentImpression = null;
    });
  }
}
