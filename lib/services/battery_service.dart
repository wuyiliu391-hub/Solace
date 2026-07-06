import 'dart:async';
import 'package:flutter/foundation.dart';
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
/// 使用 MethodChannel 调用 Android BatteryManager 粘性广播
/// 无需额外权限，实时获取电量和充电状态
class BatteryService {
  static const _channel = MethodChannel('com.solace.solace/battery');
  static BatteryInfo _cached = BatteryInfo.empty;
  static Timer? _timer;
  static final _controller = StreamController<BatteryInfo>.broadcast();

  /// 电池信息流（每 30 秒自动刷新）
  static Stream<BatteryInfo> get stream => _controller.stream;

  /// 当前缓存的电池信息
  static BatteryInfo get current => _cached;

  /// 初始化并开始监听
  static Future<void> init() async {
    await _refresh();
    // 每 30 秒轮询一次（Android 粘性广播需要主动读取）
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _refresh());
  }

  /// 手动刷新一次
  static Future<BatteryInfo> refresh() async {
    return await _refresh();
  }

  static Future<BatteryInfo> _refresh() async {
    try {
      final result = await _channel.invokeMethod('getBatteryInfo');
      if (result != null) {
        _cached = BatteryInfo.fromMap(result as Map<dynamic, dynamic>);
        _controller.add(_cached);
      }
    } catch (e) {
      debugPrint('BatteryService: 读取电池信息失败 $e');
    }
    return _cached;
  }

  /// 释放资源
  static void dispose() {
    _timer?.cancel();
    _controller.close();
  }
}
