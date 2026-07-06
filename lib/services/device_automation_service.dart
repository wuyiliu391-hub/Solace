import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 设备引擎状态
enum DeviceEngineStatus {
  /// 无任何引擎可用
  none,

  /// 仅 AccessibilityService 可用
  a11yOnly,

  /// 仅 Shizuku 可用
  shizukuOnly,

  /// 双引擎均可用
  dual,
}

/// Shizuku Shell 命令执行结果
class ShellCommandResult {
  final bool success;
  final String output;
  final String error;

  const ShellCommandResult({
    required this.success,
    required this.output,
    required this.error,
  });

  factory ShellCommandResult.fromMap(Map<String, dynamic> map) {
    return ShellCommandResult(
      success: map['success'] as bool? ?? false,
      output: map['output'] as String? ?? '',
      error: map['error'] as String? ?? '',
    );
  }
}

/// 设备操控服务
///
/// 封装对 Android 无障碍服务（AccessibilityService）和 Shizuku 的调用。
/// 提供统一的 Dart API，供 BT_ACTION 系统和 UI 层使用。
class DeviceAutomationService {
  static const _channel = MethodChannel('com.solace.solace/device');

  DeviceAutomationService._();
  static final DeviceAutomationService instance = DeviceAutomationService._();

  // ═══════════════════════════════════════════════════════════
  //  状态检测
  // ═══════════════════════════════════════════════════════════

  /// 无障碍服务是否已启用
  Future<bool> isAccessibilityEnabled() async {
    try {
      return await _channel.invokeMethod('isAccessibilityServiceEnabled') as bool;
    } catch (e) {
      debugPrint('[DeviceA11Y] isAccessibilityEnabled error: $e');
      return false;
    }
  }

  /// Shizuku 是否已安装且服务可用
  Future<bool> isShizukuAvailable() async {
    try {
      return await _channel.invokeMethod('isShizukuAvailable') as bool;
    } catch (e) {
      debugPrint('[DeviceShizuku] isShizukuAvailable error: $e');
      return false;
    }
  }

  /// Shizuku 是否已授权（有 shell 权限）
  Future<bool> isShizukuAuthorized() async {
    try {
      return await _channel.invokeMethod('isShizukuAuthorized') as bool;
    } catch (e) {
      debugPrint('[DeviceShizuku] isShizukuAuthorized error: $e');
      return false;
    }
  }

  /// 获取引擎工作状态
  Future<DeviceEngineStatus> getEngineStatus() async {
    try {
      final status = await _channel.invokeMethod<String>('getEngineStatus');
      switch (status) {
        case 'dual':
          return DeviceEngineStatus.dual;
        case 'a11y_only':
          return DeviceEngineStatus.a11yOnly;
        case 'shizuku_only':
          return DeviceEngineStatus.shizukuOnly;
        default:
          return DeviceEngineStatus.none;
      }
    } catch (e) {
      debugPrint('[Device] getEngineStatus error: $e');
      return DeviceEngineStatus.none;
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  引导用户开启服务
  // ═══════════════════════════════════════════════════════════

  /// 打开无障碍设置页面
  Future<bool> openAccessibilitySettings() async {
    try {
      return await _channel.invokeMethod('openAccessibilitySettings') as bool;
    } catch (e) {
      debugPrint('[DeviceA11Y] openAccessibilitySettings error: $e');
      return false;
    }
  }

  /// 打开 Shizuku App
  Future<bool> openShizuku() async {
    try {
      return await _channel.invokeMethod('openShizuku') as bool;
    } catch (e) {
      debugPrint('[DeviceShizuku] openShizuku error: $e');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  AccessibilityService — UI 操作
  // ═══════════════════════════════════════════════════════════

  /// 点击坐标 (x, y)
  Future<bool> tap(double x, double y) async {
    try {
      return await _channel.invokeMethod('tap', {'x': x, 'y': y}) as bool;
    } catch (e) {
      debugPrint('[DeviceA11Y] tap error: $e');
      return false;
    }
  }

  /// 滑动
  Future<bool> swipe({
    required double x1,
    required double y1,
    required double x2,
    required double y2,
    int durationMs = 300,
  }) async {
    try {
      return await _channel.invokeMethod('swipe', {
        'x1': x1,
        'y1': y1,
        'x2': x2,
        'y2': y2,
        'durationMs': durationMs,
      }) as bool;
    } catch (e) {
      debugPrint('[DeviceA11Y] swipe error: $e');
      return false;
    }
  }

  /// 长按坐标 (x, y)
  Future<bool> longPress(double x, double y, {int durationMs = 800}) async {
    try {
      return await _channel.invokeMethod('longPress', {
        'x': x,
        'y': y,
        'durationMs': durationMs,
      }) as bool;
    } catch (e) {
      debugPrint('[DeviceA11Y] longPress error: $e');
      return false;
    }
  }

  /// 返回键
  Future<bool> goBack() async {
    try {
      return await _channel.invokeMethod('back') as bool;
    } catch (e) {
      debugPrint('[DeviceA11Y] back error: $e');
      return false;
    }
  }

  /// 主页键
  Future<bool> goHome() async {
    try {
      return await _channel.invokeMethod('home') as bool;
    } catch (e) {
      debugPrint('[DeviceA11Y] home error: $e');
      return false;
    }
  }

  /// 最近任务
  Future<bool> openRecentApps() async {
    try {
      return await _channel.invokeMethod('recentApps') as bool;
    } catch (e) {
      debugPrint('[DeviceA11Y] recentApps error: $e');
      return false;
    }
  }

  /// 点击包含指定文本的 UI 元素
  Future<bool> clickText(String text) async {
    try {
      return await _channel.invokeMethod('clickText', {'text': text}) as bool;
    } catch (e) {
      debugPrint('[DeviceA11Y] clickText error: $e');
      return false;
    }
  }

  /// 在当前焦点输入框输入文字
  Future<bool> typeText(String text) async {
    try {
      return await _channel.invokeMethod('typeText', {'text': text}) as bool;
    } catch (e) {
      debugPrint('[DeviceA11Y] typeText error: $e');
      return false;
    }
  }

  /// 获取当前屏幕文字内容
  Future<String> getScreenContent() async {
    try {
      return await _channel.invokeMethod('getScreenContent') as String? ?? '';
    } catch (e) {
      debugPrint('[DeviceA11Y] getScreenContent error: $e');
      return '';
    }
  }

  /// 刷新并获取屏幕文字内容
  Future<String> refreshScreenContent() async {
    try {
      return await _channel.invokeMethod('refreshScreenContent') as String? ?? '';
    } catch (e) {
      debugPrint('[DeviceA11Y] refreshScreenContent error: $e');
      return '';
    }
  }

  /// 打开指定 App
  Future<bool> openApp(String packageName) async {
    try {
      return await _channel.invokeMethod('openApp', {
        'packageName': packageName,
      }) as bool;
    } catch (e) {
      debugPrint('[DeviceA11Y] openApp error: $e');
      return false;
    }
  }

  /// 获取通知列表
  Future<List<Map<String, dynamic>>> getNotifications() async {
    try {
      final jsonStr = await _channel.invokeMethod<String>('getNotifications');
      if (jsonStr == null || jsonStr.isEmpty) return [];
      final list = json.decode(jsonStr) as List;
      return list.cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('[DeviceA11Y] getNotifications error: $e');
      return [];
    }
  }

  /// 获取屏幕尺寸
  Future<Map<String, int>> getScreenSize() async {
    try {
      final result = await _channel.invokeMethod<Map>('getScreenSize');
      return {
        'width': (result?['width'] as int?) ?? 0,
        'height': (result?['height'] as int?) ?? 0,
      };
    } catch (e) {
      debugPrint('[DeviceA11Y] getScreenSize error: $e');
      return {'width': 0, 'height': 0};
    }
  }

  /// 展开通知面板
  Future<bool> openNotifications() async {
    try {
      return await _channel.invokeMethod('openNotifications') as bool;
    } catch (e) {
      debugPrint('[DeviceA11Y] openNotifications error: $e');
      return false;
    }
  }

  /// 展开快速设置面板
  Future<bool> openQuickSettings() async {
    try {
      return await _channel.invokeMethod('quickSettings') as bool;
    } catch (e) {
      debugPrint('[DeviceA11Y] quickSettings error: $e');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  Shizuku — 系统操作
  // ═══════════════════════════════════════════════════════════

  /// 执行任意 shell 命令（需要 Shizuku 授权）
  Future<ShellCommandResult> executeShell(String command) async {
    try {
      final result = await _channel.invokeMethod<Map>('shizukuExec', {
        'command': command,
      });
      if (result == null) {
        return const ShellCommandResult(success: false, output: '', error: 'No result');
      }
      return ShellCommandResult.fromMap(result.cast<String, dynamic>());
    } catch (e) {
      debugPrint('[DeviceShizuku] executeShell error: $e');
      return ShellCommandResult(success: false, output: '', error: e.toString());
    }
  }

  /// 开关 WiFi
  Future<bool> setWifiEnabled(bool enabled) async {
    try {
      final result = await _channel.invokeMethod<Map>('shizukuSetWifi', {
        'enabled': enabled,
      });
      return result?['success'] as bool? ?? false;
    } catch (e) {
      debugPrint('[DeviceShizuku] setWifiEnabled error: $e');
      return false;
    }
  }

  /// 开关蓝牙
  Future<bool> setBluetoothEnabled(bool enabled) async {
    try {
      final result = await _channel.invokeMethod<Map>('shizukuSetBluetooth', {
        'enabled': enabled,
      });
      return result?['success'] as bool? ?? false;
    } catch (e) {
      debugPrint('[DeviceShizuku] setBluetoothEnabled error: $e');
      return false;
    }
  }

  /// 设置音量 (0-100)
  Future<bool> setVolume(int level) async {
    try {
      final result = await _channel.invokeMethod<Map>('shizukuSetVolume', {
        'level': level.clamp(0, 100),
      });
      return result?['success'] as bool? ?? false;
    } catch (e) {
      debugPrint('[DeviceShizuku] setVolume error: $e');
      return false;
    }
  }

  /// 设置屏幕亮度 (0-255)
  Future<bool> setBrightness(int level) async {
    try {
      final result = await _channel.invokeMethod<Map>('shizukuSetBrightness', {
        'level': level.clamp(0, 255),
      });
      return result?['success'] as bool? ?? false;
    } catch (e) {
      debugPrint('[DeviceShizuku] setBrightness error: $e');
      return false;
    }
  }

  /// 安装 APK（需要 Shizuku 授权）
  Future<bool> installApp(String apkPath) async {
    try {
      final result = await _channel.invokeMethod<Map>('shizukuInstallApp', {
        'apkPath': apkPath,
      });
      return result?['success'] as bool? ?? false;
    } catch (e) {
      debugPrint('[DeviceShizuku] installApp error: $e');
      return false;
    }
  }

  /// 卸载 App（需要 Shizuku 授权）
  Future<bool> uninstallApp(String packageName) async {
    try {
      final result = await _channel.invokeMethod<Map>('shizukuUninstallApp', {
        'packageName': packageName,
      });
      return result?['success'] as bool? ?? false;
    } catch (e) {
      debugPrint('[DeviceShizuku] uninstallApp error: $e');
      return false;
    }
  }

  /// 授权运行时权限（需要 Shizuku 授权）
  Future<bool> grantPermission(String packageName, String permission) async {
    try {
      final result = await _channel.invokeMethod<Map>('shizukuGrantPermission', {
        'packageName': packageName,
        'permission': permission,
      });
      return result?['success'] as bool? ?? false;
    } catch (e) {
      debugPrint('[DeviceShizuku] grantPermission error: $e');
      return false;
    }
  }
}
