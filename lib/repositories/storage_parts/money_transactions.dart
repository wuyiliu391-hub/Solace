// LocalStorageRepository 转账/红包流水 CRUD（v71 微信钱系统）。
// 本文件是 local_storage_repository.dart 的 part，与其共同构成一个库。
// 资金安全铁律：所有扣款/入账必须包在事务里，失败整体回滚。

part of '../local_storage_repository.dart';

/// 转账/红包流水表建表 SQL（v71）
const String createMoneyTransactionsSql =
    ''' CREATE TABLE IF NOT EXISTS money_transactions ( id TEXT PRIMARY KEY, kind TEXT NOT NULL DEFAULT 'transfer', userToCharacter INTEGER NOT NULL DEFAULT 1, chatId TEXT NOT NULL, messageId TEXT NOT NULL, characterId TEXT NOT NULL, userId TEXT NOT NULL, amount INTEGER NOT NULL DEFAULT 0, note TEXT, status TEXT NOT NULL DEFAULT 'pending', receiverName TEXT, createdAt TEXT NOT NULL, actedAt TEXT, expireAt TEXT NOT NULL, sync_seq INTEGER NOT NULL DEFAULT 0 ) ''';

mixin LocalStorageRepositoryMoneyApi on LocalStorageRepositoryBtVPhoneApi {
  Future<void> saveMoneyTransaction(MoneyTransaction tx) async {
    final db = await _ensureDb();
    await db.insert(
      'money_transactions',
      tx.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<MoneyTransaction?> getMoneyTransaction(String id) async {
    final db = await _ensureDb();
    final rows = await db
        .query('money_transactions', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return MoneyTransaction.fromMap(rows.first);
  }

  Future<MoneyTransaction?> getMoneyTransactionByMessage(
      String messageId) async {
    final db = await _ensureDb();
    final rows = await db.query('money_transactions',
        where: 'messageId = ?', whereArgs: [messageId]);
    if (rows.isEmpty) return null;
    return MoneyTransaction.fromMap(rows.first);
  }

  Future<void> updateMoneyTransactionStatus(
    String id,
    MoneyStatus status, {
    DateTime? actedAt,
  }) async {
    final db = await _ensureDb();
    await db.update(
      'money_transactions',
      {
        'status': status.name,
        if (actedAt != null) 'actedAt': actedAt.toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 最近 [limit] 条流水（账单页），按时间倒序
  Future<List<MoneyTransaction>> getMoneyTransactions({
    String? userId,
    int limit = 100,
  }) async {
    final db = await _ensureDb();
    final rows = await db.query(
      'money_transactions',
      where: userId != null ? 'userId = ?' : null,
      whereArgs: userId != null ? [userId] : null,
      orderBy: 'createdAt DESC',
      limit: limit,
    );
    return rows.map(MoneyTransaction.fromMap).toList();
  }
}
