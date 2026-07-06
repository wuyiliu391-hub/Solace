// 【对标来源：KouriChat-1.4.3.2 — modules/reminder/service.py 提醒服务】
// 1:1 转译自 KouriChat ReminderService 类
// 参考文件：modules/reminder/service.py

import "dart:async";
import "dart:convert";
import "package:shared_preferences/shared_preferences.dart";
import "../models/reminder_task.dart";

/// 提醒服务（对标 KouriChat ReminderService）
/// 完整保留 KouriChat 的提醒创建、触发、清理逻辑
class ReminderService {
  static ReminderService? _instance;
  static ReminderService get instance => _instance ??= ReminderService._();
  ReminderService._();

  /// 活跃提醒列表
  final List<ReminderTask> _reminders = [];

  /// 定时器
  Timer? _checkTimer;

  /// 回调函数
  void Function(ReminderTask reminder)? onReminderTriggered;

  /// 初始化（对标 KouriChat ReminderService.__init__）
  Future<void> initialize() async {
    await _loadReminders();
    _startCheckTimer();
  }

  /// 添加提醒（对标 KouriChat add_reminder）
  Future<bool> addReminder({
    required String chatId,
    required DateTime targetTime,
    required String content,
    required String senderName,
    bool silent = false,
  }) async {
    try {
      final reminder = ReminderTask(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        chatId: chatId,
        targetTime: targetTime,
        content: content,
        senderName: senderName,
        createdAt: DateTime.now(),
        isCompleted: false,
      );

      _reminders.add(reminder);
      await _saveReminders();

      if (!silent) {
        // 非静默模式下立即检查
        _checkReminders();
      }

      return true;
    } catch (e) {
      return false;
    }
  }

  /// 完成提醒（对标 KouriChat complete_reminder）
  Future<void> completeReminder(String reminderId) async {
    final index = _reminders.indexWhere((r) => r.id == reminderId);
    if (index != -1) {
      _reminders[index] = ReminderTask(
        id: _reminders[index].id,
        chatId: _reminders[index].chatId,
        targetTime: _reminders[index].targetTime,
        content: _reminders[index].content,
        senderName: _reminders[index].senderName,
        createdAt: _reminders[index].createdAt,
        isCompleted: true,
      );
      await _saveReminders();
    }
  }

  /// 删除提醒
  Future<void> deleteReminder(String reminderId) async {
    _reminders.removeWhere((r) => r.id == reminderId);
    await _saveReminders();
  }

  /// 获取聊天的所有提醒
  List<ReminderTask> getRemindersForChat(String chatId) {
    return _reminders
        .where((r) => r.chatId == chatId && !r.isCompleted)
        .toList();
  }

  /// 获取所有活跃提醒
  List<ReminderTask> getActiveReminders() {
    return _reminders.where((r) => !r.isCompleted).toList();
  }

  /// 检查提醒（对标 KouriChat check_reminders 定时任务）
  void _checkReminders() {
    final now = DateTime.now();
    for (final reminder in _reminders) {
      if (reminder.isCompleted) continue;
      if (reminder.targetTime.isBefore(now) ||
          reminder.targetTime.isAtSameMomentAs(now)) {
        // 触发提醒回调
        onReminderTriggered?.call(reminder);
        completeReminder(reminder.id);
      }
    }
  }

  /// 启动检查定时器
  void _startCheckTimer() {
    _checkTimer?.cancel();
    _checkTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _checkReminders(),
    );
  }

  /// 保存提醒到本地存储
  Future<void> _saveReminders() async {
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode(_reminders.map((r) => r.toJson()).toList());
    await prefs.setString('reminders', json);
  }

  /// 从本地存储加载提醒
  Future<void> _loadReminders() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('reminders');
    if (json != null) {
      final list = jsonDecode(json) as List<dynamic>;
      _reminders.clear();
      for (final item in list) {
        _reminders.add(
            ReminderTask.fromJson(item as Map<String, dynamic>));
      }
    }
  }

  /// 清理已完成的提醒
  Future<void> clearCompleted() async {
    _reminders.removeWhere((r) => r.isCompleted);
    await _saveReminders();
  }

  /// 销毁服务
  void dispose() {
    _checkTimer?.cancel();
  }
}
