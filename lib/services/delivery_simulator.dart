import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart' show debugPrint;
import '../models/shop_order.dart';
import '../repositories/local_storage_repository.dart';
import '../config/business_rules.dart';

/// 配送模拟服务：管理订单状态自动流转
/// pending → preparing → shipping → delivered
class DeliverySimulator {
  final LocalStorageRepository _storage;
  final _random = Random();
  final Map<String, Timer> _activeTimers = {};

  DeliverySimulator(this._storage);

  /// 启动订单配送模拟
  void startDelivery(ShopOrder order) {
    if (_activeTimers.containsKey(order.id)) return;

    final category = order.itemId.startsWith('food')
        ? 'food'
        : order.itemId.startsWith('express')
            ? 'express'
            : 'gift';

    // pending → preparing
    final pendingDuration = _randomDuration(
      ShopDeliveryRules.pendingMinSeconds,
      ShopDeliveryRules.pendingMaxSeconds,
    );

    _activeTimers[order.id] = Timer(pendingDuration, () async {
      await _transitionToPreparing(order, category);
    });

    debugPrint('配送开始: ${order.itemName} (${order.id})');
  }

  Future<void> _transitionToPreparing(
    ShopOrder order,
    String category,
  ) async {
    await _storage.updateOrderStatus(
      order.id,
      ShopDeliveryRules.statusPreparing,
      preparingAt: DateTime.now(),
    );

    // preparing → shipping
    var preparingDuration = _randomDuration(
      ShopDeliveryRules.preparingMinSeconds,
      ShopDeliveryRules.preparingMaxSeconds,
    );

    // 食品配送更快，快递更慢
    if (category == 'food') {
      preparingDuration = Duration(
        seconds: (preparingDuration.inSeconds *
                ShopDeliveryRules.foodSpeedMultiplier)
            .round(),
      );
    } else if (category == 'express') {
      preparingDuration = Duration(
        seconds: (preparingDuration.inSeconds *
                ShopDeliveryRules.expressSpeedMultiplier)
            .round(),
      );
    }

    _activeTimers[order.id] = Timer(preparingDuration, () async {
      await _transitionToShipping(order, category);
    });
  }

  Future<void> _transitionToShipping(
    ShopOrder order,
    String category,
  ) async {
    await _storage.updateOrderStatus(
      order.id,
      ShopDeliveryRules.statusShipping,
      shippingAt: DateTime.now(),
    );

    // shipping → delivered
    var shippingDuration = _randomDuration(
      ShopDeliveryRules.shippingMinSeconds,
      ShopDeliveryRules.shippingMaxSeconds,
    );

    if (category == 'food') {
      shippingDuration = Duration(
        seconds: (shippingDuration.inSeconds *
                ShopDeliveryRules.foodSpeedMultiplier)
            .round(),
      );
    } else if (category == 'express') {
      shippingDuration = Duration(
        seconds: (shippingDuration.inSeconds *
                ShopDeliveryRules.expressSpeedMultiplier)
            .round(),
      );
    }

    _activeTimers[order.id] = Timer(shippingDuration, () async {
      await _completeDelivery(order);
    });
  }

  Future<void> _completeDelivery(ShopOrder order) async {
    // 生成AI反应文本
    final aiReaction = await _generateAIReaction(order);

    await _storage.updateOrderStatus(
      order.id,
      ShopDeliveryRules.statusDelivered,
      deliveredAt: DateTime.now(),
      aiReaction: aiReaction,
    );

    _activeTimers.remove(order.id);
    debugPrint('订单已送达: ${order.itemName} (${order.id})');
  }

  /// 生成AI收到礼物后的反应
  Future<String?> _generateAIReaction(ShopOrder order) async {
    // 只有用户送给AI的订单才生成反应
    if (order.buyerType != 'user' || order.receiverType != 'ai') {
      return null;
    }

    try {
      // 获取AI角色信息
      final character = await _storage.getAICharacter(order.receiverId);
      if (character == null) return null;

      // 根据商品类型和AI性格生成反应
      final reactions = _getReactionsByCategory(
        order.itemEmoji,
        character.personality,
      );
      return reactions[_random.nextInt(reactions.length)];
    } catch (e) {
      debugPrint('生成AI反应失败: $e');
      return null;
    }
  }

  List<String> _getReactionsByCategory(
    String emoji,
    String personality,
  ) {
    final isWarm = personality.contains('温柔') || personality.contains('体贴');
    final isCool = personality.contains('高冷') || personality.contains('酷');
    final isBouncy =
        personality.contains('活泼') || personality.contains('开朗');

    if (isCool) {
      return [
        '$emoji 还不错吧，勉强收下了。',
        '$emoji 放那儿吧，有心了。',
        '$emoji 嗯，我收下了。',
      ];
    } else if (isBouncy) {
      return [
        '哇！$emoji 超喜欢！谢谢～',
        '$emoji 太开心了！你怎么知道我喜欢这个！',
        '收到$emoji！开心得转圈圈～',
      ];
    } else {
      // 温柔/默认
      return [
        '$emoji 谢谢你，我很喜欢～',
        '收到$emoji，感觉好幸福。',
        '$emoji 好开心，你总是这么贴心。',
      ];
    }
  }

  /// 取消订单的配送计时器
  void cancelDelivery(String orderId) {
    _activeTimers[orderId]?.cancel();
    _activeTimers.remove(orderId);
  }

  /// 取消所有计时器
  void cancelAll() {
    for (final timer in _activeTimers.values) {
      timer.cancel();
    }
    _activeTimers.clear();
  }

  /// 恢复进行中的订单（app重启后）
  Future<void> resumeActiveOrders() async {
    try {
      final activeOrders = await _storage.getActiveOrders();
      for (final order in activeOrders) {
        if (order.status != ShopDeliveryRules.statusDelivered) {
          // 为未完成的订单重新启动计时器
          // 使用较短的延迟来快速完成
          _resumeOrder(order);
        }
      }
    } catch (e) {
      debugPrint('恢复订单失败: $e');
    }
  }

  void _resumeOrder(ShopOrder order) {
    final remaining = _getRemainingDuration(order);
    _activeTimers[order.id] = Timer(remaining, () async {
      await _completeDelivery(order);
    });
    debugPrint('恢复配送: ${order.itemName}, 剩余 ${remaining.inSeconds}s');
  }

  Duration _getRemainingDuration(ShopOrder order) {
    // 根据当前状态计算剩余时间
    switch (order.status) {
      case 'pending':
        return _randomDuration(5, 15); // 缩短等待
      case 'preparing':
        return _randomDuration(10, 30);
      case 'shipping':
        return _randomDuration(15, 45);
      default:
        return const Duration(seconds: 5);
    }
  }

  /// 生成随机时间间隔
  Duration _randomDuration(int minSeconds, int maxSeconds) {
    final seconds = minSeconds + _random.nextInt(maxSeconds - minSeconds + 1);
    return Duration(seconds: seconds);
  }

  /// 获取当前活跃的订单ID列表
  List<String> get activeOrderIds => _activeTimers.keys.toList();

  /// 清理资源
  void dispose() {
    cancelAll();
  }
}
