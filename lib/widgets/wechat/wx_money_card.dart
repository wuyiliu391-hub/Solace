/// 微信红包 / 转账消息卡片
///
/// 数据来源：刷圈兔 9.6.0 逆向
///   - res/layout/received_red_packet.xml
///   - res/layout/sent_red_packet.xml
///   - res/layout/received_transfer.xml
///   - res/layout/sent_transfer.xml
///   - res/values/colors.xml: wx_hongbao / wx_hongbaoline / wx_hongbaoxiao
/// 还原要点：
///   - 卡片宽 220dp，红包高 70dp，转账高 63dp
///   - 左侧图标 32dp(红包) / 28dp(转账)
///   - 底部 20dp 高的"微信红包"/"微信转账"标签条，顶部 0.3dp 橙色分割线
///   - 主文字色 #FEFEFE（橙底白字），标签文字 #FDF2DF
///   - 橙色描边 #F4AB5D
library;

import 'package:flutter/material.dart';

import '../../config/wechat_theme.dart';
import 'wx_bubble.dart';

/// 红包/转账卡片类型
enum WxMoneyKind { redPacket, transfer }

/// 红包/转账卡片
///
/// 用法：作为 [WxMessageRow] 的 bubble 参数传入，或直接放入聊天列表。
/// 卡片本身不带头像和尾巴，由外层 [WxMessageRow] 负责头像和布局。
class WxMoneyCard extends StatelessWidget {
  const WxMoneyCard({
    super.key,
    required this.kind,
    required this.isMe,
    this.title,
    this.amount,
    this.onTap,
  });

  /// 红包/转账
  final WxMoneyKind kind;

  /// 是否是自己发送（决定背景色和文字对齐）
  final bool isMe;

  /// 红包祝福语 / 转账说明
  final String? title;

  /// 转账金额（红包可不传）
  final String? amount;

  /// 点击回调
  final VoidCallback? onTap;

  static const double _cardWidth = 220.0;
  static const double _redPacketHeight = 70.0;
  static const double _transferHeight = 63.0;
  static const double _footerHeight = 20.0;

  @override
  Widget build(BuildContext context) {
    final isRed = kind == WxMoneyKind.redPacket;
    final height = isRed ? _redPacketHeight : _transferHeight;
    final defaultTitle = isRed ? '恭喜发财，大吉大利' : '微信转账';
    final displayTitle = title?.isNotEmpty == true ? title! : defaultTitle;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: _cardWidth,
        height: height,
        decoration: BoxDecoration(
          color: WxColors.redPacketBg,
          borderRadius: BorderRadius.circular(WxDimens.bubbleRadius),
          border: Border.all(color: WxColors.redPacketLine, width: 0.5),
        ),
        child: Column(
          children: [
            // 上半部分：图标 + 文字
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(left: 15, right: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // 左侧图标
                    _buildIcon(isRed),
                    const SizedBox(width: 10),
                    // 文字区
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (isRed)
                            Text(
                              displayTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: WxColors.redPacketLine,
                              ),
                            )
                          else ...[
                            if (amount != null)
                              Text(
                                amount!,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: WxColors.redPacketLine,
                                ),
                              ),
                            Text(
                              displayTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                color: WxColors.redPacketLine,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // 底部标签条
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  /// 左侧图标
  Widget _buildIcon(bool isRed) {
    if (isRed) {
      // 红包图标 32x32 — 橙色圆形 + ¥
      return Container(
        width: 32,
        height: 32,
        decoration: const BoxDecoration(
          color: WxColors.redPacketLine,
          shape: BoxShape.circle,
        ),
        child: const Center(
          child: Text(
            '¥',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: WxColors.redPacketBg,
            ),
          ),
        ),
      );
    }
    // 转账图标 28x28 — 橙色方块 + 箭头
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: WxColors.redPacketLine,
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Center(
        child: Icon(
          Icons.swap_horiz,
          size: 18,
          color: WxColors.redPacketBg,
        ),
      ),
    );
  }

  /// 底部标签条
  Widget _buildFooter() {
    return Container(
      height: _footerHeight,
      padding: const EdgeInsets.only(left: 15, right: 10),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: WxColors.redPacketLine, width: 0.3),
        ),
      ),
      child: Row(
        children: [
          Text(
            kind == WxMoneyKind.redPacket ? '微信红包' : '微信转账',
            style: const TextStyle(
              fontSize: 9,
              color: WxColors.transferBg,
            ),
          ),
        ],
      ),
    );
  }
}

/// 带头像的红包/转账消息行
///
/// 封装了 [WxAvatar] + [WxMoneyCard] 的完整消息行，
/// 可直接放入聊天列表。
class WxMoneyRow extends StatelessWidget {
  const WxMoneyRow({
    super.key,
    required this.kind,
    required this.isMe,
    this.avatar,
    this.avatarText,
    this.title,
    this.amount,
    this.onTap,
    this.showTime = false,
    this.timeText,
  });

  final WxMoneyKind kind;
  final bool isMe;
  final ImageProvider? avatar;
  final String? avatarText;
  final String? title;
  final String? amount;
  final VoidCallback? onTap;
  final bool showTime;
  final String? timeText;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (showTime && timeText != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(timeText!, style: WxText.time),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            mainAxisAlignment:
                isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isMe) ...[
                WxAvatar(image: avatar, text: avatarText, size: WxDimens.avatar),
                const SizedBox(width: 4),
              ],
              WxMoneyCard(
                kind: kind,
                isMe: isMe,
                title: title,
                amount: amount,
                onTap: onTap,
              ),
              if (isMe) ...[
                const SizedBox(width: 4),
                WxAvatar(image: avatar, text: avatarText, size: WxDimens.avatar),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
