# Solace — 项目认知（AGENTS.md）

> 给后续会话/代理用的项目地图。改代码前先读这里。
> 最后整理：2026-09-14

## 这是什么

**Solace**：Flutter 写的 **AI 陪伴应用**（不是游戏反外挂工具）。

- 多角色聊天 + 情感记忆引擎 + 人生模拟 + 微信 Bot + 语音通话
- **隐私优先**：数据全在本地 SQLite（`solace.db`），不上传用户数据
- **只支持 Android**（`android/` 是唯一平台目录；无 ios/linux/macos/windows）
- 当前版本：`20.0.0+20000`（20.0.0 维护向大版本；Roadmap「共生」主线另计）

## 环境（本机 Windows · 2026-09-14 已配好）

| 工具 | 路径 / 版本 |
|------|-------------|
| Flutter | `E:\flutter` · **3.47.4 stable** · Dart 3.13.3 |
| Git | `E:\flutter\bin\mingit\cmd\git.exe`（Flutter 自带 MiniGit 2.15） |
| JDK 17 | `E:\jdk-17.0.20.1+1`（Temurin） |
| Android SDK | `E:\Android\Sdk` · platform 36 · build-tools 36.0.0 · platform-tools |
| cmdline-tools | `E:\cmdline-tools`（junction 至 `Sdk\cmdline-tools\latest`） |
| Node | `E:\Node js\` · v24 |

### 全局环境变量（User 级）

```
JAVA_HOME=E:\jdk-17.0.20.1+1
ANDROID_HOME=E:\Android\Sdk
ANDROID_SDK_ROOT=E:\Android\Sdk
PUB_HOSTED_URL=https://pub.flutter-io.cn
FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
PATH += E:\flutter\bin; E:\flutter\bin\mingit\cmd; E:\jdk-17.0.20.1+1\bin;
        E:\cmdline-tools\bin; E:\Android\Sdk\platform-tools
```

### 国内镜像

| 层 | 配置 |
|----|------|
| Pub / Flutter Storage | 上面两个环境变量 |
| Gradle | `android/gradle/wrapper` 已用腾讯云 |
| Maven | `android/build.gradle` 已用阿里云 + 腾讯云 |
| sqlite3 原生库 | `pubspec.yaml` → `hooks.user_defines.sqlite3.url_pattern` 走 ghproxy |

### 工程健康度（2026-09-14）

- `flutter pub get` ✓（233 依赖）
- `flutter analyze --no-fatal-infos --no-fatal-warnings` ✓ **0 error**
- `flutter test` ✓ **530 / 530 全部通过**
- `.git` 已 `git init`，**尚未 commit**

### 注意

- 本机 LTSC 缺 `ProgramFiles(x86)` 时，跑 test 前先补：
  `${env:ProgramFiles(x86)} = "C:\Program Files (x86)"`
- GitHub 直连不稳，Flutter 自带 git 可用但 `flutter upgrade`/`fetch --tags` 可能超时
- 签名密钥 `android/*.jks` + `key.properties` 已 gitignore，**禁止提交**

## 目录地图

```
Solace/
├── lib/                  # Dart 源码（~400 个 .dart）
│   ├── main.dart         # 入口
│   ├── blocs/            # BLoC 状态（auth/chat/group_chat/memory/moments/novel/shop/theme/virtual_phone/pure_ai/life）
│   ├── config/           # constants / business_rules / wechat_theme / phone_theme ...
│   ├── data/             # 内置角色模板
│   ├── models/           # 60+ 数据模型（含 life/ virtual_phone/）
│   ├── repositories/     # 数据仓库；local_storage_repository.dart 是唯一数据访问点（~140KB，待拆）
│   ├── screens/          # UI 页面（chat/group_chat/phone/wechat/moments/life/settings ...）
│   ├── services/         # 业务引擎（ai_service/memory_engine/emotion_engine/background_service/proactive_*/voice/wechat ...）
│   ├── src/app/          # App 壳：auth_gate / main_shell / solace_app
│   ├── utils/            # 工具
│   └── widgets/          # 可复用组件（wechat/ phone/ moments/ life/ graph/ ...）
├── test/                 # 63 个测试文件（life/ moments/ novel/ shop/ voice/ + 根级单测）
├── android/              # Android 平台 + 签名密钥
├── assets/               # fonts / graph(d3) / phone_icons / stickers / voice
├── docs/                 # 路线图、设计报告、研究笔记
├── scripts/              # 全部脚本（见下）
├── solace/               # Cloudflare Pages 站点 + Flutter Web 构建产物（~27MB）
├── .github/workflows/    # CI：analyze + test
├── pubspec.yaml          # 版本 19.0.1+8304
└── AGENTS.md             # 本文件
```

## 关键服务（改功能先找这里）

| 服务 | 路径 | 职责 |
|------|------|------|
| AIService | `lib/services/ai_service.dart` | Prompt 组装 + 调 AI API |
| MemoryEngine | `lib/services/memory_engine.dart` | 记忆提取/衰减/检索 |
| EmotionEngine | `lib/services/emotion_engine.dart` | 7 情绪 + 强度衰减 |
| BackgroundService | `lib/services/background_service.dart` | 后台调度 / AI 主动消息 |
| LocalStorageRepository | `lib/repositories/local_storage_repository.dart` | **唯一** SQLite 访问点 |
| WeChat Bot | `lib/services/wechat/` | iLink 协议 Bot |
| Voice | `lib/services/voice/` | MiMo TTS + 本地 sherpa-onnx STT/VAD |
| Proactive\* | `lib/services/proactive_*.dart` | AI 主动生活（20.0.0 主线一） |

## 全局模式注入（必须同源）

单一来源：`lib/utils/global_mode_prompt.dart` → `buildGlobalModePromptText`  
存储包装：`LocalStorageRepository.buildGlobalModePrompt`

模式开关：纯AI / 小说 / 刀 / 恋人 / 开放 / **法功能**（`fa_mode_enabled`）

### 已注入的链路

| 链路 | 位置 |
|------|------|
| 单聊 | `prompt_builder.dart` system |
| 群聊 | 经 `AIService.sendMessageStream` → 同上 |
| 纯 AI | `pure_ai_service.dart` |
| 微信 Bot | `wechat_bot_service.dart` |
| 后台主动 | `background_service.dart` |
| 记忆/摘要 | `memory_engine` / `compat_cross` / `history_filter` |
| 人格进化 | `persona_evolution_service.dart` |
| 虚拟手机 | `virtual_phone_generator.dart` |
| 日记 | `diary_helper.dart` / `ai_diary_screen.dart` |
| 小说续写 | `novel_bloc`（法静默块 + 全局 mode） |
| 娱乐游戏 | `game_service._callAI`（2026-09-14 补齐） |
| 角色反思 | `history_filter.generateReflection`（2026-09-14 补齐） |
| 群聊滚动摘要 | `history_filter.generateGroupRollingSummary`（2026-09-14 补齐） |
| 群聊公开事件 | `history_filter.extractGroupPublicEvents`（2026-09-14 补齐） |

### 刻意不注入（非叙事聊天）

- `ex_persona_analyzer`：角色逆向画像 JSON
- `proactive_decision_engine`：工具调用决策
- `announcement_service` / `update_service`：非 LLM
- `mimo_tts_service`：语音合成

### 法功能 · 海外模型策略（2026-09-14）

- `AIConfig.detectModelFamily` → openai / anthropic / google / xai / domestic
- 海外配置 `faOverseasBoost=true`：**推理模型也会**走 `PromptRewriter` 文学档案
- `rewriteFAPrompt(..., family:)` 海外追加：成年自愿 framing、去掉「法功能」实现词、命令式降级
- 非流式 `sendMessage` 检测 `isAIRefusal` 后**软重试一次**（「（继续）场景还在进行…更贴近一点写」）
- **注入完整性**：memory_narrative 3 处、ai_service_adapter 均传 `family`；桥接 `shouldRewriteFa` 与主路径对齐
- 测试：`test/fa_mode_overseas_test.dart`

**刻意不做**：不把 LLMwc4n 等仓库的官网越狱段写进 system。

**新接 LLM 时必须调 `buildGlobalModePrompt`，禁止绕过。**

## 版本号必须同步的 5 处

1. `pubspec.yaml` → `version: x.x.x+xxx`
2. `lib/config/constants.dart` → `AppVersion.version` / `AppVersion.build`
3. `solace/version.json`
4. `solace/_worker.js` → `VERSION_DATA`
5. `solace/*.html` 页脚

一键：`scripts/bump_version.dart`

## 脚本索引（都在 `scripts/`）

| 脚本 | 用途 |
|------|------|
| `phase0_release_1901.bat` | 19.0.1 收尾一键：commit → pub get → analyze → test → build APK → deploy Pages → tag |
| `deploy.sh` | 复制 APK 到 Pages、gzip 分片、wrangler 部署（根目录有 thin wrapper） |
| `do_build.bat` | debug 构建日志 |
| `push-to-github.bat` | **危险**：git init + force push，仅首次建仓用 |
| `setup_mirrors.bat` / `china-mirrors.*` | 国内 pub/gradle 镜像 |
| `bump_version.dart` | 版本号同步 |

## 安全红线

- `android/solace-release.jks` + `android/key.properties`（明文密码）**禁止提交**
  - 已写入 `.gitignore`
- 根目录不要放 `package-lock.json`（无 package.json 时是垃圾）
- `scripts/push-to-github.bat` 会 force push，别当日常发布用

## 当前进度

- **19.0.1**：代码就绪，本机已验证 **analyze 0 error + test 530 全绿**
- **git**：已 `git init`，文件已 stage，**尚未 commit / 未关联远程**
- **20.0.0 路线图**：`docs/roadmap-20.0.0.md`
- 下一步建议：commit → 关联远程 → 跑 `scripts/phase0_release_1901.bat` 出包部署

## 改代码时注意

- 数据库迁移只走 `local_storage_repository.dart` 的 `_onUpgrade`
- `wechat_theme.dart` **不是死代码**（12 个微信皮肤组件还在用）
- 超大文件：`local_storage_repository.dart`（140KB）、`background_service.dart`（90KB）、`group_chat_bloc.dart`（70KB）、部分 screen（chat_settings 97KB）
- 测试用 `flutter test`；CI 要求 `flutter analyze` 0 error

## 文档入口

| 文档 | 内容 |
|------|------|
| `README.md` | 功能、架构、快速开始 |
| `docs/roadmap-20.0.0.md` | 20.0.0 共生路线图 + Phase 0 |
| `docs/project-status-2026-08-25.md` | 19.0.1 暂停点详细分析 |
| `docs/design/20.0.0-mainline-*.md` | 三条主线设计 |
| `docs/research/` | 微信协议 / UI 规范 / 排障 |
