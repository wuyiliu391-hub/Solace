import 'dart:math';

import 'package:sqflite/sqflite.dart' show Database, ConflictAlgorithm;

import '../../models/character_emotion.dart';
import '../../models/life/daily_schedule.dart';
import '../../models/life/life_log.dart';
import '../../models/memory.dart';
import '../log_service.dart';

/// 生活日志服务 — 依据日程块 + 当前情绪生成第一人称日志
///
/// 设计目标（见 docs/design/20.0.0-mainline-1-ai-life.md 3.2）：
/// - 简单 block 用模板句 + 情绪色彩，零成本
/// - 复杂 block（work/social）可后续接 LLM 润色（本版本只留接口）
/// - 每天最多 6 条日志
/// - 生成后可选择注入 MemoryEngine
class LifeLogService {
  final Database _db;

  /// 记忆持久化回调（可选）
  ///
  /// 由调用方传入 [LocalStorageRepository.saveMemory] 之类的函数。
  /// 为 null 时，[syncToMemory] 只更新 pushed_to_memory 标记但不真正入库。
  final Future<void> Function(Memory memory)? onSaveMemory;

  /// 每天生成日志上限，防止刷屏
  static const int dailyLimit = 6;

  LifeLogService(this._db, {this.onSaveMemory});

  /// 依据日程块生成一条日志
  ///
  /// [emotion] 用于给日志着上情绪色彩；可为 null（视为 calm）
  /// 返回 null 表示今日已达上限或 block 不值得记录
  Future<LifeLog?> appendFromSchedule({
    required String characterId,
    required String userId,
    required ScheduleBlock block,
    CharacterEmotion? emotion,
  }) async {
    final now = DateTime.now();
    final today = _fmtDate(now);

    final existing = await countForDate(
      characterId: characterId,
      userId: userId,
      date: today,
    );
    if (existing >= dailyLimit) return null;

    // 睡眠类 block 不写日志（避免"我在睡觉"这种废话）
    if (block.activity == LifeActivity.sleep) return null;

    final mood = emotion?.effectiveEmotion ?? EmotionType.calm;
    final moodIntensity = emotion?.currentIntensity ?? 0.0;

    final content = _compose(block, mood);
    if (content.isEmpty) return null;

    final log = LifeLog(
      id: _uuid(),
      characterId: characterId,
      userId: userId,
      date: today,
      time: _hhmm(now),
      content: content,
      mood: mood.label,
      moodIntensity: moodIntensity,
      source: LifeLogSource.schedule,
      pushedToMemory: false,
      createdAt: now,
    );

    await _save(log);
    LogService.instance.i('LifeLog', 'append ${characterId} ${block.label}');
    return log;
  }

  /// 追加一条自定义来源日志（供 share / crossVisit 使用）
  Future<LifeLog> appendCustom({
    required String characterId,
    required String userId,
    required String content,
    LifeLogSource source = LifeLogSource.manual,
    String? mood,
    double moodIntensity = 0.5,
    String? relatedEventId,
  }) async {
    final now = DateTime.now();
    final log = LifeLog(
      id: _uuid(),
      characterId: characterId,
      userId: userId,
      date: _fmtDate(now),
      time: _hhmm(now),
      content: content,
      mood: mood,
      moodIntensity: moodIntensity,
      source: source,
      relatedEventId: relatedEventId,
      pushedToMemory: false,
      createdAt: now,
    );
    await _save(log);
    return log;
  }

  /// 读取某角色最近 N 天的日志
  Future<List<LifeLog>> getRecent({
    required String characterId,
    required String userId,
    int days = 7,
    int limit = 100,
  }) async {
    final since = _fmtDate(
        DateTime.now().subtract(Duration(days: days - 1)));
    final rows = await _db.query(
      'ai_life_logs',
      where: 'character_id = ? AND user_id = ? AND date >= ?',
      whereArgs: [characterId, userId, since],
      orderBy: 'date DESC, time DESC',
      limit: limit,
    );
    return rows.map(LifeLog.fromMap).toList();
  }

  /// 统计某天已有多少条日志
  Future<int> countForDate({
    required String characterId,
    required String userId,
    required String date,
  }) async {
    final result = await _db.rawQuery(
      'SELECT COUNT(*) AS c FROM ai_life_logs '
      'WHERE character_id = ? AND user_id = ? AND date = ?',
      [characterId, userId, date],
    );
    return (result.first['c'] as int?) ?? 0;
  }

  /// 把未注入记忆库的日志同步到 memories 表（去重）
  ///
  /// 使用低权重（0.5），因为生活日志重要性低于对话记忆
  Future<int> syncToMemory({
    required String characterId,
    required String userId,
    int days = 3,
  }) async {
    final rows = await _db.query(
      'ai_life_logs',
      where: 'character_id = ? AND user_id = ? AND pushed_to_memory = 0',
      whereArgs: [characterId, userId],
      orderBy: 'created_at DESC',
      limit: 50,
    );

    var pushed = 0;
    for (final row in rows) {
      final log = LifeLog.fromMap(row);
      final memory = Memory(
        id: 'lifelog_${log.id}',
        characterId: characterId,
        userId: userId,
        type: MemoryType.state,
        content: '[生活日志 ${log.date} ${log.time}] ${log.content}',
        importance: MemoryImportance.trivial,
        keywords: const ['生活', '日常'],
        createdAt: log.createdAt,
        weight: 0.5,
      );
      try {
        final saver = onSaveMemory;
        if (saver != null) {
          await saver(memory);
        }
        await _db.update(
          'ai_life_logs',
          {'pushed_to_memory': 1},
          where: 'id = ?',
          whereArgs: [log.id],
        );
        pushed++;
      } catch (e) {
        LogService.instance.e('LifeLog', 'syncToMemory failed: $e');
      }
    }
    return pushed;
  }

  // ─── 内部实现 ────────────────────────────────────

  /// 用模板 + 情绪合成日志文本；预留 LLM 润色入口
  String _compose(ScheduleBlock block, EmotionType mood) {
    final moodSuffix = _moodSuffix(mood);

    switch (block.activity) {
      case LifeActivity.wake:
        return '刚起床，${moodSuffix}';
      case LifeActivity.commute:
        return '在去${block.label}的路上，${moodSuffix}';
      case LifeActivity.work:
        return '${block.label}中，${moodSuffix}';
      case LifeActivity.meal:
        return '${block.label}，${moodSuffix}';
      case LifeActivity.rest:
        return '休息一会儿，${moodSuffix}';
      case LifeActivity.hobby:
        return '${block.label}，${moodSuffix}';
      case LifeActivity.social:
        return '${block.label}，${moodSuffix}';
      case LifeActivity.exercise:
        return '${block.label}中，出了一身汗，${moodSuffix}';
      case LifeActivity.relax:
        return '${block.label}，${moodSuffix}';
      case LifeActivity.outing:
        return '在外面${block.label}，${moodSuffix}';
      case LifeActivity.sleep:
        return '';
    }
  }

  String _moodSuffix(EmotionType mood) {
    switch (mood) {
      case EmotionType.happy:
        return '心情不错';
      case EmotionType.excited:
        return '有点小兴奋';
      case EmotionType.calm:
        return '状态还行';
      case EmotionType.worried:
        return '有点心不在焉';
      case EmotionType.sad:
        return '没什么精神';
      case EmotionType.angry:
        return '有点烦躁';
      case EmotionType.shy:
        return '脸有点热';
      case EmotionType.touched:
        return '心里暖暖的';
      case EmotionType.lonely:
        return '有点想你';
      case EmotionType.miss:
        return '在想你';
      case EmotionType.anxious:
        return '有点坐立不安';
      case EmotionType.sleepy:
        return '有点困';
      case EmotionType.playful:
        return '想搞点事情';
    }
  }

  Future<void> _save(LifeLog log) async {
    await _db.insert(
      'ai_life_logs',
      log.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  String _fmtDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _hhmm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  String _uuid() {
    final rnd = Random();
    final ts = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    final r = rnd.nextInt(0x7fffffff).toRadixString(16);
    return 'log_$ts-$r';
  }
}
