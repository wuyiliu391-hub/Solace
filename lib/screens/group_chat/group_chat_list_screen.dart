// 群聊列表页面（对标 ChatListScreen 模式）
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../blocs/group_chat/group_chat_bloc.dart';
import '../../models/group_chat_session.dart';
import 'group_chat_create_screen.dart';
import 'group_chat_detail_screen.dart';

class GroupChatListScreen extends StatelessWidget {
  const GroupChatListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: Text(
          '群聊',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          ),
        ),
        centerTitle: false,
        elevation: 0,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        actions: [
          IconButton(
            icon: Icon(Icons.add_circle_outline, size: 24,
                color: colorScheme.onSurface),
            onPressed: () => _navigateToCreate(context),
          ),
        ],
      ),
      body: BlocBuilder<GroupChatBloc, GroupChatState>(
        builder: (context, state) {
          if (state is GroupChatError) {
            return _buildErrorState(context, state.message);
          }
          final sessions = state is GroupChatSessionsLoaded
              ? state.sessions
              : <GroupChatSession>[];

          if (state is GroupChatLoading || state is GroupChatInitial) {
            return const Center(child: CircularProgressIndicator());
          }

          if (sessions.isEmpty) {
            return _buildEmptyState(context);
          }

          return _buildGroupChatList(context, sessions, colorScheme);
        },
      ),
    );
  }

  Widget _buildGroupChatList(
    BuildContext context,
    List<GroupChatSession> sessions,
    ColorScheme colorScheme,
  ) {
    // 置顶排前面，然后按时间排序
    final sorted = [...sessions];
    sorted.sort((a, b) {
      if (a.isPinned && !b.isPinned) return -1;
      if (!a.isPinned && b.isPinned) return 1;
      final aTime = a.lastMessageTime ?? DateTime(0);
      final bTime = b.lastMessageTime ?? DateTime(0);
      return bTime.compareTo(aTime);
    });

    return ListView.separated(
      itemCount: sorted.length,
      separatorBuilder: (context, index) => Divider(
        height: 0.5,
        thickness: 0.5,
        indent: 80,
        color: colorScheme.outline.withOpacity(0.15),
      ),
      itemBuilder: (context, index) {
        final session = sorted[index];
        return _GroupChatTile(session: session);
      },
    );
  }

  Widget _buildErrorState(BuildContext context, String errorMessage) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48,
                color: colorScheme.error.withOpacity(0.6)),
            const SizedBox(height: 16),
            Text(
              '加载失败',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              errorMessage,
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurface.withOpacity(0.4),
              ),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () {
                final bloc = context.read<GroupChatBloc>();
                bloc.add(const GroupChatLoadSessions('local_user'));
              },
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('重试'),
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
              Icons.groups_outlined,
              size: 48,
              color: colorScheme.primary.withOpacity(0.45),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            '暂无群聊',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '点击右上角 + 创建群聊',
            style: TextStyle(
              fontSize: 14,
              color: colorScheme.onSurface.withOpacity(0.35),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _navigateToCreate(BuildContext context) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const GroupChatCreateScreen()),
    );
    if (context.mounted) {
      context.read<GroupChatBloc>().add(const GroupChatLoadSessions('local_user'));
    }
  }
}

/// 群聊列表项
class _GroupChatTile extends StatelessWidget {
  final GroupChatSession session;
  const _GroupChatTile({required this.session});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final timeText = session.lastMessageTime != null
        ? _formatTime(session.lastMessageTime!)
        : '';

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => GroupChatDetailScreen(session: session),
          ),
        ).then((_) {
          if (context.mounted) {
            context.read<GroupChatBloc>().add(const GroupChatMarkRead(''));
          }
        });
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 头像
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colorScheme.tertiaryContainer,
              ),
              child: ClipOval(
                child: session.avatarUrl != null && session.avatarUrl!.isNotEmpty
                    ? Image.network(
                        session.avatarUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _avatarFallback(colorScheme),
                      )
                    : _avatarFallback(colorScheme),
              ),
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
                          session.name,
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
            // 未读角标
            if (session.unreadCount > 0)
              Container(
                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: colorScheme.surface, width: 2),
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
          ],
        ),
      ),
    );
  }

  Widget _avatarFallback(ColorScheme cs) {
    return Center(
      child: Text(
        '群',
        style: TextStyle(
          color: cs.tertiary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate = DateTime(time.year, time.month, time.day);

    if (messageDate == today) {
      return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    } else if (messageDate == today.subtract(const Duration(days: 1))) {
      return '昨天';
    } else if (now.difference(time).inDays < 7) {
      return ['周日', '周一', '周二', '周三', '周四', '周五', '周六'][(time.weekday - 1) % 7];
    } else {
      return '${time.month.toString().padLeft(2, '0')}/${time.day.toString().padLeft(2, '0')}';
    }
  }
}
