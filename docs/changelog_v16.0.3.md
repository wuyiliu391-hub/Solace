# v16.0.3 更新日志

**版本号**: 16.0.3 (Build 264)
**发布日期**: 2026-06-25

## 🧹 朋友圈动态 AI 思考过程泄露修复

- 修复 AI 发布朋友圈动态时，内部思考过程（"用户让我分享生活"、"我来分析一下"等）被当作正文展示的问题
- 新增 `<MOMENT>` 结构化标签提取，优先从标签内取值，隔离思考与正文
- 兜底清理从"整行丢弃"优化为"句子级过滤"，避免误删正常文案
- 新增测试用例覆盖 4 种典型场景（标签提取、无标签推理、空白内容、纯文本）

## 🌐 发现页"世界"功能入口禁用

- 隐藏发现页"人生系统"入口卡片
- 禁用 `/world` 路由跳转
- 关闭 WorldEngine 初始化，减少启动时无效计算

## 💬 消息发送反馈与 CRUD 修复

- 用户发送消息后立即显示"正在输入..."指示器，不再等待风控校验完成后才出现
- 修复消息编辑后 UI 不刷新的问题：`buildWhen` 现在检测内容变化，不仅比较数量
- `ChatDeleteMessage` / `ChatEditAIReply` / `ChatToggleBookmark` 操作后均正确触发列表重建

## 🔄 流式输出中断保护

- 新增逐 chunk 超时机制（60 秒无新数据自动中断），防止切换模型后流式连接挂起
- 流式超时时若已有部分内容，正常返回而非丢弃
- 流式中断后内容过短（< 5 字）自动清空并触发非流式兜底，避免返回截断残句

## 🤖 角色身份防泄露强化

- 系统 prompt 新增第 6 条铁律：绝对禁止声明 AI 身份，即使用户直接询问也必须以角色身份回避
- 拒绝检测正则新增匹配：`我是AI`、`我是人工智能`、`作为AI`、`实际上...是AI` 等变体
- 检测到身份泄露后自动触发重试 + 兜底回复

## 📭 AI 回复空白兜底

- 所有处理流程（流式/非流式/Agent/BT 动作剥离）完成后，若回复仍为空，自动使用兜底文案
- 避免用户发送消息后完全看不到任何回复

## 🌙 深色模式适配

- **酒馆群聊**：角色气泡颜色改为主题自适应，深色模式下使用深色背景替代原有浅色贴纸色
- **幸运转盘**：分隔线、中心圆、外圈边框、装饰点全部支持主题颜色传入，深色模式下降低亮度避免刺眼

## 📋 技术细节

### 修改文件清单

| 文件 | 修改内容 |
|------|----------|
| `lib/services/ai_moment_service.dart` | `extractFinalMomentContent` 结构化提取 + 句子级兜底清理 |
| `lib/main.dart` | 注释 World 路由、入口卡片、WorldEngine 初始化 |
| `lib/blocs/chat/chat_bloc.dart` | 即时 Typing 指示、截断内容兜底、空白回复 fallback、身份泄露检测扩展 |
| `lib/services/ai_service.dart` | 流式 chunk 超时保护、系统 prompt 反 AI 身份铁律 |
| `lib/screens/chat/chat_detail_screen.dart` | `buildWhen` 支持内容变化检测 |
| `lib/screens/group_chat/group_chat_detail_screen.dart` | `_roleColorsForTheme` 深色模式适配 |
| `lib/screens/games/lucky_wheel_screen.dart` | `WheelPainter.borderColor` 主题传入 |
| `test/ai_moment_clean_test.dart` | 4 条 P1 测试用例 |
