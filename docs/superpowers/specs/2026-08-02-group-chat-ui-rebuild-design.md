# 群聊 UI 重写设计 — 对标 SillyTavern 交互

**日期:** 2026-08-02
**状态:** 已批准
**范围:** 群聊三页 UI 全部重写（list / detail / create），引擎仅加一个内存态多角色锁定事件。

## 目标

把 Solace 群聊前端重写成 SillyTavern 级别的交互，但**严格沿用 Solace 现有主题风格与颜色**（`Theme.of(context).colorScheme`，双轴 `ThemeMode` + `VisualStyle`）。不动引擎核心逻辑（策略/模式/接话轮询已在 Task 1-9 完成）。

## 设计原则

1. **组件拆分**：新开 `lib/widgets/group_chat/` 目录，screen 变薄，便于独立理解与测试。
2. **主题一致**：全部用 `colorScheme`，不引入硬编码色（仅错误红 `Color(0xFFE53935)` 沿用现有）。
3. **角色色**：`colorHex` 配置优先 → 哈希生成稳定色兜底；深色模式自动降透明度保证可读。
4. **引擎隔离**：多角色锁定是**内存态**（会话级，对标 ST 不落库），不污染 DB 模型。

## 文件结构

```
lib/utils/character_color.dart          # 新增：角色色解析（colorHex→哈希兜底）
lib/widgets/group_chat/
  member_activation_bar.dart            # 新增：输入框上方成员头像条（单击锁定/长按多选）
  group_message_bubble.dart             # 新增：角色色消息气泡
  group_top_bar.dart                    # 新增：消息区顶部悬浮条（聊天记录名+Auto-Reply）
  group_member_drawer.dart              # 新增：侧滑成员面板（静音/移除/激活/角色色）
lib/models/ai_character.dart            # 修改：+ colorHex 可空字段（无需 DB 迁移）
lib/blocs/group_chat/group_chat_event.dart  # 修改：+ GroupChatSetSpeakers
lib/blocs/group_chat/group_chat_bloc.dart   # 修改：内存 _forcedSpeakers + 处理事件
lib/screens/group_chat/group_chat_list_screen.dart     # 重写 UI 层
lib/screens/group_chat/group_chat_detail_screen.dart   # 重写 UI 层
lib/screens/group_chat/group_chat_create_screen.dart   # 重写 UI 层
```

## 组件规格

### 1. `character_color.dart`
```dart
Color characterColor({String? colorHex, required String name, required ColorScheme cs})
```
- `colorHex` 可解析（#RRGGBB / RRGGBB）→ 用该色。
- 否则哈希 `name.codeUnits` 加权 → HSV 色相固定，饱和/明度按主题明暗微调，保证与背景可读。
- 同一角色永远同色（纯函数，无随机）。
- 测试：`test/character_color_test.dart` —— 同名同色、不同名大概率不同色、浅深色模式均返回可读色。

### 2. `member_activation_bar.dart`
- 输入框上方横排头像，`horizontal ListView`，角色色描边圆头像。
- **单击**：锁定该角色（高亮 + 底部角标"发"），再次点击取消。
- **长按**：进入多选模式（StatefulWidget 内部状态），顶部出现"已锁定 N 人 / 完成 / 取消"操作条；多选模式下点击多个头像叠加锁定。
- 锁定状态 → 回调 `onSpeakersChanged(List<String> ids)` → detail screen 发 `GroupChatSetSpeakers`。
- 禁言成员置灰不可点。
- 空群（无 AI 成员）不渲染。

### 3. `group_message_bubble.dart`
- AI 消息（左排）：角色色圆头像 + 角色色名字 + 角色色淡底气泡（`withValues(alpha: 深色模式 0.18 / 浅色 0.10)`）。
- 同角色连续消息保留名字（ST 每条带名）。
- 系统消息：居中灰条（沿用现有）。
- 用户消息：右对齐主色气泡（沿用现有 Solace 样式，不改）。
- 图片消息：角色色边框包裹（沿用现有内部逻辑）。

### 4. `group_top_bar.dart`
- 消息区顶部悬浮圆角小条（`Positioned` 于 ListView 上方，左右留白）。
- 左：当前聊天记录名 + 下拉箭头 → 点击弹分支切换 sheet（复用现有 `_showBranchManager` 逻辑）。
- 右：Auto-Reply 开关 → 联动 `autoModeEnabled`（`GroupChatUpdateConfig`），ON 时主色点亮 + 小字"自动接话中"。

### 5. `group_member_drawer.dart`
- `endDrawer` 侧滑面板：全员列表。
- 每行：角色色头像 + 名字（用户显示"我"）+ 角色色名字。
- 尾部操作：禁言开关（`disabledMemberIds` 联动 `GroupChatUpdateConfig`）、移除按钮（`GroupChatRemoveMember`）、点名字切换手动激活（`GroupChatSetSpeakers`）。
- 与激活条状态实时同步（同一 `_forcedSpeakers` 来源）。

### 6. `AICharacter.colorHex`
- 新增 `final String? colorHex;` 字段（可空）。
- 构造默认 null；`copyWith`/`toMap`/`fromMap` 兜底；`props` 加入。
- **无需 DB 迁移**：SQLite 读取时该列不存在 → 兜底 null；写入时忽略未知列。角色编辑器暂不提供入口（后续）。

### 7. 引擎：`GroupChatSetSpeakers`
- `group_chat_event.dart` 加 `class GroupChatSetSpeakers extends GroupChatEvent { groupId; List<String> speakerIds; }`。
- bloc 加内存 `final Map<String, List<String>> _forcedSpeakers = {};`
- 处理：存/清 map。
- `_generateAIReplies` 中：`_forcedSpeakers[groupId]` 非空 → 激活列表 = 强制 ids 过滤禁言（忽略策略）；为空 → 原策略逻辑。locked 时 UI 显示策略"手动"。
- `close()` 清理（已有）。

## 页面规格

### 详情页（重写 UI 层，保留全部现有功能）
- AppBar：群名前成员头像堆叠（点击=侧滑面板）+ 通知/菜单。
- 顶部悬浮条 `group_top_bar`。
- 消息流 `group_message_bubble` 替换现有 `_MessageBubble`。
- 成员激活条 `member_activation_bar`（输入框上方）。
- 侧滑面板 `group_member_drawer`。
- 现有功能保留：设置 sheet（引擎配置）、分支管理、邀请、成员管理、重命名、公告、删除、图片。

### 列表页
- 群头像 → 成员头像 3 张重叠拼接（角色色描边），无成员显示"群"字兜底。
- 摘要："发言人: 内容"（最近一条消息带发言人，用户显示"我"）。
- 置顶/未读角标/长按菜单保留。

### 创建页
- 角色选择：大图卡片 + ReorderableListView（拖拽排序决定发言顺序）。
- 底部已选成员横向条（可点击移除）。
- 创建后跳详情页（现有逻辑保留）。

## 数据流

```
UI 锁定/解锁 ── GroupChatSetSpeakers ──> bloc._forcedSpeakers
                                              │
UI 发消息 ── GroupChatSendMessage ──> _generateAIReplies
                                              │
                              _forcedSpeakers 非空 ? 强制列表 : selectSpeakers(策略)
                                              ▼
                                    逐个生成/APPEND
```

## 测试计划
- `test/character_color_test.dart`：纯函数，3-4 用例。
- 引擎锁定路径测试（并入 `test/group_chat_bloc_engine_test.dart` 或新文件）：锁定时激活列表=强制 id 且过滤禁言。
- 现有 22 个群聊测试保持全 PASS。
- analyze 无新增 error。
- 不打包（用户已确认）。

## 不做的事
- 不动 DB schema（colorHex 走列兜底）。
- 不引入新依赖。
- 不重写引擎策略/接话逻辑。
- 不引入图片取主色（复杂且网络图不可靠，靠 colorHex+哈希）。
- 不做 ST 的桌面端分栏布局（手机单屏）。
