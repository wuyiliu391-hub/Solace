import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../repositories/local_storage_repository.dart';

/// 音量键控制的迷你模式面板，外部通过 ValueNotifier<bool> 控制显隐
class ModeControlMiniPanel extends StatelessWidget {
  final ValueNotifier<bool> visible;
  const ModeControlMiniPanel({super.key, required this.visible});

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
          s.isChatStyleNovelModeEnabled(),
          (v) => _setMode(ctx, '小说模式', v, () => s.setChatStyleMode(v))),
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
    ];
    return ds
        .map((d) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: _sw(cs, d)))
        .toList();
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
