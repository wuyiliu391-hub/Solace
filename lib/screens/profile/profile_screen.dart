import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../blocs/chat/chat_bloc.dart';
import '../../models/user.dart';
import '../../repositories/local_storage_repository.dart';
import '../../services/permission_service.dart';
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: isDark ? const Color(0xFF0A0A0A) : Colors.white,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_user == null) {
      return Scaffold(
        backgroundColor: isDark ? const Color(0xFF0A0A0A) : Colors.white,
        body: const Center(child: Text('未登录')),
      );
    }

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0A0A0A) : Colors.white,
      body: RefreshIndicator(
        onRefresh: () async {
          await _loadUser();
          await _loadStats();
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            _buildSliverAppBar(isDark),
            SliverToBoxAdapter(child: _buildProfileSection(isDark)),
            SliverToBoxAdapter(child: _buildStatsRow(isDark)),
            SliverToBoxAdapter(child: _buildQuickActions(isDark)),
          ],
        ),
      ),
    );
  }

  Widget _buildSliverAppBar(bool isDark) {
    final bgFile = _user?.backgroundImage != null ? File(_user!.backgroundImage!) : null;
    final hasBg = bgFile != null && bgFile.existsSync();

    return SliverAppBar(
      expandedHeight: 260,
      pinned: true,
      stretch: true,
      backgroundColor: isDark ? const Color(0xFF0A0A0A) : Colors.white,
      foregroundColor: Colors.white,
      actions: [
        IconButton(
          icon: const Icon(Icons.wallpaper, color: Colors.white, size: 22),
          onPressed: _changeBackgroundImage,
          tooltip: '更换背景',
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
              Image.file(bgFile, fit: BoxFit.cover,
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
                    (isDark ? const Color(0xFF0A0A0A) : Colors.white).withOpacity(0.8),
                    isDark ? const Color(0xFF0A0A0A) : Colors.white,
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

  Widget _buildProfileSection(bool isDark) {
    final avatarFile = _user?.avatarUrl != null ? File(_user!.avatarUrl!) : null;
    final hasValidAvatar = avatarFile != null && avatarFile.existsSync();

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
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isDark ? const Color(0xFF0A0A0A) : Colors.white,
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
                              color: isDark ? const Color(0xFF2C2C2C) : const Color(0xFFE8E4EC),
                              child: Icon(
                                Icons.person,
                                size: 40,
                                color: isDark ? Colors.white70 : Colors.black38,
                              ),
                            ),
                          )
                        : Container(
                            color: isDark ? const Color(0xFF2C2C2C) : const Color(0xFFE8E4EC),
                            child: Icon(
                              Icons.person,
                              size: 40,
                              color: isDark ? Colors.white70 : Colors.black38,
                            ),
                          ),
                  ),
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
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'ID: ${_user!.id.length > 8 ? _user!.id.substring(0, 8) : _user!.id}',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.white.withOpacity(0.4) : Colors.black.withOpacity(0.35),
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
                    color: isDark ? const Color(0xFF1A1A1A) : const Color(0xFFF0F0F0),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.08),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    '编辑资料',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.white.withOpacity(0.7) : Colors.black.withOpacity(0.6),
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
                color: isDark ? Colors.white.withOpacity(0.5) : Colors.black.withOpacity(0.45),
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatsRow(bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141414) : const Color(0xFFF8F8F8),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatColumn('$_chatCount', '对话数', isDark),
          _buildStatDivider(isDark),
          _buildStatColumn('$_bookmarkCount', '收藏', isDark),
          _buildStatDivider(isDark),
          _buildStatColumn('$_avgIntimacy', '好感度', isDark),
        ],
      ),
    );
  }

  Widget _buildStatColumn(String value, String label, bool isDark) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isDark ? Colors.white.withOpacity(0.4) : Colors.black.withOpacity(0.35),
          ),
        ),
      ],
    );
  }

  Widget _buildStatDivider(bool isDark) {
    return Container(
      height: 32,
      width: 1,
      color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.06),
    );
  }

  Widget _buildQuickActions(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
      child: Column(
        children: [
          _buildQuickAction(
            Icons.chat_bubble_outline,
            '查看所有对话',
            '共 $_chatCount 个会话',
            isDark,
            () {},
          ),
          const SizedBox(height: 12),
          _buildQuickAction(
            Icons.account_balance_wallet_outlined,
            '我的钱包',
            '${_user!.coins} 金币',
            isDark,
            _openWallet,
          ),
        ],
      ),
    );
  }

  Widget _buildQuickAction(IconData icon, String title, String subtitle, bool isDark, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF141414) : const Color(0xFFF8F8F8),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, size: 22, color: isDark ? Colors.white.withOpacity(0.5) : Colors.black.withOpacity(0.4)),
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
                      color: isDark ? Colors.white.withOpacity(0.8) : Colors.black.withOpacity(0.7),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white.withOpacity(0.3) : Colors.black.withOpacity(0.25),
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 20, color: isDark ? Colors.white.withOpacity(0.2) : Colors.black.withOpacity(0.15)),
          ],
        ),
      ),
    );
  }

  Future<void> _changeBackgroundImage() async {
    if (!await PermissionService.requestStoragePermission()) return;
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1920, maxHeight: 1920, imageQuality: 85,
    );
    if (pickedFile != null && _user != null) {
      final dir = await getApplicationDocumentsDirectory();
      final bgDir = Directory('${dir.path}/profile_backgrounds');
      if (!await bgDir.exists()) await bgDir.create(recursive: true);
      final ext = pickedFile.path.contains('.') ? pickedFile.path.split('.').last : 'jpg';
      final destPath = '${bgDir.path}/user_bg.$ext';
      await File(pickedFile.path).copy(destPath);

      final storage = RepositoryProvider.of<LocalStorageRepository>(context);
      final updatedUser = _user!.copyWith(backgroundImage: destPath);
      await storage.saveUser(updatedUser);
      final authBloc = context.read<AuthBloc>();
      if (authBloc.state is AuthAuthenticated) {
        authBloc.add(AuthUserUpdated(updatedUser));
      }
      setState(() { _user = updatedUser; });
    }
  }

  Future<void> _changeAvatar() async {
    if (!await PermissionService.requestStoragePermission()) return;
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1920, maxHeight: 1920, imageQuality: 85,
    );
    if (pickedFile != null && _user != null) {
      final storage = RepositoryProvider.of<LocalStorageRepository>(context);
      final persistentPath = await _copyToPersistentPath(pickedFile.path);
      final updatedUser = _user!.copyWith(avatarUrl: persistentPath);
      await storage.saveUser(updatedUser);
      final authBloc = context.read<AuthBloc>();
      if (authBloc.state is AuthAuthenticated) {
        authBloc.add(AuthUserUpdated(updatedUser));
      }
      setState(() {
        _user = updatedUser;
      });
    }
  }

  Future<String> _copyToPersistentPath(String sourcePath) async {
    try {
      final source = File(sourcePath);
      if (!await source.exists()) return sourcePath;
      final dir = await getApplicationDocumentsDirectory();
      final avatarDir = Directory('${dir.path}/avatars');
      if (!await avatarDir.exists()) {
        await avatarDir.create(recursive: true);
      }
      final ext = sourcePath.contains('.') ? sourcePath.split('.').last : 'jpg';
      final destPath = '${avatarDir.path}/user_avatar.$ext';
      await source.copy(destPath);
      return destPath;
    } catch (e) {
      return sourcePath;
    }
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
