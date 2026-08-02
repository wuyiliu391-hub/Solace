# 群聊 UI 重写实现计划（对标 SillyTavern 交互）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 Solace 群聊三页（列表/详情/创建）UI 重写为 SillyTavern 级别交互（角色色消息流、成员激活条、侧滑成员面板、Auto-Reply+聊天记录悬浮条、头像拼接），严格沿用 Solace 主题（`colorScheme`，不用硬编码色）。

**Architecture:** 新开 `lib/widgets/group_chat/` 组件目录 + `lib/utils/character_color.dart` 纯函数角色色；引擎仅加内存态多角色锁定（`GroupChatSetSpeakers` 事件 + `_forcedSpeakers` map + speaker.dart 纯函数 `resolveForcedSpeakers`）；screen 重写 UI 层、保留全部现有逻辑。

**Tech Stack:** Flutter / flutter_bloc / equatable / Material 3 colorScheme

**设计文档:** `docs/superpowers/specs/2026-08-02-group-chat-ui-rebuild-design.md`

---

### Task 1: 角色色纯函数 `character_color.dart`

**Files:**
- Create: `lib/utils/character_color.dart`
- Test: `test/character_color_test.dart`

- [ ] **Step 1: 写失败测试**

`test/character_color_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/utils/character_color.dart';

void main() {
  const light = ColorScheme.light();
  const dark = ColorScheme.dark();

  test('同名同色：同一角色永远同一颜色', () {
    final a = characterColor(name: '小夜', cs: light);
    final b = characterColor(name: '小夜', cs: light);
    expect(a, b);
  });

  test('不同名大概率不同色', () {
    final colors = <Color>{
      for (final n in ['小夜', '阿夏', '露娜', '白夜', '千羽'])
        characterColor(name: n, cs: light),
    };
    expect(colors.length, greaterThanOrEqualTo(4));
  });

  test('colorHex 配置优先', () {
    final c = characterColor(colorHex: '#E53935', name: '小夜', cs: light);
    expect(c, const Color(0xFFE53935));
  });

  test('浅色/深色模式都返回可读色（与背景对比）', () {
    for (final cs in [light, dark]) {
      final c = characterColor(name: '小夜', cs: cs);
      // 亮度不在极端区间（不会和背景糊一起）
      final luminance = c.computeLuminance();
      expect(luminance, greaterThan(0.05));
      expect(luminance, lessThan(0.95));
    }
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/character_color_test.dart`
Expected: FAIL — `characterColor` 未定义

- [ ] **Step 3: 写实现**

`lib/utils/character_color.dart`:
```dart
import 'package:flutter/material.dart';

/// 解析角色主题色（对标 ST 角色卡 color 字段）：
/// 1. colorHex（#RRGGBB / RRGGBB）配置优先；
/// 2. 否则按名字哈希生成稳定色相（同一角色永远同色）；
/// 3. 深色模式提亮明度保证可读性。
Color characterColor({
  String? colorHex,
  required String name,
  required ColorScheme cs,
}) {
  if (colorHex != null) {
    final hex = colorHex.replaceAll('#', '').trim();
    if (hex.length == 6 || hex.length == 8) {
      final v = int.tryParse(hex.substring(0, 6), radix: 16);
      if (v != null) return Color(0xFF000000 | v);
    }
  }
  var hash = 0;
  for (final c in name.codeUnits) {
    hash = (hash * 31 + c) & 0x7fffffff;
  }
  final hue = (hash % 360).toDouble();
  final isDark = cs.brightness == Brightness.dark;
  return HSVColor.fromAHSV(1, hue, 0.62, isDark ? 0.85 : 0.62).toColor();
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/character_color_test.dart`
Expected: PASS 4/4

- [ ] **Step 5: Commit**

```bash
git add lib/utils/character_color.dart test/character_color_test.dart
git commit -m "feat: 角色色纯函数（colorHex 优先 + 哈希稳定色兜底）"
```

---

### Task 2: `AICharacter.colorHex` 字段

**Files:**
- Modify: `lib/models/ai_character.dart`（字段区 246-247 附近、构造 271-309、copyWith 311-356、toMap ~439、fromMap ~508、props 536-574）
- Test: `test/ai_character_colorhex_test.dart`

- [ ] **Step 1: 写失败测试**

`test/ai_character_colorhex_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/models/ai_character.dart';

void main() {
  AICharacter base() => AICharacter(
        id: 'c1',
        name: '小夜',
        personality: '冷静',
        coreDesire: '陪伴',
        moralBoundary: '',
        createdAt: DateTime(2026, 1, 1),
      );

  test('colorHex 默认 null', () {
    expect(base().colorHex, isNull);
  });

  test('colorHex 可构造与 copyWith', () {
    final c = base().copyWith(colorHex: '#E53935');
    expect(c.colorHex, '#E53935');
    expect(c.copyWith(colorHex: null).colorHex, isNull);
  });

  test('toMap/fromMap 往返保留 colorHex', () {
    final c = base().copyWith(colorHex: 'E53935');
    final round = AICharacter.fromMap(c.toMap());
    expect(round.colorHex, 'E53935');
    expect(AICharacter.fromMap(base().toMap()).colorHex, isNull);
  });

  test('fromMap 兼容无 colorHex 的旧数据', () {
    final map = base().toMap()..remove('colorHex');
    expect(AICharacter.fromMap(map).colorHex, isNull);
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/ai_character_colorhex_test.dart`
Expected: FAIL — `colorHex` 不存在

- [ ] **Step 3: 实现**

在 `lib/models/ai_character.dart`：
1. 字段（`talkativeness` 声明后）：
```dart
  /// 角色主题色（#RRGGBB，群聊角色色用；null 走哈希兜底）
  final String? colorHex;
```
2. 构造（`this.talkativeness = 0.5,` 后加 `this.colorHex,`）。
3. copyWith 签名加 `String? colorHex,`，返回处加 `colorHex: colorHex ?? this.colorHex,`。
4. toMap（`'talkativeness': talkativeness,` 附近）加 `'colorHex': colorHex,`。
5. fromMap（`talkativeness: ...` 行后）加 `colorHex: map['colorHex'] as String?,`。
6. props 列表加 `colorHex,`。

- [ ] **Step 4: 跑测试确认通过 + 存量模型测试不回归**

Run: `flutter test test/ai_character_colorhex_test.dart test/ai_character_talkativeness_test.dart test/models_test.dart`
Expected: 全 PASS

- [ ] **Step 5: Commit**

```bash
git add lib/models/ai_character.dart test/ai_character_colorhex_test.dart
git commit -m "feat: AICharacter 加 colorHex 角色主题色字段（群聊角色色用）"
```

---

### Task 3: 引擎多角色锁定（内存态）

**Files:**
- Modify: `lib/blocs/group_chat/group_chat_event.dart`（`GroupChatMarkRead` 后加）
- Modify: `lib/blocs/group_chat/group_chat_speaker.dart`（加纯函数）
- Modify: `lib/blocs/group_chat/group_chat_bloc.dart`（字段 41-43 附近、构造注册 55-60、`_onDelete` 103-110、`_generateAIReplies` SWAP 分支 ~260-300）
- Test: `test/group_chat_forced_speaker_test.dart`

- [ ] **Step 1: 写失败测试**

`test/group_chat_forced_speaker_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/blocs/group_chat/group_chat_speaker.dart';

void main() {
  test('锁定列表 = 强制 id 过滤禁言与不存在成员', () {
    final result = resolveForcedSpeakers(
      forcedIds: ['c1', 'c2', 'ghost'],
      memberIds: ['c1', 'c2', 'c3'],
      disabledMemberIds: ['c2'],
    );
    expect(result, ['c1']);
  });

  test('锁定空列表返回空', () {
    expect(
      resolveForcedSpeakers(
          forcedIds: [], memberIds: ['c1'], disabledMemberIds: []),
      isEmpty,
    );
  });

  test('全员禁言时锁定结果为空', () {
    expect(
      resolveForcedSpeakers(
          forcedIds: ['c1'], memberIds: ['c1'], disabledMemberIds: ['c1']),
      isEmpty,
    );
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/group_chat_forced_speaker_test.dart`
Expected: FAIL — `resolveForcedSpeakers` 未定义

- [ ] **Step 3: 实现**

a) `lib/blocs/group_chat/group_chat_speaker.dart` 末尾加：
```dart
/// 解析手动锁定发言人（对标 ST 手动激活）：过滤禁言与不在群的 id
List<String> resolveForcedSpeakers({
  required List<String> forcedIds,
  required List<String> memberIds,
  required List<String> disabledMemberIds,
}) {
  return forcedIds
      .where((id) => !disabledMemberIds.contains(id))
      .where((id) => memberIds.contains(id))
      .toList();
}
```

b) `lib/blocs/group_chat/group_chat_event.dart`（`GroupChatMarkRead` 类后）加：
```dart
/// 手动锁定发言人（内存态，对标 ST 手动激活；不落库）
class GroupChatSetSpeakers extends GroupChatEvent {
  final String groupId;
  final List<String> speakerIds;
  const GroupChatSetSpeakers({
    required this.groupId,
    required this.speakerIds,
  });
  @override
  List<Object?> get props => [groupId, speakerIds];
}
```

c) `lib/blocs/group_chat/group_chat_bloc.dart`：
1. 字段区（`_groupDelays` 后）加：
```dart
  /// 手动锁定发言人（内存态，群聊 UI 激活条写入）
  final Map<String, List<String>> _forcedSpeakers = {};
```
2. 构造注册（`on<GroupChatMarkRead>` 后）加：
```dart
    on<GroupChatSetSpeakers>(_onSetSpeakers);
```
3. 新 handler（`_onMarkRead` 后加）：
```dart
  Future<void> _onSetSpeakers(
    GroupChatSetSpeakers event,
    Emitter<GroupChatState> emit,
  ) async {
    _forcedSpeakers[event.groupId] = List<String>.from(event.speakerIds);
  }
```
4. `_onDelete` 里 `_replyingGroups.remove(event.groupId);` 后加：
```dart
      _forcedSpeakers.remove(event.groupId);
```
5. `_generateAIReplies` SWAP 分支——`var activated = selectSpeakers(...)` 前插入锁定判断：
```dart
    var activated;
    final forcedIds = _forcedSpeakers[groupId] ?? const <String>[];
    if (forcedIds.isNotEmpty) {
      activated = resolveForcedSpeakers(
        forcedIds: forcedIds,
        memberIds: session.aiCharacterIds,
        disabledMemberIds: session.disabledMemberIds,
      );
    } else {
      activated = selectSpeakers(
        strategy: session.activationStrategy,
        ctx: ctx,
      );
    }
```
（原 `var activated = selectSpeakers(...)` 语句整体替换为上面 8 行。）

- [ ] **Step 4: 跑测试确认通过 + analyze**

Run: `flutter test test/group_chat_forced_speaker_test.dart test/group_chat_speaker_test.dart`
Run: `flutter analyze lib/blocs/group_chat/`
Expected: 全 PASS，无 error

- [ ] **Step 5: Commit**

```bash
git add lib/blocs/group_chat/ test/group_chat_forced_speaker_test.dart
git commit -m "feat: 群聊手动锁定发言人（GroupChatSetSpeakers 内存态 + 强制过滤）"
```

---

### Task 4: 组件四件套

**Files:**
- Create: `lib/widgets/group_chat/group_top_bar.dart`
- Create: `lib/widgets/group_chat/member_activation_bar.dart`
- Create: `lib/widgets/group_chat/group_message_bubble.dart`
- Create: `lib/widgets/group_chat/group_member_drawer.dart`

本任务无新测试（纯 UI 组件，analyze 保障）。**注意：全部用 `withValues(alpha:)`，不要用 `withOpacity`（SDK 已 deprecated）。**

- [ ] **Step 1: `group_top_bar.dart`（消息区顶部悬浮条）**

```dart
import 'package:flutter/material.dart';

/// 消息区顶部悬浮条：左 = 聊天记录名（点击切换），右 = Auto-Reply 开关
class GroupTopBar extends StatelessWidget {
  final String chatName;
  final bool autoModeEnabled;
  final VoidCallback onChatTap;
  final ValueChanged<bool> onAutoModeChanged;

  const GroupTopBar({
    super.key,
    required this.chatName,
    required this.autoModeEnabled,
    required this.onChatTap,
    required this.onAutoModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      child: Material(
        color: cs.surface.withValues(alpha: 0.88),
        elevation: 1,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              InkWell(
                onTap: onChatTap,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: Row(
                    children: [
                      Icon(Icons.history, size: 16, color: cs.onSurfaceVariant),
                      const SizedBox(width: 6),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 140),
                        child: Text(
                          chatName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(Icons.arrow_drop_down,
                          size: 16, color: cs.onSurfaceVariant),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              Text(
                autoModeEnabled ? '自动接话中' : 'Auto-Reply',
                style: TextStyle(
                  fontSize: 11,
                  color:
                      autoModeEnabled ? cs.primary : cs.onSurfaceVariant,
                ),
              ),
              Switch(
                value: autoModeEnabled,
                onChanged: onAutoModeChanged,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: `member_activation_bar.dart`（输入框上方成员激活条）**

```dart
import 'package:flutter/material.dart';
import '../../models/ai_character.dart';
import '../../utils/character_color.dart';

/// 输入框上方成员激活条（对标 ST 手动激活）：
/// 单击 = 锁定该角色发言；再次点击 = 解锁；长按 = 多选模式
class MemberActivationBar extends StatefulWidget {
  final List<AICharacter> members;
  final Set<String> disabledIds;
  final List<String> forcedSpeakerIds;
  final ValueChanged<List<String>> onSpeakersChanged;

  const MemberActivationBar({
    super.key,
    required this.members,
    required this.disabledIds,
    required this.forcedSpeakerIds,
    required this.onSpeakersChanged,
  });

  @override
  State<MemberActivationBar> createState() => _MemberActivationBarState();
}

class _MemberActivationBarState extends State<MemberActivationBar> {
  bool _multiSelect = false;

  bool _isForced(String id) => widget.forcedSpeakerIds.contains(id);

  void _onTap(AICharacter c) {
    if (widget.disabledIds.contains(c.id)) return;
    if (_multiSelect) {
      final next = List<String>.from(widget.forcedSpeakerIds);
      next.contains(c.id) ? next.remove(c.id) : next.add(c.id);
      widget.onSpeakersChanged(next);
    } else {
      widget.onSpeakersChanged(_isForced(c.id) ? const [] : [c.id]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (widget.members.isEmpty) return const SizedBox.shrink();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_multiSelect)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
            child: Row(
              children: [
                Text(
                  '已锁定 ${widget.forcedSpeakerIds.length} 人',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(() => _multiSelect = false),
                  child:
                      const Text('完成', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
        SizedBox(
          height: 60,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            itemCount: widget.members.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final c = widget.members[index];
              final color = characterColor(
                  colorHex: c.colorHex, name: c.name, cs: cs);
              final forced = _isForced(c.id);
              final disabled = widget.disabledIds.contains(c.id);
              return GestureDetector(
                onTap: () => _onTap(c),
                onLongPress: widget.members.isEmpty
                    ? null
                    : () => setState(() => _multiSelect = true),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: disabled
                            ? cs.surfaceContainerHighest
                            : color.withValues(alpha: 0.16),
                        border: Border.all(
                          color: forced ? color : cs.outlineVariant,
                          width: forced ? 2.5 : 1,
                        ),
                      ),
                      child: Stack(
                        children: [
                          Center(child: _avatar(c, color)),
                          if (forced)
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: Container(
                                width: 14,
                                height: 14,
                                decoration: BoxDecoration(
                                  color: color,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                    Icons.record_voice_over,
                                    size: 9,
                                    color: Colors.white),
                              ),
                            ),
                          if (disabled)
                            Positioned.fill(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.black38,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.block,
                                    size: 14, color: Colors.white),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 2),
                    SizedBox(
                      width: 46,
                      child: Text(
                        c.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 9,
                          color: forced ? color : cs.onSurfaceVariant,
                          fontWeight: forced
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _avatar(AICharacter c, Color color) {
    if (c.avatarUrl != null && c.avatarUrl!.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          c.avatarUrl!,
          fit: BoxFit.cover,
          width: 32,
          height: 32,
          errorBuilder: (_, __, ___) => _avatarText(c, color),
        ),
      );
    }
    return _avatarText(c, color);
  }

  Widget _avatarText(AICharacter c, Color color) {
    return Text(
      c.name.isNotEmpty ? c.name.substring(0, 1) : '?',
      style: TextStyle(
        color: color,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
```

- [ ] **Step 3: `group_message_bubble.dart`（角色色消息气泡）**

```dart
import 'dart:io';
import 'package:flutter/material.dart';
import '../../models/group_chat_message.dart';

/// ST 风格群聊消息气泡：
/// AI = 左侧角色色（头像/名字/淡色气泡），用户 = 右对齐主色气泡（Solace 原样式）
class GroupMessageBubble extends StatelessWidget {
  final GroupChatMessage message;
  final bool showAvatar;
  final double screenWidth;
  final Color? speakerColor;

  const GroupMessageBubble({
    super.key,
    required this.message,
    required this.showAvatar,
    required this.screenWidth,
    this.speakerColor,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // 系统消息：居中灰条（沿用现有）
    if (message.isSystem) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              message.content,
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            ),
          ),
        ),
      );
    }

    // 用户消息：右对齐主色气泡（沿用现有）
    if (message.isUser) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _contentBubble(cs, isMe: true),
                  const SizedBox(height: 2),
                  Text(
                    _formatTime(message.timestamp),
                    style: TextStyle(
                      fontSize: 11,
                      color: cs.onSurface.withValues(alpha: 0.35),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _avatar('我', cs.primaryContainer, cs.primary),
          ],
        ),
      );
    }

    // AI 消息：角色色
    final color = speakerColor ?? cs.tertiary;
    final bubbleBg = color.withValues(
      alpha: Theme.of(context).brightness == Brightness.dark ? 0.18 : 0.10,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showAvatar)
            _avatar(message.senderName, color, Colors.white)
          else
            const SizedBox(width: 32),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message.senderName,
                  style: TextStyle(
                    fontSize: 12,
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                _contentBubble(cs, isMe: false, aiColor: color, bg: bubbleBg),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _contentBubble(
    ColorScheme cs, {
    required bool isMe,
    Color? aiColor,
    Color? bg,
  }) {
    // 图片消息
    if (message.type == GroupChatMessageType.image) {
      final paths =
          (message.metadata?['imagePaths'] as List?)?.cast<String>() ??
              (message.content.isNotEmpty ? [message.content] : <String>[]);
      final first = paths.isNotEmpty ? paths.first : null;
      return Container(
        constraints: BoxConstraints(maxWidth: screenWidth * 0.6),
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: isMe ? cs.primary : (bg ?? cs.surfaceContainerHighest),
          borderRadius: BorderRadius.circular(16).copyWith(
            bottomRight: isMe ? const Radius.circular(4) : null,
            bottomLeft: isMe ? null : const Radius.circular(4),
          ),
        ),
        child: first != null && File(first).existsSync()
            ? ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(
                  File(first),
                  width: 160,
                  height: 160,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox(
                    width: 160,
                    height: 160,
                    child: Icon(Icons.broken_image),
                  ),
                ),
              )
            : const Padding(
                padding: EdgeInsets.all(12),
                child: Icon(Icons.broken_image),
              ),
      );
    }

    return Container(
      constraints: BoxConstraints(maxWidth: screenWidth * 0.7),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isMe ? cs.primary : (bg ?? cs.surfaceContainerHighest),
        borderRadius: BorderRadius.circular(16).copyWith(
          bottomRight: isMe ? const Radius.circular(4) : null,
          bottomLeft: isMe ? null : const Radius.circular(4),
        ),
      ),
      child: Text(
        message.content,
        style: TextStyle(
          fontSize: 15,
          color: isMe ? cs.onPrimary : cs.onSurface,
        ),
      ),
    );
  }

  Widget _avatar(String name, Color bg, Color fg) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(shape: BoxShape.circle, color: bg),
      child: Center(
        child: Text(
          name.isNotEmpty ? name.substring(0, 1) : '?',
          style: TextStyle(
            color: fg,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(time.year, time.month, time.day);
    if (d == today) {
      return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    }
    return '${time.month}/${time.day} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}
```

- [ ] **Step 4: `group_member_drawer.dart`（侧滑成员面板）**

```dart
import 'package:flutter/material.dart';
import '../../models/ai_character.dart';
import '../../models/group_chat_session.dart';
import '../../utils/character_color.dart';

/// 侧滑成员面板（对标 ST 右侧成员栏）：
/// 点名字 = 手动激活切换；禁言开关；移出群聊
class GroupMemberDrawer extends StatelessWidget {
  final GroupChatSession session;
  final List<AICharacter> members;
  final List<String> forcedSpeakerIds;
  final ValueChanged<String> onToggleMute;
  final ValueChanged<String> onRemove;
  final ValueChanged<List<String>> onSpeakersChanged;

  const GroupMemberDrawer({
    super.key,
    required this.session,
    required this.members,
    required this.forcedSpeakerIds,
    required this.onToggleMute,
    required this.onRemove,
    required this.onSpeakersChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final disabled = session.disabledMemberIds.toSet();
    return Drawer(
      backgroundColor: cs.surface,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text(
                '群成员',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: cs.onSurface,
                ),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: CircleAvatar(
                backgroundColor: cs.primaryContainer,
                child: Icon(Icons.person, size: 18, color: cs.primary),
              ),
              title: Text('我', style: TextStyle(color: cs.onSurface)),
              subtitle: const Text('用户'),
            ),
            ...members.map((c) {
              final color = characterColor(
                  colorHex: c.colorHex, name: c.name, cs: cs);
              final muted = disabled.contains(c.id);
              final forced = forcedSpeakerIds.contains(c.id);
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: color.withValues(alpha: 0.15),
                  child: Text(
                    c.name.isNotEmpty ? c.name.substring(0, 1) : '?',
                    style: TextStyle(
                      color: color,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                title: Text(
                  c.name,
                  style: TextStyle(
                    color: forced ? color : cs.onSurface,
                    fontWeight:
                        forced ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                subtitle: (muted || forced)
                    ? Text(
                        muted ? '已禁言' : '锁定发言',
                        style: TextStyle(
                          fontSize: 11,
                          color: muted ? cs.error : color,
                        ),
                      )
                    : null,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(
                        muted ? Icons.volume_off : Icons.volume_up,
                        size: 18,
                        color:
                            muted ? cs.error : cs.onSurfaceVariant,
                      ),
                      tooltip: muted ? '取消禁言' : '禁言',
                      onPressed: () => onToggleMute(c.id),
                    ),
                    IconButton(
                      icon: const Icon(Icons.exit_to_app,
                          size: 18, color: Color(0xFFE53935)),
                      tooltip: '移出群聊',
                      onPressed: () => onRemove(c.id),
                    ),
                  ],
                ),
                onTap: () {
                  final next = List<String>.from(forcedSpeakerIds);
                  next.contains(c.id) ? next.remove(c.id) : next.add(c.id);
                  onSpeakersChanged(next);
                },
              );
            }),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: analyze**

Run: `flutter analyze lib/widgets/group_chat/`
Expected: 无 error、无 deprecated 警告

- [ ] **Step 6: Commit**

```bash
git add lib/widgets/group_chat/
git commit -m "feat: 群聊组件四件套 — 顶部悬浮条/成员激活条/角色色气泡/侧滑成员面板"
```

---

### Task 5: 详情页重写（核心）

**Files:**
- Modify: `lib/screens/group_chat/group_chat_detail_screen.dart`（现状 1337 行，UI 层替换 + 组件接入）

步骤较多，每一步编辑完跑 analyze。**目标结构：**

```
build:
  Scaffold(
    appBar: AppBar(
      title: Row[ 成员头像堆叠InkWell(开endDrawer), 群名 ],
      actions: [通知, 菜单(不变)],
    ),
    endDrawer: GroupMemberDrawer(...),
    body: Column[
      公告条(不变),
      Expanded(
        Stack[
          BlocBuilder(...消息列表..., GroupMessageBubble 接入),
          Positioned(top:0,left:0,right:0, GroupTopBar(...)),
        ],
      ),
      MemberActivationBar(...),
      _buildInputBar()(不变),
    ],
  )
```

- [ ] **Step 1: 状态与加载**

`initState` 里 `_loadMessages();` 后加：
```dart
    _loadMembers();
```
State 字段区（`_aiTyping` 后）加：
```dart
  /// 群内 AI 成员（激活条/侧滑面板/角色色）
  List<AICharacter> _members = [];
  /// 角色 id → 角色色缓存
  final Map<String, Color> _memberColors = {};
  /// 手动锁定发言人（内存态）
  List<String> _forcedSpeakerIds = [];
  /// 当前聊天记录名（顶部悬浮条显示）
  String _chatName = '默认聊天';
```
State 里加方法（`_loadMessages` 旁）：
```dart
  Future<void> _loadMembers() async {
    final repo = RepositoryProvider.of<LocalStorageRepository>(context);
    final all = await repo.getAllAICharacters();
    final byId = {for (final c in all) c.id: c};
    if (!mounted) return;
    setState(() {
      _members = _session.aiCharacterIds
          .map((id) => byId[id])
          .whereType<AICharacter>()
          .toList();
      _memberColors
        ..clear()
        ..addEntries(_members.map((c) => MapEntry(
              c.id,
              characterColor(
                colorHex: c.colorHex,
                name: c.name,
                cs: Theme.of(context).colorScheme,
              ),
            )));
    });
  }
```
import 加 `../../utils/character_color.dart`、`../../widgets/group_chat/group_top_bar.dart`、`member_activation_bar.dart`、`group_message_bubble.dart`、`group_member_drawer.dart`、`../../blocs/group_chat/group_chat_event.dart`（若 detail 未 import）。

`_refreshSession` 加分支（`GroupChatBranchesLoaded` 时更新 `_chatName`）：
```dart
    if (state is GroupChatBranchesLoaded && state.groupId == _groupId) {
      _chatName = state.branches
              .where((b) => b.branchId == state.currentChatId)
              .firstOrNull
              ?.name ??
          _chatName;
    }
```

- [ ] **Step 2: build 结构替换**

将 `build` 中 `Scaffold(...)` 的 appBar title 与 body 按目标结构替换（body Column 里插入 Stack + 悬浮条 + 激活条）。具体：
1. appBar title 改为：
```dart
        title: InkWell(
          onTap: () => _scaffoldKey.currentState?.openEndDrawer(),
          borderRadius: BorderRadius.circular(8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _memberStackAvatar(),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  _session.name,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
```
（需要 `final _scaffoldKey = GlobalKey<ScaffoldState>();` 字段 + `scaffoldKey: _scaffoldKey,`）
`_memberStackAvatar`（AI 成员头像堆叠，最多 3 个）：
```dart
  Widget _memberStackAvatar() {
    final cs = Theme.of(context).colorScheme;
    final shown = _members.take(3).toList();
    if (shown.isEmpty) {
      return CircleAvatar(
        radius: 12,
        backgroundColor: cs.tertiaryContainer,
        child: Icon(Icons.group, size: 14, color: cs.tertiary),
      );
    }
    return SizedBox(
      width: 40,
      height: 30,
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              left: i * 12,
              top: i * 3,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _memberColors[shown[i].id] ??
                      cs.tertiaryContainer,
                  border: Border.all(color: cs.surface, width: 1.5),
                ),
                child: Center(
                  child: Text(
                    shown[i].name.isNotEmpty
                        ? shown[i].name.substring(0, 1)
                        : '?',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
```
2. `Scaffold` 加 `scaffoldKey: _scaffoldKey,` 与 `endDrawer:`：
```dart
      endDrawer: GroupMemberDrawer(
        session: _session,
        members: _members,
        forcedSpeakerIds: _forcedSpeakerIds,
        onToggleMute: (id) {
          final next = List<String>.from(_session.disabledMemberIds);
          next.contains(id) ? next.remove(id) : next.add(id);
          _dispatchConfig(disabledMemberIds: next);
        },
        onRemove: (id) {
          context
              .read<GroupChatBloc>()
              .add(GroupChatRemoveMember(_groupId, id));
          Navigator.pop(context);
        },
        onSpeakersChanged: _setForcedSpeakers,
      ),
```
3. body 的 `Column` 中 `Expanded(BlocBuilder...)` 替换为：
```dart
          Expanded(
            child: Stack(
              children: [
                BlocBuilder<GroupChatBloc, GroupChatState>(
                  builder: (context, state) {
                    ...原逻辑不变，仅 _MessageBubble 调用改为 GroupMessageBubble...
                  },
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: GroupTopBar(
                    chatName: _chatName,
                    autoModeEnabled: _session.autoModeEnabled,
                    onChatTap: _showBranchManager,
                    onAutoModeChanged: (v) {
                      _dispatchConfig(autoModeEnabled: v);
                    },
                  ),
                ),
              ],
            ),
          ),
          MemberActivationBar(
            members: _members,
            disabledIds: _session.disabledMemberIds.toSet(),
            forcedSpeakerIds: _forcedSpeakerIds,
            onSpeakersChanged: _setForcedSpeakers,
          ),
```
4. 原 `_MessageBubble(message:..., isUser:..., showAvatar:..., screenWidth:...)` 调用替换为：
```dart
        return GroupMessageBubble(
          message: msg,
          showAvatar: showAvatar,
          screenWidth: MediaQuery.of(context).size.width,
          speakerColor: msg.senderId.startsWith('ai_')
              ? _memberColors[msg.senderId.substring(3)]
              : null,
        );
```
5. 新增 `_setForcedSpeakers`：
```dart
  void _setForcedSpeakers(List<String> ids) {
    setState(() => _forcedSpeakerIds = List<String>.from(ids));
    context
        .read<GroupChatBloc>()
        .add(GroupChatSetSpeakers(groupId: _groupId, speakerIds: ids));
  }
```
6. 删除文件尾部旧 `_MessageBubble` 与 `_TypingIndicator` 中重复头像逻辑（`_TypingIndicator` 保留；`_MessageBubble` 整个类删除，图片/时间逻辑已搬入 GroupMessageBubble）。

- [ ] **Step 3: analyze 修复**

Run: `flutter analyze lib/screens/group_chat/`
Expected: 无 error（可能剩 withOpacity info，不动存量）

- [ ] **Step 4: 全量群聊测试不回归**

Run: `flutter test test/group_chat_speaker_test.dart test/group_chat_prompts_test.dart test/group_chat_bloc_engine_test.dart test/group_chat_forced_speaker_test.dart`
Expected: 全 PASS

- [ ] **Step 5: Commit**

```bash
git add lib/screens/group_chat/group_chat_detail_screen.dart
git commit -m "feat: 群聊详情页重写 — 角色色消息流 + 顶部悬浮条 + 成员激活条 + 侧滑面板"
```

---

### Task 6: 列表页重写

**Files:**
- Modify: `lib/screens/group_chat/group_chat_list_screen.dart`

- [ ] **Step 1: 成员加载 + 头像拼接 + 发言人摘要**

1. `_GroupChatListScreenState` 加：
```dart
  final Map<String, List<AICharacter>> _membersByGroup = {};
  final Map<String, String> _lastSpeakerNames = {};
```
2. `initState` 后 `_loadMemberData()`：
```dart
  Future<void> _loadMemberData() async {
    final repo = RepositoryProvider.of<LocalStorageRepository>(context);
    final all = await repo.getAllAICharacters();
    if (!mounted) return;
    final byId = {for (final c in all) c.id: c};
    final bloc = context.read<GroupChatBloc>();
    final sessions = bloc.state is GroupChatSessionsLoaded
        ? (bloc.state as GroupChatSessionsLoaded).sessions
        : <GroupChatSession>[];
    final membersByGroup = <String, List<AICharacter>>{};
    final lastSpeakerNames = <String, String>{};
    for (final s in sessions) {
      membersByGroup[s.id] = s.aiCharacterIds
          .map((id) => byId[id])
          .whereType<AICharacter>()
          .toList();
      final latest =
          await repo.getGroupChatMessages(s.id, limit: 1, chatId: s.chatId);
      if (latest.isNotEmpty) {
        final m = latest.first;
        lastSpeakerNames[s.id] =
            m.isUser ? '我' : m.senderName;
      }
    }
    if (!mounted) return;
    setState(() {
      _membersByGroup.clear();
      _membersByGroup.addAll(membersByGroup);
      _lastSpeakerNames.clear();
      _lastSpeakerNames.addAll(lastSpeakerNames);
    });
  }
```
（`_loadMessages` 的 BlocBuilder 中 sessions 变化时调用：在 `_buildGroupChatList` 返回前 `if (_membersByGroup.length != sessions.length) _loadMemberData();` 简单去抖。）
3. `_GroupChatTile` 构造加 `members` 与 `lastSpeakerName` 参数。
4. 头像替换为拼接（`_memberStack` 如上 AppBar 版，尺寸 48）：
```dart
  Widget _memberStack(List<AICharacter> members, ColorScheme cs) {
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

  Widget _miniAvatar(AICharacter c, ColorScheme cs) {
    final color = characterColor(colorHex: c.colorHex, name: c.name, cs: cs);
    if (c.avatarUrl != null && c.avatarUrl!.isNotEmpty) {
      return Image.network(
        c.avatarUrl!,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _miniAvatarText(c, color),
      );
    }
    return _miniAvatarText(c, color);
  }

  Widget _miniAvatarText(AICharacter c, Color color) {
    return Center(
      child: Text(
        c.name.isNotEmpty ? c.name.substring(0, 1) : '?',
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
```
5. 摘要行改为发言人格式（`session.lastMessage` 逻辑替换）：
```dart
  Text(
    session.lastMessage == null || session.lastMessage!.isEmpty
        ? (session.notice?.isNotEmpty == true ? '公告：${session.notice}' : '暂无消息')
        : '${lastSpeakerName ?? ''}: ${session.lastMessage}',
    ...
  )
```
（空 lastSpeakerName 时只显示内容。）

- [ ] **Step 2: analyze**

Run: `flutter analyze lib/screens/group_chat/group_chat_list_screen.dart`
Expected: 无 error

- [ ] **Step 3: Commit**

```bash
git add lib/screens/group_chat/group_chat_list_screen.dart
git commit -m "feat: 群聊列表页重写 — 成员头像拼接 + 发言人摘要"
```

---

### Task 7: 创建页重写

**Files:**
- Modify: `lib/screens/group_chat/group_chat_create_screen.dart`

- [ ] **Step 1: 拖拽排序 + 已选成员条**

1. `_selectedAiCharacterIds` 语义改为"有序"（发言顺序，创建时传给 bloc）。
2. body Column 结构改为：
```dart
          Column(
            children: [
              Padding(...群名称输入不变...),
              _buildSelectedBar(colorScheme),   // 已选成员横向条
              Expanded(child: _buildCharacterSelection(colorScheme)),
            ],
          ),
```
3. `_buildSelectedBar`（底部预览用顶部条，放在名称下、列表上；无选中时隐藏）：
```dart
  Widget _buildSelectedBar(ColorScheme colorScheme) {
    if (_selectedAiCharacterIds.isEmpty) return const SizedBox.shrink();
    final byId = {for (final c in _allCharacters) c.id: c};
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _selectedAiCharacterIds.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final c = byId[_selectedAiCharacterIds[index]];
          if (c == null) return const SizedBox.shrink();
          final color = characterColor(colorHex: c.colorHex, name: c.name, cs: colorScheme);
          return Chip(
            avatar: CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.15),
              child: Text(
                c.name.isNotEmpty ? c.name.substring(0, 1) : '?',
                style: TextStyle(color: color, fontSize: 11),
              ),
            ),
            label: Text(c.name, style: const TextStyle(fontSize: 12)),
            onDeleted: () => setState(() => _selectedAiCharacterIds.remove(c.id)),
            deleteIconColor: colorScheme.onSurfaceVariant,
          );
        },
      ),
    );
  }
```
4. 列表区改为 `ReorderableListView.builder`（选中的排前面可拖拽，未选中的排后面；拖拽仅对已选有效）：
```dart
    final selected = _selectedAiCharacterIds.toSet();
    final ordered = [
      ..._selectedAiCharacterIds.map((id) => byId[id]).whereType<AICharacter>(),
      ..._allCharacters.where((c) => !selected.contains(c.id)),
    ];
    return ReorderableListView.builder(
      itemCount: ordered.length,
      onReorder: (oldIndex, newIndex) {
        setState(() {
          if (newIndex > oldIndex) newIndex -= 1;
          final moved = ordered.removeAt(oldIndex);
          ordered.insert(newIndex, moved);
          _selectedAiCharacterIds
            ..clear()
            ..addAll(ordered.where((c) => selected.contains(c.id)).map((c) => c.id));
        });
      },
      itemBuilder: (context, index) {
        final character = ordered[index];
        final isSelected = selected.contains(character.id);
        return ListTile(
          key: ValueKey(character.id),
          ...原有 UI（头像/名字/对勾）不变,
          onTap: () {
            setState(() {
              if (isSelected) {
                _selectedAiCharacterIds.remove(character.id);
              } else {
                _selectedAiCharacterIds.add(character.id);
              }
            });
          },
        );
      },
    );
```
（`ListTile` 必须有 `key: ValueKey(character.id)`，否则 Reorderable 报错。）

- [ ] **Step 2: analyze**

Run: `flutter analyze lib/screens/group_chat/group_chat_create_screen.dart`
Expected: 无 error

- [ ] **Step 3: Commit**

```bash
git add lib/screens/group_chat/group_chat_create_screen.dart
git commit -m "feat: 群聊创建页重写 — 角色拖拽排序（发言顺序）+ 已选成员条"
```

---

### Task 8: 全量验证 + 收尾

**Files:** 无新增（验证用）

- [ ] **Step 1: 全量 analyze**

Run: `flutter analyze`
Expected: 无新增 error（存量 Operit 模板 2 error 与本计划无关；存量 withOpacity info 不修）

- [ ] **Step 2: 全部相关测试**

Run: `flutter test test/character_color_test.dart test/ai_character_colorhex_test.dart test/group_chat_forced_speaker_test.dart test/group_chat_speaker_test.dart test/group_chat_prompts_test.dart test/group_chat_bloc_engine_test.dart test/group_chat_session_config_test.dart test/group_chat_branch_model_test.dart test/ai_character_talkativeness_test.dart`
Expected: 全 PASS

- [ ] **Step 3: 自检清单**

- [ ] 组件目录 4 文件存在、detail/list/create 已接入
- [ ] 无 `withOpacity` 新增（新代码全用 `withValues`）
- [ ] `GroupChatSetSpeakers` 事件被 detail screen 发送、bloc 处理、`_generateAIReplies` 消费
- [ ] 无硬编码色新增（除存量 `Color(0xFFE53935)`）
- [ ] 设计文档 8 节全部落实（组件/三页/引擎/测试）

- [ ] **Step 4: 最终 commit（如还有未提交改动）**

```bash
git add -A
git commit -m "chore: 群聊 UI 重写收尾"
```

---

## 自检对照（spec → 任务）

| Spec 节 | 任务 |
|---|---|
| character_color 纯函数 | Task 1 |
| AICharacter.colorHex | Task 2 |
| GroupChatSetSpeakers + _forcedSpeakers + 强制过滤 | Task 3 |
| group_top_bar | Task 4 Step 1 |
| member_activation_bar | Task 4 Step 2 |
| group_message_bubble | Task 4 Step 3 |
| group_member_drawer | Task 4 Step 4 |
| 详情页重写 | Task 5 |
| 列表页重写 | Task 6 |
| 创建页重写 | Task 7 |
| 测试 + analyze + 不打包 | Task 8 |

**类型一致性：** `characterColor({colorHex, name, cs})` 全项目统一；`resolveForcedSpeakers({forcedIds, memberIds, disabledMemberIds})` 与 speaker.dart 命名风格一致；组件构造参数名与 Task 5 调用一一对应（`onSpeakersChanged`/`onChatTap`/`onAutoModeChanged`/`onToggleMute`/`onRemove`）。

**已知注意：**
1. `GroupChatMessage.isSystem` 字段存在（气泡已用）。
2. `getGroupChatMessages` 返回 DESC（最新在前），`limit: 1` 取 `.first` 即最新（Task 6 发言人摘要）。
3. `firstOrNull` 需 `package:collection` 或 Dart 3 内置（`Iterable.firstOrNull` 需 import 'package:collection/collection.dart'；如项目未引，改用 `branches.where(...).isEmpty ? _chatName : branches.where(...).first.name`）。
4. detail screen 现有 `_MessageBubble` 删除后，`_buildMessageList` 内引用必须同步替换，否则编译失败。
5. 存量 8 个失败测试（intimacy/config/refusal）与本次无关，不修。
