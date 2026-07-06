part of 'shop_bloc.dart';

class ShopState extends Equatable {
  final List<ShopItem> items;
  final List<ShopItem> filteredItems;
  final String selectedCategory;
  final List<ShopOrder> orders;
  final List<ShopOrder> activeOrders;
  final bool isLoading;
  final String? error;
  final ShopOrder? lastPlacedOrder;

  const ShopState({
    this.items = const [],
    this.filteredItems = const [],
    this.selectedCategory = 'all',
    this.orders = const [],
    this.activeOrders = const [],
    this.isLoading = false,
    this.error,
    this.lastPlacedOrder,
  });

  ShopState copyWith({
    List<ShopItem>? items,
    List<ShopItem>? filteredItems,
    String? selectedCategory,
    List<ShopOrder>? orders,
    List<ShopOrder>? activeOrders,
    bool? isLoading,
    String? error,
    ShopOrder? lastPlacedOrder,
    bool clearError = false,
    bool clearLastOrder = false,
  }) {
    return ShopState(
      items: items ?? this.items,
      filteredItems: filteredItems ?? this.filteredItems,
      selectedCategory: selectedCategory ?? this.selectedCategory,
      orders: orders ?? this.orders,
      activeOrders: activeOrders ?? this.activeOrders,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      lastPlacedOrder:
          clearLastOrder ? null : (lastPlacedOrder ?? this.lastPlacedOrder),
    );
  }

  @override
  List<Object?> get props => [
        items,
        filteredItems,
        selectedCategory,
        orders,
        activeOrders,
        isLoading,
        error,
        lastPlacedOrder,
      ];
}
