// 后台任务拆分 part
part of '../background_service.dart';

Future<Database> _openRawDb() async {
  final dbPath = await getDatabasesPath();
  final path = p.join(dbPath, 'solace.db');
  return openDatabase(path, singleInstance: false);
}

Future<Map<String, dynamic>?> _getActiveConfig(Database db) async {
  final rows = await db.query('ai_configs',
      where: 'isActive = ?', whereArgs: [1], limit: 1);
  return rows.isNotEmpty ? rows.first : null;
}

/// 解析后台任务的收件人/归属用户。
///
/// 历史 bug（信箱来信丢失根因）：直接 `users LIMIT 1` 盲取第一行，
/// 多账号场景（首启自动建的 local_user + QQ 登录账号）会把来信写到
/// 错误账号名下 —— 信箱按当前登录用户查询永远查不到，通知却照发。
///
/// 优先级：前台登录态 currentUserId → 最近登录的用户 → 首行（单用户兜底）。
Future<Map<String, dynamic>?> _resolveCurrentRecipient(Database db) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final currentUserId = prefs.getString(PrefKeys.currentUserId);
    if (currentUserId != null && currentUserId.isNotEmpty) {
      final rows = await db.query('users',
          where: 'id = ?', whereArgs: [currentUserId], limit: 1);
      if (rows.isNotEmpty) return rows.first;
    }
  } catch (e) {
    debugPrint('Background: 读取当前登录用户失败: $e');
  }
  try {
    final rows =
        await db.query('users', orderBy: 'lastLoginAt DESC', limit: 1);
    if (rows.isNotEmpty) return rows.first;
  } catch (e) {
    debugPrint('Background: 回退最近登录用户失败: $e');
  }
  return null;
}

Future<String> _callAiApi(
  Map<String, dynamic> config,
  String prompt, {
  double temperature = 0.9,
  int maxTokens = 150,
}) async {
  final baseUrl = (config['baseUrl'] as String).endsWith('/')
      ? (config['baseUrl'] as String)
          .substring(0, (config['baseUrl'] as String).length - 1)
      : config['baseUrl'] as String;

  final modePrompt = await _buildBackgroundGlobalModePrompt();
  final novelMode = await _isBackgroundNovelModeEnabled();
  final configuredMaxTokens = config['maxTokens'] as int?;
  // 后台动态不能因为全局配置较小而在句中截断；调用方的预算是最低值。
  final effectiveMaxTokens = novelMode
      ? (configuredMaxTokens == null
          ? maxTokens
          : configuredMaxTokens > maxTokens
              ? configuredMaxTokens
              : maxTokens)
      : maxTokens;

  final response = await http
      .post(
        Uri.parse('$baseUrl/chat/completions'),
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
          'Accept': 'application/json',
          'Accept-Charset': 'utf-8',
          'Authorization': 'Bearer ${config['apiKey']}',
        },
        body: jsonEncode({
          'model': config['modelName'],
          'messages': [
            {
              'role': 'system',
              'content':
                  '$modePrompt\n\n你必须只使用简体中文回复。不要输出繁体中文、乱码、编码转义、日志、时间戳或解释说明。',
            },
            {'role': 'user', 'content': prompt}
          ],
          'temperature': temperature,
          'max_tokens': effectiveMaxTokens,
        }),
      )
      .timeout(const Duration(seconds: 30));

  if (response.statusCode == 200) {
    final rawBody = await ResponseDecoder.decode(
      response.headers['content-type'],
      response.bodyBytes,
    );
    final data = jsonDecode(rawBody);
    final text = ResponseDecoder.extractVisibleContent(data);
    final normalized = _normalizeBackgroundAiText(text);
    if (normalized.isNotEmpty) return normalized;
  }
  throw Exception('API returned empty response');
}

Future<bool> _isBackgroundNovelModeEnabled() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(PrefKeys.chatStyleMode) ?? false;
}

Future<bool> _isBackgroundFaModeEnabled() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(PrefKeys.faModeEnabled) ?? false;
}

Future<String> _buildBackgroundGlobalModePrompt() async {
  final prefs = await SharedPreferences.getInstance();
  return buildGlobalModePromptText(
    pureAiMode: prefs.getBool(PrefKeys.pureAiModeEnabled) ?? false,
    novelMode: prefs.getBool(PrefKeys.chatStyleMode) ?? false,
    loverMode: prefs.getBool(PrefKeys.loverModeEnabled) ?? false,
    openMode: prefs.getBool(PrefKeys.openModeEnabled) ?? false,
    faMode: prefs.getBool(PrefKeys.faModeEnabled) ?? false,
    daoMode: prefs.getBool(PrefKeys.daoModeEnabled) ?? false,
    scope: '后台AI任务',
  );
}

String _cleanContent(String content, {bool faMode = false}) {
  var result = _normalizeBackgroundAiText(content);
  // 法模式下保留括号动作描写（对齐单聊 ai_service 清洗规则）
  if (!faMode) {
    result = result.replaceAll(RegExp(r'（[^）]*）'), '');
    result = result.replaceAll(RegExp(r'\([^)]*\)'), '');
    result = result.replaceAll(RegExp(r'\*[^*]*\*'), '');
    result = result.replaceAll(RegExp(r'\[[^\]]*\]'), '');
  }
  result = _normalizeBackgroundAiText(result);
  return result;
}

