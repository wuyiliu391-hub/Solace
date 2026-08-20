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
    _enterCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();
    _breathCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4800),
    );
    _parallaxCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 32),
    );

    _load();
    _scheduleMinuteTick();
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
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _stopAmbient();
    }
  }

  @override
  void didChangePlatformBrightness() {
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
    final nextMinute =
        DateTime(now.year, now.month, now.day, now.hour, now.minute)
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
    final theme =
        PhoneWallpaperThemeX.fromId(storage.getPhoneWallpaperThemeId());
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

  String get _dateText {
    final weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    final wd = weekdays[_now.weekday - 1];
    return '${_now.month}月${_now.day}日 周$wd';
  }

  Animation<double> _stagger(double begin, double end) {
    return CurvedAnimation(
      parent: _enterCtrl,
      curve: Interval(begin, end, curve: Curves.easeOutCubic),
    );
  }

  int get _sessionBadge {
    return _characters.isEmpty
        ? 0
        : (_characters.length > 9 ? 9 : _characters.length);
  }

  @override
  Widget build(BuildContext context) {
    final palette = PhoneWallpaperPalette.of(_wallpaper);
    return Scaffold(
      backgroundColor: palette.mid,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 壁纸层：独立动画
          AnimatedBuilder(
            animation: Listenable.merge([_breathCtrl, _parallaxCtrl]),
            builder: (context, child) {
              final breath =
                  _reduceMotion ? 1.0 : (0.96 + _breathCtrl.value * 0.04);
              final t = _parallaxCtrl.value * math.pi * 2;
              final px = _reduceMotion ? 0.0 : math.sin(t) * 5;
              final py = _reduceMotion ? 0.0 : math.cos(t) * 3.5;
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
          // 内容层
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                FadeTransition(
                  opacity: _stagger(0.0, 0.4),
                  child: _StatusBar(
                    onThemeTap: _showWallpaperPicker,
                    themeLabel: _wallpaper.label,
                  ),
                ),
                const SizedBox(height: 8),
                FadeTransition(
                  opacity: _stagger(0.05, 0.5),
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.06),
                      end: Offset.zero,
                    ).animate(_stagger(0.05, 0.5)),
                    child: _ClockBlock(
                      time: _timeText,
                      date: _dateText,
                      palette: palette,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                FadeTransition(
                  opacity: _stagger(0.12, 0.6),
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.08),
                      end: Offset.zero,
                    ).animate(_stagger(0.12, 0.6)),
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
                  opacity: _stagger(0.18, 0.65),
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
                const SizedBox(height: 12),
                Expanded(
                  child: FadeTransition(
                    opacity: _stagger(0.22, 0.85),
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
                      begin: const Offset(0, 0.15),
                      end: Offset.zero,
                    ).animate(_stagger(0.35, 1.0)),
                    child: _buildDock(),
                  ),
                ),
                SizedBox(height: MediaQuery.paddingOf(context).bottom + 12),
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
      child: PhoneGlassPanel(
        radius: PhoneTheme.dockRadius,
        fillOpacity: 0.25,
        borderOpacity: 0.4,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
      ),
    );
  }

  Future<void> _showWallpaperPicker() async {
    final picked = await showModalBottomSheet<PhoneWallpaperTheme>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _WallpaperPickerSheet(
        current: _wallpaper,
        palette: PhoneWallpaperPalette.of(_wallpaper),
      ),
    );
    if (picked != null && picked != _wallpaper) {
      setState(() => _wallpaper = picked);
      await context
          .read<LocalStorageRepository>()
          .setPhoneWallpaperThemeId(picked.id);
    }
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
      default:
        if (routeHint != null && routeHint.isNotEmpty) {
          widget.onNavigate('/$routeHint');
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text('${PhoneAppIconCatalog.byId(id)?.label ?? id} 暂未接入'),
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
    Navigator.of(context).push(
      VirtualPhoneScreen.route(context, c, wallpaperTheme: _wallpaper),
    );
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
      await context
          .read<LocalStorageRepository>()
          .setPhoneDesktopShellEnabled(false);
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
          duration: const Duration(milliseconds: 250),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: active ? 12 : 6,
          height: active ? 12 : 6,
          decoration: BoxDecoration(
            color: active
                ? Colors.white.withValues(alpha: 0.95)
                : Colors.white.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(active ? 4 : 3),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: Colors.white.withValues(alpha: 0.4),
                      blurRadius: 8,
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

/// 状态栏时钟：仅自身每分钟刷新
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
    _scheduleMinuteTick();
  }

  void _scheduleMinuteTick() {
    _timer?.cancel();
    final now = DateTime.now();
    final nextMinute =
        DateTime(now.year, now.month, now.day, now.hour, now.minute)
            .add(const Duration(minutes: 1));
    final delay = nextMinute.difference(now) + const Duration(milliseconds: 50);
    _timer = Timer(delay, () {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      _scheduleMinuteTick();
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
    return Text(
      '$h:$m',
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
          const _LiveStatusClock(),
          const Spacer(),
          GestureDetector(
            onTap: onThemeTap,
            child: PhoneGlassPanel(
              radius: 12,
              fillOpacity: 0.18,
              borderOpacity: 0.35,
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
          // 信号指示
          _SignalDots(),
          const SizedBox(width: 6),
          // 电池
          _BatteryIndicator(),
        ],
      ),
    );
  }
}

class _SignalDots extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(4, (i) {
        final active = i < 3; // 3格信号
        return Container(
          width: 3.5,
          height: 3.5 + i * 1.2,
          margin: const EdgeInsets.only(right: 2),
          decoration: BoxDecoration(
            color: active
                ? Colors.white.withValues(alpha: 0.9)
                : Colors.white.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(1),
          ),
        );
      }),
    );
  }
}

class _BatteryIndicator extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 12,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(3.5),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.6),
          width: 1.2,
        ),
      ),
      child: Stack(
        children: [
          Container(
            width: 16,
            margin: const EdgeInsets.all(1.5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              gradient: const LinearGradient(
                colors: [Color(0xFF34C759), Color(0xFF30D158)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 大时钟区块：时间 + 日期
class _ClockBlock extends StatelessWidget {
  final String time;
  final String date;
  final PhoneWallpaperPalette palette;

  const _ClockBlock({
    required this.time,
    required this.date,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [palette.clockTop, palette.clockBottom],
          ).createShader(bounds),
          child: Text(
            time,
            style: const TextStyle(
              fontSize: 72,
              height: 1.0,
              fontWeight: FontWeight.w100,
              letterSpacing: 4,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          date,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w400,
            letterSpacing: 1,
            color: Colors.white.withValues(alpha: 0.75),
          ),
        ),
      ],
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
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      child: Row(
        children: [
          _Avatar(url: avatar, name: name),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '角色世界',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.7),
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.5,
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
                    letterSpacing: 0.3,
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
            margin: const EdgeInsets.symmetric(horizontal: 8),
            color: Colors.white.withValues(alpha: 0.3),
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
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.2),
            blurRadius: 6,
            offset: const Offset(0, -2),
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
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF5BB8DC), Color(0xFF3A8EBA)],
          ),
        ),
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
      radius: 16,
      fillOpacity: 0.18,
      borderOpacity: 0.35,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
              size: 18, color: Colors.white.withValues(alpha: 0.85)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              characters.isEmpty ? '还没有角色世界，去创建一个' : '切换角色世界',
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withValues(alpha: 0.88),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Icon(Icons.chevron_right_rounded,
              size: 20, color: Colors.white.withValues(alpha: 0.8)),
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
          child: Container(
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 24),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
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
                          backgroundColor: const Color(0xFF5BB8DC),
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
      child: PhoneAppIcon.fromId(
        id,
        size: size,
        showLabel: false,
        badge: badge,
      ),
    );
  }
}

// ─────────────────── 壁纸选择面板 ───────────────────

class _WallpaperPickerSheet extends StatelessWidget {
  final PhoneWallpaperTheme current;
  final PhoneWallpaperPalette palette;

  const _WallpaperPickerSheet({required this.current, required this.palette});

  @override
  Widget build(BuildContext context) {
    const themes = PhoneWallpaperTheme.values;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              palette.gradient.first.withValues(alpha: 0.92),
              palette.mid.withValues(alpha: 0.88),
            ],
          ),
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 拖拽指示
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            palette.clockTop.withValues(alpha: 0.9),
                            palette.clockBottom.withValues(alpha: 0.7),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: palette.clockTop.withValues(alpha: 0.4),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.wallpaper_rounded,
                          color: Colors.white, size: 18),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      '选择壁纸',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '长按预览 · 点按应用',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 18),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                    childAspectRatio: 0.72,
                  ),
                  itemCount: themes.length,
                  itemBuilder: (context, i) {
                    final theme = themes[i];
                    final p = PhoneWallpaperPalette.of(theme);
                    final selected = theme == current;
                    return GestureDetector(
                      onTap: () => Navigator.of(context).pop(theme),
                      child: AnimatedScale(
                        scale: selected ? 1.05 : 1.0,
                        duration: const Duration(milliseconds: 200),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: selected
                                  ? Colors.white.withValues(alpha: 0.9)
                                  : Colors.white.withValues(alpha: 0.15),
                              width: selected ? 2 : 1,
                            ),
                            boxShadow: selected
                                ? [
                                    BoxShadow(
                                      color: p.clockTop.withValues(alpha: 0.4),
                                      blurRadius: 16,
                                      spreadRadius: 2,
                                    ),
                                  ]
                                : null,
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                // 迷你壁纸预览
                                _MiniWallpaperPreview(palette: p),
                                // 顶部时钟预览
                                Positioned(
                                  top: 8,
                                  left: 0,
                                  right: 0,
                                  child: Center(
                                    child: ShaderMask(
                                      blendMode: BlendMode.srcIn,
                                      shaderCallback: (bounds) =>
                                          LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [
                                            p.clockTop,
                                            p.clockBottom,
                                          ],
                                      ).createShader(bounds),
                                      child: const Text(
                                        '9:41',
                                        style: TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.w200,
                                          color: Colors.white,
                                          letterSpacing: 1,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                // 底部标签
                                Positioned(
                                  bottom: 0,
                                  left: 0,
                                  right: 0,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 6, horizontal: 8),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [
                                          Colors.transparent,
                                          Colors.black.withValues(alpha: 0.4),
                                        ],
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            theme.label,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                        if (selected)
                                          const Icon(Icons.check_circle_rounded,
                                              color: Colors.white, size: 14),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 迷你壁纸预览：还原大气光效的缩略版
class _MiniWallpaperPreview extends StatelessWidget {
  final PhoneWallpaperPalette palette;
  const _MiniWallpaperPreview({required this.palette});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // 基础渐变
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                palette.gradient.first,
                palette.mid,
                palette.gradient.last,
              ],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
        ),
        // 大气光斑 1
        Positioned(
          top: -20,
          right: -30,
          child: Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  palette.clockTop.withValues(alpha: 0.5),
                  palette.clockTop.withValues(alpha: 0),
                ],
              ),
            ),
          ),
        ),
        // 大气光斑 2
        Positioned(
          bottom: -25,
          left: -20,
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  palette.clockBottom.withValues(alpha: 0.4),
                  palette.clockBottom.withValues(alpha: 0),
                ],
              ),
            ),
          ),
        ),
        // 星点
        Positioned(
          top: 25,
          left: 15,
          child: Container(
            width: 2,
            height: 2,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.8),
              shape: BoxShape.circle,
            ),
          ),
        ),
        Positioned(
          top: 40,
          right: 20,
          child: Container(
            width: 1.5,
            height: 1.5,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.6),
              shape: BoxShape.circle,
            ),
          ),
        ),
      ],
    );
  }
}
