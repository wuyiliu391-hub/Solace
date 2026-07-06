import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../blocs/auth/auth_bloc.dart';
import '../../../config/moments_theme.dart';
import '../../../models/moment.dart';
import '../../../repositories/local_storage_repository.dart';
import '../../../widgets/moments/moment_card.dart';
import 'x_compose_moment_screen.dart';
import 'x_moments_profile_screen.dart';

/// X 推特风格详情页（线程视图）
class XMomentDetailScreen extends StatefulWidget {
  final String momentId;

  const XMomentDetailScreen({super.key, required this.momentId});

  @override
  State<XMomentDetailScreen> createState() => _XMomentDetailScreenState();
}

class _XMomentDetailScreenState extends State<XMomentDetailScreen> {
  Moment? _moment;
  List<Moment> _parentChain = [];
  List<Moment> _replies = [];
  bool _isLoading = true;
  Set<String> _likedIds = {};
  Set<String> _bookmarkedIds = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final storage = context.read<LocalStorageRepository>();
    final authState = context.read<AuthBloc>().state;
    final userId = authState is AuthAuthenticated ? authState.user.id : '';

    try {
      // 加载主线程
      final chain = await storage.getThreadChain(widget.momentId);
      final moment = chain.isNotEmpty ? chain.last : null;

      // 加载回复
      final replies = await storage.getRepliesByMomentId(widget.momentId);

      // 浏览量 +1
      if (moment != null) {
        await storage.incrementViewCount(moment.id);
      }

      // 检查点赞/书签状态
      final likedIds = <String>{};
      final bookmarkedIds = <String>{};
      for (final m in [...chain, ...replies]) {
        if (m.likes.any((l) => l.userId == userId)) {
          likedIds.add(m.id);
        }
        if (await storage.isBookmarked(m.id, userId)) {
          bookmarkedIds.add(m.id);
        }
      }

      if (mounted) {
        setState(() {
          _moment = moment;
          _parentChain =
              chain.length > 1 ? chain.sublist(0, chain.length - 1) : [];
          _replies = replies;
          _likedIds = likedIds;
          _bookmarkedIds = bookmarkedIds;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthBloc>().state;
    final userId = authState is AuthAuthenticated ? authState.user.id : '';
    final userName =
        authState is AuthAuthenticated ? authState.user.nickname : '我';
    final userAvatar =
        authState is AuthAuthenticated ? authState.user.avatarUrl : null;

    return Scaffold(
      backgroundColor: MomentsTheme.background(context),
      appBar: AppBar(
        backgroundColor: MomentsTheme.cardBackground(context),
        elevation: 0,
        title: Text('帖子',
            style: TextStyle(
              color: MomentsTheme.textPrimary(context),
              fontWeight: FontWeight.bold,
            )),
        leading: IconButton(
          icon:
              Icon(Icons.arrow_back, color: MomentsTheme.textPrimary(context)),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(
                  color: MomentsTheme.primary(context)))
          : _moment == null
              ? Center(
                  child: Text('动态不存在',
                      style: TextStyle(
                          color: MomentsTheme.textSecondary(context))))
              : _buildContent(userId, userName, userAvatar),
      floatingActionButton: FloatingActionButton(
        backgroundColor: MomentsTheme.primary(context),
        onPressed: () => _openReply(userId, userName, userAvatar),
        child: const Icon(Icons.reply, color: Colors.white),
      ),
    );
  }

  Widget _buildContent(String userId, String userName, String? userAvatar) {
    return RefreshIndicator(
      color: MomentsTheme.primary(context),
      onRefresh: _loadData,
      child: CustomScrollView(
        slivers: [
          // 父帖链
          if (_parentChain.isNotEmpty)
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (ctx, i) => MomentCard(
                  moment: _parentChain[i],
                  displayType: MomentDisplayType.parentMoment,
                  isLiked: _likedIds.contains(_parentChain[i].id),
                  onTap: () => _navigateToDetail(_parentChain[i].id),
                  onProfileTap: () => _openProfile(_parentChain[i]),
                ),
                childCount: _parentChain.length,
              ),
            ),
          // 主帖详情
          SliverToBoxAdapter(
            child: MomentCard(
              moment: _moment!,
              displayType: MomentDisplayType.detail,
              isLiked: _likedIds.contains(_moment!.id),
              isBookmarked: _bookmarkedIds.contains(_moment!.id),
              onLike: () => _toggleLike(_moment!, userId, userName),
              onBookmark: () => _toggleBookmark(_moment!, userId),
              onReply: () => _openReply(userId, userName, userAvatar),
              onRetweet: () {},
              onProfileTap: () => _openProfile(_moment!),
              onDelete: _moment!.userId == userId
                  ? () => _deleteMoment(_moment!.id)
                  : null,
            ),
          ),
          // 分割线
          SliverToBoxAdapter(
            child: Container(
              height: 6,
              color: MomentsTheme.surface(context),
            ),
          ),
          // 回复列表
          if (_replies.isNotEmpty)
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (ctx, i) => MomentCard(
                  moment: _replies[i],
                  displayType: MomentDisplayType.reply,
                  isLiked: _likedIds.contains(_replies[i].id),
                  onTap: () => _navigateToDetail(_replies[i].id),
                  onProfileTap: () => _openProfile(_replies[i]),
                  onLike: () => _toggleLike(_replies[i], userId, userName),
                ),
                childCount: _replies.length,
              ),
            ),
        ],
      ),
    );
  }

  void _navigateToDetail(String momentId) {
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => XMomentDetailScreen(momentId: momentId)),
    ).then((_) => _loadData());
  }

  void _openProfile(Moment moment) {
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

  void _openReply(String userId, String userName, String? userAvatar) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => XComposeMomentScreen(
          replyToMoment: _moment,
          userId: userId,
          userName: userName,
          userAvatar: userAvatar,
        ),
      ),
    ).then((_) => _loadData());
  }

  Future<void> _toggleLike(
      Moment moment, String userId, String userName) async {
    final storage = context.read<LocalStorageRepository>();
    final isLiked = _likedIds.contains(moment.id);
    final newLikes = List<MomentLike>.from(moment.likes);

    if (isLiked) {
      newLikes.removeWhere((l) => l.userId == userId);
      _likedIds.remove(moment.id);
    } else {
      newLikes.add(MomentLike(
          userId: userId, userName: userName, createdAt: DateTime.now()));
      _likedIds.add(moment.id);
    }

    await storage.saveMoment(moment.copyWith(likes: newLikes));
    setState(() {});
  }

  Future<void> _toggleBookmark(Moment moment, String userId) async {
    final storage = context.read<LocalStorageRepository>();
    final isBookmarked = _bookmarkedIds.contains(moment.id);

    if (isBookmarked) {
      await storage.removeBookmark(moment.id, userId);
      _bookmarkedIds.remove(moment.id);
    } else {
      await storage.addBookmark(moment.id, userId);
      _bookmarkedIds.add(moment.id);
    }
    setState(() {});
  }

  Future<void> _deleteMoment(String momentId) async {
    final storage = context.read<LocalStorageRepository>();
    await storage.deleteMoment(momentId);
    if (mounted) Navigator.pop(context);
  }
}
