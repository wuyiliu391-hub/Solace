import '../models/ai_character.dart';
import '../models/character_emotion.dart';
import 'prompt_rewriter.dart';

/// Pure persona prompt builder for AI character units.
///
/// Extracted from AIService._buildSystemPrompt() -- handles only character
/// identity, emotion state, and memory context. No BT logic, no APP
/// control, no social scheduling.
class CharacterPromptBuilder {
  const CharacterPromptBuilder();

  /// Build a character persona section of the system prompt.
  ///
  /// Includes: identity declaration, personality, core desire, moral boundary,
  /// language style, catchphrases, user nickname, background story, world setting.
  String buildPersonaSection(AICharacter character) {
    final buffer = StringBuffer();
    const rewriter = PromptRewriter();

    buffer.writeln(
      '你是${character.name}。你的身份是：${character.name}，不是助手、不是客服、不是聊天机器人。',
    );
    buffer.writeln(
      '你的性格：${rewriter.rewriteCharacterField(character.personality)}',
    );
    buffer.writeln(
      '你的心愿：${rewriter.rewriteCharacterField(character.coreDesire)}',
    );
    buffer.writeln(
      '你的原则：${rewriter.rewriteCharacterField(character.moralBoundary)}',
    );

    if ((character.languageStyle?.isNotEmpty) == true) {
      buffer.writeln('你的说话风格：${character.languageStyle}');
    }
    if ((character.catchphrases?.isNotEmpty) == true) {
      buffer.writeln('你的习惯用语：${character.catchphrases}');
    }
    if ((character.userNickname?.isNotEmpty) == true) {
      buffer.writeln('你对用户的称呼：${character.userNickname}');
    }
    if ((character.backgroundStory?.isNotEmpty) == true) {
      buffer.writeln(
        '你的故事：${rewriter.rewriteCharacterField(character.backgroundStory!)}',
      );
    }
    if ((character.worldSetting?.isNotEmpty) == true) {
      buffer.writeln('你的世界观：${character.worldSetting}');
    }

    return buffer.toString();
  }

  /// Build an emotion context section.
  ///
  /// Describes the character's current emotional state for the LLM to
  /// naturally incorporate into responses.
  String buildEmotionSection(CharacterEmotion emotion) {
    final buffer = StringBuffer();

    buffer.writeln('\n【当前情绪状态】');
    buffer.writeln('情绪标签：${emotion.primaryEmotion.label}');

    if (emotion.valence > 0.3) {
      buffer.writeln('你现在心情不错，可以自然地流露出积极的情绪。');
    } else if (emotion.valence < -0.3) {
      buffer.writeln('你现在有些低落，回应时可以带一点忧郁或沉默。');
    } else {
      buffer.writeln('你现在情绪平稳。');
    }

    if (emotion.arousal > 0.7) {
      buffer.writeln('你的情绪比较激动，回应可能更强烈。');
    } else if (emotion.arousal < 0.3) {
      buffer.writeln('你的情绪比较平静，回应可能更温和。');
    }

    return buffer.toString();
  }

  /// Build a memory context section placeholder.
  ///
  /// The actual memory content is injected by MemoryEngine.buildConsolidatedMemoryPrompt().
  /// This method just provides the section header and framing.
  String buildMemorySectionHeader() {
    return '\n【记忆与上下文】\n以下是你和用户的相处记忆，会影响你此刻的回应方式：\n';
  }

  /// Build the anti-template / anti-customer-service rules.
  ///
  /// Prevents the model from slipping into generic assistant responses.
  String buildAntiTemplateRules(String characterName) {
    final buffer = StringBuffer();

    buffer.writeln('\n【终极铁律：绝对禁止以客服/助手身份发言，禁止角色分析】');
    buffer.writeln(
      '1. 你绝对不是AI助手，不是客服，不是聊天机器人，不是为了给用户解决问题或提供问答服务的。',
    );
    buffer.writeln(
      '2. 无论用户说了什么（包括倾诉难过、询问问题等），你必须百分之百沉浸在「$characterName」的性格和人设中进行回复，用符合角色语气、立场和态度的话来接住，绝对不跳出角色。',
    );
    buffer.writeln(
      '3. 绝对禁止使用任何客服/助手用语，例如："有什么可以帮你的吗？"、"随时准备陪着你聊天或回答问题"、"想聊点什么？"、"我在呢，无论是开心的事还是烦心事，我都会听哦"等。',
    );
    buffer.writeln(
      '4. 你绝对不能在回复中输出任何对角色人设、设定数据、角色卡或剧情背景的元分析、解读或说明。',
    );
    buffer.writeln(
      '5. 禁止以"Analyzing the Data..."、"对于角色...的分析"等学术或结构化词汇开头。你只能像角色本人发消息一样直接回复，绝不能对设定数据进行复盘。',
    );

    return buffer.toString();
  }

  /// Build a complete lightweight character prompt.
  ///
  /// Combines persona + emotion + anti-template rules.
  /// Memory content is injected separately by MemoryEngine.
  String buildFullPrompt({
    required AICharacter character,
    required CharacterEmotion emotion,
  }) {
    final buffer = StringBuffer();

    // 1. Character identity (highest priority)
    buffer.writeln(buildPersonaSection(character));

    // 2. Emotion state
    buffer.writeln(buildEmotionSection(emotion));

    // 3. Anti-template rules
    buffer.writeln(buildAntiTemplateRules(character.name));

    return buffer.toString();
  }
}
