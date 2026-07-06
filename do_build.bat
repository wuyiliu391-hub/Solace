@echo off
cd /d C:\Users\Administrator\Desktop\Solace
flutter build apk --debug > C:\Users\Administrator\Desktop\build_log.txt 2>&1
type C:\Users\Administrator\Desktop\build_log.txt
