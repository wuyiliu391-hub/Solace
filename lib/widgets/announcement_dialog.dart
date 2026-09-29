import 'package:flutter/material.dart';
import '../models/announcement.dart';

class AnnouncementDialog extends StatelessWidget {
  final List<Announcement> announcements;

  const AnnouncementDialog({super.key, required this.announcements});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380, maxHeight: 500),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
              child: Row(
                children: [
                  Icon(Icons.campaign_rounded, color: Theme.of(context).colorScheme.primary, size: 22),
                  const SizedBox(width: 8),
                  Text(
                    '公告',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('关闭'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView.separated(
                padding: const EdgeInsets.all(20),
                shrinkWrap: true,
                itemCount: announcements.length,
                separatorBuilder: (_, __) => const SizedBox(height: 16),
                itemBuilder: (context, index) {
                  final ann = announcements[index];
                  return _AnnouncementCard(announcement: ann);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnnouncementCard extends StatelessWidget {
  final Announcement announcement;
  const _AnnouncementCard({required this.announcement});

  IconData get _typeIcon {
    switch (announcement.type) {
      case 'update':
        return Icons.system_update_rounded;
      case 'important':
        return Icons.warning_amber_rounded;
      default:
        return Icons.info_outline_rounded;
    }
  }

  Color _typeColor(ThemeData theme) {
    switch (announcement.type) {
      case 'update':
        return Colors.green;
      case 'important':
        return Colors.orange;
      default:
        return theme.colorScheme.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final typeColor = _typeColor(theme);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: typeColor.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: typeColor.withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_typeIcon, size: 18, color: typeColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  announcement.title,
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              if (announcement.isImportant)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text('重要', style: TextStyle(fontSize: 10, color: Colors.orange.shade800, fontWeight: FontWeight.w600)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            announcement.content,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.5),
          ),
          const SizedBox(height: 8),
          Text(
            announcement.date,
            style: theme.textTheme.labelSmall?.copyWith(color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
