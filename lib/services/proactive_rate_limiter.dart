import 'package:flutter/foundation.dart';

/// 主动决策限频器 — 防止工具被过度调用
///
/// 策略：
/// - 同一工具在冷却时间内不重复调用
/// - 全局调用频率限制
/// - 按优先级调整冷却时间
class ProactiveRateLimiter {
  /// 工具调用记录：{toolName: lastCallTime}
  final Map<String, DateTime> _toolCooldowns = {};

  /// 全局调用记录（最近 N 分钟内的调用次数）
  final List<DateTime> _globalCallLog = [];

  /// 默认冷却时间（分钟）
  static const int defaultCooldownMinutes = 5;

  /// 全局调用频率限制：最多 N 次 / 窗口时间
  static const int maxCallsPerWindow = 3;
  static const int windowMinutes = 10;

  /// 检查指定工具是否可以调用
  ///
  /// 返回 true 表示允许调用，false 表示被限频
  bool canCallTool(String toolName, {int? cooldownMinutes}) {
    final cooldown = cooldownMinutes ?? defaultCooldownMinutes;
    final now = DateTime.now();

    // 检查工具级冷却
    final lastCall = _toolCooldowns[toolName];
    if (lastCall != null) {
      final elapsed = now.difference(lastCall).inMinutes;
      if (elapsed < cooldown) {
        debugPrint(
            '[RateLimiter] 工具 $toolName 冷却中，还需 ${cooldown - elapsed} 分钟');
        return false;
      }
    }

    // 检查全局频率
    _globalCallLog.removeWhere(
      (t) => now.difference(t).inMinutes > windowMinutes,
    );
    if (_globalCallLog.length >= maxCallsPerWindow) {
      debugPrint(
          '[RateLimiter] 全局频率限制：${_globalCallLog.length}/$maxCallsPerWindow（$windowMinutes 分钟内）');
      return false;
    }

    return true;
  }

  /// 记录工具调用
  void recordCall(String toolName) {
    final now = DateTime.now();
    _toolCooldowns[toolName] = now;
    _globalCallLog.add(now);
  }

  /// 获取工具剩余冷却时间（秒）
  int getRemainingCooldown(String toolName, {int? cooldownMinutes}) {
    final cooldown = cooldownMinutes ?? defaultCooldownMinutes;
    final lastCall = _toolCooldowns[toolName];
    if (lastCall == null) return 0;
    final elapsed = DateTime.now().difference(lastCall).inSeconds;
    final totalSeconds = cooldown * 60;
    final remaining = totalSeconds - elapsed;
    return remaining > 0 ? remaining : 0;
  }

  /// 获取全局调用统计
  Map<String, dynamic> getStats() {
    final now = DateTime.now();
    _globalCallLog.removeWhere(
      (t) => now.difference(t).inMinutes > windowMinutes,
    );
    return {
      'globalCallsInWindow': _globalCallLog.length,
      'maxCallsPerWindow': maxCallsPerWindow,
      'windowMinutes': windowMinutes,
      'toolCooldowns': _toolCooldowns.map(
        (k, v) => MapEntry(k, v.toIso8601String()),
      ),
    };
  }

  /// 清除所有记录
  void reset() {
    _toolCooldowns.clear();
    _globalCallLog.clear();
  }
}
