Future<void> scheduleBackgroundTask({
  required String taskId,
  required String characterId,
  required String sessionId,
  required String userId,
  required int intimacyLevel,
  required int delayMinutes,
}) async {
  // Web 平台不支持后台任务
}

Future<void> cancelBackgroundTask(String uniqueName) async {
  // Web 平台不支持后台任务
}
