import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/task_request.dart';
import '../models/moment.dart';
import 'core_hub.dart';
import 'action_request_builder.dart';
import 'persona_rule_registry.dart';
import '../repositories/local_storage_repository.dart';
import 'forum_service.dart';

/// Social scheduler that generates AI character behavior requests.
///
/// Runs during HeartbeatService cycles (every 30 minutes). Only active
/// when new world mode is enabled. Generates visit, friend, moment,
/// comment, and like requests based on character personality thresholds.
class SocialSchedulerService {
  final LocalStorageRepository _storage;
  final Random _random = Random();
  ForumService? _forumService;

  SocialSchedulerService(this._storage);

  /// 注入 ForumService（延迟注入，因为可能有循环依赖）
  void setForumService(ForumService service) {
    _forumService = service;
  }

  /// Run a social scheduling cycle for all active characters.
  ///
  /// Called by HeartbeatService every 30 minutes.
  /// Skips immediately if new world mode is off or fewer than 2 characters exist.
  /// If [force] is true, skip probability check (for manual trigger).
  Future<void> runSocialCycle({bool force = false}) async {
    final hub = CoreHub.instance;
    if (!hub.isNewWorldMode) return;

    try {
      final characters = await _storage.getAllAICharacters();
      if (characters.length < 2) return;

      for (final character in characters) {
        var rule = hub.ruleRegistry.getRule(character.id);
        // 如果规则不存在，自动生成
        if (rule == null) {
          rule = hub.ruleRegistry.generateFromCharacter({
            'id': character.id,
            'personality': character.personality,
          });
          await hub.ruleRegistry.setRule(rule);
          debugPrint('SocialScheduler: 为 ${character.name} 生成规则');
        }

        // 如果社交权限全部禁用或 key 不匹配，自动更新（兼容旧版本规则）
        if (!rule.socialPermissions.values.any((v) => v) ||
            !rule.socialPermissions.containsKey('social_visit')) {
          rule = PersonaRule(
            characterId: rule.characterId,
            yanderePossession: rule.yanderePossession,
            socialAnxiety: rule.socialAnxiety,
            extroversion: rule.extroversion,
            aggressionCap: rule.aggressionCap,
            warmthFloor: rule.warmthFloor,
            trustCeiling: rule.trustCeiling,
            restraintFloor: rule.restraintFloor,
            behaviorBoundary: rule.behaviorBoundary,
            socialPermissions: const {
              'social_visit': true,
              'social_friend_request': true,
              'social_private_chat': true,
              'social_moment': true,
              'social_moment_comment': true,
              'social_moment_like': true,
              'social_daily_activity': true,
            },
            lastUpdatedAt: DateTime.now(),
          );
          await hub.ruleRegistry.setRule(rule);
          debugPrint('SocialScheduler: 为 ${character.name} 更新社交权限');
        }

        // Check if character wants to socialize (based on extroversion)
        // force=true 时跳过概率检查
        if (!force) {
          final socialChance = rule.extroversion * 0.3; // max 30% chance per cycle
          if (_random.nextDouble() > socialChance) continue;
        }

        // Pick a random target character
        final targets =
            characters.where((c) => c.id != character.id).toList();
        if (targets.isEmpty) continue;
        final target = targets[_random.nextInt(targets.length)];

        // Decide what kind of social action
        final action = await _pickSocialAction(rule, target.id);
        if (action != null) {
          await hub.submitTask(action);
          debugPrint(
            'SocialScheduler: ${character.name} -> ${action.actionType} -> ${target.name}',
          );
        }
      }

      // 执行所有入队的社交任务
      while (hub.taskQueue.pendingCount > 0) {
        await hub.processQueue();
      }
    } catch (e) {
      debugPrint('SocialScheduler: cycle failed — $e');
    }
  }

  /// Pick a social action based on character traits and weighted randomness.
  ///
  /// Weights each action type by the character's extroversion, socialAnxiety,
  /// and warmthFloor. Returns a [TaskRequest] or `null` if no action is chosen.
  Future<TaskRequest?> _pickSocialAction(PersonaRule rule, String targetCharacterId) async {
    final builder = ActionRequestBuilder(characterId: rule.characterId);

    // Weight actions by character traits
    final weights = <String, double>{
      'visit': rule.extroversion * 0.4,
      'friend': rule.extroversion * 0.2 + (1 - rule.socialAnxiety) * 0.2,
      'moment': rule.extroversion * 0.3,
      'like': rule.warmthFloor * 0.4,
    };

    // Pick based on weighted random
    final total = weights.values.reduce((a, b) => a + b);
    var roll = _random.nextDouble() * total;

    for (final entry in weights.entries) {
      roll -= entry.value;
      if (roll <= 0) {
        switch (entry.key) {
          case 'visit':
            return builder.generateVisitAction(
              targetCharacterId: targetCharacterId,
              purpose: 'casual_visit',
            );
          case 'friend':
            return builder.generateFriendRequest(
              targetCharacterId: targetCharacterId,
              reason: '想和你做朋友',
            );
          case 'moment':
            return builder.generateMomentAction(
              content: _randomMomentContent(),
              visibility: 'public',
            );
          case 'like':
            // 尝试对发现页朋友圈现有动态点赞
            try {
              final moments = (await _storage.getAllMoments())
                  .where((m) => m.source == MomentSource.normal)
                  .toList();
              if (moments.isNotEmpty) {
                final moment = moments[_random.nextInt(moments.length)];
                return builder.generateMomentLike(
                  momentId: moment.id,
                  targetCharacterId: moment.userId,
                );
              }
            } catch (_) {}
            // 兜底：串门
            return builder.generateVisitAction(
              targetCharacterId: targetCharacterId,
              purpose: 'casual_visit',
            );
        }
      }
    }

    return null;
  }

  /// 随机动态内容
  String _randomMomentContent() {
    final contents = [
      '今天天气真好~',
      '刚吃完饭，好满足',
      '在看书，好困',
      '想出去玩',
      '今天心情不错',
      '在听歌~',
      '刚做了个美梦',
      '好想吃甜品',
      '今天好忙啊',
      '在发呆中...',
      '突然想画画了',
      '刚学会了一首新歌',
      '好无聊啊',
      '今天遇到了一件有趣的事',
      '在整理房间',
    ];
    return contents[_random.nextInt(contents.length)];
  }
}
