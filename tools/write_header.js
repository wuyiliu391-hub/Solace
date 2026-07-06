const fs = require('fs');

// 写入文件头部（imports + class declaration + initialize + _ensureDb fix + close fix）
const header = `import 'dart:convert';
import 'dart:io' show Directory, File, gzip;
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../services/log_service.dart';
import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';
import '../models/ai_character.dart';
import '../models/ai_config.dart';
import '../models/chat_session.dart';
import '../models/chat_message.dart';
import '../models/memory.dart';
import '../models/moment.dart';
import '../models/sticker_pack.dart';
import '../models/group_chat_session.dart';
import '../models/group_member_settings.dart';
import '../models/group_relationship.dart';
import '../models/ai_wallet.dart';
import '../models/shop_item.dart';
import '../models/shop_order.dart';
import '../models/pure_ai_session.dart';
import '../models/pure_ai_message.dart';
import '../config/business_rules.dart';
import '../config/constants.dart';

class LocalStorageRepository {
  static const String _dbName = DbDefaults.dbName;
  static const int _dbVersion = DbDefaults.dbVersion;

  Database? _database;
  SharedPreferences? _prefs;
  bool _isWeb = false;

  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
    _isWeb = kIsWeb;
    if (!_isWeb) {
      _database = await _initDatabase();
      await _validateDatabaseIntegrity(_database!);
    }
  }

  /// 启动完整性校验：验证所有关键表可读，异常时自动修复
  Future<void> _validateDatabaseIntegrity(Database db) async {
    for (final table in expectedColumns.keys) {
      try {
        await db.rawQuery('SELECT COUNT(*) as cnt FROM \$table');
      } catch (e) {
        debugPrint('启动校验: \$table 表异常(\$e)，尝试自动修复..');
        try { await reconcileSchema(db); } catch (_) {}
        break;
      }
    }
  }

  Future<Database> _ensureDb() async {
    if (_isWeb) throw UnsupportedError('数据库不支持 Web 平台');
    var db = _database;
    if (db == null || !db.isOpen) {
      db = await _initDatabase();
      _database = db;
      return db;
    }
    // 死连接探测：sqflite 的 isOpen 只反映 Dart 侧状态，不能感知原生侧连接的存活
    try {
      await db.rawQuery('SELECT 1');
    } catch (e) {
      debugPrint('数据库连接已失效，自动重新打开: \$e');
      _database = null;
      db = await _initDatabase();
      _database = db;
    }
    return db;
  }

`;

fs.writeFileSync('lib/repositories/local_storage_repository.dart', header, 'utf8');
console.log('Header written, length:', header.length);
