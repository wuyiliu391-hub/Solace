// 顶层组件拆分（同库 part）
part of '../chat_detail_screen.dart';

class _SideStoryListSheet extends StatelessWidget {
  final List<ChatSession> sessions;
  final void Function(ChatSession) onOpen;
  final void Function(ChatSession) onDelete;

  const _SideStoryListSheet({
    required this.sessions,
    required this.onOpen,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isDark ? const Color(0xFFE6C88A) : const Color(0xFF8A6D3B);
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: colorScheme.onSurfaceVariant.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Icon(Icons.auto_awesome, size: 18, color: accent),
                const SizedBox(width: 8),
                Text(
                  '番外小剧场',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '剧情不纳入主线',
                  style: TextStyle(
                    fontSize: 11,
                    color: accent,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '番外是平行小剧场，退出后主线记忆、进度与过往对话 100% 保留。',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            if (sessions.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    '还没有番外小剧场记录',
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 360),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: sessions.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final s = sessions[index];
                    final title = s.sideStoryTitle ?? '未命名番外';
                    final preview = s.lastMessage ?? '';
                    final time = s.lastMessageTime ?? s.updatedAt;
                    return Material(
                      color:
                          colorScheme.surfaceContainerHighest.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => onOpen(s),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: colorScheme.onSurface,
                                      ),
                                    ),
                                    if (preview.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        preview,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                time == null
                                    ? ''
                                    : DateFormat('MM-dd HH:mm').format(time),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                              IconButton(
                                tooltip: '删除',
                                icon: Icon(
                                  Icons.delete_outline,
                                  size: 20,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                                onPressed: () => onDelete(s),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
