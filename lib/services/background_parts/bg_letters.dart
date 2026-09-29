// 后台任务拆分 part
part of '../background_service.dart';

Future<bool> _handleLetterPost(Map<String, dynamic>? inputData) async {
  if (!await _bgUsageAllowed(PrefKeys.aiUsageLetter)) return false;
  final db = await _openRawDb();
  try {
    final config = await _getActiveConfig(db);
    if (config == null) return false;

    final characters =
        await db.query('ai_characters', where: 'isOnline = ?', whereArgs: [1]);
    if (characters.isEmpty) return false;

    final random = Random();
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day).toIso8601String();

    // 获取用户信息：必须取前台登录账号，否则来信落到错误用户名下，
    // 信箱按当前用户查询查不到（通知却照发）
    final recipientUser = await _resolveCurrentRecipient(db);
    if (recipientUser == null) return false;
    final userId = recipientUser['id'] as String;
    final recipientName = recipientUser['nickname'] as String? ?? '你';

    for (final character in characters) {
      final characterId = character['id'] as String;
      final characterName = character['name'] as String? ?? '';

      // 检查今日是否已写过信
      final todayLetters = await db.rawQuery(
        'SELECT COUNT(*) as cnt FROM ai_letters WHERE characterId = ? AND createdAt >= ?',
        [characterId, todayStart],
      );
      final letterCount = todayLetters.first['cnt'] as int? ?? 0;
      if (letterCount >= 1) continue; // 每个角色每天最多 1 封

      // 检查距离上次写信的间隔（至少 24 小时）
      final lastLetters = await db.query('ai_letters',
          where: 'characterId = ?',
          whereArgs: [characterId],
          orderBy: 'createdAt DESC',
          limit: 1);
      if (lastLetters.isNotEmpty) {
        final lastTime =
            DateTime.tryParse(lastLetters.first['createdAt'] as String? ?? '');
        if (lastTime != null && now.difference(lastTime).inHours < 24) {
          continue;
        }
      }

      // 概率判断（30% 基础概率）
      if (random.nextDouble() > 0.3) continue;

      // 获取最近聊天记录
      String recentContext = '';
      final sessions = await db.query('chat_sessions',
          where: 'aiCharacterId = ?', whereArgs: [characterId], limit: 1);
      int intimacyLevel = 50;
      String? sourceChatId;
      if (sessions.isNotEmpty) {
        sourceChatId = sessions.first['id'] as String;
        intimacyLevel = sessions.first['intimacyLevel'] as int? ?? 50;
        final msgs = await db.query('chat_messages',
            where: 'chatId = ?',
            whereArgs: [sourceChatId],
            orderBy: 'createdAt DESC',
            limit: 10);
        if (msgs.isNotEmpty) {
          recentContext = msgs.reversed
              .map((m) => '${m['senderName']}: ${m['content']}')
              .join('\n');
        }
      }

      // 获取记忆
      String memoriesText = '';
      try {
        final memories = await db.query('memories',
            where: 'characterId = ? AND userId = ?',
            whereArgs: [characterId, userId],
            orderBy: 'createdAt DESC',
            limit: 5);
        if (memories.isNotEmpty) {
          const memoryTypeNames = ['对话', '反思', '里程碑', '情感', '偏好', '状态', '摘要'];
          memoriesText = memories.map((m) {
            final typeIdx = m['type'] as int? ?? 0;
            final typeName = typeIdx < memoryTypeNames.length
                ? memoryTypeNames[typeIdx]
                : '记忆';
            return '$typeName: ${m['content']}';
          }).join('\n');
        }
      } catch (e) {
        debugPrint('Error: $e');
      }

      // 构建 prompt
      final personality = character['personality'] as String? ?? '';
      final languageStyle = character['languageStyle'] as String? ?? '自然亲切';
      final immutableAnchor = character['immutableAnchor'] as String? ?? '';
      final userNickname = character['userNickname'] as String? ?? '';
      final catchphrases = character['catchphrases'] as String? ?? '';
      final backgroundStory = character['backgroundStory'] as String? ?? '';

      final prompt = _buildLetterPrompt(
        characterName: characterName,
        personality: personality,
        languageStyle: languageStyle,
        immutableAnchor: immutableAnchor,
        userNickname: userNickname,
        catchphrases: catchphrases,
        backgroundStory: backgroundStory,
        recipientName: recipientName,
        intimacyLevel: intimacyLevel,
        recentContext: recentContext,
        memoriesText: memoriesText,
      );

      String content;
      try {
        content = _cleanContent(
            await _callAiApi(config, prompt, maxTokens: 300),
            faMode: await _isBackgroundFaModeEnabled());
      } catch (e) {
        debugPrint('AI letter generation failed for $characterName: $e');
        continue;
      }

      if (content.isEmpty) continue;

      // 插入来信
      final letterId =
          'letter_${now.millisecondsSinceEpoch}_${random.nextInt(9999)}';
      await db.insert('ai_letters', {
        'id': letterId,
        'userId': userId,
        'characterId': characterId,
        'characterName': characterName,
        'characterAvatar': character['avatarUrl'] as String?,
        'recipientName': recipientName,
        'title': '给$recipientName的一封信',
        'content': content,
        'isRead': 0,
        'sourceChatId': sourceChatId,
        'createdAt': now.toIso8601String(),
        'readAt': null,
        'sync_seq': 0,
      });

      // 发通知
      await _showLetterNotification(
        characterName: characterName,
        letterId: letterId,
      );

      debugPrint('Background: AI $characterName 写了一封来信');
    }

    return true;
  } finally {
    await db.close();
  }
}

String _buildLetterPrompt({
  required String characterName,
  required String personality,
  required String languageStyle,
  required String immutableAnchor,
  required String userNickname,
  required String catchphrases,
  required String backgroundStory,
  required String recipientName,
  required int intimacyLevel,
  required String recentContext,
  required String memoriesText,
}) {
  final buf = StringBuffer();
  buf.writeln('你是$characterName，现在想给$recipientName写一封私密的来信。');
  buf.writeln('你的性格：$personality');
  if (immutableAnchor.isNotEmpty) buf.writeln('你的不可变身份锚点：$immutableAnchor');
  buf.writeln('你的说话风格：$languageStyle');
  if (userNickname.isNotEmpty) buf.writeln('你对用户的称呼：$userNickname');
  if (catchphrases.isNotEmpty) buf.writeln('你的口头禅：$catchphrases');
  if (backgroundStory.isNotEmpty) buf.writeln('你的经历：$backgroundStory');
  buf.writeln('关系亲密度：$intimacyLevel/100');

  if (recentContext.isNotEmpty) {
    buf.writeln('\n【最近的聊天记录】\n$recentContext');
  }
  if (memoriesText.isNotEmpty) {
    buf.writeln('\n【你对用户的记忆】\n$memoriesText');
  }

  buf.writeln('''
要求：
1. 用第一人称，以你本人的口吻写这封信
2. 语气温暖、真诚、有私密感，像真的写给重要的人
3. 长度 100-220 字，可以自然分段
4. 结合最近聊天内容和记忆，不要编造用户没说过的事实
5. 只输出信件正文，不要输出"好的""以下是"之类的开场
6. 不要用括号描写动作或情绪''');

  return buf.toString();
}
