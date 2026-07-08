import 'package:flutter/material.dart';
import '../models/ai_wallet.dart';
import '../models/ai_character.dart';
import '../config/business_rules.dart';
import '../utils/avatar_resolver.dart';

/// AI钱包卡片 - 用于展示AI角色的钱包余额和信息
/// 支持两种模式：紧凑模式（列表项）和完整模式（详情页）
class AIWalletCard extends StatelessWidget {
  final AIWallet wallet;
  final AICharacter? character;
  final bool compact;
  final VoidCallback? onTap;

  const AIWalletCard({
    super.key,
    required this.wallet,
    this.character,
    this.compact = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (compact) return _buildCompactCard(context);
    return _buildFullCard(context);
  }

  /// 完整模式 - 用于钱包页面
  Widget _buildFullCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final personalityLabel = _getPersonalityLabel(wallet.spendingPersonality);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.purple[400]!,
              Colors.deepPurple[600]!,
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.purple.withOpacity(0.3),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 顶部：头像 + 名称 + 性格标签
            Row(
              children: [
                // AI头像
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.3),
                      width: 2,
                    ),
                  ),
                  child: character?.avatarUrl != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(22),
                          child: AvatarResolver.imageWidget(
                            character!.avatarUrl,
                            fit: BoxFit.cover,
                            onError: () => const Icon(
                              Icons.smart_toy_rounded,
                              color: Colors.white,
                              size: 24,
                            ),
                          ) ??
                              const Icon(
                            Icons.smart_toy_rounded,
                            color: Colors.white,
                            size: 24,
                          ),
                        )
                      : const Icon(
                          Icons.smart_toy_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                ),
                const SizedBox(width: 12),
                // 名称 + 性格标签
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        character?.name ?? 'AI',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          personalityLabel,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // 箭头
                if (onTap != null)
                  Icon(
                    Icons.chevron_right,
                    color: Colors.white.withOpacity(0.6),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            // 余额显示
            Text(
              '${wallet.balance}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 40,
                fontWeight: FontWeight.bold,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'AI 金币余额',
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 16),
            // 底部统计
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _buildStatItem(
                      '累计收到',
                      '${wallet.totalEarned}',
                      Icons.arrow_downward_rounded,
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 24,
                    color: Colors.white.withOpacity(0.2),
                  ),
                  Expanded(
                    child: _buildStatItem(
                      '累计转出',
                      '${wallet.totalSpent}',
                      Icons.arrow_upward_rounded,
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

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.white60, size: 16),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.6),
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  /// 紧凑模式 - 用于列表项
  Widget _buildCompactCard(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // AI头像
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.purple[300]!,
                      Colors.deepPurple[500]!,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: character?.avatarUrl != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(22),
                        child: AvatarResolver.imageWidget(
                          character!.avatarUrl,
                          fit: BoxFit.cover,
                          onError: () => const Icon(
                            Icons.smart_toy_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                        ) ??
                            const Icon(
                          Icons.smart_toy_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      )
                    : const Icon(
                        Icons.smart_toy_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
              ),
              const SizedBox(width: 14),
              // 名称 + 余额
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      character?.name ?? 'AI',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _getPersonalityLabel(wallet.spendingPersonality),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              ),
              // 余额
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${wallet.balance}',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.purple[600],
                    ),
                  ),
                  const Text(
                    '金币',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getPersonalityLabel(int personality) {
    if (personality <= 2) return '非常节俭';
    if (personality <= 4) return '比较节俭';
    if (personality <= 6) return '平衡型';
    if (personality <= 8) return '比较大方';
    return '非常大方';
  }
}
