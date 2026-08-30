// ChatBloc 实例字段（拆分生成；链首 mixin，承载实例字段）
part of '../chat_bloc.dart';

mixin _ChatBlocCore {
  late final LocalStorageRepository _storage;

  late final AIService _aiService;

  late final PureAIService _pureAIService;

  late final MemoryEngine _memoryEngine;

  late final EmotionEngine _emotionEngine;

  late final CharacterCommitmentService _commitmentService;

  late final RelationshipContextService _relationshipService;

  final ProactivePolicyService _proactivePolicy = ProactivePolicyService();

  final _uuid = const Uuid();

  DateTime? _lastMessageTime;

  final Map<String, int> _dailyMsgCount = {};

  final Map<String, int> _hourlyMsgCount = {};

  final Map<String, List<int>> _msgLengths = {};

  final Map<String, int> _consecutiveAiReplies = {};

  final Map<String, DateTime> _lastErrorTime = {};

  final Set<String> _errorSessions = {};

  final Set<String> _emotionLockedSessions = {};

  final Map<String, int> _loadedOffsets = {};

  final Map<String, bool> _hasMoreByChat = {};

  final Set<String> _loadingMore = {};

  final Set<String> _activeObservations = {};

  final Map<String, List<String>> _pendingBlockMessages = {};

  final Map<String, DateTime> _lastObservationTrigger = {};

  final Map<String, int> _lastMemoryExtractionUserCount = {};

  final Map<String, AiTurnState?> _completedTurnStates = {};


  /// 微记忆冷却时间戳，按 chatId 跟踪，避免同会话短时刷入多条
  final Map<String, DateTime> _lastMicroTime = {};

  late final BtAgentExecutionService _btAgentExecutionService;

  late final StoryStateService _storyStateService;

  late final ProactiveDecisionEngine _proactiveDecisionEngine;

  late final AIServiceAdapter? _aiAdapter;


  final WellbeingService _wellbeing = WellbeingService();

}
