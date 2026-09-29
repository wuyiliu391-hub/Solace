// _ChatDetailScreenState 实例字段（拆分生成；链首 mixin，承载实例字段）
part of '../chat_detail_screen.dart';

mixin _StateCore {
  final TextEditingController _messageController = TextEditingController();

  final FocusNode _messageFocusNode = FocusNode();

  final ScrollController _scrollController = ScrollController();

  late ChatBloc _chatBloc;

  ChatSession? _currentSession;

  bool _hasSettingsChanged = false;

  bool _isBlockedByAI = false;

  bool _isBlockedByUser = false;

  bool _userScrolledUp = false;

  bool _isNearBottom = true;

  List<StickerPack> _stickerPacks = [];

  bool _isLoadingStickerPacks = false;

  Timer? _silenceTimer;

  bool _aiBrokeSilence = false;

  String? _aiPersonality;
  // 使用 AI 为本轮选择的黄脸 emoji；不再使用固定的大脑图标。

  String _turnEmoji = '🙂';

  String? _displayName;

  String _turnEmotion = '等待互动';

  String _turnThought = '下一轮对话结束后，这里会显示 TA 的最新想法。';

  double _turnIntensity = 0;

  ReplyMode? _replyMode;

  bool _enableProactiveMessage = true;

  bool _isSearching = false;

  String _searchQuery = '';
  // 多选模式（批量删除 / 收藏）

  bool _selectionMode = false;

  final Set<String> _selectedIds = <String>{};

  List<ChatMessage> _searchResults = [];

  bool _searchLoading = false;

  bool _searchLoadingMore = false;

  int _searchTotalCount = 0;

  bool _searchHasMore = false;

  final TextEditingController _searchController = TextEditingController();

  final FocusNode _searchFocusNode = FocusNode();

  bool _isJumpedToMessage = false;

  ChatMessage? _jumpedToMessage;

  List<ChatMessage> _preservedSearchResults = [];

  String _preservedSearchQuery = '';

  String? _highlightedMessageId;

  Timer? _highlightTimer;

  bool _didInitialJump = false; // 保证「打开即定位」只触发一次

  final Map<String, GlobalKey> _messageKeys = {};

  ChatMessage? _pendingJumpTarget;

  bool _hasPendingReply = false;

  final ValueNotifier<bool> _showNewMessageBannerNotifier =
      ValueNotifier<bool>(false);

  int _lastMessageCount = 0;

  List<ChatMessage> _cachedMessages = [];

  ChatMessage? _replyToMessage;

  bool _pureAiPanelExpanded = false;

  VoidCallback? _onModeSettingsChanged;

  LocalStorageRepository? _modeSettingsStorage;


  Offset? _pureAiOrbOffset;

  final ValueNotifier<bool> _isAiTypingNotifier = ValueNotifier<bool>(false);

  Timer? _loadingFallbackTimer;


  // ─── 本地语音（AI 回复合成播放 + 录音转文字） ───
  final VoiceRecorderService _voiceRecorder = VoiceRecorderService();

  final VoicePlayerService _voicePlayer = VoicePlayerService();

  final LocalTtsService _localTts = createLocalTtsService();

  final LocalSttService _localStt = createLocalSttService();

  bool _isRecordingVoice = false;

  bool _isTranscribingVoice = false;

  String? _synthesizingMessageId; // 正在合成语音的消息 id

  bool _forceUseFallback = false;

  Timer? _usageReminderTimer;

  DateTime? _sessionStartTime;

  bool _isLoadingMore = false;

  int _lastStreamingScrollTime = 0;

  bool _hasMoreMessages = true;

  final ValueNotifier<bool> _canSendNotifier = ValueNotifier<bool>(false);

  bool _webSearchEnabled = false;


  /// 待发送附图：选图后先挂在输入区，可配文字再点发送
  final List<String> _pendingImagePaths = [];

}
