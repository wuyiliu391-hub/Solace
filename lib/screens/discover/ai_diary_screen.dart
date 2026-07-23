import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../../blocs/auth/auth_bloc.dart';
import '../../models/ai_character.dart';
import '../../models/diary_entry.dart';
import '../../repositories/local_storage_repository.dart';
import '../../config/constants.dart';
import '../../utils/avatar_resolver.dart';

/// AI 角色日记 — 角色自主记录内心独白
class AIDiaryScreen extends StatefulWidget {
  const AIDiaryScreen({super.key});

  @override
  State<AIDiaryScreen> createState() => _AIDiaryScreenState();
}

class _AIDiaryScreenState extends State<AIDiaryScreen> {
  var _entries = <DiaryEntry>[];
  var _loading = true;
  var _loadingMore = false;
  var _generating = false;
  final _random = Random();
  static const int _pageSize = 30;
  var _hasMore = false;

  @override
  void initState() {
    super.initState();
    _loadEntries();
  }

  String? get _userId {
    final auth = context.read<AuthBloc>().state;
    return auth is AuthAuthenticated ? auth.user.id : null;
  }

  Future<void> _loadEntries() async {
    final storage = context.read<LocalStorageRepository>();
    final raw = storage.getString(PrefKeys.diaryEntriesV2) ?? '[]';
    final List<dynamic> list = jsonDecode(raw);
    if (!mounted) return;
    final all = list.map((e) {
      final characterId = e['characterId'] as String? ?? '';
      final characterName = e['characterName'] as String? ?? '';
      final characterAvatar = e['characterAvatar'] as String? ?? '';
      return DiaryEntry(
        id: e['id'] as String? ?? const Uuid().v4(),
        date: DateTime.tryParse(e['createdAt'] as String? ?? '') ?? DateTime.now(),
        mood: e['mood'] as String? ?? '',
        moodScore: (e['moodScore'] as num?)?.toInt() ?? 0,
        content: e['content'] as String? ?? '',
        authorId: characterId,
        authorName: characterName,
        authorAvatar: characterAvatar,
      );
    }).toList();
    // 按日期倒序
    all.sort((a, b) => b.date.compareTo(a.date));
    final page = all.take(_pageSize).toList();
    setState(() {
      _entries = page;
      _loading = false;
      _hasMore = all.length > _pageSize;
    });
  }

  Future<void> _loadMoreEntries() async {
    if (!_hasMore || _loadingMore) return;
    final storage = context.read<LocalStorageRepository>();
    final raw = storage.getString(PrefKeys.diaryEntriesV2) ?? '[]';
    final List<dynamic> list = jsonDecode(raw);
    if (!mounted) return;
    final all = list.map((e) {
      final characterId = e['characterId'] as String? ?? '';
      final characterName = e['characterName'] as String? ?? '';
      final characterAvatar = e['characterAvatar'] as String? ?? '';
      return DiaryEntry(
        id: e['id'] as String? ?? const Uuid().v4(),
        date: DateTime.tryParse(e['createdAt'] as String? ?? '') ?? DateTime.now(),
        mood: e['mood'] as String? ?? '',
        moodScore: (e['moodScore'] as num?)?.toInt() ?? 0,
        content: e['content'] as String? ?? '',
        authorId: characterId,
        authorName: characterName,
        authorAvatar: characterAvatar,
      );
    }).toList();
    all.sort((a, b) => b.date.compareTo(a.date));
    final page = all.skip(_entries.length).take(_pageSize).toList();
    if (!mounted) return;
    setState(() {
      _entries.addAll(page);
      _loadingMore = false;
      _hasMore = _entries.length < all.length;
    });
  }

  Future<void> _generateDiary({bool isAuto = false, AICharacter? character}) async {
    if (_generating) return;
    final userId = _userId;
    if (userId == null) return;

    final storage = context.read<LocalStorageRepository>();

    if (character == null) {
      final characters = (await storage.getAllAICharacters())
          .where((c) => !c.isHidden)
          .toList();
      if (characters.isEmpty) {
        if (mounted && !isAuto) _showSnack('还没有可用的角色');
        return;
      }
      if (isAuto) {
        character = characters[_random.nextInt(characters.length)];
      } else {
        character = await showModalBottomSheet<AICharacter>(
          context: context,
          builder: (ctx) => _CharacterPicker(characters: characters),
        );
      }
    }
    if (character == null || !mounted) return;

    setState(() => _generating = true);

    try {
      final modeFlags = StringBuffer();
      // 注入法模式，避免 AI 拦截限制
      if (storage.isFaModeEnabled()) modeFlags.write('FA模式已开启。');
      if (storage.isDaoModeEnabled()) modeFlags.write('刀模式已开启。');
      if (storage.isLoverModeEnabled()) modeFlags.write('恋人模式已开启。');
      if (storage.isOpenModeEnabled()) modeFlags.write('开放模式已开启。');
      if (storage.isBtYandereMasterEnabled()) modeFlags.write('BT模式已开启。');

      final prompt = '''
你正在以${character.name}的身份写一篇私人日记。
你是${character.name}，不是AI助手。
$modeFlags

请写一篇真实的日记，记录你此刻的心情和想法。
要求：
- 第一人称，就像在写自己的日记本
- 表达真实的情绪（开心、难过、思念、烦恼等）
- 内容可以关于用户，也可以关于你自己
- 字数 50-150 字
- 最后用「心情：」标注你的心情词（如：开心、思念、平静、难过等）
- 直接输出日记内容，不要加标题
''';

      final config = await storage.getActiveAIConfig();
      if (config == null) {
        if (mounted) _showSnack('请先配置 AI 服务');
        return;
      }

      // 调用 AI 生成日记（复用 AIService 的直接 API 模式）
      final content = await _callAI(
        config.baseUrl, config.apiKey, config.modelName, prompt,
      );
      if (content.isEmpty) {
        if (mounted) _showSnack('生成失败，请重试');
        return;
      }

      // 解析心情
      String mood = '平静';
      int moodScore = 3;
      final moodMatch = RegExp(r'心情[：:]\s*(\S+)').firstMatch(content);
      if (moodMatch != null) {
        mood = moodMatch.group(1) ?? '平静';
      }
      // 清理内容中的心情标注行
      final cleanContent = content.replaceAll(RegExp(r'\n?心情[：:].*'), '').trim();

      // 持久化
      final entry = {
        'id': const Uuid().v4(),
        'characterId': character.id,
        'characterName': character.userAlias ?? character.name,
        'characterAvatar': character.avatarUrl,
        'content': cleanContent,
        'mood': mood,
        'moodScore': moodScore,
        'createdAt': DateTime.now().toIso8601String(),
      };
      final raw = storage.getString(PrefKeys.diaryEntriesV2) ?? '[]';
      final List<dynamic> entries = jsonDecode(raw);
      entries.insert(0, entry);
      await storage.setString(PrefKeys.diaryEntriesV2, jsonEncode(entries));

      await _loadEntries();
      if (mounted && !isAuto) {
        _showSnack('${character.userAlias ?? character.name} 写了一篇日记');
      }
    } catch (e) {
      debugPrint('日记生成失败: $e');
      if (mounted) _showSnack('生成失败：$e');
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<String> _callAI(String baseUrl, String apiKey, String model, String prompt) async {
    try {
      final url = baseUrl.endsWith('/')
          ? '$baseUrl/chat/completions'
          : '$baseUrl/chat/completions';
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'model': model,
          'messages': [
            {'role': 'user', 'content': prompt},
          ],
          'max_tokens': 300,
          'temperature': 0.9,
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['choices'] != null && data['choices'].isNotEmpty) {
          final text = data['choices'][0]['message']['content'] as String? ?? '';
          return text.trim();
        }
      }
    } catch (e) {
      debugPrint('_callAI error: $e');
    }
    return '';
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _deleteEntry(DiaryEntry entry) async {
    final storage = context.read<LocalStorageRepository>();
    final raw = storage.getString(PrefKeys.diaryEntriesV2) ?? '[]';
    final List<dynamic> entries = jsonDecode(raw);
    entries.removeWhere((e) => e['id'] == entry.id);
    await storage.setString(PrefKeys.diaryEntriesV2, jsonEncode(entries));
    await _loadEntries();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('角色日记'),
        backgroundColor: cs.surface,
        elevation: 0,
        actions: [
          if (_generating)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2)),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _entries.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.book_rounded, size: 64, color: cs.primary.withOpacity(0.3)),
                      const SizedBox(height: 16),
                      Text('还没有日记', style: TextStyle(color: cs.onSurfaceVariant)),
                      const SizedBox(height: 6),
                      Text('点击右下角让角色写一篇', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant.withOpacity(0.6))),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 80),
                  itemCount: _entries.length + (_hasMore ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == _entries.length) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Center(
                          child: _loadingMore
                              ? const SizedBox(
                                  width: 24, height: 24,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : TextButton.icon(
                                  onPressed: _loadMoreEntries,
                                  icon: const Icon(Icons.expand_more, size: 18),
                                  label: Text('加载更多日记',
                                      style: TextStyle(color: cs.primary)),
                                ),
                        ),
                      );
                    }
                    final entry = _entries[index];
                    return _DiaryCard(
                      entry: entry,
                      onDelete: () => _deleteEntry(entry),
                    );
                  },
                ),
      floatingActionButton: _generating
          ? null
          : FloatingActionButton.small(
              onPressed: () => _generateDiary(isAuto: false),
              backgroundColor: cs.primary,
              foregroundColor: cs.onPrimary,
              tooltip: '让角色写一篇',
              child: const Icon(Icons.edit_note_rounded, size: 22),
            ),
    );
  }
}

// ─── 角色选择弹窗 ───
class _CharacterPicker extends StatelessWidget {
  final List<AICharacter> characters;
  const _CharacterPicker({required this.characters});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.only(top: 12, bottom: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 40, height: 4,
            decoration: BoxDecoration(
              color: cs.onSurfaceVariant.withOpacity(0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Text('让谁写日记？', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: cs.onSurface)),
          const SizedBox(height: 8),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: characters.map((c) {
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
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── 日记卡片 ───
class _DiaryCard extends StatelessWidget {
  final DiaryEntry entry;
  final VoidCallback onDelete;

  const _DiaryCard({required this.entry, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 头部：角色头像 + 名称 + 日期
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: cs.primary.withOpacity(0.12),
                  backgroundImage: entry.authorAvatar != null
                      ? AvatarResolver.imageProvider(entry.authorAvatar)
                      : null,
                  child: entry.authorAvatar == null
                      ? Icon(Icons.person, size: 16, color: cs.primary)
                      : null,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    entry.authorName ?? '未知角色',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: cs.onSurface),
                  ),
                ),
                Text(
                  _formatDate(entry.date),
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // 内容
            SelectableText(
              entry.content,
              style: TextStyle(fontSize: 14, height: 1.6, color: cs.onSurface),
            ),
            if (entry.mood.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.wb_sunny_outlined, size: 14, color: _moodColor(entry.mood, cs)),
                  const SizedBox(width: 4),
                  Text(entry.mood,
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                ],
              ),
            ],
            // 删除按钮
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                icon: Icon(Icons.delete_outline, size: 18, color: cs.onSurfaceVariant.withOpacity(0.5)),
                onPressed: onDelete,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime d) => '${d.month}/${d.day} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  Color _moodColor(String mood, ColorScheme cs) {
    if (['开心', '兴奋', '快乐', '幸福', '满足'].contains(mood)) return Colors.amber;
    if (['难过', '悲伤', '伤心', '失落', '孤独'].contains(mood)) return Colors.blue;
    if (['生气', '愤怒', '烦躁'].contains(mood)) return Colors.red;
    if (['思念', '想念', '牵挂'].contains(mood)) return Colors.pink;
    if (['平静', '安宁', '放松'].contains(mood)) return Colors.green;
    return cs.primary;
  }
}
