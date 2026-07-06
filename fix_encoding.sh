#!/bin/bash
# 修复chat_detail_screen.dart中的乱码

cd /c/Users/Administrator/Desktop/Solace

# 创建备份
cp lib/screens/chat/chat_detail_screen.dart lib/screens/chat/chat_detail_screen.dart.bak

# 修复各种乱码模式
sed -i "s/已开\xef\xbf\xbd/已开启/g" lib/screens/chat/chat_detail_screen.dart
sed -i "s/已关\xef\xbf\xbd/已关闭/g" lib/screens/chat/chat_detail_screen.dart
sed -i "s/消息已删\xef\xbf\xbd/消息已删除/g" lib/screens/chat/chat_detail_screen.dart
sed -i "s/消息已撤\xef\xbf\xbd/消息已撤回/g" lib/screens/chat/chat_detail_screen.dart
sed -i "s/开始聊天提升默\xef\xbf\xbd/开始聊天提升默契吧/g" lib/screens/chat/chat_detail_screen.dart
sed -i "s/人格发生了质\xef\xbf\xbd/人格发生了质变/g" lib/screens/chat/chat_detail_screen.dart
sed -i "s/角色发生了成\xef\xbf\xbd/角色发生了成长/g" lib/screens/chat/chat_detail_screen.dart
sed -i "s/开始录音失\xef\xbf\xbd/开始录音失败/g" lib/screens/chat/chat_detail_screen.dart
sed -i "s/松开发\xef\xbf\xbd/松开发送/g" lib/screens/chat/chat_detail_screen.dart
sed -i "s/强制等待一帧确保状态更\xef\xbf\xbd/强制等待一帧确保状态更新/g" lib/screens/chat/chat_detail_screen.dart
sed -i "s/派发生图事件（bloc 内部保存用户消息 + 显示生成\xef\xbf\xbd+ 执行生图\xef\xbf\xbd/派发生图事件（bloc 内部保存用户消息 + 显示生成中 + 执行生图）/g" lib/screens/chat/chat_detail_screen.dart
sed -i "s/新的消息 \xef\xbf\xbd/新的消息/g" lib/screens/chat/chat_detail_screen.dart
sed -i "s/单次转账上限\xef\xbf\xbd00000\xef\xbf\xbd/单次转账上限200000/g" lib/screens/chat/chat_detail_screen.dart
sed -i "s/未找到相关消\xef\xbf\xbd/未找到相关消息/g" lib/screens/chat/chat_detail_screen.dart
sed -i "s/最近过得怎么\xef\xbf\xbd/最近过得怎么样/g" lib/screens/chat/chat_detail_screen.dart
sed -i "s/分享一件开心的\xef\xbf\xbd/分享一件开心的事/g" lib/screens/chat/chat_detail_screen.dart
sed -i "s/今天有什么计\xef\xbf\xbd/今天有什么计划/g" lib/screens/chat/chat_detail_screen.dart

echo "修复完成"
