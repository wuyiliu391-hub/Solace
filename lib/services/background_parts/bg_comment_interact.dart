// 后台任务拆分 part
part of '../background_service.dart';

Future<bool> _handleCommentReply(Map<String, dynamic>? inputData) async {
  if (!await _bgUsageAllowed(PrefKeys.aiUsageCommentReply)) return false;
  final momentId = inputData?['momentId'] as String?;
  final commentId = inputData?['commentId'] as String?;
  final characterId = inputData?['characterId'] as String?;
  final intimacyLevel = inputData?['intimacyLevel'] as int? ?? 50;

  if (momentId == null || commentId == null || characterId == null) {
    return false;
  }

  final db = await _openRawDb();
  try {
    final config = await _getActiveConfig(db);
    if (config == null) return false;

    // 查询动态
    final momentRows =
        await db.query('moments', where: 'id = ?', whereArgs: [momentId]);
    if (momentRows.isEmpty) return false;
    final moment = momentRows.first;

    // 只处理普通动态
    final momentSource = moment['source'] as int? ?? 0;
    if (momentSource != 0) return false;

    // 解析 comments
    final commentsJson = moment['comments'] as String? ?? '[]';
    List<dynamic> comments;
    try {
      comments = jsonDecode(commentsJson) as List<dynamic>;
    } catch (_) {
      comments = [];
    }

    // 找到目标评论
    Map<String, dynamic>? targetComment;
    for (final c in comments) {
      final comment = c as Map<String, dynamic>;
      if (comment['id'] == commentId) {
        targetComment = comment;
        break;
      }
    }
    if (targetComment == null) return false;

    // 防重复：仅跳过「已对同一条 commentId 回复过」的情况，允许多轮互评
    final targetUserId = targetComment['userId'] as String? ?? '';
    final targetUserName = targetComment['userName'] as String? ?? '';
    for (final c in comments) {
      final comment = c as Map<String, dynamic>;
      if (comment['userId'] == characterId &&
          comment['replyToCommentId'] == commentId) {
        debugPrint('AI 已回复过该条评论($commentId)，跳过');
        return true;
      }
    }
    // 同一用户连发时：若最近 2 分钟内已回过同一用户，短暂冷却
    final now = DateTime.now();
    for (final c in comments.reversed) {
      final comment = c as Map<String, dynamic>;
      if (comment['userId'] != characterId) continue;
      if (comment['replyToUserId'] != targetUserId) continue;
      final created = DateTime.tryParse(comment['createdAt'] as String? ?? '');
      if (created != null && now.difference(created).inMinutes < 2) {
        debugPrint('AI 近期已回复过该用户，冷却中');
        return true;
      }
      break;
    }

    // 获取角色信息
    final charRows = await db
        .query('ai_characters', where: 'id = ?', whereArgs: [characterId]);
    if (charRows.isEmpty) return false;
    final character = charRows.first;

    // 构建评论 prompt
    final momentContent = moment['content'] as String? ?? '';
    final charName = character['name'] as String? ?? '';
    final personality = character['personality'] as String? ?? '';
    final languageStyle = character['languageStyle'] as String? ?? '自然亲切';
    final evolvedStyle = character['evolvedStyle'] as String? ?? languageStyle;
    final immutableAnchor = character['immutableAnchor'] as String? ?? '';
    final userNickname = character['userNickname'] as String? ?? '';
    final catchphrases = character['catchphrases'] as String? ?? '';

    final prompt = _buildCommentPrompt(
      characterName: charName,
      personality: personality,
      languageStyle: evolvedStyle,
      immutableAnchor: immutableAnchor,
      userNickname: userNickname,
      catchphrases: catchphrases,
      momentContent: momentContent,
      commentContent: targetComment['content'] as String? ?? '',
      commenterName: targetUserName,
      intimacyLevel: intimacyLevel,
    );

    String replyContent;
    try {
      replyContent = _cleanContent(
          await _callAiApi(config, prompt, temperature: 0.85, maxTokens: 80),
          faMode: await _isBackgroundFaModeEnabled());
    } catch (e) {
      debugPrint('AI comment reply generation failed: $e');
      return false;
    }

    if (replyContent.isEmpty) return false;

    // 添加回复（带 replyToCommentId 支持多轮线程）
    final reply = {
      'id': 'comment_${DateTime.now().millisecondsSinceEpoch}_ai',
      'userId': characterId,
      'userName': charName,
      'replyToUserId': targetUserId,
      'replyToUserName': targetUserName,
      'replyToCommentId': commentId,
      'content': replyContent,
      'createdAt': DateTime.now().toIso8601String(),
    };
    comments.add(reply);

    // 更新动态
    await db.update(
        'moments',
        {
          'comments': jsonEncode(comments),
          'updatedAt': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [momentId]);

    await _showCommentNotification(
      characterName: charName,
      content: replyContent,
      momentId: momentId,
    );

    debugPrint('Background: AI $charName 回复了评论');

    // AI→AI 多轮：这条回复若是回给另一个 AI（或回在 AI 动态下），让对方接着回
    try {
      final updatedRows = await db.query('moments',
          where: 'id = ?', whereArgs: [momentId], limit: 1);
      if (updatedRows.isNotEmpty) {
        final updatedMoment = Moment.fromMap(updatedRows.first);
        if (updatedMoment.comments.isNotEmpty) {
          await MomentInteractionService.instance.onAiCommentAdded(
            storage: LocalStorageRepository(),
            moment: updatedMoment,
            comment: updatedMoment.comments.last,
          );
        }
      }
    } catch (e) {
      debugPrint('AI→AI 多轮编排失败: $e');
    }
    return true;
  } finally {
    await db.close();
  }
}

String _buildCommentPrompt({
  required String characterName,
  required String personality,
  required String languageStyle,
  required String immutableAnchor,
  required String userNickname,
  required String catchphrases,
  required String momentContent,
  required String commentContent,
  required String commenterName,
  required int intimacyLevel,
}) {
  String intimacyTone;
  if (intimacyLevel >= 80) {
    intimacyTone = '非常亲密，可以开玩笑、用亲切的称呼';
  } else if (intimacyLevel >= 60) {
    intimacyTone = '比较亲密，可以关心、调侃';
  } else if (intimacyLevel >= 30) {
    intimacyTone = '普通朋友，保持礼貌友善';
  } else {
    intimacyTone = '不太熟悉，保持客气';
  }

  return '''你是$characterName，正在和${userNickname.isNotEmpty ? userNickname : commenterName}在朋友圈评论区聊天（可多轮继续聊）。

你的性格：$personality
${immutableAnchor.isNotEmpty ? '你的不可变身份锚点：$immutableAnchor' : ''}
你的说话风格：$languageStyle
${catchphrases.isNotEmpty ? '你的口头禅：$catchphrases' : ''}
关系亲密度：$intimacyLevel/100（$intimacyTone）

相关动态："$momentContent"
对方最新评论："$commentContent"

请回复这条评论，要求：
1. 以你的性格和与对方的关系来回复，像真人回评论
2. 自然真诚，1-2句话，可接话、反问、调侃，推动多轮
3. 要引用评论的具体内容，不要泛泛而谈
4. 不要用括号描写动作或情绪
5. 只输出回复内容''';
}

// ─── Handler: AI 互动用户动态 ───

Future<bool> _handleMomentInteract(Map<String, dynamic>? inputData) async {
  if (!await _bgUsageAllowed(PrefKeys.aiUsageMomentInteract)) return false;
  final momentId = inputData?['momentId'] as String?;
  final characterId = inputData?['characterId'] as String?;
  final intimacyLevel = inputData?['intimacyLevel'] as int? ?? 50;

  if (momentId == null || characterId == null) return false;

  final db = await _openRawDb();
  try {
    final config = await _getActiveConfig(db);
    if (config == null) return false;

    // 查询动态（并发安全：写入前重新读取）
    final momentRows =
        await db.query('moments', where: 'id = ?', whereArgs: [momentId]);
    if (momentRows.isEmpty) return false;
    final moment = momentRows.first;

    // 只处理普通动态
    final momentSource = moment['source'] as int? ?? 0;
    if (momentSource != 0) return false;

    final isFromAI = moment['isFromAI'] as int? ?? 0;
    final visibilityIdx = moment['visibility'] as int? ?? 0;

    // 私密动态：仅作者自己可见，不互动
    if (visibilityIdx == 1) return false;

    // 作者「不让谁看」名单：被拉黑的角色不互动
    final blockedRaw = moment['blockedUserIds'] as String? ?? '[]';
    try {
      final blocked = (jsonDecode(blockedRaw) as List)
          .map((e) => e.toString())
          .toList();
      if (blocked.contains(characterId)) return false;
    } catch (_) {}

    // 查询角色
    final charRows = await db
        .query('ai_characters', where: 'id = ?', whereArgs: [characterId]);
    if (charRows.isEmpty) return false;
    final character = charRows.first;

    final isOnline = character['isOnline'] as int? ?? 0;
    if (isOnline != 1) return false;

    // 解析 likes 和 comments
    final likesJson = moment['likes'] as String? ?? '[]';
    final commentsJson = moment['comments'] as String? ?? '[]';
    List<dynamic> likes;
    List<dynamic> comments;
    try {
      likes = jsonDecode(likesJson) as List<dynamic>;
    } catch (_) {
      likes = [];
    }
    try {
      comments = jsonDecode(commentsJson) as List<dynamic>;
    } catch (_) {
      comments = [];
    }

    final random = Random();
    final shouldLike = random.nextDouble() < MomentRules.aiLikeProbability;
    final shouldComment =
        random.nextDouble() < MomentRules.aiCommentProbability;

    if (!shouldLike && !shouldComment) return true;

    final charName = character['name'] as String? ?? '';
    final charId = character['id'] as String;

    // 点赞
    if (shouldLike) {
      final alreadyLiked =
          likes.any((l) => (l as Map<String, dynamic>)['userId'] == charId);
      if (!alreadyLiked) {
        likes.add({
          'userId': charId,
          'userName': charName,
          'createdAt': DateTime.now().toIso8601String(),
        });
      }
    }

    // 评论
    if (shouldComment) {
      final momentContent = moment['content'] as String? ?? '';
      final personality = character['personality'] as String? ?? '';
      final languageStyle = character['languageStyle'] as String? ?? '自然亲切';
      final evolvedStyle =
          character['evolvedStyle'] as String? ?? languageStyle;
      final immutableAnchor = character['immutableAnchor'] as String? ?? '';
      final traitSummary = character['currentAnchor'] as String? ?? '';
      final userNickname = character['userNickname'] as String? ?? '';
      final catchphrases = character['catchphrases'] as String? ?? '';

      final prompt = _buildUserMomentCommentPrompt(
        characterName: charName,
        personality: personality,
        languageStyle: evolvedStyle,
        immutableAnchor: immutableAnchor,
        traitSummary: traitSummary,
        userNickname: userNickname,
        catchphrases: catchphrases,
        momentContent: momentContent,
        intimacyLevel: intimacyLevel,
      );

      try {
        final commentContent = AIService.filterHallucinatedNames(
          _cleanContent(
              await _callAiApi(config, prompt,
                  temperature: 0.85, maxTokens: 80),
              faMode: await _isBackgroundFaModeEnabled()),
          userNickname,
        );
        if (commentContent.isNotEmpty) {
          comments.add({
            'id': 'comment_${DateTime.now().millisecondsSinceEpoch}_ai',
            'userId': charId,
            'userName': charName,
            'content': commentContent,
            'createdAt': DateTime.now().toIso8601String(),
          });
        }
      } catch (e) {
        debugPrint('AI moment comment generation failed: $e');
      }
    }

    // 更新动态
    await db.update(
        'moments',
        {
          'likes': jsonEncode(likes),
          'comments': jsonEncode(comments),
          'updatedAt': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [momentId]);

    debugPrint(
        'Background: AI $charName 互动了动态 ${shouldLike ? "点赞" : ""} ${shouldComment ? "评论" : ""}');

    // AI→AI 多轮：评论后让被评论方（动态作者/被回复的 AI）接着回
    if (shouldComment && isFromAI == 1) {
      try {
        final updatedRows = await db.query('moments',
            where: 'id = ?', whereArgs: [momentId], limit: 1);
        if (updatedRows.isNotEmpty) {
          final updatedMoment = Moment.fromMap(updatedRows.first);
          if (updatedMoment.comments.isNotEmpty) {
            await MomentInteractionService.instance.onAiCommentAdded(
              storage: LocalStorageRepository(),
              moment: updatedMoment,
              comment: updatedMoment.comments.last,
            );
          }
        }
      } catch (e) {
        debugPrint('AI→AI 多轮编排失败: $e');
      }
    }
    return true;
  } finally {
    await db.close();
  }
}

String _buildUserMomentCommentPrompt({
  required String characterName,
  required String personality,
  required String languageStyle,
  required String immutableAnchor,
  required String traitSummary,
  required String userNickname,
  required String catchphrases,
  required String momentContent,
  required int intimacyLevel,
}) {
  String intimacyTone;
  if (intimacyLevel >= 80) {
    intimacyTone = '非常亲密，可以开玩笑、用亲切的称呼';
  } else if (intimacyLevel >= 60) {
    intimacyTone = '比较亲密，可以关心、调侃';
  } else if (intimacyLevel >= 30) {
    intimacyTone = '普通朋友，保持礼貌友善';
  } else {
    intimacyTone = '不太熟悉，保持客气';
  }

  return '''你是$characterName，看到了${userNickname.isNotEmpty ? userNickname : "用户"}发的朋友圈。

你的性格：$personality
${immutableAnchor.isNotEmpty ? '你的不可变身份锚点：$immutableAnchor' : ''}
$traitSummary
你的说话风格：$languageStyle
${catchphrases.isNotEmpty ? '你的口头禅：$catchphrases' : ''}
关系亲密度：$intimacyLevel/100（$intimacyTone）

对方的朋友圈内容："$momentContent"

请写一条评论，要求：
1. 以你的性格和与对方的关系来评论
2. 自然真诚，1-2句话
3. 要引用动态的具体内容来评论
4. 不要用括号描写动作或情绪
5. 只输出评论内容''';
}

// ─── 原有聊天消息生成 ───
