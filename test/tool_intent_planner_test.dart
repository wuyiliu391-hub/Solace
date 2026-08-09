import 'package:flutter_test/flutter_test.dart';
import 'package:solace/models/chat_message.dart';
import 'package:solace/models/app_config_data.dart';
import 'package:solace/models/tool_intent_decision.dart';
import 'package:solace/services/recent_tool_context.dart';
import 'package:solace/services/tool_intent_planner.dart';
import 'package:solace/services/llm_service.dart';
import 'package:solace/services/tools/tool.dart';
import 'package:solace/services/tools/tool_registry.dart';

class _ReadTool extends Tool {
  @override
  String get name => 'get_battery_info';

  @override
  String get description => '读取电量';

  @override
  Map<String, dynamic> get parametersSchema => const {
        'type': 'object',
        'properties': <String, dynamic>{},
      };

  @override
  Set<String> get requiredPermissions => const {};

  @override
  bool get isDestructive => false;

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async =>
      ToolResult.success('电量 80%');
}

class _ReadPkg extends ToolPkg {
  @override
  String get name => 'test';

  @override
  String get description => 'test';

  @override
  List<Tool> get tools => [_ReadTool()];
}

ChatMessage _traceMessage(DateTime createdAt, String tool) => ChatMessage(
      id: 'trace',
      chatId: 'chat',
      senderId: 'system_tool',
      senderName: '工具执行',
      content: '执行了 1 个工具',
      isSystem: true,
      createdAt: createdAt,
      metadata: {
        'isToolTrace': true,
        'toolTrace': [
          {
            'tool': tool,
            'args': <String, dynamic>{},
            'result': '电量 80%，未充电（电池）',
            'success': true,
          },
        ],
      },
    );

void main() {
  test('extracts a recent successful read-only tool context', () {
    final now = DateTime(2026, 8, 8, 12);
    final context = RecentToolContext.fromMessages(
      [
        _traceMessage(
            now.subtract(const Duration(minutes: 1)), 'get_battery_info')
      ],
      now: now,
    );

    expect(context, isNotNull);
    expect(context!.toolName, 'get_battery_info');
    expect(context.isReadOnly, isTrue);
    expect(context.isUsableAt(now), isTrue);
  });

  test('does not continue destructive or expired tool traces', () {
    final now = DateTime(2026, 8, 8, 12);
    expect(
      RecentToolContext.fromMessages(
        [
          _traceMessage(
              now.subtract(const Duration(minutes: 9)), 'get_battery_info')
        ],
        now: now,
      ),
      isNull,
    );
    expect(
      RecentToolContext.fromMessages(
        [_traceMessage(now, 'open_app')],
        now: now,
      ),
      isNull,
    );
  });

  test('explicit refresh phrases are handled locally', () {
    for (final message in [
      '哥哥再看一次吗',
      '哥哥再来一次',
      '再看看呗',
      '再查一下',
      '再帮我看看',
      '重新看一下',
    ]) {
      expect(RecentToolContext.isContinuationRequest(message), isTrue);
    }
    expect(RecentToolContext.isContinuationRequest('她看看我的手机'), isFalse);
    expect(RecentToolContext.isContinuationRequest('不用再看了'), isFalse);
  });

  test('detail-follow-up phrases are treated as continuation', () {
    for (final message in [
      '具体有什么 爸爸可以告诉我吗',
      '详细说说什么情况',
      '还有哪些要看看的',
    ]) {
      expect(RecentToolContext.isContinuationRequest(message), isTrue,
          reason: message);
    }
    expect(RecentToolContext.isContinuationRequest('看看电量'), isFalse);
  });

  test('natural continuation is a planner candidate', () {
    final context = RecentToolContext(
      toolName: 'get_battery_info',
      args: const {},
      result: '电量 80%',
      createdAt: DateTime.now(),
    );
    expect(ToolIntentPlanner.shouldPlan('再看看呗', context), isTrue);
    expect(ToolIntentPlanner.shouldPlan('你好呀', null), isFalse);
    expect(ToolIntentPlanner.shouldPlan('她看看我的手机', null), isFalse);
  });

  test('planner validation keeps only known low-risk tools', () {
    final registry = ToolRegistry()..register(_ReadPkg());
    final planner = ToolIntentPlanner(
      llm: LlmService(settings: const LlmSettings()),
      registry: registry,
    );
    final recent = RecentToolContext(
      toolName: 'get_battery_info',
      args: const {},
      result: '电量 80%',
      createdAt: DateTime.now(),
    );

    final valid = planner.validate(
      const ToolIntentDecision(
        kind: ToolIntentKind.continueToolTask,
        toolName: 'get_battery_info',
        confidence: 0.9,
        isReadOnly: true,
      ),
      recent,
    );
    expect(valid.kind, ToolIntentKind.continueToolTask);

    final unknown = planner.validate(
      const ToolIntentDecision(
        kind: ToolIntentKind.directTool,
        toolName: 'delete_app',
        confidence: 0.99,
      ),
      recent,
    );
    expect(unknown.kind, ToolIntentKind.conversation);
  });
}
