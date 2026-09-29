import 'dart:math';

import 'package:sqflite/sqflite.dart' show Database, ConflictAlgorithm;

import '../../models/life/timed_event.dart';
import '../log_service.dart';

/// 定时事件服务 — 生日/纪念日/节日的注册、查询与触发
///
/// 设计目标（见 docs/design/20.0.0-mainline-1-ai-life.md 3.4）：
/// - 支持一次性事件与每年重复事件
/// - 每日检查并触发（由心跳或前台主动调用）
/// - 触发写入 life_logs，并（后续）可通知用户
class TimedEventService {
  final Database _db;

  TimedEventService(this._db);

  /// 注册事件
  Future<TimedEvent> register({
    required String characterId,
    required String userId,
    required TimedEventType eventType,
    required String title,
    required DateTime date,
    bool recurring = false,
    int reminderDays = 1,
    String? payloadJson,
  }) async {
    final ev = TimedEvent(
      id: _uuid(),
      characterId: characterId,
      userId: userId,
      eventType: eventType,
      title: title,
      date: _fmtDate(date),
      recurring: recurring,
      reminderDays: reminderDays,
      payloadJson: payloadJson,
      createdAt: DateTime.now(),
    );
    await _db.insert(
      'ai_timed_events',
      ev.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    LogService.instance.i('TimedEvent', 'register ${characterId} ${ev.title}');
    return ev;
  }

  /// 未来 N 天内即将到来或今天的事件
  Future<List<TimedEvent>> getUpcoming({
    required String userId,
    int days = 7,
  }) async {
    final rows = await _db.query(
      'ai_timed_events',
      where: 'user_id = ?',
      whereArgs: [userId],
    );
    final now = DateTime.now();
    final list = rows.map(TimedEvent.fromMap).where((e) {
      return e.isWithin(now, days);
    }).toList();
    // 按距离排序
    list.sort((a, b) => _daysUntil(a, now).compareTo(_daysUntil(b, now)));
    return list;
  }

  /// 检查并触发今天的所有事件
  ///
  /// 返回已触发的事件（用于调用方决定是否推消息/通知）
  Future<List<TimedEvent>> checkAndFire({
    required String userId,
    required String characterId,
  }) async {
    final now = DateTime.now();
    final rows = await _db.query(
      'ai_timed_events',
      where: 'user_id = ? AND character_id = ? AND fired_at IS NULL',
      whereArgs: [userId, characterId],
    );
    final fired = <TimedEvent>[];
    for (final row in rows) {
      final ev = TimedEvent.fromMap(row);
      if (!ev.isToday(now)) continue;
      await _db.update(
        'ai_timed_events',
        {'fired_at': now.millisecondsSinceEpoch},
        where: 'id = ?',
        whereArgs: [ev.id],
      );
      fired.add(ev);
    }
    return fired;
  }

  /// 取消（删除）事件
  Future<void> remove(String eventId) async {
    await _db.delete(
      'ai_timed_events',
      where: 'id = ?',
      whereArgs: [eventId],
    );
  }

  /// 为角色自动注册内置事件（首次生成时调用，幂等）
  ///
  /// 只注册：角色生日（如 ai_character 有生日字段则用，否则跳过）
  /// 未来的「首次对话纪念日」等可在此扩展
  Future<void> registerBuiltinsIfNeeded({
    required String characterId,
    required String userId,
    DateTime? characterBirthday,
  }) async {
    if (characterBirthday == null) return;
    final existing = await _db.query(
      'ai_timed_events',
      where:
          'user_id = ? AND character_id = ? AND event_type = ?',
      whereArgs: [userId, characterId, 'birthday'],
      limit: 1,
    );
    if (existing.isNotEmpty) return;

    await register(
      characterId: characterId,
      userId: userId,
      eventType: TimedEventType.birthday,
      title: '角色生日',
      date: characterBirthday,
      recurring: true,
      reminderDays: 3,
    );
  }

  // ─── 工具 ────────────────────────────────────

  int _daysUntil(TimedEvent ev, DateTime now) {
    // 计算下一个匹配日期距今天的天数
    for (var i = 0; i < 366; i++) {
      if (ev.isToday(now.add(Duration(days: i)))) return i;
    }
    return 999;
  }

  String _fmtDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _uuid() {
    final rnd = Random();
    final ts = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    final r = rnd.nextInt(0x7fffffff).toRadixString(16);
    return 'evt_$ts-$r';
  }
}
