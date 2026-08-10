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
    if (await FileSystemEntity.type(path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw ArgumentError('不能绑定符号链接目录，请选择真实目录: $path');
    }
    final canonicalPath = await directory.resolveSymbolicLinks();
    final canonicalDirectory = Directory(canonicalPath);
    if (!await canonicalDirectory.exists()) {
      throw ArgumentError('工作区目录无法访问: $path');
    }
    await storage?.setString(
      'workspace_path_$chatId',
      p.normalize(canonicalDirectory.absolute.path),
    );
  }

  Directory? directoryForChat(String chatId) {
    final root = pathForChat(chatId);
    if (root == null || root.trim().isEmpty) return null;
    return Directory(root);
  }

  String _workspaceRelativeBackupPath(String chatId, String backupPath) {
    final root = directoryForChat(chatId);
    if (root == null) throw StateError('当前聊天尚未绑定工作区。');
    final workspace = p.normalize(root.absolute.path);
    final candidate = p.isAbsolute(backupPath)
        ? p.normalize(backupPath)
        : p.normalize(p.join(workspace, backupPath));
    final relative = p.relative(candidate, from: workspace);
    if (relative == '..' || relative.startsWith('..${p.separator}')) {
      throw StateError('回滚快照必须位于当前工作区内。');
    }
    return relative;
  }

  Future<void> _rejectSymlinks(String chatId, String relativePath) async {
    final root = directoryForChat(chatId);
    if (root == null) throw StateError('当前聊天尚未绑定工作区。');
    final workspace = p.normalize(root.absolute.path);
    final candidate = resolveFile(chatId, relativePath);
    final relative = p.relative(candidate.path, from: workspace);
    if (relative == '.') return;

    var current = workspace;
    for (final segment in p.split(relative)) {
      current = p.join(current, segment);
      if (await FileSystemEntity.type(current, followLinks: false) ==
          FileSystemEntityType.link) {
        throw StateError('工作区工具拒绝操作符号链接: $relativePath');
      }
    }
  }

  Future<File> _resolveBackupFile(String chatId, String backupPath) async {
    final relative = _workspaceRelativeBackupPath(chatId, backupPath);
    final backup = resolveFile(chatId, relative);
    await _rejectSymlinks(chatId, relative);
    return backup;
  }

  Future<String> _readLimited(File file, int maxBytes) async {
    if (maxBytes <= 0) return '';
    final chunks = <int>[];
    await for (final chunk in file.openRead(0, maxBytes)) {
      chunks.addAll(chunk);
    }
    return utf8.decode(
      chunks.length > maxBytes ? chunks.sublist(0, maxBytes) : chunks,
      allowMalformed: true,
    );
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

  static const _snapshotPrefix = 'workspace_snapshot_';
  static const _snapshotCounterPrefix = 'workspace_snapshot_counter_';

  Future<String> _generateSnapshotId(String chatId) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final counter = storage?.getString('$_snapshotCounterPrefix$chatId');
    final next = (int.tryParse(counter ?? '') ?? 0) + 1;
    await storage?.setString('$_snapshotCounterPrefix$chatId', '$next');
    return 'snap-$chatId-$now-$next';
  }

  Future<void> _saveSnapshotMapping(
      String chatId, String snapshotId, String backupPath) {
    final workspaceRoot = p.normalize(directoryForChat(chatId)!.absolute.path);
    final relative = p.relative(backupPath, from: workspaceRoot);
    if (relative == '..' || relative.startsWith('..${p.separator}')) {
      throw StateError('回滚快照必须位于当前工作区内。');
    }
    return storage?.setString('$_snapshotPrefix$snapshotId', relative) ??
        Future.value();
  }

  String? _resolveSnapshotPath(String chatId, String snapshotId) =>
      storage?.getString('$_snapshotPrefix$snapshotId');
  Future<List<Map<String, dynamic>>> listDirectory(
    String chatId,
    String relativePath, {
    int maxEntries = 200,
  }) async {
    final root = directoryForChat(chatId);
    if (root == null) throw StateError('当前聊天尚未绑定工作区。');
    final base = relativePath.trim().isEmpty
        ? root
        : Directory(resolveFile(chatId, relativePath).path);
    await _rejectSymlinks(chatId, relativePath);
    if (!await base.exists()) throw StateError('目录不存在: $relativePath');
    final entries = <Map<String, dynamic>>[];
    await for (final entity in base.list(followLinks: false)) {
      if (entries.length >= maxEntries) break;
      if (await FileSystemEntity.type(entity.path, followLinks: false) ==
          FileSystemEntityType.link) {
        continue;
      }
      final stat = await entity.stat();
      entries.add({
        'name': p.basename(entity.path),
        'type': entity is Directory ? 'directory' : 'file',
        'size': entity is File ? stat.size : null,
        'modifiedAt': stat.modified.toIso8601String(),
      });
    }
    entries.sort((a, b) {
      final aDir = a['type'] == 'directory' ? 0 : 1;
      final bDir = b['type'] == 'directory' ? 0 : 1;
      return aDir != bDir
          ? aDir.compareTo(bDir)
          : (a['name'] as String).compareTo(b['name'] as String);
    });
    return entries;
  }

  Future<String> read(String chatId, String relativePath,
      {int maxBytes = 200000}) async {
    final file = resolveFile(chatId, relativePath);
    await _rejectSymlinks(chatId, relativePath);
    if (!await file.exists()) throw StateError('文件不存在: $relativePath');
    return _readLimited(file, maxBytes);
  }

  Future<Map<String, dynamic>> write(
    String chatId,
    String relativePath,
    String content,
  ) async {
    final file = resolveFile(chatId, relativePath);
    await _rejectSymlinks(chatId, relativePath);
    await file.parent.create(recursive: true);
    final existed = await file.exists();
    final previous = existed ? await file.readAsString() : null;
    final backupPath = existed
        ? '${file.path}.solace-backup-${DateTime.now().millisecondsSinceEpoch}'
        : null;
    final snapshotId = existed ? await _generateSnapshotId(chatId) : null;
    if (previous != null) {
      await File(backupPath!).writeAsString(previous);
      await _saveSnapshotMapping(chatId, snapshotId!, backupPath);
    }
    await file.writeAsString(content);
    return {
      'path': relativePath,
      'created': !existed,
      'snapshotId': snapshotId,
    };
  }

  Future<Map<String, dynamic>> edit(
    String chatId,
    String relativePath,
    String oldText,
    String newText,
  ) async {
    final file = resolveFile(chatId, relativePath);
    await _rejectSymlinks(chatId, relativePath);
    if (!await file.exists()) throw StateError('文件不存在: $relativePath');
    if (await file.length() > 4 * 1024 * 1024) {
      throw StateError('文件过大，edit_file 仅支持 4 MB 以内的文本文件。');
    }
    final content = await file.readAsString();
    final count = oldText.isEmpty ? 0 : oldText.allMatches(content).length;
    if (count == 0) throw StateError('未找到要替换的原文。');
    if (count > 1) throw StateError('原文匹配到 $count 处，请提供更精确的片段。');
    final previous = content;
    final backupPath =
        '${file.path}.solace-backup-${DateTime.now().millisecondsSinceEpoch}';
    final snapshotId = await _generateSnapshotId(chatId);
    await File(backupPath).writeAsString(previous);
    await _saveSnapshotMapping(chatId, snapshotId, backupPath);
    await file.writeAsString(content.replaceFirst(oldText, newText));
    return {
      'path': relativePath,
      'replacements': 1,
      'snapshotId': snapshotId,
    };
  }

  Future<void> rollback(
      String chatId, String relativePath, String snapshotId) async {
    final file = resolveFile(chatId, relativePath);
    await _rejectSymlinks(chatId, relativePath);
    final relativeBackup = _resolveSnapshotPath(chatId, snapshotId);
    if (relativeBackup == null || relativeBackup.trim().isEmpty) {
      throw StateError('回滚快照不存在或已失效。');
    }
    final backup = await _resolveBackupFile(chatId, relativeBackup);
    if (!await backup.exists()) throw StateError('回滚快照不存在。');
    await file.writeAsString(await backup.readAsString());
  }
}
