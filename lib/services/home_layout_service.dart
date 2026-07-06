import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_item.dart';
import '../screens/home/data/default_apps.dart';

/// 桌面布局持久化服务
///
/// 使用 SharedPreferences 存储布局 JSON（数据量小，避免改 DB schema）
/// 如果未来布局变复杂（文件夹嵌套等），可迁移到 SQLite
class HomeLayoutService {
  static const _keyPrefix = 'home_layout_';
  static const _homeWallpaperPrefix = 'home_wallpaper_';
  static const _lockWallpaperPrefix = 'lock_wallpaper_';

  /// 加载用户桌面布局
  Future<HomeLayout> loadLayout(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString('$_keyPrefix$userId');
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final map = jsonDecode(jsonStr) as Map<String, dynamic>;
        return HomeLayout.fromJson(map);
      }
    } catch (e) {
      debugPrint('HomeLayoutService: loadLayout failed: $e');
    }
    return DefaultApps.defaultLayout;
  }

  /// 保存用户桌面布局
  Future<void> saveLayout(String userId, HomeLayout layout) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = jsonEncode(layout.toJson());
      await prefs.setString('$_keyPrefix$userId', jsonStr);
    } catch (e) {
      debugPrint('HomeLayoutService: saveLayout failed: $e');
    }
  }

  // ─── 主页壁纸 ───

  Future<String?> loadHomeWallpaper(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('$_homeWallpaperPrefix$userId');
  }

  Future<void> saveHomeWallpaper(String userId, String? path) async {
    final prefs = await SharedPreferences.getInstance();
    if (path == null) {
      await prefs.remove('$_homeWallpaperPrefix$userId');
    } else {
      await prefs.setString('$_homeWallpaperPrefix$userId', path);
    }
  }

  // ─── 锁屏壁纸 ───

  Future<String?> loadLockWallpaper(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('$_lockWallpaperPrefix$userId');
  }

  Future<void> saveLockWallpaper(String userId, String? path) async {
    final prefs = await SharedPreferences.getInstance();
    if (path == null) {
      await prefs.remove('$_lockWallpaperPrefix$userId');
    } else {
      await prefs.setString('$_lockWallpaperPrefix$userId', path);
    }
  }

  // ─── 壁纸文件管理 ───

  /// 复制图片到应用永久目录，返回新路径
  Future<String?> copyImageToAppDir(String sourcePath) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final wallpaperDir = Directory('${appDir.path}/wallpapers');
      if (!wallpaperDir.existsSync()) {
        wallpaperDir.createSync(recursive: true);
      }
      final ext = sourcePath.split('.').last.toLowerCase();
      final fileName = 'wallpaper_${DateTime.now().millisecondsSinceEpoch}.$ext';
      final destPath = '${wallpaperDir.path}/$fileName';
      final sourceFile = File(sourcePath);
      await sourceFile.copy(destPath);
      return destPath;
    } catch (e) {
      debugPrint('HomeLayoutService: copyImageToAppDir failed: $e');
      return null;
    }
  }

  /// 删除壁纸文件
  Future<void> deleteWallpaperFile(String? path) async {
    if (path == null || path.isEmpty) return;
    try {
      final file = File(path);
      if (file.existsSync()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('HomeLayoutService: deleteWallpaperFile failed: $e');
    }
  }

  /// 兼容旧版 loadWallpaperPath（指向主页壁纸）
  Future<String?> loadWallpaperPath(String userId) => loadHomeWallpaper(userId);
  Future<void> saveWallpaperPath(String userId, String? path) => saveHomeWallpaper(userId, path);

  /// 重置为默认布局
  Future<void> resetToDefault(String userId) async {
    await saveLayout(userId, DefaultApps.defaultLayout);
  }
}
