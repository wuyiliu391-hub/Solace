@echo off
REM ============================================================
REM  Solace Phase 0 - 19.0.1 收尾一键脚本（Windows）
REM  执行：双击运行或在项目根目录执行
REM ============================================================
setlocal

cd /d "%~dp0.."

echo.
echo ============ Phase 0: 19.0.1 收尾 ============
echo.

echo [0.1] git status 预检查
git status --short
echo.

set /p CONFIRM="继续执行提交+测试+构建? (y/N): "
if /i not "%CONFIRM%"=="y" (
  echo 已取消。
  exit /b 0
)

echo.
echo [0.1] 提交 19.0.1
git add -A
git commit -m "feat: Solace 19.0.1 稳定性修复 + 微信 Bot 强化"
if errorlevel 1 (
  echo 提交失败或无改动。
)

echo.
echo [0.2] flutter pub get
call flutter pub get
if errorlevel 1 goto :fail

echo.
echo [0.3] flutter analyze （要求 0 error）
call flutter analyze --no-fatal-infos --no-fatal-warnings
if errorlevel 1 goto :fail

echo.
echo [0.4] flutter test
call flutter test
if errorlevel 1 (
  echo 测试有失败，请人工检查后再继续。
  pause
)

echo.
echo [0.5] 构建 Release APK (arm64)
call flutter build apk --release --target-platform android-arm64 --no-shrink
if errorlevel 1 goto :fail

echo.
echo [0.6] 部署到 Cloudflare Pages
pushd solace
call npx wrangler pages deploy . --project-name solace-auth-v2
set DEPLOY_RC=%errorlevel%
popd
if not "%DEPLOY_RC%"=="0" (
  echo Pages 部署失败，请检查 wrangler 登录状态。
)

echo.
echo [0.7] 打 tag 并推送
git tag v19.0.1
git push origin main
git push origin v19.0.1

echo.
echo ============ Phase 0 完成 ============
echo APK: build\app\outputs\flutter-apk\app-release.apk
echo 站点: https://solace-auth-v2.pages.dev
pause
exit /b 0

:fail
echo.
echo *** 执行中断，请根据上面输出排查 ***
pause
exit /b 1
