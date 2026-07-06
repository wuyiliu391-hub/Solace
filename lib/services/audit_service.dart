import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 审计日志服务
///
/// 记录 Core Hub 的关键操作，用于调试和问题追踪。
/// 日志持久化到 SharedPreferences，最多保留 200 条。
class AuditService {
  final SharedPreferences _prefs;

  static const String _storageKey = 'core_hub_audit_log';
  static const int _maxEntries = 200;

  final List<AuditEntry> _entries = [];

  AuditService(this._prefs);

  /// 从持久化恢复日志
  Future<void> init() async {
    final json = _prefs.getString(_storageKey);
    if (json != null) {
      try {
        final list = jsonDecode(json) as List<dynamic>;
        _entries.clear();
        for (final item in list) {
          _entries.add(AuditEntry.fromJson(item as Map<String, dynamic>));
        }
      } catch (e) {
        debugPrint('AuditService: 日志恢复失败 — $e');
      }
    }
  }

  /// 记录一条审计日志
  Future<void> log({
    required String category,
    required String action,
    String? characterId,
    String? detail,
    Map<String, dynamic>? metadata,
  }) async {
    final entry = AuditEntry(
      timestamp: DateTime.now(),
      category: category,
      action: action,
      characterId: characterId,
      detail: detail,
      metadata: metadata,
    );

    _entries.add(entry);

    // 超出上限时移除最旧的
    while (_entries.length > _maxEntries) {
      _entries.removeAt(0);
    }

    await _persist();
    debugPrint('AuditLog: [$category] $action${detail != null ? " — $detail" : ""}');
  }

  /// 获取所有日志条目
  List<AuditEntry> get entries => List.unmodifiable(_entries);

  /// 按类别过滤
  List<AuditEntry> getByCategory(String category) {
    return _entries.where((e) => e.category == category).toList();
  }

  /// 按角色过滤
  List<AuditEntry> getByCharacter(String characterId) {
    return _entries.where((e) => e.characterId == characterId).toList();
  }

  /// 获取最近 N 条
  List<AuditEntry> getRecent(int count) {
    final start = _entries.length > count ? _entries.length - count : 0;
    return _entries.sublist(start);
  }

  /// 清空日志
  Future<void> clear() async {
    _entries.clear();
    await _persist();
  }

  /// 持久化到 SharedPreferences
  Future<void> _persist() async {
    final json = jsonEncode(_entries.map((e) => e.toJson()).toList());
    await _prefs.setString(_storageKey, json);
  }
}

/// 单条审计日志条目
class AuditEntry {
  final DateTime timestamp;
  final String category;
  final String action;
  final String? characterId;
  final String? detail;
  final Map<String, dynamic>? metadata;

  AuditEntry({
    required this.timestamp,
    required this.category,
    required this.action,
    this.characterId,
    this.detail,
    this.metadata,
  });

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'category': category,
        'action': action,
        if (characterId != null) 'characterId': characterId,
        if (detail != null) 'detail': detail,
        if (metadata != null) 'metadata': metadata,
      };

  factory AuditEntry.fromJson(Map<String, dynamic> json) => AuditEntry(
        timestamp: DateTime.parse(json['timestamp'] as String),
        category: json['category'] as String,
        action: json['action'] as String,
        characterId: json['characterId'] as String?,
        detail: json['detail'] as String?,
        metadata: json['metadata'] as Map<String, dynamic>?,
      );

  @override
  String toString() =>
      '[${timestamp.toIso8601String()}] [$category] $action${detail != null ? " — $detail" : ""}';
}
