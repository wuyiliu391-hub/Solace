import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../blocs/shop/shop_bloc.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../models/shop_item.dart';
import '../../models/chat_session.dart';
import '../../repositories/local_storage_repository.dart';
import 'order_tracking_screen.dart';
import '../../models/shop_order.dart';

import '../../utils/avatar_resolver.dart';

/// 心意小铺 —— 给在意的 TA 挑一份礼物
/// 跟随 app 主题（colorScheme），支持浅色 / 深色，温柔克制的陪伴基调。
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
      appBar: AppBar(
        title: const Text('心意小铺'),
        centerTitle: false,
        elevation: 0,
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        actions: [
          IconButton(
            tooltip: '我的订单',
            icon: const Icon(Icons.receipt_long_outlined),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => BlocProvider.value(
                    value: context.read<ShopBloc>(),
                    child: const OrderTrackingScreen(),
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          _buildBalanceBar(cs),
          _buildBanner(cs),
          _buildCategoryGrid(cs),
          _buildTabBar(cs),
          Expanded(
            child: _buildProductGrid(cs),
          ),
        ],
      ),
    );
  }

  Widget _buildBalanceBar(ColorScheme cs) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(Icons.savings_outlined,
                color: cs.onPrimaryContainer, size: 20),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '我的金币',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 2),
              Text(
                '${_userCoins.toInt()}',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: cs.onSurface,
                ),
              ),
            ],
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: () {},
            icon: Icon(Icons.smart_toy_outlined, size: 18, color: cs.primary),
            label: Text('AI钱包', style: TextStyle(color: cs.primary)),
          ),
        ],
      ),
    );
  }

  /// 柔和的送礼引导横幅
  Widget _buildBanner(ColorScheme cs) {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            cs.primaryContainer,
            cs.primaryContainer.withValues(alpha: 0.55),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '给 TA 一份心意',
                  style: TextStyle(
                    color: cs.onPrimaryContainer,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '一份小礼物，温暖 TA 的一天',
                  style: TextStyle(
                    color: cs.onPrimaryContainer.withValues(alpha: 0.75),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.card_giftcard_outlined,
              size: 48, color: cs.onPrimaryContainer.withValues(alpha: 0.6)),
        ],
      ),
    );
  }

  /// 分类图标网格（2行5列）
  Widget _buildCategoryGrid(ColorScheme cs) {
    const categories = [
      _CategoryItem(Icons.card_giftcard, '礼物'),
      _CategoryItem(Icons.restaurant, '外卖'),
      _CategoryItem(Icons.local_shipping_outlined, '快递'),
      _CategoryItem(Icons.diamond_outlined, '精选'),
      _CategoryItem(Icons.favorite_outline, '心动'),
      _CategoryItem(Icons.local_florist_outlined, '鲜花'),
      _CategoryItem(Icons.cake_outlined, '甜点'),
      _CategoryItem(Icons.celebration_outlined, '节日'),
      _CategoryItem(Icons.auto_awesome_outlined, '推荐'),
      _CategoryItem(Icons.more_horiz, '更多'),
    ];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 5,
        mainAxisSpacing: 12,
        childAspectRatio: 1,
        children: categories.map((cat) => _buildCategoryIcon(cat, cs)).toList(),
      ),
    );
  }

  Widget _buildCategoryIcon(_CategoryItem cat, ColorScheme cs) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: cs.secondaryContainer,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(cat.icon, size: 24, color: cs.onSecondaryContainer),
        ),
        const SizedBox(height: 6),
        Text(
          cat.label,
          style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _buildTabBar(ColorScheme cs) {
    const tabs = [
      _TabItem(icon: Icons.grid_view_outlined, label: '全部', category: 'all'),
      _TabItem(icon: Icons.card_giftcard, label: '礼物', category: 'gift'),
      _TabItem(icon: Icons.restaurant, label: '外卖', category: 'food'),
      _TabItem(
          icon: Icons.local_shipping_outlined, label: '快递', category: 'express'),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: tabs.asMap().entries.map((entry) {
          final index = entry.key;
          final tab = entry.value;
          final isSelected = _selectedIndex == index;
          return GestureDetector(
            onTap: () {
              setState(() => _selectedIndex = index);
              final categories = ['all', 'gift', 'food', 'express'];
              context.read<ShopBloc>().add(
                    ShopLoadItemsByCategory(categories[index]),
                  );
            },
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? cs.primaryContainer : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    tab.icon,
                    size: 22,
                    color: isSelected
                        ? cs.onPrimaryContainer
                        : cs.onSurfaceVariant,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    tab.label,
                    style: TextStyle(
                      fontSize: 12,
                      color: isSelected
                          ? cs.onPrimaryContainer
                          : cs.onSurfaceVariant,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildProductGrid(ColorScheme cs) {
    return BlocConsumer<ShopBloc, ShopState>(
      listener: (context, state) {
        if (state.lastPlacedOrder != null) {
          _showOrderSuccessDialog(state.lastPlacedOrder!);
          context.read<ShopBloc>().add(const ShopLoadActiveOrders());
          _loadUserCoins();
          widget.onGiftSent?.call(state.lastPlacedOrder!);
        }
        if (state.error != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.error!),
              backgroundColor: cs.error,
            ),
          );
        }
      },
      builder: (context, state) {
        if (state.isLoading && state.filteredItems.isEmpty) {
          return Center(
            child: CircularProgressIndicator(color: cs.primary),
          );
        }

        if (state.filteredItems.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.shopping_bag_outlined,
                    size: 56, color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
                const SizedBox(height: 12),
                Text(
                  '暂无商品',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 15),
                ),
              ],
            ),
          );
        }

        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 0.62,
          ),
          itemCount: state.filteredItems.length,
          itemBuilder: (context, index) {
            final item = state.filteredItems[index];
            return _buildProductCard(item, cs);
          },
        );
      },
    );
  }

  Widget _buildProductCard(ShopItem item, ColorScheme cs) {
    final canAfford = _userCoins >= item.price;

    return GestureDetector(
      onTap: canAfford ? () => _showOrderDialog(item) : null,
      child: Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 商品图片区域
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(14)),
              child: Stack(
                children: [
                  Container(
                    width: double.infinity,
                    height: 130,
                    color: cs.secondaryContainer.withValues(alpha: 0.5),
                    child: Center(
                      child: Text(
                        _getItemIconConfig(item.id).$3,
                        style: const TextStyle(fontSize: 56),
                      ),
                    ),
                  ),
                  if (item.category == 'gift' || item.category == 'food')
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          item.category == 'gift' ? '礼物' : '外卖',
                          style: TextStyle(
                            color: cs.onPrimary,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // 商品信息区域
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                        height: 1.25,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.description,
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const Spacer(),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Icon(Icons.savings_outlined,
                            size: 14, color: cs.primary),
                        const SizedBox(width: 3),
                        Text(
                          '${item.price}',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: cs.primary,
                            height: 1,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: canAfford
                                ? cs.primaryContainer
                                : cs.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(
                            canAfford ? '送 TA' : '金币不足',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: canAfford
                                  ? cs.onPrimaryContainer
                                  : cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showOrderDialog(ShopItem item) {
    final cs = Theme.of(context).colorScheme;
    final messageController = TextEditingController();
    final canAfford = _userCoins >= item.price;

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
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 顶部把手 + 标题
                  const SizedBox(height: 12),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: cs.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '确认心意',
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 收礼人选择
                  if (_chatSessions.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: cs.outlineVariant),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedSessionId,
                            isExpanded: true,
                            dropdownColor: cs.surfaceContainerLow,
                            icon: Icon(Icons.keyboard_arrow_down,
                                color: cs.onSurfaceVariant),
                            items: _chatSessions.map((session) {
                              return DropdownMenuItem(
                                value: session.id,
                                child: Row(
                                  children: [
                                    _buildAvatar(session),
                                    const SizedBox(width: 8),
                                    Text(
                                      '送给 ${session.aiCharacterName}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w500,
                                        color: cs.onSurface,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                            onChanged: (sessionId) {
                              if (sessionId == null) return;
                              final session = _chatSessions
                                  .firstWhere((s) => s.id == sessionId);
                              setDialogState(() {
                                _selectedSessionId = sessionId;
                                _selectedReceiverId = session.aiCharacterId;
                              });
                            },
                          ),
                        ),
                      ),
                    ),

                  // 商品预览卡
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: cs.outlineVariant),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              color: cs.secondaryContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Center(
                              child: Text(
                                _getItemIconConfig(item.id).$3,
                                style: const TextStyle(fontSize: 34),
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.name,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: cs.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  item.description,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.center,
                                  children: [
                                    Icon(Icons.savings_outlined,
                                        size: 16, color: cs.primary),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${item.price}',
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: cs.primary,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '金币',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // 附言输入
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      controller: messageController,
                      style: TextStyle(color: cs.onSurface),
                      decoration: InputDecoration(
                        hintText: '写一句想对 TA 说的话（选填）...',
                        hintStyle: TextStyle(
                            color: cs.onSurfaceVariant, fontSize: 14),
                        filled: true,
                        fillColor: cs.surfaceContainerLow,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: cs.outlineVariant),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: cs.outlineVariant),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: cs.primary),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                      ),
                      maxLength: 50,
                    ),
                  ),

                  // 余额信息条
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '余额 ${_userCoins.toInt()}',
                            style: TextStyle(
                                fontSize: 13, color: cs.onSurfaceVariant),
                          ),
                          Text(
                            '扣除 ${item.price}',
                            style: TextStyle(
                              fontSize: 13,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          Text(
                            '剩余 ${remaining.toInt()}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: remaining >= 0
                                  ? cs.primary
                                  : cs.error,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // 确认按钮
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    child: SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: FilledButton(
                        onPressed: canAfford
                            ? () {
                                Navigator.pop(context);
                                _placeOrder(item, messageController.text);
                              }
                            : null,
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(25),
                          ),
                        ),
                        child: Text(
                          canAfford ? '送给 TA' : '金币不足',
                          style: const TextStyle(
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
    final cs = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Text(
              _getItemIconConfig(order.itemId).$3,
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${order.itemName} 已送出，心意已送到',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        backgroundColor: cs.inverseSurface,
        duration: const Duration(seconds: 2),
        action: SnackBarAction(
          label: '查看',
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => BlocProvider.value(
                  value: context.read<ShopBloc>(),
                  child: const OrderTrackingScreen(),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  (IconData, Color, String) _getItemIconConfig(String itemId) {
    // 使用 emoji 作为商品主图
    final emojiMap = <String, (IconData, Color, String)>{
      'gift_01': (Icons.cake_outlined, Colors.pink, '🍭'),
      'gift_02': (Icons.toys_outlined, Colors.brown, '🧸'),
      'gift_03': (Icons.local_florist, Colors.red, '🌹'),
      'gift_04': (Icons.cookie_outlined, Colors.brown, '🍫'),
      'gift_05': (Icons.diamond_outlined, Colors.amber, '💎'),
      'gift_06': (Icons.auto_stories, Colors.orange, '📖'),
      'gift_07': (Icons.music_note, Colors.purple, '🎵'),
      'gift_08': (Icons.local_florist, Colors.pinkAccent, '🌸'),
      'gift_09': (Icons.blur_circular, Colors.cyan, '🔮'),
      'gift_10': (Icons.favorite_outline, Colors.redAccent, '💕'),
      'food_01': (Icons.local_cafe, Colors.brown, '🧋'),
      'food_02': (Icons.cake, Colors.pink, '🎂'),
      'food_03': (Icons.lunch_dining, Colors.orange, '🍗'),
      'food_04': (Icons.soup_kitchen_outlined, Colors.red, '🍲'),
      'food_05': (Icons.set_meal_outlined, Colors.teal, '🍣'),
      'food_06': (Icons.icecream_outlined, Colors.pinkAccent, '🍦'),
      'food_07': (Icons.local_grocery_store, Colors.green, '🍎'),
      'food_08': (Icons.outdoor_grill, Colors.deepOrange, '🍖'),
      'food_09': (Icons.local_pizza, Colors.orange, '🍕'),
      'food_10': (Icons.ramen_dining, Colors.amber, '🥟'),
      'express_01': (Icons.whatshot_outlined, Colors.orange, '🧤'),
      'express_02': (Icons.checkroom, Colors.indigo, '🧣'),
      'express_03': (Icons.menu_book, Colors.blue, '📚'),
      'express_04': (Icons.mail_outline, Colors.pink, '💌'),
      'express_05': (Icons.headphones, Colors.grey, '🎧'),
      'express_06': (Icons.local_fire_department_outlined, Colors.amber, '🕯️'),
      'express_07': (Icons.directions_walk, Colors.brown, '🩴'),
      'express_08': (Icons.card_giftcard, Colors.purple, '🎁'),
      'express_09': (Icons.nights_stay_outlined, Colors.indigo, '🌌'),
      'express_10': (Icons.weekend_outlined, Colors.teal, '🛋️'),
    };
    return emojiMap[itemId] ?? (Icons.shopping_bag_outlined, Colors.grey, '🎁');
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
        style: TextStyle(fontSize: 12, color: colorScheme.onPrimaryContainer),
      ),
    );
  }
}

class _CategoryItem {
  final IconData icon;
  final String label;

  const _CategoryItem(this.icon, this.label);
}

class _TabItem {
  final IconData icon;
  final String label;
  final String category;

  const _TabItem(
      {required this.icon, required this.label, required this.category});
}
