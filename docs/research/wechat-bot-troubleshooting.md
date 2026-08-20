# 微信 iLink Bot 接入排障全记录（2026-08-20）

> 项目：Solace 微信机器人（手机端直连 iLink 长轮询 + 完整角色管线回复）
> 本文档记录从"猜测协议"到"全链路跑通"的完整过程，含所有踩过的坑与最终修复。

## 一、协议层（前期完成）

完整协议笔记见 [wechat-ilink-protocol.md](./wechat-ilink-protocol.md)。

## 二、排障时间线（按发现顺序）

### 1. 角色串戏（请求给了错误角色）
- **症状**：绑定角色 A，AI 请求却以角色 B 的口吻回复。
- **根因**：`wx_` 会话是之前绑定其他角色时创建的，`session.aiCharacterId` 残留旧角色 ID；且历史消息全是旧角色的，AI 被历史带偏。
- **修复**（`wechat_bot_service.dart` `_handleMessage`）：会话已存在但 `aiCharacterId != 绑定角色` 时，`copyWith` 同步为新角色并落库。

### 2. "抱歉，我现在无法回复" 是谁发的
- **真相**：**不是 AI 生成的，不是微信发的，是自家代码的硬编码兜底**。
- **位置**：`ai_service_adapter.dart`：
  ```dart
  if (response.error != null) {
    return '抱歉，我现在无法回复。';
  }
  ```
- **触发链**：LLM API 调用失败（HTTP 4xx/5xx/超时/网络错）→ `response.error != null` → 硬编码字符串 → bot 当正常回复发回微信。
- **教训**：错误兜底文案伪装成角色发言，极难排查。已加详细日志定位真实错误。

### 3. 未成年年龄触发上游审查（误判）
- **症状**：用户消息全是"你好""在吗"也返回"抱歉"。
- **排查**：拉设备 DB 看角色卡，绑定角色"作者"设定里有"17岁"。
- **修复**（`wechat_bot_service.dart` `_stripMinorAge`）：bot 请求上游前，角色卡里 `<18岁` 的年龄替换为"20多岁"，"未成年"声明替换为"是成年人"。只影响发往上游的文本，不改本地角色卡。
- **注**：后续发现这并非本次主因（主因是超时），但保留作为防御（国内 API 未成年人保护是平台硬拦截）。

### 4. 配置读取路径不一致（bot 打到默认地址）
- **症状**：Solace 聊天页正常，bot 全失败。
- **根因**：`AIServiceAdapter._llmService` 懒加载只从 SharedPreferences `llm_*` 键读配置（旧路径，设备上不存在）→ apiKey 空、baseUrl 默认 deepseek、model 默认 deepseek-chat → 必然失败。
- **修复**（`ai_service_adapter.dart`）：`llm_*` 键为空时回退到数据库 `ai_configs` 活跃配置（`getActiveAIConfig`），与 Solace 聊天页同源。
- **验证方法**：`adb exec-out run-as com.solace.solace cat .../shared_prefs/FlutterSharedPreferences.xml` 查 `llm_` 键。

### 5. 切后台必须返回 Solace 才有回复
- **症状**：滑到微信聊天，不返回 Solace 一次，微信永远无回复。
- **根因**（`main_shell.dart` `didChangeAppLifecycleState`）：`paused` 时调用 `stopPolling()`，bot 轮询直接停。
- **修复**：切后台只 `setForeground(false)`，**不 stopPolling**；`stopPolling` 仅保留在主动断开/登出场景。

### 6. 轮询启动死锁（_polling 卡 true）
- **症状**：App 冷启动后 bot 永远不轮询，直到用户进入角色会话（切前台）才恢复。
- **根因**（`startPolling`）：`_polling = true` 设得太早，中间 `notifyStart()` 等网络步骤抛异常 → `_polling` 卡 true 但 `_runLoop` 没启动 → 后续 `startPolling` 被 `if (_polling) return` 挡住。
- **修复**：
  - `_polling = true` 移到所有启动步骤成功之后，异常时复位 `_polling = false` 可重试；
  - `_runLoop` 所有异常 catch 后延迟重试，永不退出；
  - `_runLoop` 意外退出后自愈重启（`_stopIntentional` 标记区分主动停止）。

### 7. ROM 杀后台（保活加固）
- **已做**：Android 前台服务 `WechatBotForegroundService`（`foregroundServiceType="dataSync"`，Android 15+ 必须指定类型否则 `MissingForegroundServiceTypeException`）。
- **注意**：Android 15 targetSDK=35 下：
  - 无类型声明 → `MissingForegroundServiceTypeException`
  - `dataSync` 类型需 `FOREGROUND_SERVICE_DATA_SYNC` 权限
  - 启动前台服务用 `startForegroundService()`（Android O+）
- **新增**：`REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` 权限 + `requestIgnoreBatteryOptimization` MethodChannel，请求系统忽略电池优化（国产 ROM 保活关键）。

### 8. 微信"正在输入"出现但无消息返回（最终根因）
- **症状**：微信顶部显示"对方正在输入中"→ 随后无消息。
- **根因**（日志实锤）：
  ```
  [AIServiceAdapter] LLM 请求失败: 网络错误: TimeoutException after 0:00:30.000000
  model=deepseek-v4-pro baseUrl=http://192.168.1.169:7863/v1
  ```
  `DohResolver.post` **写死 30 秒超时**；Solace 聊天页走 `AIService` 用 `AppDurations.aiRequest`（90 秒）。`deepseek-v4-pro` 是思考模型，bot 带 50 条历史 + 20 条记忆的长上下文推理超 30 秒 → 被掐断 → 硬编码"抱歉" → 清洗拦截 → 无回复。
- **修复**：
  - `doh_client.dart`：`post()` 超时参数化；
  - `llm_service.dart`：两处 `DohResolver.post` 传 `timeout: 90s`；
  - bot 上下文精简：历史 50→20、记忆 20→10，加速思考模型。

## 三、最终全链路（成功态）

```
微信用户 → iLink 长轮询(getupdates, 45s) → _handleMessage
  → 去重 → 白名单 → 会话角色同步 → 入站落库
  → sendTyping(typing: true)【微信显示"正在输入"】
  → 取历史(20) + 记忆(10)
  → _generateReply:
      - 年龄净化（<18岁 → 20多岁）
      - 全局模式提示注入（法模式等）
      - 过滤历史中的拒绝回声
      - adapter.sendMessage（配置回退 DB ai_configs，90s 超时）
  → 清洗（拒绝/乱码/禁词拦截）
  → sendTyping(typing: false)
  → sendMessage 拆条发回微信（回传 context_token）
  → AI 回复落库 + 会话摘要 + 通知
```

## 四、保活架构（当前）

- 前台轮询：`WeChatBotService` 单例，长轮询循环（35s hold + 余量），断网自愈重启。
- 前台服务：`WechatBotForegroundService`（dataSync）防杀进程。
- 电池白名单：`requestIgnoreBatteryOptimization`（用户确认一次）。
- 切后台：不 stopPolling，轮询继续；回复走系统通知。
- 后台兜底：workmanager 15 分钟拉一次（`background_service.dart handleWeChatPollTask`）。

## 五、遗留/可选优化

- 生产级部署（服务器 OpenClaw 中继）可彻底解决手机后台受限，见子代理调研（方案 B）。
- `context_token` 缓存按联系人存 SharedPreferences（`wx_context_tokens`），上限 200 条。
- `_typingTickets` 内存缓存，App 重启后需重新 getConfig。
- 思考模型（deepseek-v4-pro）首响慢，90s 超时已覆盖但用户体验上"正在输入"会持续 ~1 分钟。