import 'package:sqflite/sqflite.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';
import '../models/ai_wallet.dart';
import '../config/constants.dart';

/// LocalStorageRepository 的用户和钱包相关方法 mixin
mixin StorageUserMixin {
  Future<Database> ensureDb();
  SharedPreferences? get prefs;

  // ── 用户 CRUD ──

  Future<void> saveUser(User user) async {
    final db = await ensureDb();
    await db.insert(
      'users',
      user.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<User?> getUser(String id) async {
    final db = await ensureDb();
    final maps = await db.query('users', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return User.fromMap(maps.first);
  }

  Future<User?> getCurrentUser() async {
    final userId = prefs?.getString(PrefKeys.currentUserId);
    if (userId == null) return null;
    return getUser(userId);
  }

  Future<bool> spendCoins(String userId, int amount) async {
    final user = await getUser(userId);
    if (user == null || user.coins < amount) return false;
    final db = await ensureDb();
    await db.update(
      'users',
      {'coins': user.coins - amount},
      where: 'id = ?',
      whereArgs: [userId],
    );
    return true;
  }

  Future<void> addCoins(String userId, int amount) async {
    final user = await getUser(userId);
    if (user == null) return;
    final db = await ensureDb();
    await db.update(
      'users',
      {'coins': user.coins + amount},
      where: 'id = ?',
      whereArgs: [userId],
    );
  }

  // ── AI 钱包 ──

  Future<AIWallet?> getAIWallet(String characterId) async {
    final db = await ensureDb();
    final maps = await db.query(
      'ai_wallets',
      where: 'characterId = ?',
      whereArgs: [characterId],
    );
    if (maps.isEmpty) return null;
    return AIWallet.fromMap(maps.first);
  }

  Future<AIWallet> getOrCreateAIWallet(String characterId) async {
    var wallet = await getAIWallet(characterId);
    wallet ??= AIWallet(characterId: characterId);
    return wallet;
  }

  Future<void> saveAIWallet(AIWallet wallet) async {
    final db = await ensureDb();
    await db.insert(
      'ai_wallets',
      wallet.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<bool> addAICoins(String characterId, int amount) async {
    final wallet = await getOrCreateAIWallet(characterId);
    final updated = wallet.copyWith(balance: wallet.balance + amount);
    await saveAIWallet(updated);
    return true;
  }

  Future<bool> deductAICoins(String characterId, int amount) async {
    final wallet = await getOrCreateAIWallet(characterId);
    if (wallet.balance < amount) return false;
    final updated = wallet.copyWith(balance: wallet.balance - amount);
    await saveAIWallet(updated);
    return true;
  }

  Future<void> updateAISpendingPersonality(
      String characterId, int personality) async {
    final wallet = await getOrCreateAIWallet(characterId);
    final updated = wallet.copyWith(spendingPersonality: personality);
    await saveAIWallet(updated);
  }

  Future<void> resetAIDailySpent(String characterId) async {
    final wallet = await getOrCreateAIWallet(characterId);
    final updated = wallet.copyWith(dailySpent: 0);
    await saveAIWallet(updated);
  }

  Future<List<AIWallet>> getAllAIWallets() async {
    final db = await ensureDb();
    final maps = await db.query('ai_wallets');
    return maps.map((m) => AIWallet.fromMap(m)).toList();
  }
}
