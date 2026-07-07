import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../blocs/virtual_phone/virtual_phone_bloc.dart';
import '../../models/ai_character.dart';
import '../../models/virtual_phone/vp_chat.dart';
import '../../repositories/local_storage_repository.dart';
import '../../services/ai_service.dart';
import 'vp_apps.dart';

/// 虚拟手机主屏
///
/// 每个 AI 角色的一台「专属虚构手机」。内容全部由 LLM 依据人设生成、纯本地存储，
/// 只读浏览 + 可刷新。不读取任何真实设备数据，不上传任何数据。
class VirtualPhoneScreen extends StatelessWidget {
  final AICharacter character;

  const VirtualPhoneScreen({super.key, required this.character});

  /// 从单聊页进入的便捷入口：自建 Bloc 并注入依赖。
  static Route<void> route(BuildContext context, AICharacter character) {
    final storage = RepositoryProvider.of<LocalStorageRepository>(context);
    return MaterialPageRoute(
      builder: (_) => RepositoryProvider.value(
        value: storage,
        child: BlocProvider(
          create: (_) => VirtualPhoneBloc(storage, AIService(storage))
            ..add(VirtualPhoneOpened(character)),
          child: _Loader(character: character),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => _VirtualPhoneView(character: character);
}

/// 负责在进入时读取用户昵称并派发 Open 事件（携带昵称）。
class _Loader extends StatefulWidget {
  final AICharacter character;
  const _Loader({required this.character});

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
  Widget build(BuildContext context) =>
      _VirtualPhoneView(character: widget.character);
}

class _VirtualPhoneView extends StatelessWidget {
  final AICharacter character;
  const _VirtualPhoneView({required this.character});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return BlocBuilder<VirtualPhoneBloc, VirtualPhoneState>(
      builder: (context, state) {
        return Scaffold(
          backgroundColor: cs.surface,
          body: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  cs.surface,
                  cs.surfaceContainerHighest,
                ],
              ),
            ),
            child: SafeArea(
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
        return _buildLoading(context);
      case VpStatus.generating:
        return _buildGenerating(context, state);
      case VpStatus.failed:
        return _buildFailed(context, state);
      case VpStatus.ready:
      case VpStatus.notGenerated:
        // 外壳与图标常驻写死；内容有没有都进主屏，内页各自处理空态。
        return _buildHome(context, state);
      case VpStatus.initial:
        return _buildLoading(context);
    }
  }

  Widget _buildLoading(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        _topBar(context, character.name),
        const Spacer(),
        CircularProgressIndicator(color: cs.primary),
        const Spacer(),
      ],
    );
  }

  Widget _buildGenerating(BuildContext context, VirtualPhoneState state) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        _topBar(context, character.name),
        const Spacer(),
        CircularProgressIndicator(color: cs.primary),
        const SizedBox(height: 20),
        Text(
          state.status == VpStatus.generating
              ? '正在生成 ${character.name} 的手机世界…'
              : '载入中…',
          style: TextStyle(color: cs.onSurface, fontSize: 15),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 48),
          child: Text(
            '依据 TA 的人设虚构，全部内容仅存本地',
            textAlign: TextAlign.center,
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
          ),
        ),
        const Spacer(),
      ],
    );
  }

  Widget _buildFailed(BuildContext context, VirtualPhoneState state) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        _topBar(context, character.name),
        const Spacer(),
        Icon(Icons.cloud_off_rounded, color: cs.onSurfaceVariant, size: 48),
        const SizedBox(height: 16),
        Text(
          state.error ?? '生成失败',
          textAlign: TextAlign.center,
          style: TextStyle(color: cs.onSurface, fontSize: 14),
        ),
        const SizedBox(height: 20),
        FilledButton.tonal(
          onPressed: () =>
              context.read<VirtualPhoneBloc>().add(const VirtualPhoneRefreshed()),
          child: const Text('重试'),
        ),
        const Spacer(),
      ],
    );
  }
  Widget _buildHome(BuildContext context, VirtualPhoneState state) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        _topBar(context, character.name, showRefresh: true),
        const SizedBox(height: 8),
        Expanded(
          child: GridView.count(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            crossAxisCount: 4,
            mainAxisSpacing: 22,
            crossAxisSpacing: 8,
            childAspectRatio: 0.72,
            children: [
              _appIcon(
                context,
                label: '信息',
                icon: Icons.chat_bubble_rounded,
                color: const Color(0xFF34C759),
                badge: state.chats.length,
                onTap: () => _open(context, VpAppKind.messages, state),
              ),
              _appIcon(
                context,
                label: '通讯录',
                icon: Icons.contacts_rounded,
                color: const Color(0xFF007AFF),
                badge: state.contacts.length,
                onTap: () => _open(context, VpAppKind.contacts, state),
              ),
              _appIcon(
                context,
                label: '备忘录',
                icon: Icons.sticky_note_2_rounded,
                color: const Color(0xFFFFC300),
                badge: state.notes.length,
                onTap: () => _open(context, VpAppKind.notes, state),
              ),
              _appIcon(
                context,
                label: '动态',
                icon: Icons.dynamic_feed_rounded,
                color: const Color(0xFFFF2D55),
                badge: state.moments.length,
                onTap: () => _open(context, VpAppKind.moments, state),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 12, left: 24, right: 24),
          child: Text(
            state.status == VpStatus.notGenerated
                ? '内容正在后台准备中，稍后再来即可 · 也可点右上角刷新立即生成'
                : '虚构内容 · 仅存本地',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: cs.onSurfaceVariant, fontSize: 11),
          ),
        ),
      ],
    );
  }

  void _open(BuildContext context, VpAppKind kind, VirtualPhoneState state) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => VpAppPage(
        kind: kind,
        ownerName: character.name,
        ownerAvatarUrl: character.avatarUrl,
        state: state,
      ),
    ));
  }

  Widget _appIcon(
    BuildContext context, {
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    int badge = 0,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.18),
                      blurRadius: 6,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Icon(icon, color: Colors.white, size: 30),
              ),
              if (badge > 0)
                Positioned(
                  right: -4,
                  top: -4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF3B30),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    constraints: const BoxConstraints(minWidth: 18),
                    child: Text(
                      '$badge',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _topBar(BuildContext context, String name, {bool showRefresh = false}) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 8, 0),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back_ios_new_rounded,
                color: cs.onSurface, size: 20),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: Text(
              '$name 的手机',
              style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 16,
                  fontWeight: FontWeight.w600),
            ),
          ),
          if (showRefresh)
            PopupMenuButton<String>(
              tooltip: '更新',
              icon: Icon(Icons.refresh_rounded, color: cs.onSurface, size: 22),
              onSelected: (v) {
                if (v == 'advance') {
                  _confirmAdvance(context);
                } else if (v == 'rebuild') {
                  _confirmRebuild(context);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'advance',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.auto_awesome_rounded),
                    title: Text('更新最近生活'),
                    subtitle: Text('追加近况，保留旧内容'),
                  ),
                ),
                PopupMenuItem(
                  value: 'rebuild',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.restart_alt_rounded),
                    title: Text('彻底重建'),
                    subtitle: Text('清空后全部重新生成'),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  /// 生活推进：增量追加最近内容，不清空。
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
    if (ok == true) {
      bloc.add(const VirtualPhoneAdvanced());
    }
  }

  /// 彻底重建：清空后全量重新生成（二级、谨慎）。
  Future<void> _confirmRebuild(BuildContext context) async {
    final bloc = context.read<VirtualPhoneBloc>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('彻底重建'),
        content: const Text('会清空这台手机的全部内容，依据角色人设与记忆重新虚构一遍。原有的动态、聊天、备忘都会被替换。确定吗？'),
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
    if (ok == true) {
      bloc.add(const VirtualPhoneRefreshed());
    }
  }
}

/// 供内页读取的聊天线便捷类型别名。
typedef VpChatList = List<VpChat>;

