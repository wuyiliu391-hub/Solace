// 【对标来源：KouriChat-1.4.3.2 — src/services/database.py 数据库服务】
// 1:1 转译自 KouriChat SQLAlchemy 数据库模式，适配 Flutter sqflite
// 参考文件：src/services/database.py:ChatMessage、Base.metadata.create_all
// 性能优化 -- 耗电与老手机兼容

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

/// 数据库服务（对标 KouriChat database.py）
/// 提供数据库连接、表创建、会话管理
class DatabaseService {
  static DatabaseService? _instance;
  static DatabaseService get instance => _instance ??= DatabaseService._();
  DatabaseService._();

  Database? _database;

  /// ⚠️ 必须与 LocalStorageRepository 的 solace.db 使用不同文件，
  /// 否则版本号差异会触发 sqflite 默认降级 = 删除用户主数据库。
  static const String _databaseName = 'solace_world.db';
  static const int dbVersion = 39;

  // ═══════════════════════════════════════════════════════
  // 性能优化：查询缓存层
  // ═══════════════════════════════════════════════════════

  /// 查询缓存：key = sql + params 的 hash，value = 缓存结果 + 过期时间
  final Map<String, _CacheEntry> _queryCache = {};
  static const Duration _cacheExpiry = Duration(seconds: 30);
  static const int _maxCacheSize = 100;

  /// 生成缓存 key
  String _cacheKey(String sql, [List<dynamic>? params]) {
    return '$sql|${params?.join(',') ?? ''}';
  }

  /// 清除过期缓存
  void _evictExpiredCache() {
    final now = DateTime.now();
    _queryCache.removeWhere((_, entry) =>
        now.difference(entry.createdAt) > _cacheExpiry);
  }

  /// 清除所有缓存（写操作后调用）
  void invalidateCache() {
    _queryCache.clear();
  }

  /// 带缓存的查询
  Future<List<Map<String, Object?>>> cachedQuery(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<dynamic>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) async {
    final db = await database;
    final key = _cacheKey(
      'query:$table:$distinct:$columns:$where:$groupBy:$having:$orderBy:$limit:$offset',
      whereArgs,
    );

    // 检查缓存
    final cached = _queryCache[key];
    if (cached != null &&
        DateTime.now().difference(cached.createdAt) < _cacheExpiry) {
      return cached.data as List<Map<String, Object?>>;
    }

    // 缓存未命中，查询数据库
    final result = await db.query(
      table,
      distinct: distinct,
      columns: columns,
      where: where,
      whereArgs: whereArgs,
      groupBy: groupBy,
      having: having,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );

    // 写入缓存
    if (_queryCache.length >= _maxCacheSize) {
      _evictExpiredCache();
      if (_queryCache.length >= _maxCacheSize) {
        _queryCache.clear(); // 紧急清理
      }
    }
    _queryCache[key] = _CacheEntry(result);

    return result;
  }

  /// 带缓存的原始查询
  Future<List<Map<String, Object?>>> cachedRawQuery(
    String sql, [
    List<dynamic>? arguments,
  ]) async {
    final db = await database;
    final key = _cacheKey(sql, arguments);

    // 检查缓存
    final cached = _queryCache[key];
    if (cached != null &&
        DateTime.now().difference(cached.createdAt) < _cacheExpiry) {
      return cached.data as List<Map<String, Object?>>;
    }

    // 缓存未命中，查询数据库
    final result = await db.rawQuery(sql, arguments);

    // 写入缓存
    if (_queryCache.length >= _maxCacheSize) {
      _evictExpiredCache();
    }
    _queryCache[key] = _CacheEntry(result);

    return result;
  }

  /// 性能优化：批量写入事务
  Future<void> batchInsert(String table, List<Map<String, Object?>> rows) async {
    final db = await database;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final row in rows) {
        batch.insert(table, row, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    });
    invalidateCache(); // 写操作后清除缓存
  }

  /// 性能优化：批量更新事务
  Future<void> batchUpdate(
    String table,
    List<Map<String, Object?>> updates, {
    required String where,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final update in updates) {
        final id = update['id'];
        batch.update(table, update, where: 'id = ?', whereArgs: [id]);
      }
      await batch.commit(noResult: true);
    });
    invalidateCache();
  }

  /// 性能优化：批量删除事务
  Future<void> batchDelete(
    String table,
    List<String> ids,
  ) async {
    final db = await database;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final id in ids) {
        batch.delete(table, where: 'id = ?', whereArgs: [id]);
      }
      await batch.commit(noResult: true);
    });
    invalidateCache();
  }

  /// 获取数据库实例（对标 KouriChat engine + Session）
  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  /// 初始化数据库（对标 KouriChat create_engine + create_all）
  Future<Database> _initDatabase() async {
    final dbPath = join(await getDatabasesPath(), _databaseName);
    return openDatabase(
      dbPath,
      version: dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onDowngrade: _onDowngrade,
    );
  }

  /// 兜底：禁止 sqflite 默认行为删库重建
  Future<void> _onDowngrade(Database db, int oldVersion, int newVersion) async {
    debugPrint(
      '[DatabaseService] onDowngrade ignored (old=$oldVersion new=$newVersion)',
    );
  }

  /// 创建表（对标 KouriChat Base.metadata.create_all）
  Future<void> _onCreate(Database db, int version) async {
    // 聊天消息表（对标 KouriChat ChatMessage 表）
    await db.execute('''
      CREATE TABLE chat_messages (
        id TEXT PRIMARY KEY,
        chatId TEXT NOT NULL,
        senderId TEXT NOT NULL,
        senderName TEXT DEFAULT '',
        content TEXT DEFAULT '',
        isUser INTEGER DEFAULT 0,
        isSystem INTEGER DEFAULT 0,
        isHidden INTEGER DEFAULT 0,
        isGhost INTEGER DEFAULT 0,
        type TEXT DEFAULT 'text',
        timestamp TEXT NOT NULL,
        generationTime INTEGER,
        tokenCount INTEGER,
        attachmentPath TEXT,
        swipeHistory TEXT DEFAULT '[]',
        swipeIndex INTEGER DEFAULT 0,
        isBookmark INTEGER DEFAULT 0,
        reasoning TEXT
      )
    ''');

    // 角色表（对标 SillyTavern v2CharData）
    await db.execute('''
      CREATE TABLE characters (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT DEFAULT '',
        characterVersion TEXT DEFAULT '',
        personality TEXT DEFAULT '',
        scenario TEXT DEFAULT '',
        firstMes TEXT DEFAULT '',
        mesExample TEXT DEFAULT '',
        creatorNotes TEXT DEFAULT '',
        tags TEXT DEFAULT '[]',
        systemPrompt TEXT DEFAULT '',
        postHistoryInstructions TEXT DEFAULT '',
        creator TEXT DEFAULT '',
        alternateGreetings TEXT DEFAULT '[]',
        characterBook TEXT,
        extensions TEXT DEFAULT '{}',
        avatarPath TEXT,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL
      )
    ''');

    // 会话表
    await db.execute('''
      CREATE TABLE chat_sessions (
        id TEXT PRIMARY KEY,
        characterId TEXT NOT NULL,
        userId TEXT NOT NULL,
        title TEXT DEFAULT '',
        lastMessage TEXT DEFAULT '',
        lastMessageTime TEXT,
        unreadCount INTEGER DEFAULT 0,
        isPinned INTEGER DEFAULT 0,
        backgroundPath TEXT,
        createdAt TEXT NOT NULL,
        sessionType TEXT DEFAULT 'private'
      )
    ''');

    // 世界观表（对标 SillyTavern WorldInfoBook）
    await db.execute('''
      CREATE TABLE world_info_books (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT DEFAULT '',
        scanDepth TEXT,
        tokenBudget TEXT,
        recursiveScanning TEXT,
        createdAt TEXT NOT NULL
      )
    ''');

    // 世界观条目表（对标 SillyTavern WorldInfoEntry）
    await db.execute('''
      CREATE TABLE world_info_entries (
        id TEXT PRIMARY KEY,
        bookId TEXT NOT NULL,
        uid TEXT DEFAULT '',
        comment TEXT DEFAULT '',
        content TEXT DEFAULT '',
        keyList TEXT DEFAULT '[]',
        keysecondaryList TEXT DEFAULT '[]',
        constant INTEGER DEFAULT 0,
        vectorized INTEGER DEFAULT 0,
        selective INTEGER DEFAULT 0,
        disable INTEGER DEFAULT 0,
        position INTEGER DEFAULT 0,
        depth INTEGER DEFAULT 4,
        sortOrder INTEGER DEFAULT 100,
        probability INTEGER DEFAULT 100,
        useGroupScoring INTEGER DEFAULT 0,
        scanDepth INTEGER DEFAULT 0,
        caseSensitive INTEGER DEFAULT 0,
        matchWholeWords INTEGER DEFAULT 0,
        excludeRecursion INTEGER DEFAULT 0,
        preventRecursion INTEGER DEFAULT 0,
        delayUntilRecursion INTEGER DEFAULT 0,
        sticky INTEGER,
        cooldown INTEGER,
        delay INTEGER,
        outletName TEXT,
        role INTEGER DEFAULT 0,
        entryLogicType INTEGER DEFAULT 0,
        triggers TEXT,
        automationId TEXT
      )
    ''');

    // 记忆表
    await db.execute('''
      CREATE TABLE memories (
        id TEXT PRIMARY KEY,
        characterId TEXT NOT NULL,
        userId TEXT NOT NULL,
        input TEXT DEFAULT '',
        output TEXT DEFAULT '',
        emotionTag TEXT,
        valence REAL,
        arousal REAL,
        timestamp TEXT NOT NULL,
        embedding TEXT,
        weight REAL DEFAULT 1.0,
        pinned INTEGER DEFAULT 0,
        lastRecalledAt TEXT
      )
    ''');

    // 社交记忆表
    await db.execute('''
      CREATE TABLE social_memories (
        id TEXT PRIMARY KEY,
        characterId TEXT NOT NULL,
        targetCharacterId TEXT NOT NULL,
        interactionType TEXT DEFAULT 'chat',
        content TEXT DEFAULT '',
        emotionTag TEXT DEFAULT '',
        importance TEXT DEFAULT 'normal',
        keywords TEXT DEFAULT '[]',
        timestamp TEXT NOT NULL,
        weight REAL DEFAULT 1.0,
        pinned INTEGER DEFAULT 0,
        lastRecalledAt TEXT
      )
    ''');

    // 用户表
    await db.execute('''
      CREATE TABLE users (
        id TEXT PRIMARY KEY,
        nickname TEXT DEFAULT '',
        avatarUrl TEXT,
        gender TEXT,
        birthday TEXT,
        location TEXT,
        bio TEXT,
        coins INTEGER DEFAULT 0,
        totalEarned INTEGER DEFAULT 0
      )
    ''');

    // Prompt 条目表（对标 SillyTavern PromptManager）
    await db.execute('''
      CREATE TABLE prompt_entries (
        id TEXT PRIMARY KEY,
        characterId TEXT,
        name TEXT NOT NULL,
        role TEXT DEFAULT 'system',
        injectionTrigger TEXT DEFAULT '["normal"]',
        injectionPosition TEXT DEFAULT 'up_context',
        injectionDepth INTEGER DEFAULT 4,
        injectionOrder INTEGER DEFAULT 100,
        prompt TEXT DEFAULT '',
        forbidOverrides INTEGER DEFAULT 0,
        enabled INTEGER DEFAULT 1,
        isSystem INTEGER DEFAULT 0
      )
    ''');

    // 创建索引
    await db
        .execute('CREATE INDEX idx_messages_chatId ON chat_messages(chatId)');
    await db.execute(
        'CREATE INDEX idx_sessions_characterId ON chat_sessions(characterId)');
    await db.execute(
        'CREATE INDEX idx_memories_characterId ON memories(characterId)');
    await db.execute(
        'CREATE INDEX idx_entries_bookId ON world_info_entries(bookId)');
  }

  /// 数据库升级迁移（对标 Solace _onUpgrade 模式）
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // 按版本递增迁移，保留旧数据
    if (oldVersion < 28) {
      // v28: 重构版本，表已在 onCreate 中重建
      // 如果是升级，尝试补全缺失列
      await _reconcileSchema(db);
    }
    if (oldVersion < 30) {
      await _reconcileSchema(db);
    }
    if (oldVersion < 38) {
      // Add sessionType column to chat_sessions for social sessions
      try {
        await db.execute("ALTER TABLE chat_sessions ADD COLUMN sessionType TEXT DEFAULT 'private'");
      } catch (_) {}

      await db.execute('''
        CREATE TABLE IF NOT EXISTS social_memories (
          id TEXT PRIMARY KEY,
          characterId TEXT NOT NULL,
          targetCharacterId TEXT NOT NULL,
          interactionType TEXT DEFAULT 'chat',
          content TEXT DEFAULT '',
          emotionTag TEXT DEFAULT '',
          importance TEXT DEFAULT 'normal',
          keywords TEXT DEFAULT '[]',
          timestamp TEXT NOT NULL,
          weight REAL DEFAULT 1.0,
          pinned INTEGER DEFAULT 0,
          lastRecalledAt TEXT
        )
      ''');
    }
  }

  /// 自动补全缺失列（对标 Solace reconcileSchema）
  Future<void> _reconcileSchema(Database db) async {
    final tables =
        await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table'");
    final tableNames = tables.map((t) => t['name'] as String).toSet();

    for (final entry in _expectedColumns.entries) {
      if (!tableNames.contains(entry.key)) {
        // 表不存在，跳过（将在 createMissingTable 中创建）
        continue;
      }
      final tableInfo = await db.rawQuery('PRAGMA table_info(${entry.key})');
      final existingColumns = tableInfo.map((c) => c['name'] as String).toSet();

      for (final col in entry.value.entries) {
        if (!existingColumns.contains(col.key)) {
          try {
            await db.execute(
                'ALTER TABLE ${entry.key} ADD COLUMN ${col.key} ${col.value}');
          } catch (_) {}
        }
      }
    }
  }

  /// 预期列定义（对标 Solace expectedColumns）
  static const _expectedColumns = <String, Map<String, String>>{
    'chat_messages': {
      'id': 'TEXT PRIMARY KEY',
      'chatId': 'TEXT NOT NULL',
      'senderId': 'TEXT NOT NULL',
      'senderName': 'TEXT DEFAULT ""',
      'content': 'TEXT DEFAULT ""',
      'isUser': 'INTEGER DEFAULT 0',
      'isSystem': 'INTEGER DEFAULT 0',
      'isHidden': 'INTEGER DEFAULT 0',
      'isGhost': 'INTEGER DEFAULT 0',
      'type': 'TEXT DEFAULT "text"',
      'timestamp': 'TEXT NOT NULL',
      'generationTime': 'INTEGER',
      'tokenCount': 'INTEGER',
      'attachmentPath': 'TEXT',
      'swipeHistory': 'TEXT DEFAULT "[]"',
      'swipeIndex': 'INTEGER DEFAULT 0',
      'isBookmark': 'INTEGER DEFAULT 0',
      'reasoning': 'TEXT',
    },
    'characters': {
      'id': 'TEXT PRIMARY KEY',
      'name': 'TEXT NOT NULL',
      'description': 'TEXT DEFAULT ""',
      'characterVersion': 'TEXT DEFAULT ""',
      'personality': 'TEXT DEFAULT ""',
      'scenario': 'TEXT DEFAULT ""',
      'firstMes': 'TEXT DEFAULT ""',
      'mesExample': 'TEXT DEFAULT ""',
      'creatorNotes': 'TEXT DEFAULT ""',
      'tags': 'TEXT DEFAULT "[]"',
      'systemPrompt': 'TEXT DEFAULT ""',
      'postHistoryInstructions': 'TEXT DEFAULT ""',
      'creator': 'TEXT DEFAULT ""',
      'alternateGreetings': 'TEXT DEFAULT "[]"',
      'characterBook': 'TEXT',
      'extensions': 'TEXT DEFAULT "{}"',
      'avatarPath': 'TEXT',
      'createdAt': 'TEXT NOT NULL',
      'updatedAt': 'TEXT NOT NULL',
    },
    'memories': {
      'id': 'TEXT PRIMARY KEY',
      'characterId': 'TEXT NOT NULL',
      'userId': 'TEXT NOT NULL',
      'input': 'TEXT DEFAULT ""',
      'output': 'TEXT DEFAULT ""',
      'emotionTag': 'TEXT',
      'valence': 'REAL',
      'arousal': 'REAL',
      'timestamp': 'TEXT NOT NULL',
      'embedding': 'TEXT',
      'weight': 'REAL DEFAULT 1.0',
      'pinned': 'INTEGER DEFAULT 0',
      'lastRecalledAt': 'TEXT',
    },
    'chat_sessions': {
      'id': 'TEXT PRIMARY KEY',
      'characterId': 'TEXT NOT NULL',
      'userId': 'TEXT NOT NULL',
      'title': 'TEXT DEFAULT ""',
      'lastMessage': 'TEXT DEFAULT ""',
      'lastMessageTime': 'TEXT',
      'unreadCount': 'INTEGER DEFAULT 0',
      'isPinned': 'INTEGER DEFAULT 0',
      'backgroundPath': 'TEXT',
      'createdAt': 'TEXT NOT NULL',
      'sessionType': 'TEXT DEFAULT "private"',
    },
    'social_memories': {
      'id': 'TEXT PRIMARY KEY',
      'characterId': 'TEXT NOT NULL',
      'targetCharacterId': 'TEXT NOT NULL',
      'interactionType': 'TEXT DEFAULT "chat"',
      'content': 'TEXT DEFAULT ""',
      'emotionTag': 'TEXT DEFAULT ""',
      'importance': 'TEXT DEFAULT "normal"',
      'keywords': 'TEXT DEFAULT "[]"',
      'timestamp': 'TEXT NOT NULL',
      'weight': 'REAL DEFAULT 1.0',
      'pinned': 'INTEGER DEFAULT 0',
      'lastRecalledAt': 'TEXT',
    },
  };
}

/// 性能优化：缓存条目
class _CacheEntry {
  final dynamic data;
  final DateTime createdAt;

  _CacheEntry(this.data) : createdAt = DateTime.now();
}
