// 【对标来源：SillyTavern-1.18.0 — public/scripts/world-info.js 世界观管理】
// 1:1 转译自 SillyTavern World Info 书本/条目 CRUD 逻辑
// 参考文件：public/scripts/world-info.js (loadWorldInfo、saveWorldInfo、deleteWorldInfo)

import "dart:convert";
import "package:uuid/uuid.dart";
import "../models/character_card_v2.dart";
import "database_service.dart";

/// 世界观仓库（对标 SillyTavern World Info 管理）
/// 完整保留 SillyTavern 的书本/条目 CRUD、选择性激活、递归扫描逻辑
class WorldInfoRepository {
  static WorldInfoRepository? _instance;
  static WorldInfoRepository get instance =>
      _instance ??= WorldInfoRepository._();
  WorldInfoRepository._();

  final DatabaseService _db = DatabaseService.instance;
  static const _uuid = Uuid();

  // ──────────── 书本 CRUD ────────────

  /// 创建世界观书本（对标 SillyTavern createNewWorldInfo）
  Future<String> createBook({
    required String name,
    String description = '',
    String? scanDepth,
    String? tokenBudget,
    String? recursiveScanning,
  }) async {
    final db = await _db.database;
    final id = _uuid.v4();
    final now = DateTime.now().toIso8601String();

    await db.insert('world_info_books', {
      'id': id,
      'name': name,
      'description': description,
      'scanDepth': scanDepth,
      'tokenBudget': tokenBudget,
      'recursiveScanning': recursiveScanning,
      'createdAt': now,
    });

    return id;
  }

  /// 获取世界观书本（对标 SillyTavern getWorldInfoSettings）
  Future<WorldInfoBook?> getBook(String bookId) async {
    final db = await _db.database;
    final rows = await db.query(
      'world_info_books',
      where: 'id = ?',
      whereArgs: [bookId],
      limit: 1,
    );

    if (rows.isEmpty) return null;

    final entries = await getEntries(bookId);
    return WorldInfoBook(
      entries: entries,
      name: rows.first['name'] as String? ?? '',
      description: rows.first['description'] as String? ?? '',
      scanDepth: rows.first['scanDepth'] as String?,
      tokenBudget: rows.first['tokenBudget'] as String?,
      recursiveScanning: rows.first['recursiveScanning'] as String?,
    );
  }

  /// 获取所有世界观书本（对标 SillyTavern world_names）
  Future<List<Map<String, dynamic>>> getAllBooks() async {
    final db = await _db.database;
    final rows = await db.query('world_info_books', orderBy: 'name ASC');
    return rows
        .map((r) => {
              'id': r['id'] as String,
              'name': r['name'] as String? ?? '',
              'description': r['description'] as String? ?? '',
            })
        .toList();
  }

  /// 更新世界观书本（对标 SillyTavern saveWorldInfoSettings）
  Future<void> updateBook(
    String bookId, {
    String? name,
    String? description,
    String? scanDepth,
    String? tokenBudget,
    String? recursiveScanning,
  }) async {
    final db = await _db.database;
    final updates = <String, dynamic>{};
    if (name != null) updates['name'] = name;
    if (description != null) updates['description'] = description;
    if (scanDepth != null) updates['scanDepth'] = scanDepth;
    if (tokenBudget != null) updates['tokenBudget'] = tokenBudget;
    if (recursiveScanning != null) {
      updates['recursiveScanning'] = recursiveScanning;
    }

    if (updates.isNotEmpty) {
      await db.update('world_info_books', updates,
          where: 'id = ?', whereArgs: [bookId]);
    }
  }

  /// 删除世界观书本（对标 SillyTavern deleteWorldInfo）
  /// 级联删除所有条目
  Future<void> deleteBook(String bookId) async {
    final db = await _db.database;
    await db.delete('world_info_entries',
        where: 'bookId = ?', whereArgs: [bookId]);
    await db.delete('world_info_books',
        where: 'id = ?', whereArgs: [bookId]);
  }

  // ──────────── 条目 CRUD ────────────

  /// 创建世界观条目（对标 SillyTavern createWorldInfoEntry）
  Future<String> createEntry({
    required String bookId,
    String comment = '',
    String content = '',
    List<String> key = const [],
    List<String> keysecondary = const [],
    bool constant = false,
    bool vectorized = false,
    bool selective = false,
    bool disable = false,
    int position = 0,
    int depth = 4,
    int order = 100,
    int probability = 100,
    bool useGroupScoring = false,
    int scanDepth = 0,
    bool caseSensitive = false,
    bool matchWholeWords = false,
    bool excludeRecursion = false,
    bool preventRecursion = false,
    int delayUntilRecursion = 0,
    int? sticky,
    int? cooldown,
    int? delay,
    String? outletName,
    int role = 0,
    int entryLogicType = 0,
    List<String>? triggers,
    String? automationId,
  }) async {
    final db = await _db.database;
    final id = _uuid.v4();
    // uid 用于 SillyTavern 兼容的 JSON 导入导出
    final uid = DateTime.now().millisecondsSinceEpoch.toString();

    await db.insert('world_info_entries', {
      'id': id,
      'bookId': bookId,
      'uid': uid,
      'comment': comment,
      'content': content,
      'keyList': jsonEncode(key),
      'keysecondaryList': jsonEncode(keysecondary),
      'constant': constant ? 1 : 0,
      'vectorized': vectorized ? 1 : 0,
      'selective': selective ? 1 : 0,
      'disable': disable ? 1 : 0,
      'position': position,
      'depth': depth,
      'sortOrder': order,
      'probability': probability,
      'useGroupScoring': useGroupScoring ? 1 : 0,
      'scanDepth': scanDepth,
      'caseSensitive': caseSensitive ? 1 : 0,
      'matchWholeWords': matchWholeWords ? 1 : 0,
      'excludeRecursion': excludeRecursion ? 1 : 0,
      'preventRecursion': preventRecursion ? 1 : 0,
      'delayUntilRecursion': delayUntilRecursion,
      'sticky': sticky,
      'cooldown': cooldown,
      'delay': delay,
      'outletName': outletName,
      'role': role,
      'entryLogicType': entryLogicType,
      'triggers': triggers != null ? jsonEncode(triggers) : null,
      'automationId': automationId,
    });

    return id;
  }

  /// 获取书本所有条目（对标 SillyTavern getWorldInfoEntries）
  Future<List<WorldInfoEntry>> getEntries(String bookId) async {
    final db = await _db.database;
    final rows = await db.query(
      'world_info_entries',
      where: 'bookId = ?',
      whereArgs: [bookId],
      orderBy: 'sortOrder ASC',
    );

    return rows.map(_rowToEntry).toList();
  }

  /// 获取单个条目
  Future<WorldInfoEntry?> getEntry(String entryId) async {
    final db = await _db.database;
    final rows = await db.query(
      'world_info_entries',
      where: 'id = ?',
      whereArgs: [entryId],
      limit: 1,
    );

    if (rows.isEmpty) return null;
    return _rowToEntry(rows.first);
  }

  /// 更新世界观条目（对标 SillyTavern saveWorldInfoEntry）
  Future<void> updateEntry(String entryId, WorldInfoEntry entry) async {
    final db = await _db.database;
    await db.update(
      'world_info_entries',
      {
        'comment': entry.comment,
        'content': entry.content,
        'keyList': jsonEncode(entry.key),
        'keysecondaryList': jsonEncode(entry.keysecondary),
        'constant': entry.constant ? 1 : 0,
        'vectorized': entry.vectorized ? 1 : 0,
        'selective': entry.selective ? 1 : 0,
        'disable': entry.disable ? 1 : 0,
        'position': entry.position,
        'depth': entry.depth,
        'sortOrder': entry.order,
        'probability': entry.probability,
        'useGroupScoring': entry.useGroupScoring ? 1 : 0,
        'scanDepth': entry.scanDepth,
        'caseSensitive': entry.caseSensitive ? 1 : 0,
        'matchWholeWords': entry.matchWholeWords ? 1 : 0,
        'excludeRecursion': entry.excludeRecursion ? 1 : 0,
        'preventRecursion': entry.preventRecursion ? 1 : 0,
        'delayUntilRecursion': entry.delayUntilRecursion,
        'sticky': entry.sticky,
        'cooldown': entry.cooldown,
        'delay': entry.delay,
        'outletName': entry.outletName,
        'role': entry.role,
        'entryLogicType': entry.entryLogicType,
        'triggers': entry.triggers != null
            ? jsonEncode(entry.triggers)
            : null,
        'automationId': entry.automationId,
      },
      where: 'id = ?',
      whereArgs: [entryId],
    );
  }

  /// 删除世界观条目（对标 SillyTavern deleteWorldInfoEntry）
  Future<void> deleteEntry(String entryId) async {
    final db = await _db.database;
    await db.delete('world_info_entries',
        where: 'id = ?', whereArgs: [entryId]);
  }

  // ──────────── 导入导出（对标 SillyTavern WI JSON 格式） ────────────

  /// 从 SillyTavern 格式 JSON 导入书本
  Future<String> importBookFromJson(Map<String, dynamic> json) async {
    final bookId = await createBook(
      name: json['name'] as String? ?? '导入的世界观',
      description: json['description'] as String? ?? '',
      scanDepth: json['scanDepth'] as String?,
      tokenBudget: json['tokenBudget'] as String?,
      recursiveScanning: json['recursiveScanning'] as String?,
    );

    final entries = json['entries'] as List<dynamic>? ?? [];
    for (final entryJson in entries) {
      final entryMap = entryJson as Map<String, dynamic>;
      await createEntry(
        bookId: bookId,
        comment: entryMap['comment'] as String? ?? '',
        content: entryMap['content'] as String? ?? '',
        key: (entryMap['key'] as List<dynamic>?)?.cast<String>() ?? [],
        keysecondary:
            (entryMap['keysecondary'] as List<dynamic>?)?.cast<String>() ??
                [],
        constant: entryMap['constant'] as bool? ?? false,
        vectorized: entryMap['vectorized'] as bool? ?? false,
        selective: entryMap['selective'] as bool? ?? false,
        disable: entryMap['disable'] as bool? ?? false,
        position: entryMap['position'] as int? ?? 0,
        depth: entryMap['depth'] as int? ?? 4,
        order: entryMap['order'] as int? ?? 100,
        probability: entryMap['probability'] as int? ?? 100,
        useGroupScoring:
            entryMap['useGroupScoring'] as bool? ?? false,
        scanDepth: entryMap['scanDepth'] as int? ?? 0,
        caseSensitive: entryMap['caseSensitive'] as bool? ?? false,
        matchWholeWords:
            entryMap['matchWholeWords'] as bool? ?? false,
        excludeRecursion:
            entryMap['excludeRecursion'] as bool? ?? false,
        preventRecursion:
            entryMap['preventRecursion'] as bool? ?? false,
        delayUntilRecursion:
            entryMap['delayUntilRecursion'] as int? ?? 0,
        sticky: entryMap['sticky'] as int?,
        cooldown: entryMap['cooldown'] as int?,
        delay: entryMap['delay'] as int?,
        outletName: entryMap['outletName'] as String?,
        role: entryMap['role'] as int? ?? 0,
        entryLogicType: entryMap['entryLogicType'] as int? ?? 0,
        triggers: (entryMap['triggers'] as List<dynamic>?)
            ?.cast<String>(),
        automationId: entryMap['automationId'] as String?,
      );
    }

    return bookId;
  }

  /// 导出书本为 SillyTavern 格式 JSON
  Future<Map<String, dynamic>> exportBookToJson(String bookId) async {
    final book = await getBook(bookId);
    if (book == null) return {};
    return book.toJson();
  }

  // ──────────── 辅助方法 ────────────

  /// 数据库行转世界观条目
  WorldInfoEntry _rowToEntry(Map<String, dynamic> row) {
    return WorldInfoEntry(
      uid: row['uid'] as String? ?? '',
      comment: row['comment'] as String? ?? '',
      content: row['content'] as String? ?? '',
      key: (jsonDecode(row['keyList'] as String? ?? '[]') as List<dynamic>)
          .cast<String>(),
      keysecondary: (jsonDecode(
                  row['keysecondaryList'] as String? ?? '[]')
              as List<dynamic>)
          .cast<String>(),
      constant: (row['constant'] as int? ?? 0) == 1,
      vectorized: (row['vectorized'] as int? ?? 0) == 1,
      selective: (row['selective'] as int? ?? 0) == 1,
      disable: (row['disable'] as int? ?? 0) == 1,
      position: row['position'] as int? ?? 0,
      depth: row['depth'] as int? ?? 4,
      order: row['sortOrder'] as int? ?? 100,
      probability: row['probability'] as int? ?? 100,
      useGroupScoring:
          (row['useGroupScoring'] as int? ?? 0) == 1,
      scanDepth: row['scanDepth'] as int? ?? 0,
      caseSensitive:
          (row['caseSensitive'] as int? ?? 0) == 1,
      matchWholeWords:
          (row['matchWholeWords'] as int? ?? 0) == 1,
      excludeRecursion:
          (row['excludeRecursion'] as int? ?? 0) == 1,
      preventRecursion:
          (row['preventRecursion'] as int? ?? 0) == 1,
      delayUntilRecursion:
          row['delayUntilRecursion'] as int? ?? 0,
      sticky: row['sticky'] as int?,
      cooldown: row['cooldown'] as int?,
      delay: row['delay'] as int?,
      outletName: row['outletName'] as String?,
      role: row['role'] as int? ?? 0,
      entryLogicType: row['entryLogicType'] as int? ?? 0,
      triggers: row['triggers'] != null
          ? (jsonDecode(row['triggers'] as String) as List<dynamic>)
              .cast<String>()
          : null,
      automationId: row['automationId'] as String?,
    );
  }
}
