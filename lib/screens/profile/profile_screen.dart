import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../blocs/chat/chat_bloc.dart';
import '../../models/user.dart';
import '../../repositories/local_storage_repository.dart';
import '../../services/permission_service.dart';
import '../../widgets/image_cropper.dart';
import '../../widgets/background_picker.dart';
import '../../utils/background_resolver.dart';
import 'wallet_screen.dart';
import 'edit_profile_screen.dart';
import 'settings_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with AutomaticKeepAliveClientMixin {
  User? _user;
  bool _isLoading = true;
  int _chatCount = 0;
  int _bookmarkCount = 0;
  int _avgIntimacy = 0;

  @override
  bool get wantKeepAlive => false;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadUser();
    _loadStats();
  }

  Future<void> _loadUser() async {
    final storage = RepositoryProvider.of<LocalStorageRepository>(context);
    final user = await storage.getCurrentUser();
    if (mounted) {
      setState(() {
        _user = user;
        _isLoading = false;
      });
    }
  }

  Future<void> _loadStats() async {
    try {
      final authBloc = context.read<AuthBloc>();
      if (authBloc.state is! AuthAuthenticated) return;
      final userId = (authBloc.state as AuthAuthenticated).user.id;
      final storage = RepositoryProvider.of<LocalStorageRepository>(context);

      // 对话数
      final chatBloc = context.read<ChatBloc>();
      final chatState = chatBloc.state;
      int chatCount = 0;
      if (chatState is ChatSessionsLoaded) {
        chatCount = chatState.sessions.length;
      }

      // 收藏数
      final bookmarkedIds = await storage.getBookmarkedMomentIds(userId);

      // 好感度（平均亲密度）
      final sessions = await storage.getChatSessions(userId);
      int totalIntimacy = 0;
      for (final s in sessions) {
        totalIntimacy += s.intimacyLevel;
      }
      final avgIntimacy = sessions.isEmpty ? 0 : (totalIntimacy / sessions.length).round();

      if (mounted) {
        setState(() {
          _chatCount = chatCount;
          _bookmarkCount = bookmarkedIds.length;
          _avgIntimacy = avgIntimacy;
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colorScheme = Theme.of(context).colorScheme;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: colorScheme.surface,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_user == null) {
      return Scaffold(
        backgroundColor: colorScheme.surface,
        body: const Center(child: Text('未登录')),
      );
    }

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: RefreshIndicator(
        onRefresh: () async {
          await _loadUser();
          await _loadStats();
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            _buildSliverAppBar(),
            SliverToBoxAdapter(child: _buildProfileSection()),
            SliverToBoxAdapter(child: _buildStatsRow()),
            SliverToBoxAdapter(child: _buildQuickActions()),
          ],
        ),
      ),
    );
  }

  Widget _buildSliverAppBar() {
    // 背景分横竖屏两张，按当前朝向取；只设了一边时另一朝向回退
    final mq = MediaQuery.sizeOf(context);
    final bgProvider = BackgroundResolver.provider(
      portrait: _user?.backgroundImage,
      landscape: _user?.backgroundImageLandscape,
      isLandscape: mq.width > mq.height,
    );
    final hasBg = bgProvider != null;
    final colorScheme = Theme.of(context).colorScheme;

    return SliverAppBar(
      expandedHeight: 260,
      pinned: true,
      stretch: true,
      backgroundColor: colorScheme.surface,
      foregroundColor: Colors.white,
      actions: [
        IconButton(
          icon: const Icon(Icons.wallpaper, color: Colors.white, size: 22),
          onPressed: _changeBackgroundImage,
          tooltip: '更换背景（横屏/竖屏）',
        ),
        IconButton(
          icon: const Icon(Icons.settings, color: Colors.white, size: 22),
          onPressed: _openSettings,
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            if (hasBg)
              Image(bgProvider, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFF1A1A2E),
                        Color(0xFF16213E),
                        Color(0xFF0F3460),
                        Color(0xFF533483),
                      ],
                    ),
                  ),
                ),
              )
            else
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF1A1A2E),
                      Color(0xFF16213E),
                      Color(0xFF0F3460),
                      Color(0xFF533483),
                    ],
                  ),
                ),
              ),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.transparent,
                    colorScheme.surface.withOpacity(0.8),
                    colorScheme.surface,
                  ],
                  stops: const [0.0, 0.5, 0.85, 1.0],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileSection() {
    final avatarFile = _user?.avatarUrl != null ? File(_user!.avatarUrl!) : null;
    final hasValidAvatar = avatarFile != null && avatarFile.existsSync();
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              GestureDetector(
                onTap: _changeAvatar,
                child: Stack(
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: colorScheme.surface,
                          width: 4,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ClipOval(
                        child: hasValidAvatar
                            ? Image.file(avatarFile, fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  color: colorScheme.surfaceContainerHigh,
                                  child: Icon(
                                    Icons.person,
                                    size: 40,
                                    color: colorScheme.onSurface.withOpacity(0.7),
                                  ),
                                ),
                              )
                            : Container(
                                color: colorScheme.surfaceContainerHigh,
                                child: Icon(
                                  Icons.person,
                                  size: 40,
                                  color: colorScheme.onSurface.withOpacity(0.7),
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _user!.nickname,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'ID: ${_user!.id.length > 8 ? _user!.id.substring(0, 8) : _user!.id}',
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.onSurface.withOpacity(0.4),
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: _editProfile,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: colorScheme.outline.withOpacity(0.1),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    '编辑资料',
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurface.withOpacity(0.7),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_user!.signature != null && _user!.signature!.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              _user!.signature!,
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.onSurface.withOpacity(0.5),
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatsRow() {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatColumn('$_chatCount', '对话数'),
          _buildStatDivider(),
          _buildStatColumn('$_bookmarkCount', '收藏'),
          _buildStatDivider(),
          _buildStatColumn('$_avgIntimacy', '好感度'),
        ],
      ),
    );
  }

  Widget _buildStatColumn(String value, String label) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: colorScheme.onSurface.withOpacity(0.4),
          ),
        ),
      ],
    );
  }

  Widget _buildStatDivider() {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: 32,
      width: 1,
      color: colorScheme.outline.withOpacity(0.1),
    );
  }

  Widget _buildQuickActions() {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
      child: Column(
        children: [
          _buildQuickAction(
            Icons.chat_bubble_outline,
            '查看所有对话',
            '共 $_chatCount 个会话',
            () {},
          ),
          const SizedBox(height: 12),
          _buildQuickAction(
            Icons.account_balance_wallet_outlined,
            '我的钱包',
            '${_user!.coins} 金币',
            _openWallet,
          ),
        ],
      ),
    );
  }

  Widget _buildQuickAction(IconData icon, String title, String subtitle, VoidCallback onTap) {
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, size: 22, color: colorScheme.onSurface.withOpacity(0.5)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: colorScheme.onSurface.withOpacity(0.8),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurface.withOpacity(0.3),
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 20, color: colorScheme.onSurface.withOpacity(0.2)),
          ],
        ),
      ),
    );
  }

  /// 打开「横屏 / 竖屏背景」设置弹窗。
  Future<void> _changeBackgroundImage() async {
    final user = _user;
    if (user == null) return;

    final result = await showModalBottomSheet<BackgroundOrientation>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('个人主页背景',
                style: Theme.of(ctx).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              '横屏和竖屏的可见范围不同，可分别设置',
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            BackgroundPicker(
              currentPortrait: user.backgroundImage,
              currentLandscape: user.backgroundImageLandscape,
              onChanged: (orientation, path) async {
                // 立即关闭弹窗，回主界面再裁剪，避免两层全屏路由叠加
                Navigator.pop(ctx, orientation);
                await _applyBackground(orientation, path);
              },
            ),
          ],
        ),
      ),
    );
    // result 仅用于语义（弹窗内已就地处理），保留以免误用
    // ignore: unnecessary_statements
    result;
  }

  Future<void> _applyBackground(
      BackgroundOrientation orientation, String? path) async {
    final user = _user;
    if (user == null || !mounted) return;
    final storage = RepositoryProvider.of<LocalStorageRepository>(context);
    // 清除时必须走 clear* 开关：copyWith 传 null 会被静默忽略
    final updated = orientation == BackgroundOrientation.portrait
        ? (path == null
            ? user.copyWith(clearBackgroundImage: true)
            : user.copyWith(backgroundImage: path))
        : (path == null
            ? user.copyWith(clearBackgroundImageLandscape: true)
            : user.copyWith(backgroundImageLandscape: path));
    await storage.saveUser(updated);
    if (!mounted) return;
    final authBloc = context.read<AuthBloc>();
    if (authBloc.state is AuthAuthenticated) {
      authBloc.add(AuthUserUpdated(updated));
    }
    setState(() {
      _user = updated;
    });
  }

  Future<void> _changeAvatar() async {
    if (!await PermissionService.requestStoragePermission()) return;
    final pickedFile = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 2048, maxHeight: 2048, imageQuality: 92,
    );
    if (pickedFile == null) return;

    // 自由裁剪：双指缩放 / 单指拖动 / 旋转，输出正方形并落到 docs/avatars
    final cropped = await showImageCropper(context, File(pickedFile.path));
    if (cropped == null || !mounted || _user == null) return;

    final storage = RepositoryProvider.of<LocalStorageRepository>(context);
    final updatedUser = _user!.copyWith(avatarUrl: cropped);
    await storage.saveUser(updatedUser);
    final authBloc = context.read<AuthBloc>();
    if (authBloc.state is AuthAuthenticated) {
      authBloc.add(AuthUserUpdated(updatedUser));
    }
    setState(() {
      _user = updatedUser;
    });
  }

  void _editProfile() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => EditProfileScreen(user: _user!)),
    );
    if (result == true) {
      _loadUser();
    }
  }

  void _openWallet() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => WalletScreen(user: _user!)),
    );
    _loadUser();
  }

  void _openSettings() async {
    final storage = RepositoryProvider.of<LocalStorageRepository>(context);
    await storage.clearUpdateAvailableBuild();
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SettingsScreen()),
    );
  }
}
