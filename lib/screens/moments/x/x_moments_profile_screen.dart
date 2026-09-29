import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../blocs/auth/auth_bloc.dart';
import '../../../config/moments_theme.dart';
import '../../../models/moment.dart';
import '../../../models/ai_character.dart';
import '../../../models/user.dart';
import '../../../repositories/local_storage_repository.dart';
import '../../../widgets/moments/circular_avatar.dart';
import '../../../widgets/moments/moment_card.dart';
import 'x_edit_profile_screen.dart';
import 'x_moment_detail_screen.dart';

/// X 推特风格个人主页（三 Tab：动态/回复/媒体）
class XMomentsProfileScreen extends StatefulWidget {
  final String userId;
  final String userName;
  final String? userAvatar;

  const XMomentsProfileScreen({
    super.key,
    required this.userId,
    required this.userName,
    this.userAvatar,
  });

  @override
  State<XMomentsProfileScreen> createState() => _XMomentsProfileScreenState();
}

class _XMomentsProfileScreenState extends State<XMomentsProfileScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Moment> _moments = [];
  List<Moment> _replies = [];
  List<Moment> _media = [];
  bool _isLoading = true;
  bool _isAI = false;
  bool _isCurrentUser = false;
  AICharacter? _character;
  User? _profileUser;
  Set<String> _likedIds = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final storage = context.read<LocalStorageRepository>();
    final authState = context.read<AuthBloc>().state;
    final currentUser = authState is AuthAuthenticated ? authState.user : null;
    final currentUserId = currentUser?.id ?? '';

    try {
      // 判断是否为 AI 角色
      final characters = await storage.getAllAICharacters();
      _character = characters.cast<AICharacter?>().firstWhere(
            (c) => c?.id == widget.userId,
            orElse: () => null,
          );
      _isAI = _character != null;
      _isCurrentUser = !_isAI && widget.userId == currentUser?.id;
      if (_isAI) {
        _profileUser = null;
      } else {
        final storedUser = await storage.getUser(widget.userId);
        _profileUser = storedUser ?? (_isCurrentUser ? currentUser : null);
      }

      final moments = await storage.getMomentsByUserId(widget.userId);
      final replies =
          await storage.getMomentsByUserId(widget.userId, repliesOnly: true);
      final media =
          await storage.getMomentsByUserId(widget.userId, mediaOnly: true);

      final likedIds = <String>{};
      for (final m in [...moments, ...replies, ...media]) {
        if (m.likes.any((l) => l.userId == currentUserId)) {
          likedIds.add(m.id);
        }
      }

      if (mounted) {
        setState(() {
          _moments = moments;
          _replies = replies;
          _media = media;
          _likedIds = likedIds;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String get _displayName => _isAI
      ? (_character?.name ?? widget.userName)
      : (_profileUser?.nickname ?? widget.userName);

  String? get _displayAvatar => _isAI
      ? (_character?.avatarUrl ?? widget.userAvatar)
      : (_profileUser?.avatarUrl ?? widget.userAvatar);

  String? get _displayBio {
    if (_isAI) return _character?.personality;
    final bio = _profileUser?.bio;
    if (bio != null && bio.trim().isNotEmpty) return bio;
    final signature = _profileUser?.signature;
    if (signature != null && signature.trim().isNotEmpty) return signature;
    return null;
  }

  String? get _displayLocation => _isAI ? null : _profileUser?.location;

  String? get _displayBackground =>
      _isAI ? null : _profileUser?.backgroundImage;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MomentsTheme.background(context),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(
                  color: MomentsTheme.primary(context)))
          : NestedScrollView(
              headerSliverBuilder: (ctx, inner) => [
                // 顶部栏
                SliverAppBar(
                  pinned: true,
                  backgroundColor: MomentsTheme.cardBackground(context),
                  elevation: 0,
                  leading: IconButton(
                    icon: Icon(Icons.arrow_back,
                        color: MomentsTheme.textPrimary(context)),
                    onPressed: () => Navigator.pop(context),
                  ),
                  title: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_displayName,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: MomentsTheme.textPrimary(context),
                          )),
                      Text(
                        '${_moments.length + _replies.length} 条动态',
                        style: TextStyle(
                          fontSize: 13,
                          color: MomentsTheme.textSecondary(context),
                        ),
                      ),
                    ],
                  ),
                ),
                // 头部信息
                SliverToBoxAdapter(child: _profileHeader()),
                // Tab 栏
                SliverToBoxAdapter(
                  child: Container(
                    color: MomentsTheme.cardBackground(context),
                    child: TabBar(
                      controller: _tabController,
                      labelColor: MomentsTheme.primary(context),
                      unselectedLabelColor: MomentsTheme.textSecondary(context),
                      indicatorColor: MomentsTheme.primary(context),
                      indicatorWeight: 3,
                      tabs: const [
                        Tab(text: '动态'),
                        Tab(text: '回复'),
                        Tab(text: '媒体'),
                      ],
                    ),
                  ),
                ),
              ],
              body: TabBarView(
                controller: _tabController,
                children: [
                  _buildList(_moments),
                  _buildList(_replies),
                  _buildList(_media),
                ],
              ),
            ),
    );
  }

  Widget _profileHeader() {
    final bgPath = _displayBackground;
    final bgFile = bgPath != null ? File(bgPath) : null;
    final hasBackground = bgFile != null && bgFile.existsSync();
    final bio = _displayBio;
    final location = _displayLocation;

    return Container(
      color: MomentsTheme.cardBackground(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 188,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                SizedBox(
                  height: 128,
                  width: double.infinity,
                  child: hasBackground
                      ? Image.file(bgFile, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(color: MomentsTheme.surface(context)),
                        )
                      : Container(color: MomentsTheme.surface(context)),
                ),
                Positioned(
                  left: 16,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: MomentsTheme.cardBackground(context),
                      shape: BoxShape.circle,
                    ),
                    child: CircularAvatar(
                      avatarPath: _displayAvatar,
                      name: _displayName,
                      radius: 38,
                    ),
                  ),
                ),
                Positioned(
                  right: 16,
                  bottom: 8,
                  child: _isAI
                      ? FilledButton(
                          onPressed: () {},
                          style: FilledButton.styleFrom(
                            backgroundColor: MomentsTheme.textPrimary(context),
                            foregroundColor: MomentsTheme.background(context),
                            shape: const StadiumBorder(),
                            minimumSize: const Size(86, 36),
                          ),
                          child: const Text('发消息',
                              style: TextStyle(fontWeight: FontWeight.w800)),
                        )
                      : _isCurrentUser
                          ? OutlinedButton(
                              onPressed: _openEditProfile,
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(
                                    color: MomentsTheme.divider(context)),
                                foregroundColor:
                                    MomentsTheme.textPrimary(context),
                                shape: const StadiumBorder(),
                                minimumSize: const Size(96, 36),
                              ),
                              child: const Text('编辑资料',
                                  style:
                                      TextStyle(fontWeight: FontWeight.w800)),
                            )
                          : OutlinedButton(
                              onPressed: () {},
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(
                                    color: MomentsTheme.divider(context)),
                                foregroundColor:
                                    MomentsTheme.textPrimary(context),
                                shape: const StadiumBorder(),
                                minimumSize: const Size(76, 36),
                              ),
                              child: const Text('关注',
                                  style:
                                      TextStyle(fontWeight: FontWeight.w800)),
                            ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        _displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w900,
                          color: MomentsTheme.textPrimary(context),
                        ),
                      ),
                    ),
                    if (_isAI) ...[
                      const SizedBox(width: 4),
                      Icon(MomentsTheme.blueTick,
                          size: 18, color: MomentsTheme.primary(context)),
                    ],
                  ],
                ),
                Text(
                  '@$_displayName',
                  style: TextStyle(
                    fontSize: 15,
                    color: MomentsTheme.textSecondary(context),
                  ),
                ),
                if (bio != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    bio,
                    style: TextStyle(
                      fontSize: 15,
                      color: MomentsTheme.textPrimary(context),
                      height: 1.35,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 14,
                  runSpacing: 8,
                  children: [
                    if (location != null && location.trim().isNotEmpty)
                      _metaItem(Icons.location_on_outlined, location),
                    _metaItem(Icons.calendar_month_outlined,
                        '加入于 ${DateTime.now().year}年'),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(
                      '${_moments.length + _replies.length}',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: MomentsTheme.textPrimary(context),
                      ),
                    ),
                    Text(' 条动态',
                        style: TextStyle(
                            color: MomentsTheme.textSecondary(context))),
                    const SizedBox(width: 16),
                    if (_isAI) ...[
                      Text(
                        '${_character!.personality.length}',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: MomentsTheme.textPrimary(context),
                        ),
                      ),
                      Text(' 性格特征',
                          style: TextStyle(
                              color: MomentsTheme.textSecondary(context))),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _metaItem(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: MomentsTheme.textSecondary(context)),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 15,
            color: MomentsTheme.textSecondary(context),
          ),
        ),
      ],
    );
  }

  Future<void> _openEditProfile() async {
    final user = _profileUser;
    if (!_isCurrentUser || user == null) return;
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => XEditProfileScreen(user: user)),
    );
    if (result == true) {
      if (!mounted) return;
      await _loadData();
    }
  }

  Widget _buildList(List<Moment> moments) {
    if (moments.isEmpty) {
      return Center(
        child: Text('暂无内容',
            style: TextStyle(color: MomentsTheme.textSecondary(context))),
      );
    }
    return ListView.builder(
      itemCount: moments.length,
      itemBuilder: (ctx, i) => MomentCard(
        moment: moments[i],
        isLiked: _likedIds.contains(moments[i].id),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => XMomentDetailScreen(momentId: moments[i].id)),
        ).then((_) => _loadData()),
      ),
    );
  }
}
