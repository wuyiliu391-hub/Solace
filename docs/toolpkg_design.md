# Solace ToolPkg 系统设计

## 目标

在单聊中让 AI 真正具备设备操控能力，效果与 Operit 一致：
- AI 根据用户语义主动选择工具
- 支持多步骤、条件、循环组合
- 工具可扩展、可注册、有权限声明
- 执行过程可追踪、可展示

## 设计原则

1. **LLM 负责意图理解与规划**，不直接执行命令
2. **工具层负责执行**，每个工具独立、可测试、可复用
3. **Agent Loop 负责调度**：解析工具调用 → 执行 → 把结果返回给 LLM → 直到完成
4. **OpenAI function calling 作为工具描述标准**，兼容大多数模型
5. **权限检查在工具执行前完成**，缺权限时引导用户开启
6. **Solace 自杀保护**：任何工具不得执行 `am force-stop com.solace.solace`

## 架构层次

```
┌─────────────────────────────────────┐
│  ChatBloc / UI 层                   │
│  - 把用户消息交给 AgentLoop         │
│  - 展示工具执行过程与最终结果       │
├─────────────────────────────────────┤
│  Agent Loop                         │
│  - 构建系统提示                     │
│  - 调用 LLM (chatWithTools)         │
│  - 解析 tool_calls                  │
│  - 调用 ToolExecutor                │
│  - 循环直到 LLM 返回最终内容        │
├─────────────────────────────────────┤
│  ToolRegistry / ToolPkg             │
│  - 注册所有工具                     │
│  - 提供工具 OpenAI schema           │
├─────────────────────────────────────┤
│  ToolExecutor                       │
│  - 权限检查                         │
│  - 执行单个工具                     │
│  - 结果格式化返回                   │
├─────────────────────────────────────┤
│  具体工具实现                       │
│  - SystemOperationToolPkg           │
│  - AppInfoToolPkg                   │
│  - ShellToolPkg                     │
│  - NotificationToolPkg              │
│  - BatteryToolPkg                   │
│  - ScreenshotToolPkg                │
│  - UIAutomationToolPkg              │
└─────────────────────────────────────┘
```

## 核心接口

### Tool

```dart
abstract class Tool {
  String get name;
  String get description;
  Map<String, dynamic> get parametersSchema;
  Set<String> get requiredPermissions;
  bool get isDestructive;

  Future<ToolResult> execute(Map<String, dynamic> args);
}
```

### ToolPkg

```dart
abstract class ToolPkg {
  String get name;
  String get description;
  List<Tool> get tools;
}
```

### ToolResult

```dart
class ToolResult {
  final bool success;
  final String message;
  final Map<String, dynamic>? data;
  final String? errorCode;
  final bool needsPermission;
  final String? permissionName;

  const ToolResult({...});
}
```

### ToolRegistry

```dart
class ToolRegistry {
  final List<ToolPkg> _packages = [];

  void register(ToolPkg pkg);
  Tool? findTool(String name);
  List<Map<String, dynamic>> toOpenAIFormat();
}
```

### ToolExecutor

```dart
class ToolExecutor {
  final ToolRegistry registry;

  Future<ToolExecutionRecord> execute(String toolName, Map<String, dynamic> args);
}
```

### AgentLoop

```dart
class AgentLoop {
  final ToolRegistry registry;
  final ToolExecutor executor;

  Future<AgentLoopResult> run({
    required String userMessage,
    required List<Map<String, dynamic>> messages,
    required LlmService llmService,
    int maxSteps = 10,
    Function(AgentStep)? onStep,
  });
}
```

## LLM 提示设计

### 系统提示

```
你是 Solace 的 AI 助手，可以通过调用工具帮助用户操控手机。

当前可用工具：
{tools_description}

规则：
1. 如果用户请求可以用工具完成，必须输出工具调用，不要只回复文字。
2. 复杂任务可以分多步调用工具，每一步基于上一步结果调整。
3. 缺权限时向用户说明需要开启什么权限，不要反复尝试。
4. 不能执行任何会关闭 Solace 自身的命令（com.solace.solace）。
5. 执行完成后用自然语言总结结果。

回复格式：
- 工具调用：使用 OpenAI function calling 格式
- 最终回复：直接输出文字
```

### 工具调用解析

LLM 返回 `tool_calls` 数组，每个元素包含：
- `function.name`: 工具名
- `function.arguments`: JSON 字符串，包含参数

AgentLoop 解析后执行，并把结果以 `tool` 角色消息追加回对话，继续调用 LLM。

## 工具列表（第一阶段）

### SystemOperationToolPkg

- `open_app`: 打开应用（包名或应用名）
- `close_app`: 关闭应用
- `lock_screen`: 锁屏
- `adjust_volume`: 调节音量
- `set_mute`: 设置静音模式
- `toggle_wifi`: 开关 WiFi
- `toggle_bluetooth`: 开关蓝牙
- `set_brightness`: 设置亮度
- `open_gallery`: 打开相册

### AppInfoToolPkg

- `get_installed_apps`: 获取已安装应用列表
- `get_app_usage_time`: 获取应用使用时间
- `get_current_app`: 获取当前前台应用

### ShellToolPkg

- `execute_shell`: 执行任意 shell 命令（危险操作标记）
- `list_shell_examples`: 列出可用 shell 命令示例

### NotificationToolPkg

- `get_notifications`: 获取最近通知
- `get_notification_count`: 获取通知数量

### BatteryToolPkg

- `get_battery_info`: 获取电池信息

### ScreenshotToolPkg

- `take_screenshot`: 截图

### UIAutomationToolPkg

- `tap`: 点击屏幕坐标
- `swipe`: 滑动屏幕
- `input_text`: 输入文本
- `press_key`: 按键

## 执行循环流程

```
1. 用户输入消息
2. AgentLoop 构建系统提示 + 历史消息
3. 调用 LLM(chatWithTools)
4. 如果 LLM 返回 tool_calls:
   a. 对每个 tool_call:
      - 解析参数
      - 检查权限
      - 调用 ToolExecutor
      - 记录结果
   b. 把 tool 结果追加到 messages
   c. 再次调用 LLM
5. 如果 LLM 返回普通内容，作为最终回复
6. 返回 AgentLoopResult（包含执行记录和最终回复）
```

## 与 ChatBloc 集成

1. 在 `_onSendMessage` 中检测到工具请求时，调用 `AgentLoop.run`
2. 保存用户消息
3. 循环中每执行一步，通过 `onStep` 回调更新 UI 状态消息
4. 最终保存 AI 回复消息，包含工具执行记录（trace）
5. 如果 LLM 没有调用工具，回退到普通 AI 回复

## 安全策略

1. 自杀保护：所有涉及 `com.solace.solace` 的 force-stop 一律拒绝
2. 危险命令：shell 执行需要二次确认或白名单
3. 权限隔离：每个工具声明所需权限，执行前检查
4. 执行日志：所有工具调用记录到本地日志

## 文件规划

```
lib/services/tools/
├── tool.dart
├── tool_pkg.dart
├── tool_registry.dart
├── tool_executor.dart
├── tool_result.dart
├── agent_loop.dart
└── packages/
    ├── system_operation_tool_pkg.dart
    ├── app_info_tool_pkg.dart
    ├── shell_tool_pkg.dart
    ├── notification_tool_pkg.dart
    ├── battery_tool_pkg.dart
    ├── screenshot_tool_pkg.dart
    └── ui_automation_tool_pkg.dart
```

## 实施顺序

1. 创建核心抽象和工具注册表
2. 把所有现有 Shizuku/API 能力封装为工具包
3. 重写 AgentLoop 为 LLM 工具循环
4. 接入 ChatBloc
5. 更新 UI 和能力手册
6. 测试和迭代
