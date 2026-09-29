import 'package:flutter/material.dart';

/// 消息列表共用的状态反馈，避免单聊和群聊各自显示不同语义。
enum MessageDeliveryState { sending, generating, sent, read, failed, cancelled }

class MessageStatusIndicator extends StatelessWidget {
  final MessageDeliveryState state;
  final VoidCallback? onRetry;
  final bool showLabel;

  const MessageStatusIndicator({
    super.key,
    required this.state,
    this.onRetry,
    this.showLabel = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isError = state == MessageDeliveryState.failed;
    final color =
        isError ? scheme.error : scheme.onSurfaceVariant.withValues(alpha: .62);

    if (state == MessageDeliveryState.sending ||
        state == MessageDeliveryState.generating) {
      return SizedBox(
        width: 13,
        height: 13,
        child: CircularProgressIndicator(strokeWidth: 1.5, color: color),
      );
    }

    final icon = switch (state) {
      MessageDeliveryState.sent => Icons.check,
      MessageDeliveryState.read => Icons.done_all,
      MessageDeliveryState.failed => Icons.error_outline,
      MessageDeliveryState.cancelled => Icons.block,
      _ => Icons.auto_awesome,
    };
    final label = switch (state) {
      MessageDeliveryState.sent => '已发送',
      MessageDeliveryState.read => '已读',
      MessageDeliveryState.failed => '重试',
      MessageDeliveryState.cancelled => '已取消',
      _ => '生成中',
    };

    final indicator = Icon(icon, size: 14, color: color);
    if (state != MessageDeliveryState.failed || onRetry == null) {
      return Tooltip(message: label, child: indicator);
    }
    return InkWell(
      onTap: onRetry,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
        child: showLabel
            ? Row(mainAxisSize: MainAxisSize.min, children: [
                indicator,
                const SizedBox(width: 3),
                Text(label, style: TextStyle(fontSize: 11, color: color)),
              ])
            : indicator,
      ),
    );
  }
}
