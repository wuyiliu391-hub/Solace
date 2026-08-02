import 'package:flutter/material.dart';

/// 消息区顶部悬浮条：左 = 聊天记录名（点击切换），右 = Auto-Reply 开关
class GroupTopBar extends StatelessWidget {
  final String chatName;
  final bool autoModeEnabled;
  final VoidCallback onChatTap;
  final ValueChanged<bool> onAutoModeChanged;

  const GroupTopBar({
    super.key,
    required this.chatName,
    required this.autoModeEnabled,
    required this.onChatTap,
    required this.onAutoModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      child: Material(
        color: cs.surface.withValues(alpha: 0.88),
        elevation: 1,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              InkWell(
                onTap: onChatTap,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: Row(
                    children: [
                      Icon(Icons.history, size: 16, color: cs.onSurfaceVariant),
                      const SizedBox(width: 6),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 140),
                        child: Text(
                          chatName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(Icons.arrow_drop_down,
                          size: 16, color: cs.onSurfaceVariant),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              Text(
                autoModeEnabled ? '自动接话中' : '自动回复',
                style: TextStyle(
                  fontSize: 11,
                  color: autoModeEnabled ? cs.primary : cs.onSurfaceVariant,
                ),
              ),
              Switch(
                value: autoModeEnabled,
                onChanged: onAutoModeChanged,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
