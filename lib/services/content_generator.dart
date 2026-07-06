// 【对标来源：KouriChat-1.4.3.2 — modules/memory/content_generator.py 内容生成】
// 1:1 转译自 KouriChat ContentGenerator 类的 7 种内容生成类型
// 参考文件：modules/memory/content_generator.py

import "../models/app_config_data.dart";
import "llm_service.dart";

/// 内容生成器（对标 KouriChat ContentGenerator）
/// 支持 7 种内容类型：日记/信件/动态/备忘录/礼物/购物/状态
class ContentGenerator {
  final LlmService llmService;
  final LlmSettings settings;

  ContentGenerator({
    required this.llmService,
    required this.settings,
  });

  /// 生成日记（对标 KouriChat /diary 命令）
  Future<String> generateDiary({
    required String characterName,
    required String recentChat,
    String? mood,
  }) async {
    final prompt = '''
你是$characterName，请根据最近的对话写一篇简短的日记。
要求：
1. 以第一人称书写
2. 100-200字
3. 包含今天的心情和事件
4. 语气自然、真实

最近的对话：
$recentChat

${mood != null ? '当前心情：$mood' : ''}
''';

    final response = await llmService.chat(
      userId: 'system',
      message: prompt,
      systemPrompt: '你是一个日记生成助手。',
    );

    return response.content;
  }

  /// 生成信件（对标 KouriChat /letter 命令）
  Future<String> generateLetter({
    required String characterName,
    required String recipientName,
    required String recentChat,
  }) async {
    final prompt = '''
你是$characterName，请给$recipientName写一封简短的信。
要求：
1. 语气温暖、真诚
2. 100-200字
3. 包含对对方的关心

最近的对话：
$recentChat
''';

    final response = await llmService.chat(
      userId: 'system',
      message: prompt,
      systemPrompt: '你是一个信件生成助手。',
    );

    return response.content;
  }

  /// 生成朋友圈动态（对标 KouriChat /pyq 命令）
  Future<String> generateMoment({
    required String characterName,
    required String topic,
    String? recentChat,
  }) async {
    final prompt = '''
你是$characterName，请发布一条朋友圈动态。
主题：$topic
要求：
1. 50-150字
2. 语气轻松、自然
3. 可以包含表情符号

${recentChat != null ? '最近的对话：$recentChat' : ''}
''';

    final response = await llmService.chat(
      userId: 'system',
      message: prompt,
      systemPrompt: '你是一个朋友圈动态生成助手。',
    );

    return response.content;
  }

  /// 生成备忘录（对标 KouriChat /memo 命令）
  Future<String> generateMemo({
    required String characterName,
    required String recentChat,
  }) async {
    final prompt = '''
你是$characterName，请根据最近的对话生成一条备忘录。
要求：
1. 简洁明了
2. 记录重要的事项或约定
3. 包含时间、地点等关键信息

最近的对话：
$recentChat
''';

    final response = await llmService.chat(
      userId: 'system',
      message: prompt,
      systemPrompt: '你是一个备忘录生成助手。',
    );

    return response.content;
  }

  /// 生成礼物建议（对标 KouriChat /gift 命令）
  Future<String> generateGiftSuggestion({
    required String characterName,
    required String recipientName,
    required String recentChat,
  }) async {
    final prompt = '''
你是$characterName，请为$recipientName推荐一个礼物。
要求：
1. 根据对方的喜好和最近的对话
2. 100字以内
3. 包含推荐理由

最近的对话：
$recentChat
''';

    final response = await llmService.chat(
      userId: 'system',
      message: prompt,
      systemPrompt: '你是一个礼物推荐助手。',
    );

    return response.content;
  }

  /// 生成购物清单（对标 KouriChat /shopping 命令）
  Future<String> generateShoppingList({
    required String characterName,
    required String recentChat,
  }) async {
    final prompt = '''
你是$characterName，请根据最近的对话生成一个购物清单。
要求：
1. 列出需要购买的物品
2. 每个物品附带简短说明
3. 格式清晰

最近的对话：
$recentChat
''';

    final response = await llmService.chat(
      userId: 'system',
      message: prompt,
      systemPrompt: '你是一个购物清单生成助手。',
    );

    return response.content;
  }

  /// 生成状态更新（对标 KouriChat /state 命令）
  Future<String> generateState({
    required String characterName,
    required String recentChat,
    String? currentMood,
  }) async {
    final prompt = '''
你是$characterName，请生成一条状态更新。
要求：
1. 简短（50字以内）
2. 反映当前的状态或心情
3. 语气自然

${currentMood != null ? '当前心情：$currentMood' : ''}
最近的对话：
$recentChat
''';

    final response = await llmService.chat(
      userId: 'system',
      message: prompt,
      systemPrompt: '你是一个状态更新生成助手。',
    );

    return response.content;
  }
}

