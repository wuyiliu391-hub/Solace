import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../models/chat_message.dart';
import '../../models/chat_session.dart';
import '../../repositories/local_storage_repository.dart';
import '../../utils/avatar_resolver.dart';
import '../chat/chat_detail_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _loadBookmarks();
  }

  Future<void> _loadBookmarks() async {
    setState(() => _isLoading = true);
    try {
      final storage = RepositoryProvider.of<LocalStorageRepository>(context);
      final bookmarks = await storage.getBookmarkedMessages();
      if (mounted) {
        setState(() {
          _bookmarks = bookmarks;
          // 选中的角色已没有收藏时，回退到「全部」
          if (_selectedCharacterId != null &&
              !bookmarks
                  .any((b) => (b['characterId'] as String?) == _selectedCharacterId)) {
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

  /// 跳转到原聊天会话
  void _openChatSession(Map<String, dynamic> entry) {
    final sessionId = entry['sessionId'] as String;
    final targetMessage = entry['message'] as ChatMessage?;
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
                    _buildFilterBar(cs, isDark),
                    Expanded(
                      child: _filteredBookmarks.isEmpty
                          ? _buildEmptyState(cs, isDark)
                          : _buildList(cs, isDark),
                    ),
                  ],
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
    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        itemCount: chars.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          if (index == 0) {
            return _buildFilterChip(cs, null, '全部', null);
          }
          final c = chars[index - 1];
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
    final items = _filteredBookmarks;
    return RefreshIndicator(
      onRefresh: _loadBookmarks,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final entry = items[index];
          final msg = entry['message'] as ChatMessage;
          final sessionName = entry['sessionName'] as String;
          final isAI = msg.isFromAI;
          final timeStr = DateFormat('MM/dd HH:mm').format(msg.createdAt);

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
                          isAI ? Icons.smart_toy_rounded : Icons.person_rounded,
                          size: 16,
                          color: isAI
                              ? cs.primary
                              : cs.onSurface.withOpacity(0.5),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isAI ? sessionName : '你',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isAI
                                ? cs.primary
                                : cs.onSurface.withOpacity(0.7),
                          ),
                        ),
                        const Spacer(),
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
                      msg.content,
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
                            sessionName,
                            style: TextStyle(
                              fontSize: 11,
                              color: cs.primary.withOpacity(0.8),
                            ),
                          ),
                        ),
                        const Spacer(),
                        // 取消收藏按钮
                        GestureDetector(
                          onTap: () => _unbookmark(msg),
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
