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

bool get _supportsWorkmanager => Platform.isAndroid || Platform.isIOS;
