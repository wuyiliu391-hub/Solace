// 群聊列表页面（对标 ChatListScreen 模式）
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../blocs/group_chat/group_chat_bloc.dart';
import '../../models/group_chat_session.dart';
import '../../models/ai_character.dart';
import '../../repositories/local_storage_repository.dart';
import '../../utils/avatar_resolver.dart';
import '../../utils/character_color.dart';
import 'group_chat_create_screen.dart';
import 'group_chat_detail_screen.dart';

class GroupChatListScreen extends StatefulWidget {
  const GroupChatListScreen({super.key});

  @override
  State<GroupChatListScreen> createState() => _GroupChatListScreenState();
}

class _GroupChatListScreenState extends State<GroupChatListScreen> {
  final Map<String, List<AICharacter>> _membersByGroup = {};
  final Map<String, String> _lastSpeakerNames = {};

  @override
  void initState() {
    super.initState();
    // 修复：首次进入不加载 → 一直转圈，必须点加号返回才有数据
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context
          .read<GroupChatBloc>()
          .add(const GroupChatLoadSessions('local_user'));
      _loadMemberData();
    });
  }

  Future<void> _loadMemberData() async {
    final repo = RepositoryProvider.of<LocalStorageRepository>(context);
    final all = await repo.getAllAICharacters();
    if (!mounted) return;
    final byId = {for (final c in all) c.id: c};
    final bloc = context.read<GroupChatBloc>();
    final sessions = bloc.state is GroupChatSessionsLoaded
        ? (bloc.state as GroupChatSessionsLoaded).sessions
        : <GroupChatSession>[];
    final membersByGroup = <String, List<AICharacter>>{};
    final lastSpeakerNames = <String, String>{};
    for (final s in sessions) {
      membersByGroup[s.id] = s.aiCharacterIds
          .map((id) => byId[id])
          .whereType<AICharacter>()
          .toList();
      final latest =
          await repo.getGroupChatMessages(s.id, limit: 1, chatId: s.chatId);
      if (latest.isNotEmpty) {
        final m = latest.first;
        lastSpeakerNames[s.id] = m.isUser ? '我' : m.senderName;
      }
    }
    if (!mounted) return;
    setState(() {
      _membersByGroup.clear();
      _membersByGroup.addAll(membersByGroup);
      _lastSpeakerNames.clear();
      _lastSpeakerNames.addAll(lastSpeakerNames);
    });
  }

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
            icon: Icon(Icons.add_circle_outline,
                size: 24, color: colorScheme.onSurface),
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
              ? state.sessions.where((s) => !s.isHidden).toList()
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

    // 会话列表变化时刷新成员数据（简单去抖）
    if (_membersByGroup.length != sessions.length) {
      _loadMemberData();
    }

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
        return _GroupChatTile(
          session: session,
          members: _membersByGroup[session.id] ?? const <AICharacter>[],
          lastSpeakerName: _lastSpeakerNames[session.id],
        );
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
            Icon(Icons.error_outline,
                size: 48, color: colorScheme.error.withOpacity(0.6)),
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
      context
          .read<GroupChatBloc>()
          .add(const GroupChatLoadSessions('local_user'));
    }
  }
}

/// 群聊列表项
class _GroupChatTile extends StatelessWidget {
  final GroupChatSession session;
  final List<AICharacter> members;
  final String? lastSpeakerName;
  const _GroupChatTile({
    required this.session,
    required this.members,
    this.lastSpeakerName,
  });

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
            // 修复：此前传空字符串导致未读清零永不生效
            context.read<GroupChatBloc>().add(GroupChatMarkRead(session.id));
            context
                .read<GroupChatBloc>()
                .add(const GroupChatLoadSessions('local_user'));
          }
        });
      },
      onLongPress: () => _showContextMenu(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 头像（自定义群头像优先，否则成员拼接）
            _memberStack(session.avatarUrl, members, colorScheme),
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
                      if (session.notice?.isNotEmpty == true) ...[
                        const SizedBox(width: 4),
                        Icon(Icons.campaign_outlined,
                            size: 14,
                            color: colorScheme.primary.withOpacity(0.6)),
                      ],
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
                    session.lastMessage == null || session.lastMessage!.isEmpty
                        ? (session.notice?.isNotEmpty == true
                            ? '公告：${session.notice}'
                            : '暂无消息')
                        : '${lastSpeakerName ?? ''}: ${session.lastMessage}',
                    style: TextStyle(
                      fontSize: 14,
                      color: session.lastMessage != null &&
                              session.lastMessage!.isNotEmpty
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
                  session.unreadCount > 99
                      ? '99+'
                      : session.unreadCount.toString(),
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

  /// 长按菜单：重命名 / 删除
  void _showContextMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: Theme.of(ctx).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16, top: 8),
                decoration: BoxDecoration(
                  color: Theme.of(ctx)
                      .colorScheme
                      .onSurfaceVariant
                      .withOpacity(0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.drive_file_rename_outline),
                title: const Text('重命名群聊'),
                onTap: () {
                  Navigator.pop(ctx);
                  _showRenameDialog(context);
                },
              ),
              ListTile(
                leading:
                    const Icon(Icons.delete_outline, color: Color(0xFFE53935)),
                title: const Text('删除群聊',
                    style: TextStyle(color: Color(0xFFE53935))),
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmDelete(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showRenameDialog(BuildContext context) {
    final controller = TextEditingController(text: session.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名群聊'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 20,
          decoration: const InputDecoration(hintText: '输入新群名'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isEmpty) return;
              context.read<GroupChatBloc>().add(GroupChatUpdateSession(
                    groupId: session.id,
                    name: name,
                  ));
              Navigator.pop(ctx);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    ).then((_) => controller.dispose());
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除群聊'),
        content: Text('确定要从消息页隐藏群聊"${session.name}"吗？群聊和历史内容会保留，可在联系人中继续查看。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.read<GroupChatBloc>().add(GroupChatUpdateSession(
                    groupId: session.id,
                    isHidden: true,
                  ));
            },
            style:
                TextButton.styleFrom(foregroundColor: const Color(0xFFE53935)),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  Widget _memberStack(
      String? avatarUrl, List<AICharacter> members, ColorScheme cs) {
    // 自定义群头像优先；无则回退成员拼接
    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      return Container(
        width: 48,
        height: 48,
        clipBehavior: Clip.antiAlias,
        decoration: const BoxDecoration(shape: BoxShape.circle),
        child: AvatarResolver.imageWidget(
              avatarUrl,
              width: 48,
              height: 48,
              fit: BoxFit.cover,
              onError: () => _groupAvatarFallback(cs),
            ) ??
            _groupAvatarFallback(cs),
      );
    }
    final shown = members.take(3).toList();
    if (shown.isEmpty) {
      return Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: cs.tertiaryContainer,
        ),
        child: Center(
          child: Text('群',
              style: TextStyle(
                  color: cs.tertiary,
                  fontSize: 18,
                  fontWeight: FontWeight.w600)),
        ),
      );
    }
    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              left: i * 13,
              top: i * 8,
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: cs.surfaceContainerHighest,
                  border: Border.all(color: cs.surface, width: 2),
                ),
                child: ClipOval(
                  child: _miniAvatar(shown[i], cs),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _groupAvatarFallback(ColorScheme cs) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: cs.tertiaryContainer,
      ),
      child: Center(
        child: Text('群',
            style: TextStyle(
                color: cs.tertiary, fontSize: 18, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _miniAvatar(AICharacter c, ColorScheme cs) {
    final color = characterColor(colorHex: c.colorHex, name: c.name, cs: cs);
    final img = AvatarResolver.imageWidget(
      c.avatarUrl,
      fit: BoxFit.cover,
      onError: () => _miniAvatarText(c, color),
    );
    if (img != null) return img;
    return _miniAvatarText(c, color);
  }

  Widget _miniAvatarText(AICharacter c, Color color) {
    return Center(
      child: Text(
        c.name.isNotEmpty ? c.name.substring(0, 1) : '?',
        style:
            TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
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
