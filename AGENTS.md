# Solace — AGENTS.md

> 给后续会话/代理的项目地图。**改代码前先读这里。**
> 最后核对：2026-09-30（对照 `main` @ `4a150ac`、CI Flutter 3.47.5 / Dart 3.13.3）

## 协作约定

- **一律用中文回复和描述**，包括提交信息、注释、文档、commit body。
  代码标识符仍用英文（项目惯例：注释中文、标识符英文）。
- 提交信息格式：`类型: 简短描述`，类型取 `feat` / `fix` / `refactor` / `docs` / `test` / `chore` / `ci`。

## 这是什么

Flutter 写的 **AI 陪伴应用**（Android 单平台）。多角色聊天 + 情感记忆引擎 + 人生模拟 + 微信 Bot + 语音通话。
**隐私优先**：用户数据全在本机 SQLite（`solace.db`），不上传。
当前版本 `20.0.0+20000`，`main` 已与 `origin/main` 同步（`origin` = `wuyiliu391-hub/Solace`）。

## ⚠️ 本机没有 Flutter / JDK / Android SDK —— 唯一校验途径是 GitHub Actions

**这台开发机上 `flutter`、`dart`、`java`、`adb`、`sdkmanager`、`bash` 全部不存在**（已实测）。
本机只有 `git` / `gh` / `node` / `python`。

因此：

- **不要**尝试 `flutter analyze` / `flutter test` / `flutter build` —— 命令不存在，会浪费一轮。
- 所有编译/测试校验**只能**通过推送后由 `.github/workflows/ci.yml` 在 Ubuntu runner 上跑。
- **一次改动 = 一次 CI 运行**，所以提交前必须靠阅读代码自检；`concurrency` 已开
  `cancel-in-progress`，连推会自动取消旧运行，不会白烧配额。
- 查历史失败原因用 `gh`（已登录 `wuyiliu391-hub`）：
  ```bash
  gh run list --limit 5
  gh run view <id> --log-failed          # 只看失败步骤
  gh run view <id> --log | findstr /C:"[E]"   # 定位失败用例
  ```
- 仓库根目录的 `.dart_tool/` 是**旧机器的陈旧产物**（`package_config.json` 全指向
  `file:///E:/flutter/...`），本地既不能跑也没有参考价值。
- 需要真机验证时只能出 APK 走 `apk.yml`（workflow_dispatch），再 `adb install` —— 但本机无 `adb`。

### CI 缓存策略（2026-09-30 重做并已验证）

之前 **0 个缓存**：3 次 CI 全红，cache 的 post-step 全是 `conclusion=skipped`，
所以每次都是冷启动（Flutter SDK + 200+ 个包重新下载，约 2.5 分钟）。
**测试转绿是缓存能生效的前提** —— 缓存是在 job 的 post 阶段落盘的。

修复后首次绿跑实测：**517 tests passed**，两个缓存均已落盘：

| 缓存 key | 体积 |
|----------|------|
| `flutter-linux-stable-3.47.5-x64-<sha>` | 1640 MB |
| `sol-pub-linux-3.47.5-<hash(pubspec.yaml)>` | 256 MB |

（仓库配额 10GB，现占约 1.9GB。）

分层与 key 设计（**key 一律不含 `github.ref`**，所以 main / 任意分支 / apk.yml 命中同一份）：

| 层 | 工具 | key |
|----|------|-----|
| Flutter SDK | `subosito/flutter-action@v2`（内部 `actions/cache`） | 版本+架构，钉死 `3.47.5` |
| pub 依赖 | `actions/cache@v6` → `~/.pub-cache` | `sol-pub-linux-3.47.5-<hash(pubspec.yaml)>` |
| Gradle（仅 apk.yml） | `actions/cache@v6` → `~/.gradle` | `sol-gradle-linux-<hash(wrapper+build.gradle)>` |

要点：

- **key 不能带分支名**。GitHub 的 cache 默认按分支隔离，带了 `ref_name` 就等于放弃跨分支共享。
- **key 必须基于 `pubspec.yaml`**，因为 `pubspec.lock` 被 gitignore，runner 上 checkout 后并不存在。
- `restore-keys` 前缀兜底：依赖变了也复用旧 pub cache（pub cache 是内容寻址、可叠加，只补增量）。
- **Flutter 版本要钉死**，别写 `3.47.x`：补丁版漂移会让 SDK 缓存 key 跟着变。
- 别再额外加 `~/.pub-cache` 的 cache step —— `flutter-action` 的 `cache: true` 会**同时**缓存
  SDK 和 pub 依赖，重复缓存白占 10GB 配额还多一次 restore。现在显式设 `pub-cache: false` 自己控 key。
- `ci.yml` 有 `paths-ignore: ['**/*.md', 'docs/**']`，纯文档提交不跑 CI。
- **`ci.yml` 是唯一跑 `flutter test` 的地方**；`apk.yml` 只在 `workflow_dispatch` / `v*` tag 触发，
  刻意不跑测试，避免同一 commit 花两次 CI 时间。
- ci.yml 里有 `Report cache status` 步骤，打印 SDK / pub 的 `cache-hit`；空字符串 = 未命中。

### 改 Gradle 配置的坑

`android/gradle.properties` 曾写死 `org.gradle.java.home=E:\jdk-17.0.20.1+1`，
Linux runner 上直接起不来。**已删除** —— 现在本地靠 `JAVA_HOME`、CI 靠 `actions/setup-java`。
别再把本机绝对路径写进任何提交文件。

### APK 签名

`android/*.jks` + `key.properties` 都 gitignore，CI 拿不到真签名密钥。
`apk.yml` 优先读 Secrets `SOLACE_KEYSTORE_BASE64` / `SOLACE_KEYSTORE_PASSWORD` /
`SOLACE_KEY_ALIAS` / `SOLACE_KEY_PASSWORD`；**没配就用 `keytool` 生成一次性 debug keystore**，
保证 workflow 不会因缺密钥硬失败。要出真正式签名包，先把 4 个 secret 配上。

## 命令（顺序即 CI 顺序）

> 以下命令**只能在 GitHub Actions 上跑**（本机无 Flutter，见上）。

```bash
flutter pub get            # 每次 clone/pull 后必跑，见下方 pubspec.lock 说明
flutter analyze --no-fatal-infos --no-fatal-warnings   # 门槛：0 error
flutter test               # 全量
flutter test test/xxx_test.dart                        # 单文件
```

- CI（`.github/workflows/ci.yml`）只做这三步，**无 `dart format`、无重试、无 matrix**。改动只要让 analyze 出 error 就一定红。
- `analysis_options.yaml`：`prefer_single_quotes` / `prefer_const_constructors` / `prefer_const_literals_to_create_immutables`；`android/**` 被 exclude。

### 容易踩的环境坑

- **`pubspec.lock` 在 `.gitignore` 里**（应用项目少见）。所以：CI 无法锁定依赖版本；缓存 key 只能基于 `pubspec.yaml`。
- `android/local.properties` 同样 gitignore，里面写 `flutter.sdk=` / `flutter.buildMode=release`。
- 国内镜像：`PUB_HOSTED_URL` / `FLUTTER_STORAGE_BASE_URL` 指向 `flutter-io.cn`；`pubspec.yaml` 的
  `hooks.user_defines.sqlite3.url_pattern` 把 sqlite3 原生库下载走 ghproxy。**别删这个 hooks 块**。
  镜像 env **不要**在 CI 里设（runner 在美国，走国内镜像更慢）。
- Gradle 发行版走 `mirrors.cloud.tencent.com`（`android/gradle/wrapper/gradle-wrapper.properties`），
  Maven 走阿里云 + 腾讯云（`android/build.gradle`）。这是给国内本机准备的；CI 能用但偏慢，靠 Gradle 缓存摊平。

## 架构：`part` 树是这个仓库最大的坑

20.0.0 把巨型文件拆成了 **5 个 facade + part 目录**。facade 才是真正的 library，part 文件**不能被单独 import**，改代码前必须先看它属于谁（`Select-String -Pattern "^\s*part of"`）：

| facade | part 目录 | 备注 |
|--------|-----------|------|
| `lib/services/ai_service.dart` (48KB) | `ai_service/` | 4 个：`clean_split` / `context_forgiveness` / `history_filter` / `memory_narrative` |
| `lib/services/background_service.dart` (**6KB**) | `background_parts/` | 10 个 `bg_*.dart`；曾是 90KB |
| `lib/services/memory_engine.dart` (72KB) | `memory_engine/` | `eh_summary` / `compat_cross` |
| `lib/repositories/local_storage_repository.dart` (142KB) | `repositories/storage_parts/` | 4 个，SQLite 唯一访问点 |
| `lib/main.dart` | `lib/src/app/` | `auth_gate` / `main_shell` / `discover_page` / `solace_app` 全是 `part of '../../main.dart'` |

同样用 part 拆的还有：`blocs/chat/chat_bloc.dart`（19 个 `chat_bloc_parts/bloc_*.dart`）、`blocs/group_chat/group_chat_bloc.dart`（8 个 `group_chat_bloc_parts/`）、`screens/chat/chat_detail_screen.dart`（20 个 `chat_detail_parts/`）。

> 找功能别只看文件名大小 —— `background_service.dart` 只有 6KB，逻辑都在 `bg_*.dart` 里。

### 关键服务

| 服务 | 路径 | 职责 |
|------|------|------|
| AIService | `services/ai_service.dart` (+`ai_service/`) | prompt 组装 + 调 AI API |
| PromptBuilder | `services/prompt/prompt_builder.dart` | 单聊 system 构建 |
| AIServiceAdapter | `services/bridge/ai_service_adapter.dart` | **桥接路径**，自带一套精简 prompt |
| MemoryEngine | `services/memory_engine.dart` (+`memory_engine/`) | 记忆提取/衰减/检索/摘要 |
| EmotionEngine | `services/emotion_engine.dart` | 7 情绪 + 强度衰减 |
| BackgroundService | `services/background_service.dart` (+`background_parts/`) | 后台调度 / AI 主动 |
| Proactive\* | `services/proactive_*.dart` | 主动生活（主线一） |
| Life | `services/life/` | `daily_schedule` / `timed_event` / `active_share` / `life_log` |
| Voice | `services/voice/` | MiMo TTS（云）+ 本地 sherpa-onnx STT/VAD；模型文件**不内置**，用户手动导入（`VoiceModelManager`） |
| WeChat Bot | `services/wechat/wechat_bot_service.dart` | iLink 协议 |
| CoreHub | `services/core_hub.dart` | 全局服务单例门面，`init()` 在 main 里 |
| LocalStorageRepository | `repositories/local_storage_repository.dart` | **唯一** SQLite 访问点 |

## 全局模式注入（必须同源，单一来源）

纯函数：`lib/utils/global_mode_prompt.dart` → `buildGlobalModePromptText`
存储包装：`LocalStorageRepository.buildGlobalModePrompt`（实现在 `repositories/storage_parts/chat_messages.dart:2099`）

6 个开关：`pureAiMode` / `novelMode` / `loverMode` / `openMode` / `faMode`（法功能）/ `daoMode`（刀）。`pureAiMode` 命中即短路，直接 return，不拼其他分支——**加新模式时注意这个优先级**。

**新增 LLM 调用点必须调 `buildGlobalModePrompt`，禁止绕过。** 已注入：`prompt_builder`(单聊) / `ai_service` / `bridge/ai_service_adapter`(单聊桥接) / `pure_ai_service` / `wechat_bot_service` / `background_parts/bg_ai_core` / `memory_engine` + `memory_engine/compat_cross` / `ai_service/history_filter`（反思/记忆档案/群聊档案/群聊事件） / `persona_evolution_service` / `virtual_phone_generator` / `diary_helper` / `screens/discover/ai_diary_screen`。

**刻意不注入**（非叙事聊天）：`ex_persona_analyzer`（角色逆向画像 JSON）、`proactive_decision_engine`（工具调用决策）、`announcement_service` / `update_service`（非 LLM）、`mimo_tts_service`（语音合成）。

### 改 prompt 必跑的 3 个测试

| 测试 | 守什么 |
|------|--------|
| `test/global_mode_prompt_test.dart` | 纯函数分支/短路/scope 透传 |
| `test/fa_mode_prompt_injection_test.dart` | 法模式文案真的进了 system message（用 `MockClient` 抓请求体断言） |
| `test/fa_mode_overseas_test.dart` | 海外模型 `faOverseasBoost` 行为 |

### 法功能 · 海外模型

- `AIConfig.detectModelFamily`（`lib/models/ai_config.dart`，按 `modelName` + `baseUrl` + `providerName` 推导）→ `ModelFamily`：`openai` / `anthropic` / `google` / `xai` / `domestic` / `other`
- `faOverseasBoost` **不是手动开关**，是 `modelFamily.isOverseas` 的派生 getter（`openai|anthropic|google|xai`）。海外模型（含推理模型）才走 `PromptRewriter`（`services/prompt_rewriter.dart`）文学档案
- 非流式 `sendMessage` 检测到 `isAIRefusal`（`ai_service.dart`）会**软重试一次**
- 桥接路径 `services/bridge/ai_service_adapter.dart:183` 自己算了一份 `shouldRewriteFa`，**必须与主路径保持一致**——这是历史上最容易漏的一处

### `rewriteUserMessage` 的替换顺序坑

`rewriteUserMessage` 第一步就调 `softenExplicitUserDirective`（指令软化），**它会抢占后面精细映射的词**。
所以指令软化里的正则**只能匹配带指令动词的短语**（如 `写做爱`），不能匹配裸词。

踩过的实际 bug：指令软化里写 `RegExp(r'写?性交|做爱|插入')`，导致裸 `做爱` 被提前换成
`床笫之间`，后面的 `做爱→亲密` 变成死代码，`test/prompt_rewriter_test.dart` 直接挂。
现在收紧成 `写(?:性交|做爱|插入)`，裸词交还给精细映射。

**残留问题（已知未修）**：`rewriteUserMessage` 里的 `插入→进入` 仍然过宽，
`插入U盘` / `把数据插入表格` 会被改坏。修它要区分语境（`插入` 既是普通词也是性描写用词），
风险大于收益，先记着。**往这两处加词前，先想清楚谁先执行。**

## 头像自定义与裁剪（2026-09-30）

所有头像都是**圆形**显示（`BoxShape.circle` / `ClipOval`），所以头像裁剪统一输出**正方形**。

核心组件：`lib/widgets/image_cropper.dart`

- `showImageCropper(context, file, {aspectRatio, outputSize, folder, allowRotate})`
  → 打开全屏裁剪页，返回 `docs/<folder>/<folder>_<uuid>.png`；取消返回 null。
  **已含持久化**，调用方不要再复制一遍。
- 默认参数即头像场景：`aspectRatio: 1.0`、`outputSize: 512`、`folder: 'avatars'`、`allowRotate: true`。
- 交互：双指缩放（最高 `coverScale × 4`）、单指拖动、90° 旋转、确认裁剪。
- 约束：图片永远不允许缩到小于取景框（`coverScaleForBox`），平移用 `clampOffsetForBox`
  夹住，四边不露白。
- 纯 `dart:ui`（`PictureRecorder` + `Canvas` + `Transform`），**没有引入 `image_cropper` 等原生插件** ——
  本机无 Android 环境，原生插件无法验证。
- 几何计算抽成纯函数 `CropGeometry`，`test/image_cropper_test.dart` 直接单测边界。

### 背景图：横屏 / 竖屏分开设置

手机横竖屏可见区域差别很大，一张图只存一个朝向必然有一边被裁得很惨，所以背景图
**按朝向分两列存储**。

- 取景框比例：竖屏 `9:16`，横屏 `16:9`（`BackgroundOrientation.aspectRatio`）。
- 输出长边：竖屏 1440，横屏 1920。
- 统一入口组件：`lib/widgets/background_picker.dart` → `BackgroundPicker`，
  两行（竖屏 / 横屏）各自选图 + 裁剪 + 清除。
- 渲染侧统一走 `lib/utils/background_resolver.dart` → `BackgroundResolver.provider()`：
  **本朝向没图时自动回退到另一朝向**，避免只配了一边出现半边空白。
  要加新的背景渲染位置就用它，别各写一遍 if。
- 存储列（db v75 新增，见 `_onUpgrade`）：
  | 表 | 竖屏 | 横屏 |
  |----|------|------|
  | `users` | `backgroundImage`（沿用旧字段，老数据不动） | `backgroundImageLandscape` |
  | `chat_sessions` | 同上 | 同上 |
  | `group_chat_sessions` | 同上 | 同上 |
- 清除必须走 `copyWith(clearBackgroundImage / clearBackgroundImageLandscape: true)`，
  传 `null` 会被静默忽略。

### 已接入的入口

**头像**（全部走 `showImageCropper`，正方形）：

| 位置 | 对象 |
|------|------|
| `widgets/avatar_picker.dart` | 通用选择器（**群聊设置走它**） |
| `screens/profile/profile_screen.dart` | 用户「我」的头像 |
| `screens/contacts/contacts_screen.dart` | 角色头像（联系人页） |
| `screens/character/create_character_screen.dart` | 创建角色头像 |
| `screens/chat/chat_settings_screen.dart` | 角色头像（单聊设置） |
| `screens/moments/x/x_edit_profile_screen.dart` | 朋友圈资料头像 |
| `widgets/moments/identity_picker.dart` | 朋友圈身份头像 |

**背景**（走 `BackgroundPicker` + `BackgroundResolver`）：

| 位置 | 对象 |
|------|------|
| `screens/profile/profile_screen.dart` | 个人主页背景（AppBar 壁纸按钮） |
| `screens/moments/x/x_edit_profile_screen.dart` | 朋友圈资料背景 |
| `screens/chat/chat_settings_screen.dart` | 单聊聊天背景 |

> 群聊的 `backgroundImage` 字段一直存在但**没有 UI 入口**（本次未加）。要加的话在
> `group_chat_detail_screen` 的 `_showGroupSettings` 里挂一个 `BackgroundPicker`，
> 配 `GroupChatUpdateSession(backgroundImageLandscape:)`（事件需先补该参数）。

**新增头像/背景入口时一律走 `showImageCropper` / `BackgroundPicker`**，
别再抄 `pickImage` + 手工 `File.copy` 那套（已删除 5 份重复实现）。

### 写 dart:ui / Flutter widget 的已踩坑（本机无法编译，只能靠 CI 发现）

1. **`ui.instantiateImageCodec` 要 `Uint8List`，不是 `List<int>`**。
   `File.readAsBytes()` 返回 `Uint8List`，所以形参也得声明成 `Uint8List`。
   用 `import 'dart:typed_data' as td;` + `td.Uint8List` 隔离（`dart:io` 也 re-export 了它）。
   同理 `File.writeAsBytes` 也只收 `Uint8List`。
2. **显示 `ui.Image` 要用 `RawImage`，不能用 `Image`**。
   `Image` 的 `image` 参数类型是 `ImageProvider`，传 `ui.Image` 直接
   `argument_type_not_assignable`。
3. **`num.clamp()` 返回 `num`**，赋给 `int?` / 传给 `int` 形参要补 `.toInt()`；
   赋给 `double` 要补 `.toDouble()`。
4. **`Image(...)` 没有位置参数构造**。写 `Image(provider, fit: ...)` 会报
   「named parameter 'image' is required」+「Too many positional arguments」。
   必须 `Image(image: provider, fit: ...)`。
5. **`bool?` 不能直接作条件**：`if (isLandscape)` 报
   「A nullable expression can't be used as a condition」。要写 `isLandscape == true`。
6. **collection-if 元素后面必须跟 `,` 或 `]`**。写
   `children: [ if (c) IconButton(...)  const Icon(...) ]` 报
   「Expected 'else' or comma」。注意区分 collection-if（列表里）与函数体里
   普通 `if` 语句（后者不需要逗号）。
7. **给模型加字段要同步 6 处**（漏一处就是 `Undefined name` / `isn't a field`）：
   `final` 声明 → 构造 `this.` → `copyWith` 形参 → `copyWith` 赋值 →
   `toMap`/`fromMap`（含 `json`）→ `props`（Equatable）。
   `scripts/` 下没有检查工具，只能自己数，或临时 grep 字段名确认出现次数。

另外：仓库里**没有** `translateByDouble` 等新 API 的先例，analyze 报的
`deprecated_member_use`（如 `Matrix4.translate`）只是 info，**不要**为了消警告换成
没验证过存在的新 API —— 那是拿编译错误换零 warning。

### 清除头像的坑

`copyWith` 普遍写成 `avatarUrl ?? this.avatarUrl`，**传 null 清不掉**。
已给 `User` / `AICharacter` / `GroupChatSession` 的 `copyWith` 加 `clearAvatarUrl` 开关
（对齐 `AICharacter` 早已有的 `clearColorHex` 写法），`GroupChatUpdateSession` 事件同步加了同名参数。
`AvatarPicker` 的清除按钮走独立的 `onAvatarCleared` 回调，**不要**复用 `onAvatarSelected(null)`。

## 数据库

- 版本常量：`lib/config/constants.dart` → `DbDefaults.dbVersion`（**当前 75**，v75 新增背景图横竖屏分列）
- 迁移只走 `local_storage_repository.dart` 的 `_onUpgrade`；自愈靠 `expectedColumns`（补列）+ `createMissingTable`（补表），v74 增加了自愈分支
- 数据库文件 / `-journal` / `.db` 全部 gitignore（`solace.db` / `solace_backup.db` / `solace_raw.db`）
- `screens/error/storage_recovery_screen.dart` + `services/storage/storage_recovery_controller.dart` 处理损坏恢复

## 版本号：4 处自动 + html 页脚手工

```bash
dart run scripts/bump_version.dart <x.y.z> <build> [--db <dbVersion>] [--dry-run]
```

同步 `pubspec.yaml` / `constants.dart`(AppVersion + dbVersion) / `solace/version.json` / `solace/_worker.js`(VERSION_DATA)。
**`solace/*.html` 页脚脚本不会改，会打印提醒，需人工同步。**

线上更新检查以 `solace/_worker.js` 的 `VERSION_DATA` + `version.json` 为准（`/api/v1/version`）。

## 发布 / 部署（有个真坑）

```bash
flutter build apk --release --split-per-abi --target-platform android-arm64 --no-shrink
bash deploy.sh            # 根目录是 thin wrapper，转发 scripts/deploy.sh
```

- **`scripts/deploy.sh` 找的是 `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`**，也就是**必须带 `--split-per-abi`**。README 和 `phase0_release_1901.bat` 里的构建命令都缺这个 flag，按它们走 deploy.sh 会报 `Missing APK`。
- `deploy.sh` 读 `scripts/.env.local` 取 `CLOUDFLARE_API_TOKEN`；默认 project 是 `solace-auth`（可用 `CLOUDFLARE_PAGES_PROJECT` 覆盖），但线上实际是 **`solace-auth-v2`**。
- 产物 `solace/app-release.apk*` 已 gitignore（deploy.sh 生成）。
- **`scripts/phase0_release_1901.bat` 已过期**：里面 commit message 和 `git tag v19.0.1` 都写死成 19.0.1，且用 `--project-name solace-auth-v2`。别直接跑，会打错 tag。
- `scripts/push-to-github.bat` 会 force push，只在首次建仓用。

## 安全红线

- `android/solace-release.jks` + `android/key.properties`（**明文密码**）已 gitignore，禁止提交。
- `scripts/package.json` 里只有 `ws` 一个依赖（`scripts/package-lock.json` 配套存在）。根目录不要新造 `package.json` / `package-lock.json`。
- `solace/_worker.js` 暴露更新检查与 APK 下载，注意别把 token / 内部地址写进去。

## 数据库与测试相关的目录速查

- 测试 63 个文件：55 个在 `test/` 根，8 个分布在 `life` / `moments` / `shop` / `voice` 四个子目录
- 碰 SQLite 的测试用 `sqflite_common_ffi`（`test/shop_schema_recovery_test.dart`、`test/group_chat_session_safe_write_test.dart`、`test/group_chat_memory_eh_test.dart`），照抄它们的 `sqfliteFfiInit` + `databaseFactoryFfi` 初始化
- 碰 HTTP 的测试用 `mocktail` + `http/testing.dart` 的 `MockClient` 抓请求体，别真发请求
- `build_runner` / `json_serializable` 在 dev_dependencies，但只有 `models/story_state.dart` 一个生成产物（`story_state.g.dart`）——**别顺手给别的 model 加 `@JsonSerializable`**

## 文档入口

| 文档 | 内容 |
|------|------|
| `.github/workflows/ci.yml` | **唯一测试闸门**。analyze + test，缓存策略见上文 |
| `.github/workflows/apk.yml` | APK 交付。仅 `workflow_dispatch` / `v*` tag 触发，**不跑测试** |
| `README.md` | 功能、架构、调试方法论（**部分过时**：写 db v70、版本 19.0.0，构建命令缺 `--split-per-abi`） |
| `docs/roadmap-20.0.0.md` | 20.0.0「共生」路线图 + Phase 0 |
| `docs/release-20.0.0.md` | 20.0.0 发布记录（权威） |
| `docs/design/20.0.0-mainline-*.md` | 三条主线设计 |
| `docs/cloudflare-deploy.md` | Pages 部署 |
| `docs/research/` | 微信 iLink 协议 / UI 规范 / Bot 排障 |
