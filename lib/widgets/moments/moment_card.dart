import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../config/moments_theme.dart';
import '../../models/moment.dart';
import 'circular_avatar.dart';
import 'moment_action_bar.dart';
import 'moment_image_grid.dart';
import 'moment_stats_bar.dart';
import 'url_text.dart';

/// X 推特风格推文卡片（4种显示模式）
class MomentCard extends StatelessWidget {
  final Moment moment;
  final MomentDisplayType displayType;
  final bool isLiked;
  final bool isRetweeted;
  final bool isBookmarked;
  final Moment? parentMoment; // 回复模式下的父帖
  final Moment? quoteMoment; // 引用转发的原帖
  final VoidCallback? onTap;
  final VoidCallback? onProfileTap;
  final VoidCallback? onReply;
  final VoidCallback? onRetweet;
  final VoidCallback? onLike;
  final VoidCallback? onBookmark;
  final VoidCallback? onShare;
  final VoidCallback? onDelete;
  final VoidCallback? onQuoteTap;
  final ValueChanged<String>? onMentionTap;
  final ValueChanged<String>? onHashtagTap;

  const MomentCard({
    super.key,
    required this.moment,
    this.displayType = MomentDisplayType.moment,
    this.isLiked = false,
    this.isRetweeted = false,
    this.isBookmarked = false,
    this.parentMoment,
    this.quoteMoment,
    this.onTap,
    this.onProfileTap,
    this.onReply,
    this.onRetweet,
    this.onLike,
    this.onBookmark,
    this.onShare,
    this.onDelete,
    this.onQuoteTap,
    this.onMentionTap,
    this.onHashtagTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: MomentsTheme.cardBackground(context),
      child: InkWell(
        onTap: onTap,
        onLongPress: () => _showOptions(context),
        splashColor: MomentsTheme.textPrimary(context).withOpacity(0.04),
        highlightColor: MomentsTheme.textPrimary(context).withOpacity(0.03),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 转发提示条
            if (moment.isRetweet) _retweetBanner(context),
            // 主体内容
            if (displayType == MomentDisplayType.detail)
              _detailBody(context)
            else
              _feedBody(context),
            // 分割线（非父帖预览模式）
            if (displayType != MomentDisplayType.parentMoment)
              Divider(
                height: 0.5,
                thickness: 0.5,
                color: MomentsTheme.divider(context),
              ),
          ],
        ),
      ),
    );
  }

  /// 转发提示条
  Widget _retweetBanner(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 56, top: 8, right: 16),
      child: Row(
        children: [
          Icon(MomentsTheme.retweet,
              size: 14, color: MomentsTheme.textSecondary(context)),
          const SizedBox(width: 8),
          Text(
            '${moment.userName} 转发了',
            style: TextStyle(
              fontSize: 13,
              color: MomentsTheme.textSecondary(context),
            ),
          ),
        ],
      ),
    );
  }

  /// 信息流卡片布局
  Widget _feedBody(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 头像
          CircularAvatar(
            avatarPath: moment.userAvatar,
            name: moment.userName,
            radius: 21,
            onTap: onProfileTap,
          ),
          const SizedBox(width: 10),
          // 内容区
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 用户信息行：@handle + 时间 + 菜单
                _userRow(context),
                // 回复标识
                if (moment.isReply && displayType == MomentDisplayType.reply)
                  _replyIndicator(context),
                // 正文
                const SizedBox(height: 2),
                UrlText(
                  text: moment.content,
                  style: TextStyle(
                    fontSize: 15.5,
                    height: 1.34,
                    letterSpacing: -0.1,
                    color: MomentsTheme.textPrimary(context),
                  ),
                  maxLines: displayType == MomentDisplayType.parentMoment
                      ? 3
                      : null,
                  onMentionTap: onMentionTap,
                  onHashtagTap: onHashtagTap,
                ),
                // 图片
                if (moment.hasImages)
                  MomentImageGrid(images: moment.images),
                // 引用转发卡片
                if (moment.isQuote && quoteMoment != null)
                  _quoteCard(context),
                // 操作栏
                MomentActionBar(
                  moment: moment,
                  displayType: displayType,
                  isLiked: isLiked,
                  isRetweeted: isRetweeted,
                  isBookmarked: isBookmarked,
                  onReply: onReply,
                  onRetweet: onRetweet,
                  onLike: onLike,
                  onBookmark: onBookmark,
                  onShare: onShare,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 详情页布局
  Widget _detailBody(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 用户信息行
          _detailUserRow(context),
          // 正文（大号）
          const SizedBox(height: 12),
          UrlText(
            text: moment.content,
            style: TextStyle(
              fontSize: 18,
              color: MomentsTheme.textPrimary(context),
              height: 1.4,
            ),
            onMentionTap: onMentionTap,
            onHashtagTap: onHashtagTap,
          ),
          // 图片
          if (moment.hasImages) ...[
            const SizedBox(height: 12),
            MomentImageGrid(images: moment.images),
          ],
          // 引用转发卡片
          if (moment.isQuote && quoteMoment != null) ...[
            const SizedBox(height: 12),
            _quoteCard(context),
          ],
          // 时间戳
          const SizedBox(height: 12),
          Text(
            _formatFullTime(moment.createdAt),
            style: TextStyle(
              fontSize: 14,
              color: MomentsTheme.textSecondary(context),
            ),
          ),
          // 统计栏
          const SizedBox(height: 8),
          MomentStatsBar(moment: moment),
          // 操作栏
          const SizedBox(height: 4),
          Divider(height: 0.5, color: MomentsTheme.divider(context)),
          MomentActionBar(
            moment: moment,
            displayType: displayType,
            isLiked: isLiked,
            isRetweeted: isRetweeted,
            isBookmarked: isBookmarked,
            onReply: onReply,
            onRetweet: onRetweet,
            onLike: onLike,
            onBookmark: onBookmark,
            onShare: onShare,
          ),
          Divider(height: 0.5, color: MomentsTheme.divider(context)),
        ],
      ),
    );
  }

  /// 用户信息行（信息流模式：昵称 + 蓝标 + @handle + ·时间）
  Widget _userRow(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // 昵称（加粗）
              Text(
                moment.userName,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: MomentsTheme.textPrimary(context),
                ),
              ),
              // 认证蓝标（紧贴昵称右侧）
              if (moment.isFromAI || moment.userVerified) ...[
                const SizedBox(width: 2),
                Icon(MomentsTheme.blueTick,
                    size: 14, color: MomentsTheme.primary(context)),
              ],
              // @handle（蓝色链接色）
              if (moment.userHandle != null) ...[
                const SizedBox(width: 4),
                Text(
                  moment.userHandle!,
                  style: TextStyle(
                    fontSize: 14,
                    color: MomentsTheme.textSecondary(context),
                  ),
                ),
              ],
              // 性别图标
              if (moment.userGender != null) ...[
                const SizedBox(width: 2),
                Icon(
                  _genderIcon(moment.userGender),
                  size: 14,
                  color: _genderColor(moment.userGender),
                ),
              ],
              // · 时间
              Text(
                ' · ${_formatRelativeTime(moment.createdAt)}',
                style: TextStyle(
                  fontSize: 14,
                  color: MomentsTheme.textSecondary(context),
                ),
              ),
            ],
          ),
        ),
        // 竖向三点菜单
        GestureDetector(
          onTap: () => _showOptions(context),
          child: Icon(
            Icons.more_horiz,
            size: 20,
            color: MomentsTheme.textSecondary(context),
          ),
        ),
      ],
    );
  }

  /// 用户信息行（详情模式：昵称 + 蓝标 + @handle）
  Widget _detailUserRow(BuildContext context) {
    return Row(
      children: [
        CircularAvatar(
          avatarPath: moment.userAvatar,
          name: moment.userName,
          radius: 22,
          onTap: onProfileTap,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    moment.userName,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: MomentsTheme.textPrimary(context),
                    ),
                  ),
                  if (moment.isFromAI || moment.userVerified) ...[
                    const SizedBox(width: 2),
                    Icon(MomentsTheme.blueTick,
                        size: 16, color: MomentsTheme.primary(context)),
                  ],
                  if (moment.userGender != null) ...[
                    const SizedBox(width: 2),
                    Icon(_genderIcon(moment.userGender),
                        size: 16, color: _genderColor(moment.userGender)),
                  ],
                ],
              ),
              Text(
                moment.userHandle ?? '@${moment.userName}',
                style: TextStyle(
                  fontSize: 14,
                  color: MomentsTheme.textSecondary(context),
                ),
              ),
            ],
          ),
        ),
        IconButton(
          icon: Icon(Icons.more_vert,
              color: MomentsTheme.textSecondary(context)),
          onPressed: () => _showOptions(context),
        ),
      ],
    );
  }

  /// 回复标识
  Widget _replyIndicator(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        '回复 ${parentMoment?.userHandle ?? '@${parentMoment?.userName ?? ''}'}',
        style: TextStyle(
          fontSize: 14,
          color: MomentsTheme.textSecondary(context),
        ),
      ),
    );
  }

  /// 引用转发卡片
  Widget _quoteCard(BuildContext context) {
    return GestureDetector(
      onTap: onQuoteTap,
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(
            color: MomentsTheme.divider(context),
            width: 0.5,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircularAvatar(
                  avatarPath: quoteMoment!.userAvatar,
                  name: quoteMoment!.userName,
                  radius: 10,
                ),
                const SizedBox(width: 6),
                Text(
                  quoteMoment!.userName,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: MomentsTheme.textPrimary(context),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  quoteMoment!.userHandle ?? '@${quoteMoment!.userName}',
                  style: TextStyle(
                    fontSize: 13,
                    color: MomentsTheme.textSecondary(context),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              quoteMoment!.content,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                color: MomentsTheme.textPrimary(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showOptions(BuildContext context) {
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
              leading: Icon(MomentsTheme.link,
                  color: MomentsTheme.textPrimary(context)),
              title: const Text('复制链接'),
              onTap: () {
                Navigator.pop(ctx);
                Clipboard.setData(
                    ClipboardData(text: 'moment/${moment.id}'));
              },
            ),
            ListTile(
              leading: Icon(MomentsTheme.bookmark,
                  color: MomentsTheme.textPrimary(context)),
              title: Text(isBookmarked ? '取消书签' : '添加书签'),
              onTap: () {
                Navigator.pop(ctx);
                onBookmark?.call();
              },
            ),
            ListTile(
              leading: Icon(Icons.share,
                  color: MomentsTheme.textPrimary(context)),
              title: const Text('分享'),
              onTap: () {
                Navigator.pop(ctx);
                onShare?.call();
              },
            ),
            if (onDelete != null) ...[
              Divider(height: 0.5, color: MomentsTheme.divider(context)),
              ListTile(
                leading: Icon(MomentsTheme.delete,
                    color: MomentsTheme.like(context)),
                title: Text('删除',
                    style: TextStyle(color: MomentsTheme.like(context))),
                onTap: () {
                  Navigator.pop(ctx);
                  onDelete?.call();
                },
              ),
            ],
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  IconData _genderIcon(String? gender) {
    switch (gender) {
      case 'male':
        return Icons.male;
      case 'female':
        return Icons.female;
      case 'other':
        return Icons.transgender;
      default:
        return Icons.person;
    }
  }

  Color _genderColor(String? gender) {
    switch (gender) {
      case 'male':
        return const Color(0xFF1DA1F2);
      case 'female':
        return const Color(0xFFF472B6);
      case 'other':
        return const Color(0xFF9C5A9A);
      default:
        return Colors.grey;
    }
  }

  String _formatRelativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return '${diff.inSeconds}秒';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟';
    if (diff.inHours < 24) return '${diff.inHours}小时';
    if (diff.inDays < 30) return '${diff.inDays}天';
    if (diff.inDays < 365) return '${(diff.inDays / 30).floor()}月';
    return '${(diff.inDays / 365).floor()}年';
  }

  String _formatFullTime(DateTime dt) {
    final hour = dt.hour;
    final period = hour < 12 ? '上午' : '下午';
    final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    return '${dt.month}月${dt.day}日 · $period${displayHour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
