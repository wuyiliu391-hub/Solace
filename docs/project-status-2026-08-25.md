# Solace 项目状态分析报告

> 分析日期：2026-08-25
> 分析方式：git 状态 + 未提交 diff + flutter analyze 验证 + 项目文档交叉比对

## 一、项目概览

- **项目**：Solace —— Flutter AI 陪伴应用（多角色聊天 / 情感记忆引擎 / 人生模拟 / 微信 Bot），隐私优先、纯本地 SQLite 存储，Android 单平台。
- **当前版本**：`19.0.1+8304`（**尚未提交**，工作区暂停中）
- **最后提交**：`e347e83` — "feat: Solace 19.0.0 微信 Bot + 工程架构重构 + 语音通话强化"（2026-08-20）
- **分支**：main（本地落后 origin/main 的 refactor/split-storage-repo 等为历史分支）

## 二、暂停的进度：19.0.1 稳定性修复版（未提交工作区）

改动规模：**17 个文件，+796 / -487**。最后修改时间 **2026-08-21 21:48**（暂停至今约 4 天）。

### 1. 微信机器人设置页（wechat_bot_screen.dart，559 行改动）
- 新增「**同步到聊天列表**」开关（默认关闭）：微信会话默认 `isHidden`，与 Solace 主聊天列表隔离；开启后恢复显示。
- 新增「**连接记忆库**」开关（默认开启）：关闭后微信 AI 回复不再读取 Solace 记忆库。
- 全页明暗主题自适应：`WxColors` → `WeChatColors` dark 系列（darkListItem / darkPageBackground / darkTextPrimary / darkTextSecondary / darkDivider）。

### 2. 聊天详情页微信化重构（chat_detail_screen.dart，428 行改动）
- 移除消息区顶部常驻「关系头 + 状态栏」，信息收敛进**紧凑 AppBar 标题**（头像 + 名字 + 状态行：`对方正在输入…` / `情绪 · 亲密度 N`）。
- 「TA 的手机」从常驻图标移入「更多」菜单，新增 5 个菜单项：TA 的手机 / 查看动态 / TA 的当前状态 / 角色设定（CharacterEditorScreen）/ 记忆回溯（MemoryScreen）。
- 移除输入区常驻快捷功能栏（微信化简化）。
- **多行输入框修复**：ConstrainedBox(maxHeight: 120) + SingleChildScrollView，解决第二行文字被遮挡。
- 气泡列表水平间距 16 → 12。

### 3. 微信回复管线加固（wechat_bot_service.dart）
- AI 回复加 **90 秒超时**保护（对应排障记录中"回复极慢 10 分钟+"问题）。
- `sendTyping` 加 5 秒超时 + try-catch 吞掉失败，避免网络抖动卡死主流程。

### 4. 聊天 Bloc（chat_bloc.dart）
- 「重新生成」路径加 90s 超时 + 异常捕获 + 重试，解决重新生成失败/中断后无法恢复。

### 5. TTS 音色切换修复（mimo_tts_service.dart + voice_profile_store.dart）
- `VoiceProfileStore.onPresetChanged` 回调 → `MiMoTtsService` 清除角色样本 base64 + sha1 缓存，解决"切换预置音色无效、仍播旧音色"。

### 6. 联系人列表修复（chat_list_screen.dart）
- `ChatInitial` 状态自动触发 `ChatLoadSessions`，解决"主页联系人列表打开后一直转圈不显示"。

### 7. 版本公告
- auth_gate.dart：新增 19.0.1 强制确认公告弹窗（`versionFeatureAck8304`）。
- version_feature_dialog.dart：公告内容更新为 19.0.1 修复清单。

### 8. 版本同步（5 文件已一致）
| 文件 | 值 |
|---|---|
| pubspec.yaml | 19.0.1+8304 |
| lib/config/constants.dart (AppVersion) | 19.0.1 / 8304 |
| solace/version.json | 19.0.1 / 8304，releaseDate 2026-08-21 |
| solace/_worker.js | 19.0.1 / 8304 + 新公告 ann_1901 |

## 三、暂停点代码健康度验证

- **flutter analyze：0 error**（1467 条均为既有 info/warning 风格 lint，主要集中在 test/ 目录，非本次改动引入）。
- 所有新增引用均存在：`CharacterEditorScreen`、`MemoryScreen`、`_openVirtualPhone`（async）、`WeChatColors` dark 系列、`WeChatDimens.dividerHeight`。
- 无残留 `WxTheme/WxColors/WxDimens` 引用（import 已切到 app_colors.dart）。

## 四、遗留事项 / 未完成步骤

1. **提交**：19.0.1 改动尚未 commit。
2. **测试**：仓库含 555+ 测试（19.0.0 提交说明），本次改动后未跑过 `flutter test`。
3. **构建**：未构建 19.0.1 release APK（arm64 分片）。
4. **部署**：version.json / _worker.js 已本地改好，但未推送 Cloudflare Pages（solace-auth-v2.pages.dev）。
5. **死代码清理**（2026-08-25 已完成）：
   - 已删除 `chat_detail_screen.dart` 中 7 个无调用点方法（`_buildRelationshipHeader` / `_buildStatusBar` / `_buildIntimacyExpanded` / `_buildIntimacyCollapsed` / `_isToday` / `_relationshipLabel` / `_eventSourceLabel`），共 390 行。删除后 flutter analyze 保持 0 error。
   - **注意**：`lib/config/wechat_theme.dart`（WxTheme/WxColors/WxDimens）**并非冗余**，仍有 12 个活跃引用方（lib/widgets/wechat/ 下的微信皮肤组件：wx_preview_screen、wx_money_card、wx_moments_page、wx_me_page、wx_main_shell、wx_discover_page、wx_create_money_sheet、wx_conversation_tile、wx_contacts_page、wx_chat_input_bar、wx_chat_app_bar、wx_bubble），不得删除。
6. **杂项**（2026-08-25 已清理）：未跟踪文件 `鹈鹕.html`（趣味 Canvas 动画）已移入回收站（可恢复）。

## 五、结论

暂停点位于 **19.0.1 开发完成、发布前的最后一步**：代码已全部写完且编译健康（0 error），版本号已全量同步，只差 **提交 → 测试 → 构建 APK → 部署 Pages** 这条发布流水线。

---

### 附注：技能包与项目不匹配
海鸥技能包内 `system-prompt.md` 描述的是 GameShield 安全研究平台（游戏反外挂研究，v4.1），与工作区实际项目 Solace（AI 陪伴应用）完全无关。本报告以工作区实际项目为准。
