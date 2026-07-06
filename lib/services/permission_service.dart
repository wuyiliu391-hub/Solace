import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart';
import 'notification_service.dart';

class PermissionService {
  static Future<bool> _isHuawei() async {
    try {
      final os = Platform.operatingSystemVersion.toLowerCase();
      if (os.contains('huawei') || os.contains('harmony')) return true;
      try {
        final r = await Process.run('getprop', ['ro.product.manufacturer']);
        return r.stdout.toString().trim().toLowerCase() == 'huawei';
      } catch (e) {
        debugPrint('华为检测命令失败: $e');
        return false;
      }
    } catch (e) {
      debugPrint('华为检测失败: $e');
      return false;
    }
  }

  static Future<void> requestRequiredPermissions() async {
    try {
      debugPrint('开始检查权限...');
      if (Platform.isAndroid) {
        final isHuawei = await _isHuawei();
        debugPrint('华为设备: $isHuawei');

        // 1. 相机
        await _safeRequest(Permission.camera);

        // 2. 麦克风（语音通话、语音消息需要）
        await _safeRequest(Permission.microphone);

        // 3. 定位
        await _safeRequest(Permission.location);

        // 3. 存储/图片 — Permission.storage 内部自动适配 API 级别
        await _safeRequest(Permission.storage);

        // 4. Android 13+ 专用权限（非华为补充请求）
        if (!isHuawei) {
          await _safeRequest(Permission.photos);
          await _safeRequest(Permission.videos);
        }

        // 4. Android 11+ 管理全部文件（模型下载）
        await _safeRequest(Permission.manageExternalStorage);

        await _requestNotificationPermission();
      } else {
        await _safeRequest(Permission.camera);
        await _safeRequest(Permission.photos);
        await _requestNotificationPermission();
      }
      debugPrint('权限申请完成');
    } catch (e) {
      debugPrint('权限申请出错: $e');
    }
  }

  static Future<bool> _safeRequest(Permission perm) async {
    try {
      final status = await perm.status.timeout(const Duration(seconds: 2));
      if (status.isGranted) return true;
      if (status.isPermanentlyDenied) return false;
      await perm.request().timeout(const Duration(seconds: 5));
      final after = await perm.status.timeout(const Duration(seconds: 2));
      return after.isGranted;
    } catch (e) {
      debugPrint('请求权限 ${perm.toString()} 超时/失败: $e');
      return false;
    }
  }

  static Future<void> _requestNotificationPermission() async {
    try {
      final notificationService = NotificationService();
      await notificationService.initialize();
      await notificationService.requestPermission();
    } catch (e) {
      debugPrint('申请通知权限出错: $e');
    }
  }

  static Future<bool> hasStoragePermission() async {
    try {
      if (Platform.isAndroid) {
        return await _safeCheck(Permission.storage) ||
               await _safeCheck(Permission.photos);
      }
      return await _safeCheck(Permission.photos);
    } catch (e) {
      debugPrint('检查存储权限出错: $e');
      return false;
    }
  }

  static Future<bool> hasCameraPermission() async {
    return _safeCheck(Permission.camera);
  }

  static Future<bool> requestCameraPermission() async {
    return _safeRequest(Permission.camera);
  }

  static Future<bool> requestStoragePermission() async {
    if (Platform.isAndroid) {
      final storage = await _safeRequest(Permission.storage);
      final photos = await _safeRequest(Permission.photos);
      return storage || photos;
    }
    return _safeRequest(Permission.photos);
  }

  static Future<bool> _safeCheck(Permission perm) async {
    try {
      final status = await perm.status;
      return status.isGranted;
    } catch (e) {
      debugPrint('权限检查失败: $e');
      return false;
    }
  }
}
