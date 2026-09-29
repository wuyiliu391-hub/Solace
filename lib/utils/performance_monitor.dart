// 性能优化 -- 耗电与老手机兼容
// 性能监控工具：用于开发阶段定位耗时操作和调用频率
// 生产环境可通过 kReleaseMode 跳过所有监控逻辑

import 'package:flutter/foundation.dart';

class PerformanceMonitor {
  static final _instance = PerformanceMonitor._();
  factory PerformanceMonitor() => _instance;
  PerformanceMonitor._();

  final Map<String, Stopwatch> _timers = {};
  final Map<String, int> _counts = {};
  final Map<String, List<int>> _durations = {};

  /// 开始计时
  void startTimer(String name) {
    if (kReleaseMode) return;
    _timers[name] = Stopwatch()..start();
  }

  /// 结束计时并打印耗时
  void endTimer(String name) {
    if (kReleaseMode) return;
    final sw = _timers[name];
    if (sw == null) return;
    sw.stop();
    final ms = sw.elapsedMilliseconds;
    debugPrint('[Perf] $name: ${ms}ms');
    _durations.putIfAbsent(name, () => []).add(ms);
    _timers.remove(name);
  }

  /// 递增调用计数器
  void incrementCounter(String name) {
    if (kReleaseMode) return;
    _counts[name] = (_counts[name] ?? 0) + 1;
  }

  /// 打印所有计数器
  void report() {
    if (kReleaseMode) return;
    if (_counts.isNotEmpty) {
      debugPrint('═══ [Perf] Counter Report ═══');
      for (final entry in _counts.entries) {
        debugPrint('  ${entry.key}: ${entry.value} times');
      }
    }
    if (_durations.isNotEmpty) {
      debugPrint('═══ [Perf] Duration Report ═══');
      for (final entry in _durations.entries) {
        final list = entry.value;
        final avg = list.isEmpty ? 0 : list.reduce((a, b) => a + b) / list.length;
        final max = list.isEmpty ? 0 : list.reduce((a, b) => a > b ? a : b);
        debugPrint('  ${entry.key}: avg=${avg.toStringAsFixed(1)}ms, max=${max}ms, count=${list.length}');
      }
    }
  }

  /// 重置所有数据
  void reset() {
    _timers.clear();
    _counts.clear();
    _durations.clear();
  }
}
