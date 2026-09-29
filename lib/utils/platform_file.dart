import 'package:flutter/foundation.dart' show kIsWeb;
import 'platform_io.dart';
import 'platform_path.dart';

/// 跨平台文件操作抽象层
/// Web 端所有文件操作返回 null 或空结果，不崩溃

/// 读取文件为字节（原生端读文件，Web 端返回 null）
Future<List<int>?> safeReadFileBytes(String path) async {
  if (kIsWeb) return null;
  try {
    final file = File(path);
    if (await file.exists()) {
      return await file.readAsBytes();
    }
    return null;
  } catch (_) {
    return null;
  }
}

/// 写入字节到文件，返回文件路径（Web 端返回 null）
Future<String?> safeWriteFileBytes(String path, List<int> bytes) async {
  if (kIsWeb) return null;
  try {
    final file = File(path);
    await file.writeAsBytes(bytes);
    return path;
  } catch (_) {
    return null;
  }
}

/// 复制文件，返回目标路径（Web 端返回 null）
Future<String?> safeCopyFile(String sourcePath, String destPath) async {
  if (kIsWeb) return null;
  try {
    final source = File(sourcePath);
    if (await source.exists()) {
      await source.copy(destPath);
      return destPath;
    }
    return null;
  } catch (_) {
    return null;
  }
}

/// 检查文件是否存在（Web 端返回 false）
Future<bool> safeFileExists(String path) async {
  if (kIsWeb) return false;
  try {
    return File(path).exists();
  } catch (_) {
    return false;
  }
}

/// 同步检查文件是否存在（Web 端返回 false）
bool safeFileExistsSync(String path) {
  if (kIsWeb) return false;
  try {
    return File(path).existsSync();
  } catch (_) {
    return false;
  }
}

/// 获取临时目录路径（Web 端返回 null）
Future<String?> safeTempDir() async {
  if (kIsWeb) return null;
  try {
    return await getTemporaryDirectoryPath();
  } catch (_) {
    return null;
  }
}

/// 获取应用文档目录路径（Web 端返回 null）
Future<String?> safeAppDir() async {
  if (kIsWeb) return null;
  try {
    return await getApplicationDocumentsDirectoryPath();
  } catch (_) {
    return null;
  }
}

/// gzip 压缩（Web 端返回原始数据）
List<int> safeGzipEncode(List<int> bytes) {
  if (kIsWeb) return bytes;
  try {
    return gzip.encode(bytes);
  } catch (_) {
    return bytes;
  }
}

/// gzip 解压（Web 端返回原始数据）
List<int> safeGzipDecode(List<int> bytes) {
  if (kIsWeb) return bytes;
  try {
    return gzip.decode(bytes);
  } catch (_) {
    return bytes;
  }
}