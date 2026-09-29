// 后台任务拆分 part
part of '../background_service.dart';

Future<bool> _handleMomentPost(Map<String, dynamic>? inputData) async {
  if (!await _bgUsageAllowed(PrefKeys.aiUsageMomentPost)) return false;
  final db = await _openRawDb();
  try {
    // 老库 raw 连接不做自动迁移：确保 blockedUserIds 列存在再插入
    try {
      final cols = await db.rawQuery('PRAGMA table_info(moments)');
      final colNames = cols.map((c) => c['name']).toSet();
      if (!colNames.contains('blockedUserIds')) {
        await db.execute('ALTER TABLE moments ADD COLUMN blockedUserIds TEXT');
      }
    } catch (e) {
      debugPrint('moments blockedUserIds 列校验失败: $e');
    }

    final config = await _getActiveConfig(db);
    if (config == null) return false;

    final characters =
        await db.query('ai_characters', where: 'isOnline = ?', whereArgs: [1]);

    final random = Random();
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day).toIso8601String();

    for (final character in characters) {
      final characterId = character['id'] as String;

      // 检查 enableUserMomentInteraction 配置
      final interactionConfigStr =
          character['interactionConfig'] as String? ?? '{}';
      Map<String, dynamic> interactionConfig;
      try {
        interactionConfig =
            jsonDecode(interactionConfigStr) as Map<String, dynamic>;
      } catch (_) {
        interactionConfig = {};
      }
      if (interactionConfig.containsKey('enableUserMomentInteraction') &&
          interactionConfig['enableUserMomentInteraction'] == false) continue;

      // 查询最近一条 AI 动态
      final lastMoments = await db.query('moments',
          where: 'userId = ? AND isFromAI = ?',
          whereArgs: [characterId, 1],
          orderBy: 'createdAt DESC',
          limit: 1);

      double hoursSinceLastPost = 999.0;
      if (lastMoments.isNotEmpty) {
        final lastCreatedAt =
            DateTime.tryParse(lastMoments.first['createdAt'] as String? ?? '');
        if (lastCreatedAt != null) {
          hoursSinceLastPost = now.difference(lastCreatedAt).inHours.toDouble();
        }
      }

      // 最小间隔检查
      if (hoursSinceLastPost < MomentSchedulerRules.minHoursBetweenPosts)
        continue;

      // 今日上限检查
      final todayCount = await db.rawQuery(
          'SELECT COUNT(*) as cnt FROM moments WHERE userId = ? AND isFromAI = 1 AND createdAt >= ?',
          [characterId, todayStart]);
      final count = todayCount.first['cnt'] as int? ?? 0;
      if (count >= MomentSchedulerRules.maxDailyPostsPerCharacter) continue;

      // 概率判断：随时间递增
      final probability =
          (hoursSinceLastPost / MomentSchedulerRules.maxHoursBetweenPosts)
              .clamp(0.0, 1.0);
      if (random.nextDouble() > probability) continue;

      // 获取最近聊天记录用于 prompt
      String recentContext = '';
      final sessions = await db.query('chat_sessions',
          where: 'aiCharacterId = ?', whereArgs: [characterId], limit: 1);
      if (sessions.isNotEmpty) {
        final sessionId = sessions.first['id'] as String;
        final msgs = await db.query('chat_messages',
            where: 'chatId = ?',
            whereArgs: [sessionId],
            orderBy: 'createdAt DESC',
            limit: 6);
        if (msgs.isNotEmpty) {
          recentContext = msgs.reversed
              .map((m) => '${m['senderName']}: ${m['content']}')
              .join('\n');
        }
      }

      // 获取记忆
      String memoriesText = '';
      try {
        final recipientUser = await _resolveCurrentRecipient(db);
        if (recipientUser != null) {
          final userId = recipientUser['id'] as String;
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
        }
      } catch (e) {
        debugPrint('Error: $e');
      }

      // 构建 prompt
      final name = character['name'] as String? ?? '';
      final personality = character['personality'] as String? ?? '';
      final languageStyle = character['languageStyle'] as String? ?? '自然亲切';
      final evolvedStyle =
          character['evolvedStyle'] as String? ?? languageStyle;
      final immutableAnchor = character['immutableAnchor'] as String? ?? '';
      final userNickname = character['userNickname'] as String? ?? '';
      final catchphrases = character['catchphrases'] as String? ?? '';
      final backgroundStory = character['backgroundStory'] as String? ?? '';

      final sessionIntimacy = sessions.isNotEmpty
          ? (sessions.first['intimacyLevel'] as int? ?? 50)
          : 50;

      final prompt = _buildMomentPrompt(
        name: name,
        personality: personality,
        languageStyle: evolvedStyle,
        immutableAnchor: immutableAnchor,
        userNickname: userNickname,
        catchphrases: catchphrases,
        backgroundStory: backgroundStory,
        intimacyLevel: sessionIntimacy,
        recentContext: recentContext,
        memoriesText: memoriesText,
      );

      // 动态允许 1-3 句完整内容。默认 150 tokens 容易让带推理的模型在句中断开，
      // 而 moments 表和主列表都保留全文，因此在生成入口提供足够预算。
      // 输出为 JSON：content + visibility（可见范围）+ blocked（不让谁看）。
      String content = '';
      int visibility = 0; // MomentVisibility.public.index
      List<String> blockedIds = const [];
      try {
        final raw = await _callAiApi(config, prompt, maxTokens: 360);
        final parsed = _parseMomentPostJson(raw);
        content = _cleanContent(
          parsed.content,
          faMode: await _isBackgroundFaModeEnabled(),
        );
        visibility = parsed.visibility;
        if (parsed.blockedNames.isNotEmpty) {
          // 角色名 → 角色 id（“不让谁看”名单）
          final ids = <String>[];
          for (final nm in parsed.blockedNames) {
            final rows = await db.query('ai_characters',
                where: 'name = ? AND id != ?',
                whereArgs: [nm, characterId],
                limit: 1);
            if (rows.isNotEmpty) {
              ids.add(rows.first['id'] as String);
            }
          }
          blockedIds = ids;
        }
      } catch (e) {
        debugPrint('AI moment generation failed for $name: $e');
        continue;
      }

      if (content.isEmpty) continue;

      // 插入动态
      final momentId =
          'moment_${now.millisecondsSinceEpoch}_${random.nextInt(9999)}';

      await db.insert('moments', {
        'id': momentId,
        'userId': characterId,
        'userName': name,
        'userAvatar': character['avatarUrl'] as String?,
        'content': content,
        'images': '',
        'type': 0, // MomentType.text.index
        'likes': '[]',
        'comments': '[]',
        'createdAt': now.toIso8601String(),
        'updatedAt': now.toIso8601String(),
        'isFromAI': 1,
        'visibility': visibility,
        'source': 0,
        'sync_seq': 0,
      });
      // blocked ids stored if table supports; best-effort
      try {
        if (blockedIds.isNotEmpty) {
          debugPrint('Moment $momentId blocked for $blockedIds');
        }
      } catch (_) {}

      await _showMomentNotification(
        characterName: name,
        content: content,
        momentId: momentId,
      );
      debugPrint('Background: AI $name 发布动态 $momentId');
    }
    return true;
  } finally {
    await db.close();
  }
}

/// 朋友圈 prompt：按人设写 1-3 句完整动态
String _buildMomentPrompt({
  required String name,
  required String personality,
  required String languageStyle,
  required String immutableAnchor,
  required String userNickname,
  required String catchphrases,
  required String backgroundStory,
  required int intimacyLevel,
  required String recentContext,
  required String memoriesText,
}) {
  final buf = StringBuffer();
  buf.writeln('你是$name，准备发一条朋友圈动态。');
  buf.writeln('你的性格：$personality');
  if (immutableAnchor.isNotEmpty) {
    buf.writeln('你的不可变身份锚点：$immutableAnchor');
  }
  buf.writeln('你的说话风格：$languageStyle');
  if (userNickname.isNotEmpty) {
    buf.writeln('你对用户的称呼：$userNickname');
  }
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
1. 像真人发朋友圈：1-3 句完整、自然的话
2. 可分享此刻状态、心情、刚想到的事，不要像客服播报
3. 不要重复最近聊天里的原话
4. 不要用括号描写动作
5. 只输出 JSON，格式：
{"content":"动态正文","visibility":0,"blocked":[]}
visibility: 0=公开 1=仅用户可见；blocked 填不希望看到的角色名数组（可空）
''');
  return buf.toString();
}

class _MomentPostParsed {
  final String content;
  final int visibility;
  final List<String> blockedNames;
  const _MomentPostParsed({
    required this.content,
    this.visibility = 0,
    this.blockedNames = const [],
  });
}

_MomentPostParsed _parseMomentPostJson(String raw) {
  var text = raw.trim();
  // 剥代码块
  final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```', caseSensitive: false);
  final m = fence.firstMatch(text);
  if (m != null) text = m.group(1)!.trim();
  final start = text.indexOf('{');
  final end = text.lastIndexOf('}');
  if (start >= 0 && end > start) {
    text = text.substring(start, end + 1);
  }
  try {
    final map = jsonDecode(text) as Map<String, dynamic>;
    final content = (map['content'] as String?)?.trim() ?? raw.trim();
    final vis = map['visibility'];
    final blocked = map['blocked'];
    return _MomentPostParsed(
      content: content,
      visibility: vis is int ? vis : 0,
      blockedNames: blocked is List
          ? blocked.map((e) => e.toString()).toList()
          : const [],
    );
  } catch (_) {
    return _MomentPostParsed(content: raw.trim());
  }
}

