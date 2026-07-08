import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../blocs/shop/shop_bloc.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../models/shop_item.dart';
import '../../models/chat_session.dart';
import '../../repositories/local_storage_repository.dart';
import 'order_tracking_screen.dart';
import '../../models/shop_order.dart';
import '../../services/delivery_simulator.dart';
import '../../utils/avatar_resolver.dart';

/// AI小商店 - 主界面
/// 灵感来源：微信底部抽屉 + 拼多多卡片网格
class ShopScreen extends StatefulWidget {
  final String? chatSessionId;
  final String? receiverId;
  final String? receiverName;
  final void Function(ShopOrder order)? onGiftSent;

  const ShopScreen({
    super.key,
    this.chatSessionId,
    this.receiverId,
    this.receiverName,
    this.onGiftSent,
  });

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _selectedIndex = 0;
  double _userCoins = 0;
  String? _selectedSessionId;
  String? _selectedReceiverId;
  String? _selectedReceiverName;
  List<ChatSession> _chatSessions = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {
          _selectedIndex = _tabController.index;
        });
        _filterItems();
      }
    });
    _selectedSessionId = widget.chatSessionId;
    _selectedReceiverId = widget.receiverId;
    _selectedReceiverName = widget.receiverName;
    _loadUserCoins();
    _loadChatSessions();
    context.read<ShopBloc>().add(const ShopLoadItems());
  }

  Future<void> _loadUserCoins() async {
    final storage = context.read<LocalStorageRepository>();
    final user = await storage.getCurrentUser();
    if (mounted) {
      setState(() {
        _userCoins = user?.coins.toDouble() ?? 0;
      });
    }
  }

  Future<void> _loadChatSessions() async {
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) return;
    final storage = context.read<LocalStorageRepository>();
    final sessions = await storage.getChatSessions(authState.user.id);
    if (mounted) {
      setState(() {
        _chatSessions = sessions;
        if (_selectedSessionId == null && sessions.isNotEmpty) {
          _selectedSessionId = sessions.first.id;
          _selectedReceiverId = sessions.first.aiCharacterId;
          _selectedReceiverName = sessions.first.aiCharacterName;
        }
      });
    }
  }

  void _filterItems() {
    final categories = ['all', 'gift', 'food', 'express'];
    final category = categories[_selectedIndex];
    context.read<ShopBloc>().add(ShopLoadItemsByCategory(category));
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
      body: Column(
        children: [
          _buildHeader(),
          _buildBalanceBar(),
          _buildTabBar(),
          Expanded(
            child: _buildProductGrid(),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 12,
        left: 16,
        right: 16,
        bottom: 12,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [cs.primary, cs.tertiary],
        ),
      ),
      child: Row(
        children: [
          Hero(
            tag: 'app_icon_shop',
            child: Icon(Icons.storefront, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'AI小商店',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          // 订单按钮
          IconButton(
            icon: const Icon(Icons.receipt_long, color: Colors.white),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const OrderTrackingScreen(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBalanceBar() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFFF9A825).withOpacity(0.1),
            const Color(0xFFFFB74D).withOpacity(0.05),
          ],
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.account_balance_wallet, color: Color(0xFFF9A825)),
          const SizedBox(width: 8),
          Text(
            '我的余额:',
            style: TextStyle(
              fontSize: 14,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '${_userCoins.toInt()}',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFFF9A825),
            ),
          ),
          const Text(
            ' 金币',
            style: TextStyle(
              fontSize: 14,
              color: Color(0xFFF9A825),
            ),
          ),
          const Spacer(),
          // AI余额入口
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF9C27B0).withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.smart_toy, size: 16, color: Color(0xFF9C27B0)),
                SizedBox(width: 4),
                Text(
                  'AI钱包',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF9C27B0),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    final cs = Theme.of(context).colorScheme;
    final tabs = [
      _TabItem(icon: Icons.card_giftcard, label: '全部'),
      _TabItem(icon: Icons.favorite, label: '礼物'),
      _TabItem(icon: Icons.restaurant, label: '外卖'),
      _TabItem(icon: Icons.local_shipping, label: '快递'),
    ];

    return Container(
      color: cs.surface,
      child: TabBar(
        controller: _tabController,
        labelColor: cs.primary,
        unselectedLabelColor: cs.onSurfaceVariant,
        indicatorColor: cs.primary,
        indicatorWeight: 3,
        indicatorSize: TabBarIndicatorSize.label,
        tabs: tabs.map((tab) {
          return Tab(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(tab.icon, size: 20),
                  const SizedBox(height: 2),
                  Text(
                    tab.label,
                    style: const TextStyle(fontSize: 11),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildProductGrid() {
    return BlocConsumer<ShopBloc, ShopState>(
      listener: (context, state) {
        if (state.lastPlacedOrder != null) {
          _showOrderSuccessDialog(state.lastPlacedOrder!);
          context.read<ShopBloc>().add(const ShopLoadActiveOrders());
          _loadUserCoins();
          // 通知聊天页面触发AI回复
          widget.onGiftSent?.call(state.lastPlacedOrder!);
          // 启动配送模拟
          try {
            final simulator = context.read<DeliverySimulator>();
            simulator.startDelivery(state.lastPlacedOrder!);
          } catch (_) {}
        }
        if (state.error != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.error!),
              backgroundColor: Colors.red,
            ),
          );
        }
      },
      builder: (context, state) {
        if (state.isLoading && state.filteredItems.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        if (state.filteredItems.isEmpty) {
          return Center(
            child: Text(
              '暂无商品',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          );
        }

        return GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 0.85,
          ),
          itemCount: state.filteredItems.length,
          itemBuilder: (context, index) {
            final item = state.filteredItems[index];
            return _buildProductCard(item);
          },
        );
      },
    );
  }

  Widget _buildProductCard(ShopItem item) {
    final cs = Theme.of(context).colorScheme;
    final canAfford = _userCoins >= item.price;

    return GestureDetector(
      onTap: canAfford ? () => _showOrderDialog(item) : null,
      child: Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: cs.shadow.withOpacity(0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 商品图标
            _buildItemIcon(item),
            const SizedBox(height: 8),
            // 商品名
            Text(
              item.name,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            // 价格
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: canAfford
                    ? const Color(0xFFF9A825).withOpacity(0.1)
                    : cs.onSurfaceVariant.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${item.price} ',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: canAfford
                          ? const Color(0xFFF9A825)
                          : cs.onSurfaceVariant,
                    ),
                  ),
                  Icon(
                    Icons.monetization_on,
                    size: 14,
                    color: canAfford
                        ? const Color(0xFFF9A825)
                        : cs.onSurfaceVariant,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            // 描述
            Text(
              item.description,
              style: TextStyle(
                fontSize: 11,
                color: cs.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  void _showOrderDialog(ShopItem item) {
    final messageController = TextEditingController();
    final cs = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final remaining = _userCoins - item.price;
            return Container(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 拖拽条
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(top: 12),
                    decoration: BoxDecoration(
                      color: cs.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),

                  // 收礼人选择
                  if (_chatSessions.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedSessionId,
                            isExpanded: true,
                            icon: Icon(Icons.keyboard_arrow_down, color: cs.onSurfaceVariant),
                            items: _chatSessions.map((session) {
                              return DropdownMenuItem(
                                value: session.id,
                                child: Row(
                                  children: [
                                    _buildAvatar(session),
                                    const SizedBox(width: 8),
                                    Text(session.aiCharacterName),
                                  ],
                                ),
                              );
                            }).toList(),
                            onChanged: (sessionId) {
                              if (sessionId == null) return;
                              final session = _chatSessions.firstWhere((s) => s.id == sessionId);
                              setDialogState(() {
                                _selectedSessionId = sessionId;
                                _selectedReceiverId = session.aiCharacterId;
                                _selectedReceiverName = session.aiCharacterName;
                              });
                            },
                          ),
                        ),
                      ),
                    ),

                  // 商品预览
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Icon(
                          _getItemIconConfig(item.id).$1,
                          size: 64,
                          color: _getItemIconConfig(item.id).$2,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          item.name,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: cs.onSurface,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${item.price} 金币',
                          style: const TextStyle(
                            fontSize: 16,
                            color: Color(0xFFF9A825),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // 附言输入
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: TextField(
                      controller: messageController,
                      decoration: InputDecoration(
                        hintText: '写一句祝福语...',
                        hintStyle: TextStyle(color: cs.onSurfaceVariant),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: cs.outlineVariant),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: cs.primary),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      maxLength: 50,
                    ),
                  ),

                  // 余额信息
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '余额: ${_userCoins.toInt()} 金币',
                          style: TextStyle(
                            fontSize: 13,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          '扣除: ${item.price} 金币',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFFF9A825),
                          ),
                        ),
                        Text(
                          '剩余: ${remaining.toInt()} 金币',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: remaining >= 0
                                ? const Color(0xFF4CAF50)
                                : cs.error,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // 确认按钮
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                    child: SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: remaining >= 0
                            ? () {
                                Navigator.pop(context);
                                _placeOrder(item, messageController.text);
                              }
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFF9A825),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                          elevation: 0,
                        ),
                        child: const Text(
                          '确认送出',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _placeOrder(ShopItem item, String message) {
    final chatSessionId = widget.chatSessionId ?? _selectedSessionId ?? '';
    final receiverId = widget.receiverId ?? _selectedReceiverId ?? '';
    final receiverName = widget.receiverName ?? _selectedReceiverName ?? 'AI';

    if (chatSessionId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先选择收礼人')),
      );
      return;
    }

    context.read<ShopBloc>().add(ShopPlaceOrder(
      chatSessionId: chatSessionId,
      buyerType: 'user',
      buyerId: (context.read<AuthBloc>().state as AuthAuthenticated).user.id,
      receiverType: 'ai',
      receiverId: receiverId,
      item: item,
      message: message.isNotEmpty ? message : null,
    ));
  }

  void _showOrderSuccessDialog(ShopOrder order) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(_getItemIconConfig(order.itemId).$1, size: 20, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${order.itemName} 已送出！',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF4CAF50),
        duration: const Duration(seconds: 2),
        action: SnackBarAction(
          label: '查看',
          textColor: Colors.white,
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const OrderTrackingScreen(),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildItemIcon(ShopItem item) {
    final config = _getItemIconConfig(item.id);
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: config.$2.withOpacity(0.12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(config.$1, size: 28, color: config.$2),
    );
  }

  String _getItemEmoji(String itemId) {
    return _getItemIconConfig(itemId).$3;
  }

  (IconData, Color, String) _getItemIconConfig(String itemId) {
    switch (itemId) {
      // 礼物
      case 'gift_01': return (Icons.cake_outlined, Colors.pink, '棒棒糖');
      case 'gift_02': return (Icons.toys_outlined, Colors.brown, '小熊');
      case 'gift_03': return (Icons.local_florist, Colors.red, '玫瑰');
      case 'gift_04': return (Icons.cookie_outlined, Colors.brown.shade700, '巧克力');
      case 'gift_05': return (Icons.diamond_outlined, Colors.amber, '水晶');
      case 'gift_06': return (Icons.auto_stories, Colors.orange, '故事书');
      case 'gift_07': return (Icons.music_note, Colors.purple, '音乐盒');
      case 'gift_08': return (Icons.local_florist, Colors.pinkAccent, '樱花');
      case 'gift_09': return (Icons.blur_circular, Colors.cyan, '水晶球');
      case 'gift_10': return (Icons.favorite_outline, Colors.redAccent, '爱心');
      // 外卖
      case 'food_01': return (Icons.local_cafe, Colors.brown, '奶茶');
      case 'food_02': return (Icons.cake, Colors.pink, '蛋糕');
      case 'food_03': return (Icons.lunch_dining, Colors.orange, '鸡腿');
      case 'food_04': return (Icons.soup_kitchen_outlined, Colors.red, '火锅');
      case 'food_05': return (Icons.set_meal_outlined, Colors.teal, '寿司');
      case 'food_06': return (Icons.icecream_outlined, Colors.pinkAccent, '冰淇淋');
      case 'food_07': return (Icons.local_grocery_store, Colors.green, '水果');
      case 'food_08': return (Icons.outdoor_grill, Colors.deepOrange, '烧烤');
      case 'food_09': return (Icons.local_pizza, Colors.orange, '披萨');
      case 'food_10': return (Icons.ramen_dining, Colors.amber, '饺子');
      // 快递
      case 'express_01': return (Icons.whatshot_outlined, Colors.orange, '手套');
      case 'express_02': return (Icons.checkroom, Colors.indigo, '围巾');
      case 'express_03': return (Icons.menu_book, Colors.blue, '书籍');
      case 'express_04': return (Icons.mail_outline, Colors.pink, '情书');
      case 'express_05': return (Icons.headphones, Colors.grey.shade800, '耳机');
      case 'express_06': return (Icons.local_fire_department_outlined, Colors.amber, '香薰');
      case 'express_07': return (Icons.directions_walk, Colors.brown, '拖鞋');
      case 'express_08': return (Icons.card_giftcard, Colors.purple, '礼盒');
      case 'express_09': return (Icons.nights_stay_outlined, Colors.indigo, '星空灯');
      case 'express_10': return (Icons.weekend_outlined, Colors.teal, '抱枕');
      default: return (Icons.shopping_bag_outlined, Colors.grey, '商品');
    }
  }

  Widget _buildAvatar(ChatSession session) {
    final avatarUrl = session.aiCharacterAvatar;
    final colorScheme = Theme.of(context).colorScheme;

    final imageProvider = AvatarResolver.imageProvider(avatarUrl);
    if (imageProvider != null) {
      return CircleAvatar(
        radius: 14,
        backgroundImage: imageProvider,
        onBackgroundImageError: (_, __) {},
      );
    }

    return CircleAvatar(
      radius: 14,
      backgroundColor: colorScheme.primaryContainer,
      child: Text(
        session.aiCharacterName.isNotEmpty ? session.aiCharacterName[0] : '?',
        style: TextStyle(fontSize: 12, color: colorScheme.primary),
      ),
    );
  }
}

class _TabItem {
  final IconData icon;
  final String label;

  const _TabItem({required this.icon, required this.label});
}
