@echo off
REM ═══════════════════════════════════════════════════════════════
REM  Solace 国内镜像配置脚本 (CMD)
REM  每次打开新终端编译前执行一次即可
REM ═══════════════════════════════════════════════════════════════

echo.
echo === Solace 国内镜像配置 ===
echo.

REM ─── Flutter/Dart Pub 镜像（阿里云） ───
set PUB_HOSTED_URL=https://pub.flutter-io.cn
set FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
echo [PUB]   PUB_HOSTED_URL = %%PUB_HOSTED_URL%%
echo [FLUTTER] FLUTTER_STORAGE_BASE_URL = %%FLUTTER_STORAGE_BASE_URL%%
echo.

REM ─── Gradle 镜像（腾讯云） ───
REM 已在 gradle-wrapper.properties 中配置
echo [GRADLE] gradle-wrapper.properties 已配置腾讯云镜像
echo.

REM ─── Android SDK 镜像（腾讯云） ───
REM 如需通过镜像下载 SDK，可在 Android Studio 中配置：
REM https://mirrors.cloud.tencent.com/android/sdk/
echo [SDK] Android SDK 镜像：https://mirrors.cloud.tencent.com/android/sdk/
echo.

echo === 配置完成！当前终端可直接使用 flutter/dart 命令 ===
echo.
