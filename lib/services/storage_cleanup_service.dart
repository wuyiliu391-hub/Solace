import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../repositories/local_storage_repository.dart';

/// 单条存储占用（估算）
class StorageBucket {
  final String key;
  final String label;
  final String hint;
  final int bytes;
  final int itemCount;
  final bool canClean;

  /// category: session | character | type | file | system
  final String category;

  /// 会话 chatId / 角色 characterId（可选）
  final String? entityId;
  final String? entityName;
  final String? avatarUrl;

  const StorageBucket({
    required this.key,
    required this.label,
    required this.hint,
    required this.bytes,
    this.itemCount = 0,
    this.canClean = true,
    this.category = 'type',
    this.entityId,
    this.entityName,
    this.avatarUrl,
  });
}

class StorageAnalysis {
  final List<StorageBucket> buckets;
  final int totalBytes;
  final int dbBytes;
  final int filesBytes;

  const StorageAnalysis({
    required this.buckets,
    required this.totalBytes,
    required this.dbBytes,
    required this.filesBytes,
  });

  Iterable<StorageBucket> byCategory(String c) =>
      buckets.where((b) => b.category == c);
}

/// 本地存储占用分析 + 精细化 / 批量清理
class StorageCleanupService {
  StorageCleanupService._();

  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  static Future<StorageAnalysis> analyze(
      LocalStorageRepository storage) async {
    final buckets = <StorageBucket>[];
    var dbBytes = 0;
    var filesBytes = 0;

    final db = storage.database;
    if (db != null) {
      dbBytes = await _dbFileSize();

      // ── 按单聊会话拆分 ──
      try {
        final rows = await db.rawQuery('''
          SELECT cm.chatId AS chatId,
                 COUNT(*) AS cnt,
                 COALESCE(SUM(length(cm.content)
                   + COALESCE(length(cm.reasoning),0)
                   + COALESCE(length(cm.metadata),0)), 0) AS bytes,
                 cs.aiCharacterName AS name,
                 cs.aiCharacterAvatar AS avatar,
                 cs.aiCharacterId AS characterId
          FROM chat_messages cm
          LEFT JOIN chat_sessions cs ON cs.id = cm.chatId
          GROUP BY cm.chatId
          ORDER BY bytes DESC
        ''');
        for (final r in rows) {
          final chatId = r['chatId'] as String? ?? '';
          if (chatId.isEmpty) continue;
          final name = (r['name'] as String?) ?? '会话';
          final bytes = ((r['bytes'] as num?) ?? 0).toInt() +
              ((r['cnt'] as num?) ?? 0).toInt() * 120;
          buckets.add(StorageBucket(
            key: 'chat:$chatId',
            label: name,
            hint: '单聊 · ${r['cnt']} 条消息',
            bytes: bytes,
            itemCount: ((r['cnt'] as num?) ?? 0).toInt(),
            category: 'session',
            entityId: chatId,
            entityName: name,
            avatarUrl: r['avatar'] as String?,
          ));
        }
      } catch (e) {
        debugPrint('analyze sessions failed: $e');
      }

      // ── 按群聊拆分 ──
      try {
        final rows = await db.rawQuery('''
          SELECT groupId, COUNT(*) AS cnt,
                 COALESCE(SUM(length(content)+COALESCE(length(metadata),0)),0) AS bytes
          FROM group_chat_messages
          GROUP BY groupId
          ORDER BY bytes DESC
        ''');
        for (final r in rows) {
          final gid = r['groupId'] as String? ?? '';
          if (gid.isEmpty) continue;
          String name = '群聊';
          try {
            final s = await db.query('group_chat_sessions',
                where: 'id = ?', whereArgs: [gid], limit: 1);
            if (s.isNotEmpty) {
              name = (s.first['name'] as String?) ?? '群聊';
              if (name.trim().isEmpty) name = '群聊';
            }
          } catch (_) {}
          final bytes = ((r['bytes'] as num?) ?? 0).toInt() +
              ((r['cnt'] as num?) ?? 0).toInt() * 120;
          buckets.add(StorageBucket(
            key: 'group:$gid',
            label: name,
            hint: '群聊 · ${r['cnt']} 条消息',
            bytes: bytes,
            itemCount: ((r['cnt'] as num?) ?? 0).toInt(),
            category: 'session',
            entityId: gid,
            entityName: name,
          ));
        }
      } catch (e) {
        debugPrint('analyze groups failed: $e');
      }

      // ── 按角色记忆 ──
      try {
        final rows = await db.rawQuery('''
          SELECT characterId, COUNT(*) AS cnt,
                 COALESCE(SUM(length(content)),0) AS bytes
          FROM memories
          GROUP BY characterId
          ORDER BY bytes DESC
        ''');
        for (final r in rows) {
          final cid = r['characterId'] as String? ?? '';
          if (cid.isEmpty) continue;
          String name = '角色';
          String? avatar;
          try {
            final c = await storage.getAICharacter(cid);
            name = c?.name ?? cid;
            avatar = c?.avatarUrl;
          } catch (_) {}
          final bytes = ((r['bytes'] as num?) ?? 0).toInt() +
              ((r['cnt'] as num?) ?? 0).toInt() * 80;
          buckets.add(StorageBucket(
            key: 'mem:$cid',
            label: '$name · 记忆',
            hint: '${r['cnt']} 条记忆',
            bytes: bytes,
            itemCount: ((r['cnt'] as num?) ?? 0).toInt(),
            category: 'character',
            entityId: cid,
            entityName: name,
            avatarUrl: avatar,
          ));
        }
      } catch (e) {
        debugPrint('analyze memories failed: $e');
      }

      // ── 按类型（全局表） ──
      Future<void> addTable(
        String table,
        String key,
        String label,
        String hint, {
        String sizeExpr = 'length(content)',
      }) async {
        try {
          final cnt = Sqflite.firstIntValue(
                  await db.rawQuery('SELECT COUNT(*) FROM $table')) ??
              0;
          if (cnt == 0) return;
          final sizeRow = await db.rawQuery(
              'SELECT COALESCE(SUM($sizeExpr), 0) AS s FROM $table');
          final contentBytes = ((sizeRow.first['s'] as num?) ?? 0).toInt();
          buckets.add(StorageBucket(
            key: key,
            label: label,
            hint: '$cnt 条 · $hint',
            bytes: contentBytes + cnt * 120,
            itemCount: cnt,
            category: 'type',
          ));
        } catch (e) {
          debugPrint('analyze $table failed: $e');
        }
      }

      await addTable('pure_ai_messages', 'table_pure_ai_messages', '纯AI消息',
          '纯 AI 会话记录');
      await addTable('ai_letters', 'table_ai_letters', 'AI 来信', '历史来信');
      await addTable('inner_thoughts', 'table_inner_thoughts', '内心独白',
          '心理活动记录');
      await addTable('growth_events', 'table_growth_events', '成长事件',
          '人格进化事件');
      await addTable('persona_snapshots', 'table_persona_snapshots',
          '人格快照', '保留 initial');
      await addTable('social_memories', 'table_social_memories', '社交记忆',
          '角色间互动');
      await addTable('usage_records', 'table_usage_records', '用量记录',
          'token/调用统计');
      await addTable('moments', 'table_moments', '朋友圈动态',
          '优先清旧 AI 动态',
          sizeExpr:
              "length(content)+COALESCE(length(images),0)+COALESCE(length(comments),0)");
    }

    // ── 真实磁盘占用：完整扫描 app 文档目录 + 数据库目录 + 缓存 ──
    Future<int> dirSize(Directory dir) async {
      if (!await dir.exists()) return 0;
      var total = 0;
      await for (final f in dir.list(recursive: true, followLinks: false)) {
        if (f is File) {
          try {
            total += await f.length();
          } catch (_) {}
        }
      }
      return total;
    }

    // 目录显示名 / 提示（未列出的目录用原名）
    const dirMeta = <String, (String, String)>{
      'ai_avatars': ('角色头像文件', 'ai_avatars 目录（清理会删本地头像）'),
      'avatars': ('用户头像', '个人资料头像文件'),
      'virtual_phone': ('虚拟手机资源', '生成的手机内容文件'),
      'voice': ('语音样本/缓存', '音色克隆样本与音频'),
      'diary': ('日记文件', '本地日记附件'),
      'chat_images': ('聊天图片', '聊天中收发的本地图片'),
      'profile_backgrounds': ('个人背景图', '主页/资料背景图片'),
      'backup_files': ('备份还原临时文件', '从备份解出的附件，通常可删'),
      // 危险：Flutter 引擎 debug 运行时（ResourceExtractor 解压的 kernel/snapshot）。
      // 删除后 res_timestamp 仍匹配 → 引擎不重解压 → 启动黑屏，需重装 APK 才能恢复。
      'flutter_assets': (
        'Flutter 引擎运行时（勿删）',
        'debug 包 JIT kernel/snapshot，删除会导致启动黑屏'
      ),
    };

    Directory? docs;
    try {
      docs = await getApplicationDocumentsDirectory();
    } catch (e) {
      debugPrint('docs dir failed: $e');
    }

    Future<void> addDirBucket(
      String name,
      String key,
      String label,
      String hint, {
      bool cleanable = true,
    }) async {
      final root = docs;
      if (root == null) return;
      final dir = Directory(p.join(root.path, name));
      final size = await dirSize(dir);
      if (size <= 0) return;
      filesBytes += size;
      buckets.add(StorageBucket(
        key: key,
        label: label,
        hint: hint,
        bytes: size,
        category: 'file',
        canClean: cleanable,
      ));
    }

    if (docs != null && await docs.exists()) {
      // 语音模型按子模型拆分（最大头）
      final vmRoot = Directory(p.join(docs.path, 'voice_models'));
      if (await vmRoot.exists()) {
        final voiceLabels = <String, (String, String)>{
          'sensevoice': (
            '语音识别模型 SenseVoice',
            '本地 STT；清理后需重新导入才能离线听写'
          ),
          'silero_vad': ('语音端点检测 VAD', '本地 VAD 小模型，可重新导入'),
          'zipvoice': (
            '旧版本地 TTS 模型',
            'TTS 已云端化，此目录一般可安全删除'
          ),
        };
        var vmTotal = 0;
        await for (final e in vmRoot.list(followLinks: false)) {
          final name = p.basename(e.path);
          int size = 0;
          if (e is Directory) {
            size = await dirSize(e);
          } else if (e is File) {
            try {
              size = await e.length();
            } catch (_) {}
          }
          if (size <= 0) continue;
          vmTotal += size;
          final meta = voiceLabels[name];
          buckets.add(StorageBucket(
            key: 'voice_model:$name',
            label: meta?.$1 ?? '语音模型 · $name',
            hint: meta?.$2 ?? 'voice_models/$name',
            bytes: size,
            category: 'file',
            canClean: true,
          ));
        }
        // 顶层散落文件
        if (vmTotal == 0) {
          vmTotal = await dirSize(vmRoot);
        }
        // 若子项已计入，不把 root 再加一遍；filesBytes 用 vmTotal
        final already = buckets
            .where((b) => b.key.startsWith('voice_model:'))
            .fold<int>(0, (s, b) => s + b.bytes);
        if (already < vmTotal) {
          filesBytes += vmTotal - already;
        } else {
          filesBytes += already;
        }
      }

      // 其余顶层目录 / 文件
      await for (final e in docs.list(followLinks: false)) {
        final name = p.basename(e.path);
        if (name == 'voice_models') continue; // 已单独统计
        if (e is Directory) {
          final meta = dirMeta[name];
          await addDirBucket(
            name,
            'dir_$name',
            meta?.$1 ?? name,
            meta?.$2 ?? '应用文档目录 $name',
            // flutter_assets 永不可清：debug 引擎 JIT kernel 在此
            cleanable: name != 'flutter_assets',
          );
        } else if (e is File) {
          int size = 0;
          try {
            size = await e.length();
          } catch (_) {}
          if (size <= 0) continue;
          filesBytes += size;
          final isHive = name.endsWith('.hive') || name.endsWith('.lock');
          buckets.add(StorageBucket(
            key: 'file_$name',
            label: isHive ? '本地库 · $name' : '散落文件 · $name',
            hint: isHive
                ? '删除可能导致功能异常，一般请保留'
                : 'app 文档根目录文件',
            bytes: size,
            category: 'file',
            canClean: false,
          ));
        }
      }
    }

    // 数据库目录（solace.db + wal/journal）
    try {
      final dbDirPath = await getDatabasesPath();
      final dbDir = Directory(dbDirPath);
      if (await dbDir.exists()) {
        await for (final e in dbDir.list(followLinks: false)) {
          if (e is! File) continue;
          final name = p.basename(e.path);
          int size = 0;
          try {
            size = await e.length();
          } catch (_) {}
          if (size <= 0) continue;
          if (name == 'solace.db') {
            // 已有 db_file 桶，避免重复；只保证 dbBytes 不为 0
            if (dbBytes == 0) dbBytes = size;
            continue;
          }
          filesBytes += size;
          buckets.add(StorageBucket(
            key: 'db_side:$name',
            label: '数据库附属 · $name',
            hint: 'WAL/日志，VACUUM 或关闭库后通常缩小',
            bytes: size,
            category: 'file',
            canClean: false,
          ));
        }
      }
    } catch (e) {
      debugPrint('analyze databases dir failed: $e');
    }

    // 缓存目录
    try {
      final cache = await getTemporaryDirectory();
      final cacheSize = await dirSize(cache);
      if (cacheSize > 0) {
        filesBytes += cacheSize;
        buckets.add(StorageBucket(
          key: 'dir_cache_tmp',
          label: '系统缓存目录',
          hint: '临时文件，可安全清理',
          bytes: cacheSize,
          category: 'file',
          canClean: true,
        ));
      }
    } catch (e) {
      debugPrint('analyze cache failed: $e');
    }

    buckets.add(StorageBucket(
      key: 'reasoning_fields',
      label: '思考过程字段',
      hint: '清空所有消息 reasoning，不删正文',
      bytes: 0,
      category: 'system',
    ));
    buckets.add(StorageBucket(
      key: 'db_file',
      label: '压缩数据库',
      hint: 'VACUUM 回收删除后的空洞',
      bytes: dbBytes,
      category: 'system',
    ));

    return StorageAnalysis(
      buckets: buckets,
      totalBytes: dbBytes + filesBytes,
      dbBytes: dbBytes,
      filesBytes: filesBytes,
    );
  }

  static Future<int> _dbFileSize() async {
    try {
      final path = await getDatabasesPath();
      final f = File(p.join(path, 'solace.db'));
      if (await f.exists()) return await f.length();
    } catch (_) {}
    return 0;
  }

  /// 清理一个 bucket key；session/character 前缀会走专用逻辑
  static Future<int> clean(
    LocalStorageRepository storage,
    String key, {
    int keepDays = 30,
    int keepMessagesPerChat = 200,
  }) async {
    final db = storage.database;

    // 会话级：chat:xxx / group:xxx
    if (key.startsWith('chat:')) {
      return _cleanChatSession(db, key.substring(5),
          keepDays: keepDays, keepPerChat: keepMessagesPerChat);
    }
    if (key.startsWith('group:')) {
      return _cleanGroupSession(db, key.substring(6), keepDays: keepDays);
    }
    // 角色记忆：mem:xxx
    if (key.startsWith('mem:')) {
      return _cleanCharacterMemories(db, key.substring(4), keepDays: keepDays);
    }

    switch (key) {
      case 'table_pure_ai_messages':
        return _deleteTableOlderThan(
            db, 'pure_ai_messages', 'createdAt', keepDays);
      case 'table_ai_letters':
        return _deleteTableOlderThan(db, 'ai_letters', 'createdAt', keepDays);
      case 'table_inner_thoughts':
        return _deleteTable(db, 'inner_thoughts');
      case 'table_growth_events':
        return _deleteTableOlderThan(
            db, 'growth_events', 'createdAt', keepDays);
      case 'table_persona_snapshots':
        return _deleteWhere(
            db, 'persona_snapshots', "snapshotType != 'initial'");
      case 'table_usage_records':
        return _deleteTableOlderThan(db, 'usage_records', 'createdAt', 7);
      case 'table_moments':
        return _purgeOldMoments(db, keepDays: keepDays);
      case 'table_social_memories':
        return _deleteTableOlderThan(
            db, 'social_memories', 'timestamp', keepDays * 3);
      case 'dir_ai_avatars':
      case 'dir_virtual_phone':
      case 'dir_voice':
      case 'dir_diary':
      case 'dir_avatars':
      case 'dir_chat_images':
      case 'dir_profile_backgrounds':
      case 'dir_backup_files':
        final name = key.replaceFirst('dir_', '');
        return _cleanDirSubdir(name);
      case 'dir_flutter_assets':
        // 引擎运行时，拒绝清理（防止旧选中态/误调用导致黑屏）
        debugPrint('refuse clean flutter_assets: engine runtime');
        return 0;
      case 'dir_cache_tmp':
        return _cleanTempCache();
      case 'db_file':
        await _vacuum(db);
        return 0;
      case 'reasoning_fields':
        return clearReasoningFields(db);
      default:
        if (key.startsWith('voice_model:')) {
          return _cleanVoiceModel(key.substring('voice_model:'.length));
        }
        if (key.startsWith('file_') && key.endsWith('.hive')) {
          // hive 数据文件：清空会丢对应业务数据，仅当用户显式勾选
          return _cleanDocsFile(key.substring(5));
        }
        return 0;
    }
  }

  /// 批量清理
  static Future<int> cleanMany(
    LocalStorageRepository storage,
    Iterable<String> keys, {
    int keepDays = 30,
    int keepMessagesPerChat = 200,
    bool vacuumAfter = true,
  }) async {
    var total = 0;
    var didDbClean = false;
    for (final key in keys) {
      try {
        if (!key.startsWith('db_file')) didDbClean = true;
        total += await clean(
          storage,
          key,
          keepDays: keepDays,
          keepMessagesPerChat: keepMessagesPerChat,
        );
      } catch (e) {
        debugPrint('cleanMany $key failed: $e');
      }
    }
    if (vacuumAfter && didDbClean) {
      await clean(storage, 'db_file');
    }
    return total;
  }

  static Future<int> _cleanChatSession(
    Database? db,
    String chatId, {
    required int keepDays,
    required int keepPerChat,
  }) async {
    if (db == null) return 0;
    try {
      final before = await _sumBytesWhere(db, 'chat_messages',
          where: 'chatId = ?',
          args: [chatId],
          expr:
              "length(content)+COALESCE(length(reasoning),0)+COALESCE(length(metadata),0)");
      await db.rawDelete(
        "DELETE FROM chat_messages WHERE chatId = ? AND isBookmark != 1 AND "
        "createdAt < datetime('now', '-$keepDays days')",
        [chatId],
      );
      await db.rawDelete('''
        DELETE FROM chat_messages
        WHERE chatId = ? AND isBookmark != 1 AND id NOT IN (
          SELECT id FROM chat_messages WHERE chatId = ?
          ORDER BY createdAt DESC LIMIT $keepPerChat
        )
      ''', [chatId, chatId]);
      final after = await _sumBytesWhere(db, 'chat_messages',
          where: 'chatId = ?',
          args: [chatId],
          expr:
              "length(content)+COALESCE(length(reasoning),0)+COALESCE(length(metadata),0)");
      return (before - after).clamp(0, 1 << 40);
    } catch (e) {
      debugPrint('clean chat $chatId failed: $e');
      return 0;
    }
  }

  static Future<int> _cleanGroupSession(
    Database? db,
    String groupId, {
    required int keepDays,
  }) async {
    if (db == null) return 0;
    try {
      final before = await _sumBytesWhere(db, 'group_chat_messages',
          where: 'groupId = ?',
          args: [groupId],
          expr: 'length(content)+COALESCE(length(metadata),0)');
      await db.rawDelete(
        "DELETE FROM group_chat_messages WHERE groupId = ? AND "
        "createdAt < datetime('now', '-$keepDays days')",
        [groupId],
      );
      final after = await _sumBytesWhere(db, 'group_chat_messages',
          where: 'groupId = ?',
          args: [groupId],
          expr: 'length(content)+COALESCE(length(metadata),0)');
      return (before - after).clamp(0, 1 << 40);
    } catch (e) {
      debugPrint('clean group $groupId failed: $e');
      return 0;
    }
  }

  static Future<int> _cleanCharacterMemories(
    Database? db,
    String characterId, {
    required int keepDays,
  }) async {
    if (db == null) return 0;
    try {
      final before = await _sumBytesWhere(db, 'memories',
          where: 'characterId = ?',
          args: [characterId],
          expr: 'length(content)');
      // 保留 pinned / crucial，删低重要性旧记忆
      await db.rawDelete(
        "DELETE FROM memories WHERE characterId = ? AND pinned != 1 "
        "AND importance <= 1 AND "
        "createdAt < datetime('now', '-$keepDays days')",
        [characterId],
      );
      final after = await _sumBytesWhere(db, 'memories',
          where: 'characterId = ?',
          args: [characterId],
          expr: 'length(content)');
      return (before - after).clamp(0, 1 << 40);
    } catch (e) {
      debugPrint('clean memories $characterId failed: $e');
      return 0;
    }
  }

  static Future<int> _sumBytesWhere(
    Database db,
    String table, {
    required String where,
    required List<Object?> args,
    required String expr,
  }) async {
    try {
      final r = await db.rawQuery(
          'SELECT COALESCE(SUM($expr),0) AS s FROM $table WHERE $where', args);
      return ((r.first['s'] as num?) ?? 0).toInt();
    } catch (_) {
      return 0;
    }
  }

  static Future<int> _purgeOldMoments(
    Database? db, {
    required int keepDays,
  }) async {
    if (db == null) return 0;
    try {
      await db.rawDelete(
        "DELETE FROM moments WHERE isFromAI = 1 AND "
        "createdAt < datetime('now', '-$keepDays days')",
      );
    } catch (e) {
      debugPrint('purge moments failed: $e');
    }
    return 0;
  }

  static Future<int> _deleteTable(Database? db, String table) async {
    if (db == null) return 0;
    try {
      final before = await _sumBytesWhere(db, table,
          where: '1=1', args: const [], expr: 'length(content)');
      await db.delete(table);
      return before.clamp(0, 1 << 40);
    } catch (e) {
      debugPrint('delete $table failed: $e');
      return 0;
    }
  }

  static Future<int> _deleteTableOlderThan(
    Database? db,
    String table,
    String dateCol,
    int days,
  ) async {
    if (db == null) return 0;
    try {
      final before = await _sumBytesWhere(db, table,
          where: "$dateCol < datetime('now', '-$days days')",
          args: const [],
          expr: 'length(content)');
      await db.rawDelete(
          "DELETE FROM $table WHERE $dateCol < datetime('now', '-$days days')");
      return before.clamp(0, 1 << 40);
    } catch (e) {
      debugPrint('purge $table failed: $e');
      return 0;
    }
  }

  static Future<int> _deleteWhere(
      Database? db, String table, String where) async {
    if (db == null) return 0;
    try {
      final before = await _sumBytesWhere(db, table,
          where: where, args: const [], expr: 'length(content)');
      await db.rawDelete('DELETE FROM $table WHERE $where');
      return before.clamp(0, 1 << 40);
    } catch (e) {
      debugPrint('deleteWhere $table failed: $e');
      return 0;
    }
  }

  static Future<int> _cleanDirSubdir(String name) async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(docs.path, name));
      if (!await dir.exists()) return 0;
      var freed = 0;
      await for (final f in dir.list(recursive: true, followLinks: false)) {
        if (f is File) {
          try {
            final len = await f.length();
            await f.delete();
            freed += len;
          } catch (_) {}
        }
      }
      return freed;
    } catch (e) {
      debugPrint('clean dir $name failed: $e');
      return 0;
    }
  }

  /// 删除 voice_models/<subdir>（如 zipvoice / sensevoice）
  static Future<int> _cleanVoiceModel(String subdir) async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(docs.path, 'voice_models', subdir));
      if (!await dir.exists()) return 0;
      var freed = 0;
      await for (final f in dir.list(recursive: true, followLinks: false)) {
        if (f is File) {
          try {
            freed += await f.length();
          } catch (_) {}
        }
      }
      await dir.delete(recursive: true);
      return freed;
    } catch (e) {
      debugPrint('clean voice model $subdir failed: $e');
      return 0;
    }
  }

  /// 清空系统临时目录
  static Future<int> _cleanTempCache() async {
    try {
      final cache = await getTemporaryDirectory();
      if (!await cache.exists()) return 0;
      var freed = 0;
      await for (final f in cache.list(recursive: true, followLinks: false)) {
        if (f is File) {
          try {
            final len = await f.length();
            await f.delete();
            freed += len;
          } catch (_) {}
        }
      }
      return freed;
    } catch (e) {
      debugPrint('clean temp cache failed: $e');
      return 0;
    }
  }

  /// 删除 app 文档根目录下的单个文件
  static Future<int> _cleanDocsFile(String name) async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final f = File(p.join(docs.path, name));
      if (!await f.exists()) return 0;
      final len = await f.length();
      await f.delete();
      return len;
    } catch (e) {
      debugPrint('clean file $name failed: $e');
      return 0;
    }
  }

  static Future<void> _vacuum(Database? db) async {
    if (db == null) return;
    try {
      await db.execute('VACUUM');
    } catch (e) {
      debugPrint('VACUUM failed: $e');
    }
  }

  static Future<int> clearReasoningFields(Database? db) async {
    if (db == null) return 0;
    try {
      final r = await db.rawQuery(
          "SELECT COALESCE(SUM(length(reasoning)),0) AS s FROM chat_messages "
          "WHERE reasoning IS NOT NULL AND reasoning != ''");
      final before = ((r.first['s'] as num?) ?? 0).toInt();
      await db.rawUpdate(
          "UPDATE chat_messages SET reasoning = NULL WHERE reasoning IS NOT NULL AND reasoning != ''");
      return before.clamp(0, 1 << 40);
    } catch (e) {
      debugPrint('clear reasoning failed: $e');
      return 0;
    }
  }
}
