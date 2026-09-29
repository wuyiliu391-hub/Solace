import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/constants.dart';
import '../models/ai_character.dart';
import 'memory_engine.dart';

/// 记忆重建状态
enum MemoryRebuildState { idle, rebuilding, completed, error }

/// 记忆重建服务 — 独立于页面生命周期，支持后台持续运行 + 断点续传
///
/// 单例模式，用户切换页面时重建任务不会中断。
/// 通过 SharedPreferences 持久化断点，支持：
/// - 切后台/杀进程后恢复
/// - 无限次续传
/// - 多角色交叉重建（每个角色独立断点）
class MemoryRebuildService {
  MemoryRebuildService._();
  static final MemoryRebuildService instance = MemoryRebuildService._();

  MemoryRebuildState _state = MemoryRebuildState.idle;
  String _statusText = '';
  int _processedMessages = 0;
  int _totalMessages = 0;
  String? _errorMessage;
  MemoryRebuildResult? _lastResult;
  String? _currentCharacterName;
  bool _isResuming = false;

  final _stateController = StreamController<MemoryRebuildState>.broadcast();
  final _progressController =
      StreamController<MemoryRebuildProgress>.broadcast();

  Stream<MemoryRebuildState> get stateStream => _stateController.stream;
  Stream<MemoryRebuildProgress> get progressStream =>
      _progressController.stream;

  MemoryRebuildState get state => _state;
  String get statusText => _statusText;
  int get processedMessages => _processedMessages;
  int get totalMessages => _totalMessages;
  bool get isRebuilding => _state == MemoryRebuildState.rebuilding;
  bool get isResuming => _isResuming;
  String? get errorMessage => _errorMessage;
  MemoryRebuildResult? get lastResult => _lastResult;
  String? get currentCharacterName => _currentCharacterName;

  // ─────────────────────── 断点持久化 ───────────────────────

  /// 保存断点到 SharedPreferences
  Future<void> _saveCheckpoint({
    required String characterId,
    required String userId,
    required String characterName,
    required int sessionIndex,
    required List<String> sessionIds,
    required int dbOffset,
    required int processedMessages,
    required int scannedMessages,
    required int totalBatches,
    required int skippedBatches,
    required int failedBatches,
    required int beforeMemoryCount,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode({
        'characterId': characterId,
        'userId': userId,
        'characterName': characterName,
        'sessionIndex': sessionIndex,
        'sessionIds': sessionIds,
        'dbOffset': dbOffset,
        'processedMessages': processedMessages,
        'scannedMessages': scannedMessages,
        'totalBatches': totalBatches,
        'skippedBatches': skippedBatches,
        'failedBatches': failedBatches,
        'beforeMemoryCount': beforeMemoryCount,
        'savedAt': DateTime.now().toIso8601String(),
      });
      await prefs.setString(PrefKeys.memoryRebuildCheckpoint, json);
      debugPrint('MemoryRebuildService: 断点已保存 sessionIdx=$sessionIndex '
          'offset=$dbOffset batches=$totalBatches processed=$processedMessages');
    } catch (e) {
      debugPrint('MemoryRebuildService: 保存断点失败: $e');
    }
  }

  /// 清除断点（重建完成或用户取消时）
  Future<void> _clearCheckpoint() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(PrefKeys.memoryRebuildCheckpoint);
      debugPrint('MemoryRebuildService: 断点已清除');
    } catch (e) {
      debugPrint('MemoryRebuildService: 清除断点失败: $e');
    }
  }

  /// 读取断点（静态方法，供 UI 层检查是否有未完成重建）
  static Future<Map<String, dynamic>?> loadCheckpoint() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(PrefKeys.memoryRebuildCheckpoint);
      if (json == null) return null;
      return jsonDecode(json) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('MemoryRebuildService: 读取断点失败: $e');
      return null;
    }
  }

  /// 判断是否有可恢复的断点
  static Future<bool> hasPendingCheckpoint() async {
    final checkpoint = await loadCheckpoint();
    return checkpoint != null;
  }

  // ─────────────────────── 重建入口 ───────────────────────

  /// 启动记忆重建。重复调用时如果正在重建则忽略。
  Future<void> startRebuild({
    required MemoryEngine engine,
    required AICharacter character,
    required String userId,
  }) async {
    if (_state == MemoryRebuildState.rebuilding) return;

    _state = MemoryRebuildState.rebuilding;
    _statusText = '正在扫描历史聊天记录...';
    _processedMessages = 0;
    _totalMessages = 0;
    _errorMessage = null;
    _lastResult = null;
    _currentCharacterName = character.name;
    _isResuming = false;
    _emitState();
    _emitProgress();

    try {
      final result = await engine.rebuildMemoriesFromHistory(
        character: character,
        userId: userId,
        onProgress: (processed, total) {
          _processedMessages = processed;
          _totalMessages = total;
          _statusText = '已处理 $processed / $total 条消息';
          _emitProgress();
        },
        onCheckpoint: (cp) async {
          await _saveCheckpoint(
            characterId: cp.characterId,
            userId: cp.userId,
            characterName: character.name,
            sessionIndex: cp.sessionIndex,
            sessionIds: cp.sessionIds,
            dbOffset: cp.dbOffset,
            processedMessages: cp.processedMessages,
            scannedMessages: cp.scannedMessages,
            totalBatches: cp.totalBatches,
            skippedBatches: cp.skippedBatches,
            failedBatches: cp.failedBatches,
            beforeMemoryCount: cp.beforeMemoryCount,
          );
        },
      );

      _lastResult = result;
      _state = MemoryRebuildState.completed;
      _statusText = '';
      await _clearCheckpoint();
      _emitState();
      _emitProgress();
    } catch (e) {
      _state = MemoryRebuildState.error;
      _errorMessage = '记忆重建失败：$e';
      _statusText = '';
      // 错误时保留断点，下次可恢复
      debugPrint('MemoryRebuildService: $e');
      _emitState();
      _emitProgress();
    }
  }

  /// 从断点恢复重建（杀后台 / 切走后回来）
  Future<void> resumeFromCheckpoint({
    required MemoryEngine engine,
  }) async {
    if (_state == MemoryRebuildState.rebuilding) return;

    final checkpoint = await loadCheckpoint();
    if (checkpoint == null) {
      debugPrint('MemoryRebuildService: 无断点可恢复');
      return;
    }

    final characterId = checkpoint['characterId'] as String;
    final userId = checkpoint['userId'] as String;
    final characterName = checkpoint['characterName'] as String? ?? '未知角色';

    _state = MemoryRebuildState.rebuilding;
    _statusText = '正在从断点恢复重建...';
    _currentCharacterName = characterName;
    _isResuming = true;
    _processedMessages = checkpoint['processedMessages'] as int? ?? 0;
    _errorMessage = null;
    _lastResult = null;
    _emitState();
    _emitProgress();

    try {
      final result = await engine.rebuildMemoriesFromHistory(
        characterId: characterId,
        userId: userId,
        checkpoint: checkpoint,
        onProgress: (processed, total) {
          _processedMessages = processed;
          _totalMessages = total;
          _statusText = '已处理 $processed / $total 条消息';
          _emitProgress();
        },
        onCheckpoint: (cp) async {
          await _saveCheckpoint(
            characterId: cp.characterId,
            userId: cp.userId,
            characterName: characterName,
            sessionIndex: cp.sessionIndex,
            sessionIds: cp.sessionIds,
            dbOffset: cp.dbOffset,
            processedMessages: cp.processedMessages,
            scannedMessages: cp.scannedMessages,
            totalBatches: cp.totalBatches,
            skippedBatches: cp.skippedBatches,
            failedBatches: cp.failedBatches,
            beforeMemoryCount: cp.beforeMemoryCount,
          );
        },
      );

      _lastResult = result;
      _state = MemoryRebuildState.completed;
      _statusText = '';
      _isResuming = false;
      await _clearCheckpoint();
      _emitState();
      _emitProgress();
    } catch (e) {
      _state = MemoryRebuildState.error;
      _errorMessage = '记忆重建失败：$e';
      _statusText = '';
      _isResuming = false;
      debugPrint('MemoryRebuildService resume: $e');
      _emitState();
      _emitProgress();
    }
  }

  /// 取消重建并清除断点
  Future<void> cancelAndClear() async {
    _state = MemoryRebuildState.idle;
    _statusText = '';
    _processedMessages = 0;
    _totalMessages = 0;
    _errorMessage = null;
    _lastResult = null;
    _currentCharacterName = null;
    _isResuming = false;
    await _clearCheckpoint();
    _emitState();
    _emitProgress();
  }

  /// 重置为空闲状态（用户关闭结果提示后调用）
  void reset() {
    _state = MemoryRebuildState.idle;
    _statusText = '';
    _processedMessages = 0;
    _totalMessages = 0;
    _errorMessage = null;
    _lastResult = null;
    _currentCharacterName = null;
    _isResuming = false;
    _emitState();
    _emitProgress();
  }

  void _emitState() {
    if (!_stateController.isClosed) {
      _stateController.add(_state);
    }
  }

  void _emitProgress() {
    if (!_progressController.isClosed) {
      _progressController.add(MemoryRebuildProgress(
        state: _state,
        statusText: _statusText,
        processedMessages: _processedMessages,
        totalMessages: _totalMessages,
        characterName: _currentCharacterName,
        errorMessage: _errorMessage,
        result: _lastResult,
        isResuming: _isResuming,
      ));
    }
  }

  void dispose() {
    _stateController.close();
    _progressController.close();
  }
}

/// 重建进度数据快照
class MemoryRebuildProgress {
  final MemoryRebuildState state;
  final String statusText;
  final int processedMessages;
  final int totalMessages;
  final String? characterName;
  final String? errorMessage;
  final MemoryRebuildResult? result;
  final bool isResuming;

  const MemoryRebuildProgress({
    required this.state,
    required this.statusText,
    required this.processedMessages,
    required this.totalMessages,
    this.characterName,
    this.errorMessage,
    this.result,
    this.isResuming = false,
  });
}
