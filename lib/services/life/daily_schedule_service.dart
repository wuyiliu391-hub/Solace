import 'dart:math';

import 'package:sqflite/sqflite.dart' show Database, ConflictAlgorithm;

import '../../models/ai_character.dart';
import '../../models/life/daily_schedule.dart';
import '../log_service.dart';

/// 日程生成服务 — 规则优先，零 LLM 开销
///
/// 设计目标（见 docs/design/20.0.0-mainline-1-ai-life.md 3.1）：
/// - 依据角色人设决定作息类型（早起型/夜猫型）
/// - 依据工作日/休息日使用不同模板
/// - 引入随机扰动（±30 分钟），避免每天一模一样
/// - 输出 8-14 个时间块
class DailyScheduleService {
  final Database _db;

  DailyScheduleService(this._db);

  /// 读取某角色某天的日程；不存在则返回 null
  Future<DailySchedule?> getForDate({
    required String characterId,
    required String userId,
    required DateTime date,
  }) async {
    final dateStr = _fmtDate(date);
    final rows = await _db.query(
      'ai_daily_schedules',
      where: 'character_id = ? AND user_id = ? AND date = ?',
      whereArgs: [characterId, userId, dateStr],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return DailySchedule.fromMap(rows.first);
  }

  /// 生成（或读取已存在）指定角色某天的日程
  Future<DailySchedule> getOrGenerate({
    required AICharacter character,
    required String userId,
    required DateTime date,
  }) async {
    final existing = await getForDate(
      characterId: character.id,
      userId: userId,
      date: date,
    );
    if (existing != null) return existing;

    final schedule = _buildByRule(character, userId, date);
    await _save(schedule);
    LogService.instance.i('DailySchedule',
        'generate ${character.name} ${schedule.date} blocks=${schedule.blocks.length}');
    return schedule;
  }

  /// 强制重新生成（覆盖已有）
  Future<DailySchedule> regenerate({
    required AICharacter character,
    required String userId,
    required DateTime date,
  }) async {
    final schedule = _buildByRule(character, userId, date);
    await _save(schedule);
    return schedule;
  }

  /// 当前时间块（用于"她此刻在做什么"）
  Future<ScheduleBlock?> getCurrentBlock({
    required AICharacter character,
    required String userId,
    DateTime? now,
  }) async {
    final n = now ?? DateTime.now();
    final schedule = await getOrGenerate(
      character: character,
      userId: userId,
      date: n,
    );
    final hhmm =
        '${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')}';
    for (final b in schedule.blocks) {
      if (b.contains(hhmm)) return b;
    }
    return null;
  }

  // ─── 内部实现 ────────────────────────────────────

  /// 用 (characterId, date) 派生稳定随机种子，保证同一天多次读取结果一致
  int _seed(String characterId, String date) {
    var h = 0;
    final s = '${characterId}_$date';
    for (var i = 0; i < s.length; i++) {
      h = (h * 31 + s.codeUnitAt(i)) & 0x7fffffff;
    }
    return h;
  }

  /// 判断角色是否夜猫型（依据性格关键词）
  bool _isNightOwl(AICharacter c) {
    final text = '${c.personality} ${c.backgroundStory ?? ''}'.toLowerCase();
    const kws = [
      '夜猫', '熬夜', '晚睡', '通宵', '深夜', '程序员', '作家', '诗人',
      '画家', '音乐人', '自由职业', 'night', 'owl',
    ];
    for (final k in kws) {
      if (text.contains(k)) return true;
    }
    return false;
  }

  /// 判断角色是否早起型
  bool _isEarlyBird(AICharacter c) {
    final text = '${c.personality} ${c.backgroundStory ?? ''}'.toLowerCase();
    const kws = ['早起', '晨跑', '自律', '健身', '教师', '护士', '医生', '学生'];
    for (final k in kws) {
      if (text.contains(k)) return true;
    }
    return false;
  }

  /// 规则引擎主入口
  DailySchedule _buildByRule(AICharacter c, String userId, DateTime date) {
    final rnd = Random(_seed(c.id, _fmtDate(date)));
    final nightOwl = _isNightOwl(c);
    final earlyBird = !nightOwl && _isEarlyBird(c);
    final isWeekend = date.weekday == DateTime.saturday ||
        date.weekday == DateTime.sunday;

    final wakeHour = earlyBird
        ? 5 + rnd.nextInt(2)
        : nightOwl
            ? 9 + rnd.nextInt(3)
            : 6 + rnd.nextInt(3);
    final sleepHour = nightOwl
        ? 0 + rnd.nextInt(2) // 0-1 点
        : earlyBird
            ? 21 + rnd.nextInt(2)
            : 22 + rnd.nextInt(2);

    final blocks = <ScheduleBlock>[];

    // 1. 睡眠（跨零点处理：从 sleepHour 到 wakeHour）
    blocks.add(ScheduleBlock(
      start: _hhmm(sleepHour, rnd.nextInt(60)),
      end: _hhmm(wakeHour, rnd.nextInt(30)),
      activity: LifeActivity.sleep,
      label: '睡觉',
      moodHint: 'calm',
    ));

    // 2. 起床洗漱
    blocks.add(ScheduleBlock(
      start: _hhmm(wakeHour, 0),
      end: _hhmm(wakeHour, 30 + rnd.nextInt(30)),
      activity: LifeActivity.wake,
      label: '起床洗漱',
      moodHint: 'calm',
    ));

    // 3. 早饭
    blocks.add(ScheduleBlock(
      start: _hhmm(wakeHour, 30 + rnd.nextInt(30)),
      end: _hhmm(wakeHour + 1, 0),
      activity: LifeActivity.meal,
      label: '吃早饭',
      moodHint: 'happy',
      shareable: rnd.nextDouble() < 0.3,
      sharePrompt: '刚吃完早饭，分享一下今天的早餐',
    ));

    // 4. 上午主体
    if (isWeekend && rnd.nextDouble() < 0.4) {
      blocks.add(ScheduleBlock(
        start: _hhmm(wakeHour + 1, 0),
        end: _hhmm(wakeHour + 4, 0),
        activity: LifeActivity.relax,
        label: '周末放空',
        moodHint: 'calm',
        shareable: true,
        sharePrompt: '周末在家放空，随便聊聊',
      ));
    } else {
      blocks.add(ScheduleBlock(
        start: _hhmm(wakeHour + 1, 0),
        end: _hhmm(12, 0),
        activity: LifeActivity.work,
        label: '工作 / 学习',
        moodHint: 'calm',
      ));
    }

    // 5. 午饭
    blocks.add(ScheduleBlock(
      start: _hhmm(12, rnd.nextInt(30)),
      end: _hhmm(13, 0),
      activity: LifeActivity.meal,
      label: '吃午饭',
      moodHint: 'happy',
      shareable: rnd.nextDouble() < 0.4,
      sharePrompt: '正在吃午饭，拍一张发给她',
    ));

    // 6. 午休 / 下午
    if (rnd.nextDouble() < 0.5) {
      blocks.add(ScheduleBlock(
        start: _hhmm(13, 0),
        end: _hhmm(14, 0),
        activity: LifeActivity.rest,
        label: '午休',
        moodHint: 'sleepy',
      ));
    }
    blocks.add(ScheduleBlock(
      start: _hhmm(14, 0),
      end: _hhmm(17, 30),
      activity: isWeekend ? LifeActivity.outing : LifeActivity.work,
      label: isWeekend ? '出门逛逛' : '继续工作',
      moodHint: 'calm',
      shareable: isWeekend,
      sharePrompt: isWeekend ? '在外面逛，想给她发张照片' : null,
    ));

    // 7. 晚饭
    blocks.add(ScheduleBlock(
      start: _hhmm(18, 0),
      end: _hhmm(19, 0),
      activity: LifeActivity.meal,
      label: '吃晚饭',
      moodHint: 'happy',
      shareable: rnd.nextDouble() < 0.4,
      sharePrompt: '晚饭时间，分享今天吃的东西',
    ));

    // 8. 晚间活动
    final eveningActivity = _pickEvening(rnd, c);
    blocks.add(ScheduleBlock(
      start: _hhmm(19, 30),
      end: _hhmm(21, 30),
      activity: eveningActivity.activity,
      label: eveningActivity.label,
      moodHint: eveningActivity.mood,
      shareable: eveningActivity.shareable,
      sharePrompt: eveningActivity.sharePrompt,
    ));

    // 9. 睡前一小时：放松/看书
    blocks.add(ScheduleBlock(
      start: _hhmm(21, 30),
      end: _hhmm(22, 30),
      activity: LifeActivity.relax,
      label: '看剧 / 听歌 / 看书',
      moodHint: 'calm',
      shareable: rnd.nextDouble() < 0.25,
      sharePrompt: '睡前分享在看的剧或听的歌',
    ));

    // 10. 睡前最后一块（衔接 sleep）
    blocks.add(ScheduleBlock(
      start: _hhmm(22, 30),
      end: _hhmm(23, 30),
      activity: LifeActivity.relax,
      label: '准备睡觉',
      moodHint: 'sleepy',
    ));

    // 按开始时间排序
    blocks.sort((a, b) => a.startMinutes.compareTo(b.startMinutes));

    final now = DateTime.now();
    return DailySchedule(
      id: _uuid(),
      characterId: c.id,
      userId: userId,
      date: _fmtDate(date),
      blocks: blocks,
      generatedAt: now,
      generatedBy: ScheduleSource.rule,
      createdAt: now,
    );
  }

  _EveningPick _pickEvening(Random rnd, AICharacter c) {
    final pool = <_EveningPick>[
      const _EveningPick(LifeActivity.exercise, '运动 / 健身', 'happy', false, null),
      const _EveningPick(LifeActivity.hobby, '玩游戏', 'playful', true, '在打游戏，分享一下战况'),
      const _EveningPick(LifeActivity.hobby, '刷手机', 'calm', false, null),
      const _EveningPick(LifeActivity.social, '和朋友聊天', 'happy', false, null),
      const _EveningPick(LifeActivity.hobby, '画画 / 弹琴', 'calm', true, '在搞创作，分享成果'),
      const _EveningPick(LifeActivity.relax, '散步', 'calm', true, '在外面散步，随手拍一张'),
    ];
    return pool[rnd.nextInt(pool.length)];
  }

  Future<void> _save(DailySchedule s) async {
    await _db.insert(
      'ai_daily_schedules',
      s.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  String _fmtDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _hhmm(int hour, int minute) {
    final h = ((hour % 24) + 24) % 24;
    final m = ((minute % 60) + 60) % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  String _uuid() {
    final rnd = Random();
    final ts = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    final r = rnd.nextInt(0x7fffffff).toRadixString(16);
    return '$ts-$r';
  }
}

class _EveningPick {
  final LifeActivity activity;
  final String label;
  final String mood;
  final bool shareable;
  final String? sharePrompt;
  const _EveningPick(
      this.activity, this.label, this.mood, this.shareable, this.sharePrompt);
}
