# Solace 部署与账号信息

## Cloudflare Pages

- **项目名称**：`solace-auth-v2`
- **正式域名**：`solace-auth-v2.pages.dev`
- **账号 ID**：`af48f65049fad4485235e33a5b4a43e1`
- **注册邮箱**：Google 邮箱（具体地址见 Cloudflare 欢迎邮件）
- **登录方式（重要）**：**GitHub OAuth**（虽然注册邮箱是 Google，但 Cloudflare 账号是通过 GitHub 登录创建的。登录时选择 **Sign in with GitHub**，用 GitHub 账号 `wuyiliu391-hub` 授权即可）
- **部署方式**：`wrangler pages deploy . --project-name solace-auth-v2`
- **构建输出目录**：`solace/`（`wrangler.toml` 中 `pages_build_output_dir = "."`）

## 部署前准备

1. 确保 wrangler 已登录：`npx wrangler login`（用 GitHub 登录方式）
2. 或设置环境变量：`CLOUDFLARE_API_TOKEN`（需要 API Token，权限含 Pages:Edit）

## 完整部署命令

```bash
cd /c/Users/Administrator/Desktop/Solace/solace
npx wrangler pages deploy . --project-name solace-auth-v2
```

## 版本更新（发布新版本时同步）

以下 5 个文件的版本号必须保持一致：
1. `pubspec.yaml` — `version: x.x.x+xxx`
2. `lib/config/constants.dart` — `AppVersion.version` / `AppVersion.build`
3. `solace/version.json` — `version` / `build`
4. `solace/_worker.js` — `VERSION_DATA.latestVersion` / `buildNumber`
5. `solace/index.html`、`solace/*.html` — 页脚版本号 `v19.0.1+8304`