import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 电池信息数据
class BatteryInfo {
  final int percentage;    // 0-100
  final bool isCharging;   // 是否充电中
  final bool isFull;       // 是否已充满
  final String chargeSource; // ac / usb / wireless / none

  const BatteryInfo({
    required this.percentage,
    required this.isCharging,
    this.isFull = false,
    this.chargeSource = 'none',
  });

  factory BatteryInfo.fromMap(Map<dynamic, dynamic> map) {
    return BatteryInfo(
      percentage: (map['percentage'] as num?)?.toInt() ?? 0,
      isCharging: map['isCharging'] as bool? ?? false,
      isFull: map['isFull'] as bool? ?? false,
      chargeSource: map['chargeSource'] as String? ?? 'none',
    );
  }

  static const empty = BatteryInfo(percentage: 0, isCharging: false);
}

/// 电池服务 — 读取 Android 设备电池状态
///
/// 使用 MethodChannel 调用 Android BatteryManager 粘性广播。
/// 无需额外权限，实时获取电量和充电状态。
///
/// 节能策略：
/// - App 前台时 60 秒轮询一次（电池数据变化极慢，30s 过频）
/// - App 进入后台时完全停止轮询（不再需要 IPC 唤醒）
/// - App 回到前台时自动恢复轮询
class BatteryService with WidgetsBindingObserver {
  static const _channel = MethodChannel('com.solace.solace/battery');
  static BatteryInfo _cached = BatteryInfo.empty;
  static Timer? _timer;
  static final _controller = StreamController<BatteryInfo>.broadcast();
  static bool _initialized = false;

  /// 电池信息流
  static Stream<BatteryInfo> get stream => _controller.stream;

  /// 当前缓存的电池信息
  static BatteryInfo get current => _cached;

  /// 初始化并开始监听（需在 WidgetsBinding 就绪后调用）
  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // 注册生命周期监听
    WidgetsBinding.instance.addObserver(BatteryService._instance);

    await _refresh();
    _startForegroundPolling();
  }

  /// 手动刷新一次
  static Future<BatteryInfo?> refresh() async {
    return await _refresh();
  }

  /// 前台轮询（60 秒一次）
  static void _startForegroundPolling() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => _refresh());
  }

  /// 停止轮询（App 进入后台时调用）
  static void _stopPolling() {
    _timer?.cancel();
    _timer = null;
  }

  static Future<BatteryInfo?> _refresh() async {
    try {
      final result = await _channel.invokeMethod('getBatteryInfo');
      if (result is! Map) return null;
      _cached = BatteryInfo.fromMap(result);
      _controller.add(_cached);
      return _cached;
    } catch (e) {
      debugPrint('BatteryService: 读取电池信息失败 $e');
      return null;
    }
  }

  /// 释放资源
  static void dispose() {
    WidgetsBinding.instance.removeObserver(BatteryService._instance);
    _timer?.cancel();
    _controller.close();
    _initialized = false;
  }

  // ── 生命周期监听（单例 observer） ──

  static final _instance = _LifecycleObserver();
}

/// 内部生命周期观察者（避免外部直接访问）
class _LifecycleObserver extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        BatteryService._startForegroundPolling();
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        BatteryService._stopPolling();
        break;
    }
  }
}
