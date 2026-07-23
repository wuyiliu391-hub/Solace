library;

import 'tool.dart';
import 'tool_registry.dart';
import 'tool_executor.dart';
import 'agent_loop.dart';
import 'conversation_turn.dart';
import 'packages/system_operation_tool_pkg.dart';
import 'packages/app_info_tool_pkg.dart';
import 'packages/shell_tool_pkg.dart';
import 'packages/notification_tool_pkg.dart';
import 'packages/battery_tool_pkg.dart';
import 'packages/screenshot_tool_pkg.dart';
import 'packages/ui_automation_tool_pkg.dart';

/// 创建并初始化全局工具注册表
ToolRegistry createToolRegistry() {
  final registry = ToolRegistry();
  registry.register(SystemOperationToolPkg());
  registry.register(AppInfoToolPkg());
  registry.register(ShellToolPkg());
  registry.register(NotificationToolPkg());
  registry.register(BatteryToolPkg());
  registry.register(ScreenshotToolPkg());
  registry.register(UIAutomationToolPkg());
  return registry;
}
