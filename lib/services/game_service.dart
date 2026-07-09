import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import '../models/ai_character.dart';
import '../models/ai_config.dart';
import '../repositories/local_storage_repository.dart';
import 'memory_engine.dart';
import 'prompt_rewriter.dart';

/// 娱乐互动游戏 AI 引擎
///
/// 代替硬编码静态列表，由 AI 实时生成角色专属的互动内容。
/// 每个游戏调用 LLM 获取角色个性化的回复，让游戏"活"起来。
class GameService {
  final LocalStorageRepository _storage;
  final MemoryEngine _memoryEngine;
  final Random _random = Random();

  GameService(this._storage) : _memoryEngine = MemoryEngine(_storage);

  /// 获取当前激活的 AI 配置（游戏用小模型直接对话）
  Future<AIConfig?> _getConfig() async {
    return _storage.getActiveAIConfig();
  }

  /// 构建角色基础信息串（注入到 prompt 中）
  String _buildCharacterContext(AICharacter character) {
    final rewriter = const PromptRewriter();
    return '你是${character.name}。\n'
        '性格：${rewriter.rewriteCharacterField(character.personality)}\n'
        '心愿：${rewriter.rewriteCharacterField(character.coreDesire)}\n'
        '原则：${rewriter.rewriteCharacterField(character.moralBoundary)}\n'
        '说话风格：${character.languageStyle ?? "自然亲切"}';
  }

  // ════════════════════════════════════════
  // 1. 真心话大冒险
  // ════════════════════════════════════════

  /// AI 角色出一个真心话或大冒险题目
  Future<String> generateGamePrompt({
    required AICharacter character,
    required bool isTruth,
  }) async {
    final charCtx = _buildCharacterContext(character);
    final prompt = '''
$charCtx

你现在在和用户玩「真心话大冒险」游戏。
用户抽到了【${isTruth ? "真心话" : "大冒险"}】。

请以你的身份，出一个${isTruth ? "真心话问题" : "大冒险挑战"}。
要求：
- 问题/挑战要符合你的性格
- 带有你说话的风格和语气
- 内容互动性强，让对方感受到是"你在问他"
- 长度 10-30 字，一句话
- 直接输出问题/挑战内容，不要加引号或前缀
''';

    return _callAI(prompt, maxTokens: 100);
  }

  /// AI 角色对用户的回答做出反应
  Future<String> reactToAnswer({
    required AICharacter character,
    required String question,
    required String userAnswer,
  }) async {
    final charCtx = _buildCharacterContext(character);
    final prompt = '''
$charCtx

你刚才问了用户一个问题：「$question」
用户的回答是：「$userAnswer」

请以你的身份，根据用户的回答，做出自然的反应。
要求：
- 符合你的性格
- 可以调侃、感动、惊讶、吐槽等
- 长度 15-40 字，一句话
''';

    return _callAI(prompt, maxTokens: 100);
  }

  // ════════════════════════════════════════
  // 2. 默契度测试
  // ════════════════════════════════════════

  /// AI 生成一个偏好类问题（用户和角色各自回答）
  Future<String> generatePreferenceQuestion({
    required AICharacter character,
  }) async {
    final charCtx = _buildCharacterContext(character);
    final prompt = '''
$charCtx

你正在和用户玩「默契度测试」游戏。
请根据你的性格和喜好，出一个二选一或开放式偏好问题，
然后你自己先默默想好答案。
例如："周末你喜欢出去逛还是宅在家里？"

要求：
- 问题与你性格/生活相关
- 简短明了，15-25字
- 直接输出问题，不要前缀
''';

    return _callAI(prompt, maxTokens: 100);
  }

  /// AI 根据问题给出 TA 的答案
  Future<String> generateAIAnswer({
    required AICharacter character,
    required String question,
  }) async {
    final charCtx = _buildCharacterContext(character);
    final prompt = '''
$charCtx

问题：「$question」

请以你的身份，诚实地回答这个问题。
只需给出简短答案（5-20字），符合你的性格。
''';

    return _callAI(prompt, maxTokens: 80);
  }

  /// AI 对答题结果做评价
  Future<String> evaluateMatch({
    required AICharacter character,
    required String question,
    required String aiAnswer,
    required String userAnswer,
  }) async {
    final matched = aiAnswer.trim().toLowerCase() ==
        userAnswer.trim().toLowerCase();
    final charCtx = _buildCharacterContext(character);
    final prompt = '''
$charCtx

默契度测试中，问题是：「$question」
你的答案是：「$aiAnswer」
对方的答案是：「$userAnswer」

${matched ? "双方的答案一致！" : "答案不一样。"}

请以你的身份，对这次答题结果做出有趣的反应（15-30字）。
${matched ? '表达开心、惊喜或\u201c我们果然很搭\u201d的感觉。' : '可以调侃或表示惊讶。'}
''';

    return _callAI(prompt, maxTokens: 100);
  }

  // ════════════════════════════════════════
  // 3. 心有灵犀
  // ════════════════════════════════════════

  /// AI 想一个词让用户猜（返回词本身，不出现在任意输出中）
  Future<String> generateSecretWord({
    required AICharacter character,
  }) async {
    final charCtx = _buildCharacterContext(character);
    final prompt = '''
$charCtx

你在和用户玩「心有灵犀」猜词游戏。
请你默默地想一个词，这个词与你的性格、喜好或你们之间的回忆相关。
不要告诉用户这个词是什么。

请只输出这个词本身（1-3个字，中文）。
''';

    return _callAI(prompt, maxTokens: 20, temperature: 1.2);
  }

  /// AI 对用户的猜测给提示（是/否/接近）
  Future<String> respondToGuess({
    required AICharacter character,
    required String secretWord,
    required String userGuess,
    int attemptCount = 1,
  }) async {
    final correct = secretWord.contains(userGuess) ||
        userGuess.contains(secretWord);
    if (correct) {
      return '猜对了！就是「$secretWord」！你真了解我～';
    }

    final charCtx = _buildCharacterContext(character);
    final prompt = '''
$charCtx

你在心里想了一个词：「$secretWord」
对方猜的是：「$userGuess」
这是第 $attemptCount 次猜测。

对方猜错了。请给出一个提示，让对方更容易猜中。
要求：
- 提示要自然，像是你在说话
- 不能直接说出答案
- 长度 10-25 字
- 语气符合你的性格
''';

    return _callAI(prompt, maxTokens: 80);
  }

  // ════════════════════════════════════════
  // 4. 角色印象
  // ════════════════════════════════════════

  /// AI 根据记忆和角色性格，生成对用户的印象评价
  Future<String> generateImpression({
    required AICharacter character,
    required String userId,
  }) async {
    // 获取最近的记忆作为参考
    final memories = await _memoryEngine.loadPrivateMemories(
      character.id, userId,
    );
    final memorySnippets = memories
        .take(8)
        .map((m) => '- ${m.content}')
        .join('\n');

    final charCtx = _buildCharacterContext(character);
    final hasMemories = memorySnippets.isNotEmpty;

    final prompt = '''
$charCtx

${hasMemories
  ? "你对用户有以下记忆（参考）：\n$memorySnippets"
  : "你和用户还没有太多共同回忆。"}

请以你的身份，写一段对用户的印象评价。
要求：
- 要像真人说话，不是干巴巴的描述
- ${hasMemories ? "结合具体记忆内容，让评价有事实依据" : "根据你现在对 TA 的第一印象"}
- 表达出你的真实感受（喜欢、好奇、依赖等）
- 字数 50-100 字
- 直接输出内容，不要前缀
''';

    return _callAI(prompt, maxTokens: 300, temperature: 0.9);
  }

  // ════════════════════════════════════════
  // LLM 调用
  // ════════════════════════════════════════

  /// 通用 LLM 文本生成调用
  Future<String> _callAI(
    String prompt, {
    int maxTokens = 100,
    double temperature = 0.8,
  }) async {
    final config = await _getConfig();
    if (config == null) return _fallbackResponse();

    try {
      final baseUrl = config.baseUrl.endsWith('/')
          ? config.baseUrl.substring(0, config.baseUrl.length - 1)
          : config.baseUrl;
      final url = Uri.parse('$baseUrl/chat/completions');

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
          'Authorization': 'Bearer ${config.apiKey}',
        },
        body: jsonEncode({
          'model': config.modelName,
          'messages': [
            {'role': 'user', 'content': prompt},
          ],
          'max_tokens': maxTokens,
          'temperature': temperature,
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final text = _extractText(data);
        if (text.isNotEmpty) return text;
      }
    } catch (e) {
      debugPrint('GameService AI call failed: $e');
    }

    return _fallbackResponse();
  }

  String _extractText(dynamic data) {
    if (data is Map<String, dynamic>) {
      if (data['choices'] != null && data['choices'].isNotEmpty) {
        final choice = data['choices'][0];
        if (choice['message'] != null && choice['message']['content'] != null) {
          return (choice['message']['content'] as String).trim();
        }
        if (choice['text'] != null) {
          return (choice['text'] as String).trim();
        }
      }
      if (data['response'] != null) return data['response'] as String;
      if (data['content'] is String) return data['content'] as String;
    }
    return '';
  }

  /// 兜底回复（AI 调用失败时的静态回退）
  String _fallbackResponse() {
    final fallbacks = [
      '嗯…让我想想怎么回答你。',
      '这个问题嘛…其实我也没想好。',
      '你觉得呢？我很好奇你的想法。',
      '被你问到了…下次再告诉你吧。',
      '嘿嘿，你猜～',
    ];
    return fallbacks[_random.nextInt(fallbacks.length)];
  }
}
