import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../blocs/shop/shop_bloc.dart';
import '../../models/shop_order.dart';
import '../../config/business_rules.dart';

/// 订单追踪页 - 借鉴京东物流追踪
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
        title: Text(
          '我的订单',
          style: TextStyle(fontWeight: FontWeight.bold, color: cs.onPrimary),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
      ),
      body: Column(
        children: [
          _buildTabBar(),
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

  Widget _buildTabBar() {
    return BlocBuilder<ShopBloc, ShopState>(
      builder: (context, state) {
        final cs = Theme.of(context).colorScheme;
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
        final cs = Theme.of(context).colorScheme;
        if (state.activeOrders.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.inbox_outlined,
                  size: 64,
                  color: cs.onSurfaceVariant,
                ),
                SizedBox(height: 12),
                Text(
                  '暂无进行中的订单',
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          );
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
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.check_circle_outline,
                  size: 64,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                SizedBox(height: 12),
                Text(
                  '暂无已完成的订单',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          );
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

  Widget _buildOrderCard(ShopOrder order) {
    final cs = Theme.of(context).colorScheme;
    final category = _getCategory(order);
    final colors = _getCardColors(category);
    final statusIndex = _getStatusIndex(order.status);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 头部：商品信息
          _buildOrderHeader(order, category),

          // 分割线
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    cs.outlineVariant.withOpacity(0.15),
                    cs.outlineVariant.withOpacity(0.05),
                  ],
                ),
              ),
            ),
          ),

          // 进度条
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: _buildProgressBar(order, statusIndex),
          ),

          // 当前状态
          _buildStatusSection(order, category),

          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildOrderHeader(ShopOrder order, String category) {
    final cs = Theme.of(context).colorScheme;
    final receiver = order.receiverType == 'ai' ? 'AI' : order.receiverId;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          // 商品图标
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: _getItemColor(order.itemId).withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              _getItemIcon(order.itemId),
              size: 26,
              color: _getItemColor(order.itemId),
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
                Text(
                  '送给: $receiver  ·  ${order.price}金币',
                  style: TextStyle(
                    fontSize: 13,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                if (order.message != null && order.message!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    '"${order.message}"',
                    style: TextStyle(
                      fontSize: 13,
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

  Widget _buildProgressBar(ShopOrder order, int statusIndex) {
    final cs = Theme.of(context).colorScheme;
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
              // 节点 + 连线
              Row(
                children: [
                  if (index > 0)
                    Expanded(
                      child: Container(
                        height: 2,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: isCompleted || isCurrent
                                ? [
                                    const Color(0xFFF9A825),
                                    const Color(0xFFF9A825),
                                  ]
                                : [
                                    cs.outlineVariant.withOpacity(0.3),
                                    cs.outlineVariant.withOpacity(0.2),
                                  ],
                          ),
                        ),
                      ),
                    ),
                  // 节点圆点
                  _buildNode(isCompleted, isCurrent),
                ],
              ),
              const SizedBox(height: 6),

              // 标签文字
              Text(
                labels[index],
                style: TextStyle(
                  fontSize: 11,
                  color: isCompleted || isCurrent
                      ? const Color(0xFFF9A825)
                      : cs.onSurfaceVariant,
                  fontWeight:
                      isCurrent ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              const SizedBox(height: 2),

              // 时间
              Text(
                timestamps[index] ?? '',
                style: TextStyle(
                  fontSize: 9,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildNode(bool isCompleted, bool isCurrent) {
    final cs = Theme.of(context).colorScheme;
    if (isCurrent) {
      return _PulsingNode();
    }

    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isCompleted ? const Color(0xFFF9A825) : cs.surface,
        border: Border.all(
          color: isCompleted
              ? const Color(0xFFF9A825)
              : cs.outlineVariant,
          width: 2,
        ),
      ),
      child: isCompleted
          ? const Icon(Icons.check, size: 8, color: Colors.white)
          : null,
    );
  }

  Widget _buildStatusSection(ShopOrder order, String category) {
    final cs = Theme.of(context).colorScheme;
    final statusInfo = _getStatusDetail(order.status);
    final bgColor = _getStatusBgColor(order.status, cs);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(
              statusInfo['icon'] as IconData,
              size: 18,
              color: statusInfo['color'] as Color,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                statusInfo['text']!,
                style: TextStyle(
                  fontSize: 13,
                  color: statusInfo['color'] as Color,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (order.status == 'delivered' && order.aiReaction != null)
              Expanded(
                child: Text(
                  order.aiReaction!,
                  style: TextStyle(
                    fontSize: 12,
                    color: const Color(0xFF9C27B0).withOpacity(0.8),
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

  String _getCategory(ShopOrder order) {
    if (order.itemId.startsWith('food')) return 'food';
    if (order.itemId.startsWith('express')) return 'express';
    return 'gift';
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
    final cs = Theme.of(context).colorScheme;
    switch (status) {
      case 'pending':
        return {
          'icon': Icons.hourglass_top,
          'text': '等待确认...',
          'color': const Color(0xFFFF9800),
        };
      case 'preparing':
        return {
          'icon': Icons.inventory_2,
          'text': '正在精心准备中...',
          'color': const Color(0xFF4CAF50),
        };
      case 'shipping':
        return {
          'icon': Icons.local_shipping,
          'text': '飞速配送中...',
          'color': const Color(0xFF2196F3),
        };
      case 'delivered':
        return {
          'icon': Icons.auto_awesome,
          'text': '已送达！',
          'color': const Color(0xFF9C27B0),
        };
      default:
        return {
          'icon': Icons.help_outline,
          'text': status,
          'color': cs.onSurfaceVariant,
        };
    }
  }

  List<Color> _getCardColors(String category) {
    final cs = Theme.of(context).colorScheme;
    switch (category) {
      case 'food':
        return [
          cs.surfaceContainerLow,
          cs.surfaceContainerLow,
        ];
      case 'express':
        return [
          cs.surfaceContainerLow,
          cs.surfaceContainerLow,
        ];
      case 'gift':
      default:
        return [
          cs.surfaceContainerLow,
          cs.surfaceContainerLow,
        ];
    }
  }

  Color _getEmojiBackground(String category) {
    final cs = Theme.of(context).colorScheme;
    switch (category) {
      case 'food':
        return cs.surfaceContainerLow;
      case 'express':
        return cs.surfaceContainerLow;
      default:
        return cs.surfaceContainerLow;
    }
  }

  IconData _getItemIcon(String itemId) {
    switch (itemId) {
      case 'gift_01': return Icons.cake_outlined;
      case 'gift_02': return Icons.toys_outlined;
      case 'gift_03': return Icons.local_florist;
      case 'gift_04': return Icons.cookie_outlined;
      case 'gift_05': return Icons.diamond_outlined;
      case 'gift_06': return Icons.auto_stories;
      case 'gift_07': return Icons.music_note;
      case 'gift_08': return Icons.local_florist;
      case 'gift_09': return Icons.blur_circular;
      case 'gift_10': return Icons.favorite_outline;
      case 'food_01': return Icons.local_cafe;
      case 'food_02': return Icons.cake;
      case 'food_03': return Icons.lunch_dining;
      case 'food_04': return Icons.soup_kitchen_outlined;
      case 'food_05': return Icons.set_meal_outlined;
      case 'food_06': return Icons.icecream_outlined;
      case 'food_07': return Icons.local_grocery_store;
      case 'food_08': return Icons.outdoor_grill;
      case 'food_09': return Icons.local_pizza;
      case 'food_10': return Icons.ramen_dining;
      case 'express_01': return Icons.whatshot_outlined;
      case 'express_02': return Icons.checkroom;
      case 'express_03': return Icons.menu_book;
      case 'express_04': return Icons.mail_outline;
      case 'express_05': return Icons.headphones;
      case 'express_06': return Icons.local_fire_department_outlined;
      case 'express_07': return Icons.directions_walk;
      case 'express_08': return Icons.card_giftcard;
      case 'express_09': return Icons.nights_stay_outlined;
      case 'express_10': return Icons.weekend_outlined;
      default: return Icons.shopping_bag_outlined;
    }
  }

  Color _getItemColor(String itemId) {
    final cs = Theme.of(context).colorScheme;
    switch (itemId) {
      case 'gift_01': return Colors.pink;
      case 'gift_02': return Colors.brown;
      case 'gift_03': return Colors.red;
      case 'gift_04': return Colors.brown.shade700;
      case 'gift_05': return Colors.amber;
      case 'gift_06': return Colors.orange;
      case 'gift_07': return Colors.purple;
      case 'gift_08': return Colors.pinkAccent;
      case 'gift_09': return Colors.cyan;
      case 'gift_10': return Colors.redAccent;
      case 'food_01': return Colors.brown;
      case 'food_02': return Colors.pink;
      case 'food_03': return Colors.orange;
      case 'food_04': return Colors.red;
      case 'food_05': return Colors.teal;
      case 'food_06': return Colors.pinkAccent;
      case 'food_07': return Colors.green;
      case 'food_08': return Colors.deepOrange;
      case 'food_09': return Colors.orange;
      case 'food_10': return Colors.amber;
      case 'express_01': return Colors.orange;
      case 'express_02': return Colors.indigo;
      case 'express_03': return Colors.blue;
      case 'express_04': return Colors.pink;
      case 'express_05': return Colors.grey.shade800;
      case 'express_06': return Colors.amber;
      case 'express_07': return Colors.brown;
      case 'express_08': return Colors.purple;
      case 'express_09': return Colors.indigo;
      case 'express_10': return Colors.teal;
      default: return cs.onSurfaceVariant;
    }
  }

  Color _getStatusBgColor(String status, ColorScheme cs) {
    switch (status) {
      case 'pending':
        return const Color(0xFFFF9800).withOpacity(0.12);
      case 'preparing':
        return const Color(0xFF4CAF50).withOpacity(0.12);
      case 'shipping':
        return const Color(0xFF2196F3).withOpacity(0.12);
      case 'delivered':
        return const Color(0xFF9C27B0).withOpacity(0.12);
      default:
        return cs.onSurfaceVariant.withOpacity(0.1);
    }
  }

  String? _formatTime(DateTime? time) {
    if (time == null) return null;
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}

/// 脉动动画节点 - 当前状态
class _PulsingNode extends StatefulWidget {
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
          color: const Color(0xFFF9A825),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFF9A825).withOpacity(0.5),
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
