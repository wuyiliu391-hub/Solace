import 'package:equatable/equatable.dart';

class ShopOrder extends Equatable {
  final String id;
  final String buyerType; // 'user' | 'ai'
  final String buyerId;
  final String receiverType; // 'user' | 'ai'
  final String receiverId;
  final String chatSessionId;
  final String itemId;
  final String itemName;
  final String itemEmoji;
  final int price;
  final String status; // 'pending', 'preparing', 'shipping', 'delivered'
  final String? message;
  final DateTime createdAt;
  final DateTime? preparingAt;
  final DateTime? shippingAt;
  final DateTime? deliveredAt;
  final String? aiReaction;
  final int syncSeq;

  const ShopOrder({
    required this.id,
    required this.buyerType,
    required this.buyerId,
    required this.receiverType,
    required this.receiverId,
    required this.chatSessionId,
    required this.itemId,
    required this.itemName,
    required this.itemEmoji,
    required this.price,
    this.status = 'pending',
    this.message,
    required this.createdAt,
    this.preparingAt,
    this.shippingAt,
    this.deliveredAt,
    this.aiReaction,
    this.syncSeq = 0,
  });

  ShopOrder copyWith({
    String? status,
    DateTime? preparingAt,
    DateTime? shippingAt,
    DateTime? deliveredAt,
    String? aiReaction,
  }) {
    return ShopOrder(
      id: id,
      buyerType: buyerType,
      buyerId: buyerId,
      receiverType: receiverType,
      receiverId: receiverId,
      chatSessionId: chatSessionId,
      itemId: itemId,
      itemName: itemName,
      itemEmoji: itemEmoji,
      price: price,
      status: status ?? this.status,
      message: message,
      createdAt: createdAt,
      preparingAt: preparingAt ?? this.preparingAt,
      shippingAt: shippingAt ?? this.shippingAt,
      deliveredAt: deliveredAt ?? this.deliveredAt,
      aiReaction: aiReaction ?? this.aiReaction,
      syncSeq: syncSeq,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'buyerType': buyerType,
      'buyerId': buyerId,
      'receiverType': receiverType,
      'receiverId': receiverId,
      'chatSessionId': chatSessionId,
      'itemId': itemId,
      'itemName': itemName,
      'itemEmoji': itemEmoji,
      'price': price,
      'status': status,
      'message': message,
      'createdAt': createdAt.toIso8601String(),
      'preparingAt': preparingAt?.toIso8601String(),
      'shippingAt': shippingAt?.toIso8601String(),
      'deliveredAt': deliveredAt?.toIso8601String(),
      'aiReaction': aiReaction,
      'sync_seq': syncSeq,
    };
  }

  factory ShopOrder.fromMap(Map<String, dynamic> map) {
    DateTime? tryParseDateTime(dynamic val) {
      if (val == null || (val is String && val.trim().isEmpty)) return null;
      if (val is String) return DateTime.tryParse(val);
      if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
      return null;
    }
    return ShopOrder(
      id: (map['id'] as String?) ?? '',
      buyerType: (map['buyerType'] as String?) ?? 'user',
      buyerId: (map['buyerId'] as String?) ?? '',
      receiverType: (map['receiverType'] as String?) ?? 'ai',
      receiverId: (map['receiverId'] as String?) ?? '',
      chatSessionId: (map['chatSessionId'] as String?) ?? '',
      itemId: (map['itemId'] as String?) ?? '',
      itemName: (map['itemName'] as String?) ?? '',
      itemEmoji: (map['itemEmoji'] as String?) ?? '',
      price: (map['price'] as int?) ?? 0,
      status: map['status'] as String? ?? 'pending',
      message: map['message'] as String?,
      createdAt: tryParseDateTime(map['createdAt']) ?? DateTime.now(),
      preparingAt: tryParseDateTime(map['preparingAt']),
      shippingAt: tryParseDateTime(map['shippingAt']),
      deliveredAt: tryParseDateTime(map['deliveredAt']),
      aiReaction: map['aiReaction'] as String?,
      syncSeq: map['sync_seq'] as int? ?? 0,
    );
  }

  /// 从聊天消息 metadata 中恢复订单信息
  factory ShopOrder.fromMetadata(Map<String, dynamic> meta) {
    return ShopOrder(
      id: meta['orderId'] as String? ?? '',
      buyerType: meta['buyerType'] as String? ?? 'user',
      buyerId: meta['buyerId'] as String? ?? '',
      receiverType: meta['receiverType'] as String? ?? 'ai',
      receiverId: meta['receiverId'] as String? ?? '',
      chatSessionId: meta['chatSessionId'] as String? ?? '',
      itemId: meta['itemId'] as String? ?? '',
      itemName: meta['itemName'] as String? ?? '',
      itemEmoji: meta['itemEmoji'] as String? ?? '商品',
      price: meta['price'] as int? ?? 0,
      status: meta['orderStatus'] as String? ?? 'pending',
      message: meta['message'] as String?,
      createdAt: meta['createdAt'] != null
          ? DateTime.parse(meta['createdAt'] as String)
          : DateTime.now(),
      preparingAt: meta['preparingAt'] != null
          ? DateTime.parse(meta['preparingAt'] as String)
          : null,
      shippingAt: meta['shippingAt'] != null
          ? DateTime.parse(meta['shippingAt'] as String)
          : null,
      deliveredAt: meta['deliveredAt'] != null
          ? DateTime.parse(meta['deliveredAt'] as String)
          : null,
    );
  }

  /// 转换为 metadata JSON 用于聊天消息
  Map<String, dynamic> toMetadata() {
    return {
      'type': 'shop_order',
      'orderId': id,
      'buyerType': buyerType,
      'buyerId': buyerId,
      'receiverType': receiverType,
      'receiverId': receiverId,
      'chatSessionId': chatSessionId,
      'itemId': itemId,
      'itemName': itemName,
      'itemEmoji': itemEmoji,
      'price': price,
      'orderStatus': status,
      'message': message,
      'createdAt': createdAt.toIso8601String(),
      'preparingAt': preparingAt?.toIso8601String(),
      'shippingAt': shippingAt?.toIso8601String(),
      'deliveredAt': deliveredAt?.toIso8601String(),
    };
  }

  @override
  List<Object?> get props => [
        id,
        buyerType,
        buyerId,
        receiverType,
        receiverId,
        chatSessionId,
        itemId,
        itemName,
        itemEmoji,
        price,
        status,
        message,
        createdAt,
        preparingAt,
        shippingAt,
        deliveredAt,
        aiReaction,
      ];
}
