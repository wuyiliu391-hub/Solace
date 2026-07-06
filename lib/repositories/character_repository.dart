// 【对标来源：SillyTavern-1.18.0 — script.js 角色操作 + char-data.js 数据结构】
// 1:1 转译自 SillyTavern 角色 CRUD 逻辑
// 参考文件：public/script.js (角色创建/编辑/删除/保存)、public/scripts/char-data.js

import 'dart:convert';
import 'package:uuid/uuid.dart';
import '../models/character_card_v2.dart';
import 'database_service.dart';

/// 角色仓库（对标 SillyTavern 角色 CRUD 操作）
class CharacterRepository {
  static CharacterRepository? _instance;
  static CharacterRepository get instance => _instance ??= CharacterRepository._();
  CharacterRepository._();

  final DatabaseService _db = DatabaseService.instance;
  static const _uuid = Uuid();

  /// 创建角色（对标 SillyTavern 角色创建流程）
  Future<String> createCharacter(CharacterCardV2 card) async {
    final db = await _db.database;
    final id = _uuid.v4();
    final now = DateTime.now().toIso8601String();

    await db.insert('characters', {
      'id': id,
      'name': card.name,
      'description': card.description,
      'characterVersion': card.characterVersion,
      'personality': card.personality,
      'scenario': card.scenario,
      'firstMes': card.firstMes,
      'mesExample': card.mesExample,
      'creatorNotes': card.creatorNotes,
      'tags': jsonEncode(card.tags),
      'systemPrompt': card.systemPrompt,
      'postHistoryInstructions': card.postHistoryInstructions,
      'creator': card.creator,
      'alternateGreetings': jsonEncode(card.alternateGreetings),
      'characterBook':
          card.characterBook != null
              ? jsonEncode(card.characterBook!.toJson())
              : null,
      'extensions': jsonEncode(card.extensions.toJson()),
      'avatarPath': card.avatarPath,
      'createdAt': now,
      'updatedAt': now,
    });

    return id;
  }

  /// 获取角色（对标 SillyTavern 角色加载）
  Future<CharacterCardV2?> getCharacter(String id) async {
    final db = await _db.database;
    final rows = await db.query(
      'characters',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (rows.isEmpty) return null;
    return _rowToCharacter(rows.first);
  }

  /// 获取所有角色（对标 SillyTavern 角色列表）
  Future<List<CharacterCardV2>> getAllCharacters() async {
    final db = await _db.database;
    final rows = await db.query('characters', orderBy: 'updatedAt DESC');
    return rows.map(_rowToCharacter).toList();
  }

  /// 更新角色（对标 SillyTavern 角色编辑保存）
  Future<void> updateCharacter(
      String id, CharacterCardV2 card) async {
    final db = await _db.database;
    await db.update(
      'characters',
      {
        'name': card.name,
        'description': card.description,
        'characterVersion': card.characterVersion,
        'personality': card.personality,
        'scenario': card.scenario,
        'firstMes': card.firstMes,
        'mesExample': card.mesExample,
        'creatorNotes': card.creatorNotes,
        'tags': jsonEncode(card.tags),
        'systemPrompt': card.systemPrompt,
        'postHistoryInstructions': card.postHistoryInstructions,
        'creator': card.creator,
        'alternateGreetings':
            jsonEncode(card.alternateGreetings),
        'characterBook': card.characterBook != null
            ? jsonEncode(card.characterBook!.toJson())
            : null,
        'extensions': jsonEncode(card.extensions.toJson()),
        'avatarPath': card.avatarPath,
        'updatedAt': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 删除角色（对标 SillyTavern 角色删除确认）
  Future<void> deleteCharacter(String id) async {
    final db = await _db.database;
    await db.delete('characters', where: 'id = ?', whereArgs: [id]);
  }

  /// 搜索角色（对标 SillyTavern filters.js 标签过滤）
  Future<List<CharacterCardV2>> searchCharacters({
    String? nameQuery,
    List<String>? tags,
  }) async {
    final db = await _db.database;
    String where = '';
    List<dynamic> args = [];

    if (nameQuery != null && nameQuery.isNotEmpty) {
      where += 'name LIKE ?';
      args.add('%$nameQuery%');
    }

    final rows = await db.query(
      'characters',
      where: where.isNotEmpty ? where : null,
      whereArgs: args.isNotEmpty ? args : null,
      orderBy: 'updatedAt DESC',
    );

    var results = rows.map(_rowToCharacter).toList();

    // 标签过滤（在内存中过滤，对标 SillyTavern 标签匹配）
    if (tags != null && tags.isNotEmpty) {
      results = results
          .where((c) => tags.any((t) => c.tags.contains(t)))
          .toList();
    }

    return results;
  }

  /// 数据库行转角色对象
  CharacterCardV2 _rowToCharacter(Map<String, dynamic> row) {
    return CharacterCardV2(
      name: row['name'] as String? ?? '',
      description: row['description'] as String? ?? '',
      characterVersion: row['characterVersion'] as String? ?? '',
      personality: row['personality'] as String? ?? '',
      scenario: row['scenario'] as String? ?? '',
      firstMes: row['firstMes'] as String? ?? '',
      mesExample: row['mesExample'] as String? ?? '',
      creatorNotes: row['creatorNotes'] as String? ?? '',
      tags: (jsonDecode(row['tags'] as String? ?? '[]') as List<dynamic>)
          .cast<String>(),
      systemPrompt: row['systemPrompt'] as String? ?? '',
      postHistoryInstructions:
          row['postHistoryInstructions'] as String? ?? '',
      creator: row['creator'] as String? ?? '',
      alternateGreetings:
          (jsonDecode(row['alternateGreetings'] as String? ?? '[]')
                  as List<dynamic>)
              .cast<String>(),
      characterBook: row['characterBook'] != null
          ? WorldInfoBook.fromJson(
              jsonDecode(row['characterBook'] as String)
                  as Map<String, dynamic>)
          : null,
      extensions: row['extensions'] != null
          ? CharacterExtensions.fromJson(
              jsonDecode(row['extensions'] as String)
                  as Map<String, dynamic>)
          : const CharacterExtensions(),
      avatarPath: row['avatarPath'] as String?,
    );
  }
}
