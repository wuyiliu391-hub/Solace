import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import '../config/constants.dart';
import '../repositories/local_storage_repository.dart';

/// 日记助手 — 聊天结束后，角色自然写日记
/// 所有公开方法 fire-and-forget，不阻塞调用线程。
/// 内部有 8 秒超时保护，无视模型响应速度差异。
class DiaryHelper {

  /// 用户和某个角色刚聊完天，触发角色写一篇日记
  /// 安全：8 秒超时 + 静默失败，不阻塞 UI
  static Future<void> tryWriteAfterChat({
    required LocalStorageRepository storage,
    required String characterId,
    required String characterName,
    String? characterAvatar,
    String? sessionId,
  }) async {
    // 用户未开启自动写日记，直接跳过
    if (!storage.isAutoDiaryEnabled()) return;

    try {
      await _doWrite(
        storage: storage,
        characterId: characterId,
        characterName: characterName,
        characterAvatar: characterAvatar,
        sessionId: sessionId,
      ).timeout(const Duration(seconds: 8));
    } on TimeoutException {
      // 超时是正常情况（慢模型），静默放弃
    } catch (_) {
      // 其他错误也静默忽略
    }
  }

  static Future<void> _doWrite({
    required LocalStorageRepository storage,
    required String characterId,
    required String characterName,
    String? characterAvatar,
    String? sessionId,
  }) async {
    final character = await storage.getAICharacter(characterId);
    if (character == null) return;

    String? chatId = sessionId;
    if (chatId == null) {
      final sessions = await storage.getChatSessionsByCharacterId(characterId);
      if (sessions.isEmpty) return;
      chatId = sessions.first.id;
    }

    final messages = await storage.getChatMessages(chatId, limit: 20);
    final userMessages = messages
        .where((m) => !m.isFromAI)
        .take(5)
        .map((m) => m.content.length > 80
            ? '${m.content.substring(0, 80)}...'
            : m.content)
        .toList();
    if (userMessages.isEmpty) return;

    final config = await storage.getActiveAIConfig();
    if (config == null) return;

    // 注入法模式
    final modeFlags = StringBuffer();
    if (storage.isFaModeEnabled()) modeFlags.write('FA模式已开启。');
    if (storage.isDaoModeEnabled()) modeFlags.write('刀模式已开启。');
    if (storage.isLoverModeEnabled()) modeFlags.write('恋人模式已开启。');
    if (storage.isOpenModeEnabled()) modeFlags.write('开放模式已开启。');

    final prompt = '''
你是$characterName，一个真实存在的角色，不是AI。
$modeFlags

你刚和用户聊完天，现在想写一篇私人日记，记录此刻的心情。

刚才用户对你说的话（回忆）：
${userMessages.map((m) => '- $m').join('\n')}

请以你的身份写一篇日记，要求：
- 第一人称，像在写自己的日记本
- 表达真实的情绪感受
- 可以写你对用户说的话的感受，也可以写你此刻的心情
- 字数 40-120 字
- 最后用「心情：」标注你的心情词（如：开心、思念、平静、难过、心动、失落等）
- 直接输出日记内容，不要加标题
''';

    final baseUrl = config.baseUrl.endsWith('/')
        ? config.baseUrl.substring(0, config.baseUrl.length - 1)
        : config.baseUrl;

    final response = await http.post(
      Uri.parse('$baseUrl/chat/completions'),
      headers: {
        'Content-Type': 'application/json; charset=utf-8',
        'Authorization': 'Bearer ${config.apiKey}',
      },
      body: jsonEncode({
        'model': config.modelName,
        'messages': [
          {'role': 'user', 'content': prompt},
        ],
        'max_tokens': 300,
        'temperature': 0.9,
      }),
    );

    if (response.statusCode != 200) return;

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final content = (data['choices']?[0]?['message']?['content'] as String?)
            ?.trim() ?? '';
    if (content.isEmpty) return;

    String mood = '平静';
    final moodMatch = RegExp(r'心情[：:]\s*(\S+)').firstMatch(content);
    if (moodMatch != null) mood = moodMatch.group(1) ?? '平静';
    final cleanContent = content.replaceAll(RegExp(r'\n?心情[：:].*'), '').trim();

    final raw = storage.getString(PrefKeys.diaryEntriesV2) ?? '[]';
    final List<dynamic> entries = jsonDecode(raw);
    entries.insert(0, {
      'id': const Uuid().v4(),
      'characterId': characterId,
      'characterName': characterName,
      'characterAvatar': characterAvatar ?? character.avatarUrl,
      'content': cleanContent,
      'mood': mood,
      'moodScore': 3,
      'createdAt': DateTime.now().toIso8601String(),
    });
    await storage.setString(PrefKeys.diaryEntriesV2, jsonEncode(entries));
    debugPrint('DiaryHelper: $characterName wrote a diary entry');
  }
}
