import 'package:flutter/material.dart';
import '../services/log_service.dart';

class _TransferStatusConfig {
  const _TransferStatusConfig({
    required this.icon,
    required this.label,
    required this.cardBg,
    required this.iconBg,
    required this.iconColor,
    required this.textColor,
  });

  final IconData icon;
  final String label;
  final Color cardBg;
  final Color iconBg;
  final Color iconColor;
  final Color textColor;
}

class TransferCard extends StatelessWidget {
  final double amount;
  final String? message;
  final bool isFromUser;
  final String transferStatus;
  final String? direction; // 'user_to_ai' or 'ai_to_user'

  const TransferCard({
    super.key,
    required this.amount,
    this.message,
    required this.isFromUser,
    this.transferStatus = 'pending',
    this.direction,
  });

  @override
  Widget build(BuildContext context) {
    LogService.instance.d('UI', 'TransferCard.build: amount=$amount, status=$transferStatus, direction=$direction');
    final isAITransfer = direction == 'ai_to_user';
    final config = isAITransfer
        ? (_aiToUserConfig[transferStatus] ?? _aiToUserConfig['accepted']!)
        : (_statusConfig[transferStatus] ?? _statusConfig['pending']!);
    final displayLabel = isAITransfer
        ? (transferStatus == 'accepted' ? 'AI转账' : 'AI退款')
        : config.label;

    return Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.55,
        minWidth: 180,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: config.cardBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: config.iconBg,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  config.icon,
                  size: 20,
                  color: config.iconColor,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      amount.toStringAsFixed(2),
                      style: const TextStyle(
                        color: Colors.black87,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.5,
                      ),
                    ),
                    if (message != null && message!.isNotEmpty)
                      Text(
                        message!,
                        style: TextStyle(
                          color: Colors.black.withOpacity(0.5),
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.only(top: 8),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: Colors.black.withOpacity(0.06),
                  width: 0.5,
                ),
              ),
            ),
            child: Text(
              displayLabel,
              style: TextStyle(
                color: config.textColor,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

const Map<String, _TransferStatusConfig> _statusConfig = {
  'pending': const _TransferStatusConfig(
    icon: Icons.sync_alt,
    label: '待收款',
    cardBg: Color(0xFFFFF3E0),
    iconBg: Color(0xFFFFE0B2),
    iconColor: Color(0xFFFF8A65),
    textColor: Color(0xFFFF8A65),
  ),
  'accepted': const _TransferStatusConfig(
    icon: Icons.check_circle_outline,
    label: '已收款',
    cardBg: Color(0xFFF1F8E9),
    iconBg: Color(0xFFC8E6C9),
    iconColor: Color(0xFF4CAF50),
    textColor: Color(0xFF4CAF50),
  ),
  'rejected': const _TransferStatusConfig(
    icon: Icons.reply,
    label: '已退还',
    cardBg: Color(0xFFF5F5F5),
    iconBg: Color(0xFFE0E0E0),
    iconColor: Color(0xFF9E9E9E),
    textColor: Color(0xFF9E9E9E),
  ),
};

const Map<String, _TransferStatusConfig> _aiToUserConfig = {
  'accepted': const _TransferStatusConfig(
    icon: Icons.redeem,
    label: 'AI转账',
    cardBg: Color(0xFFEDE7F6),
    iconBg: Color(0xFFD1C4E9),
    iconColor: Color(0xFF7E57C2),
    textColor: Color(0xFF7E57C2),
  ),
  'pending': const _TransferStatusConfig(
    icon: Icons.sync_alt,
    label: '待发放',
    cardBg: Color(0xFFEDE7F6),
    iconBg: Color(0xFFD1C4E9),
    iconColor: Color(0xFF7E57C2),
    textColor: Color(0xFF7E57C2),
  ),
  'rejected': const _TransferStatusConfig(
    icon: Icons.reply,
    label: 'AI退款',
    cardBg: Color(0xFFF3E5F5),
    iconBg: Color(0xFFE1BEE7),
    iconColor: Color(0xFFAB47BC),
    textColor: Color(0xFFAB47BC),
  ),
};
