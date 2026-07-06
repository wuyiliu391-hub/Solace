import 'package:workmanager/workmanager.dart';
import 'background_service.dart';

Future<void> scheduleBackgroundTask({
  required String taskId,
  required String characterId,
  required String sessionId,
  required String userId,
  required int intimacyLevel,
  required int delayMinutes,
}) async {
  await Workmanager().registerOneOffTask(
    taskId,
    bgTaskName,
    inputData: {
      'characterId': characterId,
      'sessionId': sessionId,
      'userId': userId,
      'intimacyLevel': intimacyLevel,
    },
    initialDelay: Duration(minutes: delayMinutes),
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingWorkPolicy.replace,
    backoffPolicy: BackoffPolicy.linear,
    backoffPolicyDelay: Duration(minutes: 1),
  );
}

Future<void> cancelBackgroundTask(String uniqueName) async {
  await Workmanager().cancelByUniqueName(uniqueName);
}
