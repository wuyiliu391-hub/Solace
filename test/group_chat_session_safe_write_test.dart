import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:solace/models/group_chat_session.dart';
import 'package:solace/repositories/local_storage_repository.dart';

/// group_chat_sessions 遗留脏表 INSERT 崩溃回归测试。
///
/// 复现用户机上的实况（ADB 校验 overture_phone.db @ user_version=65）：
/// 旧版群聊表仍含 `participantIds TEXT NOT NULL` / `participantNames TEXT NOT NULL`
/// （无默认值），而当前 GroupChatSession.toMap() 不含这两列。
/// 原「按真实列过滤」逻辑只能滤掉模型侧多余列，无法兜住
/// 表侧 NOT NULL 缺列 → `NOT NULL constraint failed: participantIds` 崩溃。
void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  test('遗留表上 saveGroupChatSession 流程不再触发 NOT NULL 崩溃，且 participantIds 被回填',
      () async {
    final db = await databaseFactoryFfi.openDatabase(':memory:');

    // —— 复现遗留 schema（v65 用户机实测列，截选与崩相关的列）——
    await db.execute('''
      CREATE TABLE group_chat_sessions (
        id TEXT PRIMARY KEY,
        userId TEXT NOT NULL,
        name TEXT NOT NULL,
        memberIds TEXT NOT NULL DEFAULT '[]',
        aiCharacterIds TEXT NOT NULL DEFAULT '[]',
        creatorId TEXT NOT NULL DEFAULT '',
        isMuted INTEGER NOT NULL DEFAULT 0,
        isPinned INTEGER NOT NULL DEFAULT 0,
        participantIds TEXT NOT NULL,
        participantNames TEXT NOT NULL
      )
    ''');

    final session = GroupChatSession(
      id: 'g1',
      name: '测试群',
      memberIds: ['c1', 'c2'],
      aiCharacterIds: ['c1', 'c2'],
      creatorId: 'u1',
      createdAt: DateTime(2026, 8, 2),
    );

    // —— 复现 saveGroupChatSession 的「按真实列过滤」逻辑 ——
    final cols =
        await LocalStorageRepository.getTableColumns(db, 'group_chat_sessions');
    final safe = <String, dynamic>{};
    for (final e in session.toMap().entries) {
      if (cols.contains(e.key)) safe[e.key] = e.value;
    }
    expect(safe.containsKey('participantIds'), isFalse,
        reason: '前置：模型不含 participantIds，过滤后仍缺');
    expect(safe.containsKey('memberIds'), isTrue,
        reason: '前置：memberIds 应保留在 safe 中');

    // —— 复现崩溃：不补填直接插入 → NOT NULL constraint failed ——
    await expectLater(
      () => db.insert('group_chat_sessions', safe,
          conflictAlgorithm: ConflictAlgorithm.replace),
      throwsA(isA<DatabaseException>()),
      reason: '补填前，缺少 participantIds 的 INSERT 应当崩溃',
    );

    // —— 应用修复 ——
    await LocalStorageRepository.fillNotNullDefaultsForTest(
        db, 'group_chat_sessions', safe);

    // —— 再插入应成功 ——
    await db.insert('group_chat_sessions', safe,
        conflictAlgorithm: ConflictAlgorithm.replace);
    final rows = await db
        .query('group_chat_sessions', where: 'id = ?', whereArgs: ['g1']);
    expect(rows.length, 1, reason: '插入应成功且仅一条');
    // participantIds 语义回填自 memberIds（均为 JSON 数组字符串）
    expect(rows.first['participantIds'], jsonEncode(session.memberIds));
    await db.close();
  });

  test('表侧 NOT NULL 无默认列均被赋予类型安全默认值', () async {
    final db = await databaseFactoryFfi.openDatabase(':memory:');
    await db.execute('''
      CREATE TABLE t (
        id TEXT PRIMARY KEY,
        aText TEXT NOT NULL,
        aInt INTEGER NOT NULL,
        aReal REAL NOT NULL
      )
    ''');
    final safe = <String, dynamic>{'id': 'x', 'aText': 'has'};
    await LocalStorageRepository.fillNotNullDefaultsForTest(db, 't', safe);
    // aText 已有值不被覆盖；aInt/aReal 被填为类型安全默认
    expect(safe['aText'], 'has');
    expect(safe['aInt'], 0);
    expect(safe['aReal'], 0.0);
    await db.insert('t', safe, conflictAlgorithm: ConflictAlgorithm.replace);
    expect((await db.query('t')).length, 1);
    await db.close();
  });

  test('旧版群聊表会自动重建并补齐新表结构', () async {
    final db = await databaseFactoryFfi.openDatabase(':memory:');
    await db.execute('''
      CREATE TABLE group_chat_sessions (
        id TEXT PRIMARY KEY,
        userId TEXT NOT NULL,
        name TEXT NOT NULL,
        memberIds TEXT NOT NULL,
        aiCharacterIds TEXT NOT NULL,
        participantIds TEXT NOT NULL,
        participantNames TEXT NOT NULL
      )
    ''');

    await LocalStorageRepository.ensureGroupChatSchemaForTest(db);

    final columns =
        await LocalStorageRepository.getTableColumns(db, 'group_chat_sessions');
    expect(
        columns,
        containsAll(<String>[
          'id',
          'userId',
          'name',
          'memberIds',
          'aiCharacterIds',
          'creatorId',
          'autoModeDelay',
          'autoModeEnabled',
          'autoModeDelaysByCharacter',
          'isHidden',
        ]));
    expect(columns, isNot(contains('participantIds')),
        reason: '旧版无默认值列不应继续阻塞新模型写入');

    await db.insert('group_chat_sessions', {
      'id': 'g1',
      'userId': 'u1',
      'name': '测试群',
      'memberIds': jsonEncode(['c1']),
      'aiCharacterIds': jsonEncode(['c1']),
      'creatorId': 'u1',
      'createdAt': DateTime.now().toIso8601String(),
    });
    expect((await db.query('group_chat_sessions')).length, 1);
    await db.close();
  });
}
