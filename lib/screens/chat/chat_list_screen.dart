import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../blocs/chat/chat_bloc.dart';
import '../../models/chat_session.dart';
import '../../repositories/local_storage_repository.dart';
import '../../services/ai_service.dart';
import '../character/create_character_screen.dart';
import '../character/discover_characters_screen.dart';
import 'chat_detail_screen.dart';

class ChatListScreen extends StatelessWidget {
  const ChatListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF000000) : Colors.white,
      appBar: AppBar(
        title: Text(
          '聊天',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        centerTitle: false,
        elevation: 0,
        backgroundColor: isDark ? const Color(0xFF000000) : Colors.white,
        foregroundColor: isDark ? Colors.white : Colors.black,
        actions: [
          IconButton(
            icon: Icon(Icons.add_circle_outline, size: 24,
                color: isDark ? Colors.white : Colors.black),
            onPressed: () => _showCreateOptions(context),
          ),
        ],
      ),
      body: BlocBuilder<ChatBloc, ChatState>(
        builder: (context, chatState) {
          final chatSessions = chatState is ChatSessionsLoaded
              ? chatState.sessions
              : <ChatSession>[];

          if (chatState is ChatLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (chatSessions.isEmpty) {
            return _buildEmptyState(context);
          }

          return Column(
            children: [
              _buildSearchBar(context, isDark),
              if (chatSessions.isNotEmpty)
                _buildOnlineFriendsRow(context, chatSessions, isDark),
              Expanded(
                child: _buildChatList(context, chatSessions),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1A1A1A) : const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            const SizedBox(width: 12),
            Icon(Icons.search, size: 20,
                color: isDark ? Colors.white.withOpacity(0.4) : Colors.black.withOpacity(0.3)),
            const SizedBox(width: 8),
            Text(
              '搜索',
              style: TextStyle(
                fontSize: 15,
                color: isDark ? Colors.white.withOpacity(0.4) : Colors.black.withOpacity(0.3),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOnlineFriendsRow(BuildContext context, List<ChatSession> sessions, bool isDark) {
    final activeSessions = sessions
        .where((s) => s.lastMessageTime != null)
        .take(10)
        .toList();

    if (activeSessions.isEmpty) return const SizedBox.shrink();

    return Container(
      height: 90,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: activeSessions.length,
        itemBuilder: (context, index) {
          final session = activeSessions[index];
          return _buildOnlineFriendItem(context, session, isDark);
        },
      ),
    );
  }

  Widget _buildOnlineFriendItem(BuildContext context, ChatSession session, bool isDark) {
    final avatarUrl = session.aiCharacterAvatar;
    final name = session.aiCharacterName;

    return GestureDetector(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatDetailScreen(session: session),
          ),
        );
        if (context.mounted) {
          final authBloc = context.read<AuthBloc>();
          if (authBloc.state is AuthAuthenticated) {
            context.read<ChatBloc>().add(ChatLoadSessions(
                (authBloc.state as AuthAuthenticated).user.id));
          }
        }
      },
      child: Container(
        width: 64,
        margin: const EdgeInsets.only(right: 12),
        child: Column(
          children: [
            Stack(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isDark ? const Color(0xFF2C2C2C) : const Color(0xFFE8E4EC),
                  ),
                  child: ClipOval(
                    child: avatarUrl != null && avatarUrl.isNotEmpty
                        ? (avatarUrl.startsWith('/')
                                ? Image.file(File(avatarUrl), fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Center(
                                      child: Text(name.isNotEmpty ? name.substring(0, 1) : '?',
                                          style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 20)),
                                    ))
                                : Image.network(avatarUrl, fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Center(
                                      child: Text(name.isNotEmpty ? name.substring(0, 1) : '?',
                                          style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 20)),
                                    )))
                        : Center(
                            child: Text(name.isNotEmpty ? name.substring(0, 1) : '?',
                                style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 20, fontWeight: FontWeight.w600)),
                          ),
                  ),
                ),
                if (session.aiIsOnline)
                  Positioned(
                    right: 2,
                    bottom: 2,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: const Color(0xFF4CAF50),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isDark ? const Color(0xFF000000) : Colors.white,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              name,
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.white.withOpacity(0.8) : Colors.black.withOpacity(0.7),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  colorScheme.primary.withOpacity(0.12),
                  colorScheme.primary.withOpacity(0.06),
                ],
              ),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.chat_bubble_outline,
              size: 48,
              color: colorScheme.primary.withOpacity(0.45),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            '暂无消息',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '点击右下角 + 创建角色',
            style: TextStyle(
              fontSize: 14,
              color: colorScheme.onSurface.withOpacity(0.35),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatList(BuildContext context, List<ChatSession> chatSessions) {
    final sessions = [...chatSessions];
    sessions.sort((a, b) {
      final aTime = a.lastMessageTime ?? DateTime(0);
      final bTime = b.lastMessageTime ?? DateTime(0);
      return bTime.compareTo(aTime);
    });

    return ListView.separated(
      itemCount: sessions.length,
      separatorBuilder: (context, index) => Divider(
        height: 0.5,
        thickness: 0.5,
        indent: 80,
        color: Theme.of(context).brightness == Brightness.dark
            ? Colors.white.withOpacity(0.08)
            : Colors.black.withOpacity(0.06),
      ),
      itemBuilder: (context, index) {
        final session = sessions[index];
        return _ChatListTile(
          session: session,
          onLongPress: () => _showSessionOptions(context, session),
        );
      },
    );
  }

  void _showSessionOptions(BuildContext context, ChatSession session) {
    final storage = RepositoryProvider.of<LocalStorageRepository>(context);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: Theme.of(ctx).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                ListTile(
                  leading: Icon(Icons.visibility_off, color: Colors.orange[700]),
                  title: const Text('隐藏聊天'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    final updated = session.copyWith(isHidden: true);
                    await storage.saveChatSession(updated);
                    if (context.mounted) {
                      final authBloc = context.read<AuthBloc>();
                      if (authBloc.state is AuthAuthenticated) {
                        context.read<ChatBloc>().add(ChatLoadSessions((authBloc.state as AuthAuthenticated).user.id));
                      }
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('已隐藏聊天')),
                      );
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.delete, color: Color(0xFFE53935)),
                  title: const Text('删除聊天', style: TextStyle(color: Color(0xFFE53935))),
                  onTap: () {
                    Navigator.pop(ctx);
                    showDialog(
                      context: context,
                      builder: (ctx2) => AlertDialog(
                        title: const Text('删除聊天'),
                        content: Text('确定要永久删除与"${session.aiCharacterName}"的聊天记录吗？'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx2),
                            child: const Text('取消'),
                          ),
                          TextButton(
                            onPressed: () async {
                              Navigator.pop(ctx2);
                              await storage.deleteChatSessionCascade(session.id);
                              if (context.mounted) {
                                final authBloc = context.read<AuthBloc>();
                                if (authBloc.state is AuthAuthenticated) {
                                  context.read<ChatBloc>().add(ChatLoadSessions((authBloc.state as AuthAuthenticated).user.id));
                                }
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('已删除与"${session.aiCharacterName}"的聊天')),
                                );
                              }
                            },
                            style: TextButton.styleFrom(foregroundColor: const Color(0xFFE53935)),
                            child: const Text('删除'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showCreateOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.person_add, color: Theme.of(context).colorScheme.primary),
                  ),
                  title: const Text('创建角色'),
                  subtitle: const Text('从零自定义创建 AI 角色', style: TextStyle(fontSize: 12)),
                  onTap: () {
                    Navigator.pop(context);
                    _navigateToCreateCharacter(context);
                  },
                ),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.tertiaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.explore,
                        color: Theme.of(context).colorScheme.tertiary),
                  ),
                  title: const Text('发现角色'),
                  subtitle: const Text('浏览并添加预设角色模板', style: TextStyle(fontSize: 12)),
                  onTap: () {
                    Navigator.pop(context);
                    _navigateToDiscoverCharacters(context);
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _navigateToCreateCharacter(BuildContext context) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => BlocProvider(
          create: (context) => ChatBloc(
            RepositoryProvider.of<LocalStorageRepository>(context),
            AIService(RepositoryProvider.of<LocalStorageRepository>(context)),
          ),
          child: const CreateCharacterScreen(),
        ),
      ),
    );

    if (result == true && context.mounted) {
      final authBloc = context.read<AuthBloc>();
      if (authBloc.state is AuthAuthenticated) {
        final userId = (authBloc.state as AuthAuthenticated).user.id;
        context.read<ChatBloc>().add(ChatLoadSessions(userId));
      }
    }
  }

  void _navigateToDiscoverCharacters(BuildContext context) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const DiscoverCharactersScreen(),
      ),
    );

    if (result == true && context.mounted) {
      final authBloc = context.read<AuthBloc>();
      if (authBloc.state is AuthAuthenticated) {
        final userId = (authBloc.state as AuthAuthenticated).user.id;
        context.read<ChatBloc>().add(ChatLoadSessions(userId));
      }
    }
  }

}

class _ChatListTile extends StatefulWidget {
  final ChatSession session;
  final VoidCallback onLongPress;

  const _ChatListTile({required this.session, required this.onLongPress});

  @override
  State<_ChatListTile> createState() => _ChatListTileState();
}

class _ChatListTileState extends State<_ChatListTile> {
  String? _displayName;

  @override
  void initState() {
    super.initState();
    _loadAlias();
  }

  @override
  void didUpdateWidget(_ChatListTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session.aiCharacterId != widget.session.aiCharacterId ||
        oldWidget.session.aiCharacterName != widget.session.aiCharacterName) {
      _loadAlias();
    }
  }

  Future<void> _loadAlias() async {
    try {
      final storage = RepositoryProvider.of<LocalStorageRepository>(context);
      final character = await storage.getAICharacter(widget.session.aiCharacterId);
      if (character != null && mounted) {
        setState(() => _displayName = character.userAlias ?? character.name);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final session = widget.session;
    final timeText = session.lastMessageTime != null
        ? _formatTime(session.lastMessageTime!)
        : '';

    return InkWell(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatDetailScreen(session: session),
          ),
        );
        if (context.mounted) {
          final authBloc = context.read<AuthBloc>();
          if (authBloc.state is AuthAuthenticated) {
            final userId = (authBloc.state as AuthAuthenticated).user.id;
            context.read<ChatBloc>().add(ChatLoadSessions(userId));
          }
        }
        Future.delayed(const Duration(seconds: 4), () {
          if (context.mounted) {
            final authBloc = context.read<AuthBloc>();
            if (authBloc.state is AuthAuthenticated) {
              context.read<ChatBloc>().add(ChatLoadSessions(
                  (authBloc.state as AuthAuthenticated).user.id));
            }
          }
        });
      },
      onLongPress: widget.onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                _buildAvatar(colorScheme),
                if (session.unreadCount > 0)
                  Positioned(
                    right: -2,
                    top: -2,
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: colorScheme.primary,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: colorScheme.surface,
                          width: 2,
                        ),
                      ),
                      child: Text(
                        session.unreadCount > 99 ? '99+' : session.unreadCount.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          _displayName ?? session.aiCharacterName,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (timeText.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Text(
                          timeText,
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurface.withOpacity(0.4),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    session.lastMessage ?? '暂无消息',
                    style: TextStyle(
                      fontSize: 14,
                      color: session.lastMessage != null
                          ? colorScheme.onSurface.withOpacity(0.55)
                          : colorScheme.onSurface.withOpacity(0.3),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar(ColorScheme colorScheme) {
    final avatarUrl = widget.session.aiCharacterAvatar;
    return Stack(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colorScheme.primaryContainer,
          ),
          child: ClipOval(
            child: avatarUrl == null || avatarUrl.isEmpty
                ? Center(
                    child: Text(
                      (_displayName ?? widget.session.aiCharacterName).isNotEmpty
                          ? (_displayName ?? widget.session.aiCharacterName).substring(0, 1)
                          : '?',
                      style: TextStyle(
                        color: colorScheme.primary,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                : (avatarUrl.startsWith('/') || avatarUrl.contains('\\')
                    ? Image.file(
                        File(avatarUrl),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Center(
                          child: Icon(Icons.person, color: colorScheme.primary),
                        ),
                      )
                    : Image.network(
                        avatarUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Center(
                          child: Icon(Icons.person, color: colorScheme.primary),
                        ),
                      )),
          ),
        ),
        if (widget.session.aiIsOnline)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: const Color(0xFF4CAF50),
                shape: BoxShape.circle,
                border: Border.all(
                  color: colorScheme.surface,
                  width: 2,
                ),
              ),
            ),
          ),
      ],
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate = DateTime(time.year, time.month, time.day);

    if (messageDate == today) {
      return DateFormat('HH:mm').format(time);
    } else if (messageDate == today.subtract(const Duration(days: 1))) {
      return '昨天';
    } else if (now.difference(time).inDays < 7) {
      return DateFormat('E', 'zh_CN').format(time);
    } else {
      return DateFormat('MM/dd').format(time);
    }
  }
}
