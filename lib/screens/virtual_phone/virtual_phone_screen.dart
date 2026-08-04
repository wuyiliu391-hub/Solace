import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../blocs/virtual_phone/virtual_phone_bloc.dart';
import '../../config/phone_theme.dart';
import '../../models/ai_character.dart';
import '../../models/virtual_phone/vp_chat.dart';
import '../../repositories/local_storage_repository.dart';
import '../../services/ai_service.dart';
import '../../widgets/phone/phone_app_icon.dart';
import '../../widgets/phone/phone_glass.dart';
import 'vp_apps.dart';

/// 角色专属虚拟手机主屏（看 TA 手机）
///
/// 视觉对齐 Solace 手机桌面壳：天空壁纸 + 玻璃顶栏 + 软图标 + Dock。
class VirtualPhoneScreen extends StatelessWidget {
  final AICharacter character;
  final PhoneWallpaperTheme wallpaperTheme;

  const VirtualPhoneScreen({
    super.key,
    required this.character,
    this.wallpaperTheme = PhoneWallpaperTheme.dawn,
  });

  static Route<void> route(
    BuildContext context,
    AICharacter character, {
    PhoneWallpaperTheme wallpaperTheme = PhoneWallpaperTheme.dawn,
  }) {
    final storage = RepositoryProvider.of<LocalStorageRepository>(context);
    return MaterialPageRoute(
      builder: (_) => RepositoryProvider.value(
        value: storage,
        child: BlocProvider(
          create: (_) => VirtualPhoneBloc(storage, AIService(storage))
            ..add(VirtualPhoneOpened(character)),
          child: _Loader(
            character: character,
            wallpaperTheme: wallpaperTheme,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => _VirtualPhoneView(
        character: character,
        wallpaperTheme: wallpaperTheme,
      );
}

class _Loader extends StatefulWidget {
  final AICharacter character;
  final PhoneWallpaperTheme wallpaperTheme;

  const _Loader({required this.character, required this.wallpaperTheme});

  @override
  State<_Loader> createState() => _LoaderState();
}

class _LoaderState extends State<_Loader> {
  @override
  void initState() {
    super.initState();
    _dispatchWithNickname();
  }

  Future<void> _dispatchWithNickname() async {
    final storage = RepositoryProvider.of<LocalStorageRepository>(context);
    final user = await storage.getCurrentUser();
    if (!mounted) return;
    context.read<VirtualPhoneBloc>().add(
          VirtualPhoneOpened(widget.character,
              userNickname: user?.nickname ?? '', userId: user?.id ?? ''),
        );
  }

  @override
  Widget build(BuildContext context) => _VirtualPhoneView(
        character: widget.character,
        wallpaperTheme: widget.wallpaperTheme,
      );
}

class _VirtualPhoneView extends StatefulWidget {
  final AICharacter character;
  final PhoneWallpaperTheme wallpaperTheme;

  const _VirtualPhoneView({
    required this.character,
    required this.wallpaperTheme,
  });

  @override
  State<_VirtualPhoneView> createState() => _VirtualPhoneViewState();
}

class _VirtualPhoneViewState extends State<_VirtualPhoneView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _enter;
  Timer? _clock;
  DateTime _now = DateTime.now();

  AICharacter get character => widget.character;

  @override
  void initState() {
    super.initState();
    _enter = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _enter.dispose();
    _clock?.cancel();
    super.dispose();
  }

  String get _timeText {
    final h = _now.hour.toString().padLeft(2, '0');
    final m = _now.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Animation<double> _fade(double a, double b) => CurvedAnimation(
        parent: _enter,
        curve: Interval(a, b, curve: Curves.easeOutCubic),
      );

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<VirtualPhoneBloc, VirtualPhoneState>(
      builder: (context, state) {
        return Scaffold(
          backgroundColor: PhoneWallpaperPalette.of(widget.wallpaperTheme).mid,
          body: PhoneWallpaper(
            theme: widget.wallpaperTheme,
            child: SafeArea(
              bottom: false,
              child: _buildBody(context, state),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBody(BuildContext context, VirtualPhoneState state) {
    switch (state.status) {
      case VpStatus.loading:
      case VpStatus.initial:
        return _buildBusy(context, '正在打开 ${character.name} 的手机…');
      case VpStatus.generating:
        return _buildBusy(context, '正在生成 ${character.name} 的手机世界…',
            subtitle: '依据 TA 的人设虚构 · 内容仅存本地');
      case VpStatus.failed:
        return _buildFailed(context, state);
      case VpStatus.ready:
      case VpStatus.notGenerated:
        return _buildHome(context, state);
    }
  }

  Widget _buildBusy(BuildContext context, String title, {String? subtitle}) {
    return Column(
      children: [
        _GlassTopBar(
          title: '${character.name} 的手机',
          onBack: () => Navigator.of(context).maybePop(),
        ),
        const Spacer(),
        PhoneGlassPanel(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 36,
                height: 36,
                child: CircularProgressIndicator(
                  strokeWidth: 2.6,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        ),
        const Spacer(),
      ],
    );
  }

  Widget _buildFailed(BuildContext context, VirtualPhoneState state) {
    return Column(
      children: [
        _GlassTopBar(
          title: '${character.name} 的手机',
          onBack: () => Navigator.of(context).maybePop(),
        ),
        const Spacer(),
        PhoneGlassPanel(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_rounded,
                  color: Colors.white.withValues(alpha: 0.9), size: 40),
              const SizedBox(height: 14),
              Text(
                state.error ?? '生成失败',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
              const SizedBox(height: 18),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.9),
                  foregroundColor: const Color(0xFF2B6B8A),
                ),
                onPressed: () => context
                    .read<VirtualPhoneBloc>()
                    .add(const VirtualPhoneRefreshed()),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
        const Spacer(),
      ],
    );
  }

  Widget _buildHome(BuildContext context, VirtualPhoneState state) {
    final letter = character.name.isNotEmpty
        ? String.fromCharCode(character.name.runes.first)
        : '?';

    return Column(
      children: [
        FadeTransition(
          opacity: _fade(0, 0.4),
          child: _GlassTopBar(
            title: '${character.name} 的手机',
            onBack: () => Navigator.of(context).maybePop(),
            trailing: _RefreshMenu(
              onAdvance: () => _confirmAdvance(context),
              onRebuild: () => _confirmRebuild(context),
            ),
          ),
        ),
        const SizedBox(height: 6),
        FadeTransition(
          opacity: _fade(0.05, 0.5),
          child: Text(
            _timeText,
            style: TextStyle(
              fontSize: 54,
              height: 1,
              fontWeight: FontWeight.w200,
              letterSpacing: 2,
              color: Colors.white.withValues(alpha: 0.95),
              shadows: PhoneTheme.labelShadows,
            ),
          ),
        ),
        const SizedBox(height: 14),
        FadeTransition(
          opacity: _fade(0.12, 0.55),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: PhoneGlassPanel(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              child: Row(
                children: [
                  _OwnerAvatar(
                    url: character.avatarUrl,
                    letter: letter,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          character.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          state.status == VpStatus.notGenerated
                              ? '内容准备中 · 点右上角可立即生成'
                              : '虚构手机 · 仅存本地 · 只读浏览',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.78),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 22),
        Expanded(
          child: FadeTransition(
            opacity: _fade(0.2, 0.85),
            child: GridView.count(
              padding: const EdgeInsets.fromLTRB(22, 4, 22, 12),
              crossAxisCount: 4,
              mainAxisSpacing: 18,
              crossAxisSpacing: 8,
              childAspectRatio: 0.74,
              physics: const BouncingScrollPhysics(),
              children: [
                PhoneAppIcon.fromId(
                  'chat',
                  badge: state.chats.length,
                  onTap: () => _open(context, VpAppKind.messages, state),
                ),
                PhoneAppIcon.fromId(
                  'contacts',
                  badge: state.contacts.length,
                  onTap: () => _open(context, VpAppKind.contacts, state),
                ),
                PhoneAppIcon.fromId(
                  'notes',
                  badge: state.notes.length,
                  onTap: () => _open(context, VpAppKind.notes, state),
                ),
                PhoneAppIcon.fromId(
                  'moments',
                  badge: state.moments.length,
                  onTap: () => _open(context, VpAppKind.moments, state),
                ),
              ],
            ),
          ),
        ),
        FadeTransition(
          opacity: _fade(0.4, 1),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 0),
            child: PhoneGlassPanel(
              radius: PhoneTheme.dockRadius,
              fillOpacity: 0.36,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  PhoneAppIcon.fromId(
                    'chat',
                    size: PhoneTheme.dockIconSize,
                    showLabel: false,
                    badge: state.chats.length,
                    onTap: () => _open(context, VpAppKind.messages, state),
                  ),
                  PhoneAppIcon.fromId(
                    'contacts',
                    size: PhoneTheme.dockIconSize,
                    showLabel: false,
                    onTap: () => _open(context, VpAppKind.contacts, state),
                  ),
                  PhoneAppIcon.fromId(
                    'notes',
                    size: PhoneTheme.dockIconSize,
                    showLabel: false,
                    onTap: () => _open(context, VpAppKind.notes, state),
                  ),
                  PhoneAppIcon.fromId(
                    'moments',
                    size: PhoneTheme.dockIconSize,
                    showLabel: false,
                    onTap: () => _open(context, VpAppKind.moments, state),
                  ),
                ],
              ),
            ),
          ),
        ),
        SizedBox(height: MediaQuery.paddingOf(context).bottom + 10),
      ],
    );
  }

  void _open(BuildContext context, VpAppKind kind, VirtualPhoneState state) {
    HapticFeedback.selectionClick();
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => VpAppPage(
        kind: kind,
        ownerName: character.name,
        ownerAvatarUrl: character.avatarUrl,
        state: state,
        wallpaperTheme: widget.wallpaperTheme,
      ),
    ));
  }

  Future<void> _confirmAdvance(BuildContext context) async {
    final bloc = context.read<VirtualPhoneBloc>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('更新最近生活'),
        content: const Text('会依据你们最近的相处，往手机里补充一些新动态/心事，旧内容保留。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('更新')),
        ],
      ),
    );
    if (ok == true) bloc.add(const VirtualPhoneAdvanced());
  }

  Future<void> _confirmRebuild(BuildContext context) async {
    final bloc = context.read<VirtualPhoneBloc>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('彻底重建'),
        content:
            const Text('会清空这台手机的全部内容，依据角色人设与记忆重新虚构一遍。原有的动态、聊天、备忘都会被替换。确定吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('彻底重建')),
        ],
      ),
    );
    if (ok == true) bloc.add(const VirtualPhoneRefreshed());
  }
}

// ─────────────────── chrome ───────────────────

class _GlassTopBar extends StatelessWidget {
  final String title;
  final VoidCallback onBack;
  final Widget? trailing;

  const _GlassTopBar({
    required this.title,
    required this.onBack,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      child: PhoneGlassPanel(
        radius: 18,
        fillOpacity: 0.26,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: Colors.white, size: 18),
              onPressed: onBack,
            ),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}

class _OwnerAvatar extends StatelessWidget {
  final String? url;
  final String letter;
  const _OwnerAvatar({this.url, required this.letter});

  @override
  Widget build(BuildContext context) {
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
        child: (url != null && url!.isNotEmpty)
            ? Image.network(
                url!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _letter(),
              )
            : _letter(),
      ),
    );
  }

  Widget _letter() => Container(
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

class _RefreshMenu extends StatelessWidget {
  final VoidCallback onAdvance;
  final VoidCallback onRebuild;
  const _RefreshMenu({required this.onAdvance, required this.onRebuild});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: '更新',
      icon: const Icon(Icons.more_horiz_rounded, color: Colors.white, size: 22),
      color: const Color(0xEE2A3A45),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      onSelected: (v) {
        if (v == 'advance') onAdvance();
        if (v == 'rebuild') onRebuild();
      },
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: 'advance',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.auto_awesome_rounded, color: Colors.white70),
            title: Text('更新最近生活', style: TextStyle(color: Colors.white)),
            subtitle: Text('追加近况，保留旧内容',
                style: TextStyle(color: Colors.white54, fontSize: 11)),
          ),
        ),
        PopupMenuItem(
          value: 'rebuild',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.restart_alt_rounded, color: Colors.white70),
            title: Text('彻底重建', style: TextStyle(color: Colors.white)),
            subtitle: Text('清空后全部重新生成',
                style: TextStyle(color: Colors.white54, fontSize: 11)),
          ),
        ),
      ],
    );
  }
}

/// 供内页读取的聊天线便捷类型别名。
typedef VpChatList = List<VpChat>;
