import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../config/phone_app_icons.dart';
import '../../config/phone_theme.dart';
import 'phone_icon_glyphs.dart';

/// 发光宝石质感应用图标。
///
/// 核心设计：每个图标是一颗「发光的宝石」——
/// 内发光 + 表面高光 + 环境反射 + 底部光晕，四合一融合成立体物体。
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

class _PhoneAppIconState extends State<PhoneAppIcon>
    with SingleTickerProviderStateMixin {
  bool _pressed = false;
  String? _assetPath;
  late final AnimationController _glowCtrl;

  @override
  void initState() {
    super.initState();
    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);
    if (widget.preferAsset) _tryLoadAsset();
  }

  @override
  void dispose() {
    _glowCtrl.dispose();
    super.dispose();
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
    final scale = _pressed ? 0.88 : 1.0;

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
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOutCubic,
            child: SizedBox(
              width: size,
              height: size,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // 底部光晕：图标「坐」在光上
                  Positioned(
                    left: size * 0.08,
                    right: size * 0.08,
                    bottom: -size * 0.06,
                    height: size * 0.28,
                    child: AnimatedBuilder(
                      animation: _glowCtrl,
                      builder: (context, child) {
                        final glowAlpha =
                            0.25 + _glowCtrl.value * 0.15;
                        return Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(size),
                            gradient: RadialGradient(
                              colors: [
                                widget.def.fallbackColor
                                    .withValues(alpha: glowAlpha),
                                widget.def.fallbackColor
                                    .withValues(alpha: 0),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  // 宝石主体
                  Container(
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(radius),
                      boxShadow: [
                        // 外阴影：深度
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.22),
                          blurRadius: 18,
                          offset: const Offset(0, 10),
                        ),
                        // 彩色光晕：材质感
                        BoxShadow(
                          color: widget.def.fallbackColor
                              .withValues(alpha: 0.35),
                          blurRadius: 20,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(radius),
                      child: _assetPath != null
                          ? Image.asset(
                              _assetPath!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  _GemFace(def: widget.def, size: size),
                            )
                          : _GemFace(def: widget.def, size: size),
                    ),
                  ),
                  // 顶部边缘光：锐利高光
                  Positioned(
                    left: size * 0.06,
                    right: size * 0.06,
                    top: 0,
                    child: IgnorePointer(
                      child: Container(
                        height: size * 0.06,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(size),
                          gradient: LinearGradient(
                            colors: [
                              Colors.white.withValues(alpha: 0.0),
                              Colors.white.withValues(alpha: 0.75),
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
                      child: _NewDot(),
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

/// 发光宝石表面：内发光 + 多层光学反射
class _GemFace extends StatelessWidget {
  final PhoneAppIconDef def;
  final double size;
  const _GemFace({required this.def, required this.size});

  @override
  Widget build(BuildContext context) {
    final c = def.fallbackColor;
    final radius = size * PhoneTheme.iconRadiusRatio;

    // 宝石的明暗关系：
    // - 顶部：光源直射，最亮
    // - 中部：固有色 + 内发光
    // - 底部：环境反光 + 阴影
    final light = Color.lerp(c, Colors.white, 0.55)!;
    final mid = Color.lerp(c, Colors.white, 0.12)!;
    final deep = Color.lerp(c, const Color(0xFF0A0A1A), 0.35)!;
    final glow = Color.lerp(c, Colors.white, 0.3)!;

    return Stack(
      fit: StackFit.expand,
      children: [
        // 基础渐变体
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [light, mid, deep],
              stops: const [0.0, 0.42, 1.0],
            ),
          ),
        ),
        // 内发光层：从中心向外扩散
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(-0.2, -0.3),
              radius: 0.85,
              colors: [
                glow.withValues(alpha: 0.5),
                glow.withValues(alpha: 0.0),
              ],
            ),
          ),
        ),
        // 右下深色晕（厚度）
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0.8, 0.85),
              radius: 0.9,
              colors: [
                deep.withValues(alpha: 0.5),
                Colors.transparent,
              ],
            ),
          ),
        ),
        // 左上冷高光（锐利）
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(-0.7, -0.75),
              radius: 0.55,
              colors: [
                Colors.white.withValues(alpha: 0.55),
                Colors.transparent,
              ],
            ),
          ),
        ),
        // 顶部镜面带（更锐利）
        Align(
          alignment: Alignment.topCenter,
          child: FractionallySizedBox(
            heightFactor: 0.38,
            widthFactor: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withValues(alpha: 0.65),
                    Colors.white.withValues(alpha: 0.15),
                    Colors.white.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
        ),
        // 椭圆形高光块（更聚焦）
        Positioned(
          left: size * 0.12,
          top: size * 0.09,
          child: Container(
            width: size * 0.28,
            height: size * 0.11,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(size),
              gradient: LinearGradient(
                colors: [
                  Colors.white.withValues(alpha: 0.85),
                  Colors.white.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ),
        // 内描边（边缘光）
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.55),
              width: 1.2,
            ),
          ),
        ),
        // 外缘淡环（深度）
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: deep.withValues(alpha: 0.22),
              width: 0.7,
            ),
          ),
        ),
        // 符号
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

class _NewDot extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [Color(0xFF00E0C6), Color(0xFF0FB8AD)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00E0C6).withValues(alpha: 0.6),
            blurRadius: 6,
            spreadRadius: 1,
          ),
        ],
      ),
    );
  }
}
