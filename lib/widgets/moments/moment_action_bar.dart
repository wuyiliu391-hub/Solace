import 'package:flutter/material.dart';
import '../../config/moments_theme.dart';
import '../../models/moment.dart';

/// 推文操作栏（评论/转发/点赞/浏览/书签/分享）
class MomentActionBar extends StatefulWidget {
  final Moment moment;
  final MomentDisplayType displayType;
  final bool isLiked;
  final bool isRetweeted;
  final bool isBookmarked;
  final VoidCallback? onReply;
  final VoidCallback? onRetweet;
  final VoidCallback? onLike;
  final VoidCallback? onBookmark;
  final VoidCallback? onShare;

  const MomentActionBar({
    super.key,
    required this.moment,
    this.displayType = MomentDisplayType.moment,
    this.isLiked = false,
    this.isRetweeted = false,
    this.isBookmarked = false,
    this.onReply,
    this.onRetweet,
    this.onLike,
    this.onBookmark,
    this.onShare,
  });

  @override
  State<MomentActionBar> createState() => _MomentActionBarState();
}

class _MomentActionBarState extends State<MomentActionBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _likeAnimController;
  late Animation<double> _likeScale;

  @override
  void initState() {
    super.initState();
    _likeAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _likeScale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.3), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.3, end: 1.0), weight: 50),
    ]).animate(
        CurvedAnimation(parent: _likeAnimController, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _likeAnimController.dispose();
    super.dispose();
  }

  void _onLikeTap() {
    _likeAnimController.forward(from: 0.0);
    widget.onLike?.call();
  }

  String _formatCount(int count) {
    if (count >= 100000000) return '${(count / 100000000).toStringAsFixed(1)}亿';
    if (count >= 10000) return '${(count / 10000).toStringAsFixed(1)}万';
    if (count > 0) return count.toString();
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final iconColor = MomentsTheme.iconDefault(context);
    final isDetail = widget.displayType == MomentDisplayType.detail;

    return Padding(
      padding: EdgeInsets.only(
        left: isDetail ? 4 : 0,
        right: isDetail ? 4 : 0,
        top: 8,
        bottom: 0,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _actionButton(
            icon: MomentsTheme.reply,
            count: widget.moment.replyCount,
            color: iconColor,
            activeColor: MomentsTheme.replyColor(context),
            isActive: false,
            onTap: widget.onReply,
          ),
          _actionButton(
            icon: MomentsTheme.retweet,
            count: widget.moment.retweetCount,
            color: iconColor,
            activeColor: MomentsTheme.retweetColor(context),
            isActive: widget.isRetweeted,
            onTap: widget.onRetweet,
          ),
          _likeButton(iconColor),
          _viewCount(iconColor),
          _actionButton(
            icon: MomentsTheme.bookmark,
            count: 0,
            color: iconColor,
            activeColor: MomentsTheme.primary(context),
            isActive: widget.isBookmarked,
            onTap: widget.onBookmark,
            showCount: false,
          ),
          _iconOnlyButton(
            icon: Icons.ios_share_outlined,
            color: iconColor,
            activeColor: MomentsTheme.primary(context),
            onTap: widget.onShare,
          ),
        ],
      ),
    );
  }

  Widget _likeButton(Color iconColor) {
    final color = widget.isLiked ? MomentsTheme.like(context) : iconColor;
    return InkResponse(
      onTap: _onLikeTap,
      radius: 22,
      splashColor: MomentsTheme.like(context).withOpacity(0.12),
      highlightColor: MomentsTheme.like(context).withOpacity(0.08),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 32,
            height: 32,
            child: Center(
              child: AnimatedBuilder(
                animation: _likeScale,
                builder: (ctx, child) => Transform.scale(
                  scale: _likeScale.value,
                  child: Icon(
                    widget.isLiked
                        ? MomentsTheme.heartFill
                        : MomentsTheme.heartEmpty,
                    size: 18,
                    color: color,
                  ),
                ),
              ),
            ),
          ),
          if (widget.moment.likeCount > 0) ...[
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              transitionBuilder: (child, anim) =>
                  ScaleTransition(scale: anim, child: child),
              child: Text(
                _formatCount(widget.moment.likeCount),
                key: ValueKey(widget.moment.likeCount),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _viewCount(Color iconColor) {
    final label = _formatCount(widget.moment.viewCount);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 32,
          height: 32,
          child: Center(
            child: Icon(Icons.bar_chart_rounded, size: 19, color: iconColor),
          ),
        ),
        if (label.isNotEmpty)
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: iconColor,
            ),
          ),
      ],
    );
  }

  Widget _actionButton({
    required IconData icon,
    required int count,
    required Color color,
    required Color activeColor,
    required bool isActive,
    VoidCallback? onTap,
    bool showCount = true,
  }) {
    final effectiveColor = isActive ? activeColor : color;
    return InkResponse(
      onTap: onTap,
      radius: 22,
      splashColor: activeColor.withOpacity(0.12),
      highlightColor: activeColor.withOpacity(0.08),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 32,
            height: 32,
            child: Center(
              child: Icon(icon, size: 18, color: effectiveColor),
            ),
          ),
          if (showCount && count > 0)
            Text(
              _formatCount(count),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: effectiveColor,
              ),
            ),
        ],
      ),
    );
  }

  Widget _iconOnlyButton({
    required IconData icon,
    required Color color,
    required Color activeColor,
    VoidCallback? onTap,
  }) {
    return InkResponse(
      onTap: onTap,
      radius: 22,
      splashColor: activeColor.withOpacity(0.12),
      highlightColor: activeColor.withOpacity(0.08),
      child: SizedBox(
        width: 32,
        height: 32,
        child: Center(child: Icon(icon, size: 18, color: color)),
      ),
    );
  }
}
