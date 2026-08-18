# memory_engine.dart 拆分配置（split_class.py 输入）
CFG = {
    "file": "lib/services/memory_engine.dart",
    "class_line": 134,
    "class_name": "MemoryEngine",
    "core_name": "_MemoryEngineCore",
    "freshness_marker": "getConversationSummariesForPrompt",
    "core_fields": ["_storage", "_httpClient"],
    "ctor_old": """MemoryEngine(this._storage, {http.Client? httpClient})
      : _httpClient = httpClient;""",
    "ctor_new": """  MemoryEngine(LocalStorageRepository storage, {http.Client? httpClient})
      : super(storage, httpClient);""",
    "core_text": """/// MemoryEngine 的字段基座：巨型引擎拆分为多个 mixin part 后，
/// 各 mixin 通过 `on _MemoryEngineCore` 共享这些实例字段。
abstract class _MemoryEngineCore {
  _MemoryEngineCore(this._storage, this._httpClient);

  final LocalStorageRepository _storage;
  final http.Client? _httpClient; // 测试注入用（默认走顶层 http.post）

  // ---- 跨 mixin 调用的方法抽象声明（实现在主类或后续 mixin，全链可见）----

  Future<void> _saveWithSummary(Memory memory);

  Future<List<Memory>> loadSocialMemories(String characterId);

  bool _memoryMatchesTopic(Memory memory, String currentMessage);

  Future<String> _getRecentStatesCompact({
    required String characterId,
    required String userId,
  });

  List<(Memory, double)> _scoreMemories(
      List<Memory> memories, String currentMessage);

  String? _formatMemoryLine(Memory memory);
}""",
    "cut_lines": [2024, 2560],
    "part_of": "../memory_engine.dart",
    "parts": [
        {"main": True},
        {"file": "lib/services/memory_engine/eh_summary.dart",
         "directive": "memory_engine/eh_summary.dart",
         "mixin": "MemoryEngineEhSummaryApi",
         "doc": "// MemoryEngine 艾宾浩斯热度系统与滚动摘要（永久记忆档案）。"},
        {"file": "lib/services/memory_engine/compat_cross.dart",
         "directive": "memory_engine/compat_cross.dart",
         "mixin": "MemoryEngineCompatCrossApi",
         "doc": "// MemoryEngine 外部调用兼容方法与跨角色记忆互通。"},
    ],
}
