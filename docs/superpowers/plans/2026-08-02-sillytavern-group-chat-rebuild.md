# SillyTavern 群聊引擎 100% 还原计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 SillyTavern-1.18.0 群聊引擎（4 种激活策略、3 种生成模式、禁言、允自答、话痨属性、自动接话、多聊天记录、nudge prompt 体系）100% 还原到 Solace Flutter 项目。

**Architecture:** 数据层给 `GroupChatSession`/`GroupChatMessage`/`AICharacter` 加字段并建 `group_chat_branches` 多聊天记录表（DB v65 迁移）；引擎层把 ST 的 `generateGroupWrapper` + 5 个 activate 算法转译为 Dart 纯函数（`group_chat_speaker.dart`）与 prompt 构建（`group_chat_prompts.dart`），重写 `group_chat_bloc.dart` 的 `_generateAIReplies`；UI 层扩展群设置面板与聊天记录切换。

**Tech Stack:** Flutter/Dart, sqflite (DB v64→v65), bloc, 现有 `AIService.sendMessageStream(internalSystemContext:)`。

**对标源码（本地已具备）：**
- `C:\Users\Administrator\Desktop\SillyTavern-1.18.0\public\scripts\group-chats.js`（2490 行，激活/生成核心）
- `C:\Users\Administrator\Desktop\SillyTavern-1.18.0\src\endpoints\groups.js`（群 CRUD 后端）
- `C:\Users\Administrator\Desktop\SillyTavern-1.18.0\public\scripts\openai.js`（群聊 prompt：main_prompt/new_group_chat_prompt/group_nudge_prompt）

**ST 机制备忘（转译依据）：**
- `group_activation_strategy = { NATURAL:0, LIST:1, MANUAL:2, POOLED:3 }`
- `group_generation_mode = { SWAP:0, APPEND:1, APPEND_DISABLED:2 }`
- `talkativeness_default = 0.5`（script.js:548）
- NATURAL：提及检测（角色名出现在输入中）+ 话痨概率 roll（排除上一条发言者，除非 allow_self_responses）+ 无激活者时随机兜底（优先 talkativeness>0 池）
- LIST：按成员列表顺序全员激活
- POOLED：用户最后消息之后已发言者优先排除，选未发言者随机；全部说过则排除最后发言者
- MANUAL：手动指定（impersonate）
- SWAP：逐角色用各自角色卡生成
- APPEND/APPEND_DISABLED：全员角色卡合并成组合卡一次生成（disabled 成员排除）
- prompt 三件套：main_prompt `Write {{char}}'s next reply in a fictional chat between {{charIfNotGroup}} and {{user}}.`；new_group_chat_prompt `[Start a new group chat. Group members: {{group}}]`；group_nudge_prompt `[Write the next reply only as {{char}}.]`（生成末尾注入，impersonate 除外）
- 消息历史格式：群聊时角色消息加 `角色名: 内容` 前缀（openai.js:585-590）
- auto mode：setInterval 每 `auto_mode_delay` 秒检查，最后一条非系统且非生成中则触发
- 新群聊：每个成员插入自己的 first_mes（ST `getFirstCharacterMessage`，含 alternate_greetings 随机）
- 多聊天记录：`group.chats = [chatId...]`、`group.chat_id` 当前、每条消息属于一个 chatId（JSONL 文件）

---

### Task 1: DB v65 迁移 — 群聊引擎字段与分支表

**Files:**
- Modify: `lib/config/constants.dart:319`
- Modify: `lib/repositories/local_storage_repository.dart`（`_onUpgrade` v64 段后加 v65 段；`createMissingTable` case；`_onCreate` 末尾补建）

- [ ] **Step 1: 版本号 64 → 65**

`lib/config/constants.dart:319`：
```dart
  static const int dbVersion = 65;
```

- [ ] **Step 2: _onUpgrade 追加 v65 迁移段**

在 `local_storage_repository.dart` 的 v64 段（约 1886-1890 行，`debugPrint('? v64 迁移: shop_items 强制 schema 校验');` 的 `}` 之后、`}` 之前）插入：

```dart
    if (oldVersion < 65) {
      // v65: SillyTavern 群聊引擎还原 — 配置字段 + 多聊天记录 + 话痨属性
      await _addColumnIfNotExists(
          db, 'ai_characters', 'talkativeness', 'REAL NOT NULL DEFAULT 0.5');
      await _addColumnIfNotExists(
          db, 'group_chat_sessions', 'chatId', 'TEXT NOT NULL DEFAULT ""');
      await _addColumnIfNotExists(db, 'group_chat_sessions',
          'activationStrategy', 'INTEGER NOT NULL DEFAULT 0');
      await _addColumnIfNotExists(
          db, 'group_chat_sessions', 'generationMode', 'INTEGER NOT NULL DEFAULT 0');
      await _addColumnIfNotExists(db, 'group_chat_sessions',
          'allowSelfResponses', 'INTEGER NOT NULL DEFAULT 0');
      await _addColumnIfNotExists(db, 'group_chat_sessions',
          'disabledMemberIds', 'TEXT NOT NULL DEFAULT "[]"');
      await _addColumnIfNotExists(
          db, 'group_chat_sessions', 'autoModeDelay', 'INTEGER NOT NULL DEFAULT 5');
      await _addColumnIfNotExists(
          db, 'group_chat_sessions', 'autoModeEnabled', 'INTEGER NOT NULL DEFAULT 0');
      await _addColumnIfNotExists(
          db, 'group_chat_sessions', 'joinPrefix', 'TEXT NOT NULL DEFAULT ""');
      await _addColumnIfNotExists(
          db, 'group_chat_sessions', 'joinSuffix', 'TEXT NOT NULL DEFAULT ""');
      await _addColumnIfNotExists(
          db, 'group_chat_messages', 'chatId', 'TEXT NOT NULL DEFAULT ""');
      // 老消息归入默认分支（chatId=groupId）
      await db.execute(
          'UPDATE group_chat_messages SET chatId = groupId WHERE chatId = ""');
      await db.execute('''CREATE TABLE IF NOT EXISTS group_chat_branches (
        branchId TEXT PRIMARY KEY,
        groupId TEXT NOT NULL DEFAULT '',
        name TEXT NOT NULL DEFAULT '',
        createdAt TEXT NOT NULL DEFAULT '',
        updatedAt TEXT
      )''');
      // 每个群补默认分支 + 当前 chatId 指向群 id
      final sessions = await db.query('group_chat_sessions');
      for (final row in sessions) {
        final gid = row['id'] as String;
        await db.insert('group_chat_branches', {
          'branchId': gid,
          'groupId': gid,
          'name': '默认聊天',
          'createdAt': DateTime.now().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
        await db.rawUpdate(
            'UPDATE group_chat_sessions SET chatId = ? WHERE id = ? AND chatId = ""',
            [gid, gid]);
      }
      debugPrint(' v65 迁移: 群聊引擎字段 + 分支表已就绪');
    }
```

- [ ] **Step 3: createMissingTable case 补 group_chat_branches**

`createMissingTable` 的 switch（约 906-925 行附近）加：

```dart
      case 'group_chat_branches':
        await db.execute('''CREATE TABLE IF NOT EXISTS group_chat_branches (
          branchId TEXT PRIMARY KEY,
          groupId TEXT NOT NULL DEFAULT '',
          name TEXT NOT NULL DEFAULT '',
          createdAt TEXT NOT NULL DEFAULT '',
          updatedAt TEXT
        )''');
        await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_gc_branches_group ON group_chat_branches(groupId)');
        break;
```

- [ ] **Step 4: _onCreate 末尾补建分支表**

`_onCreate` 的"AI 群聊模块（v56 新增）"段（约 2109-2146 行）后追加：

```dart
    // v65: 群聊分支表（多聊天记录）
    await createMissingTable(db, 'group_chat_branches');
    await _addColumnIfNotExists(
        db, 'ai_characters', 'talkativeness', 'REAL NOT NULL DEFAULT 0.5');
    await _addColumnIfNotExists(
        db, 'group_chat_sessions', 'chatId', 'TEXT NOT NULL DEFAULT ""');
    await _addColumnIfNotExists(
        db, 'group_chat_sessions', 'activationStrategy', 'INTEGER NOT NULL DEFAULT 0');
    await _addColumnIfNotExists(
        db, 'group_chat_sessions', 'generationMode', 'INTEGER NOT NULL DEFAULT 0');
    await _addColumnIfNotExists(
        db, 'group_chat_sessions', 'allowSelfResponses', 'INTEGER NOT NULL DEFAULT 0');
    await _addColumnIfNotExists(
        db, 'group_chat_sessions', 'disabledMemberIds', 'TEXT NOT NULL DEFAULT "[]"');
    await _addColumnIfNotExists(
        db, 'group_chat_sessions', 'autoModeDelay', 'INTEGER NOT NULL DEFAULT 5');
    await _addColumnIfNotExists(
        db, 'group_chat_sessions', 'autoModeEnabled', 'INTEGER NOT NULL DEFAULT 0');
    await _addColumnIfNotExists(
        db, 'group_chat_sessions', 'joinPrefix', 'TEXT NOT NULL DEFAULT ""');
    await _addColumnIfNotExists(
        db, 'group_chat_sessions', 'joinSuffix', 'TEXT NOT NULL DEFAULT ""');
    await _addColumnIfNotExists(
        db, 'group_chat_messages', 'chatId', 'TEXT NOT NULL DEFAULT ""');
```

- [ ] **Step 5: 运行 analyze 确认无语法错误**

Run: `flutter analyze lib/config/constants.dart lib/repositories/local_storage_repository.dart`
Expected: 无新增 error（存量 2 个 error 在 Operit 目录，与本任务无关）

- [ ] **Step 6: Commit**

```bash
git add lib/config/constants.dart lib/repositories/local_storage_repository.dart
git commit -m "feat: db v65 群聊引擎字段迁移（策略/模式/禁言/话痨/分支表）"
```

---

### Task 2: AICharacter 加 talkativeness 字段

**Files:**
- Modify: `lib/models/ai_character.dart`（字段/构造/copyWith/toMap/fromMap/props）
- Test: `test/ai_character_talkativeness_test.dart`（新建）

- [ ] **Step 1: 写失败测试**

`test/ai_character_talkativeness_test.dart`：
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/models/ai_character.dart';

void main() {
  test('talkativeness 默认 0.5', () {
    final c = AICharacter(
      id: '1', name: 'A', personality: 'p', coreDesire: 'd', moralBoundary: 'm',
      createdAt: DateTime.now(),
    );
    expect(c.talkativeness, 0.5);
  });

  test('toMap/fromMap 往返保留 talkativeness', () {
    final c = AICharacter(
      id: '1', name: 'A', personality: 'p', coreDesire: 'd', moralBoundary: 'm',
      createdAt: DateTime.now(), talkativeness: 0.8,
    );
    final restored = AICharacter.fromMap(c.toMap());
    expect(restored.talkativeness, 0.8);
  });

  test('copyWith 可修改 talkativeness', () {
    final c = AICharacter(
      id: '1', name: 'A', personality: 'p', coreDesire: 'd', moralBoundary: 'm',
      createdAt: DateTime.now(), talkativeness: 0.3,
    );
    expect(c.copyWith(talkativeness: 1.0).talkativeness, 1.0);
  });
}
```

Run: `flutter test test/ai_character_talkativeness_test.dart`
Expected: FAIL（talkativeness 未定义）

- [ ] **Step 2: 模型加字段**

`lib/models/ai_character.dart`：
- 字段（`deviationRadius` 附近，约 246 行）：
```dart
  /// 健谈度 0~1（群聊 NATURAL 激活策略用，默认 0.5，对标 SillyTavern talkativeness）
  final double talkativeness;
```
- 构造（约 296 行，`this.deviationRadius = 0.4,` 后）：
```dart
    this.talkativeness = 0.5,
```
- copyWith（约 343 行）：
```dart
    double? talkativeness,
```
（body 中 `deviationRadius: deviationRadius ?? this.deviationRadius,` 后）：
```dart
      talkativeness: talkativeness ?? this.talkativeness,
```
- toMap（约 433 行，`'deviationRadius': deviationRadius,` 后）：
```dart
      'talkativeness': talkativeness,
```
- fromMap（约 501 行，`deviationRadius` 行后）：
```dart
      talkativeness: (map['talkativeness'] as num?)?.toDouble() ?? 0.5,
```
- props（约 556 行，`deviationRadius,` 后）：
```dart
        talkativeness,
```

- [ ] **Step 3: 跑测试确认通过**

Run: `flutter test test/ai_character_talkativeness_test.dart`
Expected: PASS 3/3

- [ ] **Step 4: Commit**

```bash
git add lib/models/ai_character.dart test/ai_character_talkativeness_test.dart
git commit -m "feat: AICharacter 加 talkativeness 健谈度字段（对标 SillyTavern）"
```

---

### Task 3: GroupChatSession 扩展引擎配置字段

**Files:**
- Modify: `lib/models/group_chat_session.dart`
- Test: `test/group_chat_session_config_test.dart`（新建）

- [ ] **Step 1: 写失败测试**

`test/group_chat_session_config_test.dart`：
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/models/group_chat_session.dart';

void main() {
  final base = GroupChatSession(
    id: 'g1', name: '测试群', memberIds: ['local_user'],
    aiCharacterIds: ['c1', 'c2'], creatorId: 'local_user',
    createdAt: DateTime.now(),
  );

  test('引擎配置字段默认值对标 ST', () {
    expect(base.chatId, 'g1');
    expect(base.activationStrategy, GroupActivationStrategy.natural);
    expect(base.generationMode, GroupGenerationMode.swap);
    expect(base.allowSelfResponses, false);
    expect(base.disabledMemberIds, isEmpty);
    expect(base.autoModeDelay, 5);
    expect(base.autoModeEnabled, false);
    expect(base.joinPrefix, '');
    expect(base.joinSuffix, '');
  });

  test('toMap/fromMap 往返保留配置', () {
    final s = base.copyWith(
      chatId: 'b2',
      activationStrategy: GroupActivationStrategy.pooled,
      generationMode: GroupGenerationMode.append,
      allowSelfResponses: true,
      disabledMemberIds: ['c2'],
      autoModeDelay: 8,
      autoModeEnabled: true,
      joinPrefix: '【',
      joinSuffix: '】',
    );
    final restored = GroupChatSession.fromMap(s.toMap());
    expect(restored.chatId, 'b2');
    expect(restored.activationStrategy, GroupActivationStrategy.pooled);
    expect(restored.generationMode, GroupGenerationMode.append);
    expect(restored.allowSelfResponses, true);
    expect(restored.disabledMemberIds, ['c2']);
    expect(restored.autoModeDelay, 8);
    expect(restored.autoModeEnabled, true);
    expect(restored.joinPrefix, '【');
    expect(restored.joinSuffix, '】');
  });
}
```

Run: `flutter test test/group_chat_session_config_test.dart`
Expected: FAIL（枚举/字段未定义）

- [ ] **Step 2: 模型加枚举与字段**

`lib/models/group_chat_session.dart` 顶部（import 后）加枚举：
```dart
/// 群聊激活策略（对标 SillyTavern group_activation_strategy）
enum GroupActivationStrategy { natural, list, manual, pooled }

/// 群聊生成模式（对标 SillyTavern group_generation_mode）
enum GroupGenerationMode { swap, append, appendDisabled }
```

类内字段（`syncSeq` 后）：
```dart
  /// 当前聊天记录 id（多聊天记录，默认=群 id）
  final String chatId;
  /// 激活策略：natural 提及+话痨 / list 按序轮流 / manual 手动 / pooled 轮转池
  final GroupActivationStrategy activationStrategy;
  /// 生成模式：swap 逐角色 / append 合并卡 / appendDisabled 合并卡(禁言排除)
  final GroupGenerationMode generationMode;
  /// 允许同一角色连续发言
  final bool allowSelfResponses;
  /// 禁言成员 id 列表
  final List<String> disabledMemberIds;
  /// 自动接话轮询间隔（秒，对标 auto_mode_delay 默认 5）
  final int autoModeDelay;
  /// 自动接话总开关
  final bool autoModeEnabled;
  /// APPEND 合并角色卡字段前缀模板
  final String joinPrefix;
  /// APPEND 合并角色卡字段后缀模板
  final String joinSuffix;
```

构造（`this.syncSeq = 0,` 后）：
```dart
    this.chatId,
    this.activationStrategy = GroupActivationStrategy.natural,
    this.generationMode = GroupGenerationMode.swap,
    this.allowSelfResponses = false,
    this.disabledMemberIds = const [],
    this.autoModeDelay = 5,
    this.autoModeEnabled = false,
    this.joinPrefix = '',
    this.joinSuffix = '',
```
（构造体内 `syncSeq: syncSeq ?? this.syncSeq,` 模式，copyWith 里）：
```dart
  GroupChatSession copyWith({
    ...
    String? chatId,
    GroupActivationStrategy? activationStrategy,
    GroupGenerationMode? generationMode,
    bool? allowSelfResponses,
    List<String>? disabledMemberIds,
    int? autoModeDelay,
    bool? autoModeEnabled,
    String? joinPrefix,
    String? joinSuffix,
  }) {
    return GroupChatSession(
      ...
      chatId: chatId ?? this.chatId,
      activationStrategy: activationStrategy ?? this.activationStrategy,
      generationMode: generationMode ?? this.generationMode,
      allowSelfResponses: allowSelfResponses ?? this.allowSelfResponses,
      disabledMemberIds: disabledMemberIds ?? this.disabledMemberIds,
      autoModeDelay: autoModeDelay ?? this.autoModeDelay,
      autoModeEnabled: autoModeEnabled ?? this.autoModeEnabled,
      joinPrefix: joinPrefix ?? this.joinPrefix,
      joinSuffix: joinSuffix ?? this.joinSuffix,
    );
  }
```

toMap 加：
```dart
      'chatId': chatId,
      'activationStrategy': activationStrategy.index,
      'generationMode': generationMode.index,
      'allowSelfResponses': allowSelfResponses ? 1 : 0,
      'disabledMemberIds': jsonEncode(disabledMemberIds),
      'autoModeDelay': autoModeDelay,
      'autoModeEnabled': autoModeEnabled ? 1 : 0,
      'joinPrefix': joinPrefix,
      'joinSuffix': joinSuffix,
```

fromMap 加（`syncSeq` 解析后、return 前注意 chatId 默认逻辑）：
```dart
    final chatIdVal = map['chatId']?.toString() ?? map['id']?.toString() ?? '';
    final asInt = map['activationStrategy'];
    final asEnum = asInt is int && asInt >= 0 && asInt < GroupActivationStrategy.values.length
        ? GroupActivationStrategy.values[asInt]
        : GroupActivationStrategy.natural;
    final gmVal = map['generationMode'];
    final gmEnum = gmVal is int && gmVal >= 0 && gmVal < GroupGenerationMode.values.length
        ? GroupGenerationMode.values[gmVal]
        : GroupGenerationMode.swap;
    final rawDisabled = map['disabledMemberIds'];
    List<String> disabled = [];
    if (rawDisabled is String && rawDisabled.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawDisabled);
        if (decoded is List) disabled = decoded.cast<String>();
      } catch (_) {}
    }
```
return 处加：
```dart
      chatId: chatIdVal,
      activationStrategy: asEnum,
      generationMode: gmEnum,
      allowSelfResponses: map['allowSelfResponses'] == 1 || map['allowSelfResponses'] == true,
      disabledMemberIds: disabled,
      autoModeDelay: (map['autoModeDelay'] as int?) ?? 5,
      autoModeEnabled: map['autoModeEnabled'] == 1 || map['autoModeEnabled'] == true,
      joinPrefix: map['joinPrefix']?.toString() ?? '',
      joinSuffix: map['joinSuffix']?.toString() ?? '',
```

props 加（`syncSeq,` 后）：
```dart
        chatId,
        activationStrategy,
        generationMode,
        allowSelfResponses,
        disabledMemberIds,
        autoModeDelay,
        autoModeEnabled,
        joinPrefix,
        joinSuffix,
```

注意：`chatId` 构造默认值不能为 const 依赖 id，用 `this.chatId` 不加默认值，`_onCreate`/`_onUpgrade` 已保证 DB 有列；代码里 new 时若不传 chatId 则为 null —— 为安全，构造加默认：
```dart
    String? chatId,
```
body 中：
```dart
  }) : chatId = chatId ?? id,
```
把 `this.chatId` 改为局部参数 `String? chatId`，用初始化列表兜底 `chatId = chatId ?? id`。注意 copyWith 的 `chatId: chatId ?? this.chatId` 不传时保持原值，传 null 无法置空（可接受，聊天记录 id 不会为 null）。

- [ ] **Step 3: 跑测试**

Run: `flutter test test/group_chat_session_config_test.dart`
Expected: PASS 2/2

- [ ] **Step 4: Commit**

```bash
git add lib/models/group_chat_session.dart test/group_chat_session_config_test.dart
git commit -m "feat: GroupChatSession 加引擎配置（策略/模式/禁言/允自答/自动接话/分支id）"
```

---

### Task 4: GroupChatMessage 加 chatId + GroupChatBranch 模型 + DAO

**Files:**
- Modify: `lib/models/group_chat_message.dart`
- Create: `lib/models/group_chat_branch.dart`
- Modify: `lib/repositories/local_storage_repository.dart`（DAO 区域 6670-6789）
- Test: `test/group_chat_branch_model_test.dart`（新建）

- [ ] **Step 1: GroupChatMessage 加 chatId 字段**

`lib/models/group_chat_message.dart`：
- 字段（`groupId` 后）：
```dart
  /// 所属聊天记录 id（多聊天记录，默认=groupId）
  final String chatId;
```
- 构造：
```dart
    this.chatId = '',
```
- copyWith：加 `String? chatId,` 参数，body 加 `chatId: chatId ?? this.chatId,`
- toMap 加 `'chatId': chatId,`
- fromMap 加 `chatId: (map['chatId'] as String?) ?? '',`

- [ ] **Step 2: 写 GroupChatBranch 模型**

`lib/models/group_chat_branch.dart`：
```dart
import 'package:equatable/equatable.dart';

/// 群聊聊天记录（分支）— 对标 SillyTavern group.chats[chatId]
class GroupChatBranch extends Equatable {
  final String branchId;
  final String groupId;
  final String name;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const GroupChatBranch({
    required this.branchId,
    required this.groupId,
    this.name = '默认聊天',
    required this.createdAt,
    this.updatedAt,
  });

  GroupChatBranch copyWith({
    String? branchId,
    String? groupId,
    String? name,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return GroupChatBranch(
      branchId: branchId ?? this.branchId,
      groupId: groupId ?? this.groupId,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() => {
        'branchId': branchId,
        'groupId': groupId,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
      };

  factory GroupChatBranch.fromMap(Map<String, dynamic> map) {
    final ca = map['createdAt'];
    final ua = map['updatedAt'];
    return GroupChatBranch(
      branchId: map['branchId'] as String,
      groupId: (map['groupId'] as String?) ?? '',
      name: (map['name'] as String?) ?? '默认聊天',
      createdAt: ca is String
          ? (DateTime.tryParse(ca) ?? DateTime.now())
          : DateTime.now(),
      updatedAt: ua is String ? DateTime.tryParse(ua) : null,
    );
  }

  @override
  List<Object?> get props => [branchId, groupId, name, createdAt, updatedAt];
}
```

- [ ] **Step 3: 写分支模型测试**

`test/group_chat_branch_model_test.dart`：
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/models/group_chat_branch.dart';

void main() {
  test('分支模型 toMap/fromMap 往返', () {
    final b = GroupChatBranch(
      branchId: 'b1', groupId: 'g1', name: '深夜话题',
      createdAt: DateTime(2026, 8, 2),
    );
    final restored = GroupChatBranch.fromMap(b.toMap());
    expect(restored.branchId, 'b1');
    expect(restored.groupId, 'g1');
    expect(restored.name, '深夜话题');
    expect(restored.createdAt, DateTime(2026, 8, 2));
  });

  test('消息模型 chatId 默认与往返', () {
    final m = GroupChatMessage(
      id: 'm1', groupId: 'g1', senderId: 'ai_c1',
      senderName: 'A', content: 'hi', isUser: false,
    );
    expect(m.chatId, '');
    final restored = GroupChatMessage.fromMap(m.toMap());
    expect(restored.chatId, '');
    final m2 = m.copyWith(chatId: 'b2');
    expect(GroupChatMessage.fromMap(m2.toMap()).chatId, 'b2');
  });
}
```
（需在测试文件加 `import 'package:solace/models/group_chat_message.dart';`）

Run: `flutter test test/group_chat_branch_model_test.dart`
Expected: PASS 2/2（chatId 字段存在后）

- [ ] **Step 4: DAO 加分支方法 + 消息按 chatId 过滤**

`local_storage_repository.dart` 的群聊 DAO 区（`saveGroupChatMessage` 前，约 6738 行前）插入：

```dart
  Future<List<GroupChatBranch>> getGroupChatBranches(String groupId) async {
    final db = await _db;
    final maps = await db.query('group_chat_branches',
        where: 'groupId = ?', whereArgs: [groupId],
        orderBy: 'createdAt ASC');
    return maps.map(GroupChatBranch.fromMap).toList();
  }

  Future<GroupChatBranch> createGroupChatBranch(
      String groupId, String name) async {
    final branch = GroupChatBranch(
      branchId: 'br_${DateTime.now().microsecondsSinceEpoch}',
      groupId: groupId,
      name: name,
      createdAt: DateTime.now(),
    );
    final db = await _db;
    await db.insert('group_chat_branches', branch.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
    return branch;
  }

  Future<void> renameGroupChatBranch(String branchId, String name) async {
    final db = await _db;
    await db.update('group_chat_branches', {'name': name},
        where: 'branchId = ?', whereArgs: [branchId]);
  }

  Future<void> deleteGroupChatBranch(String groupId, String branchId) async {
    final db = await _db;
    await db.delete('group_chat_branches',
        where: 'branchId = ?', whereArgs: [branchId]);
    await db.delete('group_chat_messages',
        where: 'groupId = ? AND chatId = ?', whereArgs: [groupId, branchId]);
  }
```

`getGroupChatMessages`（6749 行）改签名加 chatId 过滤：
```dart
  Future<List<GroupChatMessage>> getGroupChatMessages(String groupId,
      {int? limit, String? chatId}) async {
    final db = await _db;
    final messages = <GroupChatMessage>[];
    if (chatId != null && chatId.isNotEmpty) {
      final rows = await db.query(
        'group_chat_messages',
        where: 'groupId = ? AND chatId = ?',
        whereArgs: [groupId, chatId],
        orderBy: 'createdAt ASC',
        limit: limit,
      );
      messages.addAll(rows.map(GroupChatMessage.fromMap));
      return messages;
    }
    // 兼容：chatId 为空时默认取 groupId 或旧数据（chatId=''）并按时间合并
    final rows = await db.query(
      'group_chat_messages',
      where: 'groupId = ?',
      whereArgs: [groupId],
      orderBy: 'createdAt ASC',
      limit: limit,
    );
    messages.addAll(rows.map(GroupChatMessage.fromMap));
    return messages;
  }
```
（保留原实现结构，仅加 chatId 分支；原实现中 `_legacy` JSON 分支逻辑保持不动——检查原函数体后按原样保留 JSON 兼容读取，仅在查询处加过滤。若原函数从 data 表读 JSON，则以实际代码为准调整。）

- [ ] **Step 5: analyze + 跑测试**

Run: `flutter analyze lib/models/group_chat_message.dart lib/models/group_chat_branch.dart lib/repositories/local_storage_repository.dart`
Run: `flutter test test/group_chat_branch_model_test.dart`
Expected: 无 error，测试 PASS

- [ ] **Step 6: Commit**

```bash
git add lib/models/group_chat_message.dart lib/models/group_chat_branch.dart lib/repositories/local_storage_repository.dart test/group_chat_branch_model_test.dart
git commit -m "feat: 群聊多聊天记录 — 消息 chatId + 分支模型/DAO"
```

---

### Task 5: 发言人选择算法（ST activate 系列 → Dart 纯函数）

**Files:**
- Create: `lib/blocs/group_chat/group_chat_speaker.dart`
- Test: `test/group_chat_speaker_test.dart`（新建）

对标 ST `group-chats.js`：`activateNaturalOrder`(1242)/`activateListOrder`(1180)/`activatePooledOrder`(1197)/`activateImpersonate`(1114)/`activateSwipe`(1130)。

- [ ] **Step 1: 写失败测试**

`test/group_chat_speaker_test.dart`：
```dart
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/blocs/group_chat/group_chat_speaker.dart';
import 'package:solace/models/group_chat_session.dart';

void main() {
  final members = ['c1', 'c2', 'c3'];
  final talk = {'c1': 1.0, 'c2': 0.0, 'c3': 0.5};
  final fixedRandom = Random(42);

  test('LIST 按成员顺序全员激活', () {
    final result = selectSpeakers(
      strategy: GroupActivationStrategy.list,
      ctx: SpeakerContext(
        memberIds: members,
        disabledMemberIds: [],
        historySpeakerIds: [],
        lastMessageSpeakerId: 'c3',
        talkativeness: talk,
        allowSelfResponses: false,
        userInput: '',
        isUserInput: true,
        forceCharacterId: null,
        random: fixedRandom,
      ),
    );
    expect(result, ['c1', 'c2', 'c3']);
  });

  test('LIST 排除禁言成员', () {
    final result = selectSpeakers(
      strategy: GroupActivationStrategy.list,
      ctx: SpeakerContext(
        memberIds: members,
        disabledMemberIds: ['c2'],
        historySpeakerIds: [],
        lastMessageSpeakerId: null,
        talkativeness: talk,
        allowSelfResponses: false,
        userInput: '',
        isUserInput: true,
        forceCharacterId: null,
        random: fixedRandom,
      ),
    );
    expect(result, ['c1', 'c3']);
  });

  test('POOLED 优先选用户消息后未发言者', () {
    final result = selectSpeakers(
      strategy: GroupActivationStrategy.pooled,
      ctx: SpeakerContext(
        memberIds: members,
        disabledMemberIds: [],
        historySpeakerIds: ['c1', 'c2'],
        lastMessageSpeakerId: 'c2',
        talkativeness: talk,
        allowSelfResponses: false,
        userInput: '大家好',
        isUserInput: true,
        forceCharacterId: null,
        random: fixedRandom,
      ),
    );
    // c1、c2 已发言，只剩 c3
    expect(result, ['c3']);
  });

  test('POOLED 全部说过时排除最后发言者', () {
    final result = selectSpeakers(
      strategy: GroupActivationStrategy.pooled,
      ctx: SpeakerContext(
        memberIds: members,
        disabledMemberIds: [],
        historySpeakerIds: ['c1', 'c2', 'c3'],
        lastMessageSpeakerId: 'c3',
        talkativeness: talk,
        allowSelfResponses: false,
        userInput: '继续聊',
        isUserInput: true,
        forceCharacterId: null,
        random: fixedRandom,
      ),
    );
    expect(result.length, 1);
    expect(result.first, isNot('c3'));
  });

  test('NATURAL 提及检测：输入含角色名则激活该角色', () {
    final result = selectSpeakers(
      strategy: GroupActivationStrategy.natural,
      ctx: SpeakerContext(
        memberIds: members,
        disabledMemberIds: [],
        historySpeakerIds: [],
        lastMessageSpeakerId: null,
        talkativeness: {'c1': 0.0, 'c2': 0.0, 'c3': 0.0},
        allowSelfResponses: false,
        userInput: '我觉得小美说得对',
        isUserInput: true,
        forceCharacterId: null,
        random: fixedRandom,
        memberNames: {'c1': '小美', 'c2': '阿强', 'c3': '小芳'},
      ),
    );
    expect(result, ['c1']);
  });

  test('NATURAL 无提及无高话痨时随机兜底（talkativeness>0 池）', () {
    final result = selectSpeakers(
      strategy: GroupActivationStrategy.natural,
      ctx: SpeakerContext(
        memberIds: members,
        disabledMemberIds: [],
        historySpeakerIds: [],
        lastMessageSpeakerId: 'c2',
        talkativeness: talk,
        allowSelfResponses: false,
        userInput: '',
        isUserInput: false,
        forceCharacterId: null,
        random: fixedRandom,
      ),
    );
    expect(result.length, 1);
    expect(result.first, isNot('c2')); // 排除上一条发言者
  });

  test('NATURAL allowSelfResponses 允许连续发言', () {
    final result = selectSpeakers(
      strategy: GroupActivationStrategy.natural,
      ctx: SpeakerContext(
        memberIds: ['c1'],
        disabledMemberIds: [],
        historySpeakerIds: [],
        lastMessageSpeakerId: 'c1',
        talkativeness: {'c1': 1.0},
        allowSelfResponses: true,
        userInput: '',
        isUserInput: false,
        forceCharacterId: null,
        random: fixedRandom,
      ),
    );
    expect(result, ['c1']);
  });

  test('MANUAL 指定角色', () {
    final result = selectSpeakers(
      strategy: GroupActivationStrategy.manual,
      ctx: SpeakerContext(
        memberIds: members,
        disabledMemberIds: [],
        historySpeakerIds: [],
        lastMessageSpeakerId: null,
        talkativeness: talk,
        allowSelfResponses: false,
        userInput: '',
        isUserInput: false,
        forceCharacterId: 'c2',
        random: fixedRandom,
      ),
    );
    expect(result, ['c2']);
  });
}
```

Run: `flutter test test/group_chat_speaker_test.dart`
Expected: FAIL（类型未定义）

- [ ] **Step 2: 实现算法**

`lib/blocs/group_chat/group_chat_speaker.dart`：
```dart
import 'dart:math';
import 'package:solace/models/group_chat_session.dart';

/// 群聊发言人选择上下文（对标 ST group-chats.js 各 activate 函数入参）
class SpeakerContext {
  /// 群成员 AI 角色 id（有序，ST members）
  final List<String> memberIds;

  /// 禁言成员 id（ST disabled_members）
  final List<String> disabledMemberIds;

  /// 自用户最后一条消息以来的角色发言序列（ST activatePooledOrder 的 spokenSinceUser）
  final List<String> historySpeakerIds;

  /// 最后一条消息发言者角色 id（用户消息则为 null）
  final String? lastMessageSpeakerId;

  /// 角色 id → 健谈度 0~1（ST talkativeness，默认 0.5）
  final Map<String, double> talkativeness;

  /// 是否允许同一角色连续发言（ST allow_self_responses）
  final bool allowSelfResponses;

  /// 用户输入文本（提及检测用，ST input）
  final String userInput;

  /// 是否用户输入触发（ST isUserInput）
  final bool isUserInput;

  /// 手动点名角色 id（ST force_chid / impersonate）
  final String? forceCharacterId;

  /// 角色 id → 名称（提及检测用）
  final Map<String, String> memberNames;

  final Random random;

  const SpeakerContext({
    required this.memberIds,
    this.disabledMemberIds = const [],
    this.historySpeakerIds = const [],
    this.lastMessageSpeakerId,
    this.talkativeness = const {},
    this.allowSelfResponses = false,
    this.userInput = '',
    this.isUserInput = false,
    this.forceCharacterId,
    this.memberNames = const {},
    required this.random,
  });

  List<String> get enabledMemberIds =>
      memberIds.where((m) => !disabledMemberIds.contains(m)).toList();
}

/// 选择本次发言角色列表（ST generateGroupWrapper 的 activatedMembers）
List<String> selectSpeakers({
  required GroupActivationStrategy strategy,
  required SpeakerContext ctx,
}) {
  if (strategy == GroupActivationStrategy.manual) {
    return _activateImpersonate(ctx);
  }
  final members = ctx.enabledMemberIds;
  if (members.isEmpty) return [];

  switch (strategy) {
    case GroupActivationStrategy.list:
      return _activateListOrder(members);
    case GroupActivationStrategy.pooled:
      return _activatePooledOrder(members, ctx);
    case GroupActivationStrategy.natural:
      return _activateNaturalOrder(members, ctx);
    case GroupActivationStrategy.manual:
      return _activateImpersonate(ctx);
  }
}

/// ST activateListOrder：按成员列表顺序全员激活
List<String> _activateListOrder(List<String> members) {
  return List.of(members);
}

/// ST activateImpersonate：随机取一个成员
List<String> _activateImpersonate(SpeakerContext ctx) {
  final forced = ctx.forceCharacterId;
  if (forced != null && ctx.enabledMemberIds.contains(forced)) {
    return [forced];
  }
  final members = ctx.enabledMemberIds;
  if (members.isEmpty) return [];
  return [members[ctx.random.nextInt(members.length)]];
}

/// ST activatePooledOrder：优先未发言者，全部说过排除最后发言者
List<String> _activatePooledOrder(List<String> members, SpeakerContext ctx) {
  String? activated;
  final haveNotSpoken =
      members.where((m) => !ctx.historySpeakerIds.contains(m)).toList();
  if (haveNotSpoken.isNotEmpty) {
    activated = haveNotSpoken[ctx.random.nextInt(haveNotSpoken.length)];
  }
  if (activated == null) {
    final lastAvatar = members.length > 1 &&
        ctx.lastMessageSpeakerId != null &&
        ctx.historySpeakerIds.isNotEmpty
        ? ctx.lastMessageSpeakerId
        : null;
    final pool = lastAvatar != null && members.contains(lastAvatar)
        ? members.where((m) => m != lastAvatar).toList()
        : members;
    activated = pool[ctx.random.nextInt(pool.length)];
  }
  return [activated];
}

/// ST activateNaturalOrder：提及检测 + 话痨概率 roll + 随机兜底
List<String> _activateNaturalOrder(List<String> members, SpeakerContext ctx) {
  final activated = <String>[];
  // 禁止与最后一条消息同角色连续发言（除非 allowSelfResponses）
  String? banned = !ctx.isUserInput &&
          ctx.lastMessageSpeakerId != null
      ? ctx.lastMessageSpeakerId
      : null;
  if (ctx.allowSelfResponses) banned = null;

  // 提及检测：输入中出现角色名（长度>=2）则激活
  if (ctx.userInput.isNotEmpty) {
    final words = _extractWords(ctx.userInput);
    for (final w in words) {
      for (final m in members) {
        if (m == banned) continue;
        final name = ctx.memberNames[m] ?? m;
        if (name.length >= 2 && words.contains(name)) {
          if (!activated.contains(m)) activated.add(m);
          break;
        }
      }
    }
  }

  // 话痨概率 roll（打乱顺序，排除禁言者）
  final shuffled = List.of(members)..shuffle(ctx.random);
  final chattyMembers = <String>[];
  for (final m in shuffled) {
    if (m == banned) continue;
    final t = ctx.talkativeness[m] ?? 0.5;
    if (ctx.random.nextDouble() <= t) {
      if (!activated.contains(m)) activated.add(m);
    }
    if (t > 0) chattyMembers.add(m);
  }

  // 兜底：没人激活时随机选（优先 talkativeness>0 池）
  if (activated.isEmpty) {
    final pool = chattyMembers.isNotEmpty ? chattyMembers : members;
    final candidates = pool.where((m) => m != banned).toList();
    final source = candidates.isNotEmpty ? candidates : pool;
    int retries = 0;
    while (activated.isEmpty && retries < source.length) {
      final picked = source[ctx.random.nextInt(source.length)];
      if (!activated.contains(picked)) activated.add(picked);
      retries++;
    }
  }

  return activated.toSet().toList();
}

/// 简单分词：按非字母数字切分（中文按整词/整名匹配）
List<String> _extractWords(String text) {
  return text
      .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
      .where((s) => s.isNotEmpty)
      .toList();
}
```

- [ ] **Step 3: 跑测试**

Run: `flutter test test/group_chat_speaker_test.dart`
Expected: PASS 8/8
注意：NATURAL 提及检测用 `words.contains(name)`（name 是中文时整个名字作为一个 token）。若测试"我觉得小美说得对"分词后含"小美"则过。若 split 后 token 是"我觉得小美说得对"整串（unicode 属性分词不支持中文内部切割），需要换实现：直接 `userInput.contains(name)`。改用子串匹配更稳：

`_extractWords` 改为在 NATURAL 中使用子串检查：
```dart
  if (ctx.userInput.isNotEmpty) {
    for (final m in members) {
      if (m == banned) continue;
      final name = ctx.memberNames[m] ?? m;
      if (name.length >= 2 && ctx.userInput.contains(name)) {
        if (!activated.contains(m)) activated.add(m);
      }
    }
  }
```
（测试固定 random 可能导致 POOLED 兜底分支随机性：POOLED 测试"全部说过"时 pool 是排除 lastMessageSpeakerId 后的 2 人随机取 1，固定 random 下结果确定但不确定是哪个——断言 `isNot('c3')` 即可，无 flaky。）

- [ ] **Step 4: Commit**

```bash
git add lib/blocs/group_chat/group_chat_speaker.dart test/group_chat_speaker_test.dart
git commit -m "feat: 群聊发言人选择算法（NATURAL/LIST/POOLED/MANUAL，对标 SillyTavern）"
```

---

### Task 6: 群聊 prompt 构建（ST prompt 三件套 + 消息格式化 + 合并卡）

**Files:**
- Create: `lib/blocs/group_chat/group_chat_prompts.dart`
- Test: `test/group_chat_prompts_test.dart`（新建）

对标 ST openai.js：`default_main_prompt`(101)、`default_new_group_chat_prompt`(108)、`default_group_nudge_prompt`(114)、历史前缀(585)、`getGroupCharacterCardsLazy`(497)。

- [ ] **Step 1: 写失败测试**

`test/group_chat_prompts_test.dart`：
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/blocs/group_chat/group_chat_prompts.dart';
import 'package:solace/models/ai_character.dart';

void main() {
  final charA = AICharacter(
    id: 'c1', name: '小美', personality: '温柔', coreDesire: '陪伴',
    moralBoundary: '不伤人', createdAt: DateTime.now(),
    backgroundStory: '咖啡店店员', openingLine: '你好呀',
    catchphrases: '好耶',
  );
  final charB = AICharacter(
    id: 'c2', name: '阿强', personality: '直爽', coreDesire: '热闹',
    moralBoundary: '不骗人', createdAt: DateTime.now(),
    backgroundStory: '程序员', openingLine: '哟',
    catchphrases: '整',
  );

  test('群成员名单 prompt（对标 new_group_chat_prompt）', () {
    final p = buildGroupIntroPrompt(
      selfName: '小美',
      memberNames: ['小美', '阿强', '你'],
      isNewChat: true,
    );
    expect(p, contains('群成员'));
    expect(p, contains('小美'));
    expect(p, contains('阿强'));
  });

  test('nudge prompt（对标 group_nudge_prompt）', () {
    expect(buildGroupNudge('小美'), '[请只以「小美」的身份继续发言。]');
  });

  test('消息格式化：自己发言不带前缀，他人带 名字: 内容', () {
    expect(formatGroupMessage(isSelf: true, senderName: '小美', content: '哈喽'), '哈喽');
    expect(formatGroupMessage(isSelf: false, senderName: '阿强', content: '整'), '阿强: 整');
  });

  test('合并角色卡（对标 getGroupCharacterCards）', () {
    final combined = buildCombinedCard(
      members: [charA, charB],
      joinPrefix: '',
      joinSuffix: '',
    );
    expect(combined.description, contains('咖啡店店员'));
    expect(combined.description, contains('程序员'));
    expect(combined.personality, contains('温柔'));
    expect(combined.personality, contains('直爽'));
  });

  test('合并卡 joinPrefix/joinSuffix 包字段', () {
    final combined = buildCombinedCard(
      members: [charA],
      joinPrefix: '【',
      joinSuffix: '】',
    );
    expect(combined.description, contains('【咖啡店店员】'));
  });
}

/// 合并卡结果结构
class CombinedCard {
  final String description;
  final String personality;
  final String scenario;
  final String mesExamples;
  const CombinedCard({required this.description, required this.personality, required this.scenario, required this.mesExamples});
}
```
（CombinedCard 应在实现文件中定义并从那里 import；测试里直接引用实现导出的类型。）

- [ ] **Step 2: 实现**

`lib/blocs/group_chat/group_chat_prompts.dart`：
```dart
import 'package:solace/models/ai_character.dart';

/// 合并角色卡结果（对标 ST getGroupCharacterCards 的 description/personality/scenario/mesExamples）
class CombinedCard {
  final String description;
  final String personality;
  final String scenario;
  final String mesExamples;
  const CombinedCard({
    required this.description,
    required this.personality,
    required this.scenario,
    required this.mesExamples,
  });
}

/// 群成员名单 + 新群聊提示（对标 ST new_group_chat_prompt: [Start a new group chat. Group members: {{group}}]）
String buildGroupIntroPrompt({
  required String selfName,
  required List<String> memberNames,
  required bool isNewChat,
}) {
  final memberList = memberNames.isEmpty ? selfName : memberNames.join('、');
  final base = '这是一个群聊。你是「$selfName」，群成员有：$memberList。'
      '你在群里发言要自然，像真人聊天一样，语气符合你的性格。'
      '刚才大家聊的内容见历史消息。';
  if (isNewChat) {
    return '$base\n[开始一个新的群聊。群成员: $memberList]';
  }
  return base;
}

/// 群聊 nudge：告诉 LLM 只以指定角色发言（对标 ST group_nudge_prompt）
String buildGroupNudge(String selfName) => '[请只以「$selfName」的身份继续发言。]';

/// 群聊历史消息格式化：自己消息不带前缀，他人消息加 `名字: 内容`
/// （对标 ST openai.js:585 群聊角色名前缀）
String formatGroupMessage({
  required bool isSelf,
  required String senderName,
  required String content,
}) {
  if (isSelf) return content;
  return '$senderName: $content';
}

/// 合并全员角色卡（对标 ST getGroupCharacterCardsLazy，generation_mode APPEND）
CombinedCard buildCombinedCard({
  required List<AICharacter> members,
  required String joinPrefix,
  required String joinSuffix,
}) {
  String collectField(String Function(AICharacter) getter) {
    final values = <String>[];
    for (final c in members) {
      final v = getter(c)?.trim() ?? '';
      if (v.isEmpty) continue;
      values.add('$joinPrefix$v$joinSuffix');
    }
    return values.join('\n');
  }

  return CombinedCard(
    description: collectField((c) => _firstNonEmpty([
          c.backgroundStory,
          c.worldSetting,
          c.personality,
        ])),
    personality: collectField((c) => c.personality),
    scenario: collectField((c) => _firstNonEmpty([c.worldSetting])),
    mesExamples: collectField((c) => _buildMesExample(c)),
  );
}

String _firstNonEmpty(List<String?> values) {
  for (final v in values) {
    if (v != null && v.trim().isNotEmpty) return v!;
  }
  return '';
}

String _buildMesExample(AICharacter c) {
  final parts = <String>[];
  if (c.openingLine != null && c.openingLine!.trim().isNotEmpty) {
    parts.add('${c.name}: ${c.openingLine}');
  }
  if (c.catchphrases != null && c.catchphrases!.trim().isNotEmpty) {
    parts.add('${c.name}: ${c.catchphrases}');
  }
  if (c.dialogueExamples.isNotEmpty) {
    for (final e in c.dialogueExamples) {
      parts.add('用户: ${e.userMessage}\n${c.name}: ${e.aiResponse}');
    }
  }
  return parts.join('\n');
}
```

- [ ] **Step 3: 跑测试**

Run: `flutter test test/group_chat_prompts_test.dart`
Expected: PASS 5/5
（测试文件导入改为 `import 'package:solace/blocs/group_chat/group_chat_prompts.dart';`，删除文件内重复的 CombinedCard 类定义。）

- [ ] **Step 4: Commit**

```bash
git add lib/blocs/group_chat/group_chat_prompts.dart test/group_chat_prompts_test.dart
git commit -m "feat: 群聊 prompt 构建（成员名单/nudge/历史格式化/合并角色卡）"
```

---

### Task 7: 重写群聊引擎 — 策略驱动生成 + APPEND + 自动接话轮询

**Files:**
- Modify: `lib/blocs/group_chat/group_chat_bloc.dart`（核心 503 行）
- Modify: `lib/blocs/group_chat/group_chat_event.dart`
- Modify: `lib/blocs/group_chat/group_chat_state.dart`
- Test: `test/group_chat_bloc_engine_test.dart`（新建，轻量单测辅助函数）

- [ ] **Step 1: event 扩展**

`group_chat_event.dart` 加：
```dart
/// 更新群聊引擎配置（激活策略/生成模式/禁言/允自答/自动接话）
class GroupChatUpdateConfig extends GroupChatEvent {
  final String groupId;
  final GroupActivationStrategy? activationStrategy;
  final GroupGenerationMode? generationMode;
  final bool? allowSelfResponses;
  final List<String>? disabledMemberIds;
  final int? autoModeDelay;
  final bool? autoModeEnabled;

  const GroupChatUpdateConfig({
    required this.groupId,
    this.activationStrategy,
    this.generationMode,
    this.allowSelfResponses,
    this.disabledMemberIds,
    this.autoModeDelay,
    this.autoModeEnabled,
  });

  @override
  List<Object?> get props => [
        groupId, activationStrategy, generationMode, allowSelfResponses,
        disabledMemberIds, autoModeDelay, autoModeEnabled,
      ];
}

/// 新建聊天记录（分支）
class GroupChatCreateBranch extends GroupChatEvent {
  final String groupId;
  final String name;
  const GroupChatCreateBranch({required this.groupId, required this.name});
  @override
  List<Object?> get props => [groupId, name];
}

/// 切换聊天记录
class GroupChatSwitchBranch extends GroupChatEvent {
  final String groupId;
  final String chatId;
  const GroupChatSwitchBranch({required this.groupId, required this.chatId});
  @override
  List<Object?> get props => [groupId, chatId];
}

/// 删除聊天记录
class GroupChatDeleteBranch extends GroupChatEvent {
  final String groupId;
  final String chatId;
  const GroupChatDeleteBranch({required this.groupId, required this.chatId});
  @override
  List<Object?> get props => [groupId, chatId];
}
```
（顶部 import `../../models/group_chat_session.dart` 已含枚举；group_chat_event.dart 若为 `part of` 文件则与 bloc 同文件引用，按现有结构处理。）

- [ ] **Step 2: state 加分支列表**

`group_chat_state.dart` 在 MessagesLoaded 相关状态加字段或新增：
```dart
class GroupChatBranchesLoaded extends GroupChatState {
  final String groupId;
  final List<GroupChatBranch> branches;
  final String currentChatId;
  const GroupChatBranchesLoaded({
    required this.groupId,
    required this.branches,
    required this.currentChatId,
  });
  @override
  List<Object?> get props => [groupId, branches, currentChatId];
}
```
（若 state 文件为 `part of group_chat_bloc.dart`，直接在同文件加类并 export。）

- [ ] **Step 3: 重写 _generateAIReplies 为 ST generateGroupWrapper 结构**

`group_chat_bloc.dart` 改造要点（保持现有流式 emit/落库/事件协议，替换选角与上下文构建）：

```dart
  /// ST generateGroupWrapper 的激活列表 → 逐个生成
  Future<void> _generateAIReplies({
    required String groupId,
    required String userId,
    required GroupChatSession session,
    required String userMessage,
    required List<String>? imagePaths,
    required bool isFollowUp,
    required String? excludeCharacterId,
  }) async {
    // 生成模式 APPEND：合并卡一次生成
    if (session.generationMode != GroupGenerationMode.swap) {
      await _generateAppendReply(
        groupId: groupId, userId: userId, session: session,
        userMessage: userMessage, imagePaths: imagePaths,
        isFollowUp: isFollowUp, excludeCharacterId: excludeCharacterId,
      );
      return;
    }

    final history = await _storage.getGroupChatMessages(groupId,
        limit: 40, chatId: session.chatId);
    final members = await _loadMembers(session.aiCharacterIds);
    final historySpeakerIds = _extractHistorySpeakers(history);
    final lastSpeaker = _lastAISpeaker(history);

    final ctx = SpeakerContext(
      memberIds: session.aiCharacterIds,
      disabledMemberIds: session.disabledMemberIds,
      historySpeakerIds: historySpeakerIds,
      lastMessageSpeakerId: lastSpeaker,
      talkativeness: {
        for (final m in members) m.id: m.talkativeness,
      },
      allowSelfResponses: session.allowSelfResponses,
      userInput: userMessage,
      isUserInput: userMessage.isNotEmpty,
      forceCharacterId: isFollowUp ? null : null,
      memberNames: {for (final m in members) m.id: m.name},
      random: _random,
    );

    // MANUAL 但没手动点名 → 随机一人
    final activated = selectSpeakers(
      strategy: session.activationStrategy,
      ctx: ctx,
    );
    if (activated.isEmpty) {
      _replyingGroups[groupId] = false;
      emit(GroupChatMessagesLoaded(
          groupId, await _storage.getGroupChatMessages(groupId, chatId: session.chatId)));
      return;
    }

    // 逐个生成（SWAP 模式，ST 的 for chId of activatedMembers）
    for (final characterId in activated) {
      if (_replyingGroups[groupId] != true) break;
      await _generateOneReply(
        groupId: groupId, userId: userId, session: session,
        characterId: characterId, userMessage: userMessage,
        imagePaths: imagePaths, isFollowUp: isFollowUp,
      );
    }
    _replyingGroups[groupId] = false;
  }

  /// 单个角色生成（SWAP 子流程，含 nudge）
  Future<void> _generateOneReply({
    required String groupId,
    required String userId,
    required GroupChatSession session,
    required String characterId,
    required String userMessage,
    required List<String>? imagePaths,
    required bool isFollowUp,
  }) async {
    final character = await _storage.getAICharacter(characterId);
    if (character == null) return;

    final history = await _storage.getGroupChatMessages(groupId,
        limit: 40, chatId: session.chatId);
    final memories = await _storage.getMemories(
      characterId: characterId,
      userId: userId.isNotEmpty ? userId : 'local_user',
      limit: 8,
    );

    final memberNames = await _buildMemberNames(session);
    final intro = buildGroupIntroPrompt(
      selfName: character.name,
      memberNames: memberNames,
      isNewChat: history.isEmpty,
    );
    final nudge = buildGroupNudge(character.name);
    final internalContext = '$intro\n$nudge';

    final chatHistory = _toChatHistory(history, character.id);

    emit(GroupChatTyping(groupId, character.name,
        messages: await _storage.getGroupChatMessages(groupId, chatId: session.chatId)));
    _followUpCount++;

    String fullText = '';
    try {
      await for (final chunk in _aiService.sendMessageStream(
        character: character,
        userId: userId.isNotEmpty ? userId : 'local_user',
        userMessage: userMessage,
        chatHistory: chatHistory,
        memories: memories,
        intimacyLevel: 50,
        sentiment: null,
        imagePaths: imagePaths,
        internalSystemContext: internalContext,
      )) {
        fullText = chunk.content;
        if (fullText.isNotEmpty) {
          emit(GroupChatStreaming(groupId, character.name, fullText,
              messages: await _storage.getGroupChatMessages(groupId, chatId: session.chatId)));
        }
      }
    } catch (e) {
      LogService.instance.e('GroupChat', 'AI 回复失败: $e', chatId: groupId);
      return;
    }

    final cleanText = MessageSanitizer.sanitizeFinal(fullText).trim();
    if (cleanText.isEmpty) return;

    final aiMsg = GroupChatMessage(
      id: _uuid.v4(),
      groupId: groupId,
      chatId: session.chatId,
      senderId: 'ai_$characterId',
      senderName: character.name,
      content: cleanText,
      isUser: false,
      type: GroupChatMessageType.text,
      timestamp: DateTime.now(),
      status: GroupChatMessageStatus.sent,
    );
    await _storage.saveGroupChatMessage(aiMsg);

    final latest = await _storage.getGroupChatSession(groupId);
    if (latest != null) {
      await _storage.saveGroupChatSession(latest.copyWith(
        lastMessage: cleanText,
        lastMessageTime: DateTime.now(),
        updatedAt: DateTime.now(),
      ));
    }
    emit(GroupChatMessagesLoaded(
        groupId, await _storage.getGroupChatMessages(groupId, chatId: session.chatId)));

    // 触发接话判定（仅 autoModeEnabled 时继续；否则维持原有单轮接话逻辑）
    add(GroupChatAIMessageSaved(
      groupId: groupId,
      characterId: characterId,
      content: cleanText,
    ));
  }

  /// APPEND 合并卡生成
  Future<void> _generateAppendReply({
    required String groupId,
    required String userId,
    required GroupChatSession session,
    required String userMessage,
    required List<String>? imagePaths,
    required bool isFollowUp,
    required String? excludeCharacterId,
  }) async {
    final enabledIds = session.aiCharacterIds
        .where((id) => !session.disabledMemberIds.contains(id))
        .where((id) => id != excludeCharacterId)
        .toList();
    if (enabledIds.isEmpty) {
      _replyingGroups[groupId] = false;
      return;
    }
    final members = await _loadMembers(enabledIds);
    if (members.isEmpty) {
      _replyingGroups[groupId] = false;
      return;
    }

    final card = buildCombinedCard(
      members: members,
      joinPrefix: session.joinPrefix,
      joinSuffix: session.joinSuffix,
    );

    // 组合角色：用群名作为名称，卡字段合并
    final combo = AICharacter(
      id: session.id,
      name: session.name.isEmpty ? '群聊' : session.name,
      personality: card.personality,
      coreDesire: card.scenario,
      moralBoundary: '',
      backgroundStory: card.description,
      createdAt: DateTime.now(),
      talkativeness: 0.5,
      dialogueExamples: [],
    );

    final history = await _storage.getGroupChatMessages(groupId,
        limit: 40, chatId: session.chatId);
    final memories = await _storage.getMemories(
      characterId: members.first.id,
      userId: userId.isNotEmpty ? userId : 'local_user',
      limit: 8,
    );
    final memberNames = members.map((m) => m.name).toList();
    final internalContext = buildGroupIntroPrompt(
      selfName: session.name.isEmpty ? '群聊' : session.name,
      memberNames: [...memberNames, '你'],
      isNewChat: history.isEmpty,
    );

    final chatHistory = _toChatHistory(history, combo.id);

    emit(GroupChatTyping(groupId, combo.name,
        messages: await _storage.getGroupChatMessages(groupId, chatId: session.chatId)));
    _followUpCount++;

    String fullText = '';
    try {
      await for (final chunk in _aiService.sendMessageStream(
        character: combo,
        userId: userId.isNotEmpty ? userId : 'local_user',
        userMessage: userMessage,
        chatHistory: chatHistory,
        memories: memories,
        intimacyLevel: 50,
        sentiment: null,
        imagePaths: imagePaths,
        internalSystemContext: internalContext,
      )) {
        fullText = chunk.content;
        if (fullText.isNotEmpty) {
          emit(GroupChatStreaming(groupId, combo.name, fullText,
              messages: await _storage.getGroupChatMessages(groupId, chatId: session.chatId)));
        }
      }
    } catch (e) {
      LogService.instance.e('GroupChat', 'APPEND 回复失败: $e', chatId: groupId);
      _replyingGroups[groupId] = false;
      return;
    }

    final cleanText = MessageSanitizer.sanitizeFinal(fullText).trim();
    if (cleanText.isEmpty) {
      _replyingGroups[groupId] = false;
      return;
    }
    final aiMsg = GroupChatMessage(
      id: _uuid.v4(),
      groupId: groupId,
      chatId: session.chatId,
      senderId: 'ai_${members.first.id}',
      senderName: combo.name,
      content: cleanText,
      isUser: false,
      type: GroupChatMessageType.text,
      timestamp: DateTime.now(),
      status: GroupChatMessageStatus.sent,
    );
    await _storage.saveGroupChatMessage(aiMsg);
    _replyingGroups[groupId] = false;
    emit(GroupChatMessagesLoaded(
        groupId, await _storage.getGroupChatMessages(groupId, chatId: session.chatId)));
    add(GroupChatAIMessageSaved(
      groupId: groupId,
      characterId: members.first.id,
      content: cleanText,
    ));
  }

  /// 历史 → 发言人序列（ST activatePooledOrder 的 spokenSinceUser）
  List<String> _extractHistorySpeakers(List<GroupChatMessage> history) {
    final result = <String>[];
    for (final m in history.reversed) {
      if (m.isUser || m.isSystem) break;
      if (m.senderId.startsWith('ai_')) {
        result.add(m.senderId.substring(3));
      }
    }
    return result;
  }

  /// 最后一条 AI 发言者角色 id
  String? _lastAISpeaker(List<GroupChatMessage> history) {
    for (final m in history.reversed) {
      if (m.isUser || m.isSystem) continue;
      if (m.senderId.startsWith('ai_')) return m.senderId.substring(3);
    }
    return null;
  }

  Future<List<AICharacter>> _loadMembers(List<String> ids) async {
    final result = <AICharacter>[];
    for (final id in ids) {
      final c = await _storage.getAICharacter(id);
      if (c != null) result.add(c);
    }
    return result;
  }
```

同时：
- `_triggerAIReply` 中传 `chatId: session.chatId` 到 `_generateAIReplies`（`session` 已含 chatId）
- `_onSendMessage` 的 `saveGroupChatMessage` 处补 `chatId: session.chatId`；`getGroupChatMessages` 查询统一加 `chatId: session.chatId`（读原文件后按行改）
- `_onAIMessageSaved` 的 35% 接话逻辑改为：`session.autoModeEnabled` 时 100% 接话（auto 模式无概率限制，由 delay 轮询控制）；否则保留 35% + 上限 2 条
- `_toChatHistory` 的他人消息格式从 `【名字】内容` 改为 `名字: 内容`（ST 格式）

- [ ] **Step 4: 接话逻辑改版（_onAIMessageSaved）**

```dart
  Future<void> _onAIMessageSaved(
    GroupChatAIMessageSaved event,
    Emitter<GroupChatState> emit,
  ) async {
    try {
      final session = await _storage.getGroupChatSession(event.groupId);
      if (session == null) {
        _replyingGroups[event.groupId] = false;
        return;
      }
      // autoModeEnabled：由定时轮询驱动接话，这里不再概率触发
      if (session.autoModeEnabled) {
        _replyingGroups[event.groupId] = false;
        return;
      }
      if (_followUpCount >= 2) {
        _replyingGroups[event.groupId] = false;
        return;
      }
      final roll = _random.nextDouble();
      if (roll < 0.35) {
        await _generateAIReplies(
          groupId: event.groupId,
          userId: '',
          session: session,
          userMessage: event.content,
          imagePaths: null,
          isFollowUp: true,
          excludeCharacterId: event.characterId,
        );
      } else {
        _replyingGroups[event.groupId] = false;
      }
    } catch (e) {
      LogService.instance.e('GroupChat', '_onAIMessageSaved failed: $e');
      _replyingGroups[event.groupId] = false;
    }
  }
```

- [ ] **Step 5: 自动接话轮询（ST groupChatAutoModeWorker）**

`group_chat_bloc.dart` 顶部加 Timer 字段与开关方法：
```dart
  Timer? _autoModeTimer;
  final Map<String, bool> _autoModeByGroup = {};

  /// 开启/关闭某群自动接话（ST setInterval groupChatAutoModeWorker）
  void configureAutoMode(String groupId, bool enabled, int delaySeconds) {
    _autoModeByGroup[groupId] = enabled;
    _restartAutoModeTimer();
  }

  void _restartAutoModeTimer() {
    _autoModeTimer?.cancel();
    if (!_autoModeByGroup.values.contains(true)) return;
    final minDelay = _autoModeByGroup.entries
        .where((e) => e.value)
        .map((e) => e.key)
        .map((gid) => _currentDelayFor(gid))
        .fold<int>(5, (a, b) => b < a ? b : a);
    _autoModeTimer = Timer.periodic(Duration(seconds: minDelay), (_) {
      _autoModeTick();
    });
  }

  int _currentDelayFor(String groupId) {
    return _groupDelays[groupId] ?? 5;
  }

  final Map<String, int> _groupDelays = {};

  Future<void> _autoModeTick() async {
    for (final entry in _autoModeByGroup.entries) {
      if (!entry.value) continue;
      final groupId = entry.key;
      if (_replyingGroups[groupId] == true) continue;
      final session = await _storage.getGroupChatSession(groupId);
      if (session == null) continue;
      final history = await _storage.getGroupChatMessages(groupId,
          limit: 1, chatId: session.chatId);
      if (history.isEmpty) continue;
      final last = history.last;
      if (last.isUser || last.isSystem) {
        _replyingGroups[groupId] = true;
        _followUpCount = 0;
        await _generateAIReplies(
          groupId: groupId,
          userId: '',
          session: session,
          userMessage: last.content,
          imagePaths: null,
          isFollowUp: true,
          excludeCharacterId: null,
        );
      }
    }
  }
```
（`close()` 中 `_autoModeTimer?.cancel();`）

- [ ] **Step 6: 写轻量引擎测试（纯算法集成）**

`test/group_chat_bloc_engine_test.dart`（不依赖 DB，仅验证辅助纯函数——若辅助函数已私有则改为验证 speaker/prompts 组合行为，或使用 `@visibleForTesting` 导出）：
```dart
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/blocs/group_chat/group_chat_speaker.dart';
import 'package:solace/models/group_chat_session.dart';

void main() {
  test('引擎组合：NATURAL + allowSelfResponses 下多人可连发', () {
    final speakers = selectSpeakers(
      strategy: GroupActivationStrategy.natural,
      ctx: SpeakerContext(
        memberIds: ['c1', 'c2'],
        disabledMemberIds: [],
        historySpeakerIds: [],
        lastMessageSpeakerId: 'c1',
        talkativeness: {'c1': 0.5, 'c2': 0.5},
        allowSelfResponses: true,
        userInput: '',
        isUserInput: false,
        forceCharacterId: null,
        random: Random(1),
      ),
    );
    expect(speakers, isNotEmpty);
  });

  test('引擎组合：禁言成员永远不发言', () {
    for (final s in GroupActivationStrategy.values) {
      final speakers = selectSpeakers(
        strategy: s,
        ctx: SpeakerContext(
          memberIds: ['c1', 'c2'],
          disabledMemberIds: ['c2'],
          historySpeakerIds: [],
          lastMessageSpeakerId: null,
          talkativeness: {'c1': 1.0, 'c2': 1.0},
          allowSelfResponses: false,
          userInput: 'c2',
          isUserInput: true,
          forceCharacterId: 'c2',
          memberNames: {'c1': '甲', 'c2': '乙'},
          random: Random(1),
        ),
      );
      expect(speakers.contains('c2'), false);
    }
  });
}
```
Run: `flutter test test/group_chat_bloc_engine_test.dart`
Expected: PASS 2/2

- [ ] **Step 7: analyze + 全量相关测试**

Run: `flutter analyze lib/blocs/group_chat/`
Run: `flutter test test/group_chat_speaker_test.dart test/group_chat_prompts_test.dart test/group_chat_bloc_engine_test.dart`
Expected: 无 error，测试全 PASS

- [ ] **Step 8: Commit**

```bash
git add lib/blocs/group_chat/ test/group_chat_bloc_engine_test.dart
git commit -m "feat: 群聊引擎重写 — ST 策略驱动生成 + APPEND 合并卡 + 自动接话轮询"
```

---

### Task 8: 群设置面板 + 聊天记录管理 UI

**Files:**
- Modify: `lib/screens/group_chat/group_chat_detail_screen.dart`（_showGroupSettings 457 行扩展、AppBar 菜单加聊天记录）
- Modify: `lib/screens/group_chat/group_chat_create_screen.dart`（新建群默认配置）

- [ ] **Step 1: 设置面板扩展**

`_showGroupSettings()`（457 行）的 bottom sheet 内容追加（在现有改名/公告项后）：
```dart
            // ─── SillyTavern 引擎配置 ───
            const SizedBox(height: 12),
            const Divider(),
            Text('群聊引擎', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            DropdownButtonFormField<GroupActivationStrategy>(
              value: _session?.activationStrategy ?? GroupActivationStrategy.natural,
              decoration: const InputDecoration(labelText: '激活策略'),
              items: const [
                DropdownMenuItem(value: GroupActivationStrategy.natural, child: Text('自然(提及+健谈度)')),
                DropdownMenuItem(value: GroupActivationStrategy.list, child: Text('按列表轮流')),
                DropdownMenuItem(value: GroupActivationStrategy.pooled, child: Text('轮转池')),
                DropdownMenuItem(value: GroupActivationStrategy.manual, child: Text('手动点名')),
              ],
              onChanged: (v) => _dispatchConfig(activationStrategy: v),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<GroupGenerationMode>(
              value: _session?.generationMode ?? GroupGenerationMode.swap,
              decoration: const InputDecoration(labelText: '生成模式'),
              items: const [
                DropdownMenuItem(value: GroupGenerationMode.swap, child: Text('逐角色切换')),
                DropdownMenuItem(value: GroupGenerationMode.append, child: Text('合并角色卡')),
                DropdownMenuItem(value: GroupGenerationMode.appendDisabled, child: Text('合并卡(排除禁言)')),
              ],
              onChanged: (v) => _dispatchConfig(generationMode: v),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              title: const Text('允许同一角色连续发言'),
              value: _session?.allowSelfResponses ?? false,
              onChanged: (v) => _dispatchConfig(allowSelfResponses: v),
            ),
            SwitchListTile(
              title: const Text('自动接话'),
              subtitle: Text('AI 之间持续聊天（对标 SillyTavern Auto Mode）'),
              value: _session?.autoModeEnabled ?? false,
              onChanged: (v) {
                _dispatchConfig(autoModeEnabled: v);
                if (_session != null) {
                  widget.bloc.configureAutoMode(
                      _session!.id, v, _session!.autoModeDelay);
                }
              },
            ),
            ListTile(
              title: const Text('自动接话间隔'),
              trailing: Text('${_session?.autoModeDelay ?? 5} 秒'),
              onTap: () => _showAutoModeDelayPicker(),
            ),
```
新增辅助方法：
```dart
  void _dispatchConfig({
    GroupActivationStrategy? activationStrategy,
    GroupGenerationMode? generationMode,
    bool? allowSelfResponses,
    int? autoModeDelay,
    bool? autoModeEnabled,
  }) {
    widget.bloc.add(GroupChatUpdateConfig(
      groupId: widget.groupId,
      activationStrategy: activationStrategy,
      generationMode: generationMode,
      allowSelfResponses: allowSelfResponses,
      autoModeDelay: autoModeDelay,
      autoModeEnabled: autoModeEnabled,
    ));
  }

  void _showAutoModeDelayPicker() {
    showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('自动接话间隔（秒）'),
        children: [5, 10, 15, 20, 30]
            .map((d) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, d),
                  child: Text('$d 秒'),
                ))
            .toList(),
      ),
    ).then((d) {
      if (d != null) _dispatchConfig(autoModeDelay: d);
    });
  }
```

- [ ] **Step 2: AppBar 菜单加聊天记录管理**

`_handleMenuAction`（440 行）加 case：
```dart
        case 'branches':
          _showBranchManager();
          break;
```
（菜单项在 PopupMenuButton 的 items 中加 `PopupMenuItem(value: 'branches', child: Text('聊天记录'))`）

```dart
  void _showBranchManager() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => FutureBuilder<List<GroupChatBranch>>(
        future: _storage.getGroupChatBranches(widget.groupId),
        builder: (ctx, snap) {
          final branches = snap.data ?? [];
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.add),
                  title: const Text('新建聊天记录'),
                  onTap: () => _createBranch(),
                ),
                ...branches.map((b) => ListTile(
                      title: Text(b.name),
                      subtitle: Text(b.branchId == _session?.chatId ? '当前' : null),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_forward),
                          onPressed: b.branchId == _session?.chatId
                              ? null
                              : () => widget.bloc.add(GroupChatSwitchBranch(
                                  groupId: widget.groupId, chatId: b.branchId)),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => widget.bloc.add(GroupChatDeleteBranch(
                              groupId: widget.groupId, chatId: b.branchId)),
                        ),
                      ]),
                    )),
              ],
            ),
          );
        },
      ),
    );
  }

  void _createBranch() {
    showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建聊天记录'),
        content: TextField(controller: _branchNameController, decoration: const InputDecoration(hintText: '记录名称')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, _branchNameController.text.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    ).then((name) {
      if (name != null && name.isNotEmpty) {
        widget.bloc.add(GroupChatCreateBranch(groupId: widget.groupId, name: name));
      }
    });
  }
```
（`_branchNameController` 在 State 中初始化；`_storage` 引用按现有依赖注入方式获取——detail screen 若未持有 storage，改用 bloc 暴露的 state 或经 bloc 事件拿分支列表。**若 detail screen 无 _storage 字段**，分支列表改为经 `GroupChatBranchesLoaded` state 驱动：bloc 在 LoadMessages/分支事件后 emit 分支状态，UI 从 state 读。执行时按实际代码结构选型——优先复用已有依赖注入。）

- [ ] **Step 3: bloc 处理分支事件**

`group_chat_bloc.dart` 加事件处理（_onCreateBranch/_onSwitchBranch/_onDeleteBranch/_onUpdateConfig）：
```dart
  Future<void> _onUpdateConfig(
      GroupChatUpdateConfig event, Emitter<GroupChatState> emit) async {
    try {
      final session = await _storage.getGroupChatSession(event.groupId);
      if (session == null) return;
      final updated = session.copyWith(
        activationStrategy: event.activationStrategy ?? session.activationStrategy,
        generationMode: event.generationMode ?? session.generationMode,
        allowSelfResponses: event.allowSelfResponses ?? session.allowSelfResponses,
        disabledMemberIds: event.disabledMemberIds ?? session.disabledMemberIds,
        autoModeDelay: event.autoModeDelay ?? session.autoModeDelay,
        autoModeEnabled: event.autoModeEnabled ?? session.autoModeEnabled,
        updatedAt: DateTime.now(),
      );
      await _storage.saveGroupChatSession(updated);
      _groupDelays[event.groupId] = updated.autoModeDelay;
      if (event.autoModeEnabled != null) {
        configureAutoMode(event.groupId, updated.autoModeEnabled, updated.autoModeDelay);
      }
      final sessions = await _storage.getGroupChatSessions('local_user');
      emit(GroupChatSessionsLoaded(sessions));
    } catch (e) {
      LogService.instance.e('GroupChat', '_onUpdateConfig failed: $e');
      emit(GroupChatError(e.toString()));
    }
  }

  Future<void> _onCreateBranch(
      GroupChatCreateBranch event, Emitter<GroupChatState> emit) async {
    final branch = await _storage.createGroupChatBranch(event.groupId, event.name);
    await _switchBranchInternal(event.groupId, branch.branchId);
    emit(GroupChatMessagesLoaded(
        event.groupId, await _storage.getGroupChatMessages(event.groupId, chatId: branch.branchId)));
  }

  Future<void> _onSwitchBranch(
      GroupChatSwitchBranch event, Emitter<GroupChatState> emit) async {
    await _switchBranchInternal(event.groupId, event.chatId);
    emit(GroupChatMessagesLoaded(
        event.groupId, await _storage.getGroupChatMessages(event.groupId, chatId: event.chatId)));
  }

  Future<void> _switchBranchInternal(String groupId, String chatId) async {
    final session = await _storage.getGroupChatSession(groupId);
    if (session == null) return;
    await _storage.saveGroupChatSession(
        session.copyWith(chatId: chatId, updatedAt: DateTime.now()));
  }

  Future<void> _onDeleteBranch(
      GroupChatDeleteBranch event, Emitter<GroupChatState> emit) async {
    final session = await _storage.getGroupChatSession(event.groupId);
    if (session == null) return;
    await _storage.deleteGroupChatBranch(event.groupId, event.chatId);
    if (session.chatId == event.chatId) {
      final branches = await _storage.getGroupChatBranches(event.groupId);
      final fallback = branches.isNotEmpty
          ? branches.first.branchId
          : await _ensureDefaultBranch(event.groupId);
      await _switchBranchInternal(event.groupId, fallback);
      emit(GroupChatMessagesLoaded(
          event.groupId, await _storage.getGroupChatMessages(event.groupId, chatId: fallback)));
    }
  }

  Future<String> _ensureDefaultBranch(String groupId) async {
    final branch = await _storage.createGroupChatBranch(groupId, '默认聊天');
    return branch.branchId;
  }
```
注册进 switch(event)：`case GroupChatUpdateConfig: return _onUpdateConfig(event, emit);` 等。

- [ ] **Step 4: 创建群默认配置**

`group_chat_create_screen.dart` 创建群时 copyWith 里 chatId 默认=群 id（GroupChatSession 构造已兜底 `chatId = chatId ?? id`，无需改；但创建群时也应建默认分支——在 Create 事件处理处或创建成功后调 `createGroupChatBranch` 已被 v65 迁移覆盖，新建群需要在 bloc `_onCreate` 中补建分支）。在 `_onCreate` 成功保存 session 后加：
```dart
      await _storage.createGroupChatBranch(session.id, '默认聊天');
```

- [ ] **Step 5: analyze**

Run: `flutter analyze lib/screens/group_chat/ lib/blocs/group_chat/`
Expected: 无新增 error

- [ ] **Step 6: Commit**

```bash
git add lib/screens/group_chat/ lib/blocs/group_chat/
git commit -m "feat: 群设置面板（策略/模式/禁言/自动接话）+ 聊天记录管理 UI"
```

---

### Task 9: 消息发送/加载接入 chatId 维度 + 收尾

**Files:**
- Modify: `lib/blocs/group_chat/group_chat_bloc.dart`（_onSendMessage/_onLoadMessages 查询补 chatId）
- Modify: `lib/screens/group_chat/group_chat_detail_screen.dart`（禁言成员管理入口，若未在 Task 8 完成）

- [ ] **Step 1: _onSendMessage 落库带 chatId**

读 `_onSendMessage`（约 100-165 行）后：`saveGroupChatMessage` 与 `getGroupChatMessages` 调用处补 `chatId: session.chatId`；`_onLoadMessages` 查询补 `chatId`。

- [ ] **Step 2: 禁言成员管理**

设置面板加"禁言成员"入口（多选成员）：
```dart
            ListTile(
              title: const Text('禁言成员'),
              subtitle: Text((_session?.disabledMemberIds ?? []).isEmpty
                  ? '无'
                  : (_session!.disabledMemberIds.length.toString()) + ' 人被禁言'),
              onTap: _showMuteMembersPicker,
            ),
```
```dart
  void _showMuteMembersPicker() {
    final session = _session;
    if (session == null) return;
    final disabled = Set<String>.from(session.disabledMemberIds);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('禁言成员'),
        content: FutureBuilder<List<AICharacter>>(
          future: _loadMemberCharacters(session),
          builder: (ctx, snap) {
            final chars = snap.data ?? [];
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: chars.map((c) {
                  return CheckboxListTile(
                    title: Text(c.name),
                    value: disabled.contains(c.id),
                    onChanged: (v) {
                      setState(() {
                        v == true ? disabled.add(c.id) : disabled.remove(c.id);
                      });
                    },
                  );
                }).toList(),
              ),
            );
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () {
              widget.bloc.add(GroupChatUpdateConfig(
                groupId: widget.groupId,
                disabledMemberIds: disabled.toList(),
              ));
              Navigator.pop(ctx);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Future<List<AICharacter>> _loadMemberCharacters(GroupChatSession session) async {
    final list = <AICharacter>[];
    for (final id in session.aiCharacterIds) {
      final c = await _storage.getAICharacter(id);
      if (c != null) list.add(c);
    }
    return list;
  }
```
（`_storage` 若 detail screen 未持有，从 `widget.bloc` 所在作用域取——按现有代码的依赖获取方式；若确实没有，则在 screen 构造传入或通过 bloc state 拿成员列表。）

- [ ] **Step 3: 全量测试 + 打包**

Run: `flutter analyze`
Run: `flutter test test/group_chat_speaker_test.dart test/group_chat_prompts_test.dart test/group_chat_bloc_engine_test.dart test/group_chat_session_config_test.dart test/group_chat_branch_model_test.dart test/ai_character_talkativeness_test.dart`
Expected: 全 PASS；analyze 无新增 error
Run: `flutter build apk --debug --target-platform android-arm64`
Expected: BUILD SUCCESSFUL

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: 群聊消息 chatId 维度接入 + 禁言成员管理 + 全量验证"
```

---

## 自检清单（Self-Review）

**Spec 覆盖：**
- ST 4 策略（NATURAL/LIST/POOLED/MANUAL）→ Task 5 ✅
- ST 3 生成模式（SWAP/APPEND/APPEND_DISABLED）→ Task 7（_generateAIReplies 分支，APPEND_DISABLED 由 disabledMemberIds 天然覆盖）✅
- talkativeness → Task 2 + Task 5 ✅
- 禁言 → Task 3/5/9 ✅
- 允自答 → Task 3/5 ✅
- 自动接话轮询 → Task 7 ✅
- 多聊天记录 → Task 1/4/8 ✅
- nudge/成员名单/`名字: 内容` 格式 → Task 6/7 ✅
- 新群聊 first_mes 开场 → 现有 `_triggerAIReply` 流程保留（ST 新群聊插入成员 first_mes 为可选增强，Solace 现有开场白机制保留）✅

**类型一致性：** `GroupActivationStrategy`/`GroupGenerationMode` 在 session 模型定义，speaker/prompts/bloc/UI 统一引用；`SpeakerContext` 字段名与测试一致；`buildGroupIntroPrompt`/`buildGroupNudge`/`formatGroupMessage`/`buildCombinedCard`/`CombinedCard` 在 Task 6 定义、Task 7 使用。

**已知执行注意：**
1. `_onSendMessage`/`_onLoadMessages`/`_onCreate` 的具体行号以实际文件为准，编辑前先 Read 对应段落。
2. `GroupChatSession` 构造 `chatId` 用 `String? chatId` 参数 + `chatId = chatId ?? id` 初始化列表兜底。
3. `getGroupChatMessages` 原实现可能含 JSON 兼容读取（`_legacy` 数据表），编辑时保留原分支，仅在 query 处加 chatId 过滤。
4. detail screen 的 `_storage`/`_session` 依赖按现有代码注入方式处理；若 screen 无 storage 引用，分支列表改用 state 驱动。
5. 测试中固定 `Random(42)` 保证确定性；POOLED"全部说过"断言 `isNot('c3')` 无 flaky。
6. 存量 8 个失败测试（intimacy/config/refusal 常量断言过时）与本次无关，不修。
