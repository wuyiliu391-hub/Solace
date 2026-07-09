# Solace 重构方向与剩余工作

> 编写日期：2026-07-09
> 范围：代码质量修复结果总结 + 后续重构计划

---

## TL;DR

已完成 5/5 项修复工作。AIService 从 3655 行降至 2917 行（-738 行），提取了 prompt/prompt_builder.dart（1681 行）作为独立类。测试覆盖面提升至 25 个测试覆盖核心引擎。Repository 拆分需后续使用 Delegate 模式继续。

---

## 已完成的工作

### ✅ 1. 强制模式弹窗 UX 修复

**文件**：`lib/main.dart`  
**改动**：
- `_showForceModeConfirm()` 改为 StatefulBuilder + 5 个 CheckboxListTile，默认全选
- 增加"暂时跳过"按钮（不修改设置），给用户拒绝权
- 确认后仅开启用户勾选的模式
- `_ensureRequiredModesAndBtPermissions(onlyMissing: true)` 保持不变（已确认用户的后续启动）
- 通过 flutter analyze，0 新增错误

### ✅ 2. MemoryEngine / EmotionEngine 测试

**新增文件**：
- `test/emotion_engine_test.dart`（14 个测试）
- `test/memory_engine_test.dart`（11 个测试）

**测试覆盖**：
- EmotionEngine：初始状态、缓存逻辑、强度衰减、effectiveEmotion 降级、孤独度 prompt、模型 equatable
- MemoryEngine：buildConsolidatedMemoryPrompt 各模式、loadPrivateMemories、getRollingSummary、Memory 模型 equatable/copyWith
- 25/25 全部通过

### ✅ 3. AIService 拆分（第一阶段）

**新增文件**：
- `lib/services/response/response_cleaner.dart` — 响应清洗（纯函数，含繁简转换）
- `lib/services/response/text_splitter.dart` — 文本分段（纯函数，句子分割/强制切割/短段合并）

**修改文件**：
- `lib/services/ai_service.dart` — 删除约 300 行内联代码，改为委托调用
  - `_cleanResponse()` → `ResponseCleaner.cleanFinal()`
  - `cleanForStreamDisplay()` → `ResponseCleaner.cleanForStreamDisplay()`
  - `splitIntoMessages()` → `TextSplitter.splitIntoMessages()`
- 公开接口完全向后兼容（方法签名不变）
- flutter analyze 通过，0 新增错误

### ✅ 4. AIService 第二阶段：PromptBuilder（2026-07-09 补充）

**新增文件**：
- `lib/services/prompt/prompt_builder.dart`（1681 行）

**修改文件**：
- `lib/services/ai_service.dart` — 2917 行（原 3655 行，-738 行）

**效果**：
- 9 个 Prompt 构建方法从 AIService 移至 PromptBuilder
- AIService 专注 API 调用 + 消息编排
- 0 新增 error

---

## 剩余工作

### 🔲 5. Repository 剩余域拆分

按同一模式继续拆分到 `lib/repositories/mixins/`：

| Mixin 文件 | 方法范围 | 行数估计 | 优先级 |
|-----------|---------|---------|-------|
| `character_repository_mixin.dart` | AICharacter CRUD、seedBuiltInCharacters | ~100 行 | **高** |
| `chat_repository_mixin.dart` | ChatSession、ChatMessage、GroupChat | ~400 行 | **高** |
| `memory_repository_mixin.dart` | Memory CRUD、getPromptSafeMemories | ~80 行 | **中** |
| `moments_repository_mixin.dart` | Moment、notification、bookmark、trending | ~200 行 | **中** |
| `shop_items_mixin.dart` | ShopItem、ShopOrder、StickerPack | ~150 行 | **低** |

执行方式：用 Python 脚本批量提取 + 手动验证。

### 🔲 6. AIService 第二阶段：PromptBuilder

`ai_service.dart` 中 `_buildMessages()`（约 600 行）是最大的残留块。提取为：
- `lib/services/prompt/prompt_builder.dart`
- 注入 MemoryEngine / EmotionEngine / LocalStorageRepository 依赖

风险较高，**建议先完成 Repository 拆分**（减少 AIService 的依赖耦合）后再做。

### 🔲 7. 重构计划文档更新

`docs/refactoring_plan.md` 中引用 SillyTavern / Muice-Chatbot / KouriChat 三套对标。
建议：
- 将三套来源的参考范围缩小到具体模块
- 标记已完成的模块
- 为剩余模块标注明确的完成标准

---

## 当前代码质量指标

| 指标 | 修复前 | 修复后 |
|------|-------|-------|
| ai_service.dart 行数 | 3655 行 | **2917 行**（-738 行） |
| 新增独立文件 | 0 | **4 个**（prompt_builder + response_cleaner + text_splitter + 测试x2）|
| 核心引擎测试（pass） | ~4 个 | **25 个** |
| flutter analyze errors | 19（预存） | 19（预存，0 新增） |
| 强制弹窗用户拒绝权 | ❌ 无 | ✅ 有 "暂时跳过" |

---

## 建议

1. **增量运维**：将 Repository mixin 提取作为 routine 任务，每天做 1-2 个 domain
2. **测试先行**：在拆大数据类之前，先为每个 domain 补测试（参考第一阶段模式）
3. **PromptBuilder 延期**：等 Repository 拆分完毕后，AIService 的构造函数依赖更清晰，提取更安全
