# 群聊 7 项修复设计

**日期:** 2026-08-02
**状态:** 待审阅
**范围:** 群聊 UI 7 项：头像上传/展示、顶部栏汉化、发送图标、流式时序、角色栏头像/溢出、设置弹窗溢出。

## 根因与方案

### 1. 群聊头像上传 + 圆形展示替换毛毛虫

**现状**：`GroupChatSession.avatarUrl` 字段全链路存在但零 UI；创建页无头像；列表/详情用 3 头像拼接"毛毛虫"。

**方案**：
- 创建页（`group_chat_create_screen.dart`）群名下方加 `AvatarPicker`（`lib/widgets/avatar_picker.dart`，size 80）。它选图后**复制到 `docs/avatars` 持久目录**（L278-292，非临时目录，防丢失），回调返回本地路径。
- `GroupChatCreate` 事件已有 `avatarUrl` 可选参数（event.dart L22/28）——创建时传入。
- 列表页 `_memberStack`（list L495）：改签名接收 `session.avatarUrl`；非空 → 48×48 圆形头像（`AvatarResolver.imageWidget` + errorBuilder 兜底），为空 → 保留现有毛毛虫。
- 详情页 `_memberStackAvatar`（detail L373）：同上，非空 → 圆形头像替换文字栈。

### 2. 顶部栏 Auto-Reply 汉化

`group_top_bar.dart` L63：`'Auto-Reply'` → `'自动回复'`；开启态 `'自动接话中'` 保持。

### 3. 发送按钮图标

`group_chat_detail_screen.dart` L511 `Icons.send` → 自定义 CustomPainter：**先横向、右端向上直角弯折 90°、顶端箭头尖朝上**（stroke 折线 + 箭头）。私有 `_SendArrowIcon` widget，24×24，白色，置于现有 CircleAvatar 内。

### 4. 流式输出时序修复（根因已定位）

**根因**：`getGroupChatMessages` 返回 DESC（最新在 index 0），列表 `reverse: true` → index 0 = 视觉底部。但流式消息 `displayMessages.add(...)` **追加到数组末尾**（detail L306）→ 渲染在最顶部；完成后 AI 消息落库出现在底部 → 文字"从顶部跳到底部"。`_TypingIndicator` 同样用 `index == displayMessages.length`（L345）渲染在顶部。`state.messages` 是死数据（bloc 每 chunk 拉库传的无人用）。

**方案**（对齐单聊"流式消息原位更新"逻辑）：
- 流式/打字消息 **`insert(0, ...)`**（DESC 列表头部 = 视觉底部），`_TypingIndicator` 判定改 `index == 0`。
- `showAvatar` 改完全基于 `displayMessages` 自身相邻判定（`displayMessages[index-1].senderId != msg.senderId`），消除流式期间 `_messages` 索引错位。
- `GroupChatMessagesLoaded` 分支清空 `_streamingCharacter/_streamingText` 残留。
- 保留群聊角色色气泡组件 `GroupMessageBubble`（多角色色彩不能套单聊气泡），复用单聊的流式原位更新模式。

### 5. 底部角色栏头像丢失

**根因**：`member_activation_bar.dart` L164 与 `group_chat_list_screen.dart` L544 裸 `Image.network`，本地路径/asset 头像裂图退回占位。

**方案**：换 `AvatarResolver.imageWidget(url, width, height, onError: 首字母兜底)` 统一处理 asset/本地/网络（与单聊 `chat_detail_screen` 一致）。同修 create 页角色列表头像（L168-190）。

### 6. 底部角色栏垂直溢出

**根因**：`SizedBox(height:60)` + 垂直 padding 6 → 可用 48px；内容 38 头像 + 2 gap + 9px 字号名字行 ≈ 50.5px → 溢出 2-3px。

**方案**：`height: 60 → 64`（可用 52px > 50.5px），消除 debug 黄黑条。

### 7. 设置弹窗高度溢出

**根因**：`showModalBottomSheet`（detail L631）无 `isScrollControlled`，非滚动 modal 高度上限为屏幕 9/16；内容约 11 个 ListTile ≈ 700px → 底部"自动接话间隔/禁言成员/群信息"被裁、不可滚动。

**方案**：加 `isScrollControlled: true`；内容 Column 外套 `SingleChildScrollView` + `BoxConstraints(maxHeight: 屏幕高 × 0.85)`。

## 文件清单

| 文件 | 改动 |
|---|---|
| `lib/screens/group_chat/group_chat_create_screen.dart` | +AvatarPicker，创建传 avatarUrl |
| `lib/screens/group_chat/group_chat_list_screen.dart` | _memberStack 接 avatarUrl + AvatarResolver |
| `lib/screens/group_chat/group_chat_detail_screen.dart` | _memberStackAvatar 头像、_SendArrowIcon、流式 insert(0)、设置弹窗滚动 |
| `lib/widgets/group_chat/group_top_bar.dart` | 汉化 |
| `lib/widgets/group_chat/member_activation_bar.dart` | AvatarResolver + height 64 |
| `lib/blocs/group_chat/group_chat_bloc.dart` | 无（事件/写入已支持 avatarUrl） |

## 验证

- `flutter analyze` 0 新增 error
- 群聊测试回归（group_chat_bloc_engine / forced_speaker / branch_model）
- 全量测试无新增失败
- 手工核对：创建群选头像→列表/详情显示圆形头像；无头像群显示毛毛虫；流式消息出现在底部逐字输出；角色栏无溢出；设置弹窗可滚动到底
