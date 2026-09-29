# Solace 20.0.0 发布说明

> 日期：2026-09-15  
> 版本：`20.0.0+20000`  
> 类型：维护向大版本（主题统一 / 存储可控 / 加固），非 Roadmap「共生」三主线全量交付

## 版本号（5 处已同步）

| 文件 | 值 |
|------|-----|
| `pubspec.yaml` | `20.0.0+20000` |
| `lib/config/constants.dart` | `AppVersion.version/build` |
| `solace/version.json` | `version` / `build` |
| `solace/_worker.js` | `VERSION_DATA` |
| `solace/*.html` | 页脚与下载页文案 |

## 新增

- 全局 AI 消耗控制（`ai_usage_gate`）
- 存储管理完整扫描与精细清理（语音模型 / 备份残留 / 聊天图片等）
- 聊天主题：暮玫 Dusk Rose（深）+ 软纸 Soft Paper（浅），单聊与群聊统一
- 聊天页 AppBar 模型快速切换（`AiModelSwitcher`）
- faMode 海外模型适配与软拒绝重试

## 修复 / 加固

- 单聊氛围底不再按角色混色；群聊铺同一主题渐变
- 群聊长按菜单小屏滚动、记忆列表时效、收藏跳转
- 角色去重折叠、日记入口与生成成功率
- 数据库 v74：`group_chat_branches` / `group_chat_lorebook_entries`
- `gradle.properties` UTF-8 修复；插件 `compileSdkVersion` 36
- versionCode 抬升以支持覆盖安装（历史设备 10304）
- **`flutter_assets` 禁止清理**（debug JIT kernel；误删会黑屏）
- ErrorWidget 可见化，避免异常纯黑屏
- 死功能下线与 `background_service` 拆分降压

## 构建命令

```bat
flutter build apk --release --target-platform android-arm64 --no-shrink
```

产物：`build/app/outputs/flutter-apk/app-release.apk`

## Cloudflare Pages 部署清单

见 `docs/cloudflare-deploy.md`：

1. 登录：`npx wrangler login`（GitHub OAuth，账号 `wuyiliu391-hub`）或 `CLOUDFLARE_API_TOKEN`
2. 同步 `solace/` 站点与 `version.json` / `_worker.js` / HTML
3. 将 `app-release.apk` 放到 Pages 可下载路径（按现有 `deploy.sh` / download API 约定）
4. `cd solace && npx wrangler pages deploy . --project-name solace-auth-v2`
5. 验证：`https://solace-auth-v2.pages.dev` 显示 20.0.0，更新检查接口返回 build 20000

## 注意

- 签名密钥 `android/*.jks` + `key.properties` **禁止提交**
- 本仓库 git 尚未 commit；发布前需自行 `git add` / `commit` / `tag v20.0.0`
