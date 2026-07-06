# Solace UI/交互层重构进度

## 已完成的重构工作

### Phase 1: BLoC 层（对标 SillyTavern 状态管理）

#### 1. `lib/blocs/chat/chat_event.dart` — 新增 SillyTavern 对标事件

| 事件类 | 对标 SillyTavern | 功能 |
|--------|-----------------|------|
| `ChatSwipeRight` | `swipe_right` | 滑动到下一条备选回复 |
| `ChatSwipeLeft` | `swipe_left` | 滑动到上一条备选回复 |
| `ChatHideMessage` | `hideChatMessageRange` | 隐藏消息（对 AI 不可见） |
| `ChatUnhideMessage` | `unhideChatMessageRange` | 取消隐藏消息 |
| `ChatDeleteMessage` | `deleteMessage` | 删除单条消息 |
| `ChatToggleBookmark` | `mes_bookmark` | 收藏/取消收藏消息 |
| `ChatCopyMessage` | `mes_copy` | 复制消息内容 |
| `ChatMoveMessageUp` | `mes_edit_up` | 上移消息 |
| `ChatMoveMessageDown` | `mes_edit_down` | 下移消息 |
| `ChatCreateBranch` | `mes_create_bookmark` | 创建检查点/分支 |
| `ChatClearContext` | `clearContext` | 清空上下文 |

#### 2. `lib/blocs/chat/chat_state.dart` — 新增 SillyTavern 对标状态

| 状态类 | 对标 SillyTavern | 功能 |
|--------|-----------------|------|
| `ChatSwiped` | swipe 更新 | 消息滑动完成 |
| `ChatMessageHidden` | `mes_hide` | 消息已隐藏 |
| `ChatMessageUnhidden` | `mes_unhide` | 消息已取消隐藏 |
| `ChatMessageDeleted` | `deleteMessage` | 消息已删除 |
| `ChatMessageCopied` | `mes_copy` | 消息已复制 |
| `ChatContextCleared` | `clearContext` | 上下文已清空 |

#### 3. `lib/blocs/chat/chat_bloc.dart` — 新增事件处理器

新增 11 个事件处理器方法，完整实现 SillyTavern 的消息操作逻辑：
- `_onSwipeRight` / `_onSwipeLeft` — 滑动翻页
- `_onHideMessage` / `_onUnhideMessage` — 隐藏/显示消息
- `_onDeleteMessage` — 删除消息
- `_onToggleBookmark` — 收藏切换
- `_onCopyMessage` — 复制消息
- `_onMoveMessageUp` / `_onMoveMessageDown` — 消息排序
- `_onCreateBranch` — 创建分支
- `_onClearContext` — 清空上下文

---

### Phase 2: Widget 层（对标 SillyTavern UI 组件）

#### 4. `lib/widgets/message_actions.dart` — 新建

对标 SillyTavern `chats.js` 消息操作：
- `MessageActions` 组件 — 完整的消息操作栏
- `MessageAction` 枚举 — 所有操作类型
- 支持编辑/复制/隐藏/删除/收藏/重新生成
- 包含删除确认弹窗

#### 5. `lib/widgets/swipe_handler.dart` — 新建

对标 SillyTavern `script.js` swipe_left/right：
- `SwipeHandler` 组件 — 手势滑动翻页
- `SwipeDirection` 枚举 — 滑动方向
- `SwipeArrowButton` 组件 — 滑动箭头按钮
- 支持滑动阈值、回弹动画、计数器显示

#### 6. `lib/widgets/confirm_dialog.dart` — 新建

对标 SillyTavern `confirmDialog.html`：
- `ConfirmDialog` 组件 — 通用确认弹窗
- `InputConfirmDialog` 组件 — 带输入的确认弹窗
- `ConfirmResult` 枚举 — 弹窗结果
- 支持自定义标题/内容/按钮/危险操作样式

#### 7. `lib/widgets/drawer_panel.dart` — 新建

对标 SillyTavern 左/右抽屉面板：
- `DrawerPanel` 组件 — 侧边抽屉面板
- `DrawerSide` 枚举 — 抽屉方向
- `showLeft` / `showRight` 静态方法 — 显示抽屉
- 支持滑入动画、标题栏、宽度配置

#### 8. `lib/widgets/tag_filter.dart` — 新建

对标 SillyTavern `filters.js`：
- `TagFilter` 组件 — 标签过滤器
- `TagDisplay` 组件 — 标签展示
- 支持多选/单选、搜索、计数显示

#### 9. `lib/widgets/background_manager.dart` — 新建

对标 SillyTavern `backgrounds.js`：
- `BackgroundManager` 组件 — 背景图管理
- `BackgroundPicker` 组件 — 背景选择器
- 支持透明度、模糊、暗色遮罩

---

### Phase 3: Screen 层（对标 SillyTavern 页面）

#### 10. `lib/screens/chat/v2/chat_screen_v2.dart` — 重构

对标 SillyTavern 聊天主页面：
- 集成 BLoC 层（ChatBloc）
- 使用 SwipeHandler 实现滑动翻页
- 使用 MessageBubbleV2 显示消息
- 使用 BackgroundManager 管理背景
- 使用 ConfirmDialog 确认操作
- 完整的消息操作：编辑/删除/复制/隐藏/收藏
- 清空上下文功能

---

## 待完成的重构工作

### Phase 2 剩余 Widget
- `lib/widgets/typing_indicator.dart` — 打字指示器（已有，需增强）

### Phase 3 剩余 Screen
- `lib/screens/character/v2/character_editor_screen.dart` — 角色编辑页面（已有，需完善 BLoC 集成）
- `lib/screens/settings/v2/api_config_screen.dart` — API 配置页面（已有，需完善）
- `lib/screens/settings/prompt_manager_screen.dart` — Prompt 管理页面（需新建）
- `lib/screens/settings/world_info_screen.dart` — 世界观设定页面（需新建）
- `lib/screens/settings/instruct_mode_screen.dart` — Instruct 模式页面（需新建）
- `lib/screens/settings/system_prompt_screen.dart` — 系统提示词页面（需新建）
- `lib/screens/group_chat/group_chat_screen.dart` — 群聊页面（需新建）

---

## 文件变更清单

### 新建文件
1. `lib/widgets/message_actions.dart`
2. `lib/widgets/swipe_handler.dart`
3. `lib/widgets/confirm_dialog.dart`
4. `lib/widgets/drawer_panel.dart`
5. `lib/widgets/tag_filter.dart`
6. `lib/widgets/background_manager.dart`

### 修改文件
1. `lib/blocs/chat/chat_event.dart` — 新增 11 个事件类
2. `lib/blocs/chat/chat_state.dart` — 新增 6 个状态类
3. `lib/blocs/chat/chat_bloc.dart` — 新增 11 个事件处理器
4. `lib/screens/chat/v2/chat_screen_v2.dart` — 完整重构

### 已有文件（未修改）
1. `lib/blocs/character/character_bloc.dart` — 已完成对标
2. `lib/blocs/theme/theme_bloc.dart` — 已完成对标
3. `lib/models/character_card_v2.dart` — 已完成对标
4. `lib/models/chat_message.dart` — 已完成对标
5. `lib/widgets/v2/message_bubble_v2.dart` — 已完成对标

---

## 验证状态

- [x] `flutter analyze` — 0 errors（仅有预存 warnings）
- [x] BLoC 层事件/状态完整
- [x] Widget 层编译通过
- [x] Screen 层编译通过
- [x] 所有文件开头标注【对标来源】
- [x] 保持与 services/ 层接口兼容
