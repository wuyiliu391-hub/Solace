# ai_service.dart 拆分配置（split_class.py 输入）
CFG = {
    "file": "lib/services/ai_service.dart",
    "class_line": 132,
    "class_name": "AIService",
    "core_name": "_AIServiceCore",
    "freshness_marker": "_bingSearch = const BingCnMcpService",
    "core_fields": ["_storage", "_httpClient", "_memoryEngine", "_emotionEngine",
                    "_promptBuilder", "_bingSearch", "_lastCharacterGender",
                    "_lastCharacterName", "_lastParsedStatus", "_lastTurnState",
                    "_lastWebSearchTrace"],
    "ctor_old": """AIService(this._storage, {http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client() {
    _memoryEngine = MemoryEngine(_storage);
    _emotionEngine = EmotionEngine(_storage);
    _promptBuilder = PromptBuilder(
        _storage, _memoryEngine, _emotionEngine, DialogueStrategy());
  }""",
    "ctor_new": """  /// 依赖注入入口；字段声明见 [_AIServiceCore]
  AIService(LocalStorageRepository storage, {http.Client? httpClient})
      : super(storage, httpClient ?? http.Client()) {
    _memoryEngine = MemoryEngine(_storage);
    _emotionEngine = EmotionEngine(_storage);
    _promptBuilder = PromptBuilder(
        _storage, _memoryEngine, _emotionEngine, DialogueStrategy());
  }""",
    "core_text": """/// AIService 的字段基座：巨型服务拆分为多个 mixin part 后，
/// 各 mixin 通过 `on _AIServiceCore` 共享这些实例字段。
abstract class _AIServiceCore {
  _AIServiceCore(this._storage, this._httpClient);

  final LocalStorageRepository _storage;
  final http.Client _httpClient;
  late final MemoryEngine _memoryEngine;
  late final EmotionEngine _emotionEngine;
  late final PromptBuilder _promptBuilder;
  final BingCnMcpService _bingSearch = const BingCnMcpService();

  /// 最近一次请求的角色性别/名字（用于输出侧人称轻量纠错）
  String? _lastCharacterGender;
  String? _lastCharacterName;
  String? _lastParsedStatus;
  AiTurnState? _lastTurnState;
  Map<String, dynamic>? _lastWebSearchTrace;
}""",
    "cut_lines": [1046, 1676, 2260, 2918],
    "part_of": "../ai_service.dart",
    "parts": [
        {"main": True},
        {"file": "lib/services/ai_service/clean_split.dart",
         "directive": "ai_service/clean_split.dart",
         "mixin": "AIServiceCleanSplitApi",
         "doc": "// AIService 清洗/分句/繁简转换：响应清洗、分段、简洁截断等纯文本处理方法。"},
        {"file": "lib/services/ai_service/context_forgiveness.dart",
         "directive": "ai_service/context_forgiveness.dart",
         "mixin": "AIServiceContextApi",
         "doc": "// AIService 上下文构建与拉黑原谅判断：完整上下文消息、视觉编码、多模态组装。"},
        {"file": "lib/services/ai_service/history_filter.dart",
         "directive": "ai_service/history_filter.dart",
         "mixin": "AIServiceHistoryApi",
         "doc": "// AIService 历史过滤与联网搜索上下文：消息历史清洗、必应搜索注入。"},
        {"file": "lib/services/ai_service/memory_narrative.dart",
         "directive": "ai_service/memory_narrative.dart",
         "mixin": "AIServiceMemoryApi",
         "doc": "// AIService 记忆消息/反思/滚动摘要/群聊事件抽取与回忆场景叙事。"},
    ],
}
