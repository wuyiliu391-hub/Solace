import 'package:flutter/material.dart';

/// 消息区顶部悬浮条：左 = 当前聊天记录，右 = 自动接话状态。
///
/// 组件只负责呈现和回调，不持有群聊业务状态，避免切换分支或自动回复
/// 时改变原有 Bloc 流程。
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final accent = cs.primary;
    final panelColor = isDark
        ? cs.surfaceContainer.withValues(alpha: 0.92)
        : cs.surface.withValues(alpha: 0.94);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : Colors.black.withValues(alpha: 0.07);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Material(
        color: panelColor,
        elevation: 0,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 7, 8, 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: borderColor),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.04),
                blurRadius: 16,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: onChatTap,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                    child: Row(
                      children: [
                        Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.13),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.account_tree_outlined,
                            size: 15,
                            color: accent,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '当前剧本',
                                style: TextStyle(
                                  fontSize: 9,
                                  height: 1.1,
                                  color: cs.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.25,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                chatName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  height: 1.15,
                                  color: cs.onSurface,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 17,
                          color: cs.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.only(left: 9),
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(color: borderColor),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: autoModeEnabled
                            ? accent
                            : cs.onSurfaceVariant.withValues(alpha: 0.45),
                        shape: BoxShape.circle,
                        boxShadow: autoModeEnabled
                            ? [
                                BoxShadow(
                                  color: accent.withValues(alpha: 0.45),
                                  blurRadius: 7,
                                ),
                              ]
                            : null,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      autoModeEnabled ? '自动接话' : '手动回应',
                      style: TextStyle(
                        fontSize: 10,
                        color: autoModeEnabled ? accent : cs.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Switch(
                      value: autoModeEnabled,
                      onChanged: onAutoModeChanged,
                      activeColor: accent,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
