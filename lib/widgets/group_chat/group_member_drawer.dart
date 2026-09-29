import 'package:flutter/material.dart';
import '../../models/ai_character.dart';
import '../../models/group_chat_session.dart';
import '../../utils/character_color.dart';

/// 侧滑成员面板（对标 ST 右侧成员栏）：
/// 点名字 = 手动激活切换；禁言开关；移出群聊
class GroupMemberDrawer extends StatelessWidget {
  final GroupChatSession session;
  final List<AICharacter> members;
  final List<String> forcedSpeakerIds;
  final ValueChanged<String> onToggleMute;
  final ValueChanged<String> onRemove;
  final ValueChanged<List<String>> onSpeakersChanged;

  const GroupMemberDrawer({
    super.key,
    required this.session,
    required this.members,
    required this.forcedSpeakerIds,
    required this.onToggleMute,
    required this.onRemove,
    required this.onSpeakersChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final disabled = session.disabledMemberIds.toSet();
    return Drawer(
      backgroundColor: cs.surface,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text(
                '群成员',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: cs.onSurface,
                ),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: CircleAvatar(
                backgroundColor: cs.primaryContainer,
                child: Icon(Icons.person, size: 18, color: cs.primary),
              ),
              title: Text('我', style: TextStyle(color: cs.onSurface)),
              subtitle: const Text('用户'),
            ),
            ...members.map((c) {
              final color = characterColor(
                  colorHex: c.colorHex, name: c.name, cs: cs);
              final muted = disabled.contains(c.id);
              final forced = forcedSpeakerIds.contains(c.id);
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: color.withValues(alpha: 0.15),
                  child: Text(
                    c.name.isNotEmpty ? c.name.substring(0, 1) : '?',
                    style: TextStyle(
                      color: color,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                title: Text(
                  c.name,
                  style: TextStyle(
                    color: forced ? color : cs.onSurface,
                    fontWeight: forced ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                subtitle: (muted || forced)
                    ? Text(
                        muted ? '已禁言' : '锁定发言',
                        style: TextStyle(
                          fontSize: 11,
                          color: muted ? cs.error : color,
                        ),
                      )
                    : null,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(
                        muted ? Icons.volume_off : Icons.volume_up,
                        size: 18,
                        color: muted ? cs.error : cs.onSurfaceVariant,
                      ),
                      tooltip: muted ? '取消禁言' : '禁言',
                      onPressed: () => onToggleMute(c.id),
                    ),
                    IconButton(
                      icon: const Icon(Icons.exit_to_app,
                          size: 18, color: Color(0xFFE53935)),
                      tooltip: '移出群聊',
                      onPressed: () => onRemove(c.id),
                    ),
                  ],
                ),
                onTap: () {
                  final next = List<String>.from(forcedSpeakerIds);
                  next.contains(c.id) ? next.remove(c.id) : next.add(c.id);
                  onSpeakersChanged(next);
                },
              );
            }),
          ],
        ),
      ),
    );
  }
}
