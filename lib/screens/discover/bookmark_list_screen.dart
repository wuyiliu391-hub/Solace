import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../models/chat_message.dart';
import '../../models/chat_session.dart';
import '../../models/group_chat_message.dart';
import '../../models/group_chat_session.dart';
import '../../repositories/local_storage_repository.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../utils/avatar_resolver.dart';
import '../chat/chat_detail_screen.dart';
import '../group_chat/group_chat_detail_screen.dart';

/// 收藏消息列表 — 展示用户收藏的所有 AI/用户消息
class BookmarkListScreen extends StatefulWidget {
  const BookmarkListScreen({super.key});

  @override
  State<BookmarkListScreen> createState() => _BookmarkListScreenState();
}

class _BookmarkListScreenState extends State<BookmarkListScreen> {
  List<Map<String, dynamic>> _bookmarks = [];
  bool _isLoading = true;

  /// 当前筛选的角色 ID；null = 全部
  String? _selectedCharacterId;

  /// 搜索：关键词 + 控制器。空 = 显示全部。
  /// 搜索是**本地过滤**（收藏量小），输入即出结果，不查库。
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadBookmarks();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadBookmarks() async {
    setState(() => _isLoading = true);
    try {
      final storage = RepositoryProvider.of<LocalStorageRepository>(context);
      final bookmarks = await storage.getBookmarkedMessages();
      final groupMsgs = await storage.getGroupBookmarkedMessages();
      // 群会话名：尽量按 userId 拉；失败则用空 map（展示发送者名）
      List<GroupChatSession> groupSessions = const [];
      try {
        final auth = context.read<AuthBloc>().state;
        if (auth is AuthAuthenticated) {
          groupSessions = await storage.getGroupChatSessions(auth.user.id);
        }
      } catch (_) {}
      final groupById = {
        for (final s in groupSessions) s.id: s,
      };
      final groupEntries = <Map<String, dynamic>>[];
      for (final gm in groupMsgs) {
        final session = groupById[gm.groupId];
        groupEntries.add({
          'kind': 'group',
          'message': null,
          'groupMessage': gm,
          'sessionName': session?.name.isNotEmpty == true
              ? session!.name
              : (gm.senderName.isEmpty ? '群聊' : gm.senderName),
          'sessionId': gm.groupId,
          'characterId': 'group:${gm.groupId}',
          'characterAvatar': session?.avatarUrl,
        });
      }
      final singleEntries = [
        for (final b in bookmarks)
          {
            ...b,
            'kind': 'single',
          }
      ];
      final merged = [...groupEntries, ...singleEntries];
      if (mounted) {
        setState(() {
          _bookmarks = merged;
          if (_selectedCharacterId != null &&
              !merged.any(
                  (b) => (b['characterId'] as String?) == _selectedCharacterId)) {
            _selectedCharacterId = null;
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('加载收藏消息失败: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 去重后的角色列表（按 characterId，用于筛选栏）
  List<Map<String, dynamic>> get _characters {
    final seen = <String, Map<String, dynamic>>{};
    for (final b in _bookmarks) {
      final id = (b['characterId'] as String?) ?? '';
      if (id.isEmpty) continue;
      seen.putIfAbsent(
        id,
        () => {
          'id': id,
          'name': (b['sessionName'] as String?) ?? '未知角色',
          'avatar': b['characterAvatar'] as String?,
        },
      );
    }
    return seen.values.toList();
  }

  /// 按当前筛选角色过滤后的收藏列表
  List<Map<String, dynamic>> get _filteredBookmarks {
    final id = _selectedCharacterId;
    if (id == null) return _bookmarks;
    return _bookmarks
        .where((b) => (b['characterId'] as String?) == id)
        .toList();
  }

  /// 取消收藏
  Future<void> _unbookmark(ChatMessage msg) async {
    try {
      final storage = RepositoryProvider.of<LocalStorageRepository>(context);
      await storage.saveChatMessage(msg.copyWith(isBookmark: false));
      await _loadBookmarks(); // 刷新列表
    } catch (e) {
      debugPrint('取消收藏失败: $e');
    }
  }

  Future<void> _unbookmarkGroup(GroupChatMessage msg) async {
    try {
      final storage = RepositoryProvider.of<LocalStorageRepository>(context);
      final meta = Map<String, dynamic>.from(msg.metadata ?? {});
      meta['bookmarked'] = false;
      await storage.saveGroupChatMessage(msg.copyWith(metadata: meta));
      await _loadBookmarks();
    } catch (e) {
      debugPrint('取消群聊收藏失败: $e');
    }
  }

  // ──────────────────────── 搜索 ────────────────────────

  /// 在已加载的收藏里做本地过滤。
  ///
  /// 刻意**不查库**：收藏量通常在百级，全量已加载在内存里，
  /// 本地过滤零延迟、无 loading 闪烁。跨会话/跨群统一处理，
  /// 匹配内容 + 会话名/群名 + 发言者名。
  List<Map<String, dynamic>> _applyQuery(List<Map<String, dynamic>> all) {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return all;
    return all.where((e) {
      final isGroup = (e['kind'] as String?) == 'group';
      final content =
          (isGroup ? (e['groupMessage'] as GroupChatMessage?) : null)
                  ?.content ??
              (e['message'] as ChatMessage?)?.content ??
              '';
      final sender = (isGroup
              ? (e['groupMessage'] as GroupChatMessage?)?.senderName
              : null) ??
          '';
      final session = (e['sessionName'] as String?) ?? '';
      final haystack = '$content $sender $session'.toLowerCase();
      return haystack.contains(q);
    }).toList();
  }

  /// 当前展示的列表：搜索词 + 角色筛选叠加。
  List<Map<String, dynamic>> get _visibleBookmarks =>
      _applyQuery(_filteredBookmarks);

  bool get _hasQuery => _searchQuery.trim().isNotEmpty;

  void _clearSearch() {
    _searchController.clear();
    setState(() => _searchQuery = '');
    _searchFocusNode.unfocus();
  }

  /// 跳转到原聊天会话
  void _openChatSession(Map<String, dynamic> entry) {
    final kind = entry['kind'] as String? ?? 'single';
    if (kind == 'group') {
      final gm = entry['groupMessage'] as GroupChatMessage?;
      final groupId = entry['sessionId'] as String? ?? '';
      if (gm == null || groupId.isEmpty) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => FutureBuilder<GroupChatSession?>(
            future: RepositoryProvider.of<LocalStorageRepository>(context)
                .getGroupChatSession(groupId),
            builder: (context, snapshot) {
              if (!snapshot.hasData || snapshot.data == null) {
                return Scaffold(
                  appBar: AppBar(title: const Text('群聊已不存在')),
                  body: const Center(child: Text('该群聊已被删除')),
                );
              }
              return GroupChatDetailScreen(
                session: snapshot.data!,
                initialJumpToMessageId: gm.id,
              );
            },
          ),
        ),
      );
      return;
    }

    final sessionId = entry['sessionId'] as String;
    final targetMessage = entry['message'] as ChatMessage?;
    if (targetMessage == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FutureBuilder<ChatSession?>(
          future: RepositoryProvider.of<LocalStorageRepository>(context)
              .getChatSession(sessionId),
          builder: (context, snapshot) {
            if (!snapshot.hasData || snapshot.data == null) {
              return Scaffold(
                appBar: AppBar(title: const Text('会话已不存在')),
                body: const Center(child: Text('该聊天会话已被删除')),
              );
            }
            return ChatDetailScreen(
              session: snapshot.data!,
              initialJumpToMessage: targetMessage,
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '收藏消息',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            color: isDark ? Colors.white : Colors.black,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _bookmarks.isEmpty
              ? _buildEmptyState(cs, isDark)
              : Column(
                  children: [
                    _buildSearchBar(cs),
                    _buildFilterBar(cs, isDark),
                    Expanded(
                      child: _visibleBookmarks.isEmpty
                          ? _buildNoMatchState(cs)
                          : _buildList(cs, isDark),
                    ),
                  ],
                ),
    );
  }

  /// 收藏搜索栏。搜索 + 角色筛选可叠加。
  Widget _buildSearchBar(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocusNode,
        onChanged: (v) => setState(() => _searchQuery = v),
        textInputAction: TextInputAction.search,
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          hintText: '搜索收藏内容、角色名、群名',
          hintStyle: TextStyle(
            fontSize: 13,
            color: cs.onSurface.withOpacity(0.4),
          ),
          prefixIcon: Icon(Icons.search, size: 20, color: cs.primary),
          suffixIcon: !_hasQuery
              ? null
              : IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: _clearSearch,
                  tooltip: '清除',
                ),
          isDense: true,
          filled: true,
          fillColor: cs.surfaceContainerHighest,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  /// 搜索有词但无结果（区别于「一个收藏都没有」）
  Widget _buildNoMatchState(ColorScheme cs) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 56, color: cs.onSurface.withOpacity(0.2)),
            const SizedBox(height: 12),
            Text(
              '没有匹配「$_searchQuery」的收藏',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: cs.onSurface.withOpacity(0.5),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _clearSearch,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('清除搜索'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme cs, bool isDark) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.bookmark_border,
            size: 64,
            color: cs.onSurface.withOpacity(0.2),
          ),
          const SizedBox(height: 16),
          Text(
            '还没有收藏消息',
            style: TextStyle(
              fontSize: 16,
              color: cs.onSurface.withOpacity(0.4),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '在聊天中长按消息 → 收藏',
            style: TextStyle(
              fontSize: 13,
              color: cs.onSurface.withOpacity(0.3),
            ),
          ),
        ],
      ),
    );
  }

  /// 角色筛选栏（全部 + 各角色）
  Widget _buildFilterBar(ColorScheme cs, bool isDark) {
    final chars = _characters;
    // 搜索时只保留在搜索结果里出现过的角色，避免用户点了某个角色
    // 却一条都看不到（因为那条不在搜索结果里）——那种体验最让人困惑。
    final visible = _searchQuery.trim().isEmpty
        ? chars
        : chars.where((c) {
            final id = c['id'] as String;
            return _bookmarks
                .where((b) => (b['characterId'] as String?) == id)
                .any((b) => _applyQuery([b]).isNotEmpty);
          }).toList();
    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        itemCount: visible.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          if (index == 0) {
            return _buildFilterChip(cs, null, '全部', null);
          }
          final c = visible[index - 1];
          return _buildFilterChip(cs, c['id'] as String, c['name'] as String,
              c['avatar'] as String?);
        },
      ),
    );
  }

  Widget _buildFilterChip(
      ColorScheme cs, String? id, String name, String? avatar) {
    final selected = _selectedCharacterId == id;
    final avatarWidget = AvatarResolver.imageWidget(
      avatar,
      width: 18,
      height: 18,
      onError: () =>
          Icon(Icons.person_rounded, size: 18, color: cs.onSurfaceVariant),
    );
    return ChoiceChip(
      avatar: avatarWidget == null
          ? null
          : ClipOval(
              child: SizedBox(width: 18, height: 18, child: avatarWidget)),
      label: Text(name, style: const TextStyle(fontSize: 12)),
      selected: selected,
      showCheckmark: false,
      onSelected: (_) => setState(() => _selectedCharacterId = id),
    );
  }

  Widget _buildList(ColorScheme cs, bool isDark) {
    final items = _visibleBookmarks;
    return RefreshIndicator(
      onRefresh: _loadBookmarks,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: items.length + (_hasQuery ? 1 : 0),
        itemBuilder: (context, index) {
          // 顶部结果计数条：搜索时告知「匹配 N / 共 M」
          if (_hasQuery && index == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '匹配 ${items.length} 条，共 ${_bookmarks.length} 条收藏',
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurface.withOpacity(0.5),
                ),
              ),
            );
          }
          final entry = items[_hasQuery ? index - 1 : index];
          final isGroup = (entry['kind'] as String?) == 'group';
          final singleMsg = entry['message'] as ChatMessage?;
          final groupMsg = entry['groupMessage'] as GroupChatMessage?;
          final sessionName = (entry['sessionName'] as String?) ?? '';
          final content = isGroup
              ? (groupMsg?.content ?? '')
              : (singleMsg?.content ?? '');
          final createdAt = isGroup
              ? (groupMsg?.timestamp ?? DateTime.now())
              : (singleMsg?.createdAt ?? DateTime.now());
          final isAI = isGroup
              ? !(groupMsg?.isUser ?? true)
              : (singleMsg?.isFromAI ?? false);
          final timeStr = DateFormat('MM/dd HH:mm').format(createdAt);

          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            color: isDark
                ? const Color(0xFF1E1E1E)
                : Colors.white,
            elevation: isDark ? 0 : 0.5,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: cs.outlineVariant.withOpacity(0.3),
                width: 0.5,
              ),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _openChatSession(entry),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 头部：角色名 + 时间
                    Row(
                      children: [
                        Icon(
                          isGroup
                              ? Icons.groups_rounded
                              : (isAI
                                  ? Icons.smart_toy_rounded
                                  : Icons.person_rounded),
                          size: 16,
                          color: isAI || isGroup
                              ? cs.primary
                              : cs.onSurface.withOpacity(0.5),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            isGroup
                                ? (groupMsg?.senderName.isNotEmpty == true
                                    ? groupMsg!.senderName
                                    : sessionName)
                                : (isAI ? sessionName : '你'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isAI || isGroup
                                  ? cs.primary
                                  : cs.onSurface.withOpacity(0.7),
                            ),
                          ),
                        ),
                        Text(
                          timeStr,
                          style: TextStyle(
                            fontSize: 11,
                            color: cs.onSurface.withOpacity(0.4),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // 消息内容
                    Text(
                      content,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.4,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // 底部操作栏
                    Row(
                      children: [
                        // 会话来源标签
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: cs.primary.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            isGroup ? '群聊 · $sessionName' : sessionName,
                            style: TextStyle(
                              fontSize: 11,
                              color: cs.primary.withOpacity(0.8),
                            ),
                          ),
                        ),
                        const Spacer(),
                        // 取消收藏按钮
                        GestureDetector(
                          onTap: () {
                            if (isGroup && groupMsg != null) {
                              _unbookmarkGroup(groupMsg);
                            } else if (singleMsg != null) {
                              _unbookmark(singleMsg);
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.amber.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.bookmark_rounded,
                                  size: 12,
                                  color: Colors.amber.shade700,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '取消收藏',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.amber.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
