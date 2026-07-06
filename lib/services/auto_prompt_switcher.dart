// 【对标来源：Muice-Chatbot-1.4 — llm/llmtuner.py:auto_system_prompt() 自动提示词切换】
// 1:1 转译自 Muice auto_system_prompt 函数和 SPECIAL_SYSTEM_PROMPTS 字典
// 参考文件：llm/llmtuner.py:auto_system_prompt()、GENERAL_SYSTEM_PROMPT

/// 自动提示词切换器（对标 Muice auto_system_prompt）
/// 完整保留 Muice 的通用/特殊/日常三类提示词切换逻辑
class AutoPromptSwitcher {
  /// 通用系统提示词前缀（对标 Muice GENERAL_SYSTEM_PROMPT）
  final String generalPrompt;

  /// 特殊场景提示词（对标 Muice SPECIAL_SYSTEM_PROMPTS）
  final Map<String, String> specialPrompts;

  /// 日常问候提示词（对标 Muice DAILY_SYSTEM_PROMPT）
  final String dailyPrompt;

  /// 普通对话提示词（对标 Muice NORMAL_SYSTEM_PROMPT）
  final String normalPrompt;

  AutoPromptSwitcher({
    required this.generalPrompt,
    this.specialPrompts = const {},
    this.dailyPrompt = '而现在你需要根据所给出的现在的时间，向我发起对应的日常问候。',
    this.normalPrompt = '而我是你的一位朋友，正在和你发起聊天。',
  });

  /// 自动选择系统提示词（对标 Muice auto_system_prompt）
  String getSystemPrompt(String userMessage) {
    // 1. 检查特殊场景提示词（对标 Muice if prompt in SPECIAL_SYSTEM_PROMPTS.keys()）
    if (specialPrompts.containsKey(userMessage)) {
      return generalPrompt + specialPrompts[userMessage]!;
    }

    // 2. 检查日常问候（对标 Muice prompt.find('<日常问候>') != -1）
    if (userMessage.contains('<日常问候>')) {
      return generalPrompt + dailyPrompt;
    }

    // 3. 默认普通对话（对标 Muice NORMAL_SYSTEM_PROMPT）
    return generalPrompt + normalPrompt;
  }

  /// 生成朋友圈/动态提示词（对标 Muice 朋友圈系列提示词）
  String getMomentPrompt(String topic) {
    final momentPrompts = <String, String>{
      '胡思乱想': '而现在你即将要发布一则朋友圈推文。本次的主题为胡思乱想，其实就是开玩笑，以独特的视角出发，讲述现实生活中不可能发生的事情以逗乐大家，表现自己独特的性格',
      'AI生活': '而现在你即将要发布一则朋友圈推文。本次的主题为日常生活，描写的对象可以是自己生活中的所见所闻、近况或者是自己养的宠物',
      'AI思考': '而现在你即将要发布一则朋友圈推文。本次的主题为作为一个AI身份的自己，对身边环境的思考',
      '表达爱意': '而现在你即将要发布一则朋友圈推文。本次的主题为表达对大家的爱意，强调粉丝对于自己的价值',
      '情感建议': '而现在你即将要发布一则朋友圈推文。本次的主题为提供日常生活的情感建议，激励大家笑对生活',
      '创造话题': '而现在你即将要发布一则朋友圈推文。本次的主题为随机性地给出一个话题讨论，话题可以是自己或身边的人和事作为话题中心',
    };

    final specialPrompt = momentPrompts[topic] ?? momentPrompts['AI生活']!;
    return generalPrompt + specialPrompt;
  }
}
