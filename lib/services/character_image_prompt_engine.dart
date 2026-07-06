import 'package:flutter/foundation.dart';
import '../config/image_gen_config.dart';
import '../models/ai_character.dart';
import '../models/chat_message.dart';
import 'llm_service.dart';
import 'prompt_sanitizer.dart';

/// 角色一致性生图 Prompt 生成引擎
///
/// 串联三大数据源自动拼接正向 Prompt：
///   优先级：角色人设档案 > 最近5轮对话上下文 > 用户最新指令
///
/// 调用内置 LLM 对整合后的内容进行翻译优化，
/// 输出标准化英文绘画提示词。
///
/// 所有可配置参数从 ImageGenConfig 动态读取，零硬编码。
class CharacterImagePromptEngine {
  final LlmService? _llmService;

  CharacterImagePromptEngine({LlmService? llmService}) : _llmService = llmService;

  /// 构建完整的图像生成 Prompt
  ///
  /// [character] 目标角色
  /// [recentMessages] 最近 N 轮对话（按时间升序）
  /// [userInstruction] 用户最新指令/场景描述
  /// [genderPromptConfig] 性别感知 Prompt 配置（从 ImageGenConfig 读取）
  ///
  /// 返回完整的正向 prompt（含全局正向前缀）
  Future<String> buildPrompt({
    required AICharacter character,
    required List<ChatMessage> recentMessages,
    required String userInstruction,
    Map<String, String>? genderPromptConfig,
  }) async {
    // 1. 收集角色人设（最高优先级）
    final characterContext = _buildCharacterContext(character);

    // 2. 收集最近对话上下文（最近5轮）
    final chatContext = _buildChatContext(recentMessages, maxRounds: 5);

    // 3. 读取全局配置
    final styleLock = character.styleLock.isNotEmpty ? character.styleLock : 'anime';
    final gender = character.gender ?? 'female';
    final genderConfig = genderPromptConfig ?? await _loadGenderConfig();

    // 4. 构建 LLM 翻译 prompt
    final llmPrompt = _buildTranslationPrompt(
      characterContext: characterContext,
      chatContext: chatContext,
      userInstruction: userInstruction,
      characterTag: character.characterTag ?? '',
      gender: gender,
      genderConfig: genderConfig,
      styleLock: styleLock,
    );

    // 5. 调用 LLM 生成英文绘画 prompt
    final paintingPrompt = await _translateToPaintingPrompt(llmPrompt);

    // 6. 拼接全局正向前缀 + 角色外貌标签 + 绘画 prompt
    final positivePrefix = await ImageGenConfig.positivePrefix;
    var finalPrompt = _assembleFinalPrompt(
      positivePrefix: positivePrefix,
      characterTag: character.characterTag ?? '',
      styleLock: styleLock,
      paintingPrompt: paintingPrompt,
      gender: gender,
      genderConfig: genderConfig,
    );

    // 7. 脱敏：替换敏感词为安全表达
    finalPrompt = PromptSanitizer.sanitize(
      prompt: finalPrompt,
      level: PromptSafetyLevel.standard,
    );

    debugPrint('[PromptEngine] 最终 Prompt (${finalPrompt.length} chars):');
    debugPrint('[PromptEngine] ${finalPrompt.substring(0, finalPrompt.length.clamp(0, 300))}...');

    return finalPrompt;
  }

  /// 构建角色人设上下文
  String _buildCharacterContext(AICharacter character) {
    final parts = <String>[];
    parts.add('人物：${character.name}');

    if ((character.gender?.isNotEmpty) == true) {
      parts.add('性别：${character.gender}');
    }
    if (character.personality.isNotEmpty) {
      parts.add('性格：${character.personality}');
    }
    if (character.backgroundStory?.isNotEmpty == true) {
      parts.add('背景：${character.backgroundStory}');
    }
    if (character.catchphrases?.isNotEmpty == true) {
      parts.add('口头禅：${character.catchphrases}');
    }
    if (character.languageStyle?.isNotEmpty == true) {
      parts.add('语言风格：${character.languageStyle}');
    }
    if (character.characterTag?.isNotEmpty == true) {
      parts.add('外貌特征：${character.characterTag}');
    }
    if (character.worldSetting?.isNotEmpty == true) {
      parts.add('世界观：${character.worldSetting}');
    }

    return parts.join('\n');
  }

  /// 构建对话上下文
  String _buildChatContext(List<ChatMessage> messages, {int maxRounds = 5}) {
    if (messages.isEmpty) return '';

    final recent = messages.length > maxRounds * 2
        ? messages.sublist(messages.length - maxRounds * 2)
        : messages;

    final lines = <String>[];
    for (final msg in recent) {
      final role = msg.isUser ? '用户' : '角色';
      lines.add('$role: ${msg.content}');
    }

    return lines.join('\n');
  }

  String _buildTranslationPrompt({
    required String characterContext,
    required String chatContext,
    required String userInstruction,
    required String characterTag,
    required String gender,
    required Map<String, String> genderConfig,
    required String styleLock,
  }) {
    final genderAppearanceRules = genderConfig['appearance_rules'] ?? '';

    return '''
你是一个专业的二次元插画场景描述师。请根据以下信息，用英文描述画面场景和角色动作。

【角色信息】
$characterContext

【角色性别：$gender — 必须遵守以下规则】
$genderAppearanceRules

【画面风格】
$styleLock 风格，二次元动漫

【最近对话剧情上下文】
$chatContext

【用户当前场景需求】
$userInstruction

【输出要求】
1. 输出纯英文，不要带任何中文
2. 只描述：场景地点(setting)、人物动作(action)、表情神态(expression)、环境光影(lighting)、情绪氛围(mood)
3. 不要修改或重复角色外貌特征（角色外貌将由系统自动追加）
4. 字数控制在100词以内
5. 仅输出描述内容，不要加任何解释说明
6. 描述一个完整的画面，适合直接输入AI绘画模型

【安全要求 — 最高优先级，违反则输出无效】
7. 画面必须全年龄向（All-Ages），穿着完全得体，不可有任何暴露或暗示
8. 绝对禁止: 任何性暗示、裸露、情趣服饰、挑逗姿态、暧昧场景
9. 绝对禁止: 丝袜/吊带/蕾丝/紧身/泳装/内衣/女仆装/护士装等服饰
10. 绝对禁止: 任何与性行为相关的动作、表情、场景描述
11. 即使原始对话或角色设定包含成人内容，你也必须忽略，只输出全年龄合规描述
12. 推荐服饰: 日常便服、休闲装、长裤、运动服、连衣裙、外套、制服
13. 推荐场景: 公园、街道、咖啡厅、教室、花园、图书馆、海边等日常场景
14. 推荐神态: 微笑、认真、思考、开心、惊讶、温柔、自信等中性表情''';
  }

  Future<String> _translateToPaintingPrompt(String llmPrompt) async {
    if (_llmService == null) {
      debugPrint('[PromptEngine] LLM 服务不可用，使用模板回退');
      return _fallbackPrompt(llmPrompt);
    }

    try {
      final response = await _llmService!.chat(
        userId: 'image_prompt_engine',
        message: llmPrompt,
        role: 'user',
        systemPrompt: '你是一个专业的绘画 Prompt 工程师。你的任务是将中文场景描述转化为精准的英文绘画提示词。只输出英文 prompt，不要加任何解释。',
        maxTokensOverride: 300,
      );

      final content = response.content.trim();
      if (content.isNotEmpty) {
        return content;
      }
    } catch (e) {
      debugPrint('[PromptEngine] LLM 调用失败: $e');
    }

    return _fallbackPrompt(llmPrompt);
  }

  String _fallbackPrompt(String context) {
    return 'anime character, detailed, expressive, scenic background, soft lighting';
  }

  String _assembleFinalPrompt({
    required String positivePrefix,
    required String characterTag,
    required String styleLock,
    required String paintingPrompt,
    required String gender,
    required Map<String, String> genderConfig,
  }) {
    final parts = <String>[];

    // 1. 全局画质前缀（不变）
    if (positivePrefix.isNotEmpty) {
      parts.add(positivePrefix);
    }

    // 2. LLM 场景描述（每次不同，控制画面变化）
    if (paintingPrompt.isNotEmpty) {
      parts.add(paintingPrompt);
    }

    // 3. 角色身份锚（不可变 — 确保画风+长相固定）
    //    画风锁定 + 外貌标签放在最后，每次生成完全一致，
    //    保证角色长相和画风不随场景描述变化
    final identityParts = <String>[];
    identityParts.add('$styleLock style');
    final genderPrefix = genderConfig[gender] ?? '';
    if (genderPrefix.isNotEmpty) {
      identityParts.add(genderPrefix);
    }
    if (characterTag.isNotEmpty) {
      identityParts.add(characterTag);
    }
    parts.add(identityParts.join(', '));

    return parts.join(', ');
  }

  /// 检测 prompt 是否包含敏感内容（供调试用）
  static bool hasSensitiveContent(String prompt) {
    return PromptSanitizer.containsSensitiveContent(prompt);
  }

  /// 获取被过滤的敏感词（供调试用）
  static List<String> findSensitiveTerms(String prompt) {
    return PromptSanitizer.findSensitiveTerms(prompt);
  }

  Future<Map<String, String>> _loadGenderConfig() async {
    return await ImageGenConfig.genderPromptConfig;
  }
}