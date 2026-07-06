import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';
import '../../models/shop_item.dart';
import '../../models/shop_order.dart';
import '../../models/chat_message.dart';
import '../../repositories/local_storage_repository.dart';
import '../../config/business_rules.dart';

part 'shop_event.dart';
part 'shop_state.dart';

class ShopBloc extends Bloc<ShopEvent, ShopState> {
  final LocalStorageRepository _storage;
  final _uuid = const Uuid();

  ShopBloc(this._storage) : super(const ShopState()) {
    on<ShopLoadItems>(_onLoadItems);
    on<ShopLoadItemsByCategory>(_onLoadItemsByCategory);
    on<ShopPlaceOrder>(_onPlaceOrder);
    on<ShopUpdateOrderStatus>(_onUpdateOrderStatus);
    on<ShopLoadOrders>(_onLoadOrders);
    on<ShopLoadActiveOrders>(_onLoadActiveOrders);
    on<ShopOrderDelivered>(_onOrderDelivered);
  }

  Future<void> _onLoadItems(
    ShopLoadItems event,
    Emitter<ShopState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, clearError: true));
    try {
      await _storage.initializeShopItems();
      final items = await _storage.getAllShopItems();
      emit(state.copyWith(
        items: items,
        filteredItems: items,
        selectedCategory: 'all',
        isLoading: false,
      ));
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: '加载商品失败: $e'));
    }
  }

  Future<void> _onLoadItemsByCategory(
    ShopLoadItemsByCategory event,
    Emitter<ShopState> emit,
  ) async {
    emit(state.copyWith(isLoading: true));
    try {
      List<ShopItem> filtered;
      if (event.category == 'all') {
        filtered = state.items;
      } else {
        filtered = state.items
            .where((item) => item.category == event.category)
            .toList();
      }
      emit(state.copyWith(
        filteredItems: filtered,
        selectedCategory: event.category,
        isLoading: false,
      ));
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: '筛选商品失败: $e'));
    }
  }

  Future<void> _onPlaceOrder(
    ShopPlaceOrder event,
    Emitter<ShopState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, clearError: true));
    try {
      // 检查每日订单限制
      final todayCount = await _storage.getTodayOrderCount();
      if (todayCount >= CoinRules.shopMaxDailyOrders) {
        emit(state.copyWith(
          isLoading: false,
          error: '今日订单已达上限（${CoinRules.shopMaxDailyOrders}单）',
        ));
        return;
      }

      // 检查AI每日赠送限制
      if (event.buyerType == 'ai') {
        final aiTodayCount =
            await _storage.getTodayAIOrderCount(event.buyerId);
        if (aiTodayCount >= ShopAIRules.aiMaxGiftsPerDay) {
          emit(state.copyWith(
            isLoading: false,
            error: '今日赠送已达上限',
          ));
          return;
        }
      }

      // 扣除买家金币
      bool deducted;
      if (event.buyerType == 'user') {
        deducted = await _storage.spendCoins(
          event.buyerId,
          event.item.price,
        );
      } else {
        deducted = await _storage.deductAICoins(
          event.buyerId,
          event.item.price,
        );
      }

      if (!deducted) {
        emit(state.copyWith(
          isLoading: false,
          error: '金币不足',
        ));
        return;
      }

      // 创建订单
      final order = ShopOrder(
        id: _uuid.v4(),
        buyerType: event.buyerType,
        buyerId: event.buyerId,
        receiverType: event.receiverType,
        receiverId: event.receiverId,
        chatSessionId: event.chatSessionId,
        itemId: event.item.id,
        itemName: event.item.name,
        itemEmoji: event.item.emoji,
        price: event.item.price,
        status: ShopDeliveryRules.statusPending,
        message: event.message,
        createdAt: DateTime.now(),
      );

      await _storage.createShopOrder(order);

      // 增加接收方亲密度
      if (event.receiverType == 'ai') {
        final session = await _storage.getChatSession(event.chatSessionId);
        if (session != null) {
          final newLevel = (session.intimacyLevel + 1).clamp(0, 100);
          await _storage.saveChatSession(session.copyWith(
            intimacyLevel: newLevel,
            lastMessageTime: DateTime.now(),
          ));
        }
      }

      // 发送聊天消息
      if (event.chatSessionId.isNotEmpty) {
        await _storage.saveChatMessage(ChatMessage(
          id: _uuid.v4(),
          chatId: event.chatSessionId,
          senderId: 'system',
          content: '${event.item.name} 已送出！',
          type: MessageType.system,
          status: MessageStatus.sent,
          createdAt: DateTime.now(),
          metadata: order.toMetadata(),
        ));
      }

      emit(state.copyWith(
        isLoading: false,
        lastPlacedOrder: order,
        clearLastOrder: false,
      ));

      debugPrint('下单成功: ${event.item.name} → ${order.id}');
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: '下单失败: $e'));
    }
  }

  Future<void> _onUpdateOrderStatus(
    ShopUpdateOrderStatus event,
    Emitter<ShopState> emit,
  ) async {
    try {
      DateTime? preparingAt;
      DateTime? shippingAt;
      DateTime? deliveredAt;

      if (event.status == ShopDeliveryRules.statusPreparing) {
        preparingAt = DateTime.now();
      } else if (event.status == ShopDeliveryRules.statusShipping) {
        shippingAt = DateTime.now();
      } else if (event.status == ShopDeliveryRules.statusDelivered) {
        deliveredAt = DateTime.now();
      }

      await _storage.updateOrderStatus(
        event.orderId,
        event.status,
        preparingAt: preparingAt,
        shippingAt: shippingAt,
        deliveredAt: deliveredAt,
        aiReaction: event.aiReaction,
      );

      // 更新本地订单列表
      final updatedOrders = state.orders.map((o) {
        if (o.id == event.orderId) {
          return o.copyWith(
            status: event.status,
            preparingAt: preparingAt ?? o.preparingAt,
            shippingAt: shippingAt ?? o.shippingAt,
            deliveredAt: deliveredAt ?? o.deliveredAt,
            aiReaction: event.aiReaction ?? o.aiReaction,
          );
        }
        return o;
      }).toList();

      final updatedActive = state.activeOrders
          .where((o) => o.status != ShopDeliveryRules.statusDelivered)
          .toList();

      emit(state.copyWith(
        orders: updatedOrders,
        activeOrders: updatedActive,
      ));
    } catch (e) {
      debugPrint('更新订单状态失败: $e');
    }
  }

  Future<void> _onLoadOrders(
    ShopLoadOrders event,
    Emitter<ShopState> emit,
  ) async {
    try {
      final orders = await _storage.getOrdersBySession(event.chatSessionId);
      emit(state.copyWith(orders: orders));
    } catch (e) {
      debugPrint('加载订单失败: $e');
    }
  }

  Future<void> _onLoadActiveOrders(
    ShopLoadActiveOrders event,
    Emitter<ShopState> emit,
  ) async {
    try {
      final activeOrders = await _storage.getActiveOrders();
      emit(state.copyWith(activeOrders: activeOrders));
    } catch (e) {
      debugPrint('加载进行中订单失败: $e');
    }
  }

  Future<void> _onOrderDelivered(
    ShopOrderDelivered event,
    Emitter<ShopState> emit,
  ) async {
    try {
      await _storage.updateOrderStatus(
        event.orderId,
        ShopDeliveryRules.statusDelivered,
        deliveredAt: DateTime.now(),
        aiReaction: event.aiReaction,
      );

      // 从活跃列表移除
      final updatedActive = state.activeOrders
          .where((o) => o.id != event.orderId)
          .toList();

      emit(state.copyWith(activeOrders: updatedActive));
    } catch (e) {
      debugPrint('订单送达确认失败: $e');
    }
  }
}
