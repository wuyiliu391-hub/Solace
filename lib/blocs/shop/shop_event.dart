part of 'shop_bloc.dart';

abstract class ShopEvent extends Equatable {
  const ShopEvent();

  @override
  List<Object?> get props => [];
}

class ShopLoadItems extends ShopEvent {
  const ShopLoadItems();
}

class ShopLoadItemsByCategory extends ShopEvent {
  final String category;

  const ShopLoadItemsByCategory(this.category);

  @override
  List<Object?> get props => [category];
}

class ShopPlaceOrder extends ShopEvent {
  final String chatSessionId;
  final String buyerType; // 'user' or 'ai'
  final String buyerId;
  final String receiverType;
  final String receiverId;
  final ShopItem item;
  final String? message;

  const ShopPlaceOrder({
    required this.chatSessionId,
    required this.buyerType,
    required this.buyerId,
    required this.receiverType,
    required this.receiverId,
    required this.item,
    this.message,
  });

  @override
  List<Object?> get props => [
        chatSessionId,
        buyerType,
        buyerId,
        receiverType,
        receiverId,
        item,
        message,
      ];
}

class ShopUpdateOrderStatus extends ShopEvent {
  final String orderId;
  final String status;
  final String? aiReaction;

  const ShopUpdateOrderStatus({
    required this.orderId,
    required this.status,
    this.aiReaction,
  });

  @override
  List<Object?> get props => [orderId, status, aiReaction];
}

class ShopLoadOrders extends ShopEvent {
  final String chatSessionId;

  const ShopLoadOrders(this.chatSessionId);

  @override
  List<Object?> get props => [chatSessionId];
}

class ShopLoadActiveOrders extends ShopEvent {
  const ShopLoadActiveOrders();
}

class ShopOrderDelivered extends ShopEvent {
  final String orderId;
  final String? aiReaction;

  const ShopOrderDelivered({
    required this.orderId,
    this.aiReaction,
  });

  @override
  List<Object?> get props => [orderId, aiReaction];
}
