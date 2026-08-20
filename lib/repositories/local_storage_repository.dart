// 性能优化 -- 耗电与老手机兼容
import 'dart:async';
import 'dart:convert';
import 'dart:io' show Directory, File, gzip;
import 'dart:typed_data';
import 'dart:ui' show Color;
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/foundation.dart'
    show ValueNotifier, compute, kIsWeb, debugPrint, visibleForTesting;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../services/log_service.dart';
import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';
import '../models/ai_character.dart';
import '../models/ai_config.dart';
import '../models/ai_letter.dart';
import '../models/chat_session.dart';
import '../models/chat_message.dart';
import '../models/character_commitment.dart';
import '../models/relationship_context.dart';
import '../models/intimacy_event.dart';
import '../models/memory.dart';
import '../models/moment.dart';
import '../models/moment_notification.dart';
import '../models/moment_bookmark.dart';
import '../models/trending_tag.dart';
import '../models/sticker_pack.dart';
import '../models/ai_wallet.dart';
import '../models/shop_item.dart';
import '../models/shop_order.dart';
import '../models/pure_ai_session.dart';
import '../data/builtin_characters.dart';
import '../models/virtual_phone/virtual_phone.dart';
import '../models/virtual_phone/vp_contact.dart';
import '../models/virtual_phone/vp_chat.dart';
import '../models/virtual_phone/vp_note.dart';
import '../models/virtual_phone/vp_moment.dart';
import '../models/pure_ai_message.dart';
import '../models/bt_agent_action.dart';
import '../models/money_transaction.dart';
import '../models/novel.dart';
import '../models/group_chat_session.dart';
import '../models/group_chat_message.dart';
import '../models/group_chat_summary.dart';
import '../models/group_public_event_memory.dart';
import '../models/group_chat_branch.dart';
import '../models/group_chat_lorebook_entry.dart';
import '../services/bt_operation_lock_service.dart';
import '../services/group_chat_rolling_summary.dart';
import '../config/business_rules.dart';
import '../config/constants.dart';
import '../utils/global_mode_prompt.dart';

part 'storage_parts/chat_messages.dart';
part 'storage_parts/export_moments_shop.dart';
part 'storage_parts/bt_virtual_phone.dart';
part 'storage_parts/money_transactions.dart';

/// isolate：gzip 解码
String _decodeGzipBytes(List<int> bytes) {
  final decoded = gzip.decode(bytes);
  return utf8.decode(decoded);
}

/// isolate：JSON 字符串解析
Map<String, dynamic> _parseJsonString(String jsonStr) {
  return jsonDecode(jsonStr) as Map<String, dynamic>;
}

Map<String, dynamic> _normalizeBackupData(Map<String, dynamic> raw) {
  final nested = raw['data'];
  if (nested is Map) {
    return {
      ...nested.map((key, value) => MapEntry(key.toString(), value)),
      for (final key in [
        'magic',
        'version',
        'dbVersion',
        'exportTime',
        'exportedAt',
        'timestamp',
        'preferences',
        'files',
      ])
        if (raw.containsKey(key)) key: raw[key],
    };
  }
  return raw;
}

int? _parseBackupVersion(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) {
    return int.tryParse(value) ?? int.tryParse(value.split('.').first);
  }
  return null;
}

Map<String, dynamic>? _asStringDynamicMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return null;
}

/// 在后台 isolate 中执行：收集本地文件 → JSON 编码 → gzip 压缩
List<int> _compressExportData(Map<String, dynamic> payload) {
  final data = payload['data'] as Map<String, dynamic>;
  final docsPath = payload['docsPath'] as String?;

  // 收集本地文件（同步 I/O，在 isolate 中安全）
  if (docsPath != null) {
    try {
      final dir = Directory(docsPath);
      final fileMap = <String, String>{};

      bool isLocalFileUrl(String url) =>
          url.startsWith('solace://') ||
          url.startsWith('voice/') ||
          url.startsWith('images/') ||
          url.startsWith('/') ||
          url.contains('/data/');

      void collectFromValue(dynamic value) {
        if (value is String && isLocalFileUrl(value)) {
          // 绝对路径直接用，相对路径拼接 docsPath
          final filePath = value.startsWith('/') ? value : '${dir.path}/$value';
          final file = File(filePath);
          if (file.existsSync()) {
            final bytes = file.readAsBytesSync();
            fileMap[value] = base64Encode(bytes);
          }
        }
      }

      void collectFromMap(Map<String, dynamic> map) {
        for (final v in map.values) {
          if (v is String) {
            collectFromValue(v);
          } else if (v is Map<String, dynamic>) {
            collectFromMap(v);
          } else if (v is List) {
            for (final item in v) {
              if (item is String) collectFromValue(item);
              if (item is Map<String, dynamic>) collectFromMap(item);
            }
          }
        }
      }

      for (final tableData in data.values) {
        if (tableData is List) {
          for (final row in tableData) {
            if (row is Map<String, dynamic>) collectFromMap(row);
          }
        } else if (tableData is Map<String, dynamic>) {
          collectFromMap(tableData);
        }
      }

      if (fileMap.isNotEmpty) {
        data['files'] = fileMap;
      }
    } catch (_) {}
  }

  data['magic'] = 'SOLACE_BACKUP_V1';
  final json = jsonEncode(data);
  final bytes = utf8.encode(json);
  return gzip.encode(bytes);
}

/// LocalStorageRepository 的字段基座：巨型仓库拆分为多个 mixin part 后，
/// 各 mixin 通过 `on _LocalStorageRepositoryCore` 共享这些实例字段。
abstract class _LocalStorageRepositoryCore {
  _LocalStorageRepositoryCore({bool? isWeb}) : _isWeb = isWeb ?? kIsWeb;

  Database? _database;
  SharedPreferences? _prefs;
  final ValueNotifier<bool> pureAiModeNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<int> modeSettingsNotifier = ValueNotifier<int>(0);
  final ValueNotifier<String?> themeChangeNotifier =
      ValueNotifier<String?>(null); // 'light'/'dark'/'system'/null
  bool _isWeb = false;
  Timer? _syncTimer;

  // ---- 跨 mixin 调用的方法抽象声明（实现在主类或后续 mixin，全链可见）----

  Future<Database> _ensureDb();

  Future<void> _insertShopItemSafe(Database db, ShopItem item);

  Future<void> saveUser(User user);

  Future<User?> getUser(String id);

  Future<void> saveAILetter(AILetter letter);

  Future<List<AILetter>> getAILetters({
    required String userId,
    int limit = 50,
    int offset = 0,
  });

  Future<AILetter?> getAILetter(String id);
}

class LocalStorageRepository extends _LocalStorageRepositoryCore with LocalStorageRepositoryChatMessagesApi, LocalStorageRepositoryMomentsShopApi, LocalStorageRepositoryBtVPhoneApi, LocalStorageRepositoryMoneyApi {
  LocalStorageRepository({bool? isWeb}) : super(isWeb: isWeb);

  /// 公开数据库引用（供 LifeEndEngine 等外部引擎使用）
  Database? get database => _database;
  /// 公开 SharedPreferences 引用（供 ChatBloc 等外部组件使用）
  SharedPreferences? get sharedPreferences => _prefs;
  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
    pureAiModeNotifier.value =
        _prefs?.getBool(PrefKeys.pureAiModeEnabled) ?? false;
    _isWeb = _isWeb || kIsWeb;
    if (!_isWeb) {
      _database = await _initDatabase();
      await _validateDatabaseIntegrity(_database!);
      // 不自动清理历史乱码：旧记录保留给用户查看，AI prompt 链路单独隔离污染内容。
      // 启动时将上次未同步的消息缓冲写入 SQLite
      await syncBufferToSQLite();
      // 性能优化：30秒改为60秒，减少DB写入频率，省电
      _syncTimer = Timer.periodic(
          const Duration(seconds: 60), (_) => syncBufferToSQLite());
    }
  }
  void dispose() {
    _syncTimer?.cancel();
    pureAiModeNotifier.dispose();
    modeSettingsNotifier.dispose();
  }
  /// 清理数据库中的乱码消息（GBK mojibake）
  /// 返回被清理的消息数量
  Future<int> cleanupMojibakeMessages() async {
    if (_isWeb || _database == null) return 0;
    try {
      int cleaned = 0;
      cleaned += await _cleanupTextColumn(
        table: 'chat_messages',
        idColumn: 'id',
        textColumn: 'content',
        replacement: '网络刚才有点不稳，我重新想一下怎么回复你。',
      );
      cleaned += await _cleanupTextColumn(
        table: 'memories',
        idColumn: 'id',
        textColumn: 'content',
        replacement: '',
        deleteRow: true,
      );
      cleaned += await _cleanupTextColumn(
        table: 'pure_ai_messages',
        idColumn: 'id',
        textColumn: 'content',
        replacement: '网络刚才有点不稳，我重新想一下怎么回复你。',
      );
      cleaned += await _cleanupTextColumn(
        table: 'chat_sessions',
        idColumn: 'id',
        textColumn: 'lastMessage',
        replacement: '',
      );
      cleaned += await _cleanupTextColumn(
        table: 'pure_ai_sessions',
        idColumn: 'id',
        textColumn: 'lastMessage',
        replacement: '',
      );
      debugPrint('cleanupMojibakeMessages: cleaned $cleaned records');
      return cleaned;
    } catch (e) {
      debugPrint('cleanupMojibakeMessages failed: $e');
      return 0;
    }
  }
  Future<int> _cleanupTextColumn({
    required String table,
    required String idColumn,
    required String textColumn,
    required String replacement,
    bool deleteRow = false,
  }) async {
    try {
      final maps =
          await _database!.query(table, columns: [idColumn, textColumn]);
      var cleaned = 0;
      for (final map in maps) {
        final content = map[textColumn] as String? ?? '';
        if (content.isNotEmpty && _isMojibakeContent(content)) {
          if (deleteRow) {
            await _database!.delete(table,
                where: '$idColumn = ?', whereArgs: [map[idColumn]]);
          } else {
            await _database!.update(
              table,
              {textColumn: replacement},
              where: '$idColumn = ?',
              whereArgs: [map[idColumn]],
            );
          }
          cleaned++;
        }
      }
      return cleaned;
    } catch (_) {
      return 0;
    }
  }
  Future<void> _validateDatabaseIntegrity(Database db) async {
    for (final table in expectedColumns.keys) {
      try {
        await db.rawQuery('SELECT COUNT(*) as cnt FROM $table');
      } catch (e) {
        debugPrint(': $table ($e)..');
        try {
          await reconcileSchema(db, prefs: _prefs);
        } catch (e) {
          debugPrint('Error: $e');
        }
        break;
      }
    }
  }
  Future<Database> _ensureDb() async {
    if (_isWeb) {
      throw UnsupportedError('数据库不支持 Web 平台');
    }
    var db = _database;
    if (db == null || !db.isOpen) {
      db = await _initDatabase();
      _database = db;
      return db;
    }
    try {
      await db.rawQuery('SELECT 1');
    } catch (e) {
      debugPrint('数据库连接异常，重新打开: $e');
      _database = null;
      db = await _initDatabase();
      _database = db;
    }
    return db;
  }
  /// 唯一安全写入入口：先 ensure，再按真实列 toDbMap，绝不写不存在的列
  Future<void> _insertShopItemSafe(Database db, ShopItem item) async {
    await _ensureShopItemsSchema(db);
    var cols = await getTableColumns(db, 'shop_items');
    if (!cols.contains('isCustom') || !cols.contains('createdAt')) {
      await _ensureShopItemsSchema(db, force: true);
      cols = await getTableColumns(db, 'shop_items');
    }
    final map = item.toDbMap(cols);
    // 双保险：map 里绝不能出现表中没有的 key
    final safe = <String, dynamic>{};
    for (final e in map.entries) {
      if (cols.contains(e.key)) safe[e.key] = e.value;
    }
    if (!safe.containsKey('id')) {
      throw StateError('shop_items insert missing id, cols=$cols');
    }
    await db.insert(
      'shop_items',
      safe,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _databaseName);
    final db = await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onDowngrade: _onDowngrade,
    );
    await reconcileSchema(db, prefs: _prefs);
    return db;
  }
  /// 兜底：禁止 sqflite 默认行为删库重建
  Future<void> _onDowngrade(Database db, int oldVersion, int newVersion) async {
    debugPrint(
      '[LocalStorageRepository] onDowngrade ignored (old=$oldVersion new=$newVersion)',
    );
  }
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    debugPrint(' $oldVersion -> $newVersion');
    if (oldVersion < 2) {
      await db.execute(
          ''' CREATE INDEX IF NOT EXISTS idx_sessions_characterId ON chat_sessions(aiCharacterId) ''');
    }
    if (oldVersion < 3) {
      await db.execute(
          ''' CREATE TABLE IF NOT EXISTS moments ( id TEXT PRIMARY KEY, userId TEXT NOT NULL, userName TEXT NOT NULL, userAvatar TEXT, content TEXT NOT NULL, images TEXT DEFAULT '', type INTEGER NOT NULL DEFAULT 0, likes TEXT DEFAULT '[]', comments TEXT DEFAULT '[]', createdAt TEXT NOT NULL, updatedAt TEXT, isFromAI INTEGER NOT NULL DEFAULT 0, visibility INTEGER NOT NULL DEFAULT 0, sync_seq INTEGER NOT NULL DEFAULT 0 ) ''');
      await db.execute(
          ''' CREATE INDEX IF NOT EXISTS idx_moments_userId ON moments(userId) ''');
      await db.execute(
          ''' CREATE INDEX IF NOT EXISTS idx_moments_createdAt ON moments(createdAt DESC) ''');
    }
    if (oldVersion < 4) {
      await _addColumnIfNotExists(db, 'ai_characters', 'languageStyle', 'TEXT');
      await _addColumnIfNotExists(db, 'ai_characters', 'tabooTopics', 'TEXT');
      await _addColumnIfNotExists(db, 'ai_characters', 'userNickname', 'TEXT');
      await _addColumnIfNotExists(
          db, 'ai_characters', 'dialogueExamples', 'TEXT');
      await _addColumnIfNotExists(
          db, 'ai_characters', 'interactionConfig', 'TEXT');
    }
    if (oldVersion < 5) {
      await _addColumnIfNotExists(
          db, 'chat_sessions', 'isPinned', 'INTEGER NOT NULL DEFAULT 0');
      await _addColumnIfNotExists(
          db, 'chat_sessions', 'backgroundImage', 'TEXT');
    }
    if (oldVersion < 6) {
      await _addColumnIfNotExists(db, 'users', 'gender', 'TEXT');
      await _addColumnIfNotExists(db, 'users', 'birthday', 'TEXT');
      await _addColumnIfNotExists(db, 'users', 'location', 'TEXT');
      await _addColumnIfNotExists(db, 'users', 'bio', 'TEXT');
      await _addColumnIfNotExists(
          db, 'users', 'coins', 'INTEGER NOT NULL DEFAULT 100');
      await _addColumnIfNotExists(
          db, 'users', 'totalCoinsEarned', 'INTEGER NOT NULL DEFAULT 100');
      await _addColumnIfNotExists(
          db, 'users', 'totalCoinsSpent', 'INTEGER NOT NULL DEFAULT 0');
    }
    if (oldVersion < 7) {
      await _addColumnIfNotExists(
          db, 'ai_characters', 'isHidden', 'INTEGER NOT NULL DEFAULT 0');
      await _addColumnIfNotExists(
          db, 'chat_sessions', 'isHidden', 'INTEGER NOT NULL DEFAULT 0');
    }
    if (oldVersion < 8) {}
    if (oldVersion < 9) {
      await _addColumnIfNotExists(db, 'users', 'status', 'TEXT');
    }
    if (oldVersion < 10) {
      await _addColumnIfNotExists(db, 'chat_sessions', 'dailyIntimacyCount',
          'INTEGER NOT NULL DEFAULT 0');
      await _addColumnIfNotExists(
          db, 'chat_sessions', 'lastIntimacyDate', 'TEXT');
    }
    if (oldVersion < 11) {
      await _addColumnIfNotExists(
          db, 'ai_characters', 'isOnline', 'INTEGER NOT NULL DEFAULT 1');
      await _addColumnIfNotExists(db, 'ai_characters', 'currentStatus', 'TEXT');
      await _addColumnIfNotExists(db, 'ai_characters', 'lastOnlineAt', 'TEXT');
      await _addColumnIfNotExists(
          db, 'chat_sessions', 'aiIsOnline', 'INTEGER NOT NULL DEFAULT 1');
      await _addColumnIfNotExists(
          db, 'chat_sessions', 'aiCurrentStatus', 'TEXT');
    }
    if (oldVersion < 12) {
      await db.execute(
          ''' CREATE TABLE IF NOT EXISTS sticker_packs ( id TEXT PRIMARY KEY, name TEXT NOT NULL, coverImagePath TEXT, stickers TEXT, createdAt TEXT NOT NULL, updatedAt TEXT, isDefault INTEGER NOT NULL DEFAULT 0 ) ''');
    }
    if (oldVersion < 13) {
      await _addColumnIfNotExists(
          db, 'moments', 'visibility', 'INTEGER NOT NULL DEFAULT 0');
    }
    if (oldVersion < 14) {
      await _addColumnIfNotExists(db, 'ai_characters', 'gender', 'TEXT');
    }
    if (oldVersion < 15) {
      await _addColumnIfNotExists(db, 'ai_characters', 'catchphrases', 'TEXT');
      await _addColumnIfNotExists(db, 'ai_characters', 'openingLine', 'TEXT');
    }
    if (oldVersion < 16) {
      await db.execute("UPDATE chat_messages SET type = 2 WHERE type = 3");
      await db.execute("UPDATE chat_messages SET type = 3 WHERE type = 4");
    }
    if (oldVersion < 17) {}
    if (oldVersion < 18) {
      await _addColumnIfNotExists(
          db, 'chat_sessions', 'isBlocked', 'INTEGER NOT NULL DEFAULT 0');
      await _addColumnIfNotExists(
          db, 'chat_sessions', 'blockedBy', 'INTEGER NOT NULL DEFAULT 0');
      await _addColumnIfNotExists(db, 'chat_sessions', 'blockedAt', 'TEXT');
      await _addColumnIfNotExists(db, 'chat_sessions', 'blockReason', 'TEXT');
    }
    if (oldVersion < 19) {
      // 预留
    }
    if (oldVersion < 20) {
      await _addColumnIfNotExists(
          db, 'ai_configs', 'isThinkingModel', 'INTEGER NOT NULL DEFAULT 1');
    }
    if (oldVersion < 21) {
      await db.execute(
          ''' CREATE TABLE IF NOT EXISTS ai_wallets ( characterId TEXT PRIMARY KEY, balance INTEGER NOT NULL DEFAULT 50, totalEarned INTEGER NOT NULL DEFAULT 50, totalSpent INTEGER NOT NULL DEFAULT 0, dailySpent INTEGER NOT NULL DEFAULT 0, dailySpentDate TEXT, spendingPersonality INTEGER NOT NULL DEFAULT 5, sync_seq INTEGER NOT NULL DEFAULT 0 ) ''');
    }
    if (oldVersion < 22) {
      await db.execute(
          ''' CREATE TABLE IF NOT EXISTS shop_orders ( id TEXT PRIMARY KEY, buyerType TEXT NOT NULL DEFAULT 'user', buyerId TEXT NOT NULL DEFAULT '', receiverType TEXT NOT NULL DEFAULT 'ai', receiverId TEXT NOT NULL DEFAULT '', chatSessionId TEXT NOT NULL DEFAULT '', itemId TEXT NOT NULL DEFAULT '', itemName TEXT NOT NULL DEFAULT '', itemEmoji TEXT NOT NULL DEFAULT '', price INTEGER NOT NULL DEFAULT 0, status TEXT DEFAULT 'pending', message TEXT, createdAt TEXT NOT NULL DEFAULT '', preparingAt TEXT, shippingAt TEXT, deliveredAt TEXT, aiReaction TEXT, sync_seq INTEGER NOT NULL DEFAULT 0 ) ''');
    }
    if (oldVersion < 23) {
      await db.execute(
          ''' CREATE TABLE IF NOT EXISTS pure_ai_messages ( id TEXT PRIMARY KEY, sessionId TEXT NOT NULL, senderId TEXT NOT NULL, senderName TEXT, content TEXT NOT NULL, type INTEGER NOT NULL DEFAULT 0, status INTEGER NOT NULL DEFAULT 1, createdAt TEXT NOT NULL, metadata TEXT ) ''');
    }
    if (oldVersion < 24) {
      await db.execute(
          ''' CREATE TABLE IF NOT EXISTS moments ( id TEXT PRIMARY KEY, userId TEXT NOT NULL, userName TEXT NOT NULL, userAvatar TEXT, content TEXT NOT NULL, images TEXT DEFAULT '', type INTEGER NOT NULL DEFAULT 0, likes TEXT DEFAULT '[]', comments TEXT DEFAULT '[]', createdAt TEXT NOT NULL, updatedAt TEXT, isFromAI INTEGER NOT NULL DEFAULT 0, visibility INTEGER NOT NULL DEFAULT 0, sync_seq INTEGER NOT NULL DEFAULT 0 ) ''');
      await db.execute(
          ''' CREATE INDEX IF NOT EXISTS idx_moments_userId ON moments(userId) ''');
      await db.execute(
          ''' CREATE INDEX IF NOT EXISTS idx_moments_createdAt ON moments(createdAt DESC) ''');
    }
    if (oldVersion < 25) {
      // 艾宾浩斯热度系统：给 memories 表增加 weight/pinned/lastRecalledAt
      await _addColumnIfNotExists(
          db, 'memories', 'weight', 'REAL NOT NULL DEFAULT 1.0');
      await _addColumnIfNotExists(
          db, 'memories', 'pinned', 'INTEGER NOT NULL DEFAULT 0');
      await _addColumnIfNotExists(db, 'memories', 'lastRecalledAt', 'TEXT');
    }
    if (oldVersion < 26) {
      // v10.0 大版本：6大模块数据库迁移
      // Module 2: 内心活动
      await db.execute(''' CREATE TABLE IF NOT EXISTS inner_thoughts (
        id TEXT PRIMARY KEY, characterId TEXT NOT NULL DEFAULT '', userId TEXT NOT NULL DEFAULT '',
        content TEXT NOT NULL DEFAULT '', type INTEGER NOT NULL DEFAULT 0,
        emotionValence REAL NOT NULL DEFAULT 0, emotionArousal REAL NOT NULL DEFAULT 0,
        isRead INTEGER NOT NULL DEFAULT 0, createdAt TEXT NOT NULL DEFAULT ''
      ) ''');
      // Module 3: 虚拟日记
      await db.execute(''' CREATE TABLE IF NOT EXISTS forum_posts (
        id TEXT PRIMARY KEY, authorId TEXT NOT NULL DEFAULT '', authorName TEXT NOT NULL DEFAULT '',
        authorAvatar TEXT, isFromAI INTEGER NOT NULL DEFAULT 0, characterId TEXT,
        title TEXT NOT NULL DEFAULT '', content TEXT NOT NULL DEFAULT '', images TEXT, tags TEXT,
        likes TEXT DEFAULT '[]', isAnonymous INTEGER NOT NULL DEFAULT 0,
        visibility INTEGER NOT NULL DEFAULT 0, createdAt TEXT NOT NULL DEFAULT '', updatedAt TEXT
      ) ''');
      await db.execute(''' CREATE TABLE IF NOT EXISTS forum_comments (
        id TEXT PRIMARY KEY, postId TEXT NOT NULL DEFAULT '', authorId TEXT NOT NULL DEFAULT '',
        authorName TEXT NOT NULL DEFAULT '', authorAvatar TEXT, isFromAI INTEGER NOT NULL DEFAULT 0,
        characterId TEXT, content TEXT NOT NULL DEFAULT '', replyToId TEXT, replyToName TEXT,
        isAnonymous INTEGER NOT NULL DEFAULT 0, createdAt TEXT NOT NULL DEFAULT ''
      ) ''');
      // Module 4: 共同回忆相册
      await db.execute(''' CREATE TABLE IF NOT EXISTS shared_album_entries (
        id TEXT PRIMARY KEY, characterId TEXT NOT NULL DEFAULT '', userId TEXT NOT NULL DEFAULT '',
        memoryId TEXT, title TEXT NOT NULL DEFAULT '', description TEXT, eventDate TEXT,
        imagePath TEXT, importance INTEGER NOT NULL DEFAULT 1, createdAt TEXT NOT NULL DEFAULT ''
      ) ''');
      // Module 5: 虚拟地图
      await db.execute(''' CREATE TABLE IF NOT EXISTS virtual_locations (
        id TEXT PRIMARY KEY, characterId TEXT NOT NULL DEFAULT '', userId TEXT NOT NULL DEFAULT '',
        userLat REAL NOT NULL DEFAULT 0, userLng REAL NOT NULL DEFAULT 0,
        aiLat REAL NOT NULL DEFAULT 0, aiLng REAL NOT NULL DEFAULT 0,
        sceneDescription TEXT, distance REAL NOT NULL DEFAULT 0, createdAt TEXT NOT NULL DEFAULT ''
      ) ''');
      // 扩展现有表
      await _addColumnIfNotExists(db, 'users', 'appIconPath', 'TEXT');
      await _addColumnIfNotExists(db, 'users', 'lockScreenPassword', 'TEXT');
      await _addColumnIfNotExists(
          db, 'users', 'lockScreenDuration', 'INTEGER NOT NULL DEFAULT 0');
      await _addColumnIfNotExists(db, 'users', 'lockScreenTextColor', 'TEXT');
      await _addColumnIfNotExists(
          db, 'users', 'lockScreenFontSize', 'REAL NOT NULL DEFAULT 1.0');
      await _addColumnIfNotExists(db, 'users', 'currentWeather', 'TEXT');
      await _addColumnIfNotExists(db, 'users', 'lastWeatherUpdate', 'TEXT');
      await _addColumnIfNotExists(db, 'ai_characters', 'avatarGif', 'TEXT');
      await _addColumnIfNotExists(db, 'ai_characters', 'autoReplyStickers',
          'INTEGER NOT NULL DEFAULT 0');
      await _addColumnIfNotExists(
          db, 'ai_characters', 'translatedSettings', 'TEXT');
      await _addColumnIfNotExists(db, 'chat_messages', 'pokeSuffix', 'TEXT');
      await _addColumnIfNotExists(db, 'chat_messages', 'stickerId', 'TEXT');
      await _addColumnIfNotExists(db, 'chat_messages', 'stickerPath', 'TEXT');
      await _addColumnIfNotExists(db, 'moments', 'replyToCommentId', 'TEXT');
      await _addColumnIfNotExists(db, 'moments', 'replyToContent', 'TEXT');
      await _addColumnIfNotExists(
          db, 'moments', 'aiLiked', 'INTEGER NOT NULL DEFAULT 0');
    }
    if (oldVersion < 27) {
      await _addColumnIfNotExists(
          db, 'ai_characters', 'immutableAnchor', 'TEXT');
      await _addColumnIfNotExists(
          db, 'ai_characters', 'deviationRadius', 'REAL NOT NULL DEFAULT 0.4');
      await _addColumnIfNotExists(db, 'ai_characters', 'evolutionEnabled',
          'INTEGER NOT NULL DEFAULT 1');
      await _addColumnIfNotExists(db, 'ai_characters',
          'qualitativeEvolutionEnabled', 'INTEGER NOT NULL DEFAULT 0');
      await _addColumnIfNotExists(db, 'ai_characters', 'currentAnchor', 'TEXT');
      await db.execute(
          ''' CREATE TABLE IF NOT EXISTS growth_events ( id TEXT PRIMARY KEY, characterId TEXT NOT NULL DEFAULT '', userId TEXT NOT NULL DEFAULT '', triggerType TEXT NOT NULL DEFAULT 'micro', evolutionMode TEXT NOT NULL DEFAULT 'micro', triggerData TEXT NOT NULL DEFAULT '{}', deltas TEXT NOT NULL DEFAULT '{}', impactScore REAL NOT NULL DEFAULT 0, reason TEXT, createdAt TEXT NOT NULL DEFAULT '' ) ''');
      await db.execute(
          ''' CREATE TABLE IF NOT EXISTS persona_snapshots ( id TEXT PRIMARY KEY, characterId TEXT NOT NULL DEFAULT '', snapshotType TEXT NOT NULL DEFAULT 'initial', traitsData TEXT NOT NULL DEFAULT '{}', surfaceData TEXT NOT NULL DEFAULT '{}', createdAt TEXT NOT NULL DEFAULT '', label TEXT ) ''');
    }
    if (oldVersion < 28) {
      await _addColumnIfNotExists(
          db, 'chat_messages', 'isUser', 'INTEGER NOT NULL DEFAULT 0');
      await _addColumnIfNotExists(
          db, 'chat_messages', 'isSystem', 'INTEGER NOT NULL DEFAULT 0');
      await _addColumnIfNotExists(
          db, 'chat_messages', 'isHidden', 'INTEGER NOT NULL DEFAULT 0');
      await _addColumnIfNotExists(
          db, 'chat_messages', 'isGhost', 'INTEGER NOT NULL DEFAULT 0');
      // 修复已有数据：根据 senderId 修正 isUser 字段
      await db.execute(
          "UPDATE chat_messages SET isUser = 1 WHERE senderId NOT LIKE 'ai_%' AND senderId != 'system' AND senderId != 'system_risk'");
    }
    if (oldVersion < 29) {
      await _addColumnIfNotExists(db, 'users', 'backgroundImage', 'TEXT');
    }
    if (oldVersion < 30) {
      await _addColumnIfNotExists(db, 'chat_messages', 'reasoning', 'TEXT');
    }
    if (oldVersion < 31) {
      // X 推特风格：moments 表新增字段
      await _addColumnIfNotExists(db, 'moments', 'parentKey', 'TEXT');
      await _addColumnIfNotExists(db, 'moments', 'retweetKey', 'TEXT');
      await _addColumnIfNotExists(db, 'moments', 'quoteKey', 'TEXT');
      await _addColumnIfNotExists(
          db, 'moments', 'retweetCount', 'INTEGER NOT NULL DEFAULT 0');
      await _addColumnIfNotExists(
          db, 'moments', 'replyCount', 'INTEGER NOT NULL DEFAULT 0');
      await _addColumnIfNotExists(
          db, 'moments', 'bookmarkCount', 'INTEGER NOT NULL DEFAULT 0');
      await _addColumnIfNotExists(
          db, 'moments', 'viewCount', 'INTEGER NOT NULL DEFAULT 0');
      await _addColumnIfNotExists(db, 'moments', 'tags', "TEXT DEFAULT '[]'");
      await _addColumnIfNotExists(db, 'moments', 'userHandle', 'TEXT');
      await _addColumnIfNotExists(db, 'moments', 'userGender', 'TEXT');
      await _addColumnIfNotExists(
          db, 'moments', 'userVerified', 'INTEGER NOT NULL DEFAULT 0');
      await _addColumnIfNotExists(
          db, 'moments', 'customLikeCount', 'INTEGER NOT NULL DEFAULT 0');

      // 书签表
      await db.execute(''' CREATE TABLE IF NOT EXISTS moment_bookmarks (
        id TEXT PRIMARY KEY, momentId TEXT NOT NULL, userId TEXT NOT NULL,
        createdAt TEXT NOT NULL
      ) ''');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_moment_bookmarks_userId ON moment_bookmarks(userId)');

      // 通知表
      await db.execute(''' CREATE TABLE IF NOT EXISTS moment_notifications (
        id TEXT PRIMARY KEY, momentId TEXT NOT NULL, actorId TEXT NOT NULL,
        actorName TEXT NOT NULL, actorAvatar TEXT, type INTEGER NOT NULL DEFAULT 0,
        content TEXT, createdAt TEXT NOT NULL, isRead INTEGER NOT NULL DEFAULT 0,
        isFromAI INTEGER NOT NULL DEFAULT 0
      ) ''');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_moment_notifications_createdAt ON moment_notifications(createdAt DESC)');

      // 热门话题表
      await db.execute(''' CREATE TABLE IF NOT EXISTS trending_tags (
        tag TEXT PRIMARY KEY, count INTEGER NOT NULL DEFAULT 1,
        lastUsedAt TEXT NOT NULL
      ) ''');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_trending_tags_count ON trending_tags(count DESC)');
    }
    if (oldVersion < 32) {
      final momentColumns = await getTableColumns(db, 'moments');
      if (!momentColumns.contains('source')) {
        await db.execute(
            'ALTER TABLE moments ADD COLUMN source INTEGER NOT NULL DEFAULT 0');
      }
      await db.execute('''
        UPDATE moments
        SET source = 1
        WHERE (parentKey IS NOT NULL AND parentKey != '')
           OR (retweetKey IS NOT NULL AND retweetKey != '')
           OR (quoteKey IS NOT NULL AND quoteKey != '')
           OR (userHandle IS NOT NULL AND userHandle != '')
           OR (tags IS NOT NULL AND tags != '' AND tags != '[]')
           OR replyCount > 0
           OR retweetCount > 0
           OR bookmarkCount > 0
           OR viewCount > 0
           OR customLikeCount > 0
      ''');
    }
    if (oldVersion < 33) {
      await createIntimacyEventsTable(db);
    }
    if (oldVersion < 34) {
      await _addColumnIfNotExists(db, 'ai_characters', 'userPersona', 'TEXT');
    }
    // 先确保 ai_letters 表存在（旧用户升级时表可能不存在）
    await createAILettersTable(db);
    if (oldVersion < 35) {
      await _addColumnIfNotExists(
          db, 'ai_letters', 'isFromUser', 'INTEGER NOT NULL DEFAULT 0');
    }
    if (oldVersion < 36) {
      await _addColumnIfNotExists(
          db, 'ai_letters', 'needsReply', 'INTEGER NOT NULL DEFAULT 0');
    }
    if (oldVersion < 37) {
      // BT Agent 审计日志表
      await db.execute(''' CREATE TABLE IF NOT EXISTS bt_agent_actions (
        id TEXT PRIMARY KEY,
        actionType TEXT NOT NULL DEFAULT '',
        category TEXT NOT NULL DEFAULT '',
        scope TEXT NOT NULL DEFAULT '',
        targetType TEXT NOT NULL DEFAULT '',
        targetId TEXT NOT NULL DEFAULT '',
        reason TEXT NOT NULL DEFAULT '',
        stateBefore TEXT NOT NULL DEFAULT '',
        stateAfter TEXT NOT NULL DEFAULT '',
        result TEXT NOT NULL DEFAULT '',
        rejectionReason TEXT NOT NULL DEFAULT '',
        characterId TEXT NOT NULL DEFAULT '',
        sessionId TEXT NOT NULL DEFAULT '',
        chatType TEXT NOT NULL DEFAULT 'single',
        createdAt TEXT NOT NULL DEFAULT ''
      ) ''');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_bt_agent_actions_createdAt ON bt_agent_actions(createdAt DESC)');
    }
    if (oldVersion < 38) {
      // 社交会话类型：chat_sessions 新增 sessionType 列
      await _addColumnIfNotExists(
          db, 'chat_sessions', 'sessionType', 'TEXT DEFAULT "private"');
      // AI 社交记忆表
      await db.execute(''' CREATE TABLE IF NOT EXISTS social_memories (
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
      ) ''');
    }
    if (oldVersion < 39) {
      // 角色视觉锚定字段
      await _addColumnIfNotExists(db, 'ai_characters', 'referenceImg', 'TEXT');
      await _addColumnIfNotExists(
          db, 'ai_characters', 'fixedSeed', 'INTEGER NOT NULL DEFAULT -1');
      await _addColumnIfNotExists(db, 'ai_characters', 'characterTag', 'TEXT');
      await _addColumnIfNotExists(
          db, 'ai_characters', 'styleLock', 'TEXT NOT NULL DEFAULT "anime"');
    }
    if (oldVersion < 41) {
      await _addColumnIfNotExists(db, 'ai_characters', 'age', 'INTEGER');
    }
    if (oldVersion < 42) {
      await _addColumnIfNotExists(
          db, 'chat_sessions', 'intimacyMode', 'TEXT DEFAULT "quick"');
      await _addColumnIfNotExists(
          db, 'chat_sessions', 'streakDays', 'INTEGER NOT NULL DEFAULT 0');
      await _addColumnIfNotExists(
          db, 'chat_sessions', 'isInFriction', 'INTEGER NOT NULL DEFAULT 0');
      await _addColumnIfNotExists(db, 'chat_sessions', 'frictionDaysLeft',
          'INTEGER NOT NULL DEFAULT 0');
    }
    if (oldVersion < 43) {
      // 索引优化预留
    }
    if (oldVersion < 44) {
      // 预留
    }
    if (oldVersion < 45) {
      // 预留
    }
    if (oldVersion < 46) {
      // 预留
    }
    if (oldVersion < 47) {
      // 预留
    }
    if (oldVersion < 48) {
      // 预留
    }
    if (oldVersion < 50) {
      // 虚拟手机模块（每个 AI 角色的专属虚构手机，纯本地生成内容）
      await _createVirtualPhoneTables(db);
    }
    if (oldVersion < 51) {
      // 虚拟手机「生活推进」增量追踪列（首次全量后，跟随关系缓慢生长）
      await _addColumnIfNotExists(db, 'virtual_phones', 'lastAdvanceMsgCount',
          'INTEGER NOT NULL DEFAULT 0');
      await _addColumnIfNotExists(
          db, 'virtual_phones', 'lastAdvanceAt', 'TEXT');
    }
    if (oldVersion < 52) {
      // 角色结构化特征（兴趣、作息、口癖）
      await _addColumnIfNotExists(
          db, 'ai_characters', 'structuredTraits', 'TEXT');
    }
    if (oldVersion < 53) {
      // 小说模块
      await _createNovelTables(db);
    }
    if (oldVersion < 54) {
      // 记忆摘要等列：旧库缺列会导致 saveMemory 写库失败
      await _addColumnIfNotExists(db, 'memories', 'summary', 'TEXT');
      await _addColumnIfNotExists(db, 'memories', 'keywords', 'TEXT');
      await _addColumnIfNotExists(db, 'memories', 'lastAccessedAt', 'TEXT');
      await _addColumnIfNotExists(
          db, 'memories', 'accessCount', 'INTEGER NOT NULL DEFAULT 0');
      await _addColumnIfNotExists(
          db, 'memories', 'weight', 'REAL NOT NULL DEFAULT 1.0');
      await _addColumnIfNotExists(
          db, 'memories', 'pinned', 'INTEGER NOT NULL DEFAULT 0');
      await _addColumnIfNotExists(db, 'memories', 'lastRecalledAt', 'TEXT');
      await _addColumnIfNotExists(db, 'ai_characters', 'userAlias', 'TEXT');
    }
    if (oldVersion < 55) {
      // v55: 商店功能初始化 - 先确保表结构，再填充种子
      await _ensureShopItemsSchema(db);
      final count = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM shop_items'),
      );
      if (count == null || count == 0) {
        final items = _seedShopItems();
        for (final item in items) {
          await _insertShopItemSafe(db, item);
        }
        debugPrint(' v55 迁移: 已填充 ${items.length} 个商品到 shop_items 表');
      }
    }
    if (oldVersion < 56) {
      // v56: AI 群聊模块 -- group_chat_sessions + group_chat_messages 表
      await createMissingTable(db, 'group_chat_sessions');
      await createMissingTable(db, 'group_chat_messages');
      debugPrint(' v56 迁移: 群聊表已创建/校验');
    }
    if (oldVersion < 57) {
      // v57: chat_sessions 增加 lastOnlineAt 字段（在线状态最后活跃时间）
      await _addColumnIfNotExists(db, 'chat_sessions', 'lastOnlineAt', 'TEXT');
      debugPrint(' v57 迁移: chat_sessions.lastOnlineAt 已添加');
    }
    if (oldVersion < 58) {
      // v58: 确保 chat_sessions.novelMode 存在（旧库缺列会导致新建角色写会话崩溃）
      await _addColumnIfNotExists(
          db, 'chat_sessions', 'novelMode', 'INTEGER DEFAULT -1');
      debugPrint(' v58 迁移: chat_sessions.novelMode 已添加');
    }
    if (oldVersion < 59) {
      // v59: 老用户升级全面补列（toMap 会写 sync_seq / moments.source 等）
      // 原则：全部用可空/DEFAULT，避免 ALTER 失败
      await _addColumnIfNotExists(db, 'users', 'backgroundImage', 'TEXT');
      await _addColumnIfNotExists(db, 'users', 'sync_seq', 'INTEGER DEFAULT 0');
      await _addColumnIfNotExists(
          db, 'ai_characters', 'sync_seq', 'INTEGER DEFAULT 0');
      await _addColumnIfNotExists(
          db, 'ai_configs', 'extraApiKeys', 'TEXT DEFAULT ""');
      await _addColumnIfNotExists(
          db, 'ai_configs', 'isThinkingModel', 'INTEGER DEFAULT 1');
      await _addColumnIfNotExists(
          db, 'ai_configs', 'sync_seq', 'INTEGER DEFAULT 0');
      await _addColumnIfNotExists(
          db, 'chat_sessions', 'sync_seq', 'INTEGER DEFAULT 0');
      await _addColumnIfNotExists(
          db, 'chat_sessions', 'novelMode', 'INTEGER DEFAULT -1');
      await _addColumnIfNotExists(db, 'chat_sessions', 'lastOnlineAt', 'TEXT');
      await _addColumnIfNotExists(
          db, 'chat_messages', 'sync_seq', 'INTEGER DEFAULT 0');
      await _addColumnIfNotExists(
          db, 'chat_messages', 'isBookmark', 'INTEGER DEFAULT 0');
      await _addColumnIfNotExists(db, 'chat_messages', 'pokeSuffix', 'TEXT');
      await _addColumnIfNotExists(db, 'chat_messages', 'stickerId', 'TEXT');
      await _addColumnIfNotExists(db, 'chat_messages', 'stickerPath', 'TEXT');
      await _addColumnIfNotExists(
          db, 'chat_messages', 'isUser', 'INTEGER DEFAULT 0');
      await _addColumnIfNotExists(
          db, 'chat_messages', 'isSystem', 'INTEGER DEFAULT 0');
      await _addColumnIfNotExists(
          db, 'chat_messages', 'isHidden', 'INTEGER DEFAULT 0');
      await _addColumnIfNotExists(
          db, 'chat_messages', 'isGhost', 'INTEGER DEFAULT 0');
      await _addColumnIfNotExists(db, 'chat_messages', 'reasoning', 'TEXT');
      await _addColumnIfNotExists(db, 'memories', 'summary', 'TEXT');
      await _addColumnIfNotExists(db, 'memories', 'keywords', 'TEXT');
      await _addColumnIfNotExists(db, 'memories', 'lastAccessedAt', 'TEXT');
      await _addColumnIfNotExists(
          db, 'memories', 'accessCount', 'INTEGER DEFAULT 0');
      await _addColumnIfNotExists(db, 'memories', 'weight', 'REAL DEFAULT 1.0');
      await _addColumnIfNotExists(
          db, 'memories', 'pinned', 'INTEGER DEFAULT 0');
      await _addColumnIfNotExists(db, 'memories', 'lastRecalledAt', 'TEXT');
      await _addColumnIfNotExists(
          db, 'memories', 'sync_seq', 'INTEGER DEFAULT 0');
      // moments：早期表只有基础字段，X 风格扩展列必须补齐
      await _addColumnIfNotExists(db, 'moments', 'source', 'INTEGER DEFAULT 0');
      await _addColumnIfNotExists(
          db, 'moments', 'sync_seq', 'INTEGER DEFAULT 0');
      await _addColumnIfNotExists(db, 'moments', 'replyToCommentId', 'TEXT');
      await _addColumnIfNotExists(db, 'moments', 'replyToContent', 'TEXT');
      await _addColumnIfNotExists(
          db, 'moments', 'aiLiked', 'INTEGER DEFAULT 0');
      await _addColumnIfNotExists(db, 'moments', 'parentKey', 'TEXT');
      await _addColumnIfNotExists(db, 'moments', 'retweetKey', 'TEXT');
      await _addColumnIfNotExists(db, 'moments', 'quoteKey', 'TEXT');
      await _addColumnIfNotExists(
          db, 'moments', 'retweetCount', 'INTEGER DEFAULT 0');
      await _addColumnIfNotExists(
          db, 'moments', 'replyCount', 'INTEGER DEFAULT 0');
      await _addColumnIfNotExists(
          db, 'moments', 'bookmarkCount', 'INTEGER DEFAULT 0');
      await _addColumnIfNotExists(
          db, 'moments', 'viewCount', 'INTEGER DEFAULT 0');
      await _addColumnIfNotExists(db, 'moments', 'tags', 'TEXT');
      await _addColumnIfNotExists(db, 'moments', 'userHandle', 'TEXT');
      await _addColumnIfNotExists(db, 'moments', 'userGender', 'TEXT');
      await _addColumnIfNotExists(
          db, 'moments', 'userVerified', 'INTEGER DEFAULT 0');
      await _addColumnIfNotExists(
          db, 'moments', 'customLikeCount', 'INTEGER DEFAULT 0');
      await _addColumnIfNotExists(
          db, 'sticker_packs', 'sync_seq', 'INTEGER DEFAULT 0');
      await _addColumnIfNotExists(
          db, 'ai_configs', 'isMultimodal', 'INTEGER DEFAULT 0');
      await _addColumnIfNotExists(
          db, 'ai_wallets', 'sync_seq', 'INTEGER DEFAULT 0');
      await _addColumnIfNotExists(
          db, 'shop_orders', 'sync_seq', 'INTEGER DEFAULT 0');
      await _addColumnIfNotExists(
          db, 'ai_characters', 'structuredTraits', 'TEXT');
      await _addColumnIfNotExists(db, 'ai_characters', 'userAlias', 'TEXT');
      // 缺表兜底（老安装可能只有核心表）
      await createMissingTable(db, 'shop_items');
      await createMissingTable(db, 'shop_orders');
      await createMissingTable(db, 'social_memories');
      await createMissingTable(db, 'moment_bookmarks');
      await createMissingTable(db, 'moment_notifications');
      await createMissingTable(db, 'trending_tags');
      await createMissingTable(db, 'intimacy_events');
      await createMissingTable(db, 'group_chat_sessions');
      await createMissingTable(db, 'group_chat_messages');
      await createMissingTable(db, 'pure_ai_sessions');
      await createMissingTable(db, 'pure_ai_messages');
      await createMissingTable(db, 'novels');
      await createMissingTable(db, 'novel_chapters');
      await createMissingTable(db, 'virtual_phones');
      debugPrint(' v59 迁移: 核心表补列 + 缺表兜底完成');
    }
    if (oldVersion < 60) {
      // v60: AI 配置支持用户手动标记多模态（看图）
      await _addColumnIfNotExists(
          db, 'ai_configs', 'isMultimodal', 'INTEGER DEFAULT 0');
      debugPrint(' v60 迁移: ai_configs.isMultimodal 已添加');
    }
    if (oldVersion < 61) {
      // v61: 商店支持用户自定义商品
      await _ensureShopItemsSchema(db);
      debugPrint(' v61 迁移: shop_items 自定义商品字段已添加');
    }
    if (oldVersion < 62) {
      // v62: shop_items 兼容修复（老版本可能缺少 isCustom/createdAt）
      await _ensureShopItemsSchema(db);
      debugPrint(' v62 迁移: shop_items 列兼容性修复完成');
    }
    if (oldVersion < 63) {
      // v63: 强制校验并重建 shop_items（解决「版本已升但列仍缺」）
      await _ensureShopItemsSchema(db, force: true);
      debugPrint(' v63 迁移: shop_items schema 强制校验完成');
    }
    if (oldVersion < 64) {
      // v64: 强制校验 shop_items schema
      await _ensureShopItemsSchema(db, force: true);
      debugPrint('✅ v64 迁移: shop_items 强制 schema 就绪');
    }
    if (oldVersion < 65) {
      // v65: SillyTavern 群聊引擎还原 — 配置字段 + 多聊天记录 + 话痨属性
      await _addColumnIfNotExists(
          db, 'ai_characters', 'talkativeness', 'REAL NOT NULL DEFAULT 0.5');
      await _addColumnIfNotExists(
          db, 'group_chat_sessions', 'chatId', 'TEXT NOT NULL DEFAULT ""');
      await _addColumnIfNotExists(db, 'group_chat_sessions',
          'activationStrategy', 'INTEGER NOT NULL DEFAULT 0');
      await _addColumnIfNotExists(db, 'group_chat_sessions', 'generationMode',
          'INTEGER NOT NULL DEFAULT 0');
      await _addColumnIfNotExists(db, 'group_chat_sessions',
          'allowSelfResponses', 'INTEGER NOT NULL DEFAULT 0');
      await _addColumnIfNotExists(db, 'group_chat_sessions',
          'disabledMemberIds', 'TEXT NOT NULL DEFAULT "[]"');
      await _addColumnIfNotExists(db, 'group_chat_sessions', 'autoModeDelay',
          'INTEGER NOT NULL DEFAULT 5');
      await _addColumnIfNotExists(db, 'group_chat_sessions', 'autoModeEnabled',
          'INTEGER NOT NULL DEFAULT 0');
      await _addColumnIfNotExists(db, 'group_chat_sessions',
          'autoModeDelaysByCharacter', "TEXT NOT NULL DEFAULT '{}'");
      await _addColumnIfNotExists(
          db, 'group_chat_sessions', 'isHidden', 'INTEGER NOT NULL DEFAULT 0');
      await _addColumnIfNotExists(
          db, 'group_chat_sessions', 'joinPrefix', 'TEXT NOT NULL DEFAULT ""');
      await _addColumnIfNotExists(
          db, 'group_chat_sessions', 'joinSuffix', 'TEXT NOT NULL DEFAULT ""');
      await _addColumnIfNotExists(
          db, 'group_chat_messages', 'chatId', 'TEXT NOT NULL DEFAULT ""');
      // 老消息归入默认分支（chatId=groupId）
      await db.execute(
          'UPDATE group_chat_messages SET chatId = groupId WHERE chatId = ""');
      await db.execute('''CREATE TABLE IF NOT EXISTS group_chat_branches (
        branchId TEXT PRIMARY KEY,
        groupId TEXT NOT NULL DEFAULT '',
        name TEXT NOT NULL DEFAULT '',
        createdAt TEXT NOT NULL DEFAULT '',
        updatedAt TEXT
      )''');
      // 每个群补默认分支 + 当前 chatId 指向群 id
      final sessions = await db.query('group_chat_sessions');
      for (final row in sessions) {
        final gid = row['id'] as String;
        await db.insert(
            'group_chat_branches',
            {
              'branchId': gid,
              'groupId': gid,
              'name': '默认聊天',
              'createdAt': DateTime.now().toIso8601String(),
            },
            conflictAlgorithm: ConflictAlgorithm.ignore);
        await db.rawUpdate(
            'UPDATE group_chat_sessions SET chatId = ? WHERE id = ? AND chatId = ""',
            [gid, gid]);
      }
      debugPrint(' v65 迁移: 群聊引擎字段 + 分支表已就绪');
    }
    if (oldVersion < 66) {
      // v66: 强制重建 group_chat_sessions —— 老设备表可能含
      // `userId TEXT NOT NULL`（无默认值），导致创建群 INSERT 时 NULL 约束崩溃。
      // 备份 → 统一 schema 重建 → 回迁，保证 userId 列带默认值。
      await _rebuildGroupChatSessionsTable(db);
      debugPrint(' v66 迁移: group_chat_sessions 强制重建完成');
    }
    if (oldVersion < 68) {
      for (final table in [
        'story_books',
        'story_segments',
        'story_scenes',
        'story_saves',
      ]) {
        await db.execute('DROP TABLE IF EXISTS $table');
      }
      debugPrint(' v68 迁移: 故事书模块数据表已移除');
    }
    if (oldVersion < 69) {
      await createCharacterCommitmentsTable(db);
      debugPrint(' v69 迁移: 角色承诺表已就绪');
    }
    if (oldVersion < 70) {
      await createRelationshipContextsTable(db);
      debugPrint(' v70 迁移: 关系上下文表已就绪');
    }
    if (oldVersion < 71) {
      await db.execute(createMoneyTransactionsSql);
      await db.execute(
          ''' CREATE INDEX IF NOT EXISTS idx_money_chatId ON money_transactions(chatId) ''');
      await db.execute(
          ''' CREATE INDEX IF NOT EXISTS idx_money_userId ON money_transactions(userId) ''');
      debugPrint(' v71 迁移: 转账/红包流水表已就绪');
    }
  }
  Future<void> _onCreate(Database db, int version) async {
    await db.execute(
        ''' CREATE TABLE users ( id TEXT PRIMARY KEY, nickname TEXT NOT NULL, avatarUrl TEXT, createdAt TEXT NOT NULL, lastLoginAt TEXT, signature TEXT, gender TEXT, birthday TEXT, location TEXT, bio TEXT, status TEXT, backgroundImage TEXT, coins INTEGER NOT NULL DEFAULT 100, totalCoinsEarned INTEGER NOT NULL DEFAULT 100, totalCoinsSpent INTEGER NOT NULL DEFAULT 0, sync_seq INTEGER NOT NULL DEFAULT 0 ) ''');
    await db.execute(
        ''' CREATE TABLE ai_characters ( id TEXT PRIMARY KEY, name TEXT NOT NULL, avatarUrl TEXT, personality TEXT NOT NULL, coreDesire TEXT NOT NULL, moralBoundary TEXT NOT NULL, backgroundStory TEXT, createdAt TEXT NOT NULL, updatedAt TEXT, worldSetting TEXT, languageStyle TEXT, tabooTopics TEXT, userNickname TEXT, userAlias TEXT, userPersona TEXT, catchphrases TEXT, openingLine TEXT, dialogueExamples TEXT, interactionConfig TEXT, gender TEXT, isHidden INTEGER NOT NULL DEFAULT 0, isOnline INTEGER NOT NULL DEFAULT 1, currentStatus TEXT, lastOnlineAt TEXT, avatarGif TEXT, autoReplyStickers INTEGER NOT NULL DEFAULT 0, translatedSettings TEXT, sync_seq INTEGER NOT NULL DEFAULT 0, immutableAnchor TEXT, deviationRadius REAL NOT NULL DEFAULT 0.4, evolutionEnabled INTEGER NOT NULL DEFAULT 1, qualitativeEvolutionEnabled INTEGER NOT NULL DEFAULT 0, currentAnchor TEXT, referenceImg TEXT, fixedSeed INTEGER NOT NULL DEFAULT -1, characterTag TEXT, styleLock TEXT NOT NULL DEFAULT "anime", age INTEGER, structuredTraits TEXT, storyState TEXT ) ''');
    await db.execute(
        ''' CREATE TABLE ai_configs ( id TEXT PRIMARY KEY, providerName TEXT NOT NULL, baseUrl TEXT NOT NULL, apiKey TEXT NOT NULL, extraApiKeys TEXT NOT NULL DEFAULT '', modelName TEXT NOT NULL, temperature REAL NOT NULL, maxTokens INTEGER NOT NULL, isActive INTEGER NOT NULL DEFAULT 1, isThinkingModel INTEGER NOT NULL DEFAULT 1, isMultimodal INTEGER NOT NULL DEFAULT 0, createdAt TEXT NOT NULL, updatedAt TEXT, sync_seq INTEGER NOT NULL DEFAULT 0 ) ''');
    await db.execute(
        ''' CREATE TABLE chat_sessions ( id TEXT PRIMARY KEY, userId TEXT NOT NULL, aiCharacterId TEXT NOT NULL, aiCharacterName TEXT NOT NULL, aiCharacterAvatar TEXT, lastMessage TEXT, lastMessageTime TEXT, unreadCount INTEGER NOT NULL DEFAULT 0, intimacyLevel INTEGER NOT NULL DEFAULT 0, dailyIntimacyCount INTEGER NOT NULL DEFAULT 0, lastIntimacyDate TEXT, createdAt TEXT NOT NULL, updatedAt TEXT, isMuted INTEGER NOT NULL DEFAULT 0, isPinned INTEGER NOT NULL DEFAULT 0, backgroundImage TEXT, isHidden INTEGER NOT NULL DEFAULT 0, aiIsOnline INTEGER NOT NULL DEFAULT 1, aiCurrentStatus TEXT, lastOnlineAt TEXT, sync_seq INTEGER NOT NULL DEFAULT 0, isBlocked INTEGER NOT NULL DEFAULT 0, blockedBy INTEGER NOT NULL DEFAULT 0, blockedAt TEXT, blockReason TEXT, sessionType TEXT DEFAULT "private", intimacyMode TEXT DEFAULT "quick", streakDays INTEGER NOT NULL DEFAULT 0, isInFriction INTEGER NOT NULL DEFAULT 0, frictionDaysLeft INTEGER NOT NULL DEFAULT 0, novelMode INTEGER NOT NULL DEFAULT -1 ) ''');
    await db.execute(
        ''' CREATE INDEX idx_sessions_userId ON chat_sessions(userId) ''');
    await db.execute(
        ''' CREATE INDEX idx_sessions_characterId ON chat_sessions(aiCharacterId) ''');
    await db.execute(
        ''' CREATE TABLE chat_messages ( id TEXT PRIMARY KEY, chatId TEXT NOT NULL, senderId TEXT NOT NULL, senderName TEXT, content TEXT NOT NULL, isUser INTEGER NOT NULL DEFAULT 0, isSystem INTEGER NOT NULL DEFAULT 0, isHidden INTEGER NOT NULL DEFAULT 0, isGhost INTEGER NOT NULL DEFAULT 0, type TEXT NOT NULL DEFAULT 'text', status TEXT NOT NULL DEFAULT 'sent', createdAt TEXT NOT NULL, readAt TEXT, reasoning TEXT, metadata TEXT, sync_seq INTEGER NOT NULL DEFAULT 0, pokeSuffix TEXT, stickerId TEXT, stickerPath TEXT, isBookmark INTEGER NOT NULL DEFAULT 0 ) ''');
    await db.execute(
        ''' CREATE INDEX idx_messages_chatId ON chat_messages(chatId) ''');
    await createIntimacyEventsTable(db);
    await createCharacterCommitmentsTable(db);
    await createRelationshipContextsTable(db);
    await db.execute(createMoneyTransactionsSql);
    await db.execute(
        ''' CREATE INDEX IF NOT EXISTS idx_money_chatId ON money_transactions(chatId) ''');
    await db.execute(
        ''' CREATE INDEX IF NOT EXISTS idx_money_userId ON money_transactions(userId) ''');
    await db.execute(
        ''' CREATE TABLE memories ( id TEXT PRIMARY KEY, characterId TEXT NOT NULL, userId TEXT NOT NULL, type INTEGER NOT NULL, content TEXT NOT NULL, importance INTEGER NOT NULL DEFAULT 1, keywords TEXT, createdAt TEXT NOT NULL, lastAccessedAt TEXT, accessCount INTEGER NOT NULL DEFAULT 0, sync_seq INTEGER NOT NULL DEFAULT 0, weight REAL NOT NULL DEFAULT 1.0, pinned INTEGER NOT NULL DEFAULT 0, lastRecalledAt TEXT, summary TEXT ) ''');
    await db.execute(
        ''' CREATE INDEX idx_memories_characterId ON memories(characterId) ''');
    await db
        .execute(''' CREATE INDEX idx_memories_userId ON memories(userId) ''');
    await db.execute(
        ''' CREATE INDEX IF NOT EXISTS idx_memories_char_user ON memories(characterId, userId) ''');

    await db.execute(
        ''' CREATE TABLE IF NOT EXISTS moments ( id TEXT PRIMARY KEY, userId TEXT NOT NULL, userName TEXT NOT NULL, userAvatar TEXT, content TEXT NOT NULL, images TEXT DEFAULT '', type INTEGER NOT NULL DEFAULT 0, likes TEXT DEFAULT '[]', comments TEXT DEFAULT '[]', createdAt TEXT NOT NULL, updatedAt TEXT, isFromAI INTEGER NOT NULL DEFAULT 0, visibility INTEGER NOT NULL DEFAULT 0, source INTEGER NOT NULL DEFAULT 0, sync_seq INTEGER NOT NULL DEFAULT 0, replyToCommentId TEXT, replyToContent TEXT, aiLiked INTEGER NOT NULL DEFAULT 0, parentKey TEXT, retweetKey TEXT, quoteKey TEXT, retweetCount INTEGER NOT NULL DEFAULT 0, replyCount INTEGER NOT NULL DEFAULT 0, bookmarkCount INTEGER NOT NULL DEFAULT 0, viewCount INTEGER NOT NULL DEFAULT 0, tags TEXT DEFAULT '[]', userHandle TEXT, userGender TEXT, userVerified INTEGER NOT NULL DEFAULT 0, customLikeCount INTEGER NOT NULL DEFAULT 0 ) ''');
    await db
        .execute(''' CREATE INDEX idx_moments_userId ON moments(userId) ''');
    await db.execute(
        ''' CREATE INDEX idx_moments_createdAt ON moments(createdAt DESC) ''');
    await db.execute(
        ''' CREATE TABLE sticker_packs ( id TEXT PRIMARY KEY, name TEXT NOT NULL, coverImagePath TEXT, stickers TEXT, createdAt TEXT NOT NULL, updatedAt TEXT, isDefault INTEGER NOT NULL DEFAULT 0, sync_seq INTEGER NOT NULL DEFAULT 0 ) ''');
    await createAILettersTable(db);
    await db.execute(
        ''' CREATE TABLE ai_wallets ( characterId TEXT PRIMARY KEY, balance INTEGER NOT NULL DEFAULT 50, totalEarned INTEGER NOT NULL DEFAULT 50, totalSpent INTEGER NOT NULL DEFAULT 0, dailySpent INTEGER NOT NULL DEFAULT 0, dailySpentDate TEXT, spendingPersonality INTEGER NOT NULL DEFAULT 5, sync_seq INTEGER NOT NULL DEFAULT 0 ) ''');
    await db.execute(_shopItemsCreateSql);
    await db.execute(
        ''' CREATE TABLE shop_orders ( id TEXT PRIMARY KEY, buyerType TEXT NOT NULL DEFAULT 'user', buyerId TEXT NOT NULL DEFAULT '', receiverType TEXT NOT NULL DEFAULT 'ai', receiverId TEXT NOT NULL DEFAULT '', chatSessionId TEXT NOT NULL DEFAULT '', itemId TEXT NOT NULL DEFAULT '', itemName TEXT NOT NULL DEFAULT '', itemEmoji TEXT NOT NULL DEFAULT '', price INTEGER NOT NULL DEFAULT 0, status TEXT DEFAULT 'pending', message TEXT, createdAt TEXT NOT NULL DEFAULT '', preparingAt TEXT, shippingAt TEXT, deliveredAt TEXT, aiReaction TEXT, sync_seq INTEGER NOT NULL DEFAULT 0 ) ''');
    await db.execute(
        ''' CREATE TABLE pure_ai_sessions ( id TEXT PRIMARY KEY, userId TEXT NOT NULL, title TEXT NOT NULL DEFAULT 'AI', lastMessage TEXT, lastMessageTime TEXT, isPinned INTEGER NOT NULL DEFAULT 0, createdAt TEXT NOT NULL, updatedAt TEXT ) ''');
    await db.execute(
        ''' CREATE TABLE pure_ai_messages ( id TEXT PRIMARY KEY, sessionId TEXT NOT NULL, senderId TEXT NOT NULL, senderName TEXT, content TEXT NOT NULL, type INTEGER NOT NULL DEFAULT 0, status INTEGER NOT NULL DEFAULT 1, createdAt TEXT NOT NULL, metadata TEXT ) ''');
    await _createVirtualPhoneTables(db);

    // ─── 以下表在旧版本仅由 _onUpgrade 创建，新用户 _onCreate 缺失会导致崩溃 ───

    // AI 社交记忆表（v38 迁移新增）
    await db.execute(''' CREATE TABLE IF NOT EXISTS social_memories (
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
    ) ''');

    // X 推特风格：书签表（v31 迁移新增）
    await db.execute(''' CREATE TABLE IF NOT EXISTS moment_bookmarks (
      id TEXT PRIMARY KEY, momentId TEXT NOT NULL, userId TEXT NOT NULL,
      createdAt TEXT NOT NULL
    ) ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_moment_bookmarks_userId ON moment_bookmarks(userId)');

    // X 推特风格：通知表（v31 迁移新增）
    await db.execute(''' CREATE TABLE IF NOT EXISTS moment_notifications (
      id TEXT PRIMARY KEY, momentId TEXT NOT NULL, actorId TEXT NOT NULL,
      actorName TEXT NOT NULL, actorAvatar TEXT, type INTEGER NOT NULL DEFAULT 0,
      content TEXT, createdAt TEXT NOT NULL, isRead INTEGER NOT NULL DEFAULT 0,
      isFromAI INTEGER NOT NULL DEFAULT 0
    ) ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_moment_notifications_createdAt ON moment_notifications(createdAt DESC)');

    // X 推特风格：热门话题表（v31 迁移新增）
    await db.execute(''' CREATE TABLE IF NOT EXISTS trending_tags (
      tag TEXT PRIMARY KEY, count INTEGER NOT NULL DEFAULT 1,
      lastUsedAt TEXT NOT NULL
    ) ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_trending_tags_count ON trending_tags(count DESC)');

    // 内心活动表（v26 迁移新增）
    await db.execute(''' CREATE TABLE IF NOT EXISTS inner_thoughts (
      id TEXT PRIMARY KEY, characterId TEXT NOT NULL DEFAULT '', userId TEXT NOT NULL DEFAULT '',
      content TEXT NOT NULL DEFAULT '', type INTEGER NOT NULL DEFAULT 0,
      emotionValence REAL NOT NULL DEFAULT 0, emotionArousal REAL NOT NULL DEFAULT 0,
      isRead INTEGER NOT NULL DEFAULT 0, createdAt TEXT NOT NULL DEFAULT ''
    ) ''');

    // 虚拟日记帖子和评论表（v26 迁移新增）
    await db.execute(''' CREATE TABLE IF NOT EXISTS forum_posts (
      id TEXT PRIMARY KEY, authorId TEXT NOT NULL DEFAULT '', authorName TEXT NOT NULL DEFAULT '',
      authorAvatar TEXT, isFromAI INTEGER NOT NULL DEFAULT 0, characterId TEXT,
      title TEXT NOT NULL DEFAULT '', content TEXT NOT NULL DEFAULT '', images TEXT, tags TEXT,
      likes TEXT DEFAULT '[]', isAnonymous INTEGER NOT NULL DEFAULT 0,
      visibility INTEGER NOT NULL DEFAULT 0, createdAt TEXT NOT NULL DEFAULT '', updatedAt TEXT
    ) ''');
    await db.execute(''' CREATE TABLE IF NOT EXISTS forum_comments (
      id TEXT PRIMARY KEY, postId TEXT NOT NULL DEFAULT '', authorId TEXT NOT NULL DEFAULT '',
      authorName TEXT NOT NULL DEFAULT '', authorAvatar TEXT, isFromAI INTEGER NOT NULL DEFAULT 0,
      characterId TEXT, content TEXT NOT NULL DEFAULT '', replyToId TEXT, replyToName TEXT,
      isAnonymous INTEGER NOT NULL DEFAULT 0, createdAt TEXT NOT NULL DEFAULT ''
    ) ''');

    // 共同回忆相册表（v26 迁移新增）
    await db.execute(''' CREATE TABLE IF NOT EXISTS shared_album_entries (
      id TEXT PRIMARY KEY, characterId TEXT NOT NULL DEFAULT '', userId TEXT NOT NULL DEFAULT '',
      memoryId TEXT, title TEXT NOT NULL DEFAULT '', description TEXT, eventDate TEXT,
      imagePath TEXT, importance INTEGER NOT NULL DEFAULT 1, createdAt TEXT NOT NULL DEFAULT ''
    ) ''');

    // 虚拟地图位置表（v26 迁移新增）
    await db.execute(''' CREATE TABLE IF NOT EXISTS virtual_locations (
      id TEXT PRIMARY KEY, characterId TEXT NOT NULL DEFAULT '', userId TEXT NOT NULL DEFAULT '',
      userLat REAL NOT NULL DEFAULT 0, userLng REAL NOT NULL DEFAULT 0,
      aiLat REAL NOT NULL DEFAULT 0, aiLng REAL NOT NULL DEFAULT 0,
      sceneDescription TEXT, distance REAL NOT NULL DEFAULT 0, createdAt TEXT NOT NULL DEFAULT ''
    ) ''');

    // 角色成长事件表（v27 迁移新增）
    await db.execute(''' CREATE TABLE IF NOT EXISTS growth_events (
      id TEXT PRIMARY KEY, characterId TEXT NOT NULL DEFAULT '', userId TEXT NOT NULL DEFAULT '',
      triggerType TEXT NOT NULL DEFAULT 'micro', evolutionMode TEXT NOT NULL DEFAULT 'micro',
      triggerData TEXT NOT NULL DEFAULT '{}', deltas TEXT NOT NULL DEFAULT '{}',
      impactScore REAL NOT NULL DEFAULT 0, reason TEXT, createdAt TEXT NOT NULL DEFAULT ''
    ) ''');

    // 角色人格快照表（v27 迁移新增）
    await db.execute(''' CREATE TABLE IF NOT EXISTS persona_snapshots (
      id TEXT PRIMARY KEY, characterId TEXT NOT NULL DEFAULT '', snapshotType TEXT NOT NULL DEFAULT 'initial',
      traitsData TEXT NOT NULL DEFAULT '{}', surfaceData TEXT NOT NULL DEFAULT '{}',
      createdAt TEXT NOT NULL DEFAULT '', label TEXT
    ) ''');

    // BT Agent 审计日志表（v37 迁移新增）
    await db.execute(''' CREATE TABLE IF NOT EXISTS bt_agent_actions (
      id TEXT PRIMARY KEY, actionType TEXT NOT NULL DEFAULT '', category TEXT NOT NULL DEFAULT '',
      scope TEXT NOT NULL DEFAULT '', targetType TEXT NOT NULL DEFAULT '', targetId TEXT NOT NULL DEFAULT '',
      reason TEXT NOT NULL DEFAULT '', stateBefore TEXT NOT NULL DEFAULT '', stateAfter TEXT NOT NULL DEFAULT '',
      result TEXT NOT NULL DEFAULT '', rejectionReason TEXT NOT NULL DEFAULT '',
      characterId TEXT NOT NULL DEFAULT '', sessionId TEXT NOT NULL DEFAULT '',
      chatType TEXT NOT NULL DEFAULT 'single', createdAt TEXT NOT NULL DEFAULT ''
    ) ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_bt_agent_actions_createdAt ON bt_agent_actions(createdAt DESC)');

    // 小说模块（v53 新增）
    await _createNovelTables(db);

    // AI 群聊模块（v56 新增）—— _onCreate 必须补建，否则全新安装无表
    await db.execute(''' CREATE TABLE IF NOT EXISTS group_chat_sessions (
      id TEXT PRIMARY KEY,
      userId TEXT NOT NULL DEFAULT '',
      name TEXT NOT NULL DEFAULT '',
      avatarUrl TEXT,
      memberIds TEXT NOT NULL DEFAULT '[]',
      aiCharacterIds TEXT NOT NULL DEFAULT '[]',
      creatorId TEXT NOT NULL DEFAULT '',
      lastMessage TEXT,
      lastMessageTime TEXT,
      unreadCount INTEGER NOT NULL DEFAULT 0,
      isMuted INTEGER NOT NULL DEFAULT 0,
      isPinned INTEGER NOT NULL DEFAULT 0,
      backgroundImage TEXT,
      notice TEXT,
      createdAt TEXT NOT NULL DEFAULT '',
      updatedAt TEXT,
      sync_seq INTEGER NOT NULL DEFAULT 0
    ) ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_gc_sessions_creator ON group_chat_sessions(creatorId)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_gc_sessions_updatedAt ON group_chat_sessions(updatedAt DESC)');

    await db.execute(''' CREATE TABLE IF NOT EXISTS group_chat_messages (
      id TEXT PRIMARY KEY,
      groupId TEXT NOT NULL DEFAULT '',
      senderId TEXT NOT NULL DEFAULT '',
      senderName TEXT,
      content TEXT NOT NULL DEFAULT '',
      isUser INTEGER NOT NULL DEFAULT 0,
      isSystem INTEGER NOT NULL DEFAULT 0,
      type TEXT NOT NULL DEFAULT 'text',
      status TEXT NOT NULL DEFAULT 'sent',
      createdAt TEXT NOT NULL DEFAULT '',
      metadata TEXT,
      sync_seq INTEGER NOT NULL DEFAULT 0
    ) ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_gc_msgs_group ON group_chat_messages(groupId, createdAt DESC)');
    await createMissingTable(db, 'group_chat_summaries');
    await createMissingTable(db, 'group_public_event_memories');

    // v65: 群聊分支表（多聊天记录）+ 引擎配置字段 + 话痨属性
    await createMissingTable(db, 'group_chat_branches');
    await _addColumnIfNotExists(
        db, 'ai_characters', 'talkativeness', 'REAL NOT NULL DEFAULT 0.5');
    await _addColumnIfNotExists(
        db, 'group_chat_sessions', 'chatId', 'TEXT NOT NULL DEFAULT ""');
    await _addColumnIfNotExists(db, 'group_chat_sessions', 'activationStrategy',
        'INTEGER NOT NULL DEFAULT 0');
    await _addColumnIfNotExists(db, 'group_chat_sessions', 'generationMode',
        'INTEGER NOT NULL DEFAULT 0');
    await _addColumnIfNotExists(db, 'group_chat_sessions', 'allowSelfResponses',
        'INTEGER NOT NULL DEFAULT 0');
    await _addColumnIfNotExists(db, 'group_chat_sessions', 'disabledMemberIds',
        'TEXT NOT NULL DEFAULT "[]"');
    await _addColumnIfNotExists(db, 'group_chat_sessions', 'autoModeDelay',
        'INTEGER NOT NULL DEFAULT 5');
    await _addColumnIfNotExists(db, 'group_chat_sessions', 'autoModeEnabled',
        'INTEGER NOT NULL DEFAULT 0');
    await _addColumnIfNotExists(db, 'group_chat_sessions',
        'autoModeDelaysByCharacter', "TEXT NOT NULL DEFAULT '{}'");
    await _addColumnIfNotExists(
        db, 'group_chat_sessions', 'isHidden', 'INTEGER NOT NULL DEFAULT 0');
    await _addColumnIfNotExists(
        db, 'group_chat_sessions', 'joinPrefix', 'TEXT NOT NULL DEFAULT ""');
    await _addColumnIfNotExists(
        db, 'group_chat_sessions', 'joinSuffix', 'TEXT NOT NULL DEFAULT ""');
    await _addColumnIfNotExists(
        db, 'group_chat_messages', 'chatId', 'TEXT NOT NULL DEFAULT ""');
  }
  Future<void> saveUser(User user) async {
    if (_isWeb) {
      await _prefs?.setString(PrefKeys.user(user.id), jsonEncode(user.toMap()));
      await _prefs?.setString(PrefKeys.currentUserId, user.id);
    } else {
      final db = await _ensureDb();
      // 老库可能缺 backgroundImage/sync_seq 等列
      await _addColumnIfNotExists(db, 'users', 'backgroundImage', 'TEXT');
      await _addColumnIfNotExists(db, 'users', 'sync_seq', 'INTEGER DEFAULT 0');
      final map = await _filterMapToExistingColumns(db, 'users', user.toMap());
      await db.insert(
        DbTables.users,
        map,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }
  Future<User?> getUser(String id) async {
    if (_isWeb) {
      final data = _prefs?.getString('user_$id');
      if (data != null) {
        return User.fromMap(jsonDecode(data));
      }
      return null;
    } else {
      final db = await _ensureDb();
      final maps = await db.query(
        'users',
        where: 'id = ?',
        whereArgs: [id],
      );
      if (maps.isNotEmpty) {
        return User.fromMap(maps.first);
      }
      return null;
    }
  }
  Future<User?> getCurrentUser() async {
    final userId = _prefs?.getString(PrefKeys.currentUserId);
    if (userId != null) {
      return getUser(userId);
    }
    return null;
  }
  Future<bool> spendCoins(String userId, int amount) async {
    try {
      // 免费模式：不扣币，始终成功（彻底解决「不够花」）
      if (!isCoinEconomyEnabled()) return true;
      final need = amount < 0 ? 0 : amount;
      if (need == 0) return true;
      final user = await getUser(userId);
      if (user == null) return false;
      if (user.coins < need) return false;
      final updatedUser = user.copyWith(
        coins: user.coins - need,
        totalCoinsSpent: user.totalCoinsSpent + need,
      );
      await saveUser(updatedUser);
      return true;
    } catch (e) {
      debugPrint('spendCoins 失败: $e');
      return false;
    }
  }
  Future<void> addCoins(String userId, int amount) async {
    try {
      if (amount == 0) return;
      final user = await getUser(userId);
      if (user == null) return;
      final delta = amount;
      final updatedUser = user.copyWith(
        coins: (user.coins + delta).clamp(0, 999999999),
        totalCoinsEarned:
            delta > 0 ? user.totalCoinsEarned + delta : user.totalCoinsEarned,
        totalCoinsSpent:
            delta < 0 ? user.totalCoinsSpent + (-delta) : user.totalCoinsSpent,
      );
      await saveUser(updatedUser);
    } catch (e) {
      debugPrint('addCoins 失败: $e');
    }
  }
  /// true=正常扣费；false=免费模式（spend 不减余额）
  bool isCoinEconomyEnabled() {
    return _prefs?.getBool(PrefKeys.coinEconomyEnabled) ?? true;
  }
  Future<void> setCoinEconomyEnabled(bool enabled) async {
    await _prefs?.setBool(PrefKeys.coinEconomyEnabled, enabled);
  }
  int getCoinMessageCost() {
    final v = _prefs?.getInt(PrefKeys.coinMessageCost);
    return (v ?? CoinRules.messageCost)
        .clamp(CoinRules.minCustomCost, CoinRules.maxCustomCost);
  }
  Future<void> setCoinMessageCost(int value) async {
    await _prefs?.setInt(
      PrefKeys.coinMessageCost,
      value.clamp(CoinRules.minCustomCost, CoinRules.maxCustomCost),
    );
  }
  int getCoinMomentCost() {
    final v = _prefs?.getInt(PrefKeys.coinMomentCost);
    return (v ?? CoinRules.momentInteractionCost)
        .clamp(CoinRules.minCustomCost, CoinRules.maxCustomCost);
  }
  Future<void> setCoinMomentCost(int value) async {
    await _prefs?.setInt(
      PrefKeys.coinMomentCost,
      value.clamp(CoinRules.minCustomCost, CoinRules.maxCustomCost),
    );
  }
  int getCoinLoginBonus() {
    final v = _prefs?.getInt(PrefKeys.coinLoginBonus);
    return (v ?? CoinRules.loginBonus)
        .clamp(CoinRules.minCustomReward, CoinRules.maxCustomReward);
  }
  Future<void> setCoinLoginBonus(int value) async {
    await _prefs?.setInt(
      PrefKeys.coinLoginBonus,
      value.clamp(CoinRules.minCustomReward, CoinRules.maxCustomReward),
    );
  }
  int getCoinCheckInReward() {
    final v = _prefs?.getInt(PrefKeys.coinCheckInReward);
    return (v ?? CoinRules.dailyCheckInReward)
        .clamp(CoinRules.minCustomReward, CoinRules.maxCustomReward);
  }
  Future<void> setCoinCheckInReward(int value) async {
    await _prefs?.setInt(
      PrefKeys.coinCheckInReward,
      value.clamp(CoinRules.minCustomReward, CoinRules.maxCustomReward),
    );
  }
  /// 恢复默认消耗与奖励数值（不改免费开关）
  Future<void> resetCoinEconomyToDefaults() async {
    await _prefs?.remove(PrefKeys.coinMessageCost);
    await _prefs?.remove(PrefKeys.coinMomentCost);
    await _prefs?.remove(PrefKeys.coinLoginBonus);
    await _prefs?.remove(PrefKeys.coinCheckInReward);
  }
  Future<AIWallet?> getAIWallet(String characterId) async {
    try {
      if (_isWeb) {
        final data = _prefs?.getString('ai_wallet_$characterId');
        if (data == null) return null;
        return AIWallet.fromMap(jsonDecode(data));
      }
      final db = await _ensureDb();
      final maps = await db.query(
        'ai_wallets',
        where: 'characterId = ?',
        whereArgs: [characterId],
      );
      if (maps.isEmpty) return null;
      return AIWallet.fromMap(maps.first);
    } catch (e) {
      debugPrint('AI: $e');
      return null;
    }
  }
  Future<AIWallet> getOrCreateAIWallet(String characterId) async {
    final existing = await getAIWallet(characterId);
    if (existing != null) return existing;
    final wallet = AIWallet(characterId: characterId);
    await saveAIWallet(wallet);
    return wallet;
  }
  Future<void> saveAIWallet(AIWallet wallet) async {
    try {
      if (_isWeb) {
        await _prefs?.setString(
            'ai_wallet_${wallet.characterId}', jsonEncode(wallet.toMap()));
        return;
      }
      final db = await _ensureDb();
      await db.insert(
        'ai_wallets',
        wallet.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      debugPrint('AI: $e');
    }
  }
  Future<bool> addAICoins(String characterId, int amount) async {
    try {
      final wallet = await getOrCreateAIWallet(characterId);
      final updated = wallet.copyWith(
        balance: wallet.balance + amount,
        totalEarned: wallet.totalEarned + amount,
      );
      await saveAIWallet(updated);
      return true;
    } catch (e) {
      debugPrint('AI: $e');
      return false;
    }
  }
  Future<bool> deductAICoins(String characterId, int amount) async {
    try {
      final wallet = await getOrCreateAIWallet(characterId);
      if (wallet.balance < amount) return false;
      final updated = wallet.copyWith(
        balance: wallet.balance - amount,
        totalSpent: wallet.totalSpent + amount,
        dailySpent: wallet.dailySpent + amount,
        dailySpentDate: DateTime.now().toIso8601String().substring(0, 10),
      );
      await saveAIWallet(updated);
      return true;
    } catch (e) {
      debugPrint('AI: $e');
      return false;
    }
  }
  Future<void> updateAISpendingPersonality(
      String characterId, int personality) async {
    try {
      final wallet = await getOrCreateAIWallet(characterId);
      final updated = wallet.copyWith(
        spendingPersonality: personality.clamp(
          CoinRules.aiMinSpendingPersonality,
          CoinRules.aiMaxSpendingPersonality,
        ),
      );
      await saveAIWallet(updated);
    } catch (e) {
      debugPrint('AI: $e');
    }
  }
  Future<void> resetAIDailySpent(String characterId) async {
    try {
      final wallet = await getOrCreateAIWallet(characterId);
      final today = DateTime.now().toIso8601String().substring(0, 10);
      if (wallet.dailySpentDate != today) {
        final updated = wallet.copyWith(
          dailySpent: 0,
          dailySpentDate: today,
        );
        await saveAIWallet(updated);
      }
    } catch (e) {
      debugPrint('AI: $e');
    }
  }
  Future<List<AIWallet>> getAllAIWallets() async {
    try {
      if (_isWeb) {
        final keys = _prefs
                ?.getKeys()
                .where((k) => k.startsWith('ai_wallet_'))
                .toList() ??
            [];
        final wallets = <AIWallet>[];
        for (final key in keys) {
          final data = _prefs?.getString(key);
          if (data != null) {
            wallets.add(AIWallet.fromMap(jsonDecode(data)));
          }
        }
        return wallets;
      }
      final db = await _ensureDb();
      final maps = await db.query('ai_wallets');
      return maps.map((m) => AIWallet.fromMap(m)).toList();
    } catch (e) {
      debugPrint('I: $e');
      return [];
    }
  }
  Future<void> updateMessageMetadata(
      String messageId, Map<String, dynamic> metadata) async {
    try {
      if (_isWeb) {
        return;
      }
      final db = await _ensureDb();
      await db.update(
        'chat_messages',
        {'metadata': jsonEncode(metadata)},
        where: 'id = ?',
        whereArgs: [messageId],
      );
    } catch (e) {
      debugPrint(' $e');
    }
  }
  String? getLastCheckInDate() {
    return _prefs?.getString(PrefKeys.lastCheckInDate);
  }
  Future<void> setLastCheckInDate(String date) async {
    await _prefs?.setString(PrefKeys.lastCheckInDate, date);
  }
  String? getLastLoginBonusDate() {
    return _prefs?.getString(PrefKeys.lastLoginBonusDate);
  }
  Future<void> setLastLoginBonusDate(String date) async {
    await _prefs?.setString(PrefKeys.lastLoginBonusDate, date);
  }
  /// 每日首次登录奖励（与签到独立，同一天可叠发）。
  /// 返回实际发放金额；已领过或失败返回 0。
  Future<int> claimDailyLoginBonus(String userId, {DateTime? now}) async {
    try {
      final today = _todayDateKey(now);
      if (getLastLoginBonusDate() == today) return 0;
      final amount = getCoinLoginBonus();
      if (amount <= 0) {
        await setLastLoginBonusDate(today);
        return 0;
      }
      await addCoins(userId, amount);
      await setLastLoginBonusDate(today);
      debugPrint('[Coins] 每日登录奖励 +$amount → $userId ($today)');
      return amount;
    } catch (e) {
      debugPrint('claimDailyLoginBonus 失败: $e');
      return 0;
    }
  }
  Future<void> saveAILetter(AILetter letter) async {
    if (_isWeb) {
      await _prefs?.setString(
          'ai_letter_${letter.id}', jsonEncode(letter.toMap()));
      final ids = _prefs?.getStringList('ai_letter_ids_${letter.userId}') ?? [];
      if (!ids.contains(letter.id)) {
        ids.add(letter.id);
        await _prefs?.setStringList('ai_letter_ids_${letter.userId}', ids);
      }
      return;
    }
    final db = await _ensureDb();
    await db.insert(
      'ai_letters',
      letter.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
  Future<List<AILetter>> getAILetters({
    required String userId,
    int limit = 50,
    int offset = 0,
  }) async {
    if (_isWeb) {
      final ids = _prefs?.getStringList('ai_letter_ids_$userId') ?? [];
      final letters = ids
          .map((id) => _prefs?.getString('ai_letter_$id'))
          .whereType<String>()
          .map((raw) => AILetter.fromMap(jsonDecode(raw)))
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return letters.skip(offset).take(limit).toList();
    }
    final db = await _ensureDb();
    final maps = await db.query(
      'ai_letters',
      where: 'userId = ?',
      whereArgs: [userId],
      orderBy: 'createdAt DESC',
      limit: limit,
      offset: offset,
    );
    return maps.map((m) => AILetter.fromMap(m)).toList();
  }
  Future<AILetter?> getAILetter(String id) async {
    if (_isWeb) {
      final raw = _prefs?.getString('ai_letter_$id');
      return raw == null ? null : AILetter.fromMap(jsonDecode(raw));
    }
    final db = await _ensureDb();
    final maps = await db.query(
      'ai_letters',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return maps.isEmpty ? null : AILetter.fromMap(maps.first);
  }

  static const String _databaseName = DbDefaults.dbName;
  static const int _databaseVersion = DbDefaults.dbVersion;
  static const int _normalMomentSource = 0;
  static const int _xMomentSource = 1;
  /// 检测文本是否为 GBK mojibake
  static bool _isMojibakeContent(String text) {
    // GBK mojibake 特征字符
    if (RegExp(r'[锛堝垰鎵嶈蛋绁炰簡銆鍐璇鐢浣鏈冨勫]').hasMatch(text)) {
      return true;
    }
    // 常见 GBK mojibake 连续模式
    if (RegExp(r'鐢ㄦ埛|浣犲|鍥炲|鍥剧墖').hasMatch(text)) {
      return true;
    }
    return false;
  }
  static const expectedColumns = <String, Map<String, String>>{
    'users': {
      'nickname': 'TEXT NOT NULL DEFAULT ""',
      'avatarUrl': 'TEXT',
      'createdAt': 'TEXT NOT NULL DEFAULT ""',
      'lastLoginAt': 'TEXT',
      'signature': 'TEXT',
      'gender': 'TEXT',
      'birthday': 'TEXT',
      'location': 'TEXT',
      'bio': 'TEXT',
      'status': 'TEXT',
      'backgroundImage': 'TEXT',
      'coins': 'INTEGER NOT NULL DEFAULT 100',
      'totalCoinsEarned': 'INTEGER NOT NULL DEFAULT 100',
      'totalCoinsSpent': 'INTEGER NOT NULL DEFAULT 0',
      'appIconPath': 'TEXT',
      'lockScreenPassword': 'TEXT',
      'lockScreenDuration': 'INTEGER NOT NULL DEFAULT 0',
      'lockScreenTextColor': 'TEXT',
      'lockScreenFontSize': 'REAL NOT NULL DEFAULT 1.0',
      'currentWeather': 'TEXT',
      'lastWeatherUpdate': 'TEXT',
      // 兼容旧库：toMap 会写 sync_seq，缺列会直接炸
      'sync_seq': 'INTEGER DEFAULT 0',
    },
    'ai_characters': {
      'name': 'TEXT NOT NULL DEFAULT ""',
      'avatarUrl': 'TEXT',
      'personality': 'TEXT NOT NULL DEFAULT ""',
      'coreDesire': 'TEXT NOT NULL DEFAULT ""',
      'moralBoundary': 'TEXT NOT NULL DEFAULT ""',
      'backgroundStory': 'TEXT',
      'createdAt': 'TEXT NOT NULL DEFAULT ""',
      'updatedAt': 'TEXT',
      'worldSetting': 'TEXT',
      'languageStyle': 'TEXT',
      'tabooTopics': 'TEXT',
      'userNickname': 'TEXT',
      'userAlias': 'TEXT',
      'userPersona': 'TEXT',
      'catchphrases': 'TEXT',
      'openingLine': 'TEXT',
      'dialogueExamples': 'TEXT',
      'interactionConfig': 'TEXT',
      'gender': 'TEXT',
      'isHidden': 'INTEGER NOT NULL DEFAULT 0',
      'isOnline': 'INTEGER NOT NULL DEFAULT 1',
      'currentStatus': 'TEXT',
      'lastOnlineAt': 'TEXT',
      'avatarGif': 'TEXT',
      'autoReplyStickers': 'INTEGER NOT NULL DEFAULT 0',
      'translatedSettings': 'TEXT',
      'immutableAnchor': 'TEXT',
      'deviationRadius': 'REAL NOT NULL DEFAULT 0.4',
      'talkativeness': 'REAL NOT NULL DEFAULT 0.5',
      'colorHex': 'TEXT',
      'evolutionEnabled': 'INTEGER NOT NULL DEFAULT 1',
      'qualitativeEvolutionEnabled': 'INTEGER NOT NULL DEFAULT 0',
      'currentAnchor': 'TEXT',
      'referenceImg': 'TEXT',
      'fixedSeed': 'INTEGER NOT NULL DEFAULT -1',
      'characterTag': 'TEXT',
      'styleLock': 'TEXT NOT NULL DEFAULT "anime"',
      'age': 'INTEGER',
      'structuredTraits': 'TEXT',
      'storyState': 'TEXT',
      'sync_seq': 'INTEGER DEFAULT 0',
    },
    'ai_configs': {
      'providerName': 'TEXT NOT NULL DEFAULT ""',
      'baseUrl': 'TEXT NOT NULL DEFAULT ""',
      'apiKey': 'TEXT NOT NULL DEFAULT ""',
      'extraApiKeys': 'TEXT DEFAULT ""',
      'modelName': 'TEXT NOT NULL DEFAULT ""',
      'temperature': 'REAL NOT NULL DEFAULT 0.7',
      'maxTokens': 'INTEGER NOT NULL DEFAULT 2048',
      'isActive': 'INTEGER NOT NULL DEFAULT 1',
      'isThinkingModel': 'INTEGER DEFAULT 1',
      'isMultimodal': 'INTEGER DEFAULT 0',
      'createdAt': 'TEXT NOT NULL DEFAULT ""',
      'updatedAt': 'TEXT',
      'sync_seq': 'INTEGER DEFAULT 0',
    },
    'ai_letters': {
      'userId': 'TEXT NOT NULL DEFAULT ""',
      'characterId': 'TEXT NOT NULL DEFAULT ""',
      'characterName': 'TEXT NOT NULL DEFAULT ""',
      'characterAvatar': 'TEXT',
      'recipientName': 'TEXT NOT NULL DEFAULT ""',
      'title': 'TEXT NOT NULL DEFAULT ""',
      'content': 'TEXT NOT NULL DEFAULT ""',
      'isRead': 'INTEGER NOT NULL DEFAULT 0',
      'isFromUser': 'INTEGER NOT NULL DEFAULT 0',
      'needsReply': 'INTEGER NOT NULL DEFAULT 0',
      'sourceChatId': 'TEXT',
      'createdAt': 'TEXT NOT NULL DEFAULT ""',
      'readAt': 'TEXT',
    },
    'chat_sessions': {
      'userId': 'TEXT NOT NULL DEFAULT ""',
      'aiCharacterId': 'TEXT NOT NULL DEFAULT ""',
      'aiCharacterName': 'TEXT NOT NULL DEFAULT ""',
      'aiCharacterAvatar': 'TEXT',
      'lastMessage': 'TEXT',
      'lastMessageTime': 'TEXT',
      'unreadCount': 'INTEGER NOT NULL DEFAULT 0',
      'intimacyLevel': 'INTEGER NOT NULL DEFAULT 0',
      'dailyIntimacyCount': 'INTEGER NOT NULL DEFAULT 0',
      'lastIntimacyDate': 'TEXT',
      'createdAt': 'TEXT NOT NULL DEFAULT ""',
      'updatedAt': 'TEXT',
      'isMuted': 'INTEGER NOT NULL DEFAULT 0',
      'isPinned': 'INTEGER NOT NULL DEFAULT 0',
      'backgroundImage': 'TEXT',
      'isHidden': 'INTEGER NOT NULL DEFAULT 0',
      'aiIsOnline': 'INTEGER NOT NULL DEFAULT 1',
      'aiCurrentStatus': 'TEXT',
      'lastOnlineAt': 'TEXT',
      'isBlocked': 'INTEGER NOT NULL DEFAULT 0',
      'blockedBy': 'INTEGER NOT NULL DEFAULT 0',
      'blockedAt': 'TEXT',
      'blockReason': 'TEXT',
      'sessionType': 'TEXT DEFAULT "private"',
      'intimacyMode': 'TEXT DEFAULT "quick"',
      'streakDays': 'INTEGER NOT NULL DEFAULT 0',
      'isInFriction': 'INTEGER NOT NULL DEFAULT 0',
      'frictionDaysLeft': 'INTEGER NOT NULL DEFAULT 0',
      // -1=跟随全局，0=本会话关闭，1=本会话开启
      // ALTER 兼容：不要用 NOT NULL，避免旧库补列失败
      'novelMode': 'INTEGER DEFAULT -1',
      'sync_seq': 'INTEGER DEFAULT 0',
    },
    'chat_messages': {
      'chatId': 'TEXT NOT NULL DEFAULT ""',
      'senderId': 'TEXT NOT NULL DEFAULT ""',
      'senderName': 'TEXT',
      'content': 'TEXT NOT NULL DEFAULT ""',
      'isUser': 'INTEGER NOT NULL DEFAULT 0',
      'isSystem': 'INTEGER NOT NULL DEFAULT 0',
      'isHidden': 'INTEGER NOT NULL DEFAULT 0',
      'isGhost': 'INTEGER NOT NULL DEFAULT 0',
      'type': 'TEXT NOT NULL DEFAULT "text"',
      'status': 'TEXT NOT NULL DEFAULT "sent"',
      'createdAt': 'TEXT NOT NULL DEFAULT ""',
      'readAt': 'TEXT',
      'reasoning': 'TEXT',
      'metadata': 'TEXT',
      'pokeSuffix': 'TEXT',
      'stickerId': 'TEXT',
      'stickerPath': 'TEXT',
      'isBookmark': 'INTEGER DEFAULT 0',
      'sync_seq': 'INTEGER DEFAULT 0',
    },
    'intimacy_events': {
      'chatId': 'TEXT NOT NULL DEFAULT ""',
      'userId': 'TEXT NOT NULL DEFAULT ""',
      'characterId': 'TEXT NOT NULL DEFAULT ""',
      'oldLevel': 'INTEGER NOT NULL DEFAULT 0',
      'newLevel': 'INTEGER NOT NULL DEFAULT 0',
      'delta': 'INTEGER NOT NULL DEFAULT 0',
      'dailyCount': 'INTEGER NOT NULL DEFAULT 0',
      'source': 'TEXT NOT NULL DEFAULT ""',
      'messagePreview': 'TEXT',
      'sentimentLabel': 'TEXT',
      'sentimentType': 'TEXT',
      'createdAt': 'TEXT NOT NULL DEFAULT ""',
      'sync_seq': 'INTEGER DEFAULT 0',
    },
    'character_commitments': {
      'characterId': 'TEXT NOT NULL DEFAULT ""',
      'userId': 'TEXT NOT NULL DEFAULT ""',
      'chatId': 'TEXT NOT NULL DEFAULT ""',
      'content': 'TEXT NOT NULL DEFAULT ""',
      'dueAt': 'TEXT NOT NULL DEFAULT ""',
      'status': 'TEXT NOT NULL DEFAULT "active"',
      'createdAt': 'TEXT NOT NULL DEFAULT ""',
      'updatedAt': 'TEXT NOT NULL DEFAULT ""',
    },
    'relationship_contexts': {
      'trust': 'REAL NOT NULL DEFAULT 0.5',
      'boundary': 'TEXT',
      'unresolvedConflict': 'TEXT',
      'recentImportantEvent': 'TEXT',
      'updatedAt': 'TEXT NOT NULL DEFAULT ""',
    },
    'memories': {
      'characterId': 'TEXT NOT NULL DEFAULT ""',
      'userId': 'TEXT NOT NULL DEFAULT ""',
      'type': 'INTEGER NOT NULL DEFAULT 0',
      'content': 'TEXT NOT NULL DEFAULT ""',
      'importance': 'INTEGER NOT NULL DEFAULT 1',
      'keywords': 'TEXT',
      'createdAt': 'TEXT NOT NULL DEFAULT ""',
      'lastAccessedAt': 'TEXT',
      'accessCount': 'INTEGER NOT NULL DEFAULT 0',
      'sync_seq': 'INTEGER DEFAULT 0',
      'weight': 'REAL DEFAULT 1.0',
      'pinned': 'INTEGER DEFAULT 0',
      'lastRecalledAt': 'TEXT',
      'summary': 'TEXT',
      'updatedAt': 'TEXT',
    },
    'moments': {
      'userId': 'TEXT NOT NULL DEFAULT ""',
      'userName': 'TEXT NOT NULL DEFAULT ""',
      'userAvatar': 'TEXT',
      'content': 'TEXT NOT NULL DEFAULT ""',
      'images': 'TEXT',
      'type': 'INTEGER NOT NULL DEFAULT 0',
      'likes': 'TEXT',
      'comments': 'TEXT',
      'createdAt': 'TEXT NOT NULL DEFAULT ""',
      'updatedAt': 'TEXT',
      'isFromAI': 'INTEGER NOT NULL DEFAULT 0',
      'visibility': 'INTEGER NOT NULL DEFAULT 0',
      'source': 'INTEGER DEFAULT 0',
      'replyToCommentId': 'TEXT',
      'replyToContent': 'TEXT',
      'aiLiked': 'INTEGER DEFAULT 0',
      'parentKey': 'TEXT',
      'retweetKey': 'TEXT',
      'quoteKey': 'TEXT',
      'retweetCount': 'INTEGER DEFAULT 0',
      'replyCount': 'INTEGER DEFAULT 0',
      'bookmarkCount': 'INTEGER DEFAULT 0',
      'viewCount': 'INTEGER DEFAULT 0',
      'tags': 'TEXT',
      'userHandle': 'TEXT',
      'userGender': 'TEXT',
      'userVerified': 'INTEGER DEFAULT 0',
      'customLikeCount': 'INTEGER DEFAULT 0',
      'blockedUserIds': 'TEXT',
      'sync_seq': 'INTEGER DEFAULT 0',
    },
    'sticker_packs': {
      'name': 'TEXT NOT NULL DEFAULT ""',
      'coverImagePath': 'TEXT',
      'stickers': 'TEXT',
      'createdAt': 'TEXT NOT NULL DEFAULT ""',
      'updatedAt': 'TEXT',
      'isDefault': 'INTEGER NOT NULL DEFAULT 0',
      'sync_seq': 'INTEGER DEFAULT 0',
    },
    'virtual_phones': {
      'id': 'TEXT PRIMARY KEY',
      'characterId': 'TEXT NOT NULL DEFAULT ""',
      'ownerName': 'TEXT NOT NULL DEFAULT ""',
      'wallpaperColor': 'INTEGER NOT NULL DEFAULT 4283871606',
      'status': "TEXT NOT NULL DEFAULT 'empty'",
      'generatedAt': 'TEXT',
      'lastAdvanceMsgCount': 'INTEGER NOT NULL DEFAULT 0',
      'lastAdvanceAt': 'TEXT',
      'createdAt': 'TEXT NOT NULL DEFAULT ""',
      'updatedAt': 'TEXT',
      'sync_seq': 'INTEGER NOT NULL DEFAULT 0',
    },
    'vp_contacts': {
      'id': 'TEXT PRIMARY KEY',
      'phoneId': 'TEXT NOT NULL DEFAULT ""',
      'characterId': 'TEXT NOT NULL DEFAULT ""',
      'name': 'TEXT NOT NULL DEFAULT ""',
      'relation': 'TEXT NOT NULL DEFAULT ""',
      'note': 'TEXT NOT NULL DEFAULT ""',
      'accentColor': 'INTEGER NOT NULL DEFAULT 4278223103',
      'isUser': 'INTEGER NOT NULL DEFAULT 0',
      'pinned': 'INTEGER NOT NULL DEFAULT 0',
      'orderIndex': 'INTEGER NOT NULL DEFAULT 0',
    },
    'vp_chats': {
      'id': 'TEXT PRIMARY KEY',
      'phoneId': 'TEXT NOT NULL DEFAULT ""',
      'characterId': 'TEXT NOT NULL DEFAULT ""',
      'contactId': 'TEXT NOT NULL DEFAULT ""',
      'title': 'TEXT NOT NULL DEFAULT ""',
      'lastPreview': 'TEXT NOT NULL DEFAULT ""',
      'orderIndex': 'INTEGER NOT NULL DEFAULT 0',
    },
    'vp_chat_messages': {
      'id': 'TEXT PRIMARY KEY',
      'chatId': 'TEXT NOT NULL DEFAULT ""',
      'fromOwner': 'INTEGER NOT NULL DEFAULT 0',
      'content': 'TEXT NOT NULL DEFAULT ""',
      'timeLabel': 'TEXT NOT NULL DEFAULT ""',
      'orderIndex': 'INTEGER NOT NULL DEFAULT 0',
    },
    'vp_notes': {
      'id': 'TEXT PRIMARY KEY',
      'phoneId': 'TEXT NOT NULL DEFAULT ""',
      'characterId': 'TEXT NOT NULL DEFAULT ""',
      'title': 'TEXT NOT NULL DEFAULT ""',
      'body': 'TEXT NOT NULL DEFAULT ""',
      'dateLabel': 'TEXT NOT NULL DEFAULT ""',
      'aboutUser': 'INTEGER NOT NULL DEFAULT 0',
      'orderIndex': 'INTEGER NOT NULL DEFAULT 0',
    },
    'vp_moments': {
      'id': 'TEXT PRIMARY KEY',
      'phoneId': 'TEXT NOT NULL DEFAULT ""',
      'characterId': 'TEXT NOT NULL DEFAULT ""',
      'content': 'TEXT NOT NULL DEFAULT ""',
      'timeLabel': 'TEXT NOT NULL DEFAULT ""',
      'likes': 'INTEGER NOT NULL DEFAULT 0',
      'comments': 'TEXT NOT NULL DEFAULT ""',
      'orderIndex': 'INTEGER NOT NULL DEFAULT 0',
    },
    'ai_wallets': {
      'characterId': 'TEXT PRIMARY KEY',
      'balance': 'INTEGER NOT NULL DEFAULT 50',
      'totalEarned': 'INTEGER NOT NULL DEFAULT 50',
      'totalSpent': 'INTEGER NOT NULL DEFAULT 0',
      'dailySpent': 'INTEGER NOT NULL DEFAULT 0',
      'dailySpentDate': 'TEXT',
      'spendingPersonality': 'INTEGER NOT NULL DEFAULT 5',
    },
    'shop_items': {
      'id': 'TEXT PRIMARY KEY',
      'name': 'TEXT NOT NULL DEFAULT ""',
      'category': 'TEXT NOT NULL DEFAULT ""',
      'price': 'INTEGER NOT NULL DEFAULT 0',
      'emoji': 'TEXT NOT NULL DEFAULT ""',
      'description': 'TEXT DEFAULT ""',
      'tags': 'TEXT DEFAULT ""',
      'isActive': 'INTEGER NOT NULL DEFAULT 1',
      'isCustom': 'INTEGER NOT NULL DEFAULT 0',
      'createdAt': 'TEXT',
    },
    'inner_thoughts': {
      'id': 'TEXT PRIMARY KEY',
      'characterId': 'TEXT NOT NULL DEFAULT ""',
      'userId': 'TEXT NOT NULL DEFAULT ""',
      'content': 'TEXT NOT NULL DEFAULT ""',
      'type': 'INTEGER NOT NULL DEFAULT 0',
      'emotionValence': 'REAL NOT NULL DEFAULT 0',
      'emotionArousal': 'REAL NOT NULL DEFAULT 0',
      'isRead': 'INTEGER NOT NULL DEFAULT 0',
      'createdAt': 'TEXT NOT NULL DEFAULT ""',
    },
    'forum_posts': {
      'id': 'TEXT PRIMARY KEY',
      'authorId': 'TEXT NOT NULL DEFAULT ""',
      'authorName': 'TEXT NOT NULL DEFAULT ""',
      'authorAvatar': 'TEXT',
      'isFromAI': 'INTEGER NOT NULL DEFAULT 0',
      'characterId': 'TEXT',
      'title': 'TEXT NOT NULL DEFAULT ""',
      'content': 'TEXT NOT NULL DEFAULT ""',
      'images': 'TEXT',
      'tags': 'TEXT',
      'likes': 'TEXT DEFAULT "[]"',
      'isAnonymous': 'INTEGER NOT NULL DEFAULT 0',
      'visibility': 'INTEGER NOT NULL DEFAULT 0',
      'createdAt': 'TEXT NOT NULL DEFAULT ""',
      'updatedAt': 'TEXT',
    },
    'forum_comments': {
      'id': 'TEXT PRIMARY KEY',
      'postId': 'TEXT NOT NULL DEFAULT ""',
      'authorId': 'TEXT NOT NULL DEFAULT ""',
      'authorName': 'TEXT NOT NULL DEFAULT ""',
      'authorAvatar': 'TEXT',
      'isFromAI': 'INTEGER NOT NULL DEFAULT 0',
      'characterId': 'TEXT',
      'content': 'TEXT NOT NULL DEFAULT ""',
      'replyToId': 'TEXT',
      'replyToName': 'TEXT',
      'isAnonymous': 'INTEGER NOT NULL DEFAULT 0',
      'createdAt': 'TEXT NOT NULL DEFAULT ""',
    },
    'shared_album_entries': {
      'id': 'TEXT PRIMARY KEY',
      'characterId': 'TEXT NOT NULL DEFAULT ""',
      'userId': 'TEXT NOT NULL DEFAULT ""',
      'memoryId': 'TEXT',
      'title': 'TEXT NOT NULL DEFAULT ""',
      'description': 'TEXT',
      'eventDate': 'TEXT',
      'imagePath': 'TEXT',
      'importance': 'INTEGER NOT NULL DEFAULT 1',
      'createdAt': 'TEXT NOT NULL DEFAULT ""',
    },
    'virtual_locations': {
      'id': 'TEXT PRIMARY KEY',
      'characterId': 'TEXT NOT NULL DEFAULT ""',
      'userId': 'TEXT NOT NULL DEFAULT ""',
      'userLat': 'REAL NOT NULL DEFAULT 0',
      'userLng': 'REAL NOT NULL DEFAULT 0',
      'aiLat': 'REAL NOT NULL DEFAULT 0',
      'aiLng': 'REAL NOT NULL DEFAULT 0',
      'sceneDescription': 'TEXT',
      'distance': 'REAL NOT NULL DEFAULT 0',
      'createdAt': 'TEXT NOT NULL DEFAULT ""',
    },
    'growth_events': {
      'id': 'TEXT PRIMARY KEY',
      'characterId': 'TEXT NOT NULL DEFAULT ""',
      'userId': 'TEXT NOT NULL DEFAULT ""',
      'triggerType': 'TEXT NOT NULL DEFAULT "micro"',
      'evolutionMode': 'TEXT NOT NULL DEFAULT "micro"',
      'triggerData': 'TEXT NOT NULL DEFAULT "{}"',
      'deltas': 'TEXT NOT NULL DEFAULT "{}"',
      'impactScore': 'REAL NOT NULL DEFAULT 0',
      'reason': 'TEXT',
      'createdAt': 'TEXT NOT NULL DEFAULT ""',
    },
    'persona_snapshots': {
      'id': 'TEXT PRIMARY KEY',
      'characterId': 'TEXT NOT NULL DEFAULT ""',
      'snapshotType': 'TEXT NOT NULL DEFAULT "initial"',
      'traitsData': 'TEXT NOT NULL DEFAULT "{}"',
      'surfaceData': 'TEXT NOT NULL DEFAULT "{}"',
      'createdAt': 'TEXT NOT NULL DEFAULT ""',
      'label': 'TEXT',
    },
    'shop_orders': {
      'id': 'TEXT PRIMARY KEY',
      'buyerType': 'TEXT NOT NULL DEFAULT "user"',
      'buyerId': 'TEXT NOT NULL DEFAULT ""',
      'receiverType': 'TEXT NOT NULL DEFAULT "ai"',
      'receiverId': 'TEXT NOT NULL DEFAULT ""',
      'chatSessionId': 'TEXT NOT NULL DEFAULT ""',
      'itemId': 'TEXT NOT NULL DEFAULT ""',
      'itemName': 'TEXT NOT NULL DEFAULT ""',
      'itemEmoji': 'TEXT NOT NULL DEFAULT ""',
      'price': 'INTEGER NOT NULL DEFAULT 0',
      'status': 'TEXT DEFAULT "pending"',
      'message': 'TEXT',
      'createdAt': 'TEXT NOT NULL DEFAULT ""',
      'preparingAt': 'TEXT',
      'shippingAt': 'TEXT',
      'deliveredAt': 'TEXT',
      'aiReaction': 'TEXT',
    },
    'bt_agent_actions': {
      'actionType': 'TEXT NOT NULL DEFAULT ""',
      'category': 'TEXT NOT NULL DEFAULT ""',
      'scope': 'TEXT NOT NULL DEFAULT ""',
      'targetType': 'TEXT NOT NULL DEFAULT ""',
      'targetId': 'TEXT NOT NULL DEFAULT ""',
      'reason': 'TEXT NOT NULL DEFAULT ""',
      'stateBefore': 'TEXT NOT NULL DEFAULT ""',
      'stateAfter': 'TEXT NOT NULL DEFAULT ""',
      'result': 'TEXT NOT NULL DEFAULT ""',
      'rejectionReason': 'TEXT NOT NULL DEFAULT ""',
      'characterId': 'TEXT NOT NULL DEFAULT ""',
      'sessionId': 'TEXT NOT NULL DEFAULT ""',
      'chatType': 'TEXT NOT NULL DEFAULT "single"',
      'createdAt': 'TEXT NOT NULL DEFAULT ""',
    },
    'social_memories': {
      'id': 'TEXT PRIMARY KEY',
      'characterId': 'TEXT NOT NULL DEFAULT ""',
      'targetCharacterId': 'TEXT NOT NULL DEFAULT ""',
      'interactionType': 'TEXT DEFAULT "chat"',
      'content': 'TEXT DEFAULT ""',
      'emotionTag': 'TEXT DEFAULT ""',
      'importance': 'TEXT DEFAULT "normal"',
      'keywords': 'TEXT DEFAULT "[]"',
      'timestamp': 'TEXT NOT NULL DEFAULT ""',
      'weight': 'REAL DEFAULT 1.0',
      'pinned': 'INTEGER DEFAULT 0',
      'lastRecalledAt': 'TEXT',
    },
    'moment_bookmarks': {
      'id': 'TEXT PRIMARY KEY',
      'momentId': 'TEXT NOT NULL DEFAULT ""',
      'userId': 'TEXT NOT NULL DEFAULT ""',
      'createdAt': 'TEXT NOT NULL DEFAULT ""',
    },
    'moment_notifications': {
      'id': 'TEXT PRIMARY KEY',
      'momentId': 'TEXT NOT NULL DEFAULT ""',
      'actorId': 'TEXT NOT NULL DEFAULT ""',
      'actorName': 'TEXT NOT NULL DEFAULT ""',
      'actorAvatar': 'TEXT',
      'type': 'INTEGER NOT NULL DEFAULT 0',
      'content': 'TEXT',
      'createdAt': 'TEXT NOT NULL DEFAULT ""',
      'isRead': 'INTEGER NOT NULL DEFAULT 0',
      'isFromAI': 'INTEGER NOT NULL DEFAULT 0',
    },
    'trending_tags': {
      'tag': 'TEXT PRIMARY KEY',
      'count': 'INTEGER NOT NULL DEFAULT 1',
      'lastUsedAt': 'TEXT NOT NULL DEFAULT ""',
    },
    'pure_ai_sessions': {
      'id': 'TEXT PRIMARY KEY',
      'userId': 'TEXT NOT NULL DEFAULT ""',
      'title': 'TEXT NOT NULL DEFAULT "AI"',
      'lastMessage': 'TEXT',
      'lastMessageTime': 'TEXT',
      'isPinned': 'INTEGER NOT NULL DEFAULT 0',
      'createdAt': 'TEXT NOT NULL DEFAULT ""',
      'updatedAt': 'TEXT',
    },
    'pure_ai_messages': {
      'id': 'TEXT PRIMARY KEY',
      'sessionId': 'TEXT NOT NULL DEFAULT ""',
      'senderId': 'TEXT NOT NULL DEFAULT ""',
      'senderName': 'TEXT',
      'content': 'TEXT NOT NULL DEFAULT ""',
      'type': 'INTEGER NOT NULL DEFAULT 0',
      'status': 'INTEGER NOT NULL DEFAULT 1',
      'createdAt': 'TEXT NOT NULL DEFAULT ""',
      'metadata': 'TEXT',
    },
    'novels': {
      'id': 'TEXT PRIMARY KEY',
      'userId': 'TEXT NOT NULL DEFAULT ""',
      'title': 'TEXT NOT NULL DEFAULT ""',
      'coverUrl': 'TEXT',
      'synopsis': 'TEXT NOT NULL DEFAULT ""',
      'worldSetting': 'TEXT NOT NULL DEFAULT ""',
      'characters': 'TEXT NOT NULL DEFAULT ""',
      'genre': 'INTEGER NOT NULL DEFAULT 7',
      'status': 'INTEGER NOT NULL DEFAULT 0',
      'totalWords': 'INTEGER NOT NULL DEFAULT 0',
      'chapterCount': 'INTEGER NOT NULL DEFAULT 0',
      'isArchived': 'INTEGER NOT NULL DEFAULT 0',
      'createdAt': 'TEXT NOT NULL DEFAULT ""',
      'updatedAt': 'TEXT NOT NULL DEFAULT ""',
      'lastChapterPreview': 'TEXT',
    },
    'novel_chapters': {
      'id': 'TEXT PRIMARY KEY',
      'novelId': 'TEXT NOT NULL DEFAULT ""',
      'sortOrder': 'INTEGER NOT NULL DEFAULT 0',
      'title': 'TEXT NOT NULL DEFAULT ""',
      'content': 'TEXT NOT NULL DEFAULT ""',
      'wordCount': 'INTEGER NOT NULL DEFAULT 0',
      'isAiGenerated': 'INTEGER NOT NULL DEFAULT 0',
      'createdAt': 'TEXT NOT NULL DEFAULT ""',
      'updatedAt': 'TEXT NOT NULL DEFAULT ""',
    },
    'group_chat_sessions': {
      'userId': 'TEXT NOT NULL DEFAULT ""',
      'name': 'TEXT NOT NULL DEFAULT ""',
      'avatarUrl': 'TEXT',
      'memberIds': 'TEXT NOT NULL DEFAULT "[]"',
      'aiCharacterIds': 'TEXT NOT NULL DEFAULT "[]"',
      'creatorId': 'TEXT NOT NULL DEFAULT ""',
      'lastMessage': 'TEXT',
      'lastMessageTime': 'TEXT',
      'unreadCount': 'INTEGER NOT NULL DEFAULT 0',
      'isMuted': 'INTEGER NOT NULL DEFAULT 0',
      'isPinned': 'INTEGER NOT NULL DEFAULT 0',
      'backgroundImage': 'TEXT',
      'notice': 'TEXT',
      'createdAt': 'TEXT NOT NULL DEFAULT ""',
      'updatedAt': 'TEXT',
      'sync_seq': 'INTEGER NOT NULL DEFAULT 0',
    },
    'group_chat_messages': {
      'groupId': 'TEXT NOT NULL DEFAULT ""',
      'senderId': 'TEXT NOT NULL DEFAULT ""',
      'senderName': 'TEXT',
      'content': 'TEXT NOT NULL DEFAULT ""',
      'isUser': 'INTEGER NOT NULL DEFAULT 0',
      'isSystem': 'INTEGER NOT NULL DEFAULT 0',
      'type': 'TEXT NOT NULL DEFAULT "text"',
      'createdAt': 'TEXT NOT NULL DEFAULT ""',
      'status': 'TEXT NOT NULL DEFAULT "sent"',
      'metadata': 'TEXT',
    },
    'group_chat_summaries': {
      'groupId': 'TEXT NOT NULL DEFAULT ""',
      'chatId': 'TEXT NOT NULL DEFAULT ""',
      'summary': 'TEXT NOT NULL DEFAULT ""',
      'messageCount': 'INTEGER NOT NULL DEFAULT 0',
      'updatedAt': 'TEXT NOT NULL DEFAULT ""',
    },
    'group_public_event_memories': {
      'id': 'TEXT PRIMARY KEY',
      'characterId': 'TEXT NOT NULL DEFAULT ""',
      'groupId': 'TEXT NOT NULL DEFAULT ""',
      'chatId': 'TEXT NOT NULL DEFAULT ""',
      'content': 'TEXT NOT NULL DEFAULT ""',
      'keywords': 'TEXT NOT NULL DEFAULT "[]"',
      'sourceMessageIds': 'TEXT NOT NULL DEFAULT "[]"',
      'speakerNames': 'TEXT NOT NULL DEFAULT "[]"',
      'metadata': 'TEXT',
      'sourceGroupName': 'TEXT',
      'importance': 'TEXT NOT NULL DEFAULT "normal"',
      'pinned': 'INTEGER NOT NULL DEFAULT 0',
      'weight': 'REAL NOT NULL DEFAULT 1.0',
      'createdAt': 'TEXT NOT NULL DEFAULT ""',
      'lastRecalledAt': 'TEXT',
    },
  };
  /// 修复 isUser 字段：根据 senderId 修正因迁移导致的默认值错误
  static Future<void> reconcileSchema(Database db,
      {SharedPreferences? prefs}) async {
    // user_version 可能已经升过但历史迁移中断，群聊表仍可能是旧脏结构。
    // 每次启动都做一次幂等自愈，避免创建群聊时才暴露 NOT NULL/缺表问题。
    await _ensureGroupChatSchema(db);
    bool needsIsUserRepair = false;
    for (final entry in expectedColumns.entries) {
      final table = entry.key;
      final expectedCols = entry.value;
      try {
        final existingRows = await db.rawQuery('PRAGMA table_info($table)');
        if (existingRows.isEmpty) {
          debugPrint(': $table ..');
          await createMissingTable(db, table);
          continue;
        }
        final existingCols =
            existingRows.map((r) => r['name'] as String).toSet();
        for (final colEntry in expectedCols.entries) {
          final colName = colEntry.key;
          final colDef = colEntry.value;
          if (!existingCols.contains(colName)) {
            debugPrint('[schema] add column: $table.$colName ($colDef)');
            try {
              await db
                  .execute('ALTER TABLE $table ADD COLUMN $colName $colDef');
              if (colName == 'isUser' && table == 'chat_messages') {
                needsIsUserRepair = true;
              }
            } catch (e) {
              // 单列失败不阻断同表其它列（如 novelMode）
              debugPrint('[schema] add column failed: $table.$colName $e');
            }
          }
        }
      } catch (e) {
        debugPrint('[schema] reconcile table failed: $table $e');
      }
    }
    // 商店表：不依赖 expectedColumns 循环结果，启动必校验
    try {
      await _ensureShopItemsSchema(db);
    } catch (e) {
      debugPrint('[schema] reconcile shop_items ensure failed: $e');
    }
    // 修复 isUser 字段：首次添加列时修复，或通过标记强制修复一次旧版本用户
    final alreadyRepaired = prefs?.getBool('isUserRepairV2_done') ?? false;
    if (needsIsUserRepair || !alreadyRepaired) {
      try {
        debugPrint(
            '[FIX] reconcileSchema: repairing isUser field for existing messages');
        await db.execute(
            "UPDATE chat_messages SET isUser = 1 WHERE senderId NOT LIKE 'ai_%' AND senderId != 'system' AND senderId != 'system_risk'");
        await prefs?.setBool('isUserRepairV2_done', true);
        debugPrint('[FIX] reconcileSchema: isUser repair done');
      } catch (e) {
        debugPrint('[FIX] reconcileSchema: isUser repair failed: $e');
      }
    }

    // 一次性孤儿数据清理：旧版本删除会话/角色时未连带清理，历史库里会残留
    // chatId 指向已删会话的 chat_messages、characterId 指向已删角色的 memories。
    // 这些死数据不会触发崩溃，但会长期占用空间；首次启动清理一次，之后不再扫描。
    final orphanCleanupDone = prefs?.getBool('orphanCleanupV1_done') ?? false;
    if (!orphanCleanupDone) {
      try {
        final orphanMessages = await db.rawDelete(
            'DELETE FROM chat_messages WHERE chatId NOT IN (SELECT id FROM chat_sessions)');
        final orphanMemories = await db.rawDelete(
            'DELETE FROM memories WHERE characterId NOT IN (SELECT id FROM ai_characters)');
        await prefs?.setBool('orphanCleanupV1_done', true);
        debugPrint(
            '[FIX] reconcileSchema: orphan cleanup removed $orphanMessages chat_messages, $orphanMemories memories');
      } catch (e) {
        debugPrint('[FIX] reconcileSchema: orphan cleanup failed: $e');
      }
    }
  }
  static Future<void> createMissingTable(Database db, String table) async {
    switch (table) {
      case 'virtual_phones':
      case 'vp_contacts':
      case 'vp_chats':
      case 'vp_chat_messages':
      case 'vp_notes':
      case 'vp_moments':
        await _createVirtualPhoneTables(db);
        break;
      case 'shop_items':
        await _ensureShopItemsSchema(db);
        break;
      case 'shop_orders':
        await db.execute(
            ''' CREATE TABLE IF NOT EXISTS shop_orders ( id TEXT PRIMARY KEY, buyerType TEXT NOT NULL DEFAULT 'user', buyerId TEXT NOT NULL DEFAULT '', receiverType TEXT NOT NULL DEFAULT 'ai', receiverId TEXT NOT NULL DEFAULT '', chatSessionId TEXT NOT NULL DEFAULT '', itemId TEXT NOT NULL DEFAULT '', itemName TEXT NOT NULL DEFAULT '', itemEmoji TEXT NOT NULL DEFAULT '', price INTEGER NOT NULL DEFAULT 0, status TEXT DEFAULT 'pending', message TEXT, createdAt TEXT NOT NULL DEFAULT '', preparingAt TEXT, shippingAt TEXT, deliveredAt TEXT, aiReaction TEXT, sync_seq INTEGER NOT NULL DEFAULT 0 ) ''');
        break;
      case 'inner_thoughts':
        await db.execute(
            ''' CREATE TABLE IF NOT EXISTS inner_thoughts ( id TEXT PRIMARY KEY, characterId TEXT NOT NULL DEFAULT '', userId TEXT NOT NULL DEFAULT '', content TEXT NOT NULL DEFAULT '', type INTEGER NOT NULL DEFAULT 0, emotionValence REAL NOT NULL DEFAULT 0, emotionArousal REAL NOT NULL DEFAULT 0, isRead INTEGER NOT NULL DEFAULT 0, createdAt TEXT NOT NULL DEFAULT '' ) ''');
        break;
      case 'forum_posts':
        await db.execute(
            ''' CREATE TABLE IF NOT EXISTS forum_posts ( id TEXT PRIMARY KEY, authorId TEXT NOT NULL DEFAULT '', authorName TEXT NOT NULL DEFAULT '', authorAvatar TEXT, isFromAI INTEGER NOT NULL DEFAULT 0, characterId TEXT, title TEXT NOT NULL DEFAULT '', content TEXT NOT NULL DEFAULT '', images TEXT, tags TEXT, likes TEXT DEFAULT '[]', isAnonymous INTEGER NOT NULL DEFAULT 0, visibility INTEGER NOT NULL DEFAULT 0, createdAt TEXT NOT NULL DEFAULT '', updatedAt TEXT ) ''');
        break;
      case 'forum_comments':
        await db.execute(
            ''' CREATE TABLE IF NOT EXISTS forum_comments ( id TEXT PRIMARY KEY, postId TEXT NOT NULL DEFAULT '', authorId TEXT NOT NULL DEFAULT '', authorName TEXT NOT NULL DEFAULT '', authorAvatar TEXT, isFromAI INTEGER NOT NULL DEFAULT 0, characterId TEXT, content TEXT NOT NULL DEFAULT '', replyToId TEXT, replyToName TEXT, isAnonymous INTEGER NOT NULL DEFAULT 0, createdAt TEXT NOT NULL DEFAULT '' ) ''');
        break;
      case 'shared_album_entries':
        await db.execute(
            ''' CREATE TABLE IF NOT EXISTS shared_album_entries ( id TEXT PRIMARY KEY, characterId TEXT NOT NULL DEFAULT '', userId TEXT NOT NULL DEFAULT '', memoryId TEXT, title TEXT NOT NULL DEFAULT '', description TEXT, eventDate TEXT, imagePath TEXT, importance INTEGER NOT NULL DEFAULT 1, createdAt TEXT NOT NULL DEFAULT '' ) ''');
        break;
      case 'virtual_locations':
        await db.execute(
            ''' CREATE TABLE IF NOT EXISTS virtual_locations ( id TEXT PRIMARY KEY, characterId TEXT NOT NULL DEFAULT '', userId TEXT NOT NULL DEFAULT '', userLat REAL NOT NULL DEFAULT 0, userLng REAL NOT NULL DEFAULT 0, aiLat REAL NOT NULL DEFAULT 0, aiLng REAL NOT NULL DEFAULT 0, sceneDescription TEXT, distance REAL NOT NULL DEFAULT 0, createdAt TEXT NOT NULL DEFAULT '' ) ''');
        break;
      case 'persona_snapshots':
        await db.execute(
            ''' CREATE TABLE IF NOT EXISTS persona_snapshots ( id TEXT PRIMARY KEY, characterId TEXT NOT NULL DEFAULT '', snapshotType TEXT NOT NULL DEFAULT 'initial', traitsData TEXT NOT NULL DEFAULT '{}', surfaceData TEXT NOT NULL DEFAULT '{}', createdAt TEXT NOT NULL DEFAULT '', label TEXT ) ''');
        break;
      case 'growth_events':
        await db.execute(
            ''' CREATE TABLE IF NOT EXISTS growth_events ( id TEXT PRIMARY KEY, characterId TEXT NOT NULL DEFAULT '', userId TEXT NOT NULL DEFAULT '', triggerType TEXT NOT NULL DEFAULT 'micro', evolutionMode TEXT NOT NULL DEFAULT 'micro', triggerData TEXT NOT NULL DEFAULT '{}', deltas TEXT NOT NULL DEFAULT '{}', impactScore REAL NOT NULL DEFAULT 0, reason TEXT, createdAt TEXT NOT NULL DEFAULT '' ) ''');
        break;
      case 'intimacy_events':
        await createIntimacyEventsTable(db);
        break;
      case 'character_commitments':
        await createCharacterCommitmentsTable(db);
        break;
      case 'relationship_contexts':
        await createRelationshipContextsTable(db);
        break;
      case 'ai_letters':
        await createAILettersTable(db);
        break;
      case 'bt_agent_actions':
        await db.execute(''' CREATE TABLE IF NOT EXISTS bt_agent_actions (
          id TEXT PRIMARY KEY, actionType TEXT NOT NULL DEFAULT '', category TEXT NOT NULL DEFAULT '',
          scope TEXT NOT NULL DEFAULT '', targetType TEXT NOT NULL DEFAULT '', targetId TEXT NOT NULL DEFAULT '',
          reason TEXT NOT NULL DEFAULT '', stateBefore TEXT NOT NULL DEFAULT '', stateAfter TEXT NOT NULL DEFAULT '',
          result TEXT NOT NULL DEFAULT '', rejectionReason TEXT NOT NULL DEFAULT '',
          characterId TEXT NOT NULL DEFAULT '', sessionId TEXT NOT NULL DEFAULT '',
          chatType TEXT NOT NULL DEFAULT 'single', createdAt TEXT NOT NULL DEFAULT ''
        ) ''');
        await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_bt_agent_actions_createdAt ON bt_agent_actions(createdAt DESC)');
        break;
      case 'social_memories':
        await db.execute(''' CREATE TABLE IF NOT EXISTS social_memories (
          id TEXT PRIMARY KEY, characterId TEXT NOT NULL, targetCharacterId TEXT NOT NULL,
          interactionType TEXT DEFAULT 'chat', content TEXT DEFAULT '',
          emotionTag TEXT DEFAULT '', importance TEXT DEFAULT 'normal',
          keywords TEXT DEFAULT '[]', timestamp TEXT NOT NULL,
          weight REAL DEFAULT 1.0, pinned INTEGER DEFAULT 0, lastRecalledAt TEXT
        ) ''');
        break;
      case 'moment_bookmarks':
        await db.execute(''' CREATE TABLE IF NOT EXISTS moment_bookmarks (
          id TEXT PRIMARY KEY, momentId TEXT NOT NULL, userId TEXT NOT NULL,
          createdAt TEXT NOT NULL
        ) ''');
        await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_moment_bookmarks_userId ON moment_bookmarks(userId)');
        break;
      case 'moment_notifications':
        await db.execute(''' CREATE TABLE IF NOT EXISTS moment_notifications (
          id TEXT PRIMARY KEY, momentId TEXT NOT NULL, actorId TEXT NOT NULL,
          actorName TEXT NOT NULL, actorAvatar TEXT, type INTEGER NOT NULL DEFAULT 0,
          content TEXT, createdAt TEXT NOT NULL, isRead INTEGER NOT NULL DEFAULT 0,
          isFromAI INTEGER NOT NULL DEFAULT 0
        ) ''');
        await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_moment_notifications_createdAt ON moment_notifications(createdAt DESC)');
        break;
      case 'trending_tags':
        await db.execute(''' CREATE TABLE IF NOT EXISTS trending_tags (
          tag TEXT PRIMARY KEY, count INTEGER NOT NULL DEFAULT 1,
          lastUsedAt TEXT NOT NULL
        ) ''');
        await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_trending_tags_count ON trending_tags(count DESC)');
        break;
      case 'pure_ai_sessions':
        await db.execute(
            ''' CREATE TABLE IF NOT EXISTS pure_ai_sessions ( id TEXT PRIMARY KEY, userId TEXT NOT NULL, title TEXT NOT NULL DEFAULT 'AI', lastMessage TEXT, lastMessageTime TEXT, isPinned INTEGER NOT NULL DEFAULT 0, createdAt TEXT NOT NULL, updatedAt TEXT ) ''');
        break;
      case 'pure_ai_messages':
        await db.execute(
            ''' CREATE TABLE IF NOT EXISTS pure_ai_messages ( id TEXT PRIMARY KEY, sessionId TEXT NOT NULL, senderId TEXT NOT NULL, senderName TEXT, content TEXT NOT NULL, type INTEGER NOT NULL DEFAULT 0, status INTEGER NOT NULL DEFAULT 1, createdAt TEXT NOT NULL, metadata TEXT ) ''');
        break;
      case 'novels':
      case 'novel_chapters':
        await _createNovelTables(db);
        break;
      case 'group_chat_sessions':
        await db.execute(''' CREATE TABLE IF NOT EXISTS group_chat_sessions (
          id TEXT PRIMARY KEY,
          userId TEXT NOT NULL DEFAULT '',
          name TEXT NOT NULL DEFAULT '',
          avatarUrl TEXT,
          memberIds TEXT NOT NULL DEFAULT '[]',
          aiCharacterIds TEXT NOT NULL DEFAULT '[]',
          creatorId TEXT NOT NULL DEFAULT '',
          lastMessage TEXT,
          lastMessageTime TEXT,
          unreadCount INTEGER NOT NULL DEFAULT 0,
          isMuted INTEGER NOT NULL DEFAULT 0,
          isPinned INTEGER NOT NULL DEFAULT 0,
          backgroundImage TEXT,
          notice TEXT,
          createdAt TEXT NOT NULL DEFAULT '',
          updatedAt TEXT,
      sync_seq INTEGER NOT NULL DEFAULT 0
     ) ''');
        await _addColumnIfNotExists(db, 'group_chat_sessions', 'autoModeDelay',
            'INTEGER NOT NULL DEFAULT 5');
        await _addColumnIfNotExists(db, 'group_chat_sessions',
            'autoModeEnabled', 'INTEGER NOT NULL DEFAULT 0');
        await _addColumnIfNotExists(db, 'group_chat_sessions',
            'autoModeDelaysByCharacter', "TEXT NOT NULL DEFAULT '{}'");
        // 兼容旧表缺少 userId 列的情况（老版本建的表可能含 userId 或缺失）
        await _addColumnIfNotExists(
            db, 'group_chat_sessions', 'userId', 'TEXT NOT NULL DEFAULT ""');
        // 兼容旧表缺少 creatorId 列的情况（v56 之前创建的旧表无此列）
        await _addColumnIfNotExists(
            db, 'group_chat_sessions', 'creatorId', 'TEXT NOT NULL DEFAULT ""');
        await _addColumnIfNotExists(db, 'group_chat_sessions', 'sync_seq',
            'INTEGER NOT NULL DEFAULT 0');
        await _addColumnIfNotExists(
            db, 'group_chat_sessions', 'notice', 'TEXT');
        await _addColumnIfNotExists(db, 'group_chat_sessions', 'autoModeDelay',
            'INTEGER NOT NULL DEFAULT 5');
        await _addColumnIfNotExists(db, 'group_chat_sessions',
            'autoModeEnabled', 'INTEGER NOT NULL DEFAULT 0');
        await _addColumnIfNotExists(db, 'group_chat_sessions',
            'autoModeDelaysByCharacter', "TEXT NOT NULL DEFAULT '{}'");
        await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_gc_sessions_creator ON group_chat_sessions(creatorId)');
        await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_gc_sessions_updatedAt ON group_chat_sessions(updatedAt DESC)');
        break;
      case 'group_chat_messages':
        await db.execute(''' CREATE TABLE IF NOT EXISTS group_chat_messages (
          id TEXT PRIMARY KEY,
          groupId TEXT NOT NULL DEFAULT '',
          senderId TEXT NOT NULL DEFAULT '',
          senderName TEXT,
          content TEXT NOT NULL DEFAULT '',
          isUser INTEGER NOT NULL DEFAULT 0,
          isSystem INTEGER NOT NULL DEFAULT 0,
          type TEXT NOT NULL DEFAULT 'text',
          createdAt TEXT NOT NULL DEFAULT '',
          status TEXT NOT NULL DEFAULT 'sent',
          metadata TEXT
        ) ''');
        await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_gc_msgs_group ON group_chat_messages(groupId, createdAt DESC)');
        break;
      case 'group_chat_branches':
        await db.execute('''CREATE TABLE IF NOT EXISTS group_chat_branches (
          branchId TEXT PRIMARY KEY,
          groupId TEXT NOT NULL DEFAULT '',
          name TEXT NOT NULL DEFAULT '',
          createdAt TEXT NOT NULL DEFAULT '',
          updatedAt TEXT
        )''');
        await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_gc_branches_group ON group_chat_branches(groupId)');
        break;
      case 'group_chat_summaries':
        await db.execute('''CREATE TABLE IF NOT EXISTS group_chat_summaries (
          groupId TEXT NOT NULL,
          chatId TEXT NOT NULL,
          summary TEXT NOT NULL DEFAULT '',
          messageCount INTEGER NOT NULL DEFAULT 0,
          updatedAt TEXT NOT NULL DEFAULT '',
          PRIMARY KEY (groupId, chatId)
        )''');
        break;
      case 'group_public_event_memories':
        await db
            .execute('''CREATE TABLE IF NOT EXISTS group_public_event_memories (
          id TEXT PRIMARY KEY, characterId TEXT NOT NULL DEFAULT '',
          groupId TEXT NOT NULL DEFAULT '', chatId TEXT NOT NULL DEFAULT '',
          content TEXT NOT NULL DEFAULT '', keywords TEXT NOT NULL DEFAULT '[]',
          sourceMessageIds TEXT NOT NULL DEFAULT '[]', speakerNames TEXT NOT NULL DEFAULT '[]',
          metadata TEXT, sourceGroupName TEXT, importance TEXT NOT NULL DEFAULT 'normal',
          pinned INTEGER NOT NULL DEFAULT 0, weight REAL NOT NULL DEFAULT 1.0,
          createdAt TEXT NOT NULL DEFAULT '', lastRecalledAt TEXT
        )''');
        await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_group_public_events_scope ON group_public_event_memories(characterId, groupId, chatId)');
        break;
      case 'group_chat_lorebook_entries':
        await db
            .execute('''CREATE TABLE IF NOT EXISTS group_chat_lorebook_entries (
          id TEXT PRIMARY KEY, groupId TEXT NOT NULL DEFAULT '', chatId TEXT,
          name TEXT NOT NULL DEFAULT '', content TEXT NOT NULL DEFAULT '',
          keywords TEXT NOT NULL DEFAULT '[]', priority INTEGER NOT NULL DEFAULT 0,
          depth INTEGER NOT NULL DEFAULT 2, enabled INTEGER NOT NULL DEFAULT 1,
          recursive INTEGER NOT NULL DEFAULT 0
        )''');
        await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_gc_lore_group ON group_chat_lorebook_entries(groupId)');
        break;
    }
  }
  /// 群聊数据库自愈：兼容已升级但迁移未完整执行的旧库。
  static Future<void> _ensureGroupChatSchema(Database db) async {
    try {
      if (await _groupChatSessionsNeedRebuild(db)) {
        await _rebuildGroupChatSessionsTable(db);
      }
      await createMissingTable(db, 'group_chat_sessions');
      await createMissingTable(db, 'group_chat_messages');
    await createMissingTable(db, 'group_chat_branches');
    // 显式创建 shop_items 表（不依赖 reconcileSchema 兜底，确保新用户首装即有）
    await _ensureShopItemsSchema(db);
      await createMissingTable(db, 'group_chat_summaries');
      await createMissingTable(db, 'group_public_event_memories');
      await createMissingTable(db, 'group_chat_lorebook_entries');

      await _addColumnIfNotExists(
          db, 'group_chat_messages', 'chatId', 'TEXT NOT NULL DEFAULT ""');
      await _addColumnIfNotExists(
          db, 'group_chat_messages', 'sync_seq', 'INTEGER NOT NULL DEFAULT 0');
      await _addColumnIfNotExists(db, 'group_chat_messages', 'swipeHistory',
          "TEXT NOT NULL DEFAULT '[]'");
      await _addColumnIfNotExists(db, 'group_chat_messages', 'swipeIndex',
          'INTEGER NOT NULL DEFAULT 0');
      await _addColumnIfNotExists(
          db, 'group_chat_messages', 'parentMessageId', 'TEXT');
      await _addColumnIfNotExists(
          db, 'group_chat_sessions', 'isHidden', 'INTEGER NOT NULL DEFAULT 0');
      await _addColumnIfNotExists(db, 'group_chat_sessions',
          'autoModeDelaysByCharacter', "TEXT NOT NULL DEFAULT '{}'");
    } catch (e) {
      debugPrint('[schema] group chat self-heal failed: $e');
    }
  }
  /// 识别历史群聊表：旧版本存在无默认值的 NOT NULL 列，插入新模型会崩溃。
  static Future<bool> _groupChatSessionsNeedRebuild(Database db) async {
    final rows = await db.rawQuery('PRAGMA table_info(group_chat_sessions)');
    if (rows.isEmpty) return false;
    final names = rows.map((r) => r['name'] as String).toSet();
    if (names.contains('participantIds') ||
        names.contains('participantNames')) {
      return true;
    }
    for (final row in rows) {
      final name = row['name'];
      if ((name == 'userId' || name == 'creatorId') &&
          row['notnull'] == 1 &&
          row['dflt_value'] == null) {
        return true;
      }
    }
    return !names.contains('id');
  }
  /// 安全添加列：先检查列是否已存在，避免重复添加报错
  static Future<void> _addColumnIfNotExists(
      Database db, String table, String column, String type) async {
    try {
      final result = await db.rawQuery('PRAGMA table_info($table)');
      final columns = result.map((r) => r['name'] as String).toList();
      if (!columns.contains(column)) {
        await db.execute('ALTER TABLE $table ADD COLUMN $column $type');
      }
    } catch (e) {
      // 表不存在等情况不阻断，但要打日志便于定位迁移失败
      debugPrint('[schema] add column failed: $table.$column ($type) $e');
    }
  }
  /// 强制重建 group_chat_sessions 表（统一 schema，userId 带默认值）。
  /// 备份旧表 → DROP 重建 → 按备份真实列回迁（缺失列给默认值）。
  /// 解决历史脏表 `userId TEXT NOT NULL`（无默认）导致创建群 INSERT 崩溃。
  static Future<void> _rebuildGroupChatSessionsTable(Database db) async {
    try {
      final exists = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='group_chat_sessions'");
      if (exists.isEmpty) return;

      const allCols = [
        'id',
        'userId',
        'name',
        'avatarUrl',
        'memberIds',
        'aiCharacterIds',
        'creatorId',
        'lastMessage',
        'lastMessageTime',
        'unreadCount',
        'createdAt',
        'updatedAt',
        'isMuted',
        'isPinned',
        'backgroundImage',
        'notice',
        'sync_seq',
        'chatId',
        'activationStrategy',
        'generationMode',
        'allowSelfResponses',
        'disabledMemberIds',
        'autoModeDelay',
        'autoModeEnabled',
        'autoModeDelaysByCharacter',
        'joinPrefix',
        'joinSuffix',
        'isHidden',
      ];

      await db.execute('DROP TABLE IF EXISTS group_chat_sessions_bak');
      await db.execute(
          'ALTER TABLE group_chat_sessions RENAME TO group_chat_sessions_bak');

      await db.execute(''' CREATE TABLE group_chat_sessions (
        id TEXT PRIMARY KEY,
        userId TEXT NOT NULL DEFAULT '',
        name TEXT NOT NULL DEFAULT '',
        avatarUrl TEXT,
        memberIds TEXT NOT NULL DEFAULT '[]',
        aiCharacterIds TEXT NOT NULL DEFAULT '[]',
        creatorId TEXT NOT NULL DEFAULT '',
        lastMessage TEXT,
        lastMessageTime TEXT,
        unreadCount INTEGER NOT NULL DEFAULT 0,
        isMuted INTEGER NOT NULL DEFAULT 0,
        isPinned INTEGER NOT NULL DEFAULT 0,
        backgroundImage TEXT,
        notice TEXT,
        createdAt TEXT NOT NULL DEFAULT '',
        updatedAt TEXT,
        sync_seq INTEGER NOT NULL DEFAULT 0,
        chatId TEXT NOT NULL DEFAULT '',
        activationStrategy INTEGER NOT NULL DEFAULT 0,
        generationMode INTEGER NOT NULL DEFAULT 0,
        allowSelfResponses INTEGER NOT NULL DEFAULT 0,
        disabledMemberIds TEXT NOT NULL DEFAULT '[]',
        autoModeDelay INTEGER NOT NULL DEFAULT 5,
        autoModeEnabled INTEGER NOT NULL DEFAULT 0,
        isHidden INTEGER NOT NULL DEFAULT 0,
        autoModeDelaysByCharacter TEXT NOT NULL DEFAULT '{}',
        joinPrefix TEXT NOT NULL DEFAULT '',
        joinSuffix TEXT NOT NULL DEFAULT ''
      ) ''');

      final bakCols =
          (await db.rawQuery('PRAGMA table_info(group_chat_sessions_bak)'))
              .map((r) => r['name'] as String)
              .toSet();
      final cols = allCols.where(bakCols.contains).toList();
      if (cols.isNotEmpty) {
        final colList = cols.join(',');
        final selectExprs = cols.map((c) {
          switch (c) {
            case 'userId':
              return "COALESCE(userId, '')";
            case 'name':
              return "COALESCE(name, '')";
            case 'creatorId':
              return "COALESCE(creatorId, '')";
            case 'memberIds':
              return "COALESCE(memberIds, '[]')";
            case 'aiCharacterIds':
              return "COALESCE(aiCharacterIds, '[]')";
            case 'disabledMemberIds':
              return "COALESCE(disabledMemberIds, '[]')";
            case 'createdAt':
              return "COALESCE(createdAt, '')";
            case 'unreadCount':
              return 'COALESCE(unreadCount, 0)';
            case 'isMuted':
              return 'COALESCE(isMuted, 0)';
            case 'isPinned':
              return 'COALESCE(isPinned, 0)';
            case 'sync_seq':
              return 'COALESCE(sync_seq, 0)';
            case 'chatId':
              return 'COALESCE(chatId, id)';
            case 'activationStrategy':
              return 'COALESCE(activationStrategy, 0)';
            case 'generationMode':
              return 'COALESCE(generationMode, 0)';
            case 'allowSelfResponses':
              return 'COALESCE(allowSelfResponses, 0)';
            case 'autoModeDelay':
              return 'COALESCE(autoModeDelay, 5)';
            case 'autoModeEnabled':
              return 'COALESCE(autoModeEnabled, 0)';
            case 'autoModeDelaysByCharacter':
              return "COALESCE(autoModeDelaysByCharacter, '{}')";
            case 'joinPrefix':
              return "COALESCE(joinPrefix, '')";
            case 'joinSuffix':
              return "COALESCE(joinSuffix, '')";
            default:
              return c;
          }
        }).join(',');
        await db.execute(
            'INSERT INTO group_chat_sessions ($colList) SELECT $selectExprs FROM group_chat_sessions_bak');
      }
      await db.execute('DROP TABLE IF EXISTS group_chat_sessions_bak');
    } catch (e) {
      debugPrint('[schema] _rebuildGroupChatSessionsTable failed: $e');
    }
  }
  /// shop_items 完整建表 SQL（_onCreate / 缺表 / 重建共用）
  static const String _shopItemsCreateSql =
      ''' CREATE TABLE IF NOT EXISTS shop_items (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL DEFAULT '',
        category TEXT NOT NULL DEFAULT '',
        price INTEGER NOT NULL DEFAULT 0,
        emoji TEXT NOT NULL DEFAULT '',
        description TEXT DEFAULT '',
        tags TEXT DEFAULT '',
        isActive INTEGER NOT NULL DEFAULT 1,
        isCustom INTEGER NOT NULL DEFAULT 0,
        createdAt TEXT
      ) ''';
  /// 幂等保证 shop_items 具备完整列（含 isCustom / createdAt）。
  ///
  /// 只做 CREATE IF NOT EXISTS + 按需 ALTER 补列，全部幂等：
  /// - 不开内部事务：避免与 onCreate/onUpgrade 的外层事务嵌套（历史顽疾根因）
  /// - 不用 static 缓存：避免跨实例 / 热重载状态污染
  /// - 不重建表、不 rethrow：缺的只是两个可空列，ALTER 足矣，失败也不阻断启动
  ///
  /// [force] 保留以兼容旧调用方；本方法本就每次都真正执行。
  static Future<void> _ensureShopItemsSchema(Database db,
      {bool force = false}) async {
    try {
      await db.execute(_shopItemsCreateSql);
      await _addColumnIfNotExists(
          db, 'shop_items', 'isCustom', 'INTEGER NOT NULL DEFAULT 0');
      await _addColumnIfNotExists(db, 'shop_items', 'createdAt', 'TEXT');
    } catch (e) {
      debugPrint('[schema] _ensureShopItemsSchema failed: $e');
    }
  }
  static Future<void> createAILettersTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ai_letters (
        id TEXT PRIMARY KEY,
        userId TEXT NOT NULL DEFAULT '',
        characterId TEXT NOT NULL DEFAULT '',
        characterName TEXT NOT NULL DEFAULT '',
        characterAvatar TEXT,
        recipientName TEXT NOT NULL DEFAULT '',
        title TEXT NOT NULL DEFAULT '',
        content TEXT NOT NULL DEFAULT '',
        isRead INTEGER NOT NULL DEFAULT 0,
        isFromUser INTEGER NOT NULL DEFAULT 0,
        needsReply INTEGER NOT NULL DEFAULT 0,
        sourceChatId TEXT,
        createdAt TEXT NOT NULL DEFAULT '',
        readAt TEXT,
        sync_seq INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute(
        ''' CREATE INDEX IF NOT EXISTS idx_ai_letters_userId ON ai_letters(userId) ''');
    await db.execute(
        ''' CREATE INDEX IF NOT EXISTS idx_ai_letters_characterId ON ai_letters(characterId) ''');
    await db.execute(
        ''' CREATE INDEX IF NOT EXISTS idx_ai_letters_createdAt ON ai_letters(createdAt DESC) ''');
  }
  static Future<void> createIntimacyEventsTable(Database db) async {
    await db.execute(
        ''' CREATE TABLE IF NOT EXISTS intimacy_events ( id TEXT PRIMARY KEY, chatId TEXT NOT NULL DEFAULT '', userId TEXT NOT NULL DEFAULT '', characterId TEXT NOT NULL DEFAULT '', oldLevel INTEGER NOT NULL DEFAULT 0, newLevel INTEGER NOT NULL DEFAULT 0, delta INTEGER NOT NULL DEFAULT 0, dailyCount INTEGER NOT NULL DEFAULT 0, source TEXT NOT NULL DEFAULT '', messagePreview TEXT, sentimentLabel TEXT, sentimentType TEXT, createdAt TEXT NOT NULL DEFAULT '', sync_seq INTEGER NOT NULL DEFAULT 0 ) ''');
    await db.execute(
        ''' CREATE INDEX IF NOT EXISTS idx_intimacy_events_chatId ON intimacy_events(chatId) ''');
    await db.execute(
        ''' CREATE INDEX IF NOT EXISTS idx_intimacy_events_createdAt ON intimacy_events(createdAt DESC) ''');
  }
  static Future<void> createCharacterCommitmentsTable(Database db) async {
    await db.execute(
        ''' CREATE TABLE IF NOT EXISTS character_commitments ( id TEXT PRIMARY KEY, characterId TEXT NOT NULL DEFAULT '', userId TEXT NOT NULL DEFAULT '', chatId TEXT NOT NULL DEFAULT '', content TEXT NOT NULL DEFAULT '', dueAt TEXT NOT NULL DEFAULT '', status TEXT NOT NULL DEFAULT 'active', createdAt TEXT NOT NULL DEFAULT '', updatedAt TEXT NOT NULL DEFAULT '' ) ''');
    await db.execute(
        ''' CREATE INDEX IF NOT EXISTS idx_character_commitments_active ON character_commitments(characterId, userId, status, dueAt) ''');
  }
  static Future<void> createRelationshipContextsTable(Database db) async {
    await db.execute(
        ''' CREATE TABLE IF NOT EXISTS relationship_contexts ( chatId TEXT PRIMARY KEY, trust REAL NOT NULL DEFAULT 0.5, boundary TEXT, unresolvedConflict TEXT, recentImportantEvent TEXT, updatedAt TEXT NOT NULL DEFAULT '' ) ''');
  }
  static Future<Set<String>> getTableColumns(
      DatabaseExecutor db, String table) async {
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    return rows.map((r) => r['name'] as String).toSet();
  }
  /// 兜底表侧 `NOT NULL` 且无默认值的列：模型 toMap() 可能不含它们
  /// （如历史 `participantIds`），单靠列过滤无法兜住，导致
  /// `NOT NULL constraint failed` 崩溃。改写前填入类型安全默认值予以规避。
  static Future<void> _fillNotNullDefaults(
    DatabaseExecutor db,
    String table,
    Map<String, dynamic> map,
  ) async {
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    for (final r in rows) {
      if (r['notnull'] != 1) continue;
      final name = r['name'] as String;
      if (r['dflt_value'] != null) continue; // 已有默认值，无需填充
      if (map.containsKey(name)) continue; // 模型已提供
      // 语义等价回填：历史 participantIds ≈ 现代 memberIds
      if (name == 'participantIds' && map.containsKey('memberIds')) {
        map[name] = map['memberIds'];
        continue;
      }
      final type = (r['type'] as String? ?? '').toUpperCase();
      if (type.contains('INT')) {
        map[name] = 0;
      } else if (type.contains('REAL')) {
        map[name] = 0.0;
      } else {
        map[name] = '';
      }
    }
  }
  /// 仅供测试：在给定数据库上运行 shop_items schema 自愈逻辑。
  /// 用于在「缺列的旧库」上验证幂等修复，见 test/shop_schema_recovery_test.dart。
  @visibleForTesting
  static Future<void> ensureShopItemsSchemaForTest(Database db) =>
      _ensureShopItemsSchema(db, force: true);
  /// 仅供测试：补填表侧 NOT NULL 无默认值列缺省值（防御遗留脏表插入崩溃）。
  /// 见 test/group_chat_session_safe_write_test.dart。
  @visibleForTesting
  static Future<void> fillNotNullDefaultsForTest(
    Database db,
    String table,
    Map<String, dynamic> map,
  ) =>
      _fillNotNullDefaults(db, table, map);
  /// 仅供测试：验证旧版本群聊表能被自动检测并修复。
  @visibleForTesting
  static Future<void> ensureGroupChatSchemaForTest(Database db) =>
      _ensureGroupChatSchema(db);
  /// 虚拟手机六张表建表语句（_onCreate / 迁移 共用）
  static Future<void> _createVirtualPhoneTables(Database db) async {
    await db.execute(
        ''' CREATE TABLE IF NOT EXISTS virtual_phones ( id TEXT PRIMARY KEY, characterId TEXT NOT NULL, ownerName TEXT NOT NULL DEFAULT '', wallpaperColor INTEGER NOT NULL DEFAULT 4283871606, status TEXT NOT NULL DEFAULT 'empty', generatedAt TEXT, lastAdvanceMsgCount INTEGER NOT NULL DEFAULT 0, lastAdvanceAt TEXT, createdAt TEXT NOT NULL, updatedAt TEXT, sync_seq INTEGER NOT NULL DEFAULT 0 ) ''');
    await db.execute(
        ''' CREATE INDEX IF NOT EXISTS idx_vphone_char ON virtual_phones(characterId) ''');
    await db.execute(
        ''' CREATE TABLE IF NOT EXISTS vp_contacts ( id TEXT PRIMARY KEY, phoneId TEXT NOT NULL, characterId TEXT NOT NULL, name TEXT NOT NULL DEFAULT '', relation TEXT NOT NULL DEFAULT '', note TEXT NOT NULL DEFAULT '', accentColor INTEGER NOT NULL DEFAULT 4278223103, isUser INTEGER NOT NULL DEFAULT 0, pinned INTEGER NOT NULL DEFAULT 0, orderIndex INTEGER NOT NULL DEFAULT 0 ) ''');
    await db.execute(
        ''' CREATE INDEX IF NOT EXISTS idx_vp_contacts_phone ON vp_contacts(phoneId) ''');
    await db.execute(
        ''' CREATE TABLE IF NOT EXISTS vp_chats ( id TEXT PRIMARY KEY, phoneId TEXT NOT NULL, characterId TEXT NOT NULL, contactId TEXT NOT NULL DEFAULT '', title TEXT NOT NULL DEFAULT '', lastPreview TEXT NOT NULL DEFAULT '', orderIndex INTEGER NOT NULL DEFAULT 0 ) ''');
    await db.execute(
        ''' CREATE INDEX IF NOT EXISTS idx_vp_chats_phone ON vp_chats(phoneId) ''');
    await db.execute(
        ''' CREATE TABLE IF NOT EXISTS vp_chat_messages ( id TEXT PRIMARY KEY, chatId TEXT NOT NULL, fromOwner INTEGER NOT NULL DEFAULT 0, content TEXT NOT NULL DEFAULT '', timeLabel TEXT NOT NULL DEFAULT '', orderIndex INTEGER NOT NULL DEFAULT 0 ) ''');
    await db.execute(
        ''' CREATE INDEX IF NOT EXISTS idx_vp_msgs_chat ON vp_chat_messages(chatId, orderIndex) ''');
    await db.execute(
        ''' CREATE TABLE IF NOT EXISTS vp_notes ( id TEXT PRIMARY KEY, phoneId TEXT NOT NULL, characterId TEXT NOT NULL, title TEXT NOT NULL DEFAULT '', body TEXT NOT NULL DEFAULT '', dateLabel TEXT NOT NULL DEFAULT '', aboutUser INTEGER NOT NULL DEFAULT 0, orderIndex INTEGER NOT NULL DEFAULT 0 ) ''');
    await db.execute(
        ''' CREATE INDEX IF NOT EXISTS idx_vp_notes_phone ON vp_notes(phoneId) ''');
    await db.execute(
        ''' CREATE TABLE IF NOT EXISTS vp_moments ( id TEXT PRIMARY KEY, phoneId TEXT NOT NULL, characterId TEXT NOT NULL, content TEXT NOT NULL DEFAULT '', timeLabel TEXT NOT NULL DEFAULT '', likes INTEGER NOT NULL DEFAULT 0, comments TEXT NOT NULL DEFAULT '', orderIndex INTEGER NOT NULL DEFAULT 0 ) ''');
    await db.execute(
        ''' CREATE INDEX IF NOT EXISTS idx_vp_moments_phone ON vp_moments(phoneId) ''');
  }
  /// 小说模块两张表建表语句（_onCreate / 迁移 / createMissingTable 共用）
  static Future<void> _createNovelTables(Database db) async {
    await db.execute(
        ''' CREATE TABLE IF NOT EXISTS novels ( id TEXT PRIMARY KEY, userId TEXT NOT NULL DEFAULT '', title TEXT NOT NULL DEFAULT '', coverUrl TEXT, synopsis TEXT NOT NULL DEFAULT '', worldSetting TEXT NOT NULL DEFAULT '', characters TEXT NOT NULL DEFAULT '', genre INTEGER NOT NULL DEFAULT 7, status INTEGER NOT NULL DEFAULT 0, totalWords INTEGER NOT NULL DEFAULT 0, chapterCount INTEGER NOT NULL DEFAULT 0, isArchived INTEGER NOT NULL DEFAULT 0, createdAt TEXT NOT NULL DEFAULT '', updatedAt TEXT NOT NULL DEFAULT '', lastChapterPreview TEXT ) ''');
    await db.execute(
        ''' CREATE INDEX IF NOT EXISTS idx_novels_userId ON novels(userId) ''');
    await db.execute(
        ''' CREATE TABLE IF NOT EXISTS novel_chapters ( id TEXT PRIMARY KEY, novelId TEXT NOT NULL DEFAULT '', sortOrder INTEGER NOT NULL DEFAULT 0, title TEXT NOT NULL DEFAULT '', content TEXT NOT NULL DEFAULT '', wordCount INTEGER NOT NULL DEFAULT 0, isAiGenerated INTEGER NOT NULL DEFAULT 0, createdAt TEXT NOT NULL DEFAULT '', updatedAt TEXT NOT NULL DEFAULT '' ) ''');
    await db.execute(
        ''' CREATE INDEX IF NOT EXISTS idx_novel_chapters_novel ON novel_chapters(novelId, sortOrder) ''');
  }
  static String _todayDateKey([DateTime? now]) {
    final d = now ?? DateTime.now();
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }
  /// 消息写前缓冲 key 前缀
  static const _bufferPrefix = 'msg_buffer_';
  static const _bufferIdsKey = 'msg_buffer_ids';
  static bool isLocalFileUrl(String value) {
    if (value.isEmpty) return false;
    if (value.startsWith('http://') || value.startsWith('https://'))
      return false;
    if (value.startsWith('data:')) return false;
    return value.startsWith('/') ||
        value.startsWith('storage/') ||
        value.contains('/data/');
  }
  static Future<Map<String, String>> collectLocalFiles(
      Map<String, dynamic> data) async {
    final fileMap = <String, String>{};
    try {
      final dir = await getApplicationDocumentsDirectory();
      void collectFromValue(dynamic value) {
        if (value is String && isLocalFileUrl(value)) {
          // 绝对路径直接用，相对路径拼接 docsPath
          final filePath = value.startsWith('/') ? value : '${dir.path}/$value';
          final file = File(filePath);
          if (file.existsSync()) {
            final bytes = file.readAsBytesSync();
            fileMap[value] = base64Encode(bytes);
          }
        }
      }

      void collectFromMap(Map<String, dynamic> map) {
        for (final v in map.values) {
          if (v is String) {
            collectFromValue(v);
          } else if (v is Map<String, dynamic>) {
            collectFromMap(v);
          } else if (v is List) {
            for (final item in v) {
              if (item is String) collectFromValue(item);
              if (item is Map<String, dynamic>) collectFromMap(item);
            }
          }
        }
      }

      for (final tableData in data.values) {
        if (tableData is List) {
          for (final row in tableData) {
            if (row is Map<String, dynamic>) collectFromMap(row);
          }
        } else if (tableData is Map<String, dynamic>) {
          collectFromMap(tableData);
        }
      }
    } catch (e) {
      debugPrint('collectLocalFiles error: $e');
    }
    return fileMap;
  }
  static Future<Map<String, String>> restoreLocalFiles(
      Map<String, String> encodedFiles) async {
    final pathMap = <String, String>{};
    try {
      final dir = await getApplicationDocumentsDirectory();
      final backupDir = Directory('${dir.path}/backup_files');
      if (!await backupDir.exists()) {
        await backupDir.create(recursive: true);
      }
      final usedNames = <String>{};
      for (final entry in encodedFiles.entries) {
        try {
          final bytes = base64Decode(entry.value);
          var fileName = basename(entry.key);
          if (usedNames.contains(fileName)) {
            final ext = extension(fileName);
            final base = basenameWithoutExtension(fileName);
            int seq = 2;
            while (usedNames.contains('${base}_$seq$ext')) {
              seq++;
            }
            fileName = '${base}_$seq$ext';
          }
          usedNames.add(fileName);
          final newPath = '${backupDir.path}/$fileName';
          await File(newPath).writeAsBytes(bytes);
          pathMap[entry.key] = newPath;
        } catch (e) {
          debugPrint('Error: $e');
        }
      }
    } catch (e) {
      debugPrint('Error: $e');
    }
    return pathMap;
  }
}

