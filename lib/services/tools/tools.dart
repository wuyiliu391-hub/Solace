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
import 'packages/workspace_tool_pkg.dart';
import 'packages/subagent_tool_pkg.dart';
import '../workspace_service.dart';
import '../llm_service.dart';

/// 创建并初始化全局工具注册表。
///
/// 所有设备能力必须在这里注册，避免自然语言路由和模型工具列表出现
/// “能识别但没有工具”或“有工具但模型看不到”的分裂状态。
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

ToolRegistry createWorkspaceToolRegistry({
  required WorkspaceService workspace,
  required String chatId,
  LlmService? llm,
}) {
  final registry = createToolRegistry();
  registry.register(WorkspaceToolPkg(workspace: workspace, chatId: chatId));
  if (llm != null) registry.register(SubagentToolPkg(llm));
  return registry;
}
