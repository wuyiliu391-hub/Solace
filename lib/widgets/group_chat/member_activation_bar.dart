import 'package:flutter/material.dart';
import '../../models/ai_character.dart';
import '../../utils/avatar_resolver.dart';
import '../../utils/character_color.dart';

/// 输入框上方成员激活条（对标 ST 手动激活）：
/// 单击 = 锁定该角色发言；再次点击 = 解锁；长按 = 多选模式
class MemberActivationBar extends StatefulWidget {
  final List<AICharacter> members;
  final Set<String> disabledIds;
  final List<String> forcedSpeakerIds;
  final ValueChanged<List<String>> onSpeakersChanged;

  const MemberActivationBar({
    super.key,
    required this.members,
    required this.disabledIds,
    required this.forcedSpeakerIds,
    required this.onSpeakersChanged,
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
    final cs = Theme.of(context).colorScheme;
    if (widget.members.isEmpty) return const SizedBox.shrink();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_multiSelect)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
            child: Row(
              children: [
                Text(
                  '已锁定 ${widget.forcedSpeakerIds.length} 人',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(() => _multiSelect = false),
                  child: const Text('完成', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
        SizedBox(
          height: 64,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            // 视口 = 64 - 2*4 = 56px ≥ 条目高度(38+2+名字行高≈53)，避免底部 1px 溢出
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: disabled
                            ? cs.surfaceContainerHighest
                            : color.withValues(alpha: 0.16),
                        border: Border.all(
                          color: forced ? color : cs.outlineVariant,
                          width: forced ? 2.5 : 1,
                        ),
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
                                child: const Icon(
                                    Icons.record_voice_over,
                                    size: 9,
                                    color: Colors.white),
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
                          fontWeight: forced
                              ? FontWeight.bold
                              : FontWeight.normal,
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
