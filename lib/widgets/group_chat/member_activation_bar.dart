import 'package:flutter/material.dart';
import '../../models/ai_character.dart';
import '../../utils/avatar_resolver.dart';
import '../../utils/character_color.dart';
import '../../models/group_chat_session.dart';

/// 输入框上方成员激活条（对标 ST 手动激活）：
/// 单击 = 锁定该角色发言；再次点击 = 解锁；长按 = 多选模式。
///
/// 视觉上作为输入区的一部分呈现，但所有选择行为和回调保持不变。
class MemberActivationBar extends StatefulWidget {
  final List<AICharacter> members;
  final Set<String> disabledIds;
  final List<String> forcedSpeakerIds;
  final ValueChanged<List<String>> onSpeakersChanged;
  final GroupActivationStrategy activationStrategy;

  const MemberActivationBar({
    super.key,
    required this.members,
    required this.disabledIds,
    required this.forcedSpeakerIds,
    required this.onSpeakersChanged,
    this.activationStrategy = GroupActivationStrategy.natural,
  });

  @override
  State<MemberActivationBar> createState() => _MemberActivationBarState();
}

class _MemberActivationBarState extends State<MemberActivationBar> {
  bool _multiSelect = false;

  bool _isForced(String id) => widget.forcedSpeakerIds.contains(id);

  void _onTap(AICharacter c) {
    if (widget.disabledIds.contains(c.id)) return;
    if (_multiSelect) {
      final next = List<String>.from(widget.forcedSpeakerIds);
      next.contains(c.id) ? next.remove(c.id) : next.add(c.id);
      widget.onSpeakersChanged(next);
    } else {
      widget.onSpeakersChanged(_isForced(c.id) ? const [] : [c.id]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    if (widget.members.isEmpty) return const SizedBox.shrink();

    final panelColor = isDark
        ? cs.surfaceContainer.withValues(alpha: 0.72)
        : cs.surface.withValues(alpha: 0.82);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);
    final helper = widget.forcedSpeakerIds.isEmpty
        ? (widget.activationStrategy == GroupActivationStrategy.manual
            ? '手动点名模式 · 请选择本轮发言角色'
            : '点按指定发言 · 长按可多选')
        : '本轮已锁定 ${widget.forcedSpeakerIds.length} 位成员 · 发送后自动清除';

    return Container(
      margin: const EdgeInsets.fromLTRB(10, 6, 10, 0),
      decoration: BoxDecoration(
        color: panelColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 10, 0),
            child: Row(
              children: [
                Icon(
                  widget.forcedSpeakerIds.isEmpty
                      ? Icons.record_voice_over_outlined
                      : Icons.push_pin_rounded,
                  size: 14,
                  color: widget.forcedSpeakerIds.isEmpty
                      ? cs.onSurfaceVariant
                      : cs.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  '本轮发言成员',
                  style: TextStyle(
                    fontSize: 10,
                    color: cs.onSurface,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    helper,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
                if (_multiSelect)
                  TextButton(
                    onPressed: () => setState(() => _multiSelect = false),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 28),
                      padding: const EdgeInsets.symmetric(horizontal: 7),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('完成', style: TextStyle(fontSize: 11)),
                  ),
              ],
            ),
          ),
          SizedBox(
            height: 66,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(10, 7, 10, 5),
              itemCount: widget.members.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final c = widget.members[index];
                final color = characterColor(
                    colorHex: c.colorHex, name: c.name, cs: cs);
                final forced = _isForced(c.id);
                final disabled = widget.disabledIds.contains(c.id);
                return GestureDetector(
                  onTap: () => _onTap(c),
                  onLongPress: () => setState(() => _multiSelect = true),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: disabled
                              ? cs.surfaceContainerHighest
                              : forced
                                  ? color.withValues(alpha: 0.22)
                                  : color.withValues(alpha: 0.10),
                          border: Border.all(
                            color: forced ? color : borderColor,
                            width: forced ? 2.5 : 1,
                          ),
                          boxShadow: forced
                              ? [
                                  BoxShadow(
                                    color: color.withValues(alpha: 0.28),
                                    blurRadius: 9,
                                  ),
                                ]
                              : null,
                        ),
                        child: Stack(
                          children: [
                            Center(child: _avatar(c, color)),
                            if (forced)
                              Positioned(
                                right: 0,
                                bottom: 0,
                                child: Container(
                                  width: 14,
                                  height: 14,
                                  decoration: BoxDecoration(
                                    color: color,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.record_voice_over,
                                      size: 9, color: Colors.white),
                                ),
                              ),
                            if (disabled)
                              Positioned.fill(
                                child: Container(
                                  decoration: const BoxDecoration(
                                    color: Colors.black38,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.block,
                                      size: 14, color: Colors.white),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 2),
                      SizedBox(
                        width: 46,
                        child: Text(
                          c.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 9,
                            color: forced ? color : cs.onSurfaceVariant,
                            fontWeight:
                                forced ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatar(AICharacter c, Color color) {
    final img = AvatarResolver.imageWidget(
      c.avatarUrl,
      width: 32,
      height: 32,
      fit: BoxFit.cover,
      onError: () => _avatarText(c, color),
    );
    if (img != null) return ClipOval(child: img);
    return _avatarText(c, color);
  }

  Widget _avatarText(AICharacter c, Color color) {
    return Text(
      c.name.isNotEmpty ? c.name.substring(0, 1) : '?',
      style: TextStyle(
        color: color,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
