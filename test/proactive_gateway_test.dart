import 'package:flutter_test/flutter_test.dart';
import 'package:solace/services/proactive_action_executor.dart';
import 'package:solace/services/tools/agent_tool_gateway.dart';
import 'package:solace/services/tools/tool.dart';
import 'package:solace/services/tools/tool_registry.dart';

void main() {
  test('proactive executor routes internal skill through the tool gateway',
      () async {
    final story = _FakeStoryStateService();
    final registry = ToolRegistry();
    registry.register(_ProactiveSkillPkg(story));
    final gateway = AgentToolGateway(registry: registry);
    final executor = ProactiveActionExecutor(
      storyStateService: story,
      characterId: 'char-1',
      userId: 'user-1',
      toolGateway: gateway,
    );

    final result = await executor.execute(
      ProactiveActionType.emotionCare,
      {'type': 'comfort'},
      '我今天好难过',
    );

    expect(result.success, isTrue);
    expect(result.executedThroughGateway, isTrue);
    expect(result.toolExecution?.toolName, 'proactive_emotion_care');
    expect(story.events, contains('用户表达了低落情绪'));
  });

  test('proactive executor fails closed when a skill is not registered',
      () async {
    final story = _FakeStoryStateService();
    final executor = ProactiveActionExecutor(
      storyStateService: story,
      characterId: 'char-1',
      userId: 'user-1',
      toolGateway: AgentToolGateway(registry: ToolRegistry()),
    );

    final result = await executor.execute(
      ProactiveActionType.proactiveTopic,
      {'type': 'topic_initiate'},
      '...',
    );

    expect(result.success, isFalse);
    expect(result.executedThroughGateway, isTrue);
    expect(result.toolExecution?.result.errorCode, 'UNKNOWN_TOOL');
  });

  test('registered proactive skills are non-destructive and permission-free',
      () {
    final pkg = _ProactiveSkillPkg(_FakeStoryStateService());

    expect(
        pkg.tools.map((tool) => tool.name), contains('proactive_emotion_care'));
    for (final tool in pkg.tools) {
      expect(tool.requiredPermissions, isEmpty);
      expect(tool.isDestructive, isFalse);
    }
  });
}

class _FakeStoryStateService {
  final events = <String>[];

  Future<void> addRecentEvent({
    required String characterId,
    required String userId,
    required String event,
  }) async {
    events.add(event);
  }
}

class _ProactiveSkillPkg extends ToolPkg {
  _ProactiveSkillPkg(this.story);
  final _FakeStoryStateService story;

  @override
  String get name => 'proactive-test-skills';

  @override
  String get description => 'test proactive skills';

  @override
  List<Tool> get tools => [_EmotionSkill(story)];
}

class _EmotionSkill extends Tool {
  _EmotionSkill(this.story);
  final _FakeStoryStateService story;

  @override
  String get name => 'proactive_emotion_care';

  @override
  String get description => 'test emotion care skill';

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
    await story.addRecentEvent(
      characterId: 'char-1',
      userId: 'user-1',
      event: '用户表达了低落情绪',
    );
    return ToolResult.success(
      'emotion care skill executed',
      data: const {
        'context_injection': '[系统提示] 用户当前情绪低落，请用温柔、关怀的语气回复。',
      },
    );
  }
}
