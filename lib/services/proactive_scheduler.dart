// 【对标来源：Muice-Chatbot-1.4 — Muice.py:create_a_new_topic() 主动对话调度】
// 1:1 转译自 Muice 主动对话触发逻辑
// 参考文件：Muice.py:create_a_new_topic()、configs.yml:active

import 'dart:math';

import '../models/proactive_config.dart';
import '../models/scheduled_task.dart';
import '../repositories/local_storage_repository.dart';
import 'workmanager_task_scheduler.dart'
    if (dart.library.html) 'workmanager_task_scheduler_web.dart'
    as workmanager_tasks;

/// 主动对话调度器（对标 Muice create_a_new_topic）
/// 完整保留 Muice 的三重触发机制：定时/随机/事件
class ProactiveScheduler {
  final ProactiveConfig config;
  final List<ScheduledTask> scheduledTasks;

  /// 已消耗的定时任务（对标 Muice self.time_topic 删除逻辑）
  final List<String> _consumedTaskIds = [];

  /// 上次对话时间戳
  DateTime _lastInteractionTime = DateTime.now();

  ProactiveScheduler(
    LocalStorageRepository? storage, {
    ProactiveConfig? config,
    this.scheduledTasks = const [],
  }) : config = config ?? const ProactiveConfig();

  /// 尝试生成主动话题（对标 Muice create_a_new_topic）
  /// 返回 null 表示不发起对话，返回字符串表示主动消息内容
  String? createNewTopic() {
    final now = DateTime.now();
    final currentHour = now.hour;
    final currentMinute = now.minute;
    final timeDifference = now.difference(_lastInteractionTime).inSeconds;

    // 距离上次对话小于 30 分钟，不主动发起（对标 Muice time_difference < 30 * 60）
    if (timeDifference < 30 * 60) {
      return null;
    }

    // 1. 尝试生成日常定时 Prompt（对标 Muice time_topic_probability）
    if (config.schedule.enable && _random() < config.schedule.rate) {
      for (int i = 0; i < scheduledTasks.length; i++) {
        final task = scheduledTasks[i];
        if (_consumedTaskIds.contains(task.id)) continue;

        // 检查是否匹配当前时间（对标 Muice event_time == current_time）
        final taskHour = task.hour;
        final taskMinute = _randomInt(0, 59); // 对标 Muice random.randint(0, 59)
        if (taskHour == currentHour && taskMinute == currentMinute) {
          _consumedTaskIds.add(task.id);
          return task.prompt;
        }
      }
    }

    // 2. 尝试生成不定时 Prompt（对标 Muice known_topic_probability）
    // 夜间静默：23:00-06:00 不发送随机消息（对标 Muice 夜间判断）
    final isNightHour = currentHour >= 23 || currentHour <= 6;
    if (config.enable && !isNightHour) {
      if (_random() < config.rate) {
        if (config.activePrompts.isNotEmpty) {
          return config
              .activePrompts[_randomInt(0, config.activePrompts.length - 1)];
        }
      }
    }

    // 3. 定时任务重置（对标 Muice time_topic 重置逻辑）
    // 如果消耗了定时任务且距离上次消耗超过 1 小时，重置
    if (_consumedTaskIds.isNotEmpty && timeDifference > 60 * 60) {
      _consumedTaskIds.clear();
    }

    return null;
  }

  /// 更新最后交互时间
  void updateLastInteraction() {
    _lastInteractionTime = DateTime.now();
  }

  /// 获取距离上次交互的分钟数
  int getMinutesSinceLastInteraction() {
    return DateTime.now().difference(_lastInteractionTime).inMinutes;
  }

  /// 生成日常问候 Prompt（对标 Muice <日常问候>）
  String? createDailyGreeting() {
    final hour = DateTime.now().hour;

    if (hour >= 6 && hour < 11) {
      return '现在是早上，请向我发起日常早安问候。';
    } else if (hour >= 11 && hour < 14) {
      return '现在是中午，请向我发起午间问候。';
    } else if (hour >= 18 && hour < 22) {
      return '现在是晚上，请向我发起晚间问候。';
    }

    return null;
  }

  /// 取消某个角色的所有调度任务
  void cancelAllForCharacter(String characterId) {
    _consumedTaskIds.clear();
  }

  /// 调度所有日常问候
  Future<void> scheduleAllGreetings() async {
    // 桩实现：问候逻辑由心跳服务驱动
  }

  /// 调度 AI 转移任务
  Future<void> scheduleAITransfers() async {
    // 桩实现：AI 转移由心跳服务驱动
  }

  /// 调度评论回复延迟任务
  Future<void> scheduleCommentReply({
    required String momentId,
    required String commentId,
    required String characterId,
    required int intimacyLevel,
    required Duration delay,
  }) async {
    await workmanager_tasks.scheduleCommentReplyTask(
      momentId: momentId,
      commentId: commentId,
      characterId: characterId,
      intimacyLevel: intimacyLevel,
      delay: delay,
    );
  }

  /// 调度动态互动延迟任务
  Future<void> scheduleMomentInteraction({
    required String momentId,
    required String characterId,
    required int intimacyLevel,
    required Duration delay,
  }) async {
    await workmanager_tasks.scheduleMomentInteractionTask(
      momentId: momentId,
      characterId: characterId,
      intimacyLevel: intimacyLevel,
      delay: delay,
    );
  }

  double _random() => Random().nextDouble();
  int _randomInt(int min, int max) => min + Random().nextInt(max - min + 1);
}
