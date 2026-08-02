# 全局模式设置设计 — 调色板下线 + 模式全站生效

**日期:** 2026-08-02
**状态:** 待审阅
**范围:** 删除聊天页调色板（模式面板）；模式开关迁入「我页面 → 设置」；小说模式彻底全局化；所有 AI 生成链路接入完整模式机制（重点：法模式 MSFW）。

## 目标

1. 聊天页右上角调色板入口（含悬浮球坐标 prefs）彻底下线。
2. 全部 7 个模式开关（纯AI视角 / 小说模式 / 恋人模式 / 开放模式 / 法功能 / 刀模式 / 自动写日记）+ 小说对白颜色迁入设置页，**全局唯一生效**。
3. 小说模式去掉会话级三态（session.novelMode 废弃读写），全局开关一统。
4. 所有 AI 生成链路（单聊 / 群聊 / 日记 / 朋友圈后台 / 记忆库 / 进化 reason）接入完整模式机制，法模式（MSFW）全站生效。

## 现状（已核实）

| 链路 | AI 生成点 | 现有模式支持 |
|---|---|---|
| 单聊 | chat_bloc → ai_service.sendMessageStream | 完整 6 机制（注入/清洗/改写/场景设定/NSFW跳过/亲密度） |
| 群聊 | group_chat_bloc:393,523 → 同一 sendMessageStream | 仅继承 prompt 注入（scope 写死「单聊」）；无 ContentFilter |
| 日记（自动） | diary_helper:100 直接 HTTP | 仅 4 模式注入（法/刀/恋人/开放，缺小说/纯AI）；无清洗/改写 |
| 日记（手动页） | ai_diary_screen `_generateDiary` → `_callAI` 直接 HTTP(163) | 仅 4 模式注入（+BT，缺小说/纯AI）；无清洗/改写 |
| 朋友圈后台 | background_service:1493,2010,2200 | 独立实现 `_buildBackgroundGlobalModePrompt`(137-181) + `_cleanContent`(183)，与主实现两套文本 |
| 记忆库 | memory_engine:997,2324、ai_service:2694 | 无任何模式 |
| 进化 reason | persona_evolution_service:263 → HTTP(923) | 无任何模式 |
| 纯展示页 | 成长轨迹 / 关系温度 / 收藏消息 / 聊天记录管理 / AI动态聚合 | 无 AI 生成点，不涉及 |

关键事实：
- 存储层方法齐全（`LocalStorageRepository` setter/getter + `modeSettingsNotifier` 通知），UI 迁移不动存储。
- 模式 prompt 文本主线 `buildGlobalModePrompt`（local_storage_repository.dart:4453-4500）；后台服务是**独立平行实现**，需单一来源化。
- `PromptRewriter.rewriteFAPrompt`（lib/services/prompt_rewriter.dart:13）与 `ContentFilter.check`（lib/utils/content_filter.dart:11）都是独立文件，可复用。
- 法模式 NSFW 检测跳过现状：chat_bloc.dart:2012-2016（`faModeActive ? ContentFilterResult() : ContentFilter.check()`），全项目唯一过滤点。
- `setFaVerified` 无任何读取方（死标记），面板开法功能时同步写；设置页保持同样行为。

## 设计决策（用户已确认）

1. **入口**：设置页内新增「模式与颜色」区块（不做独立子页面）。
2. **小说模式**：彻底全局化——删会话级三态读写，设置页开关 = 全局唯一。
3. **年龄锁**：恋人 / 开放 / 法三个开关保留 18+ 锁（`getUserAge() < 18` 显示锁图标）。
4. **法模式**：完整复制单聊机制到所有生成链路。
5. **对白颜色**：消费点维持现状（单聊气泡 + 故事书），颜色设置迁入设置页为全局配置。

## 分节设计

### A. 设置页「模式与颜色」区块（settings_screen.dart）

- 位置：插在「AI 设置」区块之后（AI 输出风格之前），与 AI 相关区块聚集。
- 内容（自上而下）：
  1. 区块标题「模式与颜色」
  2. 开关（复用现有 SwitchListTile 风格）：
     - 纯AI视角 → `setPureAiMode`
     - 小说模式 → `setChatStyleMode`
     - 恋人模式 → `setLoverMode`（18+ 锁）
     - 开放模式 → `setOpenMode`（18+ 锁）
     - 法功能 → `setFaMode` + 同步 `setFaVerified`（18+ 锁）
     - 刀模式 → `setDaoMode`
     - 自动写日记 → `setAutoDiaryEnabled`
  3. 小说对白颜色行（**仅小说模式开启时显示**，与旧面板行为一致）：8 色圆点（沿用 `_kPresetColors` 色值），当前色描边高亮，点击 → `setNovelDialogueColor`。
- 年龄锁交互：`getUserAge()` 缺失或 <18 时，三个锁定开关显示锁图标，点击弹 SnackBar/提示不可用，不切换状态。

### B. 聊天页调色板下线（chat_detail_screen.dart + 删组件）

删除：
- `_modePanelVisible` 声明(127)、相关字段(128-129)、dispose(1864)
- 调色板图标按钮(485-494)
- `ModeControlMiniPanel` 挂载(1297-1301)
- `_toggleSessionNovelMode`(173-185)
- 整个文件 `lib/widgets/mode_control_mini_panel.dart`

修改：
- `_isNovelModeEnabled`(159-167)：删除三态判定，改为 `_modeSettingsStorage.isChatStyleNovelModeEnabled()`（方法名保留，调用点 1299/3489/4193 不动）。
- 保留 `modeSettingsNotifier` 监听(1554-1561)：全局模式变化仍需重建气泡（小说模式开关直接影响气泡样式与对白颜色）。
- `LocalStorageRepository`：删 `setModeControlBallOffset`/`getModeControlBallOffset`(4438-4451) 及 `PrefKeys` 对应 key（实现前 grep 确认无其他引用）。

### C. 小说模式彻底全局化

| 位置 | 现状 | 改动 |
|---|---|---|
| chat_session.dart | novelMode 字段 + copyWith/toMap/fromMap | **保留定义与 DB 列，删除全部读写点**（不触发 DB 迁移） |
| chat_bloc.dart:1041-1044 | `_aiService.setNovelModeOverride(...)` | 删除 |
| chat_bloc.dart:1175 | 会话三态判定 | 改 `_storage.isChatStyleNovelModeEnabled()` |
| ai_service.dart:121,128-134 | `_novelModeOverride` / `setNovelModeOverride` | 删除 override，`_isNovelModeEnabled()` 直接读全局 |
| voice_call_screen.dart:671-672,748 | novel 判定 | 改读全局（实现时全库 grep novelMode 兜底） |
| background_service.dart:132-134 | 已读全局 | 不动 |

### D. 生成链路模式接入矩阵

机制缩写：**P** = 模式 prompt 注入（buildGlobalModePrompt）；**W** = 输出清洗 faMode 保留括号动作；**R** = PromptRewriter.rewriteFAPrompt（非推理模型语义伪装）；**S** = ContentFilter 法模式跳过；**D** = FA+小说场景设定（仅对话场景，ai_service 管道内部）。

| 链路 | P | W | R | S | D | 改动 |
|---|---|---|---|---|---|---|
| 单聊 | ✅ | ✅ | ✅ | ✅ | ✅ | 无 |
| 群聊 | ✅(继承) | ✅(继承) | ✅(继承) | ❌ | ✅(继承) | 补 S：用户发送路径加 ContentFilter（法模式跳过，复用 chat_bloc:2012-2016 模式）；群聊走 sendMessageStream 自动继承 W/R/D |
| 日记（自动，diary_helper:100） | ⚠️ 4 模式 | ❌ | ❌ | 不适用 | 不适用 | P 补全（改调 buildGlobalModePrompt）+ W（输出清洗 faMode 保留括号）+ R |
| 日记（手动页，ai_diary_screen:163） | ⚠️ 4 模式+BT | ❌ | ❌ | 不适用 | 不适用 | 同上 P 补全 + W + R |
| 朋友圈后台 | ✅(独立版) | ⚠️ 需 faMode 分支 | ❌ | 不适用 | 不适用 | P 单一来源化（见 E）+ W 改 `_cleanContent`(183) + R |
| 记忆库 | ❌ | ❌ | ❌ | 不适用 | 不适用 | memory_engine:997,2324 与 ai_service:2694 三处：P + W + R |
| 进化 reason | ❌ | ❌ | ❌ | 不适用 | 不适用 | persona_evolution_service:263 → HTTP 前 P + R，输出 W |

实现要点：
- P：直接 HTTP 链路在 system prompt 拼接处插入 `storage.buildGlobalModePrompt(scope: ...)`（diary_helper 有 storage 参数；memory_engine:96、persona_evolution:23 均持有 `_storage`）。
- R：非推理模型判定逻辑复用 ai_service 现有做法（实现时确认判定函数）；调用 `PromptRewriter().rewriteFAPrompt(prompt, characterName: ...)`。
- W：faMode 开启时清洗器保留 `*...*`、`[...]`、`(英文)` 括号动作。单聊清洗逻辑在 ai_service 管道内部；直接 HTTP 链路各自加轻量清洗（faMode 分支）。记忆总结/进化 reason 文本同样保留括号动作。
- S（群聊）：用户发送消息路径插入 `ContentFilter.check`，法模式/开放模式跳过（对齐单聊现状——实现时核对单聊是否开放模式也跳过，保持一致）。

### E. background_service 模式文本单一来源化

- 新增纯函数 `lib/utils/global_mode_prompt.dart`：`String buildGlobalModePromptText({required bool pureAiMode, required bool novelMode, required bool loverMode, required bool openMode, required bool faMode, required bool daoMode, String? scope})`——把 repository:4453-4500 的文本逻辑原样提取（纯AI 立即返回空串）。
- `LocalStorageRepository.buildGlobalModePrompt` 改为内部调用该纯函数（签名兼容，调用方零改动）。
- `background_service._buildBackgroundGlobalModePrompt`(137-181) 改为读 prefs 后调用同一纯函数（删除自拼接逻辑，保证文本永远一致）。
- 自动写日记是开关闸门（diary_helper:24）非风格 prompt，两处都不涉及。

### F. 范围外与备注

- **范围外（用户未列、不接入）**：`game_service.dart:313` `_callAI`（抓娃娃等小游戏 15-35 字台词生成，低风险短台词）；`novel_bloc`（故事书章节生成，已有 FA 改写 198-215）。如需接入另行确认。
- `ai_service_adapter.dart`（桥接层）：novel/FA 判定全部直接读全局 storage（142-143,183,263,538），**零改动**，全局化后自动正确。
- 删：mode_control_mini_panel.dart、聊天页调色板 UI、悬浮球坐标 prefs 方法、会话级 novelMode 读写。
- 保留：`chat_session.novelMode` 字段与 DB 列（避免迁移，代码不再读写，标注未来清理项）。
- 备注（不在本任务范围）：`AIService.generateReflection`(ai_service:2361) 全库无调用方（疑似废弃）；`isFaVerified` 无读取方（保持设置页同步写现状）。

## 测试策略

1. 纯函数单测：`buildGlobalModePromptText` 各模式组合 → prompt 包含/不含对应分支；纯AI → 空串。
2. 设置页区块 widget 测试：7 开关渲染；年龄锁（<18 锁图标、≥18 可切换）；颜色行仅小说模式开启时显示。
3. chat_bloc 测试：novelMode 判定改全局后现有用例回归修正。
4. 群聊 S：法模式跳过过滤 / 非法模式拉黑。
5. 日记 / 记忆库 / 进化：P 注入断言（prompt 含模式分支）。
6. 全量 `flutter analyze` 0 新增 error；相关测试全绿；无新增 withOpacity / 硬编码色。

## 风险

- 群聊引入 ContentFilter 是行为变化：非法模式下的 NSFW 用户消息会被拉黑（法模式跳过）——符合「全站适配」意图。
- scope 参数语义：提取纯函数时保持原文本输出逐字不变，避免影响单聊行为。
- DB 零迁移：novelMode 列残留无风险。
- 设置页区块插入位置不影响现有功能（纯新增 + 开关状态读 prefs）。
