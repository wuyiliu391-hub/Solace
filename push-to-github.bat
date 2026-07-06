@echo off
cd /d "C:\Users\Administrator\Desktop\Solace"

echo [1/4] 初始化 Git...
git init

echo [2/4] 添加远程仓库...
git remote remove origin 2>nul
git remote add origin https://github.com/wuyiliu391-hub/Solace.git

echo [3/4] 添加所有文件并提交...
git add -A
git commit -m "Initial commit: Solace AI companion app"

echo [4/4] 强制推送到 GitHub...
git branch -M main
git push -f origin main

echo.
echo 完成！
pause
