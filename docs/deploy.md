# Solace 部署说明

## 本地密钥

部署脚本会自动读取项目根目录的 `.env.local`。该文件只保存在本机，已加入 `.gitignore`，不要提交到仓库。

示例：

```bash
CLOUDFLARE_API_TOKEN="你的 Cloudflare API Token"
CLOUDFLARE_ACCOUNT_ID="你的 Cloudflare Account ID"
CLOUDFLARE_PAGES_PROJECT="solace-auth"
```

## 部署

先确认已构建 release APK：

```bash
flutter build apk --release --target-platform android-arm64
```

然后执行：

```bash
bash deploy.sh
```

脚本会复制 `build/app/outputs/flutter-apk/app-release.apk`，生成 `solace/app-release.apk.gz`，并部署到 Cloudflare Pages。Pages 单文件限制为 25 MiB，所以部署目录只保留 gzip 包，下载接口由 Worker 解压返回 APK。
