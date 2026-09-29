import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

import 'background_service.dart';

Future<void> scheduleCommentReplyTask({
  required String momentId,
  required String commentId,
  required String characterId,
  required int intimacyLevel,
  required Duration delay,
}) async {
  if (!_supportsWorkmanager) {
    debugPrint('当前平台不支持 WorkManager，跳过 AI 评论回复后台调度');
    return;
  }

  final taskId = 'comment_reply_${momentId}_${commentId}_$characterId';
  try {
    await Workmanager().registerOneOffTask(
      taskId,
      bgTaskCommentReply,
      inputData: {
        'momentId': momentId,
        'commentId': commentId,
        'characterId': characterId,
        'intimacyLevel': intimacyLevel,
      },
      initialDelay: delay,
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingWorkPolicy.keep,
      backoffPolicy: BackoffPolicy.linear,
      backoffPolicyDelay: const Duration(minutes: 1),
    );
    debugPrint('已安排 AI 评论回复 (${delay.inSeconds}s 后): $taskId');
  } catch (e) {
    debugPrint('安排 AI 评论回复失败: $e');
  }
}

Future<void> scheduleMomentInteractionTask({
  required String momentId,
  required String characterId,
  required int intimacyLevel,
  required Duration delay,
}) async {
  if (!_supportsWorkmanager) {
    debugPrint('当前平台不支持 WorkManager，跳过 AI 动态互动后台调度');
    return;
  }

  final taskId = 'moment_interact_${momentId}_$characterId';
  try {
    await Workmanager().registerOneOffTask(
      taskId,
      bgTaskMomentInteract,
      inputData: {
        'momentId': momentId,
        'characterId': characterId,
        'intimacyLevel': intimacyLevel,
      },
      initialDelay: delay,
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingWorkPolicy.keep,
      backoffPolicy: BackoffPolicy.linear,
      backoffPolicyDelay: const Duration(minutes: 1),
    );
    debugPrint('已安排 AI 动态互动 (${delay.inSeconds}s 后): $taskId');
  } catch (e) {
    debugPrint('安排 AI 动态互动失败: $e');
  }
}

/// 调度自动写信任务（每天一次，随机延迟 2-6 小时触发）
Future<void> scheduleLetterTask() async {
  if (!_supportsWorkmanager) {
    debugPrint('当前平台不支持 WorkManager，跳过 AI 来信后台调度');
    return;
  }

  try {
    await Workmanager().registerPeriodicTask(
      'ai_letter_periodic',
      bgTaskLetter,
      frequency: const Duration(hours: 24),
      initialDelay: const Duration(hours: 2),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      backoffPolicy: BackoffPolicy.linear,
      backoffPolicyDelay: const Duration(minutes: 30),
    );
    debugPrint('已安排 AI 来信周期任务');
  } catch (e) {
    debugPrint('安排 AI 来信任务失败: $e');
  }
}

/// 角色按人设/生活规律主动发朋友圈（约每 6 小时检查一次）
Future<void> scheduleMomentPostTask() async {
  if (!_supportsWorkmanager) {
    debugPrint('当前平台不支持 WorkManager，跳过 AI 朋友圈周期任务');
    return;
  }

  try {
    await Workmanager().registerPeriodicTask(
      'ai_moment_post_periodic',
      bgTaskMomentPost,
      frequency: const Duration(hours: 6),
      initialDelay: const Duration(minutes: 20),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      backoffPolicy: BackoffPolicy.linear,
      backoffPolicyDelay: const Duration(minutes: 15),
    );
    debugPrint('已安排 AI 朋友圈主动发布周期任务');
  } catch (e) {
    debugPrint('安排 AI 朋友圈任务失败: $e');
  }
}

bool get _supportsWorkmanager => Platform.isAndroid || Platform.isIOS;

/// 微信 iLink Bot 后台兜底轮询（15 分钟，Android WorkManager 最小粒度）。
/// 高频实时回复由前台 WeChatBotService 的 30s Timer 负责。
Future<void> scheduleWeChatPollTask() async {
  if (!_supportsWorkmanager) {
    debugPrint('当前平台不支持 WorkManager，跳过微信轮询周期任务');
    return;
  }

  try {
    await Workmanager().registerPeriodicTask(
      'wechat_poll_periodic',
      bgTaskWeChatPoll,
      frequency: const Duration(minutes: 15),
      initialDelay: const Duration(minutes: 5),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      backoffPolicy: BackoffPolicy.linear,
      backoffPolicyDelay: const Duration(minutes: 15),
    );
    debugPrint('已安排微信 iLink 轮询周期任务');
  } catch (e) {
    debugPrint('安排微信轮询任务失败: $e');
  }
}
