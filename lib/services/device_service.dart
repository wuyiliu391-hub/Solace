import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 设备执行服务 — 所有设备自动化均通过 Shizuku shell (UID 2000)。
///
/// AccessibilityService 只负责读取 UI 树、当前应用与服务状态；本服务是点击、
/// 滑动、文本输入、按键、应用启动/退出、截图和系统控制的唯一执行入口。
/// DevicePolicyManager 的作息锁屏属于独立的 wellbeing 能力，不由本类处理。
class DeviceService {
  static const _channel = MethodChannel('com.solace.solace/device');
  static const _stateChannel = EventChannel(
    'com.solace.solace/shizuku_state',
  );

  bool _shizukuRunning = false;
  bool _shizukuGranted = false;
  StreamSubscription<dynamic>? _stateSubscription;

  static final DeviceService _instance = DeviceService._();
  factory DeviceService() => _instance;

  DeviceService._() {
    _listenShizukuState();
  }

  void _listenShizukuState() {
    _stateSubscription = _stateChannel.receiveBroadcastStream().listen((event) {
      if (event is Map) {
        _shizukuRunning = event['available'] == true;
        _shizukuGranted = event['permitted'] == true;
        debugPrint(
          '[DeviceService] Shizuku: running=$_shizukuRunning '
          'granted=$_shizukuGranted',
        );
      }
    });
  }

  void dispose() => _stateSubscription?.cancel();

  bool get isShizukuRunning => _shizukuRunning;
  bool get isShizukuGranted => _shizukuGranted;
  bool get isShizukuReady => _shizukuRunning && _shizukuGranted;

  /// 主动刷新并返回 Shizuku 状态。执行前应调用此方法，不依赖事件缓存。
  Future<Map<String, bool>> getShizukuStatus() async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'isShizukuAvailable',
      );
      _shizukuRunning = result?['available'] == true;
      _shizukuGranted = result?['permitted'] == true;
    } catch (e) {
      _shizukuRunning = false;
      _shizukuGranted = false;
      debugPrint('DeviceService.getShizukuStatus error: $e');
    }
    return {
      'available': _shizukuRunning,
      'permitted': _shizukuGranted,
    };
  }

  /// 请求 Shizuku 权限。null 表示授权对话框已发起、等待用户选择。
  Future<bool?> requestShizukuPermission() async {
    try {
      return await _channel.invokeMethod<bool>('requestShizukuPermission');
    } catch (e) {
      debugPrint('DeviceService.requestShizukuPermission error: $e');
      return false;
    }
  }

  Future<bool> tap(int x, int y) => _invokeBool('tap', {'x': x, 'y': y});

  Future<bool> swipe(
    int startX,
    int startY,
    int endX,
    int endY, {
    int duration = 300,
  }) =>
      _invokeBool('swipe', {
        'startX': startX,
        'startY': startY,
        'endX': endX,
        'endY': endY,
        'duration': duration,
      });

  Future<bool> pressKey(int keyCode) =>
      _invokeBool('pressKey', {'keyCode': keyCode});

  Future<bool> inputText(String text) =>
      _invokeBool('inputText', {'text': text});

  Future<bool> startApp(String packageName) =>
      _invokeBool('startApp', {'packageName': packageName});

  Future<bool> exitApp(String packageName) =>
      _invokeBool('exitApp', {'packageName': packageName});

  Future<bool> lockScreen() => _invokeBool('lockScreen');

  Future<bool> adjustVolume(bool up, {bool showUi = true}) =>
      _invokeBool('adjustVolume', {'up': up, 'showUi': showUi});

  Future<bool> setMuteMode(int ringerMode) =>
      _invokeBool('setMuteMode', {'ringerMode': ringerMode});

  Future<bool> openGallery() => _invokeBool('openGallery');

  /// 获取应用使用时长（通过 UsageStatsManager API，不走视觉循环）
  /// [packageName] 为 null 则返回所有应用排行
  Future<Map<String, dynamic>?> getAppUsageTime({
    String? packageName,
    int sinceHours = 24,
    int limit = 10,
    bool includeSystemApps = false,
  }) async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'getAppUsageTime',
        {
          if (packageName != null) 'packageName': packageName,
          'sinceHours': sinceHours,
          'limit': limit,
          'includeSystemApps': includeSystemApps,
        },
      );
      if (result == null) return null;
      return Map<String, dynamic>.from(result);
    } catch (e) {
      debugPrint('DeviceService.getAppUsageTime error: $e');
      return null;
    }
  }

  Future<String?> shellScreenshot() async {
    try {
      return await _channel.invokeMethod<String>('shellScreenshot');
    } catch (e) {
      debugPrint('DeviceService.shellScreenshot error: $e');
      return null;
    }
  }

  Future<bool> toggleWifi(bool enable) =>
      _invokeBool('toggleWifi', {'enable': enable});

  Future<bool> toggleBluetooth(bool enable) =>
      _invokeBool('toggleBluetooth', {'enable': enable});

  Future<bool> setBrightness(int level) =>
      _invokeBool('setBrightness', {'level': level});

  /// 执行任意 Shizuku shell 命令并返回结果
  Future<ShellResult> shellExec(String command) async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'shellExec', {'command': command},
      );
      if (result == null) {
        return ShellResult(success: false, stdout: '', stderr: 'null result', exitCode: -1);
      }
      return ShellResult(
        success: (result['exitCode'] as int?) == 0,
        stdout: (result['stdout'] as String?) ?? '',
        stderr: (result['stderr'] as String?) ?? '',
        exitCode: (result['exitCode'] as int?) ?? -1,
      );
    } catch (e) {
      debugPrint('DeviceService.shellExec error: $e');
      return ShellResult(success: false, stdout: '', stderr: e.toString(), exitCode: -1);
    }
  }

  Future<bool> _invokeBool(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    try {
      return await _channel.invokeMethod<bool>(method, arguments) ?? false;
    } catch (e) {
      debugPrint('DeviceService.$method error: $e');
      return false;
    }
  }
}

/// Shell 命令执行结果
class ShellResult {
  final bool success;
  final String stdout;
  final String stderr;
  final int exitCode;

  const ShellResult({
    required this.success,
    required this.stdout,
    required this.stderr,
    required this.exitCode,
  });
}
