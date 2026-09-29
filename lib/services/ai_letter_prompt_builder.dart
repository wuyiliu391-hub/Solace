import '../models/ai_character.dart';
import '../models/chat_message.dart';
import '../models/memory.dart';
import '../utils/message_sanitizer.dart';

class AILetterPromptBuilder {
  AILetterPromptBuilder._();

  static String buildIncomingLetterPrompt({
    required AICharacter character,
    required String recipientName,
    required List<Memory> memories,
    required List<ChatMessage> chatHistory,
    String? triggerInstruction,
  }) {
    final buffer = StringBuffer();
    _writeRules(buffer);
    _writeGroundingContext(
      buffer,
      character: character,
      recipientName: recipientName,
      memories: memories,
      chatHistory: chatHistory,
    );

    buffer.writeln('\n【本次任务】');
    buffer.writeln('你是${character.name}，请给$recipientName写一封私密来信。');
    if (triggerInstruction != null && triggerInstruction.trim().isNotEmpty) {
      buffer.writeln(triggerInstruction.trim());
    }
    buffer.writeln('这封信必须像${character.name}真正写下的文字，内容要从上面的设定、记忆库和最近对话中自然生长出来。');
    buffer.writeln('【输出格式 - 必须严格遵守】');
    buffer.writeln('直接输出信件正文，不要包含以下任何内容：');
    buffer.writeln('- 不要输出思考过程、分析、推理');
    buffer.writeln('- 不要输出"好的""嗯""我来""首先""然后"等思维引导词');
    buffer.writeln('- 不要重复角色设定、身份信息、写作要求');
    buffer.writeln('- 不要使用 Markdown 格式、列表、分隔线');
    buffer.writeln('- 不要添加任何解释、备注、问候前缀');
    buffer.writeln('- 也不要输出"亲爱的"或信件标题格式——直接写第一句话');
    buffer.writeln('只输出信件正文，立即开始：');
    return buffer.toString();
  }

  static String buildReplyPrompt({
    required AICharacter character,
    required String senderName,
    required String userLetterTitle,
    required String userLetterContent,
    required List<Memory> memories,
    required List<ChatMessage> chatHistory,
  }) {
    final buffer = StringBuffer();
    _writeRules(buffer);
    _writeGroundingContext(
      buffer,
      character: character,
      recipientName: senderName,
      memories: memories,
      chatHistory: chatHistory,
    );

    buffer.writeln('\n【用户来信】');
    buffer.writeln('标题：$userLetterTitle');
    buffer.writeln(userLetterContent.trim());
    buffer.writeln('\n【本次任务】');
    buffer.writeln(
        '你是${character.name}。读完$senderName写给你的信后，用你的口吻给$senderName回一封信。');
    buffer.writeln('必须回应用户信里真正提到的内容，同时结合上面的角色设定、记忆库和最近对话。');
    buffer.writeln('不要把回信写成泛泛的安慰、模板情书或无依据的承诺。');
    buffer.writeln('【输出格式 - 必须严格遵守】');
    buffer.writeln('直接输出回信正文，不要包含：');
    buffer.writeln('- 不要输出思考过程、分析、推理');
    buffer.writeln('- 不要输出"好的""嗯"等思维引导词');
    buffer.writeln('- 不要重复角色设定或写作要求');
    buffer.writeln('- 不要使用 Markdown');
    buffer.writeln('- 不要添加任何解释或前后缀');
    buffer.writeln('只输出回信正文，立即开始：');
    return buffer.toString();
  }

  static void _writeRules(StringBuffer buffer) {
    buffer.writeln('【信件写作硬规则】');
    buffer.writeln('- 你必须依据角色设定、记忆库和最近对话写信，不能脱离这些依据随意发挥。');
    buffer.writeln('- 可以自然引用1-3条真实记忆或最近聊天细节，让信像延续你们关系的一部分。');
    buffer.writeln('- 禁止编造记忆库和最近对话中没有出现过的共同经历、约定、纪念日、称呼或用户状态。');
    buffer.writeln('- 如果没有对应记忆，就承认当下的感受和关系，不要假装想起不存在的往事。');
    buffer.writeln('- 保持角色本人的性格、立场、语言风格和边界，不要写成通用AI模板。');
    buffer.writeln('- 不要解释你参考了设定或记忆，不要提到“记忆库”“prompt”“模型”。');
  }

  static void _writeGroundingContext(
    StringBuffer buffer, {
    required AICharacter character,
    required String recipientName,
    required List<Memory> memories,
    required List<ChatMessage> chatHistory,
  }) {
    buffer.writeln('\n【角色设定】');
    buffer.writeln('姓名：${character.name}');
    _writeOptional(buffer, '性格', character.personality);
    _writeOptional(buffer, '核心渴望', character.coreDesire);
    _writeOptional(buffer, '道德边界', character.moralBoundary);
    _writeOptional(buffer, '背景故事', character.backgroundStory);
    _writeOptional(buffer, '世界观', character.worldSetting);
    _writeOptional(buffer, '语言风格', character.languageStyle);
    _writeOptional(buffer, '口头禅', character.catchphrases);
    _writeOptional(buffer, '当前状态', character.currentStatus);
    _writeOptional(buffer, '对用户的称呼', character.userNickname);
    _writeOptional(buffer, '用户对你的称呼', character.userAlias);
    _writeOptional(buffer, '用户人设', character.userPersona);
    _writeOptional(buffer, '禁忌话题', character.tabooTopics);
    buffer.writeln('当前收信人：$recipientName');

    final safeMemories = memories
        .where((m) =>
            m.type != MemoryType.rollingSummary || m.content.trim().isNotEmpty)
        .where((m) => !m.keywords.contains('__merged'))
        .where((m) => !MessageSanitizer.isLikelyUnreadableGibberish(m.content))
        .take(12)
        .toList();
    if (safeMemories.isNotEmpty) {
      buffer.writeln('\n【可引用的记忆库内容】');
      for (final memory in safeMemories) {
        buffer
            .writeln('- ${_memoryLabel(memory)}：${_trim(memory.content, 180)}');
      }
    }

    final visibleHistory = chatHistory
        .where((m) => !m.isHidden && !m.isGhost && m.content.trim().isNotEmpty)
        .where((m) => !MessageSanitizer.isLikelyUnreadableGibberish(m.content))
        .take(10)
        .toList()
        .reversed;
    if (visibleHistory.isNotEmpty) {
      buffer.writeln('\n【最近对话片段】');
      for (final message in visibleHistory) {
        final speaker = message.isFromAI ? character.name : recipientName;
        buffer.writeln('$speaker：${_trim(message.content, 120)}');
      }
    }

    if (character.dialogueExamples.isNotEmpty) {
      buffer.writeln('\n【说话方式示例】');
      for (final example in character.dialogueExamples.take(3)) {
        if (example.userMessage.trim().isEmpty ||
            example.aiResponse.trim().isEmpty) {
          continue;
        }
        buffer.writeln('$recipientName：${_trim(example.userMessage, 80)}');
        buffer.writeln('${character.name}：${_trim(example.aiResponse, 100)}');
      }
    }
  }

  static void _writeOptional(StringBuffer buffer, String label, String? value) {
    final text = value?.trim();
    if (text == null || text.isEmpty) return;
    buffer.writeln('$label：$text');
  }

  static String _memoryLabel(Memory memory) {
    switch (memory.type) {
      case MemoryType.conversation:
        return '对话记忆';
      case MemoryType.reflection:
        return '反思记忆';
      case MemoryType.milestone:
        return '重要节点';
      case MemoryType.emotion:
        return '情绪记忆';
      case MemoryType.preference:
        return '偏好记忆';
      case MemoryType.state:
        return '近期状态';
      case MemoryType.rollingSummary:
        return '长期摘要';
    }
  }

  static String _trim(String text, int maxLength) {
    final normalized = MessageSanitizer.sanitizeFinal(text).trim();
    if (normalized.length <= maxLength) return normalized;
    return '${normalized.substring(0, maxLength)}……';
  }
}
