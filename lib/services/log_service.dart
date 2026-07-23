import 'dart:async';
import 'package:flutter/foundation.dart';

enum LogLevel { debug, info, warn, error }

const Map<LogLevel, String> logLevelNames = {
  LogLevel.debug: 'DEBUG',
  LogLevel.info: 'INFO',
  LogLevel.warn: 'WARN',
  LogLevel.error: 'ERROR',
};

class LogEntry {
  final DateTime timestamp;
  final LogLevel level;
  final String module;
  final String message;
  final String? chatId;

  LogEntry({
    required this.timestamp,
    required this.level,
    required this.module,
    required this.message,
    this.chatId,
  });

  String toFormattedString() {
    final ts = timestamp.toString();
    return '[${ts.substring(0, 23)}] [${logLevelNames[level]}] [$module] $message';
  }
}

class LogService {
  static final LogService _instance = LogService._();
  static LogService get instance => _instance;
  LogService._();

  static const int _maxEntries = 1000;

  final List<LogEntry> _entries = [];
  final StreamController<List<LogEntry>> _controller =
      StreamController<List<LogEntry>>.broadcast();

  Stream<List<LogEntry>> get stream => _controller.stream;

  void _add(LogLevel level, String module, String message, {String? chatId}) {
    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      module: module,
      message: message,
      chatId: chatId,
    );
    _entries.add(entry);
    if (_entries.length > _maxEntries) {
      _entries.removeAt(0);
    }
    _controller.add(List.unmodifiable(_entries));
  }

  void d(String module, String message, {String? chatId}) =>
      _add(LogLevel.debug, module, message, chatId: chatId);

  void i(String module, String message, {String? chatId}) =>
      _add(LogLevel.info, module, message, chatId: chatId);

  void w(String module, String message, {String? chatId}) =>
      _add(LogLevel.warn, module, message, chatId: chatId);

  void e(String module, String message, {String? chatId}) {
    debugPrint('[ERROR] [$module] $message');
    _add(LogLevel.error, module, message, chatId: chatId);
  }

  List<LogEntry> getAll() => List.unmodifiable(_entries);

  List<LogEntry> getByChatId(String chatId) {
    return _entries.where((e) => e.chatId == chatId).toList();
  }

  String exportText({
    LogLevel? minLevel,
    String? module,
    String? chatId,
  }) {
    var entries = _entries;
    if (minLevel != null) {
      final levels = LogLevel.values;
      final minIndex = levels.indexOf(minLevel);
      entries = entries.where((e) => levels.indexOf(e.level) >= minIndex).toList();
    }
    if (module != null) {
      entries = entries.where((e) => e.module == module).toList();
    }
    if (chatId != null) {
      entries = entries.where((e) => e.chatId == chatId).toList();
    }
    return entries.map((e) => e.toFormattedString()).join('\n');
  }

  void clear() {
    _entries.clear();
    _controller.add([]);
  }
}
