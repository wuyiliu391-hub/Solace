// 后台任务拆分 part
part of '../background_service.dart';

Future<bool> _handleProactiveChat(Map<String, dynamic>? inputData) async {
  if (!await _bgUsageAllowed(PrefKeys.aiUsageProactiveChat)) return false;
  final characterId = inputData?['characterId'] as String?;
  final sessionId = inputData?['sessionId'] as String?;
  final intimacyLevel = inputData?['intimacyLevel'] as int? ?? 0;

  if (characterId == null || sessionId == null) return false;

  final db = await _openRawDb();
  try {
    final config = await _getActiveConfig(db);

    final charRows = await db
        .query('ai_characters', where: 'id = ?', whereArgs: [characterId]);
    if (charRows.isEmpty) return false;
    final character = charRows.first;

    final messages = await db.query(
      'chat_messages',
      where: 'chatId = ?',
      whereArgs: [sessionId],
      orderBy: 'createdAt ASC',
    );
    final now = DateTime.now();
    final proactiveMessages = messages.where((message) {
      final metadata = message['metadata'] as String?;
      return metadata != null && metadata.contains('"isProactive":true');
    }).toList();
    final latestProactive = proactiveMessages.isEmpty
        ? null
        : proactiveMessages
            .map((message) =>
                DateTime.tryParse(message['createdAt'] as String? ?? ''))
            .whereType<DateTime>()
            .fold<DateTime?>(
                null,
                (latest, value) =>
                    latest == null || value.isAfter(latest) ? value : latest);
    final latestUser = messages
        .where((message) =>
            (message['senderId']?.toString() ?? '').startsWith('ai_') == false)
        .map((message) =>
            DateTime.tryParse(message['createdAt'] as String? ?? ''))
        .whereType<DateTime>()
        .fold<DateTime?>(
            null,
            (latest, value) =>
                latest == null || value.isAfter(latest) ? value : latest);
    final interactionConfigRaw =
        character['interactionConfig'] as String? ?? '{}';
    Map<String, dynamic> interactionConfig = {};
    try {
      interactionConfig =
          Map<String, dynamic>.from(jsonDecode(interactionConfigRaw));
    } catch (_) {}
    final policy = ProactivePolicyService().evaluate(ProactivePolicyInput(
      enabled: interactionConfig['enableMomentInteraction'] != false &&
          interactionConfig['enableMomentInteraction'] != 0,
      frequencyHours:
          (interactionConfig['activeMessageFrequency'] as num?)?.toInt() ?? 2,
      now: now,
      lastUserMessageAt: latestUser,
      lastProactiveAt: latestProactive,
      deliveredToday: proactiveMessages.where((message) {
        final created =
            DateTime.tryParse(message['createdAt'] as String? ?? '');
        return created != null &&
            created.year == now.year &&
            created.month == now.month &&
            created.day == now.day;
      }).length,
      hasDueCommitment: false,
      respectsBoundary: true,
    ));
    if (!policy.allowed) {
      debugPrint('Background: 主动消息策略拦截 $characterId: ${policy.reason}');
      return true;
    }

    String content;
    try {
      content = await _generateBgContent(db, config, character, intimacyLevel);
    } catch (e) {
      debugPrint('Background generate failed: $e');
      return true;
    }

    if (content.trim().isEmpty || content.trim() == '[SILENT]') {
      debugPrint('Background: AI决定静默，不发送消息');
      return true;
    }

    final msgId = 'bg_${now.millisecondsSinceEpoch}_${Random().nextInt(9999)}';
    await db.insert('chat_messages', {
      'id': msgId,
      'chatId': sessionId,
      'senderId': 'ai_$characterId',
      'senderName': character['name'] as String? ?? 'AI',
      'content': content,
      'type': 0,
      'status': 1,
      'createdAt': now.toIso8601String(),
      'metadata': jsonEncode(
          {'isProactive': true, 'delivery': 'foreground_or_background'}),
    });

    final sessionRows = await db.query(
      'chat_sessions',
      columns: ['unreadCount'],
      where: 'id = ?',
      whereArgs: [sessionId],
      limit: 1,
    );
    final unreadCount = sessionRows.isEmpty
        ? 0
        : (sessionRows.first['unreadCount'] as int? ?? 0);
    await db.update(
        'chat_sessions',
        {
          'lastMessage': content,
          'lastMessageTime': now.toIso8601String(),
          'unreadCount': unreadCount + 1,
          'updatedAt': now.toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [sessionId]);

    if (inputData?['foreground'] == true) return true;

    final flp = FlutterLocalNotificationsPlugin();
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    await flp.initialize(const InitializationSettings(
      android: androidSettings,
      iOS: DarwinInitializationSettings(),
    ));

    await flp.show(
      now.millisecondsSinceEpoch % 100000,
      character['name'] as String? ?? 'AI',
      content,
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

    return true;
  } finally {
    await db.close();
  }
}

// ─── Handler: AI 发动态 ───
