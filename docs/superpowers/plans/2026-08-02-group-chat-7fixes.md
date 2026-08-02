# 群聊 7 项修复 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 完成群聊 7 项修复：头像上传/展示、顶部栏汉化、发送图标、流式时序、角色栏头像/溢出、设置弹窗溢出。

**Architecture:** ① 创建页复用 `AvatarPicker`（持久目录存储）上传头像，走既有 `GroupChatCreate.avatarUrl` 链路；② 列表/详情用 `AvatarResolver.imageWidget` 渲染圆形头像，无则保留毛毛虫兜底；③ 流式消息改为 `insert(0)`（DESC 列表头部=视觉底部）；④ 其余为纯 UI 微调。

**Tech Stack:** Flutter / Dart，flutter_bloc，image_picker，path_provider。

**设计文档:** `docs/superpowers/specs/2026-08-02-group-chat-7fixes-design.md`（已批准）

---

### Task 1: 创建页群头像上传

**Files:**
- Modify: `lib/screens/group_chat/group_chat_create_screen.dart`

**说明:** `AvatarPicker` 已具备选图→复制到 `docs/avatars` 持久目录→回调路径的全部逻辑（avatar_picker.dart:278-292），直接复用。无独立 widget 测试（pump 需全套 RepositoryProvider 基建，仓库无先例），靠 analyze + 手工验证。

- [ ] **Step 1: 加 import 与状态字段**

`group_chat_create_screen.dart` 顶部 import 区（现有 9 行 import 后）加：
```dart
import '../../widgets/avatar_picker.dart';
```

`_GroupChatCreateScreenState` 内（`_selectedAiCharacterIds` 声明处附近）加：
```dart
  String? _avatarUrl;
```

- [ ] **Step 2: 群名下方插入 AvatarPicker**

`build` 中群名 TextField Padding（L70-84）之后、`_buildSelectedBar` 之前插入：
```dart
                // 群头像（可选，选图自动存持久目录防丢失）
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Center(
                    child: AvatarPicker(
                      currentAvatar: _avatarUrl,
                      onAvatarSelected: (path) =>
                          setState(() => _avatarUrl = path),
                      size: 80,
                    ),
                  ),
                ),
```

- [ ] **Step 3: 创建时传 avatarUrl**

`_createGroup`（L243-248）的 `GroupChatCreate` 加参数：
```dart
    bloc.add(GroupChatCreate(
      userId: userId,
      name: _nameController.text.trim(),
      avatarUrl: _avatarUrl,
      memberIds: memberIds,
      aiCharacterIds: List<String>.from(_selectedAiCharacterIds),
    ));
```

- [ ] **Step 4: 验证**

Run: `flutter analyze lib/screens/group_chat/group_chat_create_screen.dart`
Expected: 0 新增 error

- [ ] **Step 5: 提交**

```bash
git add lib/screens/group_chat/group_chat_create_screen.dart
git commit -m "feat: 创建群聊支持上传自定义头像（持久目录存储）"
```

---

### Task 2: 列表/详情圆形头像替换毛毛虫

**Files:**
- Modify: `lib/screens/group_chat/group_chat_list_screen.dart`
- Modify: `lib/screens/group_chat/group_chat_detail_screen.dart`

- [ ] **Step 1: list 页 `_memberStack` 接 session.avatarUrl**

`group_chat_list_screen.dart` 顶部 import 区加：
```dart
import '../../utils/avatar_resolver.dart';
```

调用处（L301）`_memberStack(members, colorScheme)` 改为：
```dart
            _memberStack(session.avatarUrl, members, colorScheme),
```

`_memberStack`（L495）签名与开头改为：
```dart
  Widget _memberStack(String? avatarUrl, List<AICharacter> members,
      ColorScheme cs) {
    // 自定义群头像优先；无则回退成员拼接
    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      return Container(
        width: 48,
        height: 48,
        clipBehavior: Clip.antiAlias,
        decoration: const BoxDecoration(shape: BoxShape.circle),
        child: AvatarResolver.imageWidget(
          avatarUrl,
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          onError: () => _groupAvatarFallback(cs),
        ) ??
            _groupAvatarFallback(cs),
      );
    }
    final shown = members.take(3).toList();
    if (shown.isEmpty) {
      return Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: cs.tertiaryContainer,
        ),
        child: Center(
          child: Text('群',
              style: TextStyle(
                  color: cs.tertiary,
                  fontSize: 18,
                  fontWeight: FontWeight.w600)),
        ),
      );
    }
    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              left: i * 13,
              top: i * 8,
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: cs.surfaceContainerHighest,
                  border: Border.all(color: cs.surface, width: 2),
                ),
                child: ClipOval(
                  child: _miniAvatar(shown[i], cs),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _groupAvatarFallback(ColorScheme cs) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: cs.tertiaryContainer,
      ),
      child: Center(
        child: Text('群',
            style: TextStyle(
                color: cs.tertiary, fontSize: 18, fontWeight: FontWeight.w600)),
      ),
    );
  }
```

- [ ] **Step 2: list 页 `_miniAvatar` 换 AvatarResolver**

`_miniAvatar`（L541-551）替换为：
```dart
  Widget _miniAvatar(AICharacter c, ColorScheme cs) {
    final color = characterColor(colorHex: c.colorHex, name: c.name, cs: cs);
    final img = AvatarResolver.imageWidget(
      c.avatarUrl,
      fit: BoxFit.cover,
      onError: () => _miniAvatarText(c, color),
    );
    if (img != null) return img;
    return _miniAvatarText(c, color);
  }
```

- [ ] **Step 3: detail 页 `_memberStackAvatar` 加群头像优先**

`group_chat_detail_screen.dart` 顶部 import 区确认有 `avatar_resolver.dart`（若无则加 `import '../../utils/avatar_resolver.dart';`）。

`_memberStackAvatar`（L373）开头插入群头像优先分支：
```dart
  Widget _memberStackAvatar() {
    final cs = Theme.of(context).colorScheme;
    final avatarUrl = _session.avatarUrl;
    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      return SizedBox(
        width: 40,
        height: 30,
        child: Center(
          child: ClipOval(
            child: AvatarResolver.imageWidget(
              avatarUrl,
              width: 32,
              height: 32,
              fit: BoxFit.cover,
              onError: () => const Icon(Icons.group, size: 14),
            ),
          ),
        ),
      );
    }
    final shown = _members.take(3).toList();
    if (shown.isEmpty) {
      return CircleAvatar(
        radius: 12,
        backgroundColor: cs.tertiaryContainer,
        child: Icon(Icons.group, size: 14, color: cs.tertiary),
      );
    }
```

（其余 `shown` 逻辑保持不动，仅开头插入上述分支。）

- [ ] **Step 4: 验证**

Run: `flutter analyze lib/screens/group_chat/group_chat_list_screen.dart lib/screens/group_chat/group_chat_detail_screen.dart`
Expected: 0 新增 error

- [ ] **Step 5: 提交**

```bash
git add lib/screens/group_chat/group_chat_list_screen.dart lib/screens/group_chat/group_chat_detail_screen.dart
git commit -m "feat: 群聊列表/详情显示自定义圆形头像（无则保留毛毛虫兜底）"
```

---

### Task 3: 顶部栏 Auto-Reply 汉化

**Files:**
- Modify: `lib/widgets/group_chat/group_top_bar.dart:63`

- [ ] **Step 1: 替换文案**

`group_top_bar.dart` L63：
```dart
                autoModeEnabled ? '自动接话中' : 'Auto-Reply',
```
改为：
```dart
                autoModeEnabled ? '自动接话中' : '自动回复',
```

- [ ] **Step 2: 验证**

Run: `flutter analyze lib/widgets/group_chat/group_top_bar.dart`
Expected: 0 新增 error

- [ ] **Step 3: 提交**

```bash
git add lib/widgets/group_chat/group_top_bar.dart
git commit -m "feat: 顶部栏 Auto-Reply 汉化为自动回复"
```

---

### Task 4: 发送按钮图标（自定义箭头）

**Files:**
- Modify: `lib/screens/group_chat/group_chat_detail_screen.dart`

- [ ] **Step 1: 新增 `_SendArrowIcon` widget**

在 `_buildInputBar` 方法之前插入私有 widget：

```dart
  /// 发送箭头：先横向、右端向上直角弯折 90°、顶端箭头尖朝上
  Widget _sendArrowIcon() {
    return CustomPaint(
      size: const Size(20, 20),
      painter: _SendArrowPainter(),
    );
  }
```

文件底部（类结尾 `}` 之后）新增 painter：

```dart
/// 先横向、再向上直角弯折 90° 的箭头（箭头尖朝上）
class _SendArrowPainter extends CustomPainter {
  const _SendArrowPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final w = size.width;
    final h = size.height;
    final path = Path();
    // 横向线段
    path.moveTo(2, h - 4);
    path.lineTo(w - 4, h - 4);
    // 右端向上直角弯折 90°
    path.lineTo(w - 4, 6);
    // 箭头尖朝上（左右两条斜线）
    path.moveTo(w - 4, 6);
    path.lineTo(w - 9.5, 2);
    path.moveTo(w - 4, 6);
    path.lineTo(w + 1.5, 2);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
```

- [ ] **Step 2: 替换发送按钮图标**

`_buildInputBar` 发送按钮（L510-512）：
```dart
                child: IconButton(
                  icon: const Icon(Icons.send, color: Colors.white, size: 18),
                  onPressed: _sendCurrentMessage,
                ),
```
改为：
```dart
                child: IconButton(
                  icon: _sendArrowIcon(),
                  onPressed: _sendCurrentMessage,
                ),
```

- [ ] **Step 3: 验证**

Run: `flutter analyze lib/screens/group_chat/group_chat_detail_screen.dart`
Expected: 0 新增 error

- [ ] **Step 4: 提交**

```bash
git add lib/screens/group_chat/group_chat_detail_screen.dart
git commit -m "feat: 群聊发送按钮替换为横向+上折90°箭头图标"
```

---

### Task 5: 流式输出时序修复

**Files:**
- Modify: `lib/screens/group_chat/group_chat_detail_screen.dart`

**根因**: `getGroupChatMessages` DESC（最新 index 0）+ `reverse: true` → index 0 = 视觉底部；流式消息 `displayMessages.add` 追加尾部 → 渲染顶部。

- [ ] **Step 1: 流式消息 insert(0)**

`_buildMessageList`（L304-316）：
```dart
    if (streaming != null) {
      // 流式中的 AI 消息：临时追加为气泡
      displayMessages.add(GroupChatMessage(
        id: '_streaming_',
        groupId: _groupId,
        senderId: '_streaming_',
        senderName: streaming.characterName,
        content: streaming.streamingText,
        isUser: false,
        type: GroupChatMessageType.text,
        timestamp: DateTime.now(),
      ));
    }
```
改为：
```dart
    if (streaming != null) {
      // 流式中的 AI 消息：插入列表头部（DESC 序 index 0 = 视觉底部最新）
      displayMessages.insert(0, GroupChatMessage(
        id: '_streaming_',
        groupId: _groupId,
        senderId: '_streaming_',
        senderName: streaming.characterName,
        content: streaming.streamingText,
        isUser: false,
        type: GroupChatMessageType.text,
        timestamp: DateTime.now(),
      ));
    }
```

- [ ] **Step 2: `_TypingIndicator` 位置改 index 0**

`_buildMessageList` itemBuilder（L344-353）：
```dart
        if (typingCharacter != null &&
            index == displayMessages.length) {
          return _TypingIndicator(name: typingCharacter);
        }
        final msg = displayMessages[index];
        final showAvatar = index == 0 ||
            _messages.isEmpty ||
            (index < _messages.length &&
                _messages[index - 1].senderId != msg.senderId) ||
            index >= _messages.length;
```
改为：
```dart
        if (typingCharacter != null && index == 0) {
          return _TypingIndicator(name: typingCharacter);
        }
        final msg = displayMessages[index];
        final prev = index > 0 ? displayMessages[index - 1] : null;
        final showAvatar =
            prev == null || prev.senderId != msg.senderId;
```

- [ ] **Step 3: `GroupChatMessagesLoaded` 清流式残留**

`_buildMessageList` 所在 BlocBuilder 的 `GroupChatMessagesLoaded` 分支（L228-234）：
```dart
                    if (state is GroupChatMessagesLoaded &&
                        state.groupId == _groupId) {
                      _messages = state.messages;
                      _aiTyping = false;
                      _isLoading = false;
                      return _buildMessageList();
                    }
```
改为：
```dart
                    if (state is GroupChatMessagesLoaded &&
                        state.groupId == _groupId) {
                      _messages = state.messages;
                      _aiTyping = false;
                      _streamingText = '';
                      _streamingCharacter = '';
                      _isLoading = false;
                      return _buildMessageList();
                    }
```

- [ ] **Step 4: 验证**

Run: `flutter analyze lib/screens/group_chat/group_chat_detail_screen.dart`
Expected: 0 新增 error

Run: `flutter test test/group_chat_bloc_engine_test.dart test/group_chat_forced_speaker_test.dart test/group_chat_branch_model_test.dart`
Expected: 全 PASS（bloc 层未改，UI 层改动不影响）

- [ ] **Step 5: 提交**

```bash
git add lib/screens/group_chat/group_chat_detail_screen.dart
git commit -m "fix: 群聊流式消息插入列表底部（DESC index 0），打字指示同步 + 清残留"
```

---

### Task 6: 角色栏头像修复 + 溢出修复

**Files:**
- Modify: `lib/widgets/group_chat/member_activation_bar.dart`

- [ ] **Step 1: import AvatarResolver**

`member_activation_bar.dart` 顶部（现有 import 后）加：
```dart
import '../../utils/avatar_resolver.dart';
```

- [ ] **Step 2: `_avatar` 换 AvatarResolver**

`_avatar`（L161-174）替换为：
```dart
  Widget _avatar(AICharacter c, Color color) {
    final img = AvatarResolver.imageWidget(
      c.avatarUrl,
      width: 32,
      height: 32,
      fit: BoxFit.cover,
      onError: () => _avatarText(c, color),
    );
    if (img != null) return ClipOval(child: img);
    return _avatarText(c, color);
  }
```

- [ ] **Step 3: 高度 60 → 64 消除垂直溢出**

`SizedBox(height: 60,`（L69）改为：
```dart
          height: 64,
```

- [ ] **Step 4: 验证**

Run: `flutter analyze lib/widgets/group_chat/member_activation_bar.dart`
Expected: 0 新增 error

- [ ] **Step 5: 提交**

```bash
git add lib/widgets/group_chat/member_activation_bar.dart
git commit -m "fix: 角色栏头像走 AvatarResolver 兼容本地/asset，高度 64 消除溢出"
```

---

### Task 7: 设置弹窗高度溢出修复

**Files:**
- Modify: `lib/screens/group_chat/group_chat_detail_screen.dart`

- [ ] **Step 1: showModalBottomSheet 加 isScrollControlled + 内容滚动**

`_showGroupSettings`（L631）：
```dart
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
```
改为：
```dart
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
```

`SafeArea` 内 `Padding`（L641）的 `Column` 外套 `SingleChildScrollView`：
```dart
          child: SafeArea(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
```
并同步闭合括号（Column 结尾 L790-791 的 `),\n ),` 增加一层）。

- [ ] **Step 2: 验证**

Run: `flutter analyze lib/screens/group_chat/group_chat_detail_screen.dart`
Expected: 0 新增 error

- [ ] **Step 3: 提交**

```bash
git add lib/screens/group_chat/group_chat_detail_screen.dart
git commit -m "fix: 群聊设置弹窗 isScrollControlled + 可滚动，底部内容不再被裁"
```

---

### Task 8: 全量验证

**Files:** 无

- [ ] **Step 1: 全量测试**

Run: `flutter test`
Expected: 与基线一致（293 过 + 8 存量失败，无新增失败）

- [ ] **Step 2: 静态检查**

Run: `flutter analyze`
Expected: 0 新增 error（仅存量 Operit 2 error + 既有 withOpacity/unused info）

- [ ] **Step 3: 行为核对清单**

- [ ] 创建群可点头像上传（相册/拍照），创建后列表/详情显示圆形头像
- [ ] 无自定义头像的旧群聊显示毛毛虫兜底
- [ ] 顶部栏显示"自动回复"/"自动接话中"
- [ ] 发送按钮为横向+上折箭头
- [ ] 发消息后 AI 回复在底部逐字流式输出，无位置跳变
- [ ] 底部角色栏无 debug 黄黑条（溢出）
- [ ] 设置弹窗可滚动到"自动接话间隔/禁言成员/群信息"

- [ ] **Step 4: 提交（如有残留改动）**

```bash
git status
git commit -m "chore: 群聊 7 项修复最终验证"
```
