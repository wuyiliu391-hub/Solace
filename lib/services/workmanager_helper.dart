import 'package:workmanager/workmanager.dart';
import 'background_service.dart';
import 'workmanager_task_scheduler.dart';

Future<void> initWorkmanager() async {
  await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
  // 注册自动来信周期任务（每天一次，初始延迟 2 小时）
  await scheduleLetterTask();
  // 注册角色主动发朋友圈周期任务
  await scheduleMomentPostTask();
  // 注册微信 iLink 轮询兜底任务（15 分钟；未启用时 handler 内空转）
  await scheduleWeChatPollTask();
}
