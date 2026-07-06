import 'package:flutter/material.dart';
import '../../config/moments_theme.dart';
import '../../models/moment.dart';

/// 推文数据统计栏（浏览量 / 转发 / 引用 / 点赞）
class MomentStatsBar extends StatelessWidget {
  final Moment moment;

  const MomentStatsBar({super.key, required this.moment});

  String _formatCount(int count) {
    if (count >= 100000000) return '${(count / 100000000).toStringAsFixed(1)}亿';
    if (count >= 10000) return '${(count / 10000).toStringAsFixed(1)}万';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}k';
    return count.toString();
  }

  @override
  Widget build(BuildContext context) {
    final hasAny = moment.viewCount > 0 ||
        moment.retweetCount > 0 ||
        moment.likeCount > 0;
    if (!hasAny) return const SizedBox.shrink();

    final countStyle = TextStyle(
      color: MomentsTheme.textPrimary(context),
      fontSize: 14,
      fontWeight: FontWeight.bold,
    );
    final labelStyle = TextStyle(
      color: MomentsTheme.textSecondary(context),
      fontSize: 14,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Wrap(
        spacing: 16,
        children: [
          if (moment.retweetCount > 0)
            RichText(
              text: TextSpan(children: [
                TextSpan(text: _formatCount(moment.retweetCount), style: countStyle),
                TextSpan(text: ' 转推', style: labelStyle),
              ]),
            ),
          if (moment.likeCount > 0)
            RichText(
              text: TextSpan(children: [
                TextSpan(text: _formatCount(moment.likeCount), style: countStyle),
                TextSpan(text: ' 点赞', style: labelStyle),
              ]),
            ),
          if (moment.viewCount > 0)
            Text(_formatCount(moment.viewCount), style: labelStyle),
        ],
      ),
    );
  }
}
