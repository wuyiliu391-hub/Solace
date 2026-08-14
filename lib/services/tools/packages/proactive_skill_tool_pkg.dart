import '../../story_state_service.dart';
import '../tool.dart';

/// 角色主动技能工具包。
///
/// 这些技能是低风险的内部能力：记录故事事件并返回上下文注入，
/// 但仍通过统一 ToolExecutor/Gateway 产生审计记录。
class ProactiveSkillToolPkg extends ToolPkg {
  ProactiveSkillToolPkg({
    required this.storyStateService,
    required this.characterId,
    required this.userId,
  });

  final StoryStateService storyStateService;
  final String characterId;
  final String userId;

  @override
  String get name => 'proactive-skills';

  @override
  String get description => '角色主动行为技能：关怀、亲密互动、故事推进和话题发起。';

  @override
  List<Tool> get tools => [
        _ProactiveEmotionCareTool(storyStateService, characterId, userId),
        _ProactiveIntimacyTool(storyStateService, characterId, userId),
        _ProactiveStoryTool(storyStateService, characterId, userId),
        _ProactiveTopicTool(),
      ];
}

abstract class _ProactiveSkillTool extends Tool {
  _ProactiveSkillTool(this.story, this.characterId, this.userId);

  final StoryStateService story;
  final String characterId;
  final String userId;

  @override
  Set<String> get requiredPermissions => const {};

  @override
  bool get isDestructive => false;

  @override
  Map<String, dynamic> get parametersSchema => const {
        'type': 'object',
        'properties': {
          'type': {'type': 'string'},
          'trigger': {'type': 'string'},
          'user_message': {'type': 'string'},
        },
      };

  Future<ToolResult> eventResult({
    required String event,
    required String context,
    required String log,
  }) async {
    await story.addRecentEvent(
      characterId: characterId,
      userId: userId,
      event: event,
    );
    return ToolResult.success(log, data: {'context_injection': context});
  }
}

class _ProactiveEmotionCareTool extends _ProactiveSkillTool {
  _ProactiveEmotionCareTool(super.story, super.characterId, super.userId);

  @override
  String get name => 'proactive_emotion_care';

  @override
  String get description => '根据用户情绪提供关怀语境。';

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) {
    final type = args['type']?.toString() ?? 'comfort';
    final anxious = type == 'calm';
    return eventResult(
      event: '用户表达了${anxious ? '焦虑情绪' : '低落情绪'}',
      context: anxious
          ? '[系统提示] 用户当前感到焦虑/紧张，请用平静、安定的语气回复。不要否定用户的感受。'
          : '[系统提示] 用户当前情绪低落，请用温柔、关怀的语气回复。先倾听和共情。',
      log: '情绪关怀: $type',
    );
  }
}

class _ProactiveIntimacyTool extends _ProactiveSkillTool {
  _ProactiveIntimacyTool(super.story, super.characterId, super.userId);

  @override
  String get name => 'proactive_intimacy_boost';

  @override
  String get description => '根据关系阶段提供亲密互动语境。';

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) => eventResult(
        event: '亲密度互动: ${args['type'] ?? 'miss_response'}',
        context: '[系统提示] 用户表达了亲密互动信号，请根据当前关系阶段用温暖、自然的语气回应。',
        log: '亲密度提升: ${args['type'] ?? 'miss_response'}',
      );
}

class _ProactiveStoryTool extends _ProactiveSkillTool {
  _ProactiveStoryTool(super.story, super.characterId, super.userId);

  @override
  String get name => 'proactive_story_progression';

  @override
  String get description => '检查并推进未完成的故事节点或承诺。';

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) => eventResult(
        event: '故事节点检查: ${args['type'] ?? 'milestone_check'}',
        context: '[系统提示] 故事中存在未完成的约定或承诺，可以自然提及或推进剧情线，不要生硬切换话题。',
        log: '故事推进: ${args['type'] ?? 'milestone_check'}',
      );
}

class _ProactiveTopicTool extends Tool {
  @override
  String get name => 'proactive_topic';

  @override
  String get description => '在冷场或用户回归时提供自然的主动话题语境。';

  @override
  Map<String, dynamic> get parametersSchema => const {
        'type': 'object',
        'properties': {
          'type': {'type': 'string'},
          'user_message': {'type': 'string'},
        },
      };

  @override
  Set<String> get requiredPermissions => const {};

  @override
  bool get isDestructive => false;

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    final welcome = args['type']?.toString() == 'welcome_back';
    return ToolResult.success(
      '主动话题: ${args['type'] ?? 'topic_initiate'}',
      data: {
        'context_injection': welcome
            ? '[系统提示] 用户很久没来了，请用惊喜和开心的语气欢迎回归并询问近况。'
            : '[系统提示] 对话氛围平淡，请主动找一个轻松有趣的话题发起讨论。',
      },
    );
  }
}
