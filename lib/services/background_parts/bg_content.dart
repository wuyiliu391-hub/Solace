// 后台任务拆分 part
part of '../background_service.dart';

Future<String> _generateBgContent(
  Database db,
  Map<String, dynamic>? config,
  Map<String, dynamic> character,
  int intimacyLevel,
) async {
  if (config == null) throw Exception('No active AI config');

  final name = character['name'] as String? ?? '';
  final personality = character['personality'] as String? ?? '';
  final languageStyle = character['languageStyle'] as String? ?? '自然亲切';
  final evolvedStyle = character['evolvedStyle'] as String? ?? languageStyle;
  final immutableAnchor = character['immutableAnchor'] as String? ?? '';
  final traitSummary = character['currentAnchor'] as String? ?? '';
  final userNickname = character['userNickname'] as String? ?? '';
  final backgroundStory = character['backgroundStory'] as String? ?? '';
  final currentStatus = character['currentStatus'] as String? ?? '';

  final sessionId = character['defaultSessionId'] as String?;
  String recentContext = '';
  String recentProactiveContext = '';
  if (sessionId != null) {
    try {
      final rows = await db.query(
        'chat_messages',
        where: 'chatId = ? AND senderId LIKE ?',
        whereArgs: [sessionId, 'ai_$name%'],
        orderBy: 'createdAt DESC',
        limit: 10,
      );
      if (rows.isNotEmpty) {
        recentContext = rows.reversed
            .take(5)
            .map((r) => '${r['senderName']}: ${r['content']}')
            .join('\n');
      }
      // 获取最近的主动消息用于去重
      final proactiveRows = rows.where((r) {
        final metadata = r['metadata'] as String?;
        return metadata != null && metadata.contains('"isProactive":true');
      }).toList();
      if (proactiveRows.isNotEmpty) {
        recentProactiveContext =
            proactiveRows.take(5).map((r) => '- ${r['content']}').join('\n');
      }
    } catch (e) {
      debugPrint('Error: $e');
    }
  }

  final now = DateTime.now();
  String timeContext;
  final hour = now.hour;
  if (hour < 6) {
    timeContext = '深夜（凌晨$hour点）';
  } else if (hour < 9) {
    timeContext = '早晨（$hour点左右）';
  } else if (hour < 12) {
    timeContext = '上午（$hour点左右）';
  } else if (hour < 14) {
    timeContext = '中午（$hour点左右）';
  } else if (hour < 18) {
    timeContext = '下午（$hour点左右）';
  } else if (hour < 21) {
    timeContext = '傍晚（$hour点左右）';
  } else {
    timeContext = '夜晚（$hour点左右）';
  }

  final prompt = '''
你是$name。
你的性格：$personality
${immutableAnchor.isNotEmpty ? '你的不可变身份锚点：$immutableAnchor' : ''}
$traitSummary
你的说话风格：$evolvedStyle
${userNickname.isNotEmpty ? '你对用户的称呼：$userNickname' : ''}
${backgroundStory.isNotEmpty ? '你的经历：$backgroundStory' : ''}
${currentStatus.isNotEmpty ? '你当前的状态：$currentStatus' : ''}

【当前时间】$timeContext
关系亲密度：$intimacyLevel/100
${recentContext.isNotEmpty ? '\n【最近的聊天记录】\n$recentContext' : ''}
${recentProactiveContext.isNotEmpty ? '\n【你之前主动发过的消息（不要重复这些话题）】\n$recentProactiveContext' : ''}

你现在想主动给用户发一条消息。

要求：
1. 完全以你的性格和当前心情来决定说什么，不要模仿任何固定话术
2. 像真人给朋友发微信——想到什么说什么，可以分享你此刻的状态、心情、或者突然想到的事
3. 你可以聊任何话题：你正在做的事、刚看到的东西、你的心情、你们之间的事、一个突然的念头
4. 不要用括号描写动作或情绪
5. 只输出消息内容，1-2句话
6. 不要问"在吗""吃了吗""今天怎么样"这种千篇一律的问候，说点有你个人特色的话
7. 绝对不要重复你之前主动发过的话题，每次要有新鲜感
8. 如果最近已经主动说过类似的话，宁可输出[SILENT]也不要重复

如果觉得现在不适合打扰用户，输出：[SILENT]
''';

  return _callAiApi(
    config,
    prompt,
    temperature: ApiDefaults.proactiveTemp,
    maxTokens: ApiDefaults.proactiveMaxTokens,
  );
}
