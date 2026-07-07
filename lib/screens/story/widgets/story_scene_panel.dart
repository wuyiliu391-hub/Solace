import 'package:flutter/material.dart';
import '../../../models/story_scene.dart';

/// 悬浮实时参数面板 — 收起时是一枚药丸，展开显示全部状态
class StoryScenePanel extends StatelessWidget {
  final StoryScene scene;
  final bool expanded;
  final VoidCallback onToggle;

  const StoryScenePanel({
    super.key,
    required this.scene,
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        width: expanded ? 230 : 96,
        decoration: BoxDecoration(
          color: cs.surface.withOpacity(0.92),
          borderRadius: BorderRadius.circular(expanded ? 16 : 20),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.18),
                blurRadius: 12,
                offset: const Offset(0, 4)),
          ],
          border: Border.all(color: cs.outlineVariant.withOpacity(0.4)),
        ),
        child: expanded ? _buildExpanded(context, cs) : _buildPill(context, cs),
      ),
    );
  }

  Widget _buildPill(BuildContext context, ColorScheme cs) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.favorite, size: 15, color: cs.primary),
            const SizedBox(width: 4),
            Text('${scene.affinity}',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface)),
            const SizedBox(width: 6),
            Icon(Icons.expand_more, size: 16, color: cs.onSurface.withOpacity(0.5)),
          ],
        ),
      ),
    );
  }

  Widget _buildExpanded(BuildContext context, ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 10, 6),
            child: Row(
              children: [
                Text('状态面板',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: cs.onSurface)),
                const Spacer(),
                Icon(Icons.expand_less, size: 18, color: cs.onSurface.withOpacity(0.5)),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _bar(cs, '好感度', scene.affinity, cs.primary),
              const SizedBox(height: 8),
              _bar(cs, '情绪 · ${scene.emotionLabel}', scene.emotionValue,
                  cs.tertiary),
              const SizedBox(height: 10),
              _kv(cs, '身体', scene.bodyState),
              _kv(cs, '心理', scene.psychState),
              _kv(cs, '行动', scene.actionState),
              _kv(cs, '地点', scene.location),
              _kv(cs, '氛围', scene.atmosphere),
              if (scene.presentCharacters.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('在场人物',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface.withOpacity(0.5))),
                const SizedBox(height: 4),
                ...scene.presentCharacters.map((p) => Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(
                        '· ${p.name} ♥${p.affinity} ${p.emotion} ${p.state}',
                        style: TextStyle(
                            fontSize: 11.5,
                            color: cs.onSurface.withOpacity(0.75)),
                      ),
                    )),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _bar(ColorScheme cs, String label, int value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 11.5, color: cs.onSurface.withOpacity(0.7))),
            ),
            Text('$value',
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface)),
          ],
        ),
        const SizedBox(height: 3),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: (value.clamp(0, 100)) / 100.0,
            minHeight: 5,
            backgroundColor: cs.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ],
    );
  }

  Widget _kv(ColorScheme cs, String k, String v) {
    if (v.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: RichText(
        text: TextSpan(
          style: TextStyle(fontSize: 11.5, color: cs.onSurface.withOpacity(0.8)),
          children: [
            TextSpan(
                text: '$k ',
                style: TextStyle(color: cs.onSurface.withOpacity(0.45))),
            TextSpan(text: v),
          ],
        ),
      ),
    );
  }
}
