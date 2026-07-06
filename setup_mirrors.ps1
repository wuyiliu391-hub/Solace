# ═══════════════════════════════════════════════════════════════
#  Solace 国内镜像配置脚本 (PowerShell)
#  每次打开新终端编译前执行一次即可
# ═══════════════════════════════════════════════════════════════

Write-Host "`n=== Solace 国内镜像配置 ===`n" -ForegroundColor Cyan

# ─── Flutter/Dart Pub 镜像（阿里云） ───
$env:PUB_HOSTED_URL = "https://pub.flutter-io.cn"
$env:FLUTTER_STORAGE_BASE_URL = "https://storage.flutter-io.cn"
Write-Host "[PUB]     PUB_HOSTED_URL = $env:PUB_HOSTED_URL" -ForegroundColor Green
Write-Host "[FLUTTER] FLUTTER_STORAGE_BASE_URL = $env:FLUTTER_STORAGE_BASE_URL" -ForegroundColor Green

# ─── Gradle 镜像（腾讯云） ───
Write-Host "[GRADLE]  gradle-wrapper.properties 已配置腾讯云镜像" -ForegroundColor Yellow

# ─── Android SDK 镜像（腾讯云） ───
Write-Host "[SDK]     Android SDK 镜像：https://mirrors.cloud.tencent.com/android/sdk/" -ForegroundColor Yellow

Write-Host "`n=== 配置完成！当前终端可直接使用 flutter/dart 命令 ===`n" -ForegroundColor Cyan
