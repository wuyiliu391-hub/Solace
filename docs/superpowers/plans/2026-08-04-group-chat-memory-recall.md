# 群聊记忆回流到单聊 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让群聊中的公开事件按角色建立可检索记忆，并在单聊话题相关时召回，不相关时不污染单聊上下文。

**Architecture:** 在现有 `social_memories` 之外建立明确的群聊公开事件索引语义，事件按 `characterId + groupId + chatId` 建立可见副本，保留发言人、细节、关键词和原始消息引用。单聊发送前根据当前消息做轻量关键词匹配，只将相关事件注入该角色的单聊记忆上下文；重要事件锁定，普通事件沿用现有热度衰减。

**Tech Stack:** Flutter/Dart, flutter_bloc, sqflite, existing `MemoryEngine`, existing `LocalStorageRepository`, Flutter tests.

---

## 文件边界

- Create: `lib/models/group_public_event_memory.dart` — 群聊公开事件的领域模型和 metadata 编解码。
- Create: `lib/services/group_public_event_memory.dart` — 事件提取结果校验、关键词匹配和召回排序的纯函数。
- Modify: `lib/repositories/local_storage_repository.dart` — 幂等建表、迁移、保存/查询/删除群聊事件索引。
- Modify: `lib/services/memory_engine.dart` — 从群聊事件索引建立角色可见记忆、召回结果并格式化单聊上下文。
- Modify: `lib/services/ai_service.dart` — 增加带角色名和事件字段的群聊公开事件提取 API。
- Modify: `lib/blocs/group_chat/group_chat_bloc.dart` — 在群聊事件提取周期中生成事件，并为每个 AI 成员写入索引。
- Modify: `lib/blocs/chat/chat_bloc.dart` — 单聊发送前按当前消息召回相关群聊事件并合并到现有上下文。
- Test: `test/group_public_event_memory_test.dart` — 纯函数测试。
- Test: `test/local_storage_group_public_event_test.dart` — 存储隔离、覆盖和删除测试。
- Test: `test/group_chat_memory_recall_test.dart` — 群聊提取/索引/召回行为测试。
- Test: `test/chat_group_memory_context_test.dart` — 单聊相关召回和无关不注入测试。

### Task 1: Define the event model and deterministic recall rules

**Files:**
- Create: `lib/models/group_public_event_memory.dart`
- Create: `lib/services/group_public_event_memory.dart`
- Create: `test/group_public_event_memory_test.dart`

- [ ] **Step 1: Write the failing tests**

Add tests for these exact behaviors:

```dart
test('matches a current chat message against event keywords and names', () {
  final event = GroupPublicEventMemory(
    id: 'event-1', characterId: 'char-a', groupId: 'group-1', chatId: 'chat-1',
    content: '用户和阿强约定周末去看展，展览地点尚未确定。',
    keywords: const ['周末', '看展', '阿强'],
    sourceMessageIds: const ['m-1'],
    importance: GroupEventImportance.normal,
    pinned: false,
    weight: 1,
    createdAt: DateTime(2026, 8, 4),
    lastRecalledAt: null,
  );
  expect(eventMatchesQuery(event, '周末和阿强去看展吗'), isTrue);
});

test('unrelated events are excluded and pinned events rank first', () {
  final memories = buildRelevantGroupEventMemories(
    query: '咖啡馆',
    memories: [unrelatedEvent, pinnedCoffeeEvent, normalCoffeeEvent],
    limit: 2,
  );
  expect(memories, [pinnedCoffeeEvent, normalCoffeeEvent]);
});

test('important events are not eligible for decay deletion', () {
  expect(canDecayGroupEvent(importance: GroupEventImportance.important, pinned: true), isFalse);
  expect(canDecayGroupEvent(importance: GroupEventImportance.normal, pinned: false), isTrue);
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/group_public_event_memory_test.dart`

Expected: compilation failure because the model and recall functions do not exist.

- [ ] **Step 3: Implement the minimal model and pure functions**

Implement:

- `GroupEventImportance { normal, important }`.
- `GroupPublicEventMemory` with `fromMap`, `toMap`, and metadata fields for `sourceMessageIds`, `speakerNames`, and `sourceGroupName`.
- `eventMatchesQuery` using case-insensitive token/name matching without an external search dependency.
- `buildRelevantGroupEventMemories` filtering unrelated events, sorting pinned first, then importance, heat, and recency, and applying `limit`.
- `canDecayGroupEvent` returning false for pinned important events.

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/group_public_event_memory_test.dart`

Expected: all tests pass.

### Task 2: Add isolated persistent storage

**Files:**
- Modify: `lib/repositories/local_storage_repository.dart`
- Create: `test/local_storage_group_public_event_test.dart`

- [ ] **Step 1: Write the failing storage tests**

Cover:

```dart
test('same group branch and character replaces the existing event', () async {
  await repository.saveGroupPublicEvent(firstEvent);
  await repository.saveGroupPublicEvent(firstEvent.copyWith(content: '更新后的细节'));
  final events = await repository.getGroupPublicEvents('char-a', groupId: 'group-1', chatId: 'chat-1');
  expect(events, hasLength(1));
  expect(events.single.content, '更新后的细节');
});

test('different branches remain isolated', () async {
  await repository.saveGroupPublicEvent(firstEvent);
  await repository.saveGroupPublicEvent(branchBEvent);
  expect(await repository.getGroupPublicEvents('char-a', groupId: 'group-1', chatId: 'chat-1'), hasLength(1));
  expect(await repository.getGroupPublicEvents('char-a', groupId: 'group-1', chatId: 'chat-2'), hasLength(1));
});

test('deleting a group branch removes only its event index', () async {
  await repository.deleteGroupPublicEvents('group-1', 'chat-1');
  expect(await repository.getGroupPublicEvents('char-a', groupId: 'group-1', chatId: 'chat-1'), isEmpty);
  expect(await repository.getGroupPublicEvents('char-a', groupId: 'group-1', chatId: 'chat-2'), isNotEmpty);
});
```

Use the repository’s existing temporary database setup and do not touch unrelated tables.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/local_storage_group_public_event_test.dart`

Expected: compilation failure because the table and repository methods do not exist.

- [ ] **Step 3: Add the table and repository methods**

Add `group_public_event_memories` with:

- `id TEXT PRIMARY KEY`
- `characterId`, `groupId`, `chatId`, `content`, `keywords`, `sourceMessageIds`, `speakerNames`, `sourceGroupName`
- `importance`, `weight`, `pinned`, `createdAt`, `lastRecalledAt`, `updatedAt`
- unique index on `(id)` and lookup index on `(characterId, groupId, chatId)`

Register it in `expectedColumns`, `createMissingTable`, and the new-install path. Add idempotent migration support so old 17.6.0 databases create it without reset.

Implement:

- `saveGroupPublicEvent`
- `getGroupPublicEvents(characterId, {groupId, chatId, limit})`
- `saveGroupPublicEvents`
- `deleteGroupPublicEvents(groupId, chatId)`
- `deleteGroupPublicEventsForGroup(groupId)`

Use `ConflictAlgorithm.replace` only for the same event id. Do not replace unrelated events from another character or branch.

- [ ] **Step 4: Run the storage tests to verify they pass**

Run: `flutter test test/local_storage_group_public_event_test.dart`

Expected: all storage tests pass and the database remains readable after initialization.

### Task 3: Extract public events and index them for every AI member

**Files:**
- Modify: `lib/services/ai_service.dart`
- Modify: `lib/blocs/group_chat/group_chat_bloc.dart`
- Create: `test/group_chat_memory_recall_test.dart`

- [ ] **Step 1: Write the failing extraction/index tests**

Test that a public extraction result keeps speaker names and source message IDs, and that one event is indexed for every AI member in the session, including when the user spoke to another role.

Expected assertion shape:

```dart
expect(indexedCharacterIds, containsAll(session.aiCharacterIds));
expect(event.speakerNames, containsAll(['用户', '阿强']));
expect(event.sourceMessageIds, contains('message-17'));
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/group_chat_memory_recall_test.dart`

Expected: missing extraction/index API or empty index failure.

- [ ] **Step 3: Implement extraction and indexing**

Add `AIService.extractGroupPublicEvents` that accepts:

- group name and branch id
- existing rolling summary
- newly summarized messages with sender names and IDs

Require the model to emit line-delimited JSON with:

```json
{"content":"...","speakers":["用户","阿强"],"keywords":["..."],"importance":"normal|important","sourceMessageIds":["..."]}
```

Validate JSON, reject empty content, reject unknown importance, deduplicate exact content, and return an empty list on API failure.

In `GroupChatBloc`, after the existing group memory extraction completes, call the event extractor asynchronously. For each event and each `session.aiCharacterIds`, create a `GroupPublicEventMemory` with the same public content and character-specific index. Mark only `important` events as pinned. Preserve `chatId` and source IDs.

Do not block or fail the current AI response if extraction fails.

- [ ] **Step 4: Run the extraction/index tests to verify they pass**

Run: `flutter test test/group_chat_memory_recall_test.dart`

Expected: all tests pass.

### Task 4: Add related-event recall to MemoryEngine and single chat

**Files:**
- Modify: `lib/services/memory_engine.dart`
- Modify: `lib/blocs/chat/chat_bloc.dart`
- Create: `test/chat_group_memory_context_test.dart`

- [ ] **Step 1: Write the failing recall/context tests**

Test these behaviors:

```dart
test('related group events are included in single-chat context', () async {
  final context = await memoryEngine.buildRelatedGroupMemoryContext(
    characterId: 'char-a',
    userId: 'local_user',
    query: '周末和阿强去看展吗',
  );
  expect(context, contains('群聊中的相关记忆'));
  expect(context, contains('周末去看展'));
});

test('unrelated group events are omitted from single-chat context', () async {
  final context = await memoryEngine.buildRelatedGroupMemoryContext(
    characterId: 'char-a',
    userId: 'local_user',
    query: '今天午饭吃什么',
  );
  expect(context, isEmpty);
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/chat_group_memory_context_test.dart`

Expected: missing `buildRelatedGroupMemoryContext` failure.

- [ ] **Step 3: Implement related recall**

Add `MemoryEngine.buildRelatedGroupMemoryContext`:

- query the current character’s public-event index;
- use the pure matching/ranking helper;
- return an empty string for no match;
- include at most 3 events and truncate each event to a safe prompt length;
- call the existing recall-strengthening path for returned non-pinned events;
- format group name, speaker details, event content, and unresolved details without exposing database metadata.

In `_onSendMessage` in `ChatBloc`, call this method after the current user message and character are known. Merge the returned block with the existing `internalSystemContext` using `_mergeInternalSystemContext`. Do not alter normal memory limits or inject the block when it is empty.

- [ ] **Step 4: Run the context tests to verify they pass**

Run: `flutter test test/chat_group_memory_context_test.dart`

Expected: related content is present and unrelated content is absent.

### Task 5: Clean up lifecycle and verify the full feature

**Files:**
- Modify: `lib/repositories/local_storage_repository.dart`
- Modify: `lib/blocs/group_chat/group_chat_bloc.dart`
- Modify: `lib/screens/group_chat/group_chat_detail_screen.dart` only if branch deletion does not already dispatch repository cleanup
- Test: `test/group_chat_memory_recall_test.dart`

- [ ] **Step 1: Add lifecycle tests**

Verify deleting a group or branch removes its public-event indexes, while events from other groups/branches remain.

- [ ] **Step 2: Implement lifecycle cleanup**

Call `deleteGroupPublicEventsForGroup` from group deletion and `deleteGroupPublicEvents(groupId, branchId)` from branch deletion. Keep pinned events only when the group/branch still exists; deleting the source context deletes its derived indexes.

- [ ] **Step 3: Run focused tests**

Run:

```text
flutter test test/group_public_event_memory_test.dart test/local_storage_group_public_event_test.dart test/group_chat_memory_recall_test.dart test/chat_group_memory_context_test.dart
```

Expected: all new tests pass.

- [ ] **Step 4: Run existing group and chat tests**

Run:

```text
flutter test test/group_chat_rolling_summary_test.dart test/group_chat_prompts_test.dart test/group_chat_speaker_test.dart test/group_chat_memory_test.dart test/group_chat_memory_eh_test.dart
```

Expected: all pass, except any already documented pre-existing failure in the current worktree.

- [ ] **Step 5: Run static analysis**

Run:

```text
flutter analyze lib/models/group_public_event_memory.dart lib/services/group_public_event_memory.dart lib/repositories/local_storage_repository.dart lib/services/memory_engine.dart lib/services/ai_service.dart lib/blocs/group_chat/group_chat_bloc.dart lib/blocs/chat/chat_bloc.dart
```

Expected: no new analyzer errors. Existing info/warning diagnostics may remain.

- [ ] **Step 6: Review the diff and confirm no APK build**

Run: `git diff --check` and `git status --short`

Confirm that the feature is implemented and verified without building or installing an APK unless explicitly requested.
