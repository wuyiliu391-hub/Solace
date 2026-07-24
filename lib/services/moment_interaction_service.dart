import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../config/business_rules.dart';
import '../models/ai_character.dart';
import '../models/chat_session.dart';
import '../models/moment.dart';
import '../repositories/local_storage_repository.dart';
import 'background_service.dart';
import 'proactive_scheduler.dart';

/// 朋友圈 AI 互动编排：
/// - 用户发动态 → 角色按人设延迟点赞/评论
/// - 用户评论角色动态 / 回复角色评论 → 角色延迟再回，支持多轮
/// - 周期任务：角色按人设+生活规律主动发动态
class MomentInteractionService {
  MomentInteractionService._();
  static final MomentInteractionService instance = MomentInteractionService._();

  final _rng = Random();
  final _pendingTimers = <String, Timer>{};

  /// 用户发布动态后，为可见角色安排互动
  Future<void> onUserPostedMoment({
    required LocalStorageRepository storage,
    required Moment moment,
    required String userId,
  }) async {
    if (moment.source != MomentSource.normal) return;
    if (moment.visibility == MomentVisibility.private) return;

    final characters = await storage.getAllAICharacters();
    final sessions = await storage.getChatSessions(userId);
    final intimacyByChar = <String, int>{
      for (final s in sessions) s.aiCharacterId: s.intimacyLevel,
    };

    final scheduler = ProactiveScheduler(storage);
    for (final character in characters) {
      if (character.isHidden) continue;
      if (!character.isOnline) continue;
      final cfg = character.interactionConfig ?? const AIInteractionConfig();
      if (!cfg.enableUserMomentInteraction) continue;

      final intimacy = intimacyByChar[character.id] ?? 0;
      if (!_canSeeMoment(moment.visibility, intimacy)) continue;

      final delay = _userMomentDelay(character.personality);
      final key = 'interact_${moment.id}_${character.id}';
      debugPrint(
          'MomentAI: 安排 ${character.name} 互动用户动态，${delay.inSeconds}s 后');

      await scheduler.scheduleMomentInteraction(
        momentId: moment.id,
        characterId: character.id,
        intimacyLevel: intimacy,
        delay: delay,
      );
      // 短延迟前台兜底（Windows / WorkManager 不可用时仍能互动）
      _scheduleForegroundFallback(
        key: key,
        delay: delay,
        run: () => _runMomentInteractFallback(
          momentId: moment.id,
          characterId: character.id,
          intimacyLevel: intimacy,
        ),
      );
    }
  }

  /// 用户发表评论后：
  /// - 若动态是角色发的 → 角色回复该评论
  /// - 若用户回复了某角色评论 → 该角色继续回
  Future<void> onUserCommented({
    required LocalStorageRepository storage,
    required Moment moment,
    required MomentComment comment,
    required String userId,
  }) async {
    if (moment.source != MomentSource.normal) return;

    final targets = <({String characterId, int intimacy})>{};

    // 1) 用户评角色动态 → 动态作者回复
    if (moment.isFromAI) {
      final authorId = moment.userId;
      final intimacy = await _intimacyFor(storage, userId, authorId);
      final char = await storage.getAICharacter(authorId);
      if (char != null &&
          !char.isHidden &&
          (char.interactionConfig?.enableMomentInteraction ?? true)) {
        targets.add((characterId: authorId, intimacy: intimacy));
      }
    }

    // 2) 用户回复某条角色评论 → 该角色继续回（多轮）
    final replyToId = comment.replyToUserId;
    if (replyToId != null && replyToId.isNotEmpty) {
      final chars = await storage.getAllAICharacters();
      final hit = chars.where((c) => c.id == replyToId).toList();
      if (hit.isNotEmpty) {
        final c = hit.first;
        if (!c.isHidden &&
            (c.interactionConfig?.enableMomentInteraction ?? true)) {
          final intimacy = await _intimacyFor(storage, userId, c.id);
          targets.add((characterId: c.id, intimacy: intimacy));
        }
      }
    }

    // 3) 用户在自己动态下继续说话，且已有角色评论过 → 已参与角色可能再回
    if (!moment.isFromAI && moment.userId == userId) {
      final aiCommenters = moment.comments
          .where((c) => c.userId != userId)
          .map((c) => c.userId)
          .toSet();
      final chars = await storage.getAllAICharacters();
      for (final c in chars) {
        if (!aiCommenters.contains(c.id)) continue;
        if (c.isHidden) continue;
        if (!(c.interactionConfig?.enableMomentInteraction ?? true)) continue;
        // 仅当用户评论是对角色的回复，或本轮未指定 reply 时按概率再回
        final isDirectReply = comment.replyToUserId == c.id;
        if (!isDirectReply && _rng.nextDouble() > 0.45) continue;
        final intimacy = await _intimacyFor(storage, userId, c.id);
        targets.add((characterId: c.id, intimacy: intimacy));
      }
    }

    final scheduler = ProactiveScheduler(storage);
    for (final t in targets) {
      final char = await storage.getAICharacter(t.characterId);
      final delay = _commentReplyDelay(char?.personality);
      final key = 'reply_${moment.id}_${comment.id}_${t.characterId}';
      debugPrint(
          'MomentAI: 安排角色 ${t.characterId} 回复评论 ${comment.id}，${delay.inSeconds}s 后');

      await scheduler.scheduleCommentReply(
        momentId: moment.id,
        commentId: comment.id,
        characterId: t.characterId,
        intimacyLevel: t.intimacy,
        delay: delay,
      );
      _scheduleForegroundFallback(
        key: key,
        delay: delay,
        run: () => _runCommentReplyFallback(
          momentId: moment.id,
          commentId: comment.id,
          characterId: t.characterId,
          intimacyLevel: t.intimacy,
        ),
      );
    }
  }

  // ─── delays ───

  Duration _userMomentDelay(String? personality) {
    final p = (personality ?? '').toLowerCase();
    int min;
    int range;
    if (p.contains('活泼') || p.contains('热情') || p.contains('开朗')) {
      min = IntimacyRules.userMomentBouncyMin;
      range = IntimacyRules.userMomentBouncyRange;
    } else if (p.contains('温柔') || p.contains('体贴') || p.contains('细心')) {
      min = IntimacyRules.userMomentWarmMin;
      range = IntimacyRules.userMomentWarmRange;
    } else if (p.contains('高冷') || p.contains('冷淡') || p.contains('冷静')) {
      min = IntimacyRules.userMomentCoolMin;
      range = IntimacyRules.userMomentCoolRange;
    } else if (p.contains('害羞') || p.contains('内向')) {
      min = IntimacyRules.userMomentShyMin;
      range = IntimacyRules.userMomentShyRange;
    } else {
      min = IntimacyRules.userMomentDefaultMin;
      range = IntimacyRules.userMomentDefaultRange;
    }
    // 规则单位是“秒级小延迟”，再放大到更自然的分钟感（×15）
    final seconds = (min + _rng.nextInt(range + 1)) * 15;
    return Duration(seconds: seconds.clamp(20, 900));
  }

  Duration _commentReplyDelay(String? personality) {
    final p = (personality ?? '').toLowerCase();
    int min;
    int range;
    if (p.contains('活泼') || p.contains('热情') || p.contains('开朗')) {
      min = MomentSchedulerRules.commentReplyBouncyMin;
      range = MomentSchedulerRules.commentReplyBouncyRange;
    } else if (p.contains('温柔') || p.contains('体贴') || p.contains('细心')) {
      min = MomentSchedulerRules.commentReplyWarmMin;
      range = MomentSchedulerRules.commentReplyWarmRange;
    } else if (p.contains('高冷') || p.contains('冷淡') || p.contains('冷静')) {
      min = MomentSchedulerRules.commentReplyCoolMin;
      range = MomentSchedulerRules.commentReplyCoolRange;
    } else if (p.contains('害羞') || p.contains('内向')) {
      min = MomentSchedulerRules.commentReplyShyMin;
      range = MomentSchedulerRules.commentReplyShyRange;
    } else {
      min = MomentSchedulerRules.commentReplyDefaultMin;
      range = MomentSchedulerRules.commentReplyDefaultRange;
    }
    final seconds = min + _rng.nextInt(range + 1);
    return Duration(seconds: seconds.clamp(30, 1800));
  }

  bool _canSeeMoment(MomentVisibility visibility, int intimacy) {
    switch (visibility) {
      case MomentVisibility.public:
        return true;
      case MomentVisibility.private:
        return false;
      case MomentVisibility.intimate:
        return intimacy >= IntimacyRules.intimateVisibilityThreshold;
      case MomentVisibility.normal:
        return intimacy >= IntimacyRules.normalVisibilityThreshold;
    }
  }

  Future<int> _intimacyFor(
    LocalStorageRepository storage,
    String userId,
    String characterId,
  ) async {
    try {
      final sessions = await storage.getChatSessionsByCharacterId(characterId);
      if (sessions.isEmpty) return 0;
      ChatSession? mine;
      for (final s in sessions) {
        if (s.userId == userId) {
          mine = s;
          break;
        }
      }
      return mine?.intimacyLevel ?? sessions.first.intimacyLevel;
    } catch (_) {
      return 0;
    }
  }

  void _scheduleForegroundFallback({
    required String key,
    required Duration delay,
    required Future<void> Function() run,
  }) {
    _pendingTimers[key]?.cancel();
    // 仅对 ≤3 分钟的任务做前台兜底，避免常驻 Timer 过多
    if (delay > const Duration(minutes: 3)) return;
    _pendingTimers[key] = Timer(delay, () async {
      _pendingTimers.remove(key);
      try {
        await run();
      } catch (e) {
        debugPrint('MomentAI foreground fallback failed: $e');
      }
    });
  }

  Future<void> _runMomentInteractFallback({
    required String momentId,
    required String characterId,
    required int intimacyLevel,
  }) async {
    // 直接复用后台 handler，保证逻辑一致
    await handleMomentInteractTask({
      'momentId': momentId,
      'characterId': characterId,
      'intimacyLevel': intimacyLevel,
    });
  }

  Future<void> _runCommentReplyFallback({
    required String momentId,
    required String commentId,
    required String characterId,
    required int intimacyLevel,
  }) async {
    await handleCommentReplyTask({
      'momentId': momentId,
      'commentId': commentId,
      'characterId': characterId,
      'intimacyLevel': intimacyLevel,
    });
  }
}
