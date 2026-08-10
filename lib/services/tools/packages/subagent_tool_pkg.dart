import '../../llm_service.dart';
import '../tool.dart';

/// 轻量子代理：独立上下文完成分析/审查，再把结果返回主 Agent。
class SubagentToolPkg extends ToolPkg {
  final LlmService llm;

  SubagentToolPkg(this.llm);

  @override
  String get name => '子代理';

  @override
  String get description => '将独立的分析、审查或规划任务交给子代理，避免污染主角色上下文。';

  @override
  List<Tool> get tools => [_DelegateSubagentTool(llm)];
}

class _DelegateSubagentTool extends Tool {
  final LlmService llm;
  _DelegateSubagentTool(this.llm);

  @override
  String get name => 'run_agent';

  @override
  String get description => '运行一个只读子代理。适合代码审查、方案比较、错误分析和任务拆解。';

  @override
  Map<String, dynamic> get parametersSchema => {
        'type': 'object',
        'properties': {
          'task': {'type': 'string'},
          'context': {'type': 'string'},
        },
        'required': ['task'],
      };

  @override
  Set<String> get requiredPermissions => const {};

  @override
  bool get isDestructive => false;

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    final task = args['task']?.toString().trim() ?? '';
    if (task.isEmpty)
      return ToolResult.error('子代理任务为空。', errorCode: 'INVALID_TASK');
    final context = args['context']?.toString().trim() ?? '';
    final response = await llm.chat(
      userId: 'subagent',
      message: task,
      systemPrompt:
          '你是 Solace 的只读子代理。只做分析、审查、规划和事实归纳，不修改文件、不执行命令。输出简洁、结构化、可供主代理直接采用的结果。',
      extraContext: context.isEmpty
          ? null
          : [
              {'role': 'user', 'content': '补充上下文：$context'}
            ],
      maxTokensOverride: 1800,
    );
    if (response.error != null) {
      return ToolResult.error(response.error!, errorCode: 'SUBAGENT_FAILED');
    }
    return ToolResult.success(response.content, data: {'subagent': true});
  }
}
