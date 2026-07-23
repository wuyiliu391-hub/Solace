import '../models/device_agent_action.dart';

/// L0 确定性路由 与 Device Agent 共用频控 / 读类判定
class DeviceActionPolicy {
  DeviceActionPolicy._();
  static final DeviceActionPolicy instance = DeviceActionPolicy._();

  static const int maxActionsPerHour = 12;
  static const Duration coolDown = Duration(seconds: 15);

  /// sessionId -> 成功时间戳
  final Map<String, List<DateTime>> _recentSuccess = {};

  /// sessionId -> 待回灌事实（下一轮 internal）
  final Map<String, List<String>> _pendingFeedback = {};

  static const Set<String> readToolNames = {
    'get_battery_info',
    'get_current_app',
    'get_installed_apps',
    'get_app_usage_time',
    'get_notifications',
    'get_notification_count',
    'take_screenshot',
  };

  bool isReadTool(String toolName) => readToolNames.contains(toolName);

  bool isReadAction(DeviceActionType type) {
    return deviceActionCategoryMap[type] == DevicePermissionCategory.read;
  }

  bool allow(String sessionId) {
    final now = DateTime.now();
    final list = _recentSuccess[sessionId] ?? [];
    list.removeWhere((t) => now.difference(t) > const Duration(hours: 1));
    _recentSuccess[sessionId] = list;
    if (list.length >= maxActionsPerHour) return false;
    if (list.isNotEmpty && now.difference(list.last) < coolDown) return false;
    return true;
  }

  void markSuccess(String sessionId) {
    final list = _recentSuccess[sessionId] ?? [];
    list.add(DateTime.now());
    _recentSuccess[sessionId] = list;
  }

  /// 写入下一轮回灌（读类优先完整消息，写类短确认）
  void pushFeedback({
    required String sessionId,
    required String toolName,
    required String message,
    required bool success,
    bool isRead = false,
  }) {
    if (!success) return;
    final line = isRead || isReadTool(toolName)
        ? '设备事实 · $toolName：$message'
        : '设备动作 · $toolName：$message';
    final list = _pendingFeedback[sessionId] ?? [];
    list.add(line);
    // 只保留最近 6 条，防炸 token
    if (list.length > 6) {
      list.removeRange(0, list.length - 6);
    }
    _pendingFeedback[sessionId] = list;
  }

  /// 取回并清空（消费一次）
  String? consumeFeedback(String sessionId) {
    final list = _pendingFeedback.remove(sessionId);
    if (list == null || list.isEmpty) return null;
    final buf = StringBuffer();
    buf.writeln('【上一轮设备结果 · 仅内部事实，勿对用户复读标签】');
    for (final line in list) {
      buf.writeln('- $line');
    }
    buf.writeln('可自然融入台词；读类结果优先用于关心/提醒。');
    return buf.toString().trim();
  }

  /// 窥视不清空（调试用）
  List<String> peekFeedback(String sessionId) =>
      List.unmodifiable(_pendingFeedback[sessionId] ?? const []);
}
