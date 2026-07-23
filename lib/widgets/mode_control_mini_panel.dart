import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../repositories/local_storage_repository.dart';

/// novelMode 对白颜色预设（亮色主题；暗色在 hue 不变基础上提亮）
const _kPresetColors = [
  Color(0xFF2B7BF5), // 默认蓝
  Color(0xFF7B61FF), // 紫
  Color(0xFFE91E8C), // 粉
  Color(0xFF4CAF50), // 绿
  Color(0xFFFF9800), // 橙
  Color(0xFF00BCD4), // 青
  Color(0xFFF44336), // 红
  Color(0xFFFFAB00), // 金
];

/// 音量键控制的迷你模式面板，外部通过 ValueNotifier<bool> 控制显隐
class ModeControlMiniPanel extends StatelessWidget {
  final ValueNotifier<bool> visible;

  /// 当前会话小说模式是否开启（从 session.novelMode 读取）
  final bool novelModeEnabled;

  /// 切换当前会话小说模式的回调
  final VoidCallback? onNovelModeToggle;

  const ModeControlMiniPanel({
    super.key,
    required this.visible,
    this.novelModeEnabled = false,
    this.onNovelModeToggle,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: visible,
      builder: (context, show, _) {
        if (!show) return const SizedBox.shrink();
        return _buildPanel(context);
      },
    );
  }

  Widget _buildPanel(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = cs.brightness == Brightness.dark;
    final s = RepositoryProvider.of<LocalStorageRepository>(context);
    return Positioned.fill(
      child: Align(
        alignment: Alignment.bottomRight,
        child: Padding(
          padding: const EdgeInsets.only(right: 12, bottom: 90),
          child: Material(
            elevation: 12,
            borderRadius: BorderRadius.circular(14),
            color: Colors.transparent,
            child: Container(
              width: 230,
              decoration: BoxDecoration(
                color: dark
                    ? const Color(0xFF1E1E1E).withOpacity(0.97)
                    : Colors.white.withOpacity(0.98),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: cs.outlineVariant.withOpacity(dark ? 0.35 : 0.6),
                    width: 0.5),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(dark ? 0.4 : 0.15),
                      blurRadius: 18,
                      offset: const Offset(0, 4))
                ],
              ),
              child: ValueListenableBuilder<int>(
                valueListenable: s.modeSettingsNotifier,
                builder: (ctx, _, __) {
                  final age = s.getUserAge();
                  final adult = age != null && age >= 18;
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(children: [
                          Icon(Icons.tune_rounded, size: 15, color: cs.primary),
                          const SizedBox(width: 5),
                          Expanded(
                              child: Text('模式控制',
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: cs.onSurface))),
                          InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () => visible.value = false,
                              child: Padding(
                                  padding: const EdgeInsets.all(4),
                                  child: Icon(Icons.close_rounded,
                                      size: 16,
                                      color: cs.onSurface.withOpacity(0.4)))),
                        ]),
                        const SizedBox(height: 4),
                        ..._grid(ctx, s, cs, adult),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _grid(
      BuildContext ctx, LocalStorageRepository s, ColorScheme cs, bool ad) {
    final ds = <_D>[
      _D(
          Icons.smart_toy_outlined,
          Colors.deepPurple,
          '纯AI视角',
          s.isPureAiModeEnabled(),
          (v) => _setMode(ctx, '纯AI视角', v, () => s.setPureAiMode(v),
              enabledTip: '下一条回复将切换为中立AI助手风格，不再沿用角色人设')),
      _D(
          Icons.auto_stories_outlined,
          Colors.teal,
          '小说模式',
          novelModeEnabled,
          onNovelModeToggle != null
              ? (v) async {
                  // 会话级开关，由外部处理切换
                  onNovelModeToggle!();
                  if (!ctx.mounted) return;
                  final msg = v ? '小说模式已开启（仅本会话）' : '小说模式已关闭（仅本会话）';
                  ScaffoldMessenger.of(ctx)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(
                      SnackBar(
                        content: Text(msg),
                        duration: const Duration(seconds: 2),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                }
              : null),
      _D(
          Icons.favorite_border,
          Colors.pink,
          '恋人模式',
          s.isLoverModeEnabled(),
          ad ? (v) => _setMode(ctx, '恋人模式', v, () => s.setLoverMode(v)) : null,
          !ad),
      _D(
          Icons.lock_open_outlined,
          Colors.purple,
          '开放模式',
          s.isOpenModeEnabled(),
          ad ? (v) => _setMode(ctx, '开放模式', v, () => s.setOpenMode(v)) : null,
          !ad),
      _D(
          Icons.auto_awesome,
          Colors.deepOrange,
          '法功能',
          s.isFaModeEnabled(),
          ad
              ? (v) => _setMode(ctx, '法功能', v, () async {
                    await s.setFaMode(v);
                    await s.setFaVerified(v);
                  })
              : null,
          !ad),
      _D(
          Icons.local_florist_outlined,
          Colors.blueGrey,
          '刀模式',
          s.isDaoModeEnabled(),
          (v) => _setMode(ctx, '刀模式', v, () => s.setDaoMode(v))),
      _D(
          Icons.book_rounded,
          Colors.orange,
          '自动写日记',
          s.isAutoDiaryEnabled(),
          (v) => s.setAutoDiaryEnabled(v)),
    ];

    final widgets = <Widget>[];
    for (final d in ds) {
      widgets.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: _sw(cs, d)));
      // 小说模式开启时，在其下方显示对白颜色选择行
      if (d.t == '小说模式' && d.v) {
        widgets.add(_novelColorRow(ctx, s, cs));
      }
    }
    return widgets;
  }

  Widget _novelColorRow(
      BuildContext ctx, LocalStorageRepository s, ColorScheme cs) {
    final current = s.getNovelDialogueColor();
    return Padding(
      padding: const EdgeInsets.only(left: 8, right: 4, bottom: 2, top: 1),
      child: Row(
        children: [
          Icon(Icons.palette_outlined, size: 13, color: cs.onSurface.withOpacity(0.45)),
          const SizedBox(width: 6),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  // 预设颜色圆点
                  for (final color in _kPresetColors)
                    _colorDot(ctx, s, cs, color, current == color),
                  const SizedBox(width: 4),
                  // 恢复默认
                  Tooltip(
                    message: '恢复默认',
                    child: GestureDetector(
                      onTap: () async {
                        await s.setNovelDialogueColor(null);
                      },
                      child: Container(
                        width: 18,
                        height: 18,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: cs.outlineVariant.withOpacity(0.6),
                              width: 1),
                          color: cs.surfaceContainerHighest,
                        ),
                        child: Icon(Icons.refresh_rounded,
                            size: 11, color: cs.onSurface.withOpacity(0.5)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _colorDot(BuildContext ctx, LocalStorageRepository s, ColorScheme cs,
      Color color, bool selected) {
    return Tooltip(
      message: '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
      child: GestureDetector(
        onTap: () async {
          await s.setNovelDialogueColor(color);
        },
        child: Container(
          width: 18,
          height: 18,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            border: selected
                ? Border.all(color: cs.onSurface, width: 2)
                : Border.all(color: Colors.transparent, width: 2),
            boxShadow: selected
                ? [BoxShadow(color: color.withOpacity(0.5), blurRadius: 4)]
                : null,
          ),
        ),
      ),
    );
  }

  Future<void> _setMode(
    BuildContext context,
    String name,
    bool enabled,
    Future<void> Function() save, {
    String? enabledTip,
  }) async {
    await save();
    if (!context.mounted) return;

    final message = enabled
        ? '$name已开启${enabledTip != null ? '，$enabledTip' : ''}'
        : '$name已关闭';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Widget _sw(ColorScheme cs, _D d) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: d.lk
          ? null
          : () {
              if (d.oc != null) d.oc!(!d.v);
            },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: d.v ? cs.primary.withOpacity(0.08) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: d.v
                  ? cs.primary.withOpacity(0.25)
                  : cs.outlineVariant.withOpacity(0.3),
              width: 0.5),
        ),
        child: Row(children: [
          Icon(d.ic, size: 15, color: d.c),
          const SizedBox(width: 8),
          Expanded(
              child: d.lk
                  ? const Icon(Icons.lock, size: 12)
                  : Text(d.t,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: d.lk
                          ? cs.onSurface.withOpacity(0.35)
                          : cs.onSurface.withOpacity(0.8)))),
          if (!d.lk)
            SizedBox(
                width: 40,
                height: 24,
                child: FittedBox(
                    fit: BoxFit.fill,
                    child: Switch(
                        value: d.v,
                        onChanged: d.oc,
                        activeColor: cs.primary,
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap))),
        ]),
      ),
    );
  }
}

class _D {
  final IconData ic;
  final Color c;
  final String t;
  final bool v;
  final ValueChanged<bool>? oc;
  final bool lk;
  const _D(this.ic, this.c, this.t, this.v, [this.oc, this.lk = false]);
}
