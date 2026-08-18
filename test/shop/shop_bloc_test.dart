// ShopBloc 单元测试。
//
// 沿用本项目 mocktail 风格，用可变 Map 模拟「内存数据库」，
// 覆盖：商品加载/筛选、下单成功、余额不足、每日订单上限、
// AI 赠送上限、订单状态推进、送达确认、自定义商品增删。
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:solace/blocs/shop/shop_bloc.dart';
import 'package:solace/config/business_rules.dart';
import 'package:solace/models/chat_message.dart';
import 'package:solace/models/chat_session.dart';
import 'package:solace/models/shop_item.dart';
import 'package:solace/models/shop_order.dart';
import 'package:solace/repositories/local_storage_repository.dart';

class _MockStorage extends Mock implements LocalStorageRepository {}

ShopItem _item(
  String id,
  String name,
  String category,
  int price,
  String emoji, {
  bool isCustom = false,
}) {
  return ShopItem(
    id: id,
    name: name,
    category: category,
    price: price,
    emoji: emoji,
    isCustom: isCustom,
    createdAt: DateTime(2026, 8, 1),
  );
}

/// 等待事件级联处理完毕
Future<void> _pump([int milliseconds = 200]) =>
    Future<void>.delayed(Duration(milliseconds: milliseconds));

void main() {
  setUpAll(() {
    // mock 参数匹配需要 fallback 值
    registerFallbackValue(_item('fb', 'fb', 'gift', 1, '🎁'));
    registerFallbackValue(ShopOrder(
      id: 'fb',
      buyerType: 'user',
      buyerId: 'u',
      receiverType: 'ai',
      receiverId: 'a',
      chatSessionId: 's',
      itemId: 'i',
      itemName: 'n',
      itemEmoji: 'e',
      price: 1,
      createdAt: DateTime(2026, 8, 1),
    ));
    registerFallbackValue(ChatMessage(id: 'fb', senderId: 's'));
    registerFallbackValue(ChatSession(
      id: 'fb',
      userId: 'u',
      aiCharacterId: 'c',
      aiCharacterName: 'n',
      createdAt: DateTime(2026, 8, 1),
    ));
  });

  late _MockStorage storage;

  // 「内存数据库」
  final itemsById = <String, ShopItem>{};
  final ordersById = <String, ShopOrder>{};
  final ChatSession session = ChatSession(
    id: 'sess1',
    userId: 'u1',
    aiCharacterId: 'char1',
    aiCharacterName: '测试角色',
    intimacyLevel: 10,
    createdAt: DateTime(2026, 8, 1),
  );

  setUp(() {
    storage = _MockStorage();
    itemsById.clear();
    ordersById.clear();

    when(() => storage.initializeShopItems()).thenAnswer((_) async {});
    when(() => storage.getAllShopItems())
        .thenAnswer((_) async => itemsById.values.toList());
    when(() => storage.saveShopItem(any())).thenAnswer((inv) async {
      final i = inv.positionalArguments[0] as ShopItem;
      itemsById[i.id] = i;
    });
    when(() => storage.deleteShopItem(any())).thenAnswer((inv) async {
      itemsById.remove(inv.positionalArguments[0] as String);
    });

    when(() => storage.getTodayOrderCount())
        .thenAnswer((_) async => ordersById.length);
    when(() => storage.getTodayAIOrderCount(any()))
        .thenAnswer((_) async => 0);
    when(() => storage.spendCoins(any(), any()))
        .thenAnswer((_) async => true);
    when(() => storage.deductAICoins(any(), any()))
        .thenAnswer((_) async => true);

    when(() => storage.createShopOrder(any())).thenAnswer((inv) async {
      final o = inv.positionalArguments[0] as ShopOrder;
      ordersById[o.id] = o;
    });
    when(() => storage.getOrdersBySession(any())).thenAnswer((inv) async {
      final sessionId = inv.positionalArguments[0] as String;
      return ordersById.values
          .where((o) => o.chatSessionId == sessionId)
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    });
    when(() => storage.getActiveOrders()).thenAnswer((_) async =>
        ordersById.values
            .where((o) => o.status != ShopDeliveryRules.statusDelivered)
            .toList());
    when(() => storage.updateOrderStatus(
          any(),
          any(),
          preparingAt: any(named: 'preparingAt'),
          shippingAt: any(named: 'shippingAt'),
          deliveredAt: any(named: 'deliveredAt'),
          aiReaction: any(named: 'aiReaction'),
        )).thenAnswer((inv) async {
      final id = inv.positionalArguments[0] as String;
      final status = inv.positionalArguments[1] as String;
      final named = inv.namedArguments;
      final o = ordersById[id];
      if (o == null) return;
      ordersById[id] = o.copyWith(
        status: status,
        preparingAt: named[const Symbol('preparingAt')] as DateTime?,
        shippingAt: named[const Symbol('shippingAt')] as DateTime?,
        deliveredAt: named[const Symbol('deliveredAt')] as DateTime?,
        aiReaction: named[const Symbol('aiReaction')] as String?,
      );
    });
    when(() => storage.getShopOrder(any()))
        .thenAnswer((inv) async => ordersById[inv.positionalArguments[0] as String]);

    when(() => storage.getChatSession(any()))
        .thenAnswer((_) async => session);
    when(() => storage.saveChatSession(any())).thenAnswer((_) async {});
    when(() => storage.saveChatMessage(any())).thenAnswer((_) async {});
    when(() => storage.getChatMessages(any()))
        .thenAnswer((_) async => <ChatMessage>[]);
  });

  ShopBloc buildBloc() => ShopBloc(storage);

  group('ShopBloc 初始状态', () {
    test('默认值：空商品、分类 all、无加载', () {
      final bloc = buildBloc();
      expect(bloc.state.items, isEmpty);
      expect(bloc.state.filteredItems, isEmpty);
      expect(bloc.state.selectedCategory, 'all');
      expect(bloc.state.orders, isEmpty);
      expect(bloc.state.activeOrders, isEmpty);
      expect(bloc.state.isLoading, isFalse);
      expect(bloc.state.error, isNull);
      bloc.close();
    });
  });

  group('ShopLoadItems / ShopLoadItemsByCategory', () {
    test('加载成功：填充商品列表并初始化种子数据', () async {
      itemsById['gift_1'] = _item('gift_1', '棒棒糖', 'gift', 10, '🍭');
      itemsById['food_1'] = _item('food_1', '奶茶', 'food', 15, '🧋');

      final bloc = buildBloc();
      bloc.add(const ShopLoadItems());
      await _pump();

      verify(() => storage.initializeShopItems()).called(1);
      expect(bloc.state.isLoading, isFalse);
      expect(bloc.state.items.length, 2);
      expect(bloc.state.filteredItems.length, 2);
      expect(bloc.state.selectedCategory, 'all');

      await bloc.close();
    });

    test('加载空数据：商品列表为空', () async {
      final bloc = buildBloc();
      bloc.add(const ShopLoadItems());
      await _pump();

      expect(bloc.state.items, isEmpty);
      expect(bloc.state.filteredItems, isEmpty);
      expect(bloc.state.error, isNull);

      await bloc.close();
    });

    test('加载失败：error 携带「加载商品失败」', () async {
      when(() => storage.getAllShopItems()).thenThrow(Exception('表损坏'));

      final bloc = buildBloc();
      bloc.add(const ShopLoadItems());
      await _pump();

      expect(bloc.state.isLoading, isFalse);
      expect(bloc.state.error, contains('加载商品失败'));

      await bloc.close();
    });

    test('按分类筛选：food 分类只剩食物，all 恢复全部', () async {
      itemsById['gift_1'] = _item('gift_1', '棒棒糖', 'gift', 10, '🍭');
      itemsById['food_1'] = _item('food_1', '奶茶', 'food', 15, '🧋');

      final bloc = buildBloc();
      bloc.add(const ShopLoadItems());
      await _pump();

      bloc.add(const ShopLoadItemsByCategory('food'));
      await _pump();
      expect(bloc.state.selectedCategory, 'food');
      expect(bloc.state.filteredItems.length, 1);
      expect(bloc.state.filteredItems.first.id, 'food_1');

      bloc.add(const ShopLoadItemsByCategory('all'));
      await _pump();
      expect(bloc.state.selectedCategory, 'all');
      expect(bloc.state.filteredItems.length, 2);

      await bloc.close();
    });
  });

  group('ShopPlaceOrder', () {
    test('用户购买成功：扣币、建单、发系统消息并提升亲密度', () async {
      final item = _item('gift_1', '棒棒糖', 'gift', 10, '🍭');

      final bloc = buildBloc();
      bloc.add(ShopPlaceOrder(
        chatSessionId: 'sess1',
        buyerType: 'user',
        buyerId: 'u1',
        receiverType: 'ai',
        receiverId: 'char1',
        item: item,
      ));
      await _pump();

      // 扣除用户金币
      verify(() => storage.spendCoins('u1', 10)).called(1);
      // 订单落库且状态为 pending（物流第一阶段）
      final order = bloc.state.lastPlacedOrder;
      expect(order, isNotNull);
      expect(order!.status, ShopDeliveryRules.statusPending);
      expect(order.itemName, '棒棒糖');
      expect(order.price, 10);
      // 写入活跃订单列表
      expect(bloc.state.activeOrders.length, 1);
      expect(bloc.state.error, isNull);
      // 会话亲密度 +1（10 → 11）
      final savedSession = verify(() => storage.saveChatSession(captureAny()))
          .captured
          .cast<ChatSession>()
          .last;
      expect(savedSession.intimacyLevel, 11);
      // 聊天流写入订单卡片系统消息
      final savedMsg = verify(() => storage.saveChatMessage(captureAny()))
          .captured
          .cast<ChatMessage>()
          .last;
      expect(savedMsg.type, MessageType.system);
      expect(savedMsg.content, '🍭 棒棒糖');
      expect(savedMsg.metadata?['orderId'], order.id);

      await bloc.close();
    });

    test('余额不足：金币不足且不创建订单', () async {
      when(() => storage.spendCoins(any(), any()))
          .thenAnswer((_) async => false);
      final item = _item('gift_1', '钻石', 'gift', 999, '💎');

      final bloc = buildBloc();
      bloc.add(ShopPlaceOrder(
        chatSessionId: 'sess1',
        buyerType: 'user',
        buyerId: 'u1',
        receiverType: 'ai',
        receiverId: 'char1',
        item: item,
      ));
      await _pump();

      expect(bloc.state.error, '金币不足');
      expect(bloc.state.lastPlacedOrder, isNull);
      expect(bloc.state.activeOrders, isEmpty);
      verifyNever(() => storage.createShopOrder(any()));
      verifyNever(() => storage.saveChatMessage(any()));

      await bloc.close();
    });

    test('每日订单上限：拒绝下单且不扣币', () async {
      when(() => storage.getTodayOrderCount())
          .thenAnswer((_) async => CoinRules.shopMaxDailyOrders);

      final bloc = buildBloc();
      bloc.add(ShopPlaceOrder(
        chatSessionId: 'sess1',
        buyerType: 'user',
        buyerId: 'u1',
        receiverType: 'ai',
        receiverId: 'char1',
        item: _item('gift_1', '棒棒糖', 'gift', 10, '🍭'),
      ));
      await _pump();

      expect(bloc.state.error,
          contains('今日订单已达上限（${CoinRules.shopMaxDailyOrders}单）'));
      verifyNever(() => storage.spendCoins(any(), any()));
      verifyNever(() => storage.createShopOrder(any()));

      await bloc.close();
    });

    test('AI 每日赠送上限：拒绝赠送且不扣 AI 金币', () async {
      when(() => storage.getTodayAIOrderCount(any()))
          .thenAnswer((_) async => ShopAIRules.aiMaxGiftsPerDay);

      final bloc = buildBloc();
      bloc.add(ShopPlaceOrder(
        chatSessionId: 'sess1',
        buyerType: 'ai',
        buyerId: 'char1',
        receiverType: 'user',
        receiverId: 'u1',
        item: _item('gift_1', '棒棒糖', 'gift', 10, '🍭'),
      ));
      await _pump();

      expect(bloc.state.error, '今日赠送已达上限');
      verifyNever(() => storage.deductAICoins(any(), any()));
      verifyNever(() => storage.createShopOrder(any()));

      await bloc.close();
    });

    test('AI 买家下单成功：走 AI 钱包扣款通道', () async {
      final bloc = buildBloc();
      bloc.add(ShopPlaceOrder(
        chatSessionId: 'sess1',
        buyerType: 'ai',
        buyerId: 'char1',
        receiverType: 'user',
        receiverId: 'u1',
        item: _item('gift_1', '棒棒糖', 'gift', 10, '🍭'),
      ));
      await _pump();

      verify(() => storage.deductAICoins('char1', 10)).called(1);
      verifyNever(() => storage.spendCoins(any(), any()));
      expect(bloc.state.lastPlacedOrder, isNotNull);
      expect(bloc.state.error, isNull);
      // 送给用户（receiverType=user）不动会话亲密度
      verifyNever(() => storage.saveChatSession(any()));

      await bloc.close();
    });
  });

  group('ShopLoadOrders / ShopUpdateOrderStatus / ShopOrderDelivered', () {
    Future<ShopOrder> placeOrder(ShopBloc bloc) async {
      bloc.add(ShopPlaceOrder(
        chatSessionId: 'sess1',
        buyerType: 'user',
        buyerId: 'u1',
        receiverType: 'ai',
        receiverId: 'char1',
        item: _item('gift_1', '棒棒糖', 'gift', 10, '🍭'),
      ));
      await _pump();
      return bloc.state.lastPlacedOrder!;
    }

    test('加载会话订单：填充 orders 列表', () async {
      final bloc = buildBloc();
      final order = await placeOrder(bloc);

      bloc.add(const ShopLoadOrders('sess1'));
      await _pump();

      expect(bloc.state.orders.length, 1);
      expect(bloc.state.orders.first.id, order.id);

      await bloc.close();
    });

    test('更新订单状态：pending → preparing 且记录 preparingAt', () async {
      final bloc = buildBloc();
      final order = await placeOrder(bloc);

      bloc.add(ShopUpdateOrderStatus(
        orderId: order.id,
        status: ShopDeliveryRules.statusPreparing,
      ));
      await _pump();

      final active = bloc.state.activeOrders.single;
      expect(active.status, ShopDeliveryRules.statusPreparing);
      expect(active.preparingAt, isNotNull);
      verify(() => storage.updateOrderStatus(order.id,
          ShopDeliveryRules.statusPreparing,
          preparingAt: any(named: 'preparingAt'),
          shippingAt: any(named: 'shippingAt'),
          deliveredAt: any(named: 'deliveredAt'),
          aiReaction: any(named: 'aiReaction'))).called(1);

      await bloc.close();
    });

    test('订单送达确认：从活跃列表移除并更新会话订单状态', () async {
      final bloc = buildBloc();
      final order = await placeOrder(bloc);

      // 先把订单加载进会话列表，再确认送达
      bloc.add(const ShopLoadOrders('sess1'));
      await _pump();

      bloc.add(ShopOrderDelivered(orderId: order.id));
      await _pump();

      expect(bloc.state.activeOrders, isEmpty);
      expect(bloc.state.orders.first.status,
          ShopDeliveryRules.statusDelivered);
      expect(bloc.state.orders.first.deliveredAt, isNotNull);
      // 内存库中的订单状态同步为 delivered
      expect(ordersById[order.id]!.status,
          ShopDeliveryRules.statusDelivered);

      await bloc.close();
    });
  });

  group('ShopSaveCustomItem / ShopDeleteCustomItem', () {
    test('保存自定义商品：强制 isCustom/isActive 并出现在列表中', () async {
      itemsById['gift_1'] = _item('gift_1', '棒棒糖', 'gift', 10, '🍭');

      final bloc = buildBloc();
      bloc.add(const ShopLoadItems());
      await _pump();

      bloc.add(ShopSaveCustomItem(
        _item('custom_1', '手织围巾', 'gift', 20, '🧣'),
      ));
      await _pump();

      // 落库时被标记为自定义商品
      expect(itemsById['custom_1']!.isCustom, isTrue);
      expect(itemsById['custom_1']!.isActive, isTrue);
      expect(bloc.state.items.length, 2);
      expect(bloc.state.filteredItems.map((i) => i.id),
          contains('custom_1'));

      await bloc.close();
    });

    test('删除自定义商品：从列表移除', () async {
      itemsById['custom_1'] = _item('custom_1', '手织围巾', 'gift', 20, '🧣',
          isCustom: true);

      final bloc = buildBloc();
      bloc.add(const ShopLoadItems());
      await _pump();
      expect(bloc.state.items.length, 1);

      bloc.add(const ShopDeleteCustomItem('custom_1'));
      await _pump();

      verify(() => storage.deleteShopItem('custom_1')).called(1);
      expect(bloc.state.items, isEmpty);
      expect(bloc.state.error, isNull);

      await bloc.close();
    });
  });
}
