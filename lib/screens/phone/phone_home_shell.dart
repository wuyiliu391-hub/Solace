import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../config/phone_app_icons.dart';
import '../../config/phone_theme.dart';
import '../../models/ai_character.dart';
import '../../repositories/local_storage_repository.dart';
import '../../screens/virtual_phone/virtual_phone_screen.dart';
import '../../widgets/phone/phone_app_icon.dart';
import '../../widgets/phone/phone_glass.dart';

/// Solace 小手机系统主壳（不是角色手机）。
class PhoneHomeShell extends StatefulWidget {
  final void Function(String route) onNavigate;
  final VoidCallback? onExitToClassic;

  const PhoneHomeShell({
    super.key,
    required this.onNavigate,
    this.onExitToClassic,
  });

  @override
  State<PhoneHomeShell> createState() => _PhoneHomeShellState();
}

class _PhoneHomeShellState extends State<PhoneHomeShell>
    with TickerProviderStateMixin {
  List<AICharacter> _characters = const [];
  AICharacter? _worldCharacter;
  Timer? _clockTimer;
  DateTime _now = DateTime.now();
  int _pageIndex = 0;
  PhoneWallpaperTheme _wallpaper = PhoneWallpaperTheme.dawn;
  final _pageController = PageController();

  late final AnimationController _enterCtrl;
  late final AnimationController _breathCtrl;
  late final AnimationController _parallaxCtrl;

  @override
  void initState() {
    super.initState();
    _enterCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
    _breathCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4200),
    )..repeat(reverse: true);
    _parallaxCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    )..repeat(reverse: true);

    _load();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _enterCtrl.dispose();
    _breathCtrl.dispose();
    _parallaxCtrl.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final storage = context.read<LocalStorageRepository>();
    final chars = await storage.getAllAICharacters();
    final visible = chars.where((c) => !c.isHidden).toList();
    final theme = PhoneWallpaperThemeX.fromId(storage.getPhoneWallpaperThemeId());
    if (!mounted) return;
    setState(() {
      _characters = visible;
      _worldCharacter = visible.isNotEmpty ? visible.first : null;
      _wallpaper = theme;
    });
  }

  String get _timeText {
    final h = _now.hour.toString().padLeft(2, '0');
    final m = _now.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String get _statusTime {
    final h = _now.hour.toString().padLeft(2, '0');
    final m = _now.minute.toString().padLeft(2, '0');
    final s = _now.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  Animation<double> _stagger(double begin, double end) {
    return CurvedAnimation(
      parent: _enterCtrl,
      curve: Interval(begin, end, curve: Curves.easeOutCubic),
    );
  }

  int get _sessionBadge {
    // 轻量角标：有角色时给消息一个存在感（真实未读可后续接 ChatBloc）
    return _characters.isEmpty ? 0 : (_characters.length > 9 ? 9 : _characters.length);
  }

  @override
  Widget build(BuildContext context) {
    final palette = SolacePalettes.of(_wallpaper);
    return Scaffold(
      backgroundColor: palette.mid,
      body: AnimatedBuilder(
        animation: Listenable.merge([_breathCtrl, _parallaxCtrl]),
        builder: (context, _) {
          final breath = 0.96 + _breathCtrl.value * 0.04;
          final px = math.sin(_parallaxCtrl.value * math.pi * 2) * 10;
          final py = math.cos(_parallaxCtrl.value * math.pi * 2) * 6;
          return PhoneWallpaper(
            theme: _wallpaper,
            parallax: Offset(px, py),
            breath: breath,
            child: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  FadeTransition(
                    opacity: _stagger(0.0, 0.35),
                    child: _StatusBar(
                      time: _statusTime,
                      onThemeTap: _cycleWallpaper,
                      themeLabel: _wallpaper.label,
                    ),
                  ),
                  const SizedBox(height: 4),
                  FadeTransition(
                    opacity: _stagger(0.05, 0.45),
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.12),
                        end: Offset.zero,
                      ).animate(_stagger(0.05, 0.45)),
                      child: _BigClock(
                        time: _timeText,
                        breath: breath,
                        palette: palette,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FadeTransition(
                    opacity: _stagger(0.15, 0.55),
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.18),
                        end: Offset.zero,
                      ).animate(_stagger(0.15, 0.55)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        child: _WorldCard(
                          character: _worldCharacter,
                          onOfflineStory: () => widget.onNavigate('/story'),
                          onPeekPhone: _openTaPhone,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  FadeTransition(
                    opacity: _stagger(0.22, 0.6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      child: _SwitchWorldBar(
                        characters: _characters,
                        current: _worldCharacter,
                        onPick: (c) => setState(() => _worldCharacter = c),
                        onCreate: () => widget.onNavigate('/create_character'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: FadeTransition(
                      opacity: _stagger(0.28, 0.85),
                      child: PageView.builder(
                        controller: _pageController,
                        itemCount: PhoneAppIconCatalog.homePages.length,
                        onPageChanged: (i) => setState(() => _pageIndex = i),
                        itemBuilder: (context, page) {
                          final ids = PhoneAppIconCatalog.homePages[page];
                          return _IconPage(
                            ids: ids,
                            newIds: PhoneAppIconCatalog.newBadgeIds,
                            onTap: _handleIconTap,
                          );
                        },
                      ),
                    ),
                  ),
                  _PageDots(
                    count: PhoneAppIconCatalog.homePages.length,
                    index: _pageIndex,
                  ),
                  const SizedBox(height: 8),
                  FadeTransition(
                    opacity: _stagger(0.45, 1.0),
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.35),
                        end: Offset.zero,
                      ).animate(_stagger(0.45, 1.0)),
                      child: _buildDock(),
                    ),
                  ),
                  SizedBox(height: MediaQuery.paddingOf(context).bottom + 10),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDock() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (final id in PhoneAppIconCatalog.defaultDockIds)
            _DockBubble(
              id: id,
              size: PhoneTheme.dockIconSize,
              badge: id == 'chat' ? _sessionBadge : 0,
              onTap: () {
                final def = PhoneAppIconCatalog.byId(id);
                _handleIconTap(id, def?.routeHint);
              },
            ),
        ],
      ),
    );
  }

  Future<void> _cycleWallpaper() async {
    const order = PhoneWallpaperTheme.values;
    final next = order[(_wallpaper.index + 1) % order.length];
    setState(() => _wallpaper = next);
    await context
        .read<LocalStorageRepository>()
        .setPhoneWallpaperThemeId(next.id);
  }

  void _handleIconTap(String id, String? routeHint) {
    switch (id) {
      case 'power':
        _confirmExit();
        return;
      case 'chat':
      case 'phone':
        widget.onNavigate('/chat_list');
        return;
      case 'contacts':
        widget.onNavigate('/contacts');
        return;
      case 'settings':
        widget.onNavigate('/settings');
        return;
      case 'memory':
      case 'notes':
        widget.onNavigate('/memory');
        return;
      case 'shop':
      case 'wallet':
      case 'coins':
      case 'store':
        widget.onNavigate('/shop');
        return;
      case 'diary':
        widget.onNavigate('/ai_diary');
        return;
      case 'moments':
      case 'forum':
        widget.onNavigate('/moments');
        return;
      case 'tarot':
      case 'oracle':
      case 'love_sign':
        widget.onNavigate('/tarot');
        return;
      case 'music':
        widget.onNavigate('/music');
        return;
      case 'story':
      case 'destiny':
      case 'guide':
      case 'inspiration':
        widget.onNavigate('/story');
        return;
      case 'reading':
        widget.onNavigate('/novel');
        return;
      case 'mailbox':
        widget.onNavigate('/mailbox');
        return;
      case 'calendar':
        widget.onNavigate('/growth');
        return;
      case 'love_lab':
        widget.onNavigate('/relationship');
        return;
      case 'live2d':
        if (_worldCharacter != null) {
          _openTaPhone();
        } else {
          widget.onNavigate('/create_character');
        }
        return;
      default:
        if (routeHint != null && routeHint.isNotEmpty) {
          widget.onNavigate('/$routeHint');
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  '${PhoneAppIconCatalog.byId(id)?.label ?? id} 暂未接入'),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 1),
            ),
          );
        }
    }
  }

  void _openTaPhone() {
    final c = _worldCharacter;
    if (c == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('还没有角色，先去创建一个吧'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      widget.onNavigate('/create_character');
      return;
    }
    Navigator.of(context).push(VirtualPhoneScreen.route(context, c));
  }

  Future<void> _confirmExit() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('关闭小手机？'),
        content: const Text('将回到经典底部导航。可在设置 → 外观中再次开启。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await context.read<LocalStorageRepository>().setPhoneDesktopShellEnabled(false);
      widget.onExitToClassic?.call();
    }
  }
}

// ─────────────────────────── pages ───────────────────────────

class _IconPage extends StatelessWidget {
  final List<String> ids;
  final Set<String> newIds;
  final void Function(String id, String? routeHint) onTap;

  const _IconPage({
    required this.ids,
    required this.newIds,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 4),
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: PhoneTheme.gridCrossAxisCount,
        mainAxisSpacing: PhoneTheme.gridSpacing,
        crossAxisSpacing: 8,
        childAspectRatio: 0.74,
      ),
      itemCount: ids.length,
      itemBuilder: (context, i) {
        final id = ids[i];
        final def = PhoneAppIconCatalog.byId(id);
        return PhoneAppIcon.fromId(
          id,
          size: PhoneTheme.homeIconSize,
          isNew: newIds.contains(id),
          onTap: () => onTap(id, def?.routeHint),
        );
      },
    );
  }
}

class _PageDots extends StatelessWidget {
  final int count;
  final int index;
  const _PageDots({required this.count, required this.index});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final active = i == index;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: active ? 10 : 8,
          height: active ? 10 : 8,
          decoration: BoxDecoration(
            color: active
                ? Colors.white.withValues(alpha: 0.95)
                : Colors.white.withValues(alpha: 0.30),
            borderRadius: BorderRadius.circular(3),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: Colors.white.withValues(alpha: 0.35),
                      blurRadius: 6,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          curve: Curves.easeOutCubic,
        );
      }),
    );
  }
}

// ─────────────────────────── chrome ───────────────────────────

class _StatusBar extends StatelessWidget {
  final String time;
  final VoidCallback onThemeTap;
  final String themeLabel;
  const _StatusBar({
    required this.time,
    required this.onThemeTap,
    required this.themeLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 12, 0),
      child: Row(
        children: [
          Text(
            time,
            style: TextStyle(
              color: PhoneTheme.textOnWallpaper,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              shadows: PhoneTheme.labelShadows,
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: onThemeTap,
            child: PhoneGlassPanel(
              radius: 12,
              fillOpacity: 0.22,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.wallpaper_rounded,
                      size: 13, color: Colors.white),
                  const SizedBox(width: 4),
                  Text(
                    themeLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Solace-style dot-matrix status indicators (not iOS-like)
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: PhoneTheme.textOnWallpaper.withValues(alpha: 0.6),
                width: 1.2,
              ),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  PhoneTheme.textOnWallpaper.withValues(alpha: 0.35),
                  PhoneTheme.textOnWallpaper.withValues(alpha: 0.15),
                ],
              ),
            ),
          ),
          const SizedBox(width: 5),
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: PhoneTheme.textOnWallpaper.withValues(alpha: 0.6),
                width: 1.2,
              ),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  PhoneTheme.textOnWallpaper.withValues(alpha: 0.55),
                  PhoneTheme.textOnWallpaper.withValues(alpha: 0.25),
                ],
              ),
            ),
          ),
          const SizedBox(width: 5),
          Container(
            width: 18,
            height: 10,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(3),
              border: Border.all(
                color: PhoneTheme.textOnWallpaper.withValues(alpha: 0.6),
                width: 1.2,
              ),
              gradient: LinearGradient(
                colors: [
                  PhoneTheme.textOnWallpaper.withValues(alpha: 0.35),
                  PhoneTheme.textOnWallpaper.withValues(alpha: 0.15),
                ],
              ),
            ),
            child: Stack(
              children: [
                Container(
                  width: 12,
                  height: 6,
                  margin: const EdgeInsets.all(1.5),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(1.5),
                    color: PhoneTheme.textOnWallpaper.withValues(alpha: 0.75),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BigClock extends StatelessWidget {
  final String time;
  final double breath;
  final SolacePalette palette;
  const _BigClock({
    required this.time,
    this.breath = 1,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scale: 0.98 + (breath - 0.96) * 0.5,
      child: ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (bounds) => LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [palette.clockTop, palette.clockBottom],
        ).createShader(bounds),
        child: Text(
          time,
          style: TextStyle(
            fontSize: 76,
            height: 1.0,
            fontWeight: FontWeight.w200,
            letterSpacing: 3,
            color: Colors.white,
            shadows: [
              Shadow(
                color: const Color(0x33000000),
                blurRadius: 22 * breath,
                offset: const Offset(0, 8),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WorldCard extends StatelessWidget {
  final AICharacter? character;
  final VoidCallback onOfflineStory;
  final VoidCallback onPeekPhone;

  const _WorldCard({
    required this.character,
    required this.onOfflineStory,
    required this.onPeekPhone,
  });

  @override
  Widget build(BuildContext context) {
    final name = character?.name ?? '未选择角色';
    final avatar = character?.avatarUrl;

    return PhoneGlassPanel(
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      child: Row(
        children: [
          _Avatar(url: avatar, name: name),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '角色世界',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.75),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          _MiniAction(
            icon: Icons.auto_awesome_outlined,
            label: '世界任务',
            onTap: onOfflineStory,
          ),
          Container(
            width: 1,
            height: 36,
            margin: const EdgeInsets.symmetric(horizontal: 6),
            color: Colors.white.withValues(alpha: 0.35),
          ),
          _MiniAction(
            icon: Icons.devices_rounded,
            label: '角色设备',
            onTap: onPeekPhone,
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String? url;
  final String name;
  const _Avatar({this.url, required this.name});

  @override
  Widget build(BuildContext context) {
    final letter =
        name.isNotEmpty ? String.fromCharCode(name.runes.first) : '?';
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border:
            Border.all(color: Colors.white.withValues(alpha: 0.7), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipOval(
        child: url != null && url!.isNotEmpty
            ? Image.network(
                url!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _letter(letter),
              )
            : _letter(letter),
      ),
    );
  }

  Widget _letter(String letter) => Container(
        color: SolacePalettes.dawn.accent.withValues(alpha: 0.55),
        alignment: Alignment.center,
        child: Text(
          letter,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
      );
}

class _MiniAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _MiniAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: Colors.white.withValues(alpha: 0.95)),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: Colors.white.withValues(alpha: 0.9),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SwitchWorldBar extends StatelessWidget {
  final List<AICharacter> characters;
  final AICharacter? current;
  final ValueChanged<AICharacter> onPick;
  final VoidCallback onCreate;

  const _SwitchWorldBar({
    required this.characters,
    required this.current,
    required this.onPick,
    required this.onCreate,
  });

  @override
  Widget build(BuildContext context) {
    return PhoneGlassPanel(
      radius: 18,
      fillOpacity: 0.22,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      onTap: () {
        if (characters.isEmpty) {
          onCreate();
        } else {
          _showPicker(context);
        }
      },
      child: Row(
        children: [
          Icon(Icons.swap_horiz_rounded,
              size: 18, color: Colors.white.withValues(alpha: 0.9)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              characters.isEmpty ? '还没有角色世界，去创建一个' : '切换角色世界',
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withValues(alpha: 0.92),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Icon(Icons.chevron_right_rounded,
              size: 20, color: Colors.white.withValues(alpha: 0.85)),
        ],
      ),
    );
  }

  Future<void> _showPicker(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
            child: Container(
              padding: const EdgeInsets.fromLTRB(8, 12, 8, 24),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.28),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
                border: Border.all(color: Colors.white.withValues(alpha: 0.45)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                    const Text(
                      '选择角色世界',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(ctx).height * 0.45,
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: characters.length,
                      itemBuilder: (_, i) {
                        final c = characters[i];
                        final selected = c.id == current?.id;
                        final letter = c.name.isNotEmpty
                            ? String.fromCharCode(c.name.runes.first)
                            : '?';
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: SolacePalettes.dawn.accent.withValues(alpha: 0.45),
                            child: Text(letter,
                                style: const TextStyle(color: Colors.white)),
                          ),
                          title: Text(
                            c.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          trailing: selected
                              ? const Icon(Icons.check_circle,
                                  color: Colors.white)
                              : null,
                          onTap: () {
                            onPick(c);
                            Navigator.pop(ctx);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────── dock bubbles ───────────────────────────

class _DockBubble extends StatelessWidget {
  final String id;
  final double size;
  final int badge;
  final VoidCallback onTap;

  const _DockBubble({
    required this.id,
    required this.size,
    this.badge = 0,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: PhoneGlassPanel(
        radius: 20,
        fillOpacity: 0.28,
        borderOpacity: 0.45,
        padding: EdgeInsets.all(size * 0.22),
        child: PhoneAppIcon.fromId(
          id,
          size: size,
          showLabel: false,
          badge: badge,
        ),
      ),
    );
  }
}
