import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  bool _economyEnabled = true;
  int _messageCost = CoinRules.messageCost;
  int _momentCost = CoinRules.momentInteractionCost;
  int _loginBonus = CoinRules.loginBonus;
  int _checkInReward = CoinRules.dailyCheckInReward;

  @override
  void initState() {
    super.initState();
    _user = widget.user;
    _loadEconomy();
    _loadAIWallets();
  }

  void _loadEconomy() {
    final storage = RepositoryProvider.of<LocalStorageRepository>(context);
    setState(() {
      _economyEnabled = storage.isCoinEconomyEnabled();
      _messageCost = storage.getCoinMessageCost();
      _momentCost = storage.getCoinMomentCost();
      _loginBonus = storage.getCoinLoginBonus();
      _checkInReward = storage.getCoinCheckInReward();
    });
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
    if (mounted) _loadEconomy();
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
        actions: [
          IconButton(
            tooltip: '金币规则',
            icon: const Icon(Icons.tune_rounded),
            onPressed: _openEconomySheet,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshUser,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _buildBalanceCard(colorScheme),
              if (!_economyEnabled) ...[
                const SizedBox(height: 12),
                _buildFreeModeBanner(colorScheme),
              ],
              const SizedBox(height: 24),
              if (_aiWallets.isNotEmpty) ...[
                _buildAIWalletsSection(colorScheme),
                const SizedBox(height: 24),
              ],
              _buildQuickGrant(colorScheme),
              const SizedBox(height: 24),
              _buildActionsGrid(colorScheme),
              const SizedBox(height: 24),
              _buildUsageInfo(colorScheme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFreeModeBanner(ColorScheme colorScheme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: colorScheme.primary.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.all_inclusive, color: colorScheme.primary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '免费模式已开启：消费不扣金币，商店/互动不会因余额失败',
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
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
            color: Colors.amber.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.account_balance_wallet,
                color: Colors.white,
                size: 28,
              ),
              SizedBox(width: 8),
              Text(
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
          Text(
            _economyEnabled ? '可用于商店与互动（可自定义规则）' : '免费模式 · 余额仅作展示',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickGrant(ColorScheme colorScheme) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.savings_outlined, color: colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                const Text(
                  '补充金币',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                TextButton(
                  onPressed: _openEconomySheet,
                  child: const Text('自定义规则'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final n in const [100, 500, 1000, 5000])
                  ActionChip(
                    label: Text('+$n'),
                    onPressed: () => _grantCoins(n),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.edit, size: 16),
                  label: const Text('自定义数额'),
                  onPressed: _grantCustomAmount,
                ),
              ],
            ),
          ],
        ),
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
    final msgLabel = !_economyEnabled
        ? '免费'
        : (_messageCost <= 0 ? '免费' : '-$_messageCost 金币');
    final momentLabel = !_economyEnabled
        ? '免费'
        : (_momentCost <= 0 ? '免费' : '-$_momentCost 金币');

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
          subtitle: msgLabel,
          color: Colors.blue,
          onTap: () => _showInfo(
            !_economyEnabled
                ? '免费模式：发消息不扣金币'
                : '发送一条消息消耗 $_messageCost 金币（可在规则里改）',
          ),
        ),
        _buildActionCard(
          icon: Icons.favorite_outline,
          title: '朋友圈互动',
          subtitle: momentLabel,
          color: Colors.pink,
          onTap: () => _showInfo(
            !_economyEnabled
                ? '免费模式：朋友圈互动不扣金币'
                : '点赞或评论朋友圈消耗 $_momentCost 金币（可在规则里改）',
          ),
        ),
        _buildActionCard(
          icon: Icons.card_giftcard,
          title: '每日签到',
          subtitle: '+$_checkInReward 金币',
          color: Colors.green,
          onTap: _dailyCheckIn,
        ),
        _buildActionCard(
          icon: Icons.emoji_events,
          title: '每日登录',
          subtitle: '+$_loginBonus 金币',
          color: Colors.orange,
          onTap: () => _showInfo(
            '每天首次打开/登录自动获得 $_loginBonus 金币，可与签到叠加',
          ),
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
                  color: color.withValues(alpha: 0.85),
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
            const SizedBox(height: 12),
            _buildInfoRow(
              '经济模式',
              _economyEnabled ? '正常扣费' : '免费（不扣币）',
              _economyEnabled ? colorScheme.primary : Colors.teal,
            ),
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
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: valueColor,
            ),
          ),
        ),
      ],
    );
  }

  void _showInfo(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _grantCoins(int amount) async {
    if (amount <= 0) return;
    final storage = RepositoryProvider.of<LocalStorageRepository>(context);
    final n = amount.clamp(1, CoinRules.maxManualGrant);
    await storage.addCoins(_user.id, n);
    await _refreshUser();
    if (mounted) _showInfo('已补充 +$n 金币');
  }

  Future<void> _grantCustomAmount() async {
    final controller = TextEditingController(text: '1000');
    final amount = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('补充金币'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: '数额',
            hintText: '1 ~ 999999',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final v = int.tryParse(controller.text.trim()) ?? 0;
              Navigator.pop(ctx, v);
            },
            child: const Text('确认'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (amount == null || amount <= 0) return;
    await _grantCoins(amount);
  }

  Future<void> _openEconomySheet() async {
    final storage = RepositoryProvider.of<LocalStorageRepository>(context);
    var enabled = storage.isCoinEconomyEnabled();
    final msgCtrl =
        TextEditingController(text: '${storage.getCoinMessageCost()}');
    final momentCtrl =
        TextEditingController(text: '${storage.getCoinMomentCost()}');
    final loginCtrl =
        TextEditingController(text: '${storage.getCoinLoginBonus()}');
    final checkCtrl =
        TextEditingController(text: '${storage.getCoinCheckInReward()}');

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 8,
            bottom: MediaQuery.viewInsetsOf(ctx).bottom + 24,
          ),
          child: StatefulBuilder(
            builder: (ctx, setModal) {
              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      '金币规则（自定义）',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '本地生效。关闭消耗后商店与互动不再因金币不足失败。',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('启用金币消耗'),
                      subtitle: Text(
                        enabled
                            ? '正常扣费（可把单项消耗设为 0）'
                            : '免费模式：spend 不减余额',
                      ),
                      value: enabled,
                      onChanged: (v) => setModal(() => enabled = v),
                    ),
                    const Divider(),
                    _numField(msgCtrl, '发消息消耗', '0 = 不扣'),
                    _numField(momentCtrl, '朋友圈互动消耗', '0 = 不扣'),
                    _numField(loginCtrl, '每日登录奖励', '每天首次登录'),
                    _numField(checkCtrl, '每日签到奖励', '钱包手动签到'),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () async {
                            await storage.resetCoinEconomyToDefaults();
                            await storage.setCoinEconomyEnabled(true);
                            if (ctx.mounted) Navigator.pop(ctx);
                            await _refreshUser();
                            if (mounted) _showInfo('已恢复默认金币规则');
                          },
                          child: const Text('恢复默认'),
                        ),
                        const Spacer(),
                        FilledButton(
                          onPressed: () async {
                            int parse(TextEditingController c, int fallback) =>
                                int.tryParse(c.text.trim()) ?? fallback;

                            await storage.setCoinEconomyEnabled(enabled);
                            await storage.setCoinMessageCost(
                              parse(msgCtrl, CoinRules.messageCost),
                            );
                            await storage.setCoinMomentCost(
                              parse(momentCtrl, CoinRules.momentInteractionCost),
                            );
                            await storage.setCoinLoginBonus(
                              parse(loginCtrl, CoinRules.loginBonus),
                            );
                            await storage.setCoinCheckInReward(
                              parse(checkCtrl, CoinRules.dailyCheckInReward),
                            );
                            if (ctx.mounted) Navigator.pop(ctx);
                            await _refreshUser();
                            if (mounted) {
                              _showInfo(enabled
                                  ? '金币规则已保存'
                                  : '已开启免费模式，消费不扣币');
                            }
                          },
                          child: const Text('保存'),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );

    msgCtrl.dispose();
    momentCtrl.dispose();
    loginCtrl.dispose();
    checkCtrl.dispose();
  }

  Widget _numField(
    TextEditingController controller,
    String label,
    String hint,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
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

    final reward = storage.getCoinCheckInReward();
    await storage.setLastCheckInDate(today);
    if (reward > 0) {
      await storage.addCoins(_user.id, reward);
    }
    await _refreshUser();

    if (mounted) {
      _showInfo(reward > 0 ? '签到成功！获得 $reward 金币' : '签到成功（奖励已设为 0）');
    }
  }
}
