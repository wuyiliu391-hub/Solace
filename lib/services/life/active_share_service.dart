import 'package:sqflite/sqflite.dart' show Database;

import '../../models/ai_character.dart';
import '../../models/character_emotion.dart';
import '../../models/life/daily_schedule.dart';
import '../../models/life/life_log.dart';
import '../log_service.dart';
import 'life_log_service.dart';

/// 分享去向
enum ShareTarget {
  /// 只写生活日志（低打扰）
  logOnly,

  /// 发一条聊天消息（默认）
  chat,

  /// 发朋友圈（后续接入，本版本仅标记）
  moment,
}

/// 分享决策
class ShareDecision {
  final bool shouldShare;
  final ScheduleBlock? block;
  final ShareTarget target;
  final String reason;

  const ShareDecision({
    required this.shouldShare,
    this.block,
    this.target = ShareTarget.chat,
    required this.reason,
  });

  const ShareDecision.skip(String reason)
      : shouldShare = false,
        block = null,
        target = ShareTarget.logOnly,
        reason = reason;
}

/// 主动分享服务 — 判断当前时间块是否该主动找用户说话
///
/// 设计目标（见 docs/design/20.0.0-mainline-1-ai-life.md 3.3）：
/// - 只在「日程块 shareable=true」+「冷却到期」+「非免打扰」时触发
/// - 内容由调用方（ChatBloc / background_service）注入 LLM 生成
/// - 本服务只负责「判定」，不负责生成文案，避免侵入现有生成链路
class ActiveShareService {
  final Database _db;

  /// 分享冷却（默认 4 小时）
  final Duration cooldown;

  static const String _prefKey = 'life_active_share_last_at';

  ActiveShareService(this._db, {this.cooldown = const Duration(hours: 4)});

  /// 判断当前角色是否应该主动分享
  Future<ShareDecision> evaluate({
    required AICharacter character,
    required String userId,
    ScheduleBlock? currentBlock,
    CharacterEmotion? emotion,
  }) async {
    // 1. 必须有可分享的当前块
    if (currentBlock == null) {
      return const ShareDecision.skip('无当前时间块');
    }
    if (!currentBlock.shareable) {
      return const ShareDecision.skip('当前块不标记分享');
    }

    // 2. 冷却检查（用 life_logs 里 source=share 的最近一条）
    final recent = await _db.query(
      'ai_life_logs',
      where: 'character_id = ? AND user_id = ? AND source = ?',
      whereArgs: [character.id, userId, 'share'],
      orderBy: 'created_at DESC',
      limit: 1,
    );
    if (recent.isNotEmpty) {
      final lastAt = (recent.first['created_at'] as int?) ?? 0;
      final elapsed = DateTime.now().millisecondsSinceEpoch - lastAt;
      if (elapsed < cooldown.inMilliseconds) {
        return ShareDecision.skip('冷却中');
      }
    }

    // 3. 情绪阈值（排除极端负面，避免不合时宜的打扰）
    if (emotion != null &&
        (emotion.effectiveEmotion == EmotionType.angry ||
            emotion.effectiveEmotion == EmotionType.sad) &&
        emotion.currentIntensity > 0.7) {
      return ShareDecision.skip('情绪不适合分享');
    }

    // 4. 通过 → 生成决策
    return ShareDecision(
      shouldShare: true,
      block: currentBlock,
      target: ShareTarget.chat,
      reason: 'block=${currentBlock.label}',
    );
  }

  /// 记录一次分享（更新冷却 + 写生活日志）
  ///
  /// [content] 是调用方生成的分享文案（用于写日志）
  Future<LifeLog> recordShare({
    required String characterId,
    required String userId,
    required String content,
    String? mood,
    double moodIntensity = 0.5,
  }) async {
    final logService = LifeLogService(_db);
    final log = await logService.appendCustom(
      characterId: characterId,
      userId: userId,
      content: content,
      source: LifeLogSource.share,
      mood: mood,
      moodIntensity: moodIntensity,
    );
    LogService.instance.i(
        'ActiveShare', 'recorded ${characterId} len=${content.length}');
    return log;
  }
}
