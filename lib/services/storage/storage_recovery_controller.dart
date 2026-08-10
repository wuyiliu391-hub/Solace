import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// 数据库启动失败时的恢复状态。
enum StorageRecoveryState { idle, retrying, ready, failed }

/// 数据库启动失败恢复控制器。
///
/// 职责（纯逻辑，便于测试）：
/// - 重试初始化；
/// - 把原始数据库文件复制到备份目录（不改动原文件）；
/// - 重置：先备份，再删除损坏数据库，等待下次启动重建。
class StorageRecoveryController extends ChangeNotifier {
  StorageRecoveryController({
    required this.initialize,
    required this.databasePath,
    this.backupDirectoryName = 'recovery_backups',
  });

  /// 重试数据库初始化（由外部注入，通常是 LocalStorageRepository.initialize）。
  final Future<void> Function() initialize;

  /// 解析数据库文件绝对路径（由外部注入，通常是 sqflite 的 getDatabasesPath + 库名）。
  final Future<String> Function() databasePath;

  /// 备份目录名（相对数据库文件所在目录）。
  final String backupDirectoryName;

  StorageRecoveryState _state = StorageRecoveryState.idle;
  StorageRecoveryState get state => _state;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  bool _busy = false;
  bool get busy => _busy;

  /// 重试数据库初始化。成功返回 true，失败返回 false 并保留错误信息。
  Future<bool> retry() async {
    if (_busy) return false;
    _busy = true;
    _state = StorageRecoveryState.retrying;
    _errorMessage = null;
    notifyListeners();
    try {
      await initialize();
      _state = StorageRecoveryState.ready;
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      _state = StorageRecoveryState.failed;
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<String> _resolveDbPath() async {
    final path = await databasePath();
    if (path.trim().isEmpty) throw StateError('数据库路径为空');
    return path;
  }

  /// 把原始数据库文件复制到备份目录，返回备份文件绝对路径。
  /// 不修改、不删除原文件。
  Future<String?> exportBackup() async {
    if (_busy) return null;
    _busy = true;
    notifyListeners();
    try {
      return await _copyBackup();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<String?> _copyBackup() async {
    final dbPath = await _resolveDbPath();
    final dbFile = File(dbPath);
    if (!await dbFile.exists()) return null;
    final backupDir = Directory(
      p.join(p.dirname(dbPath), backupDirectoryName),
    );
    await backupDir.create(recursive: true);
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final target = p.join(backupDir.path, 'solace-$stamp.db');
    await dbFile.copy(target);
    return target;
  }

  /// 重置数据库：先自动备份原文件，再删除数据库文件（下次启动会重建空库）。
  /// 返回备份文件路径；原文件不存在时返回 null 且不删除。
  Future<String?> resetDatabase() async {
    if (_busy) return null;
    _busy = true;
    notifyListeners();
    try {
      final dbPath = await _resolveDbPath();
      final dbFile = File(dbPath);
      if (!await dbFile.exists()) return null;
      final backup = await _copyBackup();
      await dbFile.delete();
      return backup;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }
}
