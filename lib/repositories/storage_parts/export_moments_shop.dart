// LocalStorageRepository 导入导出 / 朋友圈 / 贴纸 / 商店 / 纯AI / v10 扩展 CRUD。
// 本文件是 local_storage_repository.dart 的 part，与其共同构成一个库。

part of '../local_storage_repository.dart';

mixin LocalStorageRepositoryMomentsShopApi on LocalStorageRepositoryChatMessagesApi {
  Future<void> clearAllData() async {
    if (_isWeb) {
      await _prefs?.clear();
    } else {
      final db = await _ensureDb();
      const allTables = [
        'users',
        'ai_characters',
        'ai_configs',
        'chat_sessions',
        'chat_messages',
        'memories',
        'moments',
        'sticker_packs',
        'ai_wallets',
        'shop_items',
        'shop_orders',
        'pure_ai_sessions',
        'pure_ai_messages',
        'inner_thoughts',
        'forum_posts',
        'forum_comments',
        'shared_album_entries',
        'virtual_locations',
        'persona_snapshots',
        'growth_events',
        'bt_agent_actions',
        'ai_letters',
        'intimacy_events',
        'character_commitments',
        'relationship_contexts',
        'moment_bookmarks',
        'moment_notifications',
        'trending_tags',
        'social_memories',
        // 虚拟手机模块
        'virtual_phones',
        'vp_contacts',
        'vp_chats',
        'vp_chat_messages',
        'vp_notes',
        'vp_moments',
        // 小说模块（DB v53）
        'novels',
        'novel_chapters',
      ];
      for (final table in allTables) {
        try {
          await db.delete(table);
        } catch (_) {
          // 表可能不存在，静默跳过
        }
      }
    }
    await _prefs?.clear();
  }

  Future<List<int>> exportToBytes({
    void Function(double progress, String message)? onProgress,
  }) async {
    final data = <String, dynamic>{};
    final prefsData = <String, dynamic>{};
    final db = await _ensureDb();
    const allTables = [
      'users',
      'ai_characters',
      'ai_configs',
      'chat_sessions',
      'chat_messages',
      'memories',
      'moments',
      'sticker_packs',
      'ai_wallets',
      'shop_items',
      'shop_orders',
      'pure_ai_sessions',
      'pure_ai_messages',
      'inner_thoughts',
      'forum_posts',
      'forum_comments',
      'shared_album_entries',
      'virtual_locations',
      'persona_snapshots',
      'growth_events',
      'bt_agent_actions',
      'ai_letters',
      'intimacy_events',
      'character_commitments',
      'relationship_contexts',
      'moment_bookmarks',
      'moment_notifications',
      'trending_tags',
      'social_memories',
      // 虚拟手机模块（DB v50）
      'virtual_phones',
      'vp_contacts',
      'vp_chats',
      'vp_chat_messages',
      'vp_notes',
      'vp_moments',
      // 小说模块（DB v53）
      'novels',
      'novel_chapters',
    ];
    for (int i = 0; i < allTables.length; i++) {
      final table = allTables[i];
      try {
        data[table] = await db.query(table);
      } catch (_) {
        data[table] = [];
      }
      onProgress?.call(
        (i + 1) / (allTables.length + 3) * 0.7,
        '正在导出 $table...',
      );
      await Future.delayed(Duration.zero); // 让出事件循环
    }
    onProgress?.call(0.7, '正在读取设置...');
    if (_prefs != null) {
      for (final key in _prefs!.getKeys()) {
        prefsData[key] = _prefs!.get(key);
      }
    }
    data['preferences'] = prefsData;
    data['exportTime'] = DateTime.now().toIso8601String();
    data['dbVersion'] = LocalStorageRepository._databaseVersion;
    data['version'] = LocalStorageRepository._databaseVersion;

    onProgress?.call(0.8, '正在收集文件...');
    String? docsPath;
    try {
      final dir = await getApplicationDocumentsDirectory();
      docsPath = dir.path;
    } catch (e) {
      debugPrint('获取文档目录失败: $e');
    }

    onProgress?.call(0.9, '正在压缩...');
    return compute(_compressExportData, {'data': data, 'docsPath': docsPath});
  }

  Future<Map<String, dynamic>> importFromBytes(List<int> bytes,
      {bool validateOnly = false,
      void Function(double progress, String message)? onProgress}) async {
    onProgress?.call(0.05, '正在解压数据...');
    // gzip 解码放到 isolate
    String jsonStr;
    try {
      jsonStr = await compute(_decodeGzipBytes, bytes);
    } catch (_) {
      try {
        jsonStr = utf8.decode(bytes);
      } catch (_) {
        throw Exception('无效的备份文件：数据格式损坏');
      }
    }
    await Future.delayed(Duration.zero);

    onProgress?.call(0.1, '正在解析数据...');
    // JSON 解析放到 isolate
    Map<String, dynamic> data;
    try {
      data = await compute(_parseJsonString, jsonStr);
    } catch (_) {
      try {
        final decrypted = await _tryDecryptOldBackup(jsonStr);
        data = await compute(_parseJsonString, decrypted);
      } catch (_) {
        throw Exception('无效的备份文件：JSON 解析失败');
      }
    }
    await Future.delayed(Duration.zero);
    data = _normalizeBackupData(data);

    onProgress?.call(0.15, '正在验证备份...');

    // 验证格式
    final hasMagic = data['magic'] == 'SOLACE_BACKUP_V1';
    final exportVersion = _parseBackupVersion(data['dbVersion']) ??
        _parseBackupVersion(data['version']);
    if (!hasMagic && exportVersion == null) {
      throw Exception('无效的备份文件：不是 Solace 数据备份');
    }
    if (exportVersion != null && exportVersion > LocalStorageRepository._databaseVersion) {
      throw Exception('备份文件来自更新版本，请升级应用后重试');
    }

    // 检查必要的数据表
    const requiredTables = [
      'users',
      'ai_characters',
      'ai_configs',
      'chat_sessions',
      'chat_messages'
    ];
    final hasKnownTable = requiredTables.any((table) => data[table] is List);
    if (!hasKnownTable) {
      throw Exception('备份文件不完整：缺少核心数据表');
    }

    // 提取账号信息
    String? accountInfo;
    final prefs = _asStringDynamicMap(data['preferences']);
    if (prefs != null) {
      final currentUserId = prefs['current_user_id'] as String?;
      if (currentUserId != null) {
        accountInfo = 'QQ: $currentUserId';
      }
    }

    if (validateOnly) {
      return {
        'valid': true,
        'version': exportVersion ?? 1,
        'accountInfo': accountInfo,
        'exportTime':
            data['exportTime'] ?? data['exportedAt'] ?? data['timestamp'],
      };
    }

    onProgress?.call(0.2, '正在恢复文件...');
    // 恢复本地文件
    Map<String, String> pathMap = {};
    final filesData = _asStringDynamicMap(data['files']);
    if (filesData != null && filesData.isNotEmpty) {
      final stringFiles = <String, String>{};
      for (final entry in filesData.entries) {
        if (entry.value is String) {
          stringFiles[entry.key] = entry.value as String;
        }
      }
      pathMap = await LocalStorageRepository.restoreLocalFiles(stringFiles);
      debugPrint('备份恢复：还原了 ${pathMap.length} 个本地文件');
    }
    await Future.delayed(Duration.zero);

    onProgress?.call(0.3, '正在准备数据库...');
    // 恢复数据表
    final db = await _ensureDb();
    await LocalStorageRepository.reconcileSchema(db, prefs: _prefs);

    const allTables = [
      'users',
      'ai_characters',
      'ai_configs',
      'chat_sessions',
      'chat_messages',
      'memories',
      'moments',
      'sticker_packs',
      'ai_wallets',
      'shop_items',
      'shop_orders',
      'pure_ai_sessions',
      'pure_ai_messages',
      'inner_thoughts',
      'forum_posts',
      'forum_comments',
      'shared_album_entries',
      'virtual_locations',
      'persona_snapshots',
      'growth_events',
      'bt_agent_actions',
      'ai_letters',
      'intimacy_events',
      'character_commitments',
      'relationship_contexts',
      'moment_bookmarks',
      'moment_notifications',
      'trending_tags',
      'social_memories',
      // 虚拟手机模块（DB v50）
      'virtual_phones',
      'vp_contacts',
      'vp_chats',
      'vp_chat_messages',
      'vp_notes',
      'vp_moments',
      // 小说模块（DB v53）
      'novels',
      'novel_chapters',
    ];

    final totalTables = allTables.length;
    await db.transaction((txn) async {
      // 增量导入：不删除已有数据，直接 upsert（缺的补上，冲突的更新）
      for (int i = 0; i < allTables.length; i++) {
        final table = allTables[i];
        final rows = data[table] as List<dynamic>?;
        if (rows != null) {
          Set<String> existingColumns;
          try {
            existingColumns = await LocalStorageRepository.getTableColumns(txn, table);
          } catch (_) {
            continue;
          }
          if (existingColumns.isEmpty) continue;
          for (final row in rows) {
            if (row is! Map) continue;
            final filteredRow = <String, dynamic>{};
            final rowMap =
                row.map((key, value) => MapEntry(key.toString(), value));
            for (final entry in rowMap.entries) {
              if (existingColumns.contains(entry.key)) {
                var value = entry.value;
                if (value is String && pathMap.containsKey(value)) {
                  value = pathMap[value]!;
                }
                filteredRow[entry.key] = value;
              }
            }
            try {
              await txn.insert(table, filteredRow,
                  conflictAlgorithm: ConflictAlgorithm.replace);
            } catch (e) {
              debugPrint('Error: $e');
            }
          }
        }
        // 事务内不能 await Future.delayed，进度在事务外报告
      }
    });

    // 事务结束后统一报告表导入进度
    for (int i = 0; i < totalTables; i++) {
      onProgress?.call(
        0.3 + (i + 1) / totalTables * 0.6,
        '已导入 ${allTables[i]}',
      );
      await Future.delayed(Duration.zero); // 让出事件循环，刷新 UI
    }

    await LocalStorageRepository.reconcileSchema(db, prefs: _prefs);

    onProgress?.call(0.92, '正在恢复设置...');
    // 恢复 SharedPreferences（增量合并：备份数据覆盖已有 key，本地独有 key 保留）
    if (prefs != null && _prefs != null) {
      for (final entry in prefs.entries) {
        final val = entry.value;
        if (val is String) {
          await _prefs!.setString(entry.key, val);
        } else if (val is int) {
          await _prefs!.setInt(entry.key, val);
        } else if (val is double) {
          await _prefs!.setDouble(entry.key, val);
        } else if (val is bool) {
          await _prefs!.setBool(entry.key, val);
        } else if (val is List) {
          await _prefs!.setStringList(entry.key, List<String>.from(val));
        }
      }
    }

    onProgress?.call(0.95, '正在清理...');
    // 清理无效背景图片路径
    if (_prefs != null) {
      final bgPath = _prefs!.getString('moments_background_image');
      if (bgPath != null && bgPath.isNotEmpty && !bgPath.startsWith('http')) {
        try {
          if (!await File(bgPath).exists()) {
            await _prefs!.remove('moments_background_image');
            debugPrint('导入清理：背景图片文件不存在，已清除引用');
          }
        } catch (_) {
          await _prefs!.remove('moments_background_image');
        }
      }
    }

    return {
      'valid': true,
      'version': exportVersion ?? 1,
      'accountInfo': accountInfo,
      'exportTime':
          data['exportTime'] ?? data['exportedAt'] ?? data['timestamp'],
    };
  }

  /// 尝试解密旧版本 AES 加密备份文件（兼容 iv:base64 格式）
  Future<String> _tryDecryptOldBackup(String encrypted) async {
    if (!encrypted.contains(':') ||
        !RegExp(r'^[A-Za-z0-9+/=]+:[A-Za-z0-9+/=]+$')
            .hasMatch(encrypted.trim())) {
      throw FormatException('not encrypted backup');
    }
    final password = _prefs?.getString('backup_password');
    if (password == null || password.isEmpty) {
      throw Exception('未找到备份密码');
    }
    final parts = encrypted.trim().split(':');
    final key = enc.Key(
        Uint8List.fromList(sha256.convert(utf8.encode(password)).bytes));
    final iv = enc.IV(base64.decode(parts[0]));
    final encrypter =
        enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc, padding: 'PKCS7'));
    return encrypter.decrypt64(parts[1], iv: iv);
  }

  Future<void> saveMoment(Moment moment) async {
    try {
      final db = await _ensureDb();
      // 老库 moments 可能缺 source / X 风格扩展列
      await LocalStorageRepository._addColumnIfNotExists(db, 'moments', 'source', 'INTEGER DEFAULT 0');
      await LocalStorageRepository._addColumnIfNotExists(
          db, 'moments', 'sync_seq', 'INTEGER DEFAULT 0');
      final map =
          await _filterMapToExistingColumns(db, 'moments', moment.toMap());
      final updated = await db
          .update('moments', map, where: 'id = ?', whereArgs: [moment.id]);
      if (updated == 0) {
        await db.insert('moments', map,
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    } catch (e) {
      debugPrint('saveMoment 失败: $e');
    }
  }

  Future<List<Moment>> getAllMoments({String? viewerId}) async {
    try {
      final db = await _ensureDb();
      // 老库可能没有 source 列
      await LocalStorageRepository._addColumnIfNotExists(db, 'moments', 'source', 'INTEGER DEFAULT 0');
      await LocalStorageRepository._addColumnIfNotExists(
          db, 'moments', 'blockedUserIds', 'TEXT');
      List<Map<String, Object?>> maps;
      try {
        maps = await db.query(
          'moments',
          where: 'source = ?',
          whereArgs: [LocalStorageRepository._normalMomentSource],
          orderBy: 'createdAt DESC',
        );
      } catch (e) {
        // 兜底：不带 source 条件读全表
        debugPrint('getAllMoments source 过滤失败，降级全表: $e');
        maps = await db.query('moments', orderBy: 'createdAt DESC');
      }
      var moments = maps.map((map) => Moment.fromMap(map)).toList();
      if (viewerId != null && viewerId.isNotEmpty) {
        // 「不让谁看」：观看者被作者拉黑时，对观看者隐藏该动态
        moments = moments
            .where((m) => !m.blockedUserIds.contains(viewerId))
            .toList();
      }
      return moments;
    } catch (e) {
      debugPrint('getAllMoments 失败: $e');
      return [];
    }
  }

  Future<bool> _checkTableExists(Database db, String tableName) async {
    final result = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
      [tableName],
    );
    return result.isNotEmpty;
  }

  Future<void> deleteMoment(String id) async {
    try {
      final db = await _ensureDb();
      await db.delete('moments', where: 'id = ?', whereArgs: [id]);
    } catch (e) {
      debugPrint('deleteMoment 失败: $e');
    }
  }

  Future<void> saveStickerPack(StickerPack pack) async {
    try {
      final db = await _ensureDb();
      await db.insert('sticker_packs', pack.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (e) {
      debugPrint('saveStickerPack 失败: $e');
    }
  }

  Future<List<StickerPack>> getAllStickerPacks() async {
    try {
      final db = await _ensureDb();
      final maps = await db.query('sticker_packs', orderBy: 'createdAt DESC');
      return maps.map((map) => StickerPack.fromMap(map)).toList();
    } catch (e) {
      debugPrint('getAllStickerPacks 失败: $e');
      return [];
    }
  }

  Future<StickerPack?> getStickerPack(String id) async {
    try {
      final db = await _ensureDb();
      final maps =
          await db.query('sticker_packs', where: 'id = ?', whereArgs: [id]);
      if (maps.isNotEmpty) {
        return StickerPack.fromMap(maps.first);
      }
      return null;
    } catch (e) {
      debugPrint('getStickerPack 失败: $e');
      return null;
    }
  }

  Future<void> deleteStickerPack(String id) async {
    try {
      final db = await _ensureDb();
      await db.delete('sticker_packs', where: 'id = ?', whereArgs: [id]);
    } catch (e) {
      debugPrint('deleteStickerPack 失败: $e');
    }
  }

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
          "SELECT COUNT(*) as cnt FROM shop_orders WHERE createdAt >= ? AND buyerType = 'ai' AND buyerId = ?",
          [today, characterId],
        );
        return (result.first['cnt'] as int?) ?? 0;
      }
      final result = await db.rawQuery(
        "SELECT COUNT(*) as cnt FROM shop_orders WHERE createdAt >= ? AND buyerType = 'ai'",
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
          try {
            await _insertShopItemSafe(db, item);
          } catch (e) {
            // 单个种子商品失败不影响其余，也绝不外抛到「加载失败」页
            debugPrint('[shop] seed insert skipped: ${item.id} ($e)');
          }
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
      ShopItem(
          id: 'gift_01',
          name: '棒棒糖',
          category: 'gift',
          price: 10,
          emoji: '🍭',
          description: '甜蜜的奖励'),
      ShopItem(
          id: 'gift_02',
          name: '小熊',
          category: 'gift',
          price: 50,
          emoji: '🧸',
          description: '毛茸茸的陪伴'),
      ShopItem(
          id: 'gift_03',
          name: '玫瑰',
          category: 'gift',
          price: 30,
          emoji: '🌹',
          description: '浪漫的表达'),
      ShopItem(
          id: 'gift_04',
          name: '巧克力',
          category: 'gift',
          price: 25,
          emoji: '🍫',
          description: '丝滑的心意'),
      ShopItem(
          id: 'gift_05',
          name: '水晶',
          category: 'gift',
          price: 100,
          emoji: '💎',
          description: '永恒的珍藏'),
      ShopItem(
          id: 'gift_06',
          name: '故事书',
          category: 'gift',
          price: 40,
          emoji: '📖',
          description: '共同的回忆'),
      ShopItem(
          id: 'gift_07',
          name: '音乐盒',
          category: 'gift',
          price: 60,
          emoji: '🎵',
          description: '旋律的礼物'),
      ShopItem(
          id: 'gift_08',
          name: '樱花',
          category: 'gift',
          price: 35,
          emoji: '🌸',
          description: '春日的气息'),
      ShopItem(
          id: 'gift_09',
          name: '水晶球',
          category: 'gift',
          price: 80,
          emoji: '🔮',
          description: '梦幻的回忆'),
      ShopItem(
          id: 'gift_10',
          name: '爱心',
          category: 'gift',
          price: 15,
          emoji: '💕',
          description: '满满的爱意'),

      // ═══ 外卖类 ═══
      ShopItem(
          id: 'food_01',
          name: '奶茶',
          category: 'food',
          price: 20,
          emoji: '🧋',
          description: '温暖的下午茶'),
      ShopItem(
          id: 'food_02',
          name: '蛋糕',
          category: 'food',
          price: 35,
          emoji: '🎂',
          description: '甜蜜的庆祝'),
      ShopItem(
          id: 'food_03',
          name: '鸡腿',
          category: 'food',
          price: 18,
          emoji: '🍗',
          description: '香喷喷的美食'),
      ShopItem(
          id: 'food_04',
          name: '火锅',
          category: 'food',
          price: 50,
          emoji: '🍲',
          description: '热腾腾的团圆'),
      ShopItem(
          id: 'food_05',
          name: '寿司',
          category: 'food',
          price: 45,
          emoji: '🍣',
          description: '精致的一餐'),
      ShopItem(
          id: 'food_06',
          name: '冰淇淋',
          category: 'food',
          price: 15,
          emoji: '🍦',
          description: '清凉的享受'),
      ShopItem(
          id: 'food_07',
          name: '水果',
          category: 'food',
          price: 25,
          emoji: '🍎',
          description: '健康的选择'),
      ShopItem(
          id: 'food_08',
          name: '烧烤',
          category: 'food',
          price: 40,
          emoji: '🍖',
          description: '烟火气的美味'),
      ShopItem(
          id: 'food_09',
          name: '披萨',
          category: 'food',
          price: 38,
          emoji: '🍕',
          description: '分享的快乐'),
      ShopItem(
          id: 'food_10',
          name: '饺子',
          category: 'food',
          price: 22,
          emoji: '🥟',
          description: '家的味道'),

      // ═══ 快递类 ═══
      ShopItem(
          id: 'express_01',
          name: '手套',
          category: 'express',
          price: 30,
          emoji: '🧤',
          description: '冬日的温暖'),
      ShopItem(
          id: 'express_02',
          name: '围巾',
          category: 'express',
          price: 45,
          emoji: '🧣',
          description: '贴心的呵护'),
      ShopItem(
          id: 'express_03',
          name: '书籍',
          category: 'express',
          price: 35,
          emoji: '📚',
          description: '知识的礼物'),
      ShopItem(
          id: 'express_04',
          name: '情书',
          category: 'express',
          price: 20,
          emoji: '💌',
          description: '真挚的告白'),
      ShopItem(
          id: 'express_05',
          name: '耳机',
          category: 'express',
          price: 80,
          emoji: '🎧',
          description: '音乐的陪伴'),
      ShopItem(
          id: 'express_06',
          name: '香薰',
          category: 'express',
          price: 40,
          emoji: '🕯️',
          description: '放松的氛围'),
      ShopItem(
          id: 'express_07',
          name: '拖鞋',
          category: 'express',
          price: 25,
          emoji: '🩴',
          description: '居家的舒适'),
      ShopItem(
          id: 'express_08',
          name: '礼盒',
          category: 'express',
          price: 55,
          emoji: '🎁',
          description: '惊喜的包装'),
      ShopItem(
          id: 'express_09',
          name: '星空灯',
          category: 'express',
          price: 70,
          emoji: '🌌',
          description: '梦幻的夜晚'),
      ShopItem(
          id: 'express_10',
          name: '抱枕',
          category: 'express',
          price: 35,
          emoji: '🛋️',
          description: '柔软的依靠'),
    ];
  }

  Future<List<PureAISession>> getPureAISessions(String userId) async {
    try {
      final db = await _ensureDb();
      final rows = await db.query('pure_ai_sessions',
          where: 'userId = ?',
          whereArgs: [userId],
          orderBy: 'isPinned DESC, lastMessageTime DESC, createdAt DESC');
      return rows.map((r) => PureAISession.fromMap(r)).toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> createPureAISession(PureAISession session) async {
    final db = await _ensureDb();
    await db.insert('pure_ai_sessions', session.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updatePureAISession(PureAISession session) async {
    final db = await _ensureDb();
    await db.update('pure_ai_sessions', session.toMap(),
        where: 'id = ?', whereArgs: [session.id]);
  }

  Future<void> deletePureAISession(String sessionId) async {
    final db = await _ensureDb();
    await db.delete('pure_ai_messages',
        where: 'sessionId = ?', whereArgs: [sessionId]);
    await db
        .delete('pure_ai_sessions', where: 'id = ?', whereArgs: [sessionId]);
  }

  Future<List<PureAIMessage>> getPureAIMessages(String sessionId) async {
    try {
      final db = await _ensureDb();
      final rows = await db.query('pure_ai_messages',
          where: 'sessionId = ?',
          whereArgs: [sessionId],
          orderBy: 'createdAt ASC');
      return rows.map((r) => PureAIMessage.fromMap(r)).toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> savePureAIMessage(PureAIMessage message) async {
    final db = await _ensureDb();
    await db.insert('pure_ai_messages', message.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<int> getTableCount(String table) async {
    final db = await _ensureDb();
    try {
      final result = await db.rawQuery('SELECT COUNT(*) as cnt FROM $table');
      return (result.first['cnt'] as int?) ?? 0;
    } catch (e) {
      return 0;
    }
  }

  // --- inner_thoughts ---
  Future<void> saveInnerThought(Map<String, dynamic> thought) async {
    final db = await _ensureDb();
    await db.insert('inner_thoughts', thought,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> getInnerThoughts({
    required String characterId,
    required String userId,
    int limit = 50,
  }) async {
    final db = await _ensureDb();
    return db.query('inner_thoughts',
        where: 'characterId = ? AND userId = ?',
        whereArgs: [characterId, userId],
        orderBy: 'createdAt DESC',
        limit: limit);
  }

  Future<void> markInnerThoughtRead(String id) async {
    final db = await _ensureDb();
    await db.update('inner_thoughts', {'isRead': 1},
        where: 'id = ?', whereArgs: [id]);
  }

  // --- character_commitments ---
  Future<void> saveCharacterCommitment(CharacterCommitment commitment) async {
    final db = await _ensureDb();
    await db.insert('character_commitments', commitment.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<CharacterCommitment?> getActiveCharacterCommitment({
    required String characterId,
    required String userId,
  }) async {
    final db = await _ensureDb();
    final rows = await db.query('character_commitments',
        where: 'characterId = ? AND userId = ? AND status = ?',
        whereArgs: [characterId, userId, CharacterCommitmentStatus.active.name],
        orderBy: 'dueAt ASC, updatedAt DESC',
        limit: 1);
    return rows.isEmpty ? null : CharacterCommitment.fromMap(rows.first);
  }

  Future<void> saveRelationshipContext(RelationshipContext context) async {
    final db = await _ensureDb();
    await db.insert('relationship_contexts', context.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<RelationshipContext?> getRelationshipContext(String chatId) async {
    final db = await _ensureDb();
    final rows = await db.query('relationship_contexts',
        where: 'chatId = ?', whereArgs: [chatId], limit: 1);
    return rows.isEmpty ? null : RelationshipContext.fromMap(rows.first);
  }

  // --- forum_posts ---
  Future<void> saveForumPost(Map<String, dynamic> post) async {
    final db = await _ensureDb();
    await db.insert('forum_posts', post,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> getForumPosts({int limit = 50}) async {
    final db = await _ensureDb();
    return db.query('forum_posts', orderBy: 'createdAt DESC', limit: limit);
  }

  Future<void> likeForumPost(String postId, String userId) async {
    final db = await _ensureDb();
    final posts = await db.query('forum_posts',
        where: 'id = ?', whereArgs: [postId], limit: 1);
    if (posts.isEmpty) return;
    final likes = List<String>.from(posts.first['likes'] as List? ?? []);
    if (!likes.contains(userId)) {
      likes.add(userId);
    }
    await db.update('forum_posts', {'likes': likes},
        where: 'id = ?', whereArgs: [postId]);
  }

  Future<void> deleteForumPost(String id) async {
    final db = await _ensureDb();
    await db.delete('forum_posts', where: 'id = ?', whereArgs: [id]);
    await db.delete('forum_comments', where: 'postId = ?', whereArgs: [id]);
  }

  // --- forum_comments ---
  Future<void> saveForumComment(Map<String, dynamic> comment) async {
    final db = await _ensureDb();
    await db.insert('forum_comments', comment,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> getForumComments(String postId) async {
    final db = await _ensureDb();
    return db.query('forum_comments',
        where: 'postId = ?', whereArgs: [postId], orderBy: 'createdAt ASC');
  }

  // --- shared_album_entries ---
  Future<void> saveSharedAlbumEntry(Map<String, dynamic> entry) async {
    final db = await _ensureDb();
    await db.insert('shared_album_entries', entry,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> getSharedAlbumEntries({
    required String characterId,
    required String userId,
  }) async {
    final db = await _ensureDb();
    return db.query('shared_album_entries',
        where: 'characterId = ? AND userId = ?',
        whereArgs: [characterId, userId],
        orderBy: 'eventDate DESC');
  }

  Future<void> deleteSharedAlbumEntry(String id) async {
    final db = await _ensureDb();
    await db.delete('shared_album_entries', where: 'id = ?', whereArgs: [id]);
  }

  // --- virtual_locations ---
  Future<void> saveVirtualLocation(Map<String, dynamic> loc) async {
    final db = await _ensureDb();
    await db.insert('virtual_locations', loc,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, dynamic>?> getLatestVirtualLocation({
    required String characterId,
    required String userId,
  }) async {
    final db = await _ensureDb();
    final results = await db.query('virtual_locations',
        where: 'characterId = ? AND userId = ?',
        whereArgs: [characterId, userId],
        orderBy: 'createdAt DESC',
        limit: 1);
    return results.isNotEmpty ? results.first : null;
  }

  // --- moments 扩展 ---
  Future<void> updateMomentAiLiked(String momentId) async {
    final db = await _ensureDb();
    await db.update('moments', {'aiLiked': 1},
        where: 'source = ? AND id = ?',
        whereArgs: [LocalStorageRepository._normalMomentSource, momentId]);
  }

  /// 获取信息流（排除回复帖，按时间倒序）
  /// [viewerId] 非空时，过滤掉作者「不让谁看」名单中包含该观看者的动态。
  Future<List<Moment>> getXMomentsFeed({String? viewerId}) async {
    final db = await _ensureDb();
    await LocalStorageRepository._addColumnIfNotExists(
        db, 'moments', 'blockedUserIds', 'TEXT');
    final maps = await db.query('moments',
        where: 'source = ? AND parentKey IS NULL',
        whereArgs: [LocalStorageRepository._xMomentSource],
        orderBy: 'createdAt DESC');
    var moments = maps.map((m) => Moment.fromMap(m)).toList();
    if (viewerId != null && viewerId.isNotEmpty) {
      moments = moments
          .where((m) => !m.blockedUserIds.contains(viewerId))
          .toList();
    }
    return moments;
  }

  /// 获取指定用户的动态（用于个人主页 Tab）
  Future<List<Moment>> getMomentsByUserId(String userId,
      {bool repliesOnly = false, bool mediaOnly = false}) async {
    final db = await _ensureDb();
    String where = 'source = ? AND userId = ?';
    final whereArgs = <dynamic>[LocalStorageRepository._xMomentSource, userId];
    if (repliesOnly) {
      where += ' AND parentKey IS NOT NULL';
    } else {
      where += ' AND parentKey IS NULL';
    }
    if (mediaOnly) {
      where += " AND images != '' AND images IS NOT NULL";
    }
    final maps = await db.query(
      'moments',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'createdAt DESC',
    );
    return maps.map((m) => Moment.fromMap(m)).toList();
  }

  /// 获取回复列表（直接回复某条动态）
  Future<List<Moment>> getRepliesByMomentId(String momentId) async {
    final db = await _ensureDb();
    final maps = await db.query('moments',
        where: 'source = ? AND parentKey = ?',
        whereArgs: [LocalStorageRepository._xMomentSource, momentId],
        orderBy: 'createdAt ASC');
    return maps.map((m) => Moment.fromMap(m)).toList();
  }

  /// 获取线程链（向上遍历 parentKey）
  Future<List<Moment>> getThreadChain(String momentId) async {
    final db = await _ensureDb();
    final chain = <Moment>[];
    var currentId = momentId;
    for (var i = 0; i < 20; i++) {
      // 防止无限循环
      final maps = await db.query('moments',
          where: 'source = ? AND id = ?',
          whereArgs: [LocalStorageRepository._xMomentSource, currentId],
          limit: 1);
      if (maps.isEmpty) break;
      final moment = Moment.fromMap(maps.first);
      chain.insert(0, moment);
      if (moment.parentKey == null || moment.parentKey!.isEmpty) break;
      currentId = moment.parentKey!;
    }
    return chain;
  }

  /// 递增转发计数
  Future<void> incrementRetweetCount(String momentId) async {
    final db = await _ensureDb();
    await db.rawUpdate(
        'UPDATE moments SET retweetCount = retweetCount + 1 WHERE source = ? AND id = ?',
        [LocalStorageRepository._xMomentSource, momentId]);
  }

  /// 递增回复计数
  Future<void> incrementReplyCount(String momentId) async {
    final db = await _ensureDb();
    await db.rawUpdate(
        'UPDATE moments SET replyCount = replyCount + 1 WHERE source = ? AND id = ?',
        [LocalStorageRepository._xMomentSource, momentId]);
  }

  /// 递增浏览量
  Future<void> incrementViewCount(String momentId) async {
    final db = await _ensureDb();
    await db.rawUpdate(
        'UPDATE moments SET viewCount = viewCount + 1 WHERE source = ? AND id = ?',
        [LocalStorageRepository._xMomentSource, momentId]);
  }

  /// 搜索动态（内容、标签、用户名）
  Future<List<Moment>> searchMoments(String query) async {
    final db = await _ensureDb();
    final maps = await db.query('moments',
        where:
            'source = ? AND (content LIKE ? OR userName LIKE ? OR tags LIKE ?)',
        whereArgs: [LocalStorageRepository._xMomentSource, '%$query%', '%$query%', '%$query%'],
        orderBy: 'createdAt DESC',
        limit: 50);
    return maps.map((m) => Moment.fromMap(m)).toList();
  }

  /// 按话题标签获取动态
  Future<List<Moment>> getMomentsByTag(String tag) async {
    final db = await _ensureDb();
    final maps = await db.query('moments',
        where: 'source = ? AND tags LIKE ?',
        whereArgs: [LocalStorageRepository._xMomentSource, '%"$tag"%'],
        orderBy: 'createdAt DESC');
    return maps.map((m) => Moment.fromMap(m)).toList();
  }

  Future<void> addBookmark(String momentId, String userId) async {
    final db = await _ensureDb();
    final moments = await db.query('moments',
        where: 'source = ? AND id = ?',
        whereArgs: [LocalStorageRepository._xMomentSource, momentId],
        limit: 1);
    if (moments.isEmpty) return;
    await db.insert('moment_bookmarks', {
      'id': '${momentId}_$userId',
      'momentId': momentId,
      'userId': userId,
      'createdAt': DateTime.now().toIso8601String(),
    });
    await db.rawUpdate(
        'UPDATE moments SET bookmarkCount = bookmarkCount + 1 WHERE source = ? AND id = ?',
        [LocalStorageRepository._xMomentSource, momentId]);
  }

  Future<void> removeBookmark(String momentId, String userId) async {
    final db = await _ensureDb();
    final deleted = await db.rawDelete('''
      DELETE FROM moment_bookmarks
      WHERE momentId = ?
        AND userId = ?
        AND EXISTS (
          SELECT 1 FROM moments
          WHERE moments.id = moment_bookmarks.momentId
            AND moments.source = ?
        )
    ''', [momentId, userId, LocalStorageRepository._xMomentSource]);
    if (deleted > 0) {
      await db.rawUpdate(
          'UPDATE moments SET bookmarkCount = MAX(0, bookmarkCount - 1) WHERE source = ? AND id = ?',
          [LocalStorageRepository._xMomentSource, momentId]);
    }
  }

  Future<bool> isBookmarked(String momentId, String userId) async {
    final db = await _ensureDb();
    final maps = await db.rawQuery('''
      SELECT b.id FROM moment_bookmarks b
      INNER JOIN moments m ON m.id = b.momentId
      WHERE b.momentId = ? AND b.userId = ? AND m.source = ?
      LIMIT 1
    ''', [momentId, userId, LocalStorageRepository._xMomentSource]);
    return maps.isNotEmpty;
  }

  Future<Set<String>> getBookmarkedMomentIds(String userId) async {
    final db = await _ensureDb();
    final maps = await db.rawQuery('''
      SELECT b.momentId FROM moment_bookmarks b
      INNER JOIN moments m ON m.id = b.momentId
      WHERE b.userId = ? AND m.source = ?
    ''', [userId, LocalStorageRepository._xMomentSource]);
    return maps.map((m) => m['momentId'] as String).toSet();
  }

  Future<List<Moment>> getBookmarkedMoments(String userId) async {
    final db = await _ensureDb();
    final maps = await db.rawQuery('''
      SELECT m.* FROM moments m
      INNER JOIN moment_bookmarks b ON m.id = b.momentId
      WHERE b.userId = ? AND m.source = ?
      ORDER BY b.createdAt DESC
    ''', [userId, LocalStorageRepository._xMomentSource]);
    return maps.map((m) => Moment.fromMap(m)).toList();
  }

  Future<void> saveMomentNotification(MomentNotification notification) async {
    final db = await _ensureDb();
    await db.insert('moment_notifications', notification.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<MomentNotification>> getMomentNotifications(
      {int limit = 50}) async {
    final db = await _ensureDb();
    final maps = await db.query('moment_notifications',
        orderBy: 'createdAt DESC', limit: limit);
    return maps.map((m) => MomentNotification.fromMap(m)).toList();
  }

  Future<void> markMomentNotificationRead(String notificationId) async {
    final db = await _ensureDb();
    await db.update('moment_notifications', {'isRead': 1},
        where: 'id = ?', whereArgs: [notificationId]);
  }

  Future<int> getUnreadMomentNotificationCount() async {
    final db = await _ensureDb();
    final result = await db.rawQuery(
        'SELECT COUNT(*) as cnt FROM moment_notifications WHERE isRead = 0');
    return (result.first['cnt'] as int?) ?? 0;
  }

  Future<void> updateTrendingTags(List<String> tags) async {
    final db = await _ensureDb();
    final now = DateTime.now().toIso8601String();
    for (final tag in tags) {
      await db.rawInsert('''
        INSERT INTO trending_tags (tag, count, lastUsedAt)
        VALUES (?, 1, ?)
        ON CONFLICT(tag) DO UPDATE SET
          count = count + 1,
          lastUsedAt = ?
      ''', [tag, now, now]);
    }
  }

  Future<List<TrendingTag>> getTrendingTags({int limit = 10}) async {
    final db = await _ensureDb();
    final maps =
        await db.query('trending_tags', orderBy: 'count DESC', limit: limit);
    return maps.map((m) => TrendingTag.fromMap(m)).toList();
  }

  // --- users 扩展 ---
  Future<void> updateUserWeather(String userId, String weather) async {
    final db = await _ensureDb();
    await db.update(
        'users',
        {
          'currentWeather': weather,
          'lastWeatherUpdate': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [userId]);
  }

  Future<void> updateUserLockScreen(
    String userId, {
    String? password,
    int? duration,
    String? textColor,
    double? fontSize,
  }) async {
    final updates = <String, dynamic>{};
    if (password != null) updates['lockScreenPassword'] = password;
    if (duration != null) updates['lockScreenDuration'] = duration;
    if (textColor != null) updates['lockScreenTextColor'] = textColor;
    if (fontSize != null) updates['lockScreenFontSize'] = fontSize;
    if (updates.isEmpty) return;
    final db = await _ensureDb();
    await db.update('users', updates, where: 'id = ?', whereArgs: [userId]);
  }

  Future<void> updateUserAppIcon(String userId, String? iconPath) async {
    final db = await _ensureDb();
    await db.update('users', {'appIconPath': iconPath},
        where: 'id = ?', whereArgs: [userId]);
  }
}
