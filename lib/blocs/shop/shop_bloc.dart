import 'dart:async';
import 'dart:math';

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
  final _rng = Random();

  /// 订单 ID → 下一阶段定时器（本地模拟物流）
  final Map<String, Timer> _deliveryTimers = {};

  ShopBloc(this._storage) : super(const ShopState()) {
    on<ShopLoadItems>(_onLoadItems);
    on<ShopLoadItemsByCategory>(_onLoadItemsByCategory);
    on<ShopPlaceOrder>(_onPlaceOrder);
    on<ShopUpdateOrderStatus>(_onUpdateOrderStatus);
    on<ShopLoadOrders>(_onLoadOrders);
    on<ShopLoadActiveOrders>(_onLoadActiveOrders);
    on<ShopOrderDelivered>(_onOrderDelivered);
    on<ShopAdvanceOrder>(_onAdvanceOrder);
    on<ShopSaveCustomItem>(_onSaveCustomItem);
    on<ShopDeleteCustomItem>(_onDeleteCustomItem);
  }

  @override
  Future<void> close() {
    for (final t in _deliveryTimers.values) {
      t.cancel();
    }
    _deliveryTimers.clear();
    return super.close();
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

  Future<void> _onSaveCustomItem(
    ShopSaveCustomItem event,
    Emitter<ShopState> emit,
  ) async {
    try {
      final item = event.item.copyWith(
        isCustom: true,
        isActive: true,
        createdAt: event.item.createdAt ?? DateTime.now(),
      );
      await _storage.saveShopItem(item);
      final items = await _storage.getAllShopItems();
      final cat = state.selectedCategory;
      final filtered = cat == 'all'
          ? items
          : items.where((i) => i.category == cat).toList();
      emit(state.copyWith(
        items: items,
        filteredItems: filtered,
        clearError: true,
      ));
    } catch (e) {
      emit(state.copyWith(error: '保存自定义商品失败: $e'));
    }
  }

  Future<void> _onDeleteCustomItem(
    ShopDeleteCustomItem event,
    Emitter<ShopState> emit,
  ) async {
    try {
      await _storage.deleteShopItem(event.itemId);
      final items = await _storage.getAllShopItems();
      final cat = state.selectedCategory;
      final filtered = cat == 'all'
          ? items
          : items.where((i) => i.category == cat).toList();
      emit(state.copyWith(items: items, filteredItems: filtered));
    } catch (e) {
      emit(state.copyWith(error: '删除商品失败: $e'));
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

      // 创建订单（扣款成功 = 已下单；pending 是物流第一阶段，不是「未付款」）
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
        itemDescription: event.item.description,
        itemCategory: event.item.category,
        isCustomItem: event.item.isCustom || event.item.id.startsWith('custom_'),
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
          senderId: event.buyerId,
          senderName: event.buyerType == 'user' ? '你' : '',
          content: '${event.item.emoji} ${event.item.name}',
          isUser: event.buyerType == 'user',
          type: MessageType.system,
          status: MessageStatus.sent,
          createdAt: DateTime.now(),
          metadata: order.toMetadata(),
        ));
      }

      // 写入活跃列表并启动物流推进（以前缺这一步 → 永远「等待确认」）
      final active = [order, ...state.activeOrders];
      emit(state.copyWith(
        isLoading: false,
        lastPlacedOrder: order,
        clearLastOrder: false,
        activeOrders: active,
      ));

      _scheduleNextStage(order);
      debugPrint('下单成功: ${event.item.name} → ${order.id}，已调度物流');
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

      ShopOrder? touched;
      final updatedOrders = state.orders.map((o) {
        if (o.id == event.orderId) {
          touched = o.copyWith(
            status: event.status,
            preparingAt: preparingAt ?? o.preparingAt,
            shippingAt: shippingAt ?? o.shippingAt,
            deliveredAt: deliveredAt ?? o.deliveredAt,
            aiReaction: event.aiReaction ?? o.aiReaction,
          );
          return touched!;
        }
        return o;
      }).toList();

      final updatedActive = state.activeOrders
          .map((o) {
            if (o.id != event.orderId) return o;
            touched ??= o.copyWith(
              status: event.status,
              preparingAt: preparingAt ?? o.preparingAt,
              shippingAt: shippingAt ?? o.shippingAt,
              deliveredAt: deliveredAt ?? o.deliveredAt,
              aiReaction: event.aiReaction ?? o.aiReaction,
            );
            return touched!;
          })
          .where((o) => o.status != ShopDeliveryRules.statusDelivered)
          .toList();

      emit(state.copyWith(
        orders: updatedOrders,
        activeOrders: updatedActive,
      ));

      if (touched != null) {
        await _syncOrderChatMessage(touched!);
        if (touched!.status != ShopDeliveryRules.statusDelivered) {
          _scheduleNextStage(touched!);
        } else {
          _cancelTimer(touched!.id);
        }
      }
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
      var activeOrders = await _storage.getActiveOrders();
      // 追赶卡死在 pending/preparing/shipping 的旧单（扣过钱却永不推进）
      activeOrders = await _catchUpStaleOrders(activeOrders);
      emit(state.copyWith(activeOrders: activeOrders));
      // 为仍在途订单确保定时器
      for (final o in activeOrders) {
        if (o.status != ShopDeliveryRules.statusDelivered) {
          _scheduleNextStage(o, onlyIfMissing: true);
        }
      }
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
      _cancelTimer(event.orderId);

      final updatedActive =
          state.activeOrders.where((o) => o.id != event.orderId).toList();

      // 同步会话订单列表
      final updatedOrders = state.orders.map((o) {
        if (o.id == event.orderId) {
          return o.copyWith(
            status: ShopDeliveryRules.statusDelivered,
            deliveredAt: DateTime.now(),
            aiReaction: event.aiReaction ?? o.aiReaction,
          );
        }
        return o;
      }).toList();

      emit(state.copyWith(
        activeOrders: updatedActive,
        orders: updatedOrders,
      ));

      final fresh = await _storage.getShopOrder(event.orderId);
      if (fresh != null) await _syncOrderChatMessage(fresh);
    } catch (e) {
      debugPrint('订单送达确认失败: $e');
    }
  }

  /// 定时器触发：推进到下一物流阶段
  Future<void> _onAdvanceOrder(
    ShopAdvanceOrder event,
    Emitter<ShopState> emit,
  ) async {
    try {
      ShopOrder? found = await _storage.getShopOrder(event.orderId);
      if (found == null) {
        for (final o in state.activeOrders) {
          if (o.id == event.orderId) {
            found = o;
            break;
          }
        }
      }
      if (found == null) return;
      final order = found;
      if (order.status == ShopDeliveryRules.statusDelivered) {
        _cancelTimer(order.id);
        return;
      }

      final next = _nextStatus(order.status);
      if (next == null) return;

      DateTime? preparingAt;
      DateTime? shippingAt;
      DateTime? deliveredAt;
      if (next == ShopDeliveryRules.statusPreparing) {
        preparingAt = DateTime.now();
      } else if (next == ShopDeliveryRules.statusShipping) {
        shippingAt = DateTime.now();
      } else if (next == ShopDeliveryRules.statusDelivered) {
        deliveredAt = DateTime.now();
      }

      await _storage.updateOrderStatus(
        order.id,
        next,
        preparingAt: preparingAt,
        shippingAt: shippingAt,
        deliveredAt: deliveredAt,
      );

      final advanced = order.copyWith(
        status: next,
        preparingAt: preparingAt ?? order.preparingAt,
        shippingAt: shippingAt ?? order.shippingAt,
        deliveredAt: deliveredAt ?? order.deliveredAt,
      );

      final updatedActive = [
        if (next != ShopDeliveryRules.statusDelivered) advanced,
        ...state.activeOrders.where((o) => o.id != order.id),
      ];
      final updatedOrders = state.orders.map((o) {
        return o.id == order.id ? advanced : o;
      }).toList();

      emit(state.copyWith(
        activeOrders: updatedActive,
        orders: updatedOrders,
      ));

      await _syncOrderChatMessage(advanced);
      debugPrint('订单推进 ${order.id}: ${order.status} → $next');

      if (next != ShopDeliveryRules.statusDelivered) {
        _scheduleNextStage(advanced);
      } else {
        _cancelTimer(order.id);
        // 送达系统提示（可选轻量）
        if (advanced.chatSessionId.isNotEmpty) {
          await _storage.saveChatMessage(ChatMessage(
            id: _uuid.v4(),
            chatId: advanced.chatSessionId,
            senderId: 'system',
            content: '${advanced.itemEmoji} ${advanced.itemName} 已送达！',
            type: MessageType.system,
            status: MessageStatus.sent,
            createdAt: DateTime.now(),
            metadata: {
              ...advanced.toMetadata(),
              'isDeliveryNotice': true,
            },
          ));
        }
      }
    } catch (e, st) {
      debugPrint('推进订单失败: $e\n$st');
    }
  }

  // ─── 物流调度 ─────────────────────────────────────────────

  String? _nextStatus(String current) {
    switch (current) {
      case ShopDeliveryRules.statusPending:
        return ShopDeliveryRules.statusPreparing;
      case ShopDeliveryRules.statusPreparing:
        return ShopDeliveryRules.statusShipping;
      case ShopDeliveryRules.statusShipping:
        return ShopDeliveryRules.statusDelivered;
      default:
        return null;
    }
  }

  double _speedMultiplier(String itemId) {
    if (itemId.startsWith('food')) {
      return ShopDeliveryRules.foodSpeedMultiplier;
    }
    if (itemId.startsWith('express')) {
      return ShopDeliveryRules.expressSpeedMultiplier;
    }
    return 1.0;
  }

  Duration _stageDelay(String status, String itemId) {
    int minS;
    int maxS;
    switch (status) {
      case ShopDeliveryRules.statusPending:
        minS = ShopDeliveryRules.pendingMinSeconds;
        maxS = ShopDeliveryRules.pendingMaxSeconds;
        break;
      case ShopDeliveryRules.statusPreparing:
        minS = ShopDeliveryRules.preparingMinSeconds;
        maxS = ShopDeliveryRules.preparingMaxSeconds;
        break;
      case ShopDeliveryRules.statusShipping:
        minS = ShopDeliveryRules.shippingMinSeconds;
        maxS = ShopDeliveryRules.shippingMaxSeconds;
        break;
      default:
        return const Duration(seconds: 5);
    }
    final mult = _speedMultiplier(itemId);
    final span = (maxS - minS).clamp(0, 3600);
    final raw = minS + (span == 0 ? 0 : _rng.nextInt(span + 1));
    final sec = (raw * mult).round().clamp(3, 300);
    return Duration(seconds: sec);
  }

  int _stageMaxSeconds(String status, String itemId) {
    int maxS;
    switch (status) {
      case ShopDeliveryRules.statusPending:
        maxS = ShopDeliveryRules.pendingMaxSeconds;
        break;
      case ShopDeliveryRules.statusPreparing:
        maxS = ShopDeliveryRules.preparingMaxSeconds;
        break;
      case ShopDeliveryRules.statusShipping:
        maxS = ShopDeliveryRules.shippingMaxSeconds;
        break;
      default:
        maxS = 30;
    }
    return (maxS * _speedMultiplier(itemId)).round().clamp(5, 400);
  }

  DateTime _stageStart(ShopOrder o) {
    switch (o.status) {
      case ShopDeliveryRules.statusPreparing:
        return o.preparingAt ?? o.createdAt;
      case ShopDeliveryRules.statusShipping:
        return o.shippingAt ?? o.preparingAt ?? o.createdAt;
      case ShopDeliveryRules.statusPending:
      default:
        return o.createdAt;
    }
  }

  void _cancelTimer(String orderId) {
    _deliveryTimers.remove(orderId)?.cancel();
  }

  void _scheduleNextStage(ShopOrder order, {bool onlyIfMissing = false}) {
    if (order.status == ShopDeliveryRules.statusDelivered) {
      _cancelTimer(order.id);
      return;
    }
    if (onlyIfMissing && _deliveryTimers.containsKey(order.id)) return;

    _cancelTimer(order.id);
    final delay = _stageDelay(order.status, order.itemId);
    debugPrint(
        '调度订单 ${order.id} 阶段 ${order.status}，${delay.inSeconds}s 后推进');
    _deliveryTimers[order.id] = Timer(delay, () {
      if (isClosed) return;
      add(ShopAdvanceOrder(order.id));
    });
  }

  /// 打开订单页时：把超时卡死的订单一口气追到合理进度
  Future<List<ShopOrder>> _catchUpStaleOrders(List<ShopOrder> orders) async {
    final result = <ShopOrder>[];
    for (var order in orders) {
      var guard = 0;
      while (order.status != ShopDeliveryRules.statusDelivered && guard < 4) {
        guard++;
        final start = _stageStart(order);
        final maxSec = _stageMaxSeconds(order.status, order.itemId);
        final elapsed = DateTime.now().difference(start);
        if (elapsed.inSeconds < maxSec) {
          // 未超时：按剩余时间调度
          final remain = Duration(seconds: maxSec) - elapsed;
          final wait = remain.inSeconds < 3
              ? const Duration(seconds: 3)
              : remain;
          _cancelTimer(order.id);
          _deliveryTimers[order.id] = Timer(wait, () {
            if (isClosed) return;
            add(ShopAdvanceOrder(order.id));
          });
          break;
        }
        // 已超时：立即推进一阶段
        final next = _nextStatus(order.status);
        if (next == null) break;
        DateTime? preparingAt;
        DateTime? shippingAt;
        DateTime? deliveredAt;
        final now = DateTime.now();
        if (next == ShopDeliveryRules.statusPreparing) preparingAt = now;
        if (next == ShopDeliveryRules.statusShipping) shippingAt = now;
        if (next == ShopDeliveryRules.statusDelivered) deliveredAt = now;
        await _storage.updateOrderStatus(
          order.id,
          next,
          preparingAt: preparingAt,
          shippingAt: shippingAt,
          deliveredAt: deliveredAt,
        );
        order = order.copyWith(
          status: next,
          preparingAt: preparingAt ?? order.preparingAt,
          shippingAt: shippingAt ?? order.shippingAt,
          deliveredAt: deliveredAt ?? order.deliveredAt,
        );
        await _syncOrderChatMessage(order);
        debugPrint('追赶卡单 ${order.id} → $next（已超时 ${elapsed.inSeconds}s）');
      }
      if (order.status != ShopDeliveryRules.statusDelivered) {
        result.add(order);
      }
    }
    return result;
  }

  /// 聊天里的订单卡片读的是 message.metadata，状态变了要回写
  Future<void> _syncOrderChatMessage(ShopOrder order) async {
    if (order.chatSessionId.isEmpty) return;
    try {
      final msgs = await _storage.getChatMessages(order.chatSessionId);
      for (final m in msgs) {
        final meta = m.metadata;
        if (meta == null) continue;
        if (meta['type'] == 'shop_order' && meta['orderId'] == order.id) {
          await _storage.saveChatMessage(
            m.copyWith(metadata: {
              ...meta,
              ...order.toMetadata(),
            }),
          );
          break;
        }
      }
    } catch (e) {
      debugPrint('同步订单聊天卡片失败: $e');
    }
  }
}
