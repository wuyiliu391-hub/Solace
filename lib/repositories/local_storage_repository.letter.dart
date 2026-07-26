part of 'local_storage_repository.dart';

/// AI 信件相关数据访问（AI Letters）。
///
/// 从 [LocalStorageRepository] 拆分而来（part + extension），调用方无需改动；
/// 与主文件同库，可访问 _ensureDb() / _prefs / _isWeb 等私有成员。
extension StorageLetterDao on LocalStorageRepository {
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

  Future<void> markAILetterRead(String id) async {
    final readAt = DateTime.now().toIso8601String();
    if (_isWeb) {
      final letter = await getAILetter(id);
      if (letter == null) return;
      await _prefs?.setString(
        'ai_letter_$id',
        jsonEncode(letter
            .copyWith(isRead: true, readAt: DateTime.parse(readAt))
            .toMap()),
      );
      return;
    }
    final db = await _ensureDb();
    await db.update(
      'ai_letters',
      {'isRead': 1, 'readAt': readAt},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteAILetter(String id) async {
    if (_isWeb) {
      final letter = await getAILetter(id);
      await _prefs?.remove('ai_letter_$id');
      if (letter != null) {
        final key = 'ai_letter_ids_${letter.userId}';
        final ids = _prefs?.getStringList(key) ?? [];
        ids.remove(id);
        await _prefs?.setStringList(key, ids);
      }
      return;
    }
    final db = await _ensureDb();
    await db.delete('ai_letters', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> getUnreadAILetterCount(String userId) async {
    if (_isWeb) {
      final letters = await getAILetters(userId: userId, limit: 9999);
      return letters.where((l) => !l.isRead).length;
    }
    final db = await _ensureDb();
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS count FROM ai_letters WHERE userId = ? AND isRead = 0',
      [userId],
    );
    return (rows.first['count'] as int?) ?? 0;
  }

  Future<List<AILetter>> getPendingReplyLetters(String userId) async {
    if (_isWeb) {
      final letters = await getAILetters(userId: userId, limit: 9999);
      return letters.where((l) => l.needsReply).toList();
    }
    final db = await _ensureDb();
    final maps = await db.query(
      'ai_letters',
      where: 'userId = ? AND needsReply = 1',
      whereArgs: [userId],
      orderBy: 'createdAt ASC',
    );
    return maps.map((m) => AILetter.fromMap(m)).toList();
  }

  Future<void> markAILetterReplied(String id) async {
    if (_isWeb) {
      final letter = await getAILetter(id);
      if (letter == null) return;
      await _prefs?.setString(
        'ai_letter_$id',
        jsonEncode(letter.copyWith(needsReply: false).toMap()),
      );
      return;
    }
    final db = await _ensureDb();
    await db.update(
      'ai_letters',
      {'needsReply': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
