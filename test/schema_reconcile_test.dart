// schema 自愈回归测试：老库缺表/缺列必须被 reconcileSchema 自动补齐。
//
// 背景（2026-10-01 审计）：expectedColumns 是唯一的补列自愈来源，
// 漏声明一列 → 该列在老库上永远补不上 → 表现为「新版功能在新装能用、
// 覆盖升级的用户直接崩」。本次审计发现 relationship_contexts.chatId 与
// group_chat_sessions 的 chatId 等列曾长期只在 _onUpgrade 里补、
// 没进 expectedColumns。本测试把关键表的关键列钉死，防止再漏。
//
// 初始化方式抄 test/shop_schema_recovery_test.dart（sqflite_common_ffi）。
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/repositories/local_storage_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<Set<String>> _cols(Database db, String table) async {
  final info = await db.rawQuery('PRAGMA table_info($table)');
  return info.map((r) => r['name'] as String).toSet();
}

Future<void> _expectCols(
    Database db, String table, List<String> cols) async {
  final names = await _cols(db, table);
  expect(names.isNotEmpty, isTrue, reason: '缺少表 $table');
  for (final c in cols) {
    expect(names, contains(c), reason: '$table 缺列 $c');
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  group('reconcileSchema · 缺表自愈', () {
    test('空库启动后收藏/跳转相关表全部存在', () async {
      final db = await databaseFactoryFfi.openDatabase(':memory:');
      await LocalStorageRepository.reconcileSchema(db);
      for (final t in [
        'users',
        'chat_sessions',
        'chat_messages',
        'group_chat_sessions',
        'group_chat_messages',
        'moment_bookmarks',
      ]) {
        final rows = await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
            [t]);
        expect(rows.isNotEmpty, isTrue, reason: '缺少表 $t');
      }
      await db.close();
    });
  });

  group('reconcileSchema · 缺列自愈', () {
    test('users 缺 chatAlias（v76 新增）会被自动补上', () async {
      final db = await databaseFactoryFfi.openDatabase(':memory:');
      // 造一个「v75 老库」users 表：故意不含 chatAlias
      await db.execute('''CREATE TABLE users (
        id TEXT PRIMARY KEY,
        nickname TEXT NOT NULL,
        avatarUrl TEXT,
        createdAt TEXT NOT NULL,
        lastLoginAt TEXT,
        signature TEXT,
        gender TEXT,
        birthday TEXT,
        location TEXT,
        bio TEXT,
        status TEXT,
        backgroundImage TEXT,
        coins INTEGER NOT NULL DEFAULT 100,
        totalCoinsEarned INTEGER NOT NULL DEFAULT 100,
        totalCoinsSpent INTEGER NOT NULL DEFAULT 0,
        sync_seq INTEGER NOT NULL DEFAULT 0
      )''');

      await LocalStorageRepository.reconcileSchema(db);

      await _expectCols(
          db, 'users', ['chatAlias', 'backgroundImageLandscape']);
      await db.close();
    });

    test('chat_messages 缺 isBookmark 会被补上（收藏功能依赖）', () async {
      final db = await databaseFactoryFfi.openDatabase(':memory:');
      await db.execute('''CREATE TABLE chat_messages (
        id TEXT PRIMARY KEY,
        chatId TEXT NOT NULL,
        senderId TEXT NOT NULL,
        senderName TEXT,
        content TEXT NOT NULL,
        isUser INTEGER NOT NULL DEFAULT 0,
        isSystem INTEGER NOT NULL DEFAULT 0,
        createdAt TEXT NOT NULL,
        metadata TEXT
      )''');

      await LocalStorageRepository.reconcileSchema(db);
      await _expectCols(db, 'chat_messages', ['isBookmark', 'sync_seq']);
      await db.close();
    });

    test('relationship_contexts 缺 chatId 会被补上', () async {
      final db = await databaseFactoryFfi.openDatabase(':memory:');
      await db.execute('''CREATE TABLE relationship_contexts (
        id TEXT PRIMARY KEY,
        characterId TEXT NOT NULL DEFAULT "",
        userId TEXT NOT NULL DEFAULT "",
        content TEXT DEFAULT ""
      )''');

      await LocalStorageRepository.reconcileSchema(db);
      await _expectCols(db, 'relationship_contexts', ['chatId']);
      await db.close();
    });

    test('shop_orders 缺 sync_seq 会被补上', () async {
      final db = await databaseFactoryFfi.openDatabase(':memory:');
      await db.execute('''CREATE TABLE shop_orders (
        id TEXT PRIMARY KEY,
        buyerType TEXT NOT NULL DEFAULT 'user',
        price INTEGER NOT NULL DEFAULT 0,
        status TEXT DEFAULT 'pending'
      )''');

      await LocalStorageRepository.reconcileSchema(db);
      await _expectCols(db, 'shop_orders', ['sync_seq']);
      await db.close();
    });
  });

  group('关键表列齐全性（防止新列漏进 expectedColumns）', () {
    final critical = <String, List<String>>{
      'users': ['chatAlias', 'backgroundImageLandscape', 'sync_seq'],
      'chat_messages': ['isBookmark', 'sync_seq', 'metadata', 'chatId'],
      'chat_sessions': ['backgroundImageLandscape', 'sync_seq'],
      'group_chat_sessions': [
        'chatId',
        'autoModeEnabled',
        'autoModeDelaysByCharacter',
        'isHidden',
      ],
      'group_chat_messages': ['chatId', 'swipeHistory', 'sync_seq'],
      'relationship_contexts': ['chatId'],
      'shop_orders': ['sync_seq'],
    };

    for (final entry in critical.entries) {
      test('${entry.key} 含 ${entry.value.join('/')}', () async {
        final db = await databaseFactoryFfi.openDatabase(':memory:');
        await LocalStorageRepository.reconcileSchema(db);
        await _expectCols(db, entry.key, entry.value);
        await db.close();
      });
    }
  });

  group('幂等', () {
    test('连续两次 reconcileSchema 不报错且列不减', () async {
      final db = await databaseFactoryFfi.openDatabase(':memory:');
      await LocalStorageRepository.reconcileSchema(db);
      final first = (await _cols(db, 'users')).length;
      await LocalStorageRepository.reconcileSchema(db);
      final second = (await _cols(db, 'users')).length;
      expect(second, greaterThanOrEqualTo(first));
      await db.close();
    });
  });
}
