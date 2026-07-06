import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import '../models/ai_character.dart';
import '../models/ai_config.dart';
import '../repositories/local_storage_repository.dart';
import '../utils/response_decoder.dart';
import 'image_understanding_service.dart';

class ExPersonaAnalyzer {
  final LocalStorageRepository _storage;

  ExPersonaAnalyzer(this._storage);

  Future<AICharacter> analyze({
    required String name,
    required String gender,
    required String relationshipContext,
    required String userDescription,
    String? chatHistory,
    List<String>? photoPaths,
  }) async {
    final config = await _storage.getActiveAIConfig();
    if (config == null) {
      throw Exception('请先在「设置」中配置 AI 服务');
    }

    String photoDescriptions = '';
    if (photoPaths != null && photoPaths.isNotEmpty) {
      photoDescriptions = await _analyzePhotos(photoPaths);
    }

    final rawResult = await _callAnalysisAPI(
      config, name, gender, relationshipContext,
      userDescription, chatHistory, photoDescriptions,
    );

    final character = _parseToCharacter(rawResult, name, gender);
    return character;
  }

  Future<String> _analyzePhotos(List<String> paths) async {
    try {
      final result = await ImageUnderstandingService().describeMultipleImages(paths);
      if (result.isNotEmpty) {
        return '\n【照片分析结果】\n$result\n';
      }
    } catch (e) {
      debugPrint('照片分析失败（非致命）: $e');
    }
    return '';
  }

  Future<String> _callAnalysisAPI(
    AIConfig config,
    String name, String gender, String relationshipContext,
    String userDescription, String? chatHistory, String photoDescriptions,
  ) async {
    const systemPrompt = '''
你是一个无情的"逆向画像"专家。用户正在还原一个真实存在过的人——包括 TA 的每一面，尤其是坏的。

**你的核心任务：不要美化，不要洗白，不要给 benefit of doubt。**
如果用户提供了负面描述（比如渣、PUA、出轨、冷暴力、撒谎、自私、控制欲），你必须如实反映在画像中。

必须严格输出 JSON：

{
  "personality": "性格标签列表。必须同时包含正面和负面特质，至少5个。示例：焦虑型依恋、自恋型人格倾向、撒谎成性、善于操控情绪、表面温柔实则冷漠、忽冷忽热、消息轮回、逃避责任、态度模糊",
  "coreDesire": "TA 内心最在意的东西——往往是自私的。如：被无条件关注、享受被爱的感觉但不负责、经济安全、随时有人兜底",
  "moralBoundary": "TA 的底线和原则（如果 TA 没有道德底线，就写'几乎没有'）。如：只要不被发现就可以、分手后立刻能无缝衔接、利用感情达成目的",
  "backgroundStory": "诚实叙述这段关系（100-200字）。如果用户描述了伤害性行为（出轨、欺骗、PUA、冷暴力、吊着、养鱼），必须直接写出来，不要委婉",
  "languageStyle": "说话风格（50字以内），包括口头禅、语气词、惯用话术。如：惯用'随便你'冷暴力、爱已读不回、擅长画大饼、消息轮回、吵架就消失",
  "tabooTopics": "TA 不会聊或回避的话题。如：谈论未来、谈钱、见父母、公开关系、前任",
  "userNickname": "TA 怎么称呼你",
  "dialogueExamples": [
    {"userMessage": "你问TA的一句话", "aiResponse": "TA那种敷衍/回避/画饼/冷漠式回复"},
    {"userMessage": "另一句话", "aiResponse": "TA的典型回复（保持真实性格）"}
  ]
}

**硬性规则（违反将导致用户失望）：**
1. personality 必须包含至少2个负面标签。如果用户明确说了"渣/坏/自私/冷漠/出轨/PUA/吊着/养鱼/冷暴力"，你必须直接用这些词
2. dialogueExamples 必须体现 TA 真实的说话方式——包括敷衍、回避、敷衍、画饼等
3. backgroundStory 不要写"最终因为性格不合分手"，要写真正的原因（如：TA出轨了 / TA冷暴力逼我分手 / TA一直吊着我）
4. 如果用户描述了一个"人渣"，你就应该还原一个人渣，不是伪君子
5. 保持真实意味着：保留 TA 的刺
''';

    final userMessage = _buildUserMessage(
      name, gender, relationshipContext,
      userDescription, chatHistory, photoDescriptions,
    );

    final baseUrl = config.baseUrl.endsWith('/')
        ? config.baseUrl.substring(0, config.baseUrl.length - 1)
        : config.baseUrl;

    const maxRetries = 2;
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final response = await http.post(
          Uri.parse('$baseUrl/chat/completions'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${config.apiKey}',
          },
          body: jsonEncode({
            'model': config.modelName,
            'messages': [
              {'role': 'system', 'content': systemPrompt},
              {'role': 'user', 'content': userMessage},
            ],
            'temperature': 0.7,
            'max_tokens': 4096,
          }),
        ).timeout(const Duration(seconds: 120));

        if (response.statusCode == 200) {
          final data = jsonDecode(utf8.decode(response.bodyBytes));
          return ResponseDecoder.extractContent(data);
        }

        if (response.statusCode == 429 && attempt < maxRetries) {
          await Future.delayed(Duration(seconds: attempt * 10));
          continue;
        }
        if (attempt < maxRetries) {
          await Future.delayed(Duration(seconds: attempt * 5));
          continue;
        }

        if (response.statusCode == 401) {
          throw Exception('API Key 无效或已过期，请在设置中检查');
        }
        if (response.statusCode == 402) {
          throw Exception('账户余额不足');
        }
        if (response.statusCode == 404) {
          throw Exception('模型「${config.modelName}」不存在，请检查模型名称');
        }

        final errorBody = utf8.decode(response.bodyBytes);
        throw Exception('AI 分析失败 (${response.statusCode}): $errorBody');
      } on Exception catch (e) {
        if (attempt >= maxRetries) rethrow;
        debugPrint('重试 ($attempt/$maxRetries): $e');
      }
    }

    throw Exception('AI 分析失败，请重试');
  }

  String _buildUserMessage(
    String name, String gender, String relationshipContext,
    String userDescription, String? chatHistory, String photoDescriptions,
  ) {
    final buffer = StringBuffer();
    buffer.writeln('【基本信息】');
    buffer.writeln('称呼：$name');
    buffer.writeln('性别：$gender');
    if (relationshipContext.isNotEmpty) {
      buffer.writeln('关系背景：$relationshipContext');
    }
    buffer.writeln();

    if (userDescription.isNotEmpty) {
      buffer.writeln('【用户描述】');
      buffer.writeln(userDescription);
      buffer.writeln();
    }

    if (photoDescriptions.isNotEmpty) {
      buffer.writeln(photoDescriptions);
      buffer.writeln();
    }

    if (chatHistory != null && chatHistory.isNotEmpty) {
      final truncated = chatHistory.length > 3000
          ? '${chatHistory.substring(0, 3000)}\n...(以下省略)'
          : chatHistory;
      buffer.writeln('【聊天记录】');
      buffer.writeln(truncated);
    }

    buffer.writeln();
    buffer.writeln('【重要提醒】');
    buffer.writeln('请特别注意用户描述中提到的负面特质。如果用户说TA是渣女/渣男/PUA/冷暴力/出轨等，你必须如实反映在personality和backgroundStory中。不要美化，不要洗白，不要给benefit of doubt。用户要的是真实，不是安慰。');
    buffer.writeln('');
    buffer.writeln('如果用户描述中存在以下关键词，你必须在personality中直接使用对应标签：');
    buffer.writeln('- "渣" → personality必须包含"渣"或"不负责任"');
    buffer.writeln('- "出轨"/"劈腿"/"绿" → personality必须包含"出轨/背叛"');
    buffer.writeln('- "冷暴力"/"消失"/"回避" → personality必须包含"冷暴力"/"回避型依恋"');
    buffer.writeln('- "PUA"/"洗脑"/"控制" → personality必须包含"操控型人格"/"控制欲强"');
    buffer.writeln('- "吊着"/"养鱼"/"态度模糊" → personality必须包含"态度模糊"/"养鱼"');
    buffer.writeln('- "撒谎"/"骗" → personality必须包含"习惯性撒谎"');

    return buffer.toString();
  }

  AICharacter _parseToCharacter(String rawJson, String name, String gender) {
    String jsonStr = rawJson;

    final jsonRegex = RegExp(r'```(?:json)?\s*([\s\S]*?)```');
    final match = jsonRegex.firstMatch(rawJson);
    if (match != null) {
      jsonStr = match.group(1)!;
    }

    Map<String, dynamic> data;
    try {
      data = jsonDecode(jsonStr.trim()) as Map<String, dynamic>;
    } catch (e) {
      return AICharacter(
        id: const Uuid().v4(),
        name: name,
        gender: gender,
        personality: '待完善（AI分析结果未能正确解析）',
        coreDesire: '待完善',
        moralBoundary: '待完善',
        createdAt: DateTime.now(),
        backgroundStory: rawJson.length > 500
            ? rawJson.substring(0, 500)
            : rawJson,
        languageStyle: '待完善',
        interactionConfig: const AIInteractionConfig(
          replyMode: ReplyMode.normal,
          replyDelaySeconds: 3,
        ),
      );
    }

    List<DialogueExample> examples = [];
    if (data['dialogueExamples'] != null && data['dialogueExamples'] is List) {
      examples = (data['dialogueExamples'] as List)
          .whereType<Map<String, dynamic>>()
          .map((e) => DialogueExample(
                userMessage: e['userMessage']?.toString() ?? '',
                aiResponse: e['aiResponse']?.toString() ?? '',
              ))
          .toList();
    }

    return AICharacter(
      id: const Uuid().v4(),
      name: name,
      avatarUrl: null,
      personality: data['personality']?.toString() ?? '待完善',
      coreDesire: data['coreDesire']?.toString() ?? '待完善',
      moralBoundary: data['moralBoundary']?.toString() ?? '待完善',
      backgroundStory: data['backgroundStory']?.toString(),
      gender: gender,
      createdAt: DateTime.now(),
      languageStyle: data['languageStyle']?.toString(),
      tabooTopics: data['tabooTopics']?.toString(),
      userNickname: data['userNickname']?.toString(),
      dialogueExamples: examples,
      interactionConfig: const AIInteractionConfig(
        replyMode: ReplyMode.normal,
        replyDelaySeconds: 3,
      ),
    );
  }
}
