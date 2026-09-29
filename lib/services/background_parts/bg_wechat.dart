// 后台任务拆分 part
part of '../background_service.dart';

Future<bool> handleWeChatPollTask(Map<String, dynamic>? inputData) async {
  if (!await _bgUsageAllowed(PrefKeys.aiUsageWechatPoll)) return true;
  try {
    final enabled = await WeChatBotStore.loadEnabled();
    final token = await WeChatBotStore.loadToken();
    if (!enabled || token == null) return true;

    final baseUrl = await WeChatBotStore.loadBaseUrl();
    final client = IlinkClient(baseUrl: baseUrl, botToken: token);
    final updatesBuf = await WeChatBotStore.loadUpdatesBuf();

    final IlinkUpdatesResult result;
    try {
      // 后台任务时限紧张：短超时拉一次即走（前台长轮询负责实时性）
      result = await client.getUpdates(
        updatesBuf: updatesBuf,
        timeout: const Duration(seconds: 20),
      );
    } on IlinkException catch (e) {
      if (e.isUnauthorized || e.isStaleToken) await WeChatBotStore.clearSession();
      debugPrint('Background WeChat: iLink 错误: $e');
      return !(e.isUnauthorized || e.isStaleToken);
    }
    if (result.updatesBuf != updatesBuf) {
      await WeChatBotStore.saveUpdatesBuf(result.updatesBuf);
    }
    final updates = result.messages;
    if (updates.isEmpty) return true;

    final db = await _openRawDb();
    try {
      final config = await _getActiveConfig(db);
      final recipient = await _resolveCurrentRecipient(db);
      final userId = (recipient?['id'] as String?) ?? 'local_user';

      Map<String, dynamic>? character;
      final boundId = await WeChatBotStore.loadBoundCharacterId();
      if (boundId != null) {
        final rows = await db.query('ai_characters',
            where: 'id = ?', whereArgs: [boundId], limit: 1);
        if (rows.isNotEmpty) character = rows.first;
      }

      for (final update in updates) {
        // 只处理联系人发来且已完结的消息
        if (!update.isFromUser || !update.isFinished) continue;

        if (update.contextToken != null) {
          await WeChatBotStore.saveContextToken(
              update.fromUserId, update.contextToken!);
        }

        if (!(await WeChatBotStore.isWhitelisted(update.fromUserId))) {
          await WeChatBotStore.upsertPending(
            wxId: update.fromUserId,
            fromName: update.fromUserId,
            lastText: update.text,
          );
          continue;
        }

        final sessionId =
            'wx_${update.fromUserId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')}';
        final contactName =
            await WeChatBotStore.displayNameOf(update.fromUserId) ??
                update.fromUserId;
        final now = DateTime.now();

        // 会话不存在则创建
        final sessionRows = await db.query('chat_sessions',
            columns: ['id'], where: 'id = ?', whereArgs: [sessionId], limit: 1);
        if (sessionRows.isEmpty && character != null) {
          await db.insert('chat_sessions', {
            'id': sessionId,
            'userId': userId,
            'aiCharacterId': character['id'] as String? ?? '',
            'aiCharacterName': character['name'] as String? ?? 'AI',
            'createdAt': now.toIso8601String(),
            'updatedAt': now.toIso8601String(),
            'sessionType': 'private',
          });
        }

        // 入站消息落库
        await db.insert(
          'chat_messages',
          {
            'id':
                'wx_${update.messageId ?? update.seq}_${update.text.hashCode.toUnsigned(20)}',
            'chatId': sessionId,
            'senderId': update.fromUserId,
            'senderName': contactName,
            'content': update.text,
            'isUser': 1,
            'type': 0,
            'status': 1,
            'createdAt': update.createdAt.toIso8601String(),
            'metadata': jsonEncode({'source': 'wechat_ilink'}),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        // 简化 AI 回复（无 config/角色时跳过，等前台全管线处理）
        if (config != null && character != null) {
          try {
            final recent = await db.query(
              'chat_messages',
              where: 'chatId = ?',
              whereArgs: [sessionId],
              orderBy: 'createdAt DESC',
              limit: 6,
            );
            final reply = await _callAiApi(
              config,
              _buildWxBackgroundReplyPrompt(
                  character, contactName, update.text, recent),
              temperature: 0.7,
              maxTokens: 300,
            );
            if (reply.trim().isNotEmpty) {
              final contextToken = update.contextToken ??
                  await WeChatBotStore.loadContextToken(update.fromUserId);
              await client.sendMessage(
                to: update.fromUserId,
                text: reply,
                contextToken: contextToken,
              );
              await db.insert('chat_messages', {
                'id': 'wxr_${now.millisecondsSinceEpoch}_${Random().nextInt(9999)}',
                'chatId': sessionId,
                'senderId': 'ai_${character['id']}',
                'senderName': character['name'] as String? ?? 'AI',
                'content': reply,
                'type': 0,
                'status': 1,
                'createdAt': DateTime.now().toIso8601String(),
                'metadata': jsonEncode({'source': 'wechat_ilink_reply'}),
              });
            }
          } catch (e) {
            debugPrint('Background WeChat: 回复生成失败: $e');
          }
        }

        // 更新会话摘要
        await db.update(
          'chat_sessions',
          {
            'lastMessage': update.text,
            'lastMessageTime': now.toIso8601String(),
            'updatedAt': now.toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [sessionId],
        );

        // 通知（后台 isolate 内单独初始化插件，照主动消息先例）
        try {
          final flp = FlutterLocalNotificationsPlugin();
          const androidSettings =
              AndroidInitializationSettings('@mipmap/ic_launcher');
          await flp.initialize(const InitializationSettings(
            android: androidSettings,
            iOS: DarwinInitializationSettings(),
          ));
          await flp.show(
            (update.messageId ?? update.seq ?? now.millisecondsSinceEpoch) &
                0x7fffffff,
            '微信 · $contactName',
            update.text,
            const NotificationDetails(
              android: AndroidNotificationDetails(
                NotificationChannels.backgroundChat,
                '聊天消息',
                channelDescription: 'AI 角色的聊天消息',
                importance: Importance.high,
                priority: Priority.high,
                icon: '@mipmap/ic_launcher',
              ),
            ),
            payload: 'chat_$sessionId',
          );
        } catch (e) {
          debugPrint('Background WeChat: 通知失败: $e');
        }
      }
    } finally {
      await db.close();
    }
    return true;
  } catch (e) {
    debugPrint('Background WeChat poll failed: $e');
    return false;
  }
}

/// 后台简化回复 prompt（无记忆引擎，仅人设 + 最近上下文）。
String _buildWxBackgroundReplyPrompt(
  Map<String, dynamic> character,
  String contactName,
  String incoming,
  List<Map<String, Object?>> recent,
) {
  final name = character['name'] as String? ?? 'AI';
  final personality = character['personality'] as String? ?? '';
  final languageStyle = character['languageStyle'] as String? ?? '';
  final buffer = StringBuffer()
    ..writeln('你是「$name」，正在微信上代替用户回复朋友的消息。')
    ..writeln('你的人设：$personality')
    ..writeln('你的说话风格：$languageStyle')
    ..writeln('要求：口语化、简短自然（1-2 句），符合微信聊天习惯，'
        '不要暴露自己是 AI，不要使用括号动作描写。');
  if (recent.isNotEmpty) {
    buffer.writeln('最近的聊天记录（旧→新）：');
    for (final m in recent.reversed) {
      final isUser = (m['isUser'] as int? ?? 0) == 1;
      buffer.writeln('${isUser ? contactName : name}：${m['content']}');
    }
  }
  buffer.writeln('现在 $contactName 发来：$incoming');
  buffer.writeln('请以$name的身份直接回复（只输出回复内容本身）：');
  return buffer.toString();
}

