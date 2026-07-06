import 'dart:io';
import 'dart:typed_data';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;

/// 自定义图标服务
///
/// 管理用户自定义的首页功能图标（相册照片替换默认矢量图标）
/// 使用 Hive 本地存储映射关系：功能ID → 本地图片路径
class CustomIconService {
  static const String _boxName = 'custom_icons';
  static Box<String>? _box;

  /// 初始化 Hive 存储
  static Future<void> init() async {
    _box = await Hive.openBox<String>(_boxName);
  }

  /// 获取某个功能的自定义图标路径，无则返回 null
  static String? getCustomIconPath(String appId) {
    return _box?.get(appId);
  }

  /// 判断某个功能是否有自定义图标
  static bool hasCustomIcon(String appId) {
    final path = _box?.get(appId);
    if (path == null) return false;
    // 验证文件是否仍然存在
    return File(path).existsSync();
  }

  /// 设置自定义图标路径
  static Future<void> setCustomIcon(String appId, String imagePath) async {
    await _box?.put(appId, imagePath);
  }

  /// 恢复默认图标（删除自定义记录 + 清理缓存文件）
  static Future<void> restoreDefault(String appId) async {
    final path = _box?.get(appId);
    if (path != null) {
      try {
        final file = File(path);
        if (file.existsSync()) {
          await file.delete();
        }
      } catch (_) {}
      await _box?.delete(appId);
    }
  }

  /// 从相册选择图片并居中裁剪为正方形
  /// 返回裁剪后的本地文件路径，取消则返回 null
  static Future<String?> pickAndCropImage() async {
    // 1. 选择图片
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );

    if (result == null || result.files.isEmpty) return null;

    final filePath = result.files.first.path;
    if (filePath == null) return null;

    // 2. 读取并居中裁剪为正方形
    final bytes = await File(filePath).readAsBytes();
    final original = img.decodeImage(bytes);
    if (original == null) return null;

    final size = original.width < original.height ? original.width : original.height;
    final x = (original.width - size) ~/ 2;
    final y = (original.height - size) ~/ 2;
    final cropped = img.copyCrop(original, x: x, y: y, width: size, height: size);

    // 3. 缩放到 256x256（图标够用）
    final resized = img.copyResize(cropped, width: 256, height: 256);

    // 4. 保存到 App 缓存目录
    final appDir = await getApplicationDocumentsDirectory();
    final iconsDir = Directory('${appDir.path}/custom_icons');
    if (!iconsDir.existsSync()) {
      await iconsDir.create(recursive: true);
    }

    final fileName = 'icon_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final savedPath = '${iconsDir.path}/$fileName';

    final jpg = img.encodeJpg(resized, quality: 90);
    await File(savedPath).writeAsBytes(jpg);

    return savedPath;
  }

  /// 清理所有自定义图标缓存
  static Future<void> clearAll() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final iconsDir = Directory('${appDir.path}/custom_icons');
      if (iconsDir.existsSync()) {
        await iconsDir.delete(recursive: true);
      }
    } catch (_) {}
    await _box?.clear();
  }
}
