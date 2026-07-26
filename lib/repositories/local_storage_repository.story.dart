part of 'local_storage_repository.dart';

/// 故事书相关数据访问（Story Books / Segments / Scenes / Saves）。
///
/// 从 [LocalStorageRepository] 拆分而来：通过 extension 挂在同一个类上，
/// 调用方无需任何改动。part 文件与主文件同属一个库，因此可访问
/// `_ensureDb()` 等私有成员；所需的模型类与 sqflite 由主文件 import 共享。
extension StorageStoryDao on LocalStorageRepository {
  // ==================== 故事书 Story Books ====================

  Future<void> saveStoryBook(StoryBook book) async {
    final db = await _ensureDb();
    await db.insert('story_books', book.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<StoryBook?> getStoryBook(String id) async {
    final db = await _ensureDb();
    final maps =
        await db.query('story_books', where: 'id = ?', whereArgs: [id]);
    return maps.isNotEmpty ? StoryBook.fromMap(maps.first) : null;
  }

  Future<List<StoryBook>> getStoryBooks(String userId,
      {bool includeArchived = false}) async {
    final db = await _ensureDb();
    final where = includeArchived
        ? 'userId = ?'
        : 'userId = ? AND isArchived = 0';
    final maps = await db.query('story_books',
        where: where, whereArgs: [userId], orderBy: 'updatedAt DESC');
    return maps.map((m) => StoryBook.fromMap(m)).toList();
  }

  Future<void> deleteStoryBook(String id) async {
    final db = await _ensureDb();
    await db.delete('story_books', where: 'id = ?', whereArgs: [id]);
    await db.delete('story_segments', where: 'storyId = ?', whereArgs: [id]);
    await db.delete('story_scenes', where: 'storyId = ?', whereArgs: [id]);
    await db.delete('story_saves', where: 'storyId = ?', whereArgs: [id]);
    // 记忆按 storyId 存在 memories 表（characterId 维度）
    await db.delete('memories', where: 'characterId = ?', whereArgs: [id]);
  }

  // ==================== 故事书段落 Story Segments ====================

  Future<void> saveStorySegment(StorySegment segment) async {
    final db = await _ensureDb();
    await db.insert('story_segments', segment.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<StorySegment>> getStorySegments(String storyId, String saveId,
      {int? limit, int? offset}) async {
    final db = await _ensureDb();
    final maps = await db.query('story_segments',
        where: 'storyId = ? AND saveId = ?',
        whereArgs: [storyId, saveId],
        orderBy: 'orderIndex ASC',
        limit: limit,
        offset: offset);
    return maps.map((m) => StorySegment.fromMap(m)).toList();
  }

  Future<int> getStorySegmentCount(String storyId, String saveId) async {
    final db = await _ensureDb();
    final result = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM story_segments WHERE storyId = ? AND saveId = ?',
        [storyId, saveId]);
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<void> deleteStorySegment(String id) async {
    final db = await _ensureDb();
    await db.delete('story_segments', where: 'id = ?', whereArgs: [id]);
  }

  /// 删除某存档下所有段落（读档覆盖/回退时用）
  Future<void> deleteStorySegmentsAfter(
      String storyId, String saveId, int orderIndex) async {
    final db = await _ensureDb();
    await db.delete('story_segments',
        where: 'storyId = ? AND saveId = ? AND orderIndex >= ?',
        whereArgs: [storyId, saveId, orderIndex]);
  }

  // ==================== 故事书场景快照 Story Scenes ====================

  Future<void> saveStoryScene(StoryScene scene) async {
    final db = await _ensureDb();
    await db.insert('story_scenes', scene.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<StoryScene?> getStoryScene(String storyId, String saveId) async {
    final db = await _ensureDb();
    final maps = await db.query('story_scenes',
        where: 'storyId = ? AND saveId = ?', whereArgs: [storyId, saveId]);
    return maps.isNotEmpty ? StoryScene.fromMap(maps.first) : null;
  }

  // ==================== 故事书存档 Story Saves ====================

  Future<void> saveStorySave(StorySave save) async {
    final db = await _ensureDb();
    await db.insert('story_saves', save.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<StorySave>> getStorySaves(String storyId) async {
    final db = await _ensureDb();
    final maps = await db.query('story_saves',
        where: 'storyId = ?', whereArgs: [storyId], orderBy: 'updatedAt DESC');
    return maps.map((m) => StorySave.fromMap(m)).toList();
  }

  Future<void> deleteStorySave(String id) async {
    final db = await _ensureDb();
    final saves =
        await db.query('story_saves', where: 'id = ?', whereArgs: [id]);
    if (saves.isEmpty) return;
    final storyId = saves.first['storyId'] as String? ?? '';
    await db.delete('story_saves', where: 'id = ?', whereArgs: [id]);
    await db.delete('story_segments',
        where: 'storyId = ? AND saveId = ?', whereArgs: [storyId, id]);
    await db.delete('story_scenes',
        where: 'storyId = ? AND saveId = ?', whereArgs: [storyId, id]);
  }

  /// 复制存档（含全部段落与场景）到新存档 id
  Future<void> copyStorySaveContents(
      String storyId, String fromSaveId, String toSaveId) async {
    final db = await _ensureDb();
    final segs = await db.query('story_segments',
        where: 'storyId = ? AND saveId = ?', whereArgs: [storyId, fromSaveId]);
    final batch = db.batch();
    for (final s in segs) {
      final m = Map<String, dynamic>.from(s);
      m['saveId'] = toSaveId;
      m['id'] = '${m['id']}_$toSaveId';
      batch.insert('story_segments', m,
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    final scene = await db.query('story_scenes',
        where: 'storyId = ? AND saveId = ?', whereArgs: [storyId, fromSaveId]);
    if (scene.isNotEmpty) {
      final m = Map<String, dynamic>.from(scene.first);
      m['saveId'] = toSaveId;
      batch.insert('story_scenes', m,
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }
}
