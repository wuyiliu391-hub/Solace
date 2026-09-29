import 'package:flutter/material.dart';
import '../../config/wechat_theme.dart';
import 'wx_bubble.dart';

/// 微信会话列表项 — 1:1 还原
///
/// 结构（来自 item_main_chat.xml）：
/// 高 60dp | 头像 39dp(框45) | 名字 14sp | 摘要 10sp | 右侧时间+免打扰
/// 底部 hairline 0.5dp 从 x=58dp 起 | 未读红点右上角
class WxConversationTile extends StatelessWidget {
  final String name;
  final String lastMessage;
  final String time;
  final ImageProvider? avatar;
  final int unreadCount;
  final bool muted;     // 消息免打扰
  final bool pinned;    // 置顶（背景变浅灰）
  final VoidCallback? onTap;

  const WxConversationTile({
    super.key,
    required this.name,
    required this.lastMessage,
    required this.time,
    this.avatar,
    this.unreadCount = 0,
    this.muted = false,
    this.pinned = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: pinned ? const Color(0xFFF1F1F1) : WxColors.listBg,
      child: InkWell(
        onTap: onTap,
        highlightColor: WxColors.cellPressed,
        child: SizedBox(
          height: 60,
          child: Row(
            children: [
              const SizedBox(width: 9),
              // 头像 + 未读角标
              Stack(
                clipBehavior: Clip.none,
                children: [
                  WxAvatar(image: avatar, text: name, size: 39),
                  if (unreadCount > 0)
                    Positioned(
                      right: -5,
                      top: -4,
                      child: _UnreadBadge(count: unreadCount, muted: muted),
                    ),
                ],
              ),
              const SizedBox(width: 10),
              // 名字 + 摘要
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 16, color: WxColors.textBlack),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      lastMessage,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14, color: WxColors.lastMessage),
                    ),
                  ],
                ),
              ),
              // 时间 + 免打扰
              Padding(
                padding: const EdgeInsets.only(right: 13),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(time,
                        style: const TextStyle(
                            fontSize: 12, color: WxColors.lastMessage)),
                    const SizedBox(height: 3),
                    if (muted)
                      const Icon(Icons.volume_off,
                          size: 16, color: WxColors.textHint)
                    else
                      const SizedBox(height: 16),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 未读角标（免打扰时为灰点、无数字）
class _UnreadBadge extends StatelessWidget {
  final int count;
  final bool muted;
  const _UnreadBadge({required this.count, this.muted = false});

  @override
  Widget build(BuildContext context) {
    if (muted) {
      // 免打扰：只显示小红点
      return Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(
          color: WxColors.badge,
          shape: BoxShape.circle,
        ),
      );
    }
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
      child: Text(
        text,
        style: const TextStyle(
            color: Colors.white, fontSize: 11, height: 1),
      ),
    );
  }
}
