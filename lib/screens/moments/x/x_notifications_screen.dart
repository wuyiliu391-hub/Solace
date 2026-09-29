import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../config/moments_theme.dart';
import '../../../models/moment_notification.dart';
import '../../../repositories/local_storage_repository.dart';
import 'x_moment_detail_screen.dart';

/// X 推特风格通知页面
class XNotificationsScreen extends StatefulWidget {
  const XNotificationsScreen({super.key});

  @override
  State<XNotificationsScreen> createState() => _XNotificationsScreenState();
}

class _XNotificationsScreenState extends State<XNotificationsScreen> {
  List<MomentNotification> _notifications = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    final storage = context.read<LocalStorageRepository>();
    final notifications = await storage.getMomentNotifications();
    if (mounted) {
      setState(() {
        _notifications = notifications;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MomentsTheme.background(context),
      appBar: AppBar(
        backgroundColor: MomentsTheme.cardBackground(context),
        elevation: 0,
        title: Text('通知',
            style: TextStyle(
              color: MomentsTheme.textPrimary(context),
              fontWeight: FontWeight.bold,
            )),
        leading: IconButton(
          icon: Icon(Icons.arrow_back,
              color: MomentsTheme.textPrimary(context)),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(
                  color: MomentsTheme.primary(context)))
          : _notifications.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.notifications_outlined,
                          size: 64,
                          color: MomentsTheme.textSecondary(context)),
                      const SizedBox(height: 16),
                      Text('还没有通知',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: MomentsTheme.textPrimary(context),
                          )),
                      const SizedBox(height: 8),
                      Text('当有人互动你的动态时会显示在这里',
                          style: TextStyle(
                            fontSize: 14,
                            color: MomentsTheme.textSecondary(context),
                          )),
                    ],
                  ),
                )
              : RefreshIndicator(
                  color: MomentsTheme.primary(context),
                  onRefresh: _loadNotifications,
                  child: ListView.builder(
                    itemCount: _notifications.length,
                    itemBuilder: (ctx, i) =>
                        _notificationTile(_notifications[i]),
                  ),
                ),
    );
  }

  Widget _notificationTile(MomentNotification n) {
    final iconData = _iconForType(n.type);
    final iconColor = _colorForType(n.type);
    final actionText = _actionText(n.type);

    return InkWell(
      onTap: () => _onNotificationTap(n),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: n.isRead
              ? MomentsTheme.cardBackground(context)
              : MomentsTheme.primary(context).withOpacity(0.05),
          border: Border(
            bottom: BorderSide(
                color: MomentsTheme.divider(context), width: 0.5),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(iconData, color: iconColor, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 14,
                        backgroundColor:
                            MomentsTheme.primary(context).withOpacity(0.2),
                        child: Text(
                          n.actorName.isNotEmpty ? n.actorName[0] : '?',
                          style: TextStyle(
                            fontSize: 12,
                            color: MomentsTheme.primary(context),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: RichText(
                          text: TextSpan(
                            children: [
                              TextSpan(
                                text: n.actorName,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: MomentsTheme.textPrimary(context),
                                ),
                              ),
                              TextSpan(
                                text: ' $actionText',
                                style: TextStyle(
                                  fontSize: 14,
                                  color:
                                      MomentsTheme.textSecondary(context),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (n.content != null && n.content!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      n.content!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        color: MomentsTheme.textSecondary(context),
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    _formatTime(n.createdAt),
                    style: TextStyle(
                      fontSize: 12,
                      color: MomentsTheme.textSecondary(context),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconForType(MomentNotificationType type) {
    switch (type) {
      case MomentNotificationType.like:
        return MomentsTheme.heartFill;
      case MomentNotificationType.reply:
        return MomentsTheme.reply;
      case MomentNotificationType.retweet:
        return MomentsTheme.retweet;
      case MomentNotificationType.mention:
        return Icons.alternate_email;
    }
  }

  Color _colorForType(MomentNotificationType type) {
    switch (type) {
      case MomentNotificationType.like:
        return MomentsTheme.like(context);
      case MomentNotificationType.reply:
        return MomentsTheme.replyColor(context);
      case MomentNotificationType.retweet:
        return MomentsTheme.retweetColor(context);
      case MomentNotificationType.mention:
        return MomentsTheme.primary(context);
    }
  }

  String _actionText(MomentNotificationType type) {
    switch (type) {
      case MomentNotificationType.like:
        return '赞了你的动态';
      case MomentNotificationType.reply:
        return '回复了你的动态';
      case MomentNotificationType.retweet:
        return '转发了你的动态';
      case MomentNotificationType.mention:
        return '在动态中提到了你';
    }
  }

  void _onNotificationTap(MomentNotification n) async {
    final storage = context.read<LocalStorageRepository>();
    if (!n.isRead) {
      await storage.markMomentNotificationRead(n.id);
    }
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => XMomentDetailScreen(momentId: n.momentId)),
      ).then((_) => _loadNotifications());
    }
  }

  String _formatTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes}分钟前';
    if (diff.inDays < 1) return '${diff.inHours}小时前';
    if (diff.inDays < 30) return '${diff.inDays}天前';
    return '${dt.month}月${dt.day}日';
  }
}
