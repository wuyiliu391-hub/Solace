import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'device_service.dart';

/// 屏幕截图服务 — Flutter 桥接层
///
/// 通过 MediaProjection API 捕获设备屏幕：
/// - 请求/检查/释放截图权限
/// - 执行截图并返回文件路径
///
/// ## 权限时序说明
/// `requestPermission()` 会启动透明 Activity 申请 MediaProjection 授权。
/// 由于结果通过 `onActivityResult` 异步返回，调用后需要轮询等待权限就绪。
class ScreenshotService {
  static const _channel = MethodChannel('com.solace.solace/screenshot');

  /// 请求截图权限（弹出系统确认对话框）
  /// 返回 true 表示已触发请求，但不代表权限已就绪
  /// 调用后应轮询 [hasPermission] 等待权限真正可用
  Future<bool> requestPermission() async {
    try {
      final result = await _channel.invokeMethod<bool>('requestPermission');
      return result ?? false;
    } catch (e) {
      debugPrint('ScreenshotService.requestPermission error: $e');
      return false;
    }
  }

  /// 请求截图权限并等待就绪（阻塞式）
  /// [maxWaitMs] 最大等待毫秒数，默认 8 秒
  /// 如果 Shizuku 可用则立即返回 true（无需弹窗）
  Future<bool> requestPermissionAndWait({int maxWaitMs = 8000}) async {
    // 主动查询 Shizuku 状态
    final status = await DeviceService().getShizukuStatus();
    if (status['available'] == true && status['permitted'] == true) return true;
    if (DeviceService().isShizukuReady) return true;

    final triggered = await requestPermission();
    if (!triggered) return false;

    // 轮询等待 MediaProjection 就绪
    for (int i = 0; i < maxWaitMs ~/ 200; i++) {
      await Future.delayed(const Duration(milliseconds: 200));
      if (await hasPermission()) return true;
    }
    return await hasPermission();
  }

  /// 检查截图权限是否已授予且渲染管道可用
  ///
  /// Shizuku screencap 不需要 MediaProjection 权限
  Future<bool> hasPermission() async {
    // Shizuku 优先：screencap 无需弹窗授权
    // 用主动查询而非 EventChannel 状态，确保拿到最新值
    try {
      final status = await DeviceService().getShizukuStatus();
      final available = status['available'] == true;
      final permitted = status['permitted'] == true;
      debugPrint('[ScreenshotService] Shizuku status: available=$available permitted=$permitted');
      if (available && permitted) return true;
    } catch (e) {
      debugPrint('[ScreenshotService] getShizukuStatus error: $e');
    }
    // EventChannel 缓存兜底
    if (DeviceService().isShizukuReady) {
      debugPrint('[ScreenshotService] Shizuku ready via EventChannel cache');
      return true;
    }

    // 回退：MediaProjection
    try {
      final result = await _channel.invokeMethod<bool>('hasPermission');
      debugPrint('[ScreenshotService] MediaProjection hasPermission: $result');
      return result ?? false;
    } catch (e) {
      debugPrint('[ScreenshotService] hasPermission error: $e');
      return false;
    }
  }

  /// 验证截图能力是否真的可用（不只检查 token，还做一次试截图）
  Future<bool> isActuallyReady() async {
    if (!await hasPermission()) return false;
    // 做一次快速试截图验证管道可用
    final testResult = await capture();
    return testResult != null;
  }

  /// 确保截图管理器已初始化（用于 App 从后台回来重连）
  Future<bool> ensureReady() async {
    if (await hasPermission()) return true;
    return await requestPermissionAndWait();
  }

  /// 释放截图权限（停止 VirtualDisplay 和 FGS）
  Future<void> releasePermission() async {
    try {
      await _channel.invokeMethod('releasePermission');
    } catch (e) {
      debugPrint('ScreenshotService.releasePermission error: $e');
    }
  }

  /// 执行一次截图，返回截图信息
  /// 返回 null 表示截图失败
  /// Shizuku 可用时使用 shell screencap（无弹窗），否则走 MediaProjection
  Future<ScreenshotResult?> capture() async {
    // Priority 1: Shizuku shell screencap（无需权限弹窗）
    final shizukuResult = await _captureViaShizuku();
    if (shizukuResult != null) return shizukuResult;

    // Fallback: MediaProjection
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>('capture');
      if (result == null) return null;
      final path = result['path'] as String?;
      if (path == null || path.isEmpty) return null;
      return ScreenshotResult(
        filePath: path,
        width: (result['width'] as num?)?.toInt() ?? 0,
        height: (result['height'] as num?)?.toInt() ?? 0,
      );
    } catch (e) {
      debugPrint('ScreenshotService.capture error: $e');
      return null;
    }
  }

  /// Shizuku shell screencap 截图（无 MediaProjection 弹窗）
  Future<ScreenshotResult?> _captureViaShizuku() async {
    final ds = DeviceService();
    if (!ds.isShizukuReady) {
      final status = await ds.getShizukuStatus();
      if (!(status['available'] == true && status['permitted'] == true)) {
        debugPrint('[ScreenshotService] _captureViaShizuku: Shizuku not ready');
        return null;
      }
    }
    try {
      debugPrint('[ScreenshotService] _captureViaShizuku: calling shellScreenshot...');
      final path = await ds.shellScreenshot();
      debugPrint('[ScreenshotService] _captureViaShizuku: shellScreenshot returned: $path');
      if (path == null || path.isEmpty) return null;
      final file = File(path);
      if (!file.existsSync()) {
        debugPrint('[ScreenshotService] _captureViaShizuku: file not found at $path');
        return null;
      }
      debugPrint('[ScreenshotService] _captureViaShizuku: success, ${file.lengthSync()} bytes');
      return ScreenshotResult(filePath: path, width: 0, height: 0);
    } catch (e) {
      debugPrint('[ScreenshotService] _captureViaShizuku error: $e');
      return null;
    }
  }

  /// 截图并读取为字节数组（用于传给视觉模型）
  Future<Uint8List?> captureBytes() async {
    final result = await capture();
    if (result == null) return null;
    try {
      final file = File(result.filePath);
      if (!file.existsSync()) return null;
      return await file.readAsBytes();
    } catch (e) {
      debugPrint('ScreenshotService.captureBytes error: $e');
      return null;
    }
  }
}

class ScreenshotResult {
  final String filePath;
  final int width;
  final int height;

  const ScreenshotResult({
    required this.filePath,
    required this.width,
    required this.height,
  });
}