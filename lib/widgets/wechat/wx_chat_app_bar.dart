import 'package:flutter/material.dart';
import '../../config/wechat_theme.dart';

/// 微信聊天详情页顶部导航栏 — 1:1 还原
///
/// 结构（activity_chatmsg.xml）：
/// [返回箭头] [昵称 + 未读数 + 免打扰/听筒图标] [更多按钮]
/// 背景 wx_top_bg(#EAEAEA)，底部 0.3dp 分割线
class WxChatAppBar extends StatelessWidget {
  final String title;
  final int? unreadCount;     // 显示在标题右侧的小红点数字
  final bool muted;          // 消息免打扰
  final bool earpiece;       // 听筒模式
  final VoidCallback? onBack;
  final VoidCallback? onMore;

  const WxChatAppBar({
    super.key,
    required this.title,
    this.unreadCount,
    this.muted = false,
    this.earpiece = false,
    this.onBack,
    this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: WxColors.chatBg,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 状态栏占位
          SizedBox(height: MediaQuery.of(context).padding.top),
          // 导航行
          SizedBox(
            height: WxDimens.navHeight,
            child: Row(
              children: [
                // 返回
                IconButton(
                  onPressed: onBack,
                  padding: const EdgeInsets.only(left: 4),
                  icon: const Icon(Icons.chevron_left,
                      size: 30, color: WxColors.textBlack),
                  visualDensity: VisualDensity.compact,
                ),
                // 标题区（昵称 + 图标）
                Expanded(
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(title,
                            style: const TextStyle(
                                fontSize: 16,
                                color: WxColors.textBlack,
                                fontWeight: FontWeight.w500)),
                        if (unreadCount != null && unreadCount! > 0) ...[
                          const SizedBox(width: 6),
                          _UnreadChip(count: unreadCount!),
                        ],
                        if (muted) ...[
                          const SizedBox(width: 4),
                          const Icon(Icons.notifications_off,
                              size: 14, color: WxColors.textGray),
                        ],
                        if (earpiece) ...[
                          const SizedBox(width: 4),
                          const Icon(Icons.hearing,
                              size: 14, color: WxColors.textGray),
                        ],
                      ],
                    ),
                  ),
                ),
                // 更多
                IconButton(
                  onPressed: onMore,
                  icon: const Icon(Icons.more_horiz,
                      size: 22, color: WxColors.textBlack),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
          // 底部 hairline
          Container(height: WxDimens.divider, color: WxColors.divider),
        ],
      ),
    );
  }
}

class _UnreadChip extends StatelessWidget {
  final int count;
  const _UnreadChip({required this.count});

  @override
  Widget build(BuildContext context) {
    final text = count > 99 ? '99+' : '$count';
    return Container(
      constraints: const BoxConstraints(minWidth: 16),
      height: 16,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: WxColors.badge,
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: Text(text,
          style: const TextStyle(color: Colors.white, fontSize: 11, height: 1)),
    );
  }
}
