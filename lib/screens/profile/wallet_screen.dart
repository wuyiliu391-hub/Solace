import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../models/user.dart';
import '../../models/ai_wallet.dart';
import '../../repositories/local_storage_repository.dart';
import '../../config/business_rules.dart';
import '../../widgets/ai_wallet_card.dart';

class WalletScreen extends StatefulWidget {
  final User user;

  const WalletScreen({super.key, required this.user});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  late User _user;
  List<AIWallet> _aiWallets = [];

  @override
  void initState() {
    super.initState();
    _user = widget.user;
    _loadAIWallets();
  }

  Future<void> _refreshUser() async {
    final storage = RepositoryProvider.of<LocalStorageRepository>(context);
    final user = await storage.getUser(_user.id);
    final wallets = await storage.getAllAIWallets();
    if (user != null && mounted) {
      setState(() {
        _user = user;
        _aiWallets = wallets;
      });
    }
  }

  Future<void> _loadAIWallets() async {
    try {
      final storage = RepositoryProvider.of<LocalStorageRepository>(context);
      final wallets = await storage.getAllAIWallets();
      if (mounted) {
        setState(() {
          _aiWallets = wallets;
        });
      }
    } catch (e) {
      debugPrint('加载AI钱包失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('我的钱包'),
      ),
      body: RefreshIndicator(
        onRefresh: _refreshUser,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _buildBalanceCard(colorScheme),
              const SizedBox(height: 24),
              if (_aiWallets.isNotEmpty) ...[
                _buildAIWalletsSection(colorScheme),
                const SizedBox(height: 24),
              ],
              _buildActionsGrid(colorScheme),
              const SizedBox(height: 24),
              _buildUsageInfo(colorScheme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBalanceCard(ColorScheme colorScheme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.amber[600]!,
            Colors.amber[800]!,
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.amber.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.account_balance_wallet,
                color: Colors.white,
                size: 28,
              ),
              const SizedBox(width: 8),
              const Text(
                '金币余额',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            '${_user.coins}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 48,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '可用于和 AI 好友互动',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAIWalletsSection(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.smart_toy_rounded,
              size: 18,
              color: Colors.purple[600],
            ),
            const SizedBox(width: 8),
            Text(
              'AI 伙伴钱包',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.purple[600],
              ),
            ),
            const Spacer(),
            Text(
              '${_aiWallets.length} 个',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ..._aiWallets.map((wallet) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: AIWalletCard(
            wallet: wallet,
            compact: true,
          ),
        )),
      ],
    );
  }

  Widget _buildActionsGrid(ColorScheme colorScheme) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      childAspectRatio: 1.5,
      children: [
        _buildActionCard(
          icon: Icons.chat_bubble_outline,
          title: '发送消息',
          subtitle: '-${CoinRules.messageCost} 金币',
          color: Colors.blue,
          onTap: () => _showInfo('发送一条消息消耗 ${CoinRules.messageCost} 金币'),
        ),
        _buildActionCard(
          icon: Icons.favorite_outline,
          title: '朋友圈互动',
          subtitle: '-${CoinRules.momentInteractionCost} 金币',
          color: Colors.pink,
          onTap: () => _showInfo('点赞或评论朋友圈消耗 ${CoinRules.momentInteractionCost} 金币'),
        ),
        _buildActionCard(
          icon: Icons.card_giftcard,
          title: '每日签到',
          subtitle: '+${CoinRules.dailyCheckInReward} 金币',
          color: Colors.green,
          onTap: _dailyCheckIn,
        ),
        _buildActionCard(
          icon: Icons.emoji_events,
          title: '连续登录',
          subtitle: '+${CoinRules.loginBonus} 金币',
          color: Colors.orange,
          onTap: () => _showInfo('每天首次登录获得 ${CoinRules.loginBonus} 金币'),
        ),
      ],
    );
  }

  Widget _buildActionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 32),
              const SizedBox(height: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: color.withOpacity(0.8),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUsageInfo(ColorScheme colorScheme) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '金币明细',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            _buildInfoRow('累计获得', '${_user.totalCoinsEarned} 金币', Colors.green),
            const SizedBox(height: 12),
            _buildInfoRow('累计花费', '${_user.totalCoinsSpent} 金币', Colors.red),
            const SizedBox(height: 12),
            _buildInfoRow('当前余额', '${_user.coins} 金币', Colors.amber[700]!),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, Color valueColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 15,
            color: Colors.grey[600],
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: valueColor,
          ),
        ),
      ],
    );
  }

  void _showInfo(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _dailyCheckIn() async {
    final storage = RepositoryProvider.of<LocalStorageRepository>(context);
    
    final lastCheckIn = storage.getLastCheckInDate();
    final today = DateTime.now().toIso8601String().split('T')[0];
    
    if (lastCheckIn == today) {
      _showInfo('今天已经签到过了，明天再来吧！');
      return;
    }

    await storage.setLastCheckInDate(today);
    await storage.addCoins(_user.id, 10);
    await _refreshUser();

    if (mounted) {
      _showInfo('签到成功！获得 10 金币');
    }
  }
}
