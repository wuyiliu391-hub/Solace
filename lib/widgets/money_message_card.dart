import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../models/chat_message.dart';
import '../models/money_transaction.dart';

/// 微信式转账/红包消息卡片。
///
/// 渲染契约：读取 [message].metadata['money']（[MoneyTransaction.toMessageMetadata]
/// 的产出），点击行为由 [onTap] 回调给聊天页（收款/拆包/查看详情路由由上层决定）。
///
/// 逆向视觉规格（仿微信）：
/// - 卡片整体圆角 6，白底（深色 #2C2C2C），宽约 240
/// - 左侧图标：转账=橙色方块图标，红包=红色红包图标
/// - 标题 15sp 主文本色；备注 12sp 次要色
/// - 底部 28 高条带：分割线 0.5 + 「微信转账」/「微信红包」11sp 灰字
/// - 状态小字（已收款/待收款/已过期）跟在标题右侧 11sp 灰
class MoneyMessageCard extends StatelessWidget {
  final ChatMessage message;
  final bool isDark;
  final VoidCallback? onTap;

  const MoneyMessageCard({
    super.key,
    required this.message,
    required this.isDark,
    this.onTap,
  });

  static const double cardWidth = 240;

  @override
  Widget build(BuildContext context) {
    final meta = MoneyTransaction.fromMessageMetadata(
        message.metadata?['money'] as Map<String, dynamic>?);
    if (meta == null) {
      return Container(
        width: cardWidth,
        padding: const EdgeInsets.all(12),
        decoration: _cardDecoration(),
        child: Text('¥ --',
            style: TextStyle(color: isDark ? WeChatColors.darkTextPrimary : WeChatColors.textPrimary)),
      );
    }

    final isRedPacket = meta.kind == MoneyKind.redPacket;
    final accent = isRedPacket ? const Color(0xFFE06A4E) : const Color(0xFFF89D35);
    final titleSuffix = switch (meta.status) {
      MoneyStatus.pending => isRedPacket ? '' : '（待收款）',
      MoneyStatus.accepted => '（已收款）',
      MoneyStatus.rejected => '（已拒收）',
      MoneyStatus.expired => isRedPacket ? '（已过期）' : '（已过期退回）',
      MoneyStatus.opened => '（已拆开）',
    };

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: cardWidth,
        decoration: _cardDecoration(),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
              child: Row(
                children: [
                  _MoneyIcon(kind: meta.kind, color: accent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text.rich(
                          TextSpan(children: [
                            TextSpan(
                              text: '¥${meta.amount}',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                color: isDark
                                    ? WeChatColors.darkTextPrimary
                                    : WeChatColors.textPrimary,
                              ),
                            ),
                            if (titleSuffix.isNotEmpty)
                              TextSpan(
                                text: titleSuffix,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark
                                      ? WeChatColors.darkTextSecondary
                                      : WeChatColors.textSecondary,
                                ),
                              ),
                          ]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          meta.note?.isNotEmpty == true
                              ? (isRedPacket ? meta.note! : '${meta.note}')
                              : (isRedPacket ? '恭喜发财，大吉大利' : '转账给你'),
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? WeChatColors.darkTextSecondary
                                : WeChatColors.textPreview,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Container(
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.centerLeft,
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: isDark
                        ? const Color(0xFF3A3A3A)
                        : const Color(0xFFEDEDED),
                    width: 0.5,
                  ),
                ),
              ),
              child: Text(
                isRedPacket ? '微信红包' : '微信转账',
                style: TextStyle(
                  fontSize: 11,
                  color: isDark
                      ? WeChatColors.darkTextSecondary
                      : WeChatColors.textPreview,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: isDark ? const Color(0xFF2C2C2C) : Colors.white,
      borderRadius: BorderRadius.circular(6),
      border: isDark
          ? null
          : Border.all(color: const Color(0xFFE5E5E5), width: 0.5),
    );
  }
}

class _MoneyIcon extends StatelessWidget {
  final MoneyKind kind;
  final Color color;

  const _MoneyIcon({required this.kind, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(
        kind == MoneyKind.redPacket
            ? Icons.card_giftcard_rounded
            : Icons.currency_exchange_rounded,
        color: Colors.white,
        size: 22,
      ),
    );
  }
}
