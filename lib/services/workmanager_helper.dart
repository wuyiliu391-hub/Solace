import 'package:workmanager/workmanager.dart';
import 'background_service.dart';
import 'workmanager_task_scheduler.dart';

Future<void> initWorkmanager() async {
  await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
  // 注册自动来信周期任务（每天一次，初始延迟 2 小时）
  await scheduleLetterTask();
}
