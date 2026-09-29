// 【对标来源：Muice-Chatbot-1.4 — configs.yml:active.shecdule.tasks[] + Muice.py time_topic】
// 1:1 转译自 Muice 定时任务数据结构
// 参考文件：configs.yml:shecdule.tasks、Muice.py:create_a_new_topic()

/// 定时任务（对标 Muice shecdule.tasks[] 单条）
class ScheduledTask {
  /// 唯一标识
  final String id;

  /// 触发小时 0-23（对标 task['hour']）
  final int hour;

  /// 触发提示词（对标 task['prompt']）
  final String prompt;

  /// 是否已触发（对标 Muice 触发后 remove 逻辑）
  final bool triggered;

  const ScheduledTask({
    required this.id,
    required this.hour,
    required this.prompt,
    this.triggered = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'hour': hour,
        'prompt': prompt,
        'triggered': triggered,
      };

  factory ScheduledTask.fromJson(Map<String, dynamic> json) {
    return ScheduledTask(
      id: json['id'] as String? ?? '',
      hour: json['hour'] as int? ?? 0,
      prompt: json['prompt'] as String? ?? '',
      triggered: json['triggered'] as bool? ?? false,
    );
  }
}

