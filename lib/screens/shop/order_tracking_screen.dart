import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../blocs/shop/shop_bloc.dart';
import '../../models/shop_order.dart';

/// 订单追踪页 —— 跟随 app 主题，温柔的物流进度展示
class OrderTrackingScreen extends StatefulWidget {
  const OrderTrackingScreen({super.key});

  @override
  State<OrderTrackingScreen> createState() => _OrderTrackingScreenState();
}

class _OrderTrackingScreenState extends State<OrderTrackingScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    context.read<ShopBloc>().add(const ShopLoadActiveOrders());
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('我的订单'),
        centerTitle: false,
        elevation: 0,
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
      ),
      body: Column(
        children: [
          _buildTabBar(cs),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildActiveOrdersTab(),
                _buildCompletedOrdersTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar(ColorScheme cs) {
    return BlocBuilder<ShopBloc, ShopState>(
      builder: (context, state) {
        final activeCount = state.activeOrders.length;
        final completedCount =
            state.orders.where((o) => o.status == 'delivered').length;

        return Container(
          color: cs.surface,
          child: TabBar(
            controller: _tabController,
            labelColor: cs.primary,
            unselectedLabelColor: cs.onSurfaceVariant,
            indicatorColor: cs.primary,
            indicatorWeight: 3,
            labelStyle:
                const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            unselectedLabelStyle:
                const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
            tabs: [
              Tab(text: '进行中 ($activeCount)'),
              Tab(text: '已完成 ($completedCount)'),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActiveOrdersTab() {
    return BlocBuilder<ShopBloc, ShopState>(
      builder: (context, state) {
        if (state.activeOrders.isEmpty) {
          return _buildEmptyState(Icons.inbox_outlined, '暂无进行中的订单');
        }

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: state.activeOrders.length,
          itemBuilder: (context, index) {
            return _buildOrderCard(state.activeOrders[index]);
          },
        );
      },
    );
  }

  Widget _buildCompletedOrdersTab() {
    return BlocBuilder<ShopBloc, ShopState>(
      builder: (context, state) {
        final completed = state.orders
            .where((o) => o.status == 'delivered')
            .toList()
          ..sort((a, b) {
            final aTime = a.deliveredAt ?? a.createdAt;
            final bTime = b.deliveredAt ?? b.createdAt;
            return bTime.compareTo(aTime);
          });

        if (completed.isEmpty) {
          return _buildEmptyState(Icons.check_circle_outline, '暂无已完成的订单');
        }

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: completed.length,
          itemBuilder: (context, index) {
            return _buildOrderCard(completed[index]);
          },
        );
      },
    );
  }

  Widget _buildEmptyState(IconData icon, String text) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(40),
            ),
            child: Icon(icon, size: 40, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          Text(
            text,
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 15),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderCard(ShopOrder order) {
    final cs = Theme.of(context).colorScheme;
    final statusIndex = _getStatusIndex(order.status);
    final isDelivered = order.status == 'delivered';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 顶部状态条
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isDelivered
                  ? cs.tertiaryContainer
                  : cs.primaryContainer,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: Row(
              children: [
                Icon(
                  isDelivered
                      ? Icons.check_circle_outline
                      : Icons.local_shipping_outlined,
                  color: isDelivered
                      ? cs.onTertiaryContainer
                      : cs.onPrimaryContainer,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  _getStatusDetail(order.status)['text'] as String,
                  style: TextStyle(
                    color: isDelivered
                        ? cs.onTertiaryContainer
                        : cs.onPrimaryContainer,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          // 头部：商品信息
          _buildOrderHeader(order, cs),
          // 进度条
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: _buildProgressBar(order, statusIndex, cs),
          ),
          // 当前状态
          _buildStatusSection(order, cs),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildOrderHeader(ShopOrder order, ColorScheme cs) {
    final receiver = order.receiverType == 'ai' ? 'AI' : order.receiverId;

    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          // 商品图标
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: cs.secondaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                _getItemEmoji(order.itemId),
                style: const TextStyle(fontSize: 30),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // 商品信息
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  order.itemName,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      '送给 $receiver',
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(Icons.savings_outlined, size: 14, color: cs.primary),
                    const SizedBox(width: 2),
                    Text(
                      '${order.price}',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: cs.primary,
                      ),
                    ),
                  ],
                ),
                if (order.message != null && order.message!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    '"${order.message}"',
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar(ShopOrder order, int statusIndex, ColorScheme cs) {
    const labels = ['下单', '准备', '配送', '送达'];
    final timestamps = [
      _formatTime(order.createdAt),
      _formatTime(order.preparingAt),
      _formatTime(order.shippingAt),
      _formatTime(order.deliveredAt),
    ];

    return Row(
      children: List.generate(4, (index) {
        final isCompleted = index < statusIndex;
        final isCurrent = index == statusIndex - 1;

        return Expanded(
          child: Column(
            children: [
              Row(
                children: [
                  if (index > 0)
                    Expanded(
                      child: Container(
                        height: 2,
                        color: isCompleted || isCurrent
                            ? cs.primary
                            : cs.outlineVariant,
                      ),
                    ),
                  _buildNode(isCompleted, isCurrent, cs),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                labels[index],
                style: TextStyle(
                  fontSize: 11,
                  color: isCompleted || isCurrent
                      ? cs.primary
                      : cs.onSurfaceVariant,
                  fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                timestamps[index] ?? '',
                style: TextStyle(
                  fontSize: 9,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildNode(bool isCompleted, bool isCurrent, ColorScheme cs) {
    if (isCurrent) {
      return _PulsingNode(color: cs.primary);
    }

    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isCompleted ? cs.primary : cs.surface,
        border: Border.all(
          color: isCompleted ? cs.primary : cs.outlineVariant,
          width: 2,
        ),
      ),
      child: isCompleted
          ? Icon(Icons.check, size: 8, color: cs.onPrimary)
          : null,
    );
  }

  Widget _buildStatusSection(ShopOrder order, ColorScheme cs) {
    final statusInfo = _getStatusDetail(order.status);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(
              statusInfo['icon'] as IconData,
              size: 18,
              color: cs.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                statusInfo['text'] as String,
                style: TextStyle(
                  fontSize: 13,
                  color: cs.onSurface,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (order.status == 'delivered' && order.aiReaction != null)
              Flexible(
                child: Text(
                  order.aiReaction!,
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
      ),
    );
  }

  int _getStatusIndex(String status) {
    switch (status) {
      case 'pending':
        return 1;
      case 'preparing':
        return 2;
      case 'shipping':
        return 3;
      case 'delivered':
        return 4;
      default:
        return 0;
    }
  }

  Map<String, dynamic> _getStatusDetail(String status) {
    switch (status) {
      case 'pending':
        return {'icon': Icons.hourglass_top, 'text': '等待确认...'};
      case 'preparing':
        return {'icon': Icons.inventory_2_outlined, 'text': '正在精心准备中...'};
      case 'shipping':
        return {'icon': Icons.local_shipping_outlined, 'text': '正在送往 TA 那里...'};
      case 'delivered':
        return {'icon': Icons.auto_awesome_outlined, 'text': '已送达 TA 手中'};
      default:
        return {'icon': Icons.help_outline, 'text': status};
    }
  }

  String _getItemEmoji(String itemId) {
    const emojiMap = <String, String>{
      'gift_01': '🍭', 'gift_02': '🧸', 'gift_03': '🌹', 'gift_04': '🍫',
      'gift_05': '💎', 'gift_06': '📖', 'gift_07': '🎵', 'gift_08': '🌸',
      'gift_09': '🔮', 'gift_10': '💕',
      'food_01': '🧋', 'food_02': '🎂', 'food_03': '🍗', 'food_04': '🍲',
      'food_05': '🍣', 'food_06': '🍦', 'food_07': '🍎', 'food_08': '🍖',
      'food_09': '🍕', 'food_10': '🥟',
      'express_01': '🧤', 'express_02': '🧣', 'express_03': '📚',
      'express_04': '💌', 'express_05': '🎧', 'express_06': '🕯️',
      'express_07': '🩴', 'express_08': '🎁', 'express_09': '🌌',
      'express_10': '🛋️',
    };
    return emojiMap[itemId] ?? '🎁';
  }

  String? _formatTime(DateTime? time) {
    if (time == null) return null;
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}

/// 脉动动画节点 - 当前状态
class _PulsingNode extends StatefulWidget {
  final Color color;
  const _PulsingNode({required this.color});

  @override
  State<_PulsingNode> createState() => _PulsingNodeState();
}

class _PulsingNodeState extends State<_PulsingNode>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 0.85, end: 1.15).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    _controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _scaleAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: child,
        );
      },
      child: Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.color,
          boxShadow: [
            BoxShadow(
              color: widget.color.withValues(alpha: 0.5),
              blurRadius: 8,
              spreadRadius: 2,
            ),
          ],
        ),
        child: const Icon(Icons.circle, size: 6, color: Colors.white),
      ),
    );
  }
}
