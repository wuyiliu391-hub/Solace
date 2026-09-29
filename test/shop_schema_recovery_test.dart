import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:solace/repositories/local_storage_repository.dart';

/// 商店数据库自愈回归测试。
///
/// 复现「中招用户」的场景：旧版 shop_items 表缺 isCustom / createdAt 列
/// （历史 rebuild 事务嵌积导致），验证修复后的幂等 schema 逻辑能：
/// 1. 把缺失的列补回来（自愈）；
/// 2. 让此前会崩溃的「带全列 INSERT」正常执行；
/// 3. 幂等 —— 重复运行无副作用。
void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  test('缺列的旧 shop_items 表被自愈补列，且带全列 INSERT 不再报错', () async {
    final db = await databaseFactoryFfi.openDatabase(':memory:');

    // —— 构造「中招用户」的数据库：旧版 shop_items，无 isCustom / createdAt ——
    await db.execute('''
      CREATE TABLE shop_items (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL DEFAULT '',
        category TEXT NOT NULL DEFAULT '',
        price INTEGER NOT NULL DEFAULT 0,
        emoji TEXT NOT NULL DEFAULT '',
        description TEXT DEFAULT '',
        tags TEXT DEFAULT '',
        isActive INTEGER NOT NULL DEFAULT 1
      )
    ''');

    var cols = await LocalStorageRepository.getTableColumns(db, 'shop_items');
    expect(cols.contains('isCustom'), isFalse, reason: '前置：确实缺 isCustom');
    expect(cols.contains('createdAt'), isFalse, reason: '前置：确实缺 createdAt');

    // —— 运行真实修复逻辑 ——
    await LocalStorageRepository.ensureShopItemsSchemaForTest(db);

    // —— 断言自愈：两列都补上了 ——
    cols = await LocalStorageRepository.getTableColumns(db, 'shop_items');
    expect(cols.contains('isCustom'), isTrue, reason: '自愈后应补上 isCustom');
    expect(cols.contains('createdAt'), isTrue, reason: '自愈后应补上 createdAt');

    // —— 断言：正是用户端崩溃的那句「带全列 INSERT」现在成功 ——
    await db.insert('shop_items', {
      'id': 'gift_01',
      'name': '棒棒糖',
      'category': 'gift',
      'price': 10,
      'emoji': '🍭',
      'description': '甜蜜的奖励',
      'tags': '',
      'isActive': 1,
      'isCustom': 0,
      'createdAt': '2026-07-26T22:55:32.894435',
    });
    final rows = await db.query('shop_items');
    expect(rows.length, 1);
    expect(rows.first['isCustom'], 0);

    await db.close();
  });

  test('全新表上运行 schema 逻辑：幂等、无副作用', () async {
    final db = await databaseFactoryFfi.openDatabase(':memory:');

    // 空库直接运行（模拟全新安装后进商店）
    await LocalStorageRepository.ensureShopItemsSchemaForTest(db);
    // 再运行一次，确认幂等
    await LocalStorageRepository.ensureShopItemsSchemaForTest(db);

    final cols = await LocalStorageRepository.getTableColumns(db, 'shop_items');
    expect(
      cols.containsAll(
          {'id', 'name', 'category', 'price', 'emoji', 'isCustom', 'createdAt'}),
      isTrue,
      reason: '全新表应含完整列',
    );

    await db.close();
  });
}
