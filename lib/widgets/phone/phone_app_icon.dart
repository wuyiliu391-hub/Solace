import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../config/phone_app_icons.dart';
import '../../config/phone_theme.dart';
import 'phone_icon_glyphs.dart';

/// 代码绘制的「软玻璃 / 粘土」应用图标。
///
/// 主路径：多层渐变面 + 自绘 glyph（非粗 Material）。
/// 可选：preferAsset 时尝试加载 generated 贴图。
class PhoneAppIcon extends StatefulWidget {
  final PhoneAppIconDef def;
  final VoidCallback? onTap;
  final double size;
  final int badge;
  final bool showLabel;
  final bool isNew;
  final bool preferAsset;

  const PhoneAppIcon({
    super.key,
    required this.def,
    this.onTap,
    this.size = PhoneTheme.homeIconSize,
    this.badge = 0,
    this.showLabel = true,
    this.isNew = false,
    this.preferAsset = false,
  });

  factory PhoneAppIcon.fromId(
    String id, {
    Key? key,
    VoidCallback? onTap,
    double size = PhoneTheme.homeIconSize,
    int badge = 0,
    bool showLabel = true,
    bool isNew = false,
    bool preferAsset = false,
  }) {
    final def = PhoneAppIconCatalog.byId(id) ??
        PhoneAppIconDef(
          id: id,
          label: id,
          subject: id,
          fallbackIcon: Icons.apps_rounded,
          fallbackColor: const Color(0xFF8E8E93),
        );
    return PhoneAppIcon(
      key: key,
      def: def,
      onTap: onTap,
      size: size,
      badge: badge,
      showLabel: showLabel,
      isNew: isNew,
      preferAsset: preferAsset,
    );
  }

  @override
  State<PhoneAppIcon> createState() => _PhoneAppIconState();
}

class _PhoneAppIconState extends State<PhoneAppIcon> {
  bool _pressed = false;
  String? _assetPath;

  @override
  void initState() {
    super.initState();
    if (widget.preferAsset) _tryLoadAsset();
  }

  Future<void> _tryLoadAsset() async {
    for (final path in [widget.def.assetWebp, widget.def.assetPng]) {
      try {
        await rootBundle.load(path);
        if (mounted) setState(() => _assetPath = path);
        return;
      } catch (_) {}
    }
  }

  void _setPressed(bool v) {
    if (_pressed == v) return;
    setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final radius = size * PhoneTheme.iconRadiusRatio;
    final scale = _pressed ? 0.90 : 1.0;

    return GestureDetector(
      onTapDown: widget.onTap == null ? null : (_) => _setPressed(true),
      onTapUp: widget.onTap == null
          ? null
          : (_) {
              _setPressed(false);
              HapticFeedback.selectionClick();
              widget.onTap?.call();
            },
      onTapCancel: widget.onTap == null ? null : () => _setPressed(false),
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedScale(
            scale: scale,
            duration: const Duration(milliseconds: 110),
            curve: Curves.easeOutCubic,
            child: SizedBox(
              width: size,
              height: size,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(radius),
                      boxShadow: PhoneTheme.iconDropShadow(widget.def.fallbackColor),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(radius),
                      child: _assetPath != null
                          ? Image.asset(
                              _assetPath!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  _SoftGlassFace(def: widget.def, size: size),
                            )
                          : _SoftGlassFace(def: widget.def, size: size),
                    ),
                  ),
                  // 底部内侧反光
                  Positioned(
                    left: size * 0.12,
                    right: size * 0.12,
                    bottom: size * 0.08,
                    child: IgnorePointer(
                      child: Container(
                        height: size * 0.08,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(size),
                          gradient: LinearGradient(
                            colors: [
                              Colors.white.withValues(alpha: 0.0),
                              Colors.white.withValues(alpha: 0.18),
                              Colors.white.withValues(alpha: 0.0),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (widget.badge > 0)
                    Positioned(
                      top: -4,
                      right: -4,
                      child: _Badge(count: widget.badge),
                    ),
                  if (widget.isNew)
                    Positioned(
                      top: -4,
                      right: -4,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            colors: [Color(0xFF00E0C6), Color(0xFF0FB8AD)],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF00E0C6).withValues(alpha: 0.55),
                              blurRadius: 5,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (widget.showLabel) ...[
            const SizedBox(height: 7),
            SizedBox(
              width: size + 20,
              child: Text(
                widget.def.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: PhoneTheme.iconLabelSize,
                  height: 1.1,
                  fontWeight: FontWeight.w500,
                  color: PhoneTheme.textOnWallpaper,
                  shadows: PhoneTheme.labelShadows,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 多层渐变 + 高光 + 自绘 glyph
class _SoftGlassFace extends StatelessWidget {
  final PhoneAppIconDef def;
  final double size;
  const _SoftGlassFace({required this.def, required this.size});

  @override
  Widget build(BuildContext context) {
    final c = def.fallbackColor;
    final light = Color.lerp(c, Colors.white, 0.48)!;
    final mid = Color.lerp(c, Colors.white, 0.08)!;
    final deep = Color.lerp(c, const Color(0xFF1A1A2E), 0.28)!;
    final radius = size * PhoneTheme.iconRadiusRatio;

    return Stack(
      fit: StackFit.expand,
      children: [
        // 主渐变体
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [light, mid, deep],
              stops: const [0.0, 0.45, 1.0],
            ),
          ),
        ),
        // 右下深色晕（厚度）
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0.75, 0.8),
              radius: 0.95,
              colors: [
                deep.withValues(alpha: 0.42),
                Colors.transparent,
              ],
            ),
          ),
        ),
        // 左上冷高光 → Solace 内荧光
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(-0.65, -0.7),
              radius: 0.7,
              colors: [
                c.withValues(alpha: 0.55),
                Colors.white.withValues(alpha: 0.18),
                Colors.transparent,
              ],
            ),
          ),
        ),
        // 顶部镜面带（更柔和）
        Align(
          alignment: Alignment.topCenter,
          child: FractionallySizedBox(
            heightFactor: 0.46,
            widthFactor: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withValues(alpha: 0.38),
                    Colors.white.withValues(alpha: 0.06),
                    Colors.white.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
        ),
        // 椭圆形高光块（偏品牌色）
        Positioned(
          left: size * 0.14,
          top: size * 0.11,
          child: Container(
            width: size * 0.34,
            height: size * 0.14,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(size),
              gradient: LinearGradient(
                colors: [
                  c.withValues(alpha: 0.58),
                  Colors.white.withValues(alpha: 0.12),
                ],
              ),
            ),
          ),
        ),
        // 内描边（Solace 荧光边）
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.32),
              width: 1.15,
            ),
          ),
        ),
        // 外缘淡环
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: deep.withValues(alpha: 0.18),
              width: 0.6,
            ),
          ),
        ),
        // 符号：A 档立体图标略放大，层次更清晰
        Center(
          child: PhoneGlyph(
            id: def.id,
            size: size * (_isPremium(def.id) ? 0.56 : 0.50),
            color: Colors.white.withValues(alpha: 0.97),
          ),
        ),
      ],
    );
  }

  static bool _isPremium(String id) => const {
        'phone',
        'chat',
        'contacts',
        'settings',
        'wallet',
        'shop',
        'diary',
        'memory',
        'moments',
        'notes',
        'power',
        'oracle',
        'tarot',
        'music',
        'story',
        'destiny',
        'mailbox',
        'calendar',
        'inspiration',
        'coins',
        'love_lab',
        'love_sign',
        'reading',
        'guide',
        'store',
        'forum',
      }.contains(id);
}

class _Badge extends StatelessWidget {
  final int count;
  const _Badge({required this.count});

  @override
  Widget build(BuildContext context) {
    final text = count > 99 ? '99+' : '$count';
    return Container(
      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
      padding: const EdgeInsets.symmetric(horizontal: 5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFF5A5F), Color(0xFFFF2D55)],
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white, width: 1.6),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF2D55).withValues(alpha: 0.4),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
