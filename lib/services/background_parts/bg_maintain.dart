// 后台任务拆分 part
part of '../background_service.dart';

Future<void> _maintainAiLife(Database db) async {
  final scheduleService = DailyScheduleService(db);
  final logService = LifeLogService(db);

  final prefs = await SharedPreferences.getInstance();
  final userId = prefs.getString(PrefKeys.currentUserId) ?? 'local_user';

  final rows = await db.query('ai_characters');
  for (final row in rows) {
    try {
      final character = AICharacter.fromMap(row);
      if (character.isHidden) continue;

      // 1. 确保今日日程存在
      final schedule = await scheduleService.getOrGenerate(
        character: character,
        userId: userId,
        date: DateTime.now(),
      );

      // 2. 找到当前时间块
      final now = DateTime.now();
      final hhmm =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      ScheduleBlock? current;
      for (final b in schedule.blocks) {
        if (b.contains(hhmm)) {
          current = b;
          break;
        }
      }
      if (current == null) continue;

      // 3. 该块今天是否已写过日志？
      final logs = await logService.getRecent(
        characterId: character.id,
        userId: userId,
        days: 1,
        limit: 30,
      );
      final already =
          logs.any((l) => l.time.startsWith(current!.start.substring(0, 2)));
      if (already) continue;

      // 4. 追加日志
      await logService.appendFromSchedule(
        characterId: character.id,
        userId: userId,
        block: current,
      );

      // 5. A2：检查是否该主动分享（只写日志，真正的消息生成由上层接管）
      try {
        final shareSvc = ActiveShareService(db);
        final decision = await shareSvc.evaluate(
          character: character,
          userId: userId,
          currentBlock: current,
        );
        if (decision.shouldShare && current.sharePrompt != null) {
          await shareSvc.recordShare(
            characterId: character.id,
            userId: userId,
            content: current.sharePrompt!,
            mood: current.moodHint,
          );
        }
      } catch (e) {
        debugPrint('Background: 主动分享判定失败: $e');
      }

      // 6. A2：检查今天的定时事件（生日/纪念日）
      try {
        final eventSvc = TimedEventService(db);
        final fired = await eventSvc.checkAndFire(
          userId: userId,
          characterId: character.id,
        );
        for (final ev in fired) {
          // 触发的生日/纪念日写入生活日志（供 UI 展示；通知可后续接入）
          await logService.appendCustom(
            characterId: character.id,
            userId: userId,
            content: '今天是「${ev.title}」',
            source: LifeLogSource.schedule,
            mood: '开心',
            moodIntensity: 0.7,
          );
        }
      } catch (e) {
        debugPrint('Background: 定时事件检查失败: $e');
      }
    } catch (e) {
      debugPrint('Background: 角色 ${row['id']} 生活维护失败: $e');
    }
  }
}

// ─── Shared helpers ───
