import 'package:flutter/material.dart';
import '../models/shop_order.dart';

/// 订单卡片 - 显示在聊天流中
/// 灵感来源：微信红包卡片 + 拼多多礼物卡
class OrderCard extends StatefulWidget {
  final ShopOrder order;
  final bool isFromUser;
  final String? receiverName;
  final VoidCallback? onTap;

  const OrderCard({
    super.key,
    required this.order,
    required this.isFromUser,
    this.receiverName,
    this.onTap,
  });

  @override
  State<OrderCard> createState() => _OrderCardState();
}

class _OrderCardState extends State<OrderCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    if (widget.order.status != 'delivered') {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final category = _getCategory();
    final colors = _getColors(category);

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.72,
          minWidth: 200,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: colors.first.withOpacity(0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(order, category),
            _buildDivider(category),
            _buildBody(order, category),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ShopOrder order, String category) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      child: Row(
        children: [
          // 商品图标
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _getItemColor(order.itemId).withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              _getItemIcon(order.itemId),
              size: 22,
              color: _getItemColor(order.itemId),
            ),
          ),
          const SizedBox(width: 10),
          // 商品信息
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  order.itemName,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF333333),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _getSubtitle(order),
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          // 价格标签
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFF9A825).withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${order.price} ',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFF9A825),
                  ),
                ),
                const Icon(
                  Icons.monetization_on,
                  size: 13,
                  color: Color(0xFFF9A825),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider(String category) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Container(
        height: 1,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.grey.withOpacity(0.2),
              Colors.grey.withOpacity(0.1),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(ShopOrder order, String category) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 附言
          if (order.message != null && order.message!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '"${order.message}"',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[700],
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),

          // 配送状态
          _buildStatusRow(order, category),
        ],
      ),
    );
  }

  Widget _buildStatusRow(ShopOrder order, String category) {
    final statusInfo = _getStatusInfo(order.status);

    return Row(
      children: [
        // 状态图标（带脉动动画）
        if (order.status != 'delivered')
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: _pulseAnimation.value,
                child: child,
              );
            },
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: statusInfo.color,
                shape: BoxShape.circle,
              ),
            ),
          )
        else
          Icon(
            Icons.check_circle,
            size: 14,
            color: statusInfo.color,
          ),
        const SizedBox(width: 6),

        // 状态文字
        Text(
          statusInfo.label,
          style: TextStyle(
            fontSize: 12,
            color: statusInfo.color,
            fontWeight: FontWeight.w500,
          ),
        ),

        const Spacer(),

        // 操作按钮
        if (order.status == 'delivered')
          TextButton(
            onPressed: widget.onTap,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text(
              '查看详情',
              style: TextStyle(fontSize: 12),
            ),
          ),
      ],
    );
  }

  String _getCategory() {
    if (widget.order.itemId.startsWith('food')) return 'food';
    if (widget.order.itemId.startsWith('express')) return 'express';
    return 'gift';
  }

  String _getSubtitle(ShopOrder order) {
    final buyer = order.buyerType == 'user' ? '我' : order.buyerId;
    final receiver = order.receiverType == 'ai' ? 'AI' : order.receiverId;
    return '送给${receiver} · ${order.createdAt.hour}:${order.createdAt.minute.toString().padLeft(2, '0')}';
  }

  _StatusInfo _getStatusInfo(String status) {
    switch (status) {
      case 'pending':
        return _StatusInfo(
          label: '等待确认...',
          color: const Color(0xFFFF9800),
        );
      case 'preparing':
        return _StatusInfo(
          label: '准备中...',
          color: const Color(0xFF4CAF50),
        );
      case 'shipping':
        return _StatusInfo(
          label: '配送中...',
          color: const Color(0xFF2196F3),
        );
      case 'delivered':
        return _StatusInfo(
          label: '已送达',
          color: const Color(0xFF9C27B0),
        );
      default:
        return _StatusInfo(
          label: status,
          color: Colors.grey,
        );
    }
  }

  List<Color> _getColors(String category) {
    switch (category) {
      case 'food':
        return const [
          Color(0xFFFFF3E0),
          Color(0xFFFFE0B2),
        ];
      case 'express':
        return const [
          Color(0xFFE3F2FD),
          Color(0xFFBBDEFB),
        ];
      case 'gift':
      default:
        return const [
          Color(0xFFFFF0F5),
          Color(0xFFFFE4E9),
        ];
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
      default: return Colors.grey;
    }
  }
}

class _StatusInfo {
  final String label;
  final Color color;

  const _StatusInfo({required this.label, required this.color});
}
