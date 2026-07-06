import 'package:flutter/foundation.dart';

Future<void> scheduleCommentReplyTask({
  required String momentId,
  required String commentId,
  required String characterId,
  required int intimacyLevel,
  required Duration delay,
}) async {
  debugPrint('Web 平台不支持 WorkManager，跳过 AI 评论回复后台调度');
}

Future<void> scheduleMomentInteractionTask({
  required String momentId,
  required String characterId,
  required int intimacyLevel,
  required Duration delay,
}) async {
  debugPrint('Web 平台不支持 WorkManager，跳过 AI 动态互动后台调度');
}

Future<void> scheduleLetterTask() async {
  debugPrint('Web 平台不支持 WorkManager，跳过 AI 来信后台调度');
}
