import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../repositories/local_storage_repository.dart';

/// 本地工作区边界。所有文件工具都必须经过此服务，禁止模型直接拼接任意路径。
class WorkspaceService {
  final LocalStorageRepository? storage;
  final String? Function(String chatId)? pathResolver;

  const WorkspaceService(this.storage, {this.pathResolver});

  String? pathForChat(String chatId) =>
      pathResolver?.call(chatId) ??
      storage?.getString('workspace_path_$chatId');

  Future<void> bind(String chatId, String path) async {
    final directory = Directory(path);
    if (!await directory.exists()) {
      throw ArgumentError('工作区不存在: $path');
    }
    await storage?.setString('workspace_path_$chatId', directory.absolute.path);
  }

  Directory? directoryForChat(String chatId) {
    final root = pathForChat(chatId);
    if (root == null || root.trim().isEmpty) return null;
    return Directory(root);
  }

  File resolveFile(String chatId, String relativePath) {
    final root = directoryForChat(chatId);
    if (root == null) throw StateError('当前聊天尚未绑定工作区。');
    final workspace = p.normalize(root.absolute.path);
    final candidate = p.normalize(p.join(workspace, relativePath));
    final relative = p.relative(candidate, from: workspace);
    if (relative == '..' || relative.startsWith('..${p.separator}')) {
      throw StateError('路径超出当前工作区范围。');
    }
    return File(candidate);
  }

  Future<String> read(String chatId, String relativePath,
      {int maxBytes = 200000}) async {
    final file = resolveFile(chatId, relativePath);
    if (!await file.exists()) throw StateError('文件不存在: $relativePath');
    final bytes = await file.readAsBytes();
    final clipped =
        bytes.length > maxBytes ? bytes.sublist(0, maxBytes) : bytes;
    return utf8.decode(clipped, allowMalformed: true);
  }

  Future<Map<String, dynamic>> write(
    String chatId,
    String relativePath,
    String content,
  ) async {
    final file = resolveFile(chatId, relativePath);
    await file.parent.create(recursive: true);
    final existed = await file.exists();
    final previous = existed ? await file.readAsString() : null;
    final backupPath = existed
        ? '${file.path}.solace-backup-${DateTime.now().millisecondsSinceEpoch}'
        : null;
    if (previous != null) await File(backupPath!).writeAsString(previous);
    await file.writeAsString(content);
    return {
      'path': relativePath,
      'created': !existed,
      'backupPath': backupPath,
      'previous': previous,
    };
  }

  Future<Map<String, dynamic>> edit(
    String chatId,
    String relativePath,
    String oldText,
    String newText,
  ) async {
    final file = resolveFile(chatId, relativePath);
    if (!await file.exists()) throw StateError('文件不存在: $relativePath');
    final content = await file.readAsString();
    final count = oldText.isEmpty ? 0 : oldText.allMatches(content).length;
    if (count == 0) throw StateError('未找到要替换的原文。');
    if (count > 1) throw StateError('原文匹配到 $count 处，请提供更精确的片段。');
    final previous = content;
    final backupPath =
        '${file.path}.solace-backup-${DateTime.now().millisecondsSinceEpoch}';
    await File(backupPath).writeAsString(previous);
    await file.writeAsString(content.replaceFirst(oldText, newText));
    return {'path': relativePath, 'replacements': 1, 'backupPath': backupPath};
  }

  Future<void> rollback(
      String chatId, String relativePath, String backupPath) async {
    final file = resolveFile(chatId, relativePath);
    final backup = File(backupPath);
    if (!await backup.exists()) throw StateError('回滚快照不存在。');
    await file.writeAsString(await backup.readAsString());
  }
}
