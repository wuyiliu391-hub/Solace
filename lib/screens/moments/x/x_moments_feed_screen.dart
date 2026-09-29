import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../blocs/auth/auth_bloc.dart';
import '../../../blocs/moments/moments_feed_bloc.dart';
import '../../../config/moments_theme.dart';
import '../../../models/moment.dart';
import '../../../repositories/local_storage_repository.dart';
import '../../../widgets/moments/circular_avatar.dart';
import '../../../widgets/moments/moment_card.dart';
import 'x_compose_moment_screen.dart';
import 'x_moment_detail_screen.dart';
import 'x_moments_profile_screen.dart';
import 'x_bookmarks_screen.dart';
import 'x_notifications_screen.dart';
import 'x_search_screen.dart';

/// X 推特风格信息流页面
class XMomentsFeedScreen extends StatefulWidget {
  const XMomentsFeedScreen({super.key});

  @override
  State<XMomentsFeedScreen> createState() => _XMomentsFeedScreenState();
}

class _XMomentsFeedScreenState extends State<XMomentsFeedScreen> {
  int _bottomIndex = 0;
  MomentsFeedBloc? _feedBloc;

  @override
  void dispose() {
    _feedBloc?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthBloc>().state;
    final userId = authState is AuthAuthenticated ? authState.user.id : '';
    final userName =
        authState is AuthAuthenticated ? authState.user.nickname : '我';
    final userAvatar =
        authState is AuthAuthenticated ? authState.user.avatarUrl : null;
    final overlayStyle = MomentsTheme.isDark(context)
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark;

    _feedBloc ??= MomentsFeedBloc(
      context.read<LocalStorageRepository>(),
      currentUserId: userId,
    )..add(MomentsFeedLoad());

    return BlocProvider.value(
      value: _feedBloc!,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: overlayStyle,
        child: DefaultTabController(
          length: 2,
          child: Scaffold(
            backgroundColor: MomentsTheme.background(context),
            body: NestedScrollView(
              headerSliverBuilder: (ctx, innerBoxScrolled) => [
                SliverAppBar(
                  floating: true,
                  pinned: true,
                  snap: false,
                  toolbarHeight: 54,
                  backgroundColor:
                      MomentsTheme.cardBackground(context).withOpacity(0.96),
                  surfaceTintColor: Colors.transparent,
                  elevation: 0,
                  leadingWidth: 56,
                  leading:
                      _profileButton(context, userId, userName, userAvatar),
                  title: Icon(
                    Icons.close,
                    size: 30,
                    color: MomentsTheme.textPrimary(context),
                  ),
                  centerTitle: true,
                  actions: [
                    _circleIconButton(
                      context,
                      icon: Icons.search,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const XSearchScreen()),
                      ),
                    ),
                    _circleIconButton(
                      context,
                      icon: Icons.notifications_none_rounded,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const XNotificationsScreen()),
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                  bottom: PreferredSize(
                    preferredSize: const Size.fromHeight(49),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TabBar(
                          indicatorColor: MomentsTheme.primary(context),
                          indicatorSize: TabBarIndicatorSize.label,
                          indicatorWeight: 4,
                          labelColor: MomentsTheme.textPrimary(context),
                          unselectedLabelColor:
                              MomentsTheme.textSecondary(context),
                          labelStyle: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                          unselectedLabelStyle: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                          tabs: const [
                            Tab(text: '为你推荐'),
                            Tab(text: '关注'),
                          ],
                        ),
                        Divider(
                          height: 0.5,
                          thickness: 0.5,
                          color: MomentsTheme.divider(context),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              body: BlocBuilder<MomentsFeedBloc, MomentsFeedState>(
                builder: (ctx, state) {
                  return TabBarView(
                    children: [
                      _buildFeed(ctx, state, userId, userName, userAvatar),
                      _buildFeed(ctx, state, userId, userName, userAvatar,
                          followingOnly: true),
                    ],
                  );
                },
              ),
            ),
            bottomNavigationBar: _bottomNavigation(context),
            floatingActionButton: FloatingActionButton(
              backgroundColor: MomentsTheme.primary(context),
              elevation: 0,
              shape: const CircleBorder(),
              onPressed: () =>
                  _openCompose(context, userId, userName, userAvatar),
              child: const Icon(Icons.add, color: Colors.white, size: 30),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFeed(
    BuildContext context,
    MomentsFeedState state,
    String userId,
    String userName,
    String? userAvatar, {
    bool followingOnly = false,
  }) {
    if (state is MomentsFeedLoading) {
      return Center(
        child: CircularProgressIndicator(color: MomentsTheme.primary(context)),
      );
    }
    if (state is MomentsFeedError) {
      return Center(
        child: Text(
          state.message,
          style: TextStyle(color: MomentsTheme.textSecondary(context)),
        ),
      );
    }
    if (state is! MomentsFeedLoaded) return const SizedBox.shrink();

    final moments = followingOnly
        ? state.moments.where((m) => m.isFromAI || m.userId == userId).toList()
        : state.moments;

    if (moments.isEmpty) {
      return _emptyState(context,
          title: followingOnly ? '还没有关注动态' : '还没有动态',
          subtitle: followingOnly ? '你关注的人发布后会出现在这里' : '点击右下角按钮发布第一条动态');
    }

    return RefreshIndicator(
      color: MomentsTheme.primary(context),
      backgroundColor: MomentsTheme.cardBackground(context),
      onRefresh: () async {
        context.read<MomentsFeedBloc>().add(MomentsFeedRefresh());
        await Future.delayed(const Duration(milliseconds: 350));
      },
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        itemCount: moments.length,
        itemBuilder: (ctx, i) {
          final m = moments[i];
          return MomentCard(
            moment: m,
            isLiked: state.likedIds.contains(m.id),
            isBookmarked: state.bookmarkedIds.contains(m.id),
            onTap: () => _openDetail(ctx, m),
            onProfileTap: () => _openProfile(ctx, m),
            onLike: () => _toggleLike(ctx, m, userId, userName),
            onBookmark: () => _toggleBookmark(ctx, m, userId),
            onReply: () => _openReply(ctx, m, userId, userName, userAvatar),
            onRetweet: () =>
                _showRetweetSheet(ctx, m, userId, userName, userAvatar),
            onDelete:
                m.userId == userId ? () => _deleteMoment(ctx, m.id) : null,
          );
        },
      ),
    );
  }

  Widget _profileButton(
    BuildContext context,
    String userId,
    String userName,
    String? userAvatar,
  ) {
    return Center(
      child: GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => XMomentsProfileScreen(
              userId: userId,
              userName: userName,
              userAvatar: userAvatar,
            ),
          ),
        ),
        child: CircularAvatar(
          avatarPath: userAvatar,
          name: userName,
          radius: 17,
        ),
      ),
    );
  }

  Widget _circleIconButton(
    BuildContext context, {
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return IconButton(
      splashRadius: 22,
      icon: Icon(icon, color: MomentsTheme.textPrimary(context), size: 24),
      onPressed: onTap,
    );
  }

  Widget _bottomNavigation(BuildContext context) {
    final items = [
      (Icons.home_filled, '主页'),
      (Icons.search, '搜索'),
      (Icons.notifications_none_rounded, '通知'),
      (MomentsTheme.bookmark, '书签'),
    ];

    return DecoratedBox(
      decoration: BoxDecoration(
        color: MomentsTheme.cardBackground(context),
        border: Border(
          top: BorderSide(color: MomentsTheme.divider(context), width: 0.5),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 52,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(items.length, (index) {
              final active = _bottomIndex == index;
              return Expanded(
                child: InkResponse(
                  radius: 28,
                  onTap: () {
                    setState(() => _bottomIndex = index);
                    if (index == 1) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const XSearchScreen()),
                      );
                    } else if (index == 2) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const XNotificationsScreen()),
                      );
                    } else if (index == 3) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const XBookmarksScreen()),
                      );
                    }
                  },
                  child: Icon(
                    items[index].$1,
                    size: 27,
                    color: active
                        ? MomentsTheme.textPrimary(context)
                        : MomentsTheme.textSecondary(context),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  Widget _emptyState(BuildContext context, {String? title, String? subtitle}) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.article_outlined,
              size: 64, color: MomentsTheme.textSecondary(context)),
          const SizedBox(height: 16),
          Text(
            title ?? '还没有动态',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: MomentsTheme.textPrimary(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle ?? '点击右下角按钮发布第一条动态',
            style: TextStyle(
              fontSize: 14,
              color: MomentsTheme.textSecondary(context),
            ),
          ),
        ],
      ),
    );
  }

  void _openDetail(BuildContext context, Moment moment) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => XMomentDetailScreen(momentId: moment.id),
      ),
    ).then((_) {
      if (mounted) _feedBloc?.add(MomentsFeedRefresh());
    });
  }

  void _openProfile(BuildContext context, Moment moment) {
    final authState = context.read<AuthBloc>().state;
    final currentUser = authState is AuthAuthenticated ? authState.user : null;
    final avatar = moment.userId == currentUser?.id
        ? currentUser?.avatarUrl
        : moment.userAvatar;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => XMomentsProfileScreen(
          userId: moment.userId,
          userName: moment.userName,
          userAvatar: avatar,
        ),
      ),
    );
  }

  void _toggleLike(
      BuildContext context, Moment moment, String userId, String userName) {
    _feedBloc?.add(MomentLikeToggled(moment.id, userId, userName));
  }

  void _toggleBookmark(BuildContext context, Moment moment, String userId) {
    _feedBloc?.add(MomentBookmarked(moment.id, userId));
  }

  void _openReply(
    BuildContext context,
    Moment moment,
    String userId,
    String userName,
    String? userAvatar,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => XComposeMomentScreen(
          replyToMoment: moment,
          userId: userId,
          userName: userName,
          userAvatar: userAvatar,
        ),
      ),
    ).then((_) {
      if (mounted) _feedBloc?.add(MomentsFeedRefresh());
    });
  }

  void _showRetweetSheet(
    BuildContext context,
    Moment moment,
    String userId,
    String userName,
    String? userAvatar,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: MomentsTheme.cardBackground(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: MomentsTheme.divider(context),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: Icon(MomentsTheme.retweet,
                  color: MomentsTheme.retweetColor(context)),
              title: const Text('转发'),
              onTap: () {
                Navigator.pop(ctx);
                _feedBloc?.add(MomentRetweeted(moment, userId, userName));
              },
            ),
            ListTile(
              leading:
                  Icon(MomentsTheme.edit, color: MomentsTheme.primary(context)),
              title: const Text('引用转发'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => XComposeMomentScreen(
                      quoteMoment: moment,
                      userId: userId,
                      userName: userName,
                      userAvatar: userAvatar,
                    ),
                  ),
                ).then((_) {
                  if (mounted) _feedBloc?.add(MomentsFeedRefresh());
                });
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _openCompose(
    BuildContext context,
    String userId,
    String userName,
    String? userAvatar,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => XComposeMomentScreen(
          userId: userId,
          userName: userName,
          userAvatar: userAvatar,
        ),
      ),
    ).then((_) {
      if (!mounted) return;
      _feedBloc?.add(MomentsFeedRefresh());
    });
  }

  void _deleteMoment(BuildContext context, String momentId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除动态'),
        content: const Text('确定要删除这条动态吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _feedBloc?.add(MomentDeleted(momentId));
            },
            child:
                Text('删除', style: TextStyle(color: MomentsTheme.like(context))),
          ),
        ],
      ),
    );
  }
}
