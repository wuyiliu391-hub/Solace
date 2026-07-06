// 【对标来源：Muice-Chatbot-1.4 — configs.yml:active 主动对话配置】
// 1:1 转译自 Muice configs.yml active 字段
// 参考文件：configs.yml、Muice.py:create_a_new_topic()

import 'scheduled_task.dart';

/// 主动对话配置（对标 Muice configs.yml:active）
class ProactiveConfig {
  /// 是否启用主动对话（对标 active.enable）
  final bool enable;

  /// 随机话题触发概率（对标 active.rate，默认 0.003）
  final double rate;

  /// 是否启用免打扰（对标 active.not_disturb）
  final bool notDisturb;

  /// 免打扰开始小时（对标 23:00）
  final int quietStart;

  /// 免打扰结束小时（对标 06:00）
  final int quietEnd;

  /// 定时任务配置（对标 active.shecdule）
  final ScheduleConfig schedule;

  /// 随机话题候选池（对标 active.active_prompts）
  final List<String> activePrompts;

  /// 冷却时间秒：距离上次对话不足此时间不触发（对标 Muice 30min 门槛）
  final int cooldownSeconds;

  /// 定时任务重置间隔秒（对标 Muice 1h 重置逻辑）
  final int scheduleResetSeconds;

  /// 随机话题触发概率（对标 known_topic_probability）
  final double knownTopicProbability;

  /// 定时任务触发概率（对标 time_topic_probability）
  final double timeTopicProbability;

  const ProactiveConfig({
    this.enable = false,
    this.rate = 0.003,
    this.notDisturb = true,
    this.quietStart = 23,
    this.quietEnd = 6,
    this.schedule = const ScheduleConfig(),
    this.activePrompts = const [],
    this.cooldownSeconds = 1800,
    this.scheduleResetSeconds = 3600,
    this.knownTopicProbability = 0.003,
    this.timeTopicProbability = 0.75,
  });

  Map<String, dynamic> toJson() => {
        'enable': enable,
        'rate': rate,
        'notDisturb': notDisturb,
        'quietStart': quietStart,
        'quietEnd': quietEnd,
        'schedule': schedule.toJson(),
        'activePrompts': activePrompts,
        'cooldownSeconds': cooldownSeconds,
        'scheduleResetSeconds': scheduleResetSeconds,
        'knownTopicProbability': knownTopicProbability,
        'timeTopicProbability': timeTopicProbability,
      };

  factory ProactiveConfig.fromJson(Map<String, dynamic> json) {
    return ProactiveConfig(
      enable: json['enable'] as bool? ?? false,
      rate: (json['rate'] as num?)?.toDouble() ?? 0.003,
      notDisturb: json['notDisturb'] as bool? ?? true,
      quietStart: json['quietStart'] as int? ?? 23,
      quietEnd: json['quietEnd'] as int? ?? 6,
      schedule: json['schedule'] != null
          ? ScheduleConfig.fromJson(
              json['schedule'] as Map<String, dynamic>)
          : const ScheduleConfig(),
      activePrompts:
          (json['activePrompts'] as List<dynamic>?)?.cast<String>() ?? [],
      cooldownSeconds: json['cooldownSeconds'] as int? ?? 1800,
      scheduleResetSeconds:
          json['scheduleResetSeconds'] as int? ?? 3600,
      knownTopicProbability:
          (json['knownTopicProbability'] as num?)?.toDouble() ?? 0.003,
      timeTopicProbability:
          (json['timeTopicProbability'] as num?)?.toDouble() ?? 0.75,
    );
  }
}

/// 定时任务配置（对标 Muice active.shecdule）
class ScheduleConfig {
  /// 是否启用定时任务（对标 shecdule.enable）
  final bool enable;

  /// 定时任务触发概率（对标 shecdule.rate）
  final double rate;

  /// 任务列表（对标 shecdule.tasks）
  final List<ScheduledTask> tasks;

  const ScheduleConfig({
    this.enable = true,
    this.rate = 0.75,
    this.tasks = const [],
  });

  Map<String, dynamic> toJson() => {
        'enable': enable,
        'rate': rate,
        'tasks': tasks.map((e) => e.toJson()).toList(),
      };

  factory ScheduleConfig.fromJson(Map<String, dynamic> json) {
    return ScheduleConfig(
      enable: json['enable'] as bool? ?? true,
      rate: (json['rate'] as num?)?.toDouble() ?? 0.75,
      tasks: (json['tasks'] as List<dynamic>?)
              ?.map((e) =>
                  ScheduledTask.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}
