import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/ai_character.dart';
import '../models/chat_message.dart';
import '../config/image_gen_config.dart';
import '../config/gender_prompt_config.dart';

/// 图像 Prompt 生成引擎（v2 重构版 — 角色一致性全链路）
///
/// 串联三大数据源自动拼接正向 Prompt：
///   角色人设档案 > 最近 N 轮对话上下文 > 用户最新指令
///
/// v2 新增：
///   - LLM 翻译优化（中文场景→英文绘画提示词）
///   - 性别感知解剖排除规则（GenderPromptDefaults）
///   - 角色外貌标签强制锁定
///   - 4K 分辨率配置
///
/// 所有可配置参数从 ImageGenConfig / GenderPromptDefaults 动态读取，零硬编码。
class ImagePromptEngine {
  ImagePromptEngine._();

  // ─── LLM 服务注入（可选，启用后使用 LLM 翻译优化） ───
  static dynamic _llmService;

  /// 注入 LLM 服务以启用智能 Prompt 翻译
  static void setLlmService(dynamic service) {
    _llmService = service;
  }

  /// 生成文生图 Prompt
  static Future<String> buildPrompt({
    required AICharacter character,
    required String userMessage,
    List<ChatMessage>? recentMessages,
    String memoryContext = '',
  }) async {
    final buf = StringBuffer();

    // ─── 1. 全局正向前缀（从配置读取） ───
    buf.write(await ImageGenConfig.positivePrefix);
    buf.write(', ');

    // ─── 2. 角色身份锚定（性别感知 + 外貌锁定） ───
    buf.write(await _buildIdentityAnchor(character));
    buf.write(', ');

    // ─── 3. 角色外貌标签（从 characterTag 字段读取，强制锁定） ───
    if (character.characterTag != null && character.characterTag!.isNotEmpty) {
      buf.write(character.characterTag);
      buf.write(', ');
    }

    // ─── 4. 最近对话上下文（场景/情绪提取） ───
    if (recentMessages != null && recentMessages.isNotEmpty) {
      final contextStr = _extractSceneContext(recentMessages);
      if (contextStr.isNotEmpty) {
        buf.write(contextStr);
        buf.write(', ');
      }
    }

    // ─── 5. 记忆上下文 ───
    if (memoryContext.isNotEmpty) {
      buf.write('context from memories: $memoryContext');
      buf.write(', ');
    }

    // ─── 6. 用户指令 ───
    buf.write(userMessage);

    // ─── 7. 性别解剖排除规则 ───
    final anatomyExclude = await _getGenderAnatomyExclude(character);
    if (anatomyExclude.isNotEmpty) {
      // 追加到负面词中（由调用方拼接 negative_prompt）
    }

    return buf.toString();
  }

  /// 构建图生图 Prompt（用于参考图模式）
  static Future<String> buildImg2ImgPrompt({
    required AICharacter character,
    required String userMessage,
    List<ChatMessage>? recentMessages,
    String memoryContext = '',
  }) async {
    final base = await buildPrompt(
      character: character,
      userMessage: userMessage,
      recentMessages: recentMessages,
      memoryContext: memoryContext,
    );

    // 追加构图保持指令
    return '$base, while preserving the original character identity, '
        'facial features, hair style, and overall composition';
  }

  /// LLM 翻译优化：中文场景描述 → 标准化英文绘画提示词
  ///
  /// 返回优化后的英文 prompt，LLM 不可用时回退到原始 prompt
  static Future<String> translateWithLlm({
    required AICharacter character,
    required String userMessage,
    List<ChatMessage>? recentMessages,
    String memoryContext = '',
    bool isImg2Img = false,
  }) async {
    // 先用基础方法构建 prompt
    final basePrompt = isImg2Img
        ? await buildImg2ImgPrompt(
            character: character,
            userMessage: userMessage,
            recentMessages: recentMessages,
            memoryContext: memoryContext,
          )
        : await buildPrompt(
            character: character,
            userMessage: userMessage,
            recentMessages: recentMessages,
            memoryContext: memoryContext,
          );

    // 如果没有 LLM 服务，直接返回基础 prompt
    if (_llmService == null) {
      debugPrint('[PromptEngine] LLM 服务未注入，使用基础 prompt');
      return basePrompt;
    }

    try {
      final genderConfig = GenderPromptDefaults.defaults[character.gender ?? 'female']
          ?? GenderPromptDefaults.defaults['female']!;
      final appearanceRules = genderConfig['appearance_rules'] ?? '';
      final anatomyRules = genderConfig['anatomy_rules'] ?? '';

      final translationPrompt = '''
You are a professional anime illustration Prompt engineer. Convert the following into a precise English painting prompt.

【Character Info】
Name: ${character.name}, Gender: ${character.gender ?? 'female'}
Personality: ${character.personality}
Appearance Tags (MUST preserve exactly): ${character.characterTag ?? 'N/A'}

【Gender Rules】
$appearanceRules
Avoid: $anatomyRules

【Style】
${character.styleLock} style, anime

【Scene Request】
$userMessage

【Output Requirements】
1. English only, no Chinese
2. Include: setting, action, expression, lighting, outfit, mood
3. Character appearance MUST match appearance tags exactly
4. Under 100 words
5. Only output the prompt, no explanations''';

      final response = await _llmService!.chat(
        userId: 'image_prompt_engine',
        message: translationPrompt,
        role: 'user',
        systemPrompt: 'You are a professional anime Prompt engineer. Convert scene descriptions into precise English painting prompts. Only output English prompt text.',
        maxTokensOverride: 300,
      );

      final content = response.content.trim();
      if (content.isNotEmpty && content.length > 20) {
        // 拼接全局前缀 + LLM 优化后的 prompt
        final prefix = await ImageGenConfig.positivePrefix;
        if (character.characterTag != null && character.characterTag!.isNotEmpty) {
          return '$prefix, ${character.characterTag}, $content';
        }
        return '$prefix, $content';
      }
    } catch (e) {
      debugPrint('[PromptEngine] LLM 翻译失败，回退基础 prompt: $e');
    }

    return basePrompt;
  }

  /// 构建角色身份锚定描述（性别感知 v2）
  static Future<String> _buildIdentityAnchor(AICharacter character) async {
    final buf = StringBuffer();
    final gender = (character.gender ?? '').toLowerCase();

    final isMale = gender == 'male' || gender == '男';
    final isFemale = gender == 'female' || gender == '女';

    // 角色名
    buf.write('${character.name}');

    // 从 GenderPromptDefaults 读取性别感知前缀
    final genderConfig = GenderPromptDefaults.defaults[gender]
        ?? GenderPromptDefaults.defaults['female']!;
    final genderPrefix = genderConfig['prefix'] ?? '';

    if (genderPrefix.isNotEmpty) {
      buf.write(', $genderPrefix');
    } else if (isMale) {
      buf.write(', male character, masculine features, ');
      buf.write('sharp jawline, broad shoulders');
    } else if (isFemale) {
      buf.write(', female character, feminine features, ');
      buf.write('soft facial features, delicate build');
    } else {
      buf.write(', androgynous character');
    }

    // 性格（仅提取外貌相关的气质词汇）
    if (character.personality.isNotEmpty) {
      buf.write(', ${character.personality}');
    }

    return buf.toString();
  }

  /// 获取性别解剖排除词（用于拼接 negative_prompt）
  static Future<String> _getGenderAnatomyExclude(AICharacter character) async {
    final gender = character.gender ?? 'female';
    final genderConfig = GenderPromptDefaults.defaults[gender]
        ?? GenderPromptDefaults.defaults['female']!;
    return genderConfig['anatomy_rules'] ?? '';
  }

  /// 获取增强后的 negative prompt（含性别排除词）
  static Future<String> getEnhancedNegativePrompt(AICharacter character) async {
    final base = await ImageGenConfig.negativePrompt;
    final genderExclude = await _getGenderAnatomyExclude(character);
    if (genderExclude.isNotEmpty) {
      return '$base, $genderExclude';
    }
    return base;
  }

  /// 从最近对话中提取场景/情绪上下文
  static String _extractSceneContext(List<ChatMessage> messages) {
    final recent = messages.length > 5
        ? messages.sublist(messages.length - 5)
        : messages;

    final contexts = <String>[];
    for (final msg in recent) {
      if (msg.content.isEmpty) continue;
      if (!msg.isUser && msg.content.length > 5) {
        final snippet = msg.content.length > 50
            ? msg.content.substring(0, 50)
            : msg.content;
        contexts.add(snippet);
      }
    }

    if (contexts.isEmpty) return '';
    return 'current scene context: ${contexts.join('; ')}';
  }
}