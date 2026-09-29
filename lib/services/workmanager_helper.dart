import 'package:workmanager/workmanager.dart';
import '../repositories/local_storage_repository.dart';
import 'ai_usage_gate.dart';
import 'background_service.dart';
import 'workmanager_task_scheduler.dart';

Future<void> initWorkmanager(LocalStorageRepository storage) async {
  await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
  // 按用户「AI 消耗控制」决定是否注册周期任务（handler 内还会再判一次）
  if (AiUsageGate.allow(storage, AiUsageFeature.letter)) {
    await scheduleLetterTask();
  }
  if (AiUsageGate.allow(storage, AiUsageFeature.momentPost)) {
    await scheduleMomentPostTask();
  }
  if (AiUsageGate.allow(storage, AiUsageFeature.wechatPoll)) {
    await scheduleWeChatPollTask();
  }
}
