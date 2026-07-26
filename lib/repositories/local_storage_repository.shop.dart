part of 'local_storage_repository.dart';

/// 商店相关数据访问（Shop Orders / Shop Items）。
///
/// 从 [LocalStorageRepository] 拆分而来（part + extension），调用方无需改动；
/// 与主文件同库，可访问 _ensureDb() / _prefs / _isWeb 等私有成员。
extension StorageShopDao on LocalStorageRepository {
  // ==================== Shop Orders ====================

  Future<void> updateOrderStatus(
    String orderId,
    String status, {
    DateTime? preparingAt,
    DateTime? shippingAt,
    DateTime? deliveredAt,
    String? aiReaction,
  }) async {
    try {
      final db = await _ensureDb();
      final updates = <String, dynamic>{
        'status': status,
      };
      if (preparingAt != null)
        updates['preparingAt'] = preparingAt.toIso8601String();
      if (shippingAt != null)
        updates['shippingAt'] = shippingAt.toIso8601String();
      if (deliveredAt != null)
        updates['deliveredAt'] = deliveredAt.toIso8601String();
      if (aiReaction != null) updates['aiReaction'] = aiReaction;
      await db.update('shop_orders', updates,
          where: 'id = ?', whereArgs: [orderId]);
    } catch (e) {
      debugPrint('updateOrderStatus 失败: $e');
    }
  }

  Future<List<ShopOrder>> getOrdersBySession(String chatSessionId) async {
    try {
      final db = await _ensureDb();
      final maps = await db.query('shop_orders',
          where: 'chatSessionId = ?',
          whereArgs: [chatSessionId],
          orderBy: 'createdAt DESC');
      return maps.map((m) => ShopOrder.fromMap(m)).toList();
    } catch (e) {
      return [];
    }
  }

  Future<List<ShopOrder>> getActiveOrders() async {
    try {
      final db = await _ensureDb();
      final maps = await db.query('shop_orders',
          where: "status != ?",
          whereArgs: ['delivered'],
          orderBy: 'createdAt DESC');
      return maps.map((m) => ShopOrder.fromMap(m)).toList();
    } catch (e) {
      return [];
    }
  }

  Future<List<ShopOrder>> getCompletedOrders() async {
    try {
      final db = await _ensureDb();
      final maps = await db.query('shop_orders',
          where: "status = ?",
          whereArgs: ['delivered'],
          orderBy: 'deliveredAt DESC');
      return maps.map((m) => ShopOrder.fromMap(m)).toList();
    } catch (e) {
      return [];
    }
  }

  Future<int> getTodayOrderCount() async {
    try {
      final db = await _ensureDb();
      final today = DateTime.now().toIso8601String().substring(0, 10);
      final result = await db.rawQuery(
        "SELECT COUNT(*) as cnt FROM shop_orders WHERE createdAt >= ?",
        [today],
      );
      return (result.first['cnt'] as int?) ?? 0;
    } catch (e) {
      return 0;
    }
  }

  Future<int> getTodayAIOrderCount([String? characterId]) async {
    try {
      final db = await _ensureDb();
      final today = DateTime.now().toIso8601String().substring(0, 10);
      if (characterId != null) {
        final result = await db.rawQuery(
          "SELECT COUNT(*) as cnt FROM shop_orders WHERE createdAt >= ? AND isFromAI = 1 AND buyerId = ?",
          [today, characterId],
        );
        return (result.first['cnt'] as int?) ?? 0;
      }
      final result = await db.rawQuery(
        "SELECT COUNT(*) as cnt FROM shop_orders WHERE createdAt >= ? AND isFromAI = 1",
        [today],
      );
      return (result.first['cnt'] as int?) ?? 0;
    } catch (e) {
      return 0;
    }
  }

  Future<void> createShopOrder(ShopOrder order) async {
    final db = await _ensureDb();
    await db.insert('shop_orders', order.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<ShopOrder?> getShopOrder(String orderId) async {
    try {
      final db = await _ensureDb();
      final maps = await db.query(
        'shop_orders',
        where: 'id = ?',
        whereArgs: [orderId],
        limit: 1,
      );
      if (maps.isEmpty) return null;
      return ShopOrder.fromMap(maps.first);
    } catch (e) {
      debugPrint('getShopOrder 失败: $e');
      return null;
    }
  }

  // ==================== Shop Items ====================

  Future<void> initializeShopItems() async {
    try {
      final db = await _ensureDb();
      // 每次进入商店都强制校验表结构（不依赖 dbVersion 是否已升过）
      await LocalStorageRepository._ensureShopItemsSchema(db, force: true);
      final count = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM shop_items'),
      );
      if (count == null || count == 0) {
        final items = _seedShopItems();
        for (final item in items) {
          await _insertShopItemSafe(db, item);
        }
      }
    } catch (e) {
      debugPrint('initializeShopItems 失败: $e');
    }
  }

  Future<List<ShopItem>> getAllShopItems() async {
    try {
      final db = await _ensureDb();
      await LocalStorageRepository._ensureShopItemsSchema(db);
      // 自定义商品靠前，再按分类 + 价格
      final maps = await db.query(
        'shop_items',
        where: 'isActive = 1 OR isActive IS NULL',
        orderBy: 'isCustom DESC, category ASC, price ASC, name ASC',
      );
      return maps.map((m) => ShopItem.fromMap(m)).toList();
    } catch (e) {
      debugPrint('getAllShopItems 失败: $e');
      // 兜底：无 orderBy 再读一次，避免黑屏空页
      try {
        final db = await _ensureDb();
        await LocalStorageRepository._ensureShopItemsSchema(db, force: true);
        final maps = await db.query('shop_items');
        return maps.map((m) => ShopItem.fromMap(m)).toList();
      } catch (e2) {
        debugPrint('getAllShopItems 兜底失败: $e2');
        return [];
      }
    }
  }

  Future<void> saveShopItem(ShopItem item) async {
    final db = await _ensureDb();
    await _insertShopItemSafe(db, item);
  }

  Future<void> deleteShopItem(String id) async {
    final db = await _ensureDb();
    // 仅允许删自定义；系统种子软隐藏更安全，但自定义可硬删
    final maps = await db.query(
      'shop_items',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isEmpty) return;
    final item = ShopItem.fromMap(maps.first);
    if (item.isCustom) {
      await db.delete('shop_items', where: 'id = ?', whereArgs: [id]);
    } else {
      await db.update(
        'shop_items',
        {'isActive': 0},
        where: 'id = ?',
        whereArgs: [id],
      );
    }
  }

  Future<ShopItem?> getShopItem(String id) async {
    try {
      final db = await _ensureDb();
      final maps = await db.query(
        'shop_items',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (maps.isEmpty) return null;
      return ShopItem.fromMap(maps.first);
    } catch (e) {
      return null;
    }
  }

  List<ShopItem> _seedShopItems() {
    return const [
      // ═══ 礼物类 ═══
      ShopItem(id: 'gift_01', name: '棒棒糖', category: 'gift', price: 10, emoji: '🍭', description: '甜蜜的奖励'),
      ShopItem(id: 'gift_02', name: '小熊', category: 'gift', price: 50, emoji: '🧸', description: '毛茸茸的陪伴'),
      ShopItem(id: 'gift_03', name: '玫瑰', category: 'gift', price: 30, emoji: '🌹', description: '浪漫的表达'),
      ShopItem(id: 'gift_04', name: '巧克力', category: 'gift', price: 25, emoji: '🍫', description: '丝滑的心意'),
      ShopItem(id: 'gift_05', name: '水晶', category: 'gift', price: 100, emoji: '💎', description: '永恒的珍藏'),
      ShopItem(id: 'gift_06', name: '故事书', category: 'gift', price: 40, emoji: '📖', description: '共同的回忆'),
      ShopItem(id: 'gift_07', name: '音乐盒', category: 'gift', price: 60, emoji: '🎵', description: '旋律的礼物'),
      ShopItem(id: 'gift_08', name: '樱花', category: 'gift', price: 35, emoji: '🌸', description: '春日的气息'),
      ShopItem(id: 'gift_09', name: '水晶球', category: 'gift', price: 80, emoji: '🔮', description: '梦幻的回忆'),
      ShopItem(id: 'gift_10', name: '爱心', category: 'gift', price: 15, emoji: '💕', description: '满满的爱意'),

      // ═══ 外卖类 ═══
      ShopItem(id: 'food_01', name: '奶茶', category: 'food', price: 20, emoji: '🧋', description: '温暖的下午茶'),
      ShopItem(id: 'food_02', name: '蛋糕', category: 'food', price: 35, emoji: '🎂', description: '甜蜜的庆祝'),
      ShopItem(id: 'food_03', name: '鸡腿', category: 'food', price: 18, emoji: '🍗', description: '香喷喷的美食'),
      ShopItem(id: 'food_04', name: '火锅', category: 'food', price: 50, emoji: '🍲', description: '热腾腾的团圆'),
      ShopItem(id: 'food_05', name: '寿司', category: 'food', price: 45, emoji: '🍣', description: '精致的一餐'),
      ShopItem(id: 'food_06', name: '冰淇淋', category: 'food', price: 15, emoji: '🍦', description: '清凉的享受'),
      ShopItem(id: 'food_07', name: '水果', category: 'food', price: 25, emoji: '🍎', description: '健康的选择'),
      ShopItem(id: 'food_08', name: '烧烤', category: 'food', price: 40, emoji: '🍖', description: '烟火气的美味'),
      ShopItem(id: 'food_09', name: '披萨', category: 'food', price: 38, emoji: '🍕', description: '分享的快乐'),
      ShopItem(id: 'food_10', name: '饺子', category: 'food', price: 22, emoji: '🥟', description: '家的味道'),

      // ═══ 快递类 ═══
      ShopItem(id: 'express_01', name: '手套', category: 'express', price: 30, emoji: '🧤', description: '冬日的温暖'),
      ShopItem(id: 'express_02', name: '围巾', category: 'express', price: 45, emoji: '🧣', description: '贴心的呵护'),
      ShopItem(id: 'express_03', name: '书籍', category: 'express', price: 35, emoji: '📚', description: '知识的礼物'),
      ShopItem(id: 'express_04', name: '情书', category: 'express', price: 20, emoji: '💌', description: '真挚的告白'),
      ShopItem(id: 'express_05', name: '耳机', category: 'express', price: 80, emoji: '🎧', description: '音乐的陪伴'),
      ShopItem(id: 'express_06', name: '香薰', category: 'express', price: 40, emoji: '🕯️', description: '放松的氛围'),
      ShopItem(id: 'express_07', name: '拖鞋', category: 'express', price: 25, emoji: '🩴', description: '居家的舒适'),
      ShopItem(id: 'express_08', name: '礼盒', category: 'express', price: 55, emoji: '🎁', description: '惊喜的包装'),
      ShopItem(id: 'express_09', name: '星空灯', category: 'express', price: 70, emoji: '🌌', description: '梦幻的夜晚'),
      ShopItem(id: 'express_10', name: '抱枕', category: 'express', price: 35, emoji: '🛋️', description: '柔软的依靠'),
    ];
  }
}
