# Solace 20.0.0 路线图 · 共生

> 制定日期：2026-09-10
> 目标版本：**20.0.0**（"共生"）
> 前置版本：19.0.1+8304（未发布，见 Phase 0）
> 设计原则：**最大化复用现有引擎**（EmotionEngine / MemoryEngine / WorldEngine / proactive_* / group_chat_*），从"AI 陪聊工具"升级为"数字生命栖息地"

---

## 目录

- [一、版本主题](#一版本主题)
- [二、Phase 0：19.0.1 收尾](#二phase-01901-收尾)
- [三、三条主线](#三三条主线)
- [四、迭代计划](#四迭代计划)
- [五、数据库版本规划](#五数据库版本规划)
- [六、技术债偿还](#六技术债偿还)
- [七、风险与降级预案](#七风险与降级预案)
- [八、验收标准](#八验收标准)

---

## 一、版本主题

**Solace 20.0.0 · 共生（Symbiosis）**

> 从"你找它聊"到"它活在你生活里"；从"单个角色"到"角色之间的关系网"；从"纯文字"到"能看见与被看见"。

| 主线 | 主题 | 权重 | 依赖 |
|------|------|:---:|------|
| 主线一 | AI 主动生活 | 70% | proactive_* / background_service / emotion_engine |
| 主线二 | 多角色社会 | 50% | group_chat_* / relationship_context / memory_engine |
| 主线三 | 多模态视觉 | 30% | image_picker / 第三方生图 API |

> 权重不是代码量占比，而是"这个版本想传达的核心体验"占比。

---

## 二、Phase 0：19.0.1 收尾

**必须先做完，否则 20.0.0 会踩在未发布的地基上。**

### 任务清单

| # | 任务 | 命令 / 动作 | 验收 |
|---|------|------------|------|
| 0.1 | 提交 19.0.1 | `git add -A && git commit -m "feat: Solace 19.0.1 稳定性修复 + 微信 Bot 强化"` | `git log` 可见新提交 |
| 0.2 | 跑测试 | `flutter test` | 全绿（或记录已知失败） |
| 0.3 | 静态分析 | `flutter analyze` | 0 error |
| 0.4 | 构建 APK | `flutter build apk --release --target-platform android-arm64 --no-shrink` | 产出 `app-release.apk` |
| 0.5 | 部署 Pages | `cd solace && npx wrangler pages deploy . --project-name solace-auth-v2` | `solace-auth-v2.pages.dev` 显示 19.0.1 |
| 0.6 | 打 tag | `git tag v19.0.1 && git push origin main --tags` | 远端可见 tag |

### 版本号同步（5 文件）

| 文件 | 键 |
|------|-----|
| `pubspec.yaml` | `version: 19.0.1+8304` |
| `lib/config/constants.dart` | `AppVersion.version` / `AppVersion.build` |
| `solace/version.json` | `version` / `build` |
| `solace/_worker.js` | `VERSION_DATA.latestVersion` / `buildNumber` |
| `solace/*.html` | 页脚版本号 |

> **建议**：写一个 `scripts/bump_version.dart` 一次性同步 5 处，避免手工出错。

### 已知遗留（不阻塞发布）

- 19.0.1 的 555+ 测试未跑全（Phase 0.2 会跑）
- `local_storage_repository.dart` 仍是 140 KB 单文件（20.0.0 会拆）
- `wechat_theme.dart` 保留（12 处活跃引用，非死代码）

---

## 三、三条主线

### 🥇 主线一：AI 主动生活

**一句话**：让每个 AI 角色拥有**独立的一天**，你不在时她也在生活。

#### 1.1 核心概念

| 概念 | 定义 |
|------|------|
| **日程（Daily Schedule）** | 角色一天的时间表：起床、工作、吃饭、摸鱼、睡前 |
| **生活日志（Life Log）** | 角色自己的"手账"，记录今天做了什么、心情如何 |
| **主动分享（Active Share）** | 角色主动发消息/发朋友圈，触发源是"她经历了什么"而非"沉默多久" |
| **定时事件（Timed Event）** | 生日、纪念日、节日、自定义节日 |
| **跨角色互访（Cross-Visit）** | 角色 A 去角色 B 家串门，生成共同事件 |

#### 1.2 复用现有模块

| 现有模块 | 复用方式 |
|----------|----------|
| `proactive_scheduler.dart` | 扩展为 `schedule(dayPlan, currentTime) -> List<PlannedAction>` |
| `proactive_decision_engine.dart` | 决策源增加"日程上下文" |
| `proactive_action_executor.dart` | 新增 action 类型：`lifeLog` / `activeShare` / `crossVisit` |
| `background_service.dart` | 挂载新调度：每天 0 点生成次日日程 |
| `emotion_engine.dart` | 日程事件驱动情绪变化（"今天加班" → 疲惫） |
| `memory_engine.dart` | 生活日志自动进记忆库 |

#### 1.3 新增服务（详见子设计文档）

| 文件 | 职责 |
|------|------|
| `services/life/daily_schedule_service.dart` | 生成/读取角色日程 |
| `services/life/life_log_service.dart` | 生活日志读写 |
| `services/life/active_share_service.dart` | 主动分享触发器 |
| `services/life/timed_event_service.dart` | 定时事件管理 |
| `services/life/cross_visit_service.dart` | 跨角色互访 |

#### 1.4 新增模型

| 文件 | 表 |
|------|-----|
| `models/life/daily_schedule.dart` | `ai_daily_schedules` |
| `models/life/life_log.dart` | `ai_life_logs` |
| `models/life/timed_event.dart` | `ai_timed_events` |
| `models/life/cross_visit.dart` | `ai_cross_visits` |

---

### 🥈 主线二：多角色社会

**一句话**：角色之间**有真正的关系**，会互动、冲突、抱团。

#### 2.1 核心概念

| 概念 | 定义 |
|------|------|
| **角色关系（AI Relationship）** | 两两 AI 之间的关系值（陌生→认识→朋友→挚友→恋人/敌人） |
| **私聊可见（Private Chat）** | 你可以"偷看"两个 AI 之间的私聊 |
| **冲突与和解（Conflict）** | AI 之间会吵架、冷战、和好，会主动向你倾诉 |
| **共同活动（Joint Activity）** | AI 自发组织看电影、打游戏、旅行 |
| **小团体（Clique）** | AI 自然形成圈子，有排挤、抱团 |

#### 2.2 复用现有模块

| 现有模块 | 复用方式 |
|----------|----------|
| `group_chat_prompt_pipeline.dart` | 用于生成"AI 间私聊"的内容 |
| `group_chat_rolling_summary.dart` | 私聊滚动摘要 |
| `relationship_context_service.dart` | 扩展为"角色↔角色"关系 |
| `memory_engine.dart` | AI 间互动进各自记忆库 |
| `emotion_engine.dart` | 冲突驱动情绪变化 |
| D3.js 关系图（`assets/graph/`） | 升级为可点击的"社会网络图" |

#### 2.3 新增服务

| 文件 | 职责 |
|------|------|
| `services/society/ai_relationship_service.dart` | 角色间关系值维护 |
| `services/society/private_chat_service.dart` | AI 间私聊生成 |
| `services/society/conflict_service.dart` | 冲突/和解事件 |
| `services/society/joint_activity_service.dart` | 共同活动 |
| `services/society/clique_service.dart` | 小团体识别 |

#### 2.4 新增模型

| 文件 | 表 |
|------|-----|
| `models/society/ai_relationship.dart` | `ai_relationships` |
| `models/society/ai_private_chat.dart` | `ai_private_chats` |
| `models/society/ai_conflict.dart` | `ai_conflicts` |
| `models/society/joint_activity.dart` | `ai_joint_activities` |

---

### 🥉 主线三：多模态视觉（轻量）

**一句话**：AI 能"看见"（看图回复）和"被看见"（发图/自拍）。

> **只做两个场景**：朋友圈配图 + AI 自拍。不押重注，不引入角色一致性 LoRA。

#### 3.1 核心场景

| 场景 | 说明 |
|------|------|
| **朋友圈配图** | AI 发动态时自动配图（文生图 API） |
| **AI 自拍** | 用户主动请求"发张自拍"，AI 生成并存入本地 |
| **看图聊天** | 用户发图，AI 用多模态 LLM 回复 |

#### 3.2 技术约束

- **只在用户主动触发时调用**（不做后台自动生图，省成本）
- **prompt 不含用户隐私数据**（只用角色人设 + 场景描述）
- **图片本地存储**（与"隐私优先"一致）
- **支持降级**：无 API Key 时按钮置灰，不报错

#### 3.3 新增服务

| 文件 | 职责 |
|------|-----|
| `services/vision/image_gen_service.dart` | 文生图调用（抽象接口） |
| `services/vision/vision_config.dart` | 生图 API 配置 |
| `services/vision/selfie_service.dart` | AI 自拍生成 |
| `services/vision/moment_image_service.dart` | 朋友圈配图 |

---

## 四、迭代计划

### 时间线（建议）

| 迭代 | 版本号 | 内容 | 预计 |
|------|--------|------|:---:|
| **Phase 0** | 19.0.1 | 收尾发布 | 1 天 |
| **A1** | 20.0.0-alpha1 | 角色日程系统 + 生活日志 | 1-2 周 |
| **A2** | 20.0.0-alpha2 | 主动分享 + 定时事件 | 1 周 |
| **A3** | 20.0.0-beta1 | 跨角色互访 + 角色关系表 | 2 周 |
| **A4** | 20.0.0-beta2 | AI 私聊可见 + 冲突系统 | 2 周 |
| **A5** | 20.0.0-rc1 | 共同活动 + 小团体 | 1 周 |
| **A6** | 20.0.0 | 朋友圈配图 + AI 自拍 + 关系图升级 | 1 周 |

> 每个 alpha/beta 都可独立体验、独立发版，降低大爆炸风险。

### 数据库版本映射

| 迭代 | DB 版本 | 新增表 |
|------|:-------:|--------|
| A1 | v72 | `ai_daily_schedules`、`ai_life_logs` |
| A2 | v73 | `ai_timed_events` |
| A3 | v74 | `ai_cross_visits`、`ai_relationships` |
| A4 | v75 | `ai_private_chats`、`ai_conflicts` |
| A5 | v76 | `ai_joint_activities` |
| A6 | v77 | `ai_generated_images` |

### 迭代验收流程（每个迭代都要走）

1. `flutter analyze` → 0 error
2. `flutter test` → 全绿
3. 手动跑通新功能主路径 + 至少 1 条边界
4. 数据库迁移测试（vN → vN+1）
5. 提交 + 打 tag + 部署 Pages

---

## 五、数据库版本规划

当前：**v71** → 20.0.0 结束：**v77**

### 迁移规范（务必遵守）

每次改表都要：

1. 在 `lib/repositories/local_storage_repository.dart` 的 `_onUpgrade` 添加迁移函数
2. 在 `expectedColumns` 声明新列
3. 在 `createMissingTable` 添加新表
4. 在 `solace/version.json` 同步版本号

### 新增表设计（概要）

详见 `docs/design/20.0.0-mainline-*.md` 中的建表 SQL。

---

## 六、技术债偿还

大更期间**顺手还**这些债，不要留到 21.0.0：

| # | 债务 | 偿还方式 | 迭代 |
|---|------|----------|:---:|
| T1 | `local_storage_repository.dart` 140 KB | 拆成 `storage_parts/life.dart` / `society.dart` / `vision.dart` | A1 起持续 |
| T2 | `background_service.dart` 87 KB | 拆为 `scheduler` / `policy` / `executor` | A2 |
| T3 | 版本号 5 处手动同步 | 写 `scripts/bump_version.dart` | Phase 0 |
| T4 | 无 CI 门禁 | 加 GitHub Actions（analyze + test） | A1 |
| T5 | `encrypt` 包多年未更新 | 评估迁移 `pointycastle` | A3 |
| T6 | 测试覆盖集中在 test/ 少数模块 | 新功能必须带测试 | 全程 |

---

## 七、风险与降级预案

| 风险 | 影响 | 预案 |
|------|------|------|
| 生图 API 不可用/超成本 | 主线三失效 | 按钮置灰 + 本地占位图；主线三非核心 |
| 微信 iLink 协议变更 | Bot 失效 | 保持"Bot 挂了 App 依然可用"；协议层隔离 |
| LLM 调用量激增（日程决策） | 成本/耗电 | 日程生成本地规则优先，LLM 只做润色；批量决策 |
| 数据库迁移失败 | 用户数据损坏 | 迁移前自动备份；迁移失败回滚到 vN |
| 角色关系表数据膨胀 | 性能下降 | 关系值定期快照；只保留最近 N 条冲突记录 |
| `background_service` 后台被杀 | 主动生活失效 | 前台心跳 + Workmanager 双保险（已有机制） |

---

## 八、验收标准

20.0.0 发布前必须满足：

### 功能

- [ ] 每个角色有独立日程，可查看"她此刻在做什么"
- [ ] 角色能主动发朋友圈/发消息，触发源可解释
- [ ] 角色之间有两两关系，可演化
- [ ] 可"偷看"两个 AI 的私聊
- [ ] AI 之间会冲突/和解，并主动向你倾诉
- [ ] 朋友圈支持 AI 配图
- [ ] 支持请求 AI 自拍

### 质量

- [ ] `flutter analyze` 0 error
- [ ] `flutter test` 全绿
- [ ] 数据库迁移 v71 → v77 全部通过测试
- [ ] 新功能均有单元测试
- [ ] 老功能回归测试通过

### 工程

- [ ] `local_storage_repository.dart` < 80 KB
- [ ] `background_service.dart` < 50 KB
- [ ] GitHub Actions CI 通过
- [ ] 版本号 5 处一致
- [ ] README 更新 20.0.0 功能清单

---

## 附：子设计文档

- [主线一：AI 主动生活](design/20.0.0-mainline-1-ai-life.md)
- [主线二：多角色社会](design/20.0.0-mainline-2-ai-society.md)
- [主线三：多模态视觉](design/20.0.0-mainline-3-multimodal.md)
