part of 'local_storage_repository.dart';

/// 纯 AI 会话 / 消息相关数据访问（Pure AI）。
///
/// 从 [LocalStorageRepository] 拆分而来（part + extension），调用方无需改动；
/// 与主文件同库，可访问 _ensureDb() / _prefs / _isWeb 等私有成员。
extension StoragePureAiDao on LocalStorageRepository {
  // ==================== Pure AI ====================

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
}
