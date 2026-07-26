import 'dart:async';
import 'dart:math' as math;

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
    with TickerProviderStateMixin, WidgetsBindingObserver {
  List<AICharacter> _characters = const [];
  AICharacter? _worldCharacter;
  Timer? _minuteTimer;
  DateTime _now = DateTime.now();
  int _pageIndex = 0;
  PhoneWallpaperTheme _wallpaper = PhoneWallpaperTheme.dawn;
  final _pageController = PageController();
  bool _reduceMotion = false;
  bool _animationsActive = true;

  late final AnimationController _enterCtrl;
  late final AnimationController _breathCtrl;
  late final AnimationController _parallaxCtrl;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 入场缩短：切换模式时别卡 900ms 全树动画
    _enterCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    )..forward();
    // 呼吸/视差仅驱动壁纸层，不再 rebuild 图标网格
    _breathCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5600),
    );
    _parallaxCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 28),
    );

    _load();
    // 大时钟只按分钟刷新，避免每秒 setState 整页
    _scheduleMinuteTick();
    // 等首帧布局完成后再开循环动画，降低「一切换就卡」
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncMotionPreference();
      _startAmbientIfAllowed();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startAmbientIfAllowed();
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _stopAmbient();
    }
  }

  @override
  void didChangePlatformBrightness() {
    // 无强制关联，但可借机同步无障碍偏好
    _syncMotionPreference();
  }

  void _syncMotionPreference() {
    final disable = MediaQuery.disableAnimationsOf(context);
    if (disable == _reduceMotion) return;
    setState(() => _reduceMotion = disable);
    if (disable) {
      _stopAmbient();
      _enterCtrl.value = 1.0;
    } else {
      _startAmbientIfAllowed();
    }
  }

  void _startAmbientIfAllowed() {
    if (!mounted || _reduceMotion) return;
    if (!_animationsActive) {
      _animationsActive = true;
    }
    if (!_breathCtrl.isAnimating) {
      _breathCtrl.repeat(reverse: true);
    }
    if (!_parallaxCtrl.isAnimating) {
      _parallaxCtrl.repeat(reverse: true);
    }
  }

  void _stopAmbient() {
    _animationsActive = false;
    if (_breathCtrl.isAnimating) _breathCtrl.stop();
    if (_parallaxCtrl.isAnimating) _parallaxCtrl.stop();
  }

  void _scheduleMinuteTick() {
    _minuteTimer?.cancel();
    final now = DateTime.now();
    final nextMinute = DateTime(now.year, now.month, now.day, now.hour, now.minute)
        .add(const Duration(minutes: 1));
    final delay = nextMinute.difference(now) + const Duration(milliseconds: 50);
    _minuteTimer = Timer(delay, () {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      _scheduleMinuteTick();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _minuteTimer?.cancel();
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
    final palette = PhoneWallpaperPalette.of(_wallpaper);
    // 关键：壁纸动画层 与 前景内容层 分离。
    // 旧实现把整棵 Column（图标/毛玻璃/PageView）包进 AnimatedBuilder，
    // 呼吸+视差每帧重建全部子树 → 一切换手机模式就卡。
    return Scaffold(
      backgroundColor: palette.mid,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 仅壁纸吃动画；内容用 child 槽位固定，不随 tick rebuild
          AnimatedBuilder(
            animation: Listenable.merge([_breathCtrl, _parallaxCtrl]),
            builder: (context, child) {
              final breath = _reduceMotion
                  ? 1.0
                  : (0.97 + _breathCtrl.value * 0.03);
              final t = _parallaxCtrl.value * math.pi * 2;
              final px = _reduceMotion ? 0.0 : math.sin(t) * 6;
              final py = _reduceMotion ? 0.0 : math.cos(t) * 4;
              return PhoneWallpaper(
                theme: _wallpaper,
                parallax: Offset(px, py),
                breath: breath,
                animate: !_reduceMotion,
                child: child,
              );
            },
            child: const SizedBox.expand(),
          ),
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                FadeTransition(
                  opacity: _stagger(0.0, 0.45),
                  child: _StatusBar(
                    // 秒级时钟独立组件，不拖整页
                    onThemeTap: _cycleWallpaper,
                    themeLabel: _wallpaper.label,
                  ),
                ),
                const SizedBox(height: 4),
                FadeTransition(
                  opacity: _stagger(0.05, 0.55),
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.08),
                      end: Offset.zero,
                    ).animate(_stagger(0.05, 0.55)),
                    child: _BigClock(
                      time: _timeText,
                      breath: 1.0,
                      palette: palette,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                FadeTransition(
                  opacity: _stagger(0.12, 0.65),
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.10),
                      end: Offset.zero,
                    ).animate(_stagger(0.12, 0.65)),
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
                  opacity: _stagger(0.18, 0.7),
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
                    opacity: _stagger(0.22, 0.9),
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
                  opacity: _stagger(0.35, 1.0),
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.2),
                      end: Offset.zero,
                    ).animate(_stagger(0.35, 1.0)),
                    child: _buildDock(),
                  ),
                ),
                SizedBox(height: MediaQuery.paddingOf(context).bottom + 10),
              ],
            ),
          ),
        ],
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
        content: const Text('将回到经典底部导航。之后可在 设置 → 外观设置 → 虚拟手机桌面 再次开启。'),
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

/// 状态栏时钟：仅自身每秒刷新，不触发 PhoneHomeShell setState。
class _LiveStatusClock extends StatefulWidget {
  const _LiveStatusClock();

  @override
  State<_LiveStatusClock> createState() => _LiveStatusClockState();
}

class _LiveStatusClockState extends State<_LiveStatusClock> {
  Timer? _timer;
  late DateTime _now;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = _now.hour.toString().padLeft(2, '0');
    final m = _now.minute.toString().padLeft(2, '0');
    final s = _now.second.toString().padLeft(2, '0');
    return Text(
      '$h:$m:$s',
      style: TextStyle(
        color: PhoneTheme.textOnWallpaper,
        fontSize: 13,
        fontWeight: FontWeight.w600,
        shadows: PhoneTheme.labelShadows,
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  final VoidCallback onThemeTap;
  final String themeLabel;
  const _StatusBar({
    required this.onThemeTap,
    required this.themeLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 12, 0),
      child: Row(
        children: [
          // 秒表独立刷新，避免拖整页 setState
          const _LiveStatusClock(),
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
  final PhoneWallpaperPalette palette;
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
        color: const Color(0xFF8FD0EA),
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
        // 底部选择器：半透明即可，避免再开一层大 sigma BackdropFilter
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: Container(
              padding: const EdgeInsets.fromLTRB(8, 12, 8, 24),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
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
                            backgroundColor: const Color(0xFF8FD0EA),
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
