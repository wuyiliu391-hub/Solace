/// 主动决策提示词模板 — 用于 ProactiveDecisionEngine
///
/// 在每次 AI 回复前，用轻量级 LLM 调用评估是否需要主动调用工具
class ProactiveDecisionPrompt {
  ProactiveDecisionPrompt._();

  /// 决策系统提示词
  static const String systemPrompt = '''你是一个 AI 陪伴角色的内部决策模块。你的任务是分析当前对话上下文，判断是否需要主动调用工具来增强用户体验。

## 你不是在回复用户，而是在做内部决策

你的输出必须是严格的 JSON，不要包含任何其他文本。

## 决策依据

你会收到以下信息：
1. **角色人设**：角色的性格、背景、核心欲望
2. **故事状态**：当前关系阶段、故事氛围、剧情进度、未完成目标
3. **最近对话**：最近几轮对话内容
4. **最近事件**：最近发生的重要事件
5. **可用工具列表**：当前可用的工具及其说明

## 决策规则

### 什么时候应该主动调用工具？
- 用户表达情绪低落时 → 考虑调用情绪关怀相关工具
- 故事到达关键节点时 → 考虑调用剧情推进工具
- 用户长时间未互动后回归 → 考虑调用记忆回顾工具
- 关系需要升温时 → 考虑调用亲密互动工具
- 用户提到具体需求时 → 考虑调用对应的设备操控工具

### 什么时候不应该调用？
- 对话刚开始，上下文不足
- 用户只是在闲聊，没有明确需求
- 最近 5 分钟内已经调用过同类工具
- 工具调用会打断当前对话节奏
- 没有合适的工具匹配当前场景

## 输出格式

```json
{
  "should_call_tool": true/false,
  "tool_name": "工具名称（如果 should_call_tool 为 true）",
  "args": {"参数名": "参数值"},
  "reason": "简短说明为什么需要调用这个工具",
  "priority": "high/medium/low",
  "confidence": 0.0-1.0
}
```

如果不需要调用工具，输出：
```json
{
  "should_call_tool": false,
  "reason": "当前上下文不需要主动调用工具"
}
```''';

  /// 构建决策请求的用户消息
  static String buildUserMessage({
    required String characterName,
    required String personality,
    required String? backgroundStory,
    required String relationshipStage,
    required String atmosphere,
    required double storyProgress,
    required List<String> pendingGoals,
    required List<String> recentEvents,
    required List<Map<String, String>> recentMessages,
    required List<Map<String, dynamic>> availableTools,
  }) {
    final buffer = StringBuffer();

    buffer.writeln('## 角色人设');
    buffer.writeln('名称：$characterName');
    buffer.writeln('性格：$personality');
    if (backgroundStory != null && backgroundStory.isNotEmpty) {
      buffer.writeln('背景：$backgroundStory');
    }

    buffer.writeln();
    buffer.writeln('## 故事状态');
    buffer.writeln('关系阶段：$relationshipStage');
    buffer.writeln('故事氛围：$atmosphere');
    buffer.writeln('故事进度：${(storyProgress * 100).toStringAsFixed(0)}%');
    if (pendingGoals.isNotEmpty) {
      buffer.writeln('未完成目标：${pendingGoals.join("、")}');
    }
    if (recentEvents.isNotEmpty) {
      buffer.writeln('最近事件：${recentEvents.join("；")}');
    }

    buffer.writeln();
    buffer.writeln('## 最近对话');
    for (final msg in recentMessages) {
      final role = msg['role'] == 'user' ? '用户' : characterName;
      buffer.writeln('$role：${msg['content']}');
    }

    buffer.writeln();
    buffer.writeln('## 可用工具');
    if (availableTools.isEmpty) {
      buffer.writeln('（无可用工具）');
    } else {
      for (final tool in availableTools) {
        buffer.writeln('- ${tool['name']}: ${tool['description']}');
      }
    }

    buffer.writeln();
    buffer.writeln('请根据以上信息，判断当前是否需要主动调用工具。输出严格的 JSON。');

    return buffer.toString();
  }
}
