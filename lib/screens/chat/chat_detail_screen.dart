// 性能优化 -- 耗电与老手机兼容
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../blocs/chat/chat_bloc.dart';
import '../../models/chat_session.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../../models/chat_message.dart';
import '../../models/ai_character.dart';
import '../../models/intimacy_event.dart';
import '../../repositories/local_storage_repository.dart';
import '../../services/ai_service.dart';
import '../virtual_phone/virtual_phone_screen.dart';
import '../../models/virtual_phone/virtual_phone.dart';
import '../../services/virtual_phone_generator.dart';
import '../../utils/message_sanitizer.dart';
import '../../services/ai_status_service.dart';
import '../../services/heartbeat_service.dart';
import '../../services/builtin_sticker_service.dart';
import '../../services/sticker_pack_service.dart';
import '../../models/sticker_pack.dart';
import '../../widgets/red_packet_card.dart';
import '../../widgets/order_card.dart';
import '../../screens/shop/shop_screen.dart';
import '../../screens/shop/order_tracking_screen.dart';
import '../../models/shop_order.dart';
import '../../blocs/shop/shop_bloc.dart';

import '../../widgets/topic_suggestions.dart';
import '../../widgets/animated_list_item.dart';
import '../../widgets/typing_indicator.dart';
import '../../widgets/voice_message_bubble.dart';
import '../../widgets/mode_control_mini_panel.dart';
import '../../utils/ui_utils.dart';
import '../../utils/avatar_resolver.dart';
import '../../config/constants.dart';
import '../../config/business_rules.dart';
import '../../services/log_service.dart';
import '../../services/tts_service.dart';
import '../../services/voice_clone_service.dart';
import '../../services/audio_transcription_service.dart';
import '../../services/weather_service.dart';
import '../../services/emotion_engine.dart';
import '../../models/character_emotion.dart';
import 'package:record/record.dart';
import '../../screens/settings/log_viewer_screen.dart';
import 'chat_settings_screen.dart';
import 'voice_call_screen.dart';
import '../../services/scenario_service.dart';

class ChatDetailScreen extends StatefulWidget {
  final ChatSession session;
  final String? initialMessage; // 从塔罗牌等活动预填的消息

  const ChatDetailScreen(
      {super.key, required this.session, this.initialMessage});

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
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
  String? _displayName;
  ReplyMode? _replyMode;
  bool _enableProactiveMessage = true;
  List<String> _suggestedTopics = [];
  bool _showTopics = false;
  bool _isSearching = false;
  String _searchQuery = '';
  List<ChatMessage> _searchResults = [];
  bool _searchLoading = false;
  bool _searchLoadingMore = false;
  int _searchTotalCount = 0;
  static const int _searchPageSize = 30;
  bool _searchHasMore = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  bool _isJumpedToMessage = false;
  ChatMessage? _jumpedToMessage;
  List<ChatMessage> _preservedSearchResults = [];
  int _lastVoiceProcessedCount = 0;
  String _preservedSearchQuery = '';
  String? _highlightedMessageId;
  Timer? _highlightTimer;
  final Map<String, GlobalKey> _messageKeys = {};
  ChatMessage? _pendingJumpTarget;
  bool _hasPendingReply = false;
  final ValueNotifier<bool> _showNewMessageBannerNotifier =
      ValueNotifier<bool>(false);
  bool get _showNewMessageBanner => _showNewMessageBannerNotifier.value;
  int _lastMessageCount = 0;
  List<ChatMessage> _cachedMessages = [];
  ChatMessage? _replyToMessage;
  bool _pureAiPanelExpanded = false;
  final ValueNotifier<bool> _modePanelVisible = ValueNotifier<bool>(false);
  IconData? _weatherIcon;
  Offset? _pureAiOrbOffset;
  final ValueNotifier<bool> _isAiTypingNotifier = ValueNotifier<bool>(false);
  bool get _isAiTyping => _isAiTypingNotifier.value;
  Timer? _loadingFallbackTimer;
  bool _forceUseFallback = false;
  Timer? _usageReminderTimer;
  DateTime? _sessionStartTime;
  bool _isLoadingMore = false;
  int _lastStreamingScrollTime = 0;
  bool _hasMoreMessages = true;
  final ValueNotifier<bool> _canSendNotifier = ValueNotifier<bool>(false);
  bool get _canSend => _canSendNotifier.value;
  bool _webSearchEnabled = false;

  List<IntimacyEvent> _intimacyEvents = [];
  bool _isIntimacyExpanded = true;

  // ── 语音录制 ──
  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  bool _showVoiceInput = false; // 是否显示语音输入模式
  String? _recordPath;
  Timer? _recordTimer;
  int _recordSeconds = 0;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: !_isJumpedToMessage && !_isSearching,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          if (_isJumpedToMessage) {
            _returnToSearchResults();
          } else if (_isSearching) {
            setState(() {
              _isSearching = false;
              _searchQuery = '';
              _searchResults = [];
              _searchController.clear();
            });
          } else {
            Navigator.pop(context, _hasSettingsChanged);
          }
        }
      },
      child: BlocProvider.value(
        value: _chatBloc,
        child: Scaffold(
          backgroundColor: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF000000)
              : const Color(0xFFF5F5F5),
          appBar: _isSearching
              ? _buildSearchAppBar(colorScheme)
              : _isJumpedToMessage
                  ? _buildJumpedAppBar(colorScheme)
                  : _buildModernAppBar(colorScheme),
          body: _buildBody(colorScheme),
        ),
      ),
    );
  }

  // ─── 现代风格 AppBar ───
  PreferredSizeWidget _buildModernAppBar(ColorScheme colorScheme) {
    final brightness = Theme.of(context).brightness;
    final isDark = brightness == Brightness.dark;
    final currentAvatar =
        _currentSession?.aiCharacterAvatar ?? widget.session.aiCharacterAvatar;
    final currentName = _displayName ??
        _currentSession?.aiCharacterName ??
        widget.session.aiCharacterName;
    final isOnline =
        AIStatusService.isOnlineFromSession(_currentSession ?? widget.session);

    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      leading: IconButton(
        icon: Icon(
          Icons.arrow_back_ios_new_rounded,
          color: isDark ? Colors.white : Colors.black,
          size: 20,
        ),
        onPressed: () => Navigator.pop(context, _hasSettingsChanged),
      ),
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // AI 头像（圆形）+ 在线绿点
          SizedBox(
            width: 36,
            height: 36,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: ClipOval(
                    child: _buildAppBarAvatar(currentAvatar, isDark),
                  ),
                ),
                if (isOnline)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: const Color(0xFF4CAF50),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isDark ? Colors.black : Colors.white,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    currentName,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'AI',
                    style: TextStyle(
                      fontSize: 10,
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      centerTitle: true,
      actions: [
        IconButton(
          tooltip: '设置场景',
          icon: Icon(
            Icons.landscape_rounded,
            color: isDark ? Colors.white : Colors.black,
            size: 22,
          ),
          onPressed: () => _showScenarioSheet(context),
        ),
        IconButton(
          tooltip: 'TA 的手机',
          icon: Icon(
            Icons.smartphone_rounded,
            color: isDark ? Colors.white : Colors.black,
            size: 22,
          ),
          onPressed: () => _openVirtualPhone(context),
        ),
        IconButton(
          icon: Icon(
            Icons.more_horiz_rounded,
            color: isDark ? Colors.white : Colors.black,
            size: 24,
          ),
          onPressed: () => _openChatSettings(context),
        ),
      ],
    );
  }

  /// 场景设置底部弹窗
  Future<void> _showScenarioSheet(BuildContext context) async {
    final storage = RepositoryProvider.of<LocalStorageRepository>(context);
    final prefs = storage.sharedPreferences;
    if (prefs == null) return;

    final user = await storage.getCurrentUser();
    final userId = user?.id ?? 'default';
    final characterId = widget.session.aiCharacterId;
    final svc = ScenarioService(prefs);
    final current = svc.getScenario(characterId, userId);

    if (!context.mounted) return;

    final whereCtrl =
        TextEditingController(text: current?.where ?? '');
    final doingCtrl =
        TextEditingController(text: current?.doing ?? '');
    final moodCtrl =
        TextEditingController(text: current?.mood ?? '');
    final extraCtrl =
        TextEditingController(text: current?.extra ?? '');
    bool withUser = current?.withUser ?? false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final pad = MediaQuery.of(ctx).viewInsets.bottom;
            return Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + pad),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.landscape_rounded, size: 20),
                      const SizedBox(width: 8),
                      const Text('当前场景',
                          style: TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w600)),
                      const Spacer(),
                      if (current != null)
                        TextButton(
                          onPressed: () async {
                            await svc.clearScenario(characterId, userId);
                            if (ctx.mounted) Navigator.pop(ctx);
                          },
                          child: const Text('清除',
                              style: TextStyle(color: Colors.red)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '让 AI 知道你们现在所处的背景，对话会更有沉浸感',
                    style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(ctx)
                            .colorScheme
                            .onSurface
                            .withAlpha(153)),
                  ),
                  const SizedBox(height: 16),
                  _scenarioField(ctx, whereCtrl, '在哪', '例：星巴克、家里的卧室、雨天的路上'),
                  const SizedBox(height: 10),
                  _scenarioField(ctx, doingCtrl, '在做什么', '例：等朋友、刚下班、躺着刷手机'),
                  const SizedBox(height: 10),
                  _scenarioField(ctx, moodCtrl, '氛围 / 心境', '例：慵懒的午后、有点烦躁'),
                  const SizedBox(height: 10),
                  _scenarioField(ctx, extraCtrl, '补充（选填）', '例：今天下雨、刚发完一条朋友圈'),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Checkbox(
                        value: withUser,
                        onChanged: (v) =>
                            setSheetState(() => withUser = v ?? false),
                      ),
                      const Text('对方也在同一场景（你们在一起）'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // 快选预设
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: _scenarioPresets.map((p) {
                      return ActionChip(
                        label: Text(p['label']!,
                            style: const TextStyle(fontSize: 12)),
                        onPressed: () {
                          whereCtrl.text = p['where'] ?? '';
                          doingCtrl.text = p['doing'] ?? '';
                          moodCtrl.text = p['mood'] ?? '';
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        final newCtx = ScenarioContext(
                          where: whereCtrl.text.trim().isEmpty
                              ? null
                              : whereCtrl.text.trim(),
                          doing: doingCtrl.text.trim().isEmpty
                              ? null
                              : doingCtrl.text.trim(),
                          mood: moodCtrl.text.trim().isEmpty
                              ? null
                              : moodCtrl.text.trim(),
                          withUser: withUser,
                          extra: extraCtrl.text.trim().isEmpty
                              ? null
                              : extraCtrl.text.trim(),
                          isManual: true,
                          setAt: DateTime.now(),
                        );
                        if (newCtx.isEmpty) {
                          await svc.clearScenario(characterId, userId);
                        } else {
                          await svc.setScenario(characterId, userId, newCtx);
                        }
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                      child: const Text('保存场景'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _scenarioField(BuildContext ctx, TextEditingController ctrl,
      String label, String hint) {
    return TextField(
      controller: ctrl,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle:
            TextStyle(fontSize: 12, color: Theme.of(ctx).hintColor),
        border: const OutlineInputBorder(),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        isDense: true,
      ),
    );
  }

  static const List<Map<String, String>> _scenarioPresets = [
    {'label': '☕ 咖啡厅', 'where': '咖啡厅', 'doing': '喝咖啡', 'mood': '惬意'},
    {'label': '🏠 在家', 'where': '家里', 'doing': '躺着休息', 'mood': '慵懒'},
    {'label': '🌙 深夜', 'where': '卧室', 'doing': '睡前聊天', 'mood': '有点困但不想睡'},
    {
      'label': '🌧 雨天',
      'where': '窗边',
      'doing': '看雨发呆',
      'mood': '有些伤感'
    },
    {'label': '🚶 散步', 'where': '公园', 'doing': '散步', 'mood': '放松'},
    {
      'label': '📚 自习',
      'where': '图书馆',
      'doing': '看书/学习',
      'mood': '专注但有点无聊'
    },
  ];

  Future<void> _openVirtualPhone(BuildContext context) async {
    final storage = RepositoryProvider.of<LocalStorageRepository>(context);
    final character =
        await storage.getAICharacter(widget.session.aiCharacterId);
    if (!context.mounted) return;
    if (character == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('找不到该角色的资料')),
      );
      return;
    }
    Navigator.of(context).push(VirtualPhoneScreen.route(context, character));
  }

  Widget _buildAppBarAvatar(String? avatarUrl, bool isDark) {
    Widget fallback() => Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
          ),
          child: Icon(
            Icons.smart_toy_rounded,
            size: 20,
            color: isDark ? Colors.white70 : Colors.grey.shade600,
          ),
        );

    final image = AvatarResolver.imageWidget(
      avatarUrl,
      width: 36,
      height: 36,
      onError: fallback,
    );
    if (image != null) return image;
    return fallback();
  }

  void _showPersonaEvolutionNotice(ChatPersonaEvolved state) {
    final isQualitative = state.mode == 'qualitative';
    final title = isQualitative ? '人格发生了质变' : '角色发生了成长';
    final iconData = isQualitative ? Icons.psychology : Icons.spa;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(iconData, size: 16),
                const SizedBox(width: 4),
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 4),
            Text(state.summary),
          ],
        ),
        action: SnackBarAction(
          label: '查看',
          onPressed: () => _openChatSettings(context),
        ),
      ),
    );
  }

  Widget _buildChatTitle(ColorScheme colorScheme) {
    return BlocConsumer<ChatBloc, ChatState>(
      bloc: _chatBloc,
      listenWhen: (previous, current) =>
          current is ChatIntimacyChanged ||
          current is ChatEmotionChanged ||
          current is ChatBlockedByAI ||
          current is ChatUnblockedByAI ||
          current is ChatAIObserving,
      listener: (context, state) {
        if (state is ChatBlockedByAI && state.chatId == widget.session.id) {
          setState(() => _isBlockedByAI = true);
        }
        if (state is ChatUnblockedByAI && state.chatId == widget.session.id) {
          setState(() => _isBlockedByAI = false);
        }
        if (state is ChatAIObserving && state.chatId == widget.session.id) {
          // setState 已移除，ChatAIObserving 由 BlocConsumer.buildWhen 处理重建
        }
      },
      builder: (context, state) {
        String? moodText;
        Color moodColor = colorScheme.onSurface.withOpacity(0.4);

        if (state is ChatAITyping && !_isBlockedByAI) {
          moodText = '正在输入中...';
          moodColor = colorScheme.primary;
        } else if (state is ChatAIObserving) {
          moodText = state.statusText;
          if (state.pendingCount > 0) {
            moodText += ' · 已读${state.pendingCount}条';
          }
          if (state.emotionEmoji == '生气' || state.emotionEmoji == '愤怒') {
            moodColor = Colors.red.shade400;
          } else if (state.emotionEmoji == '难过' || state.emotionEmoji == '伤心') {
            moodColor = Colors.blueGrey.shade400;
          } else if (state.emotionEmoji == '焦虑' || state.emotionEmoji == '紧张') {
            moodColor = Colors.amber.shade600;
          } else {
            moodColor = Colors.orange.shade400;
          }
        } else if (_isBlockedByAI) {
          moodText = '已拉黑你';
          moodColor = Colors.red.shade300;
        }

        if (moodText == null) return const SizedBox.shrink();

        return AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 300),
          style: TextStyle(fontSize: 12, color: moodColor),
          child: Text(moodText, overflow: TextOverflow.ellipsis),
        );
      },
    );
  }

  Widget _buildRelationshipHeader(ColorScheme colorScheme, bool isDark) {
    if (_isSearching || _isJumpedToMessage) return const SizedBox.shrink();

    final session = _currentSession ?? widget.session;
    final level = session.intimacyLevel.clamp(0, 999999);
    final progress = (level % 100) / 100.0;
    final todayGain = _intimacyEvents.fold<int>(
      0,
      (sum, event) => _isToday(event.createdAt) ? sum + event.delta : sum,
    );
    final lastEvent = _intimacyEvents.isNotEmpty ? _intimacyEvents.first : null;
    final subtitle = lastEvent == null
        ? '开始聊天提升默契吧'
        : '${_eventSourceLabel(lastEvent.source)} ${lastEvent.delta >= 0 ? '+' : ''}${lastEvent.delta}';

    return GestureDetector(
      onTap: () => setState(() => _isIntimacyExpanded = !_isIntimacyExpanded),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        padding: EdgeInsets.symmetric(
          horizontal: 14,
          vertical: _isIntimacyExpanded ? 10 : 6,
        ),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withOpacity(0.06)
              : Colors.white.withOpacity(0.86),
          borderRadius: BorderRadius.circular(_isIntimacyExpanded ? 18 : 24),
          border: Border.all(
            color: colorScheme.primary.withOpacity(isDark ? 0.22 : 0.14),
          ),
        ),
        child: _isIntimacyExpanded
            ? _buildIntimacyExpanded(
                colorScheme, level, progress, subtitle, todayGain)
            : _buildIntimacyCollapsed(colorScheme, level),
      ),
    );
  }

  /// 展开状态：完整亲密度信息
  Widget _buildIntimacyExpanded(
    ColorScheme colorScheme,
    int level,
    double progress,
    String subtitle,
    int todayGain,
  ) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: colorScheme.primary.withOpacity(0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.favorite_rounded,
            color: colorScheme.primary,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _relationshipLabel(level),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '亲密度 $level',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 4,
                  backgroundColor: colorScheme.primary.withOpacity(0.10),
                  valueColor:
                      AlwaysStoppedAnimation<Color>(colorScheme.primary),
                ),
              ),
              const SizedBox(height: 5),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (todayGain != 0)
                    Text(
                      '今日 ${todayGain > 0 ? '+' : ''}$todayGain',
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 4),
        Icon(
          Icons.keyboard_arrow_up_rounded,
          size: 18,
          color: colorScheme.onSurfaceVariant.withOpacity(0.5),
        ),
      ],
    );
  }

  /// 折叠状态：单行紧凑显示
  Widget _buildIntimacyCollapsed(ColorScheme colorScheme, int level) {
    return Row(
      children: [
        Icon(
          Icons.favorite_rounded,
          color: colorScheme.primary,
          size: 16,
        ),
        const SizedBox(width: 8),
        Text(
          '${_relationshipLabel(level)} · 亲密度 $level',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface.withOpacity(0.7),
          ),
        ),
        const Spacer(),
        Icon(
          Icons.keyboard_arrow_down_rounded,
          size: 18,
          color: colorScheme.onSurfaceVariant.withOpacity(0.5),
        ),
      ],
    );
  }

  bool _isToday(DateTime value) {
    final now = DateTime.now();
    return value.year == now.year &&
        value.month == now.month &&
        value.day == now.day;
  }

  String _relationshipLabel(int level) {
    if (level >= 500) return '灵魂伴侣';
    if (level >= 300) return '亲密无间';
    if (level >= 180) return '彼此信任';
    if (level >= 80) return '逐渐熟悉';
    if (level >= 20) return '初有默契';
    return '刚刚认识';
  }

  String _eventSourceLabel(String source) {
    switch (source) {
      case 'image':
        return '图片互动';
      case 'voice':
        return '语音互动';
      case 'message':
        return '消息互动';
      default:
        return '最近互动';
    }
  }

  Widget _buildBody(ColorScheme colorScheme) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final content = Column(
      children: [
        _buildRelationshipHeader(colorScheme, isDark),
        Expanded(
          child: Stack(
            children: [
              BlocConsumer<ChatBloc, ChatState>(
                bloc: _chatBloc,
                buildWhen: (previous, current) {
                  // 仅当消息真正变化时才重建列表，避免每轮状态跳跃都触发全量刷新
                  if (current is ChatAIStreaming) return true;
                  if (current is ChatTransferStatusUpdated) return true;
                  if (current is ChatMessagesLoaded &&
                      previous is ChatMessagesLoaded) {
                    // P3: 消息数量或内容变化均需重建（支持编辑/删除后的 UI 刷新）
                    if (current.messages.length != previous.messages.length)
                      return true;
                    for (var i = 0; i < current.messages.length; i++) {
                      if (i >= previous.messages.length) return true;
                      if (current.messages[i].content !=
                              previous.messages[i].content ||
                          current.messages[i].isBookmark !=
                              previous.messages[i].isBookmark) {
                        return true;
                      }
                    }
                    return false;
                  }
                  return previous.runtimeType != current.runtimeType;
                },
                listenWhen: (previous, current) =>
                    previous?.runtimeType != current.runtimeType ||
                    current is ChatAITyping ||
                    current is ChatError ||
                    current is ChatAIObserving ||
                    (current is ChatMessagesLoaded &&
                        previous is ChatMessagesLoaded &&
                        current.messages.length != previous.messages.length),
                listener: (context, state) {
                  LogService.instance.d('UI', 'Listener: ${state.runtimeType}',
                      chatId: widget.session.id);
                  if (state is ChatError) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(state.message),
                        duration: const Duration(seconds: 3),
                      ),
                    );
                  }
                  if (state is ChatAITyping) {
                    if (!_isBlockedByAI) {
                      _isAiTypingNotifier.value = true;
                    }
                  }
                  if (state is ChatAIStreaming) {
                    if (!_isBlockedByAI) {
                      _isAiTypingNotifier.value = true;
                    }
                    // 流式滚动节流：每 400ms 最多滚一次，避免每 chunk 跳跃
                    final now = DateTime.now().millisecondsSinceEpoch;
                    if (now - _lastStreamingScrollTime > 400) {
                      _lastStreamingScrollTime = now;
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) _scrollToBottom(force: false);
                      });
                    }
                  }
                  if (state is ChatMessagesLoaded || state is ChatError) {
                    if (_isAiTypingNotifier.value)
                      _isAiTypingNotifier.value = false;
                  }
                  if (state is ChatAIObserving) {
                    if (_isAiTypingNotifier.value)
                      _isAiTypingNotifier.value = false;
                  }
                  if (state is ChatPersonaEvolved &&
                      state.chatId == widget.session.id) {
                    _showPersonaEvolutionNotice(state);
                  }
                  if (state is ChatIntimacyChanged &&
                      state.chatId == widget.session.id) {
                    setState(() {
                      _currentSession = (_currentSession ?? widget.session)
                          .copyWith(intimacyLevel: state.newLevel);
                    });
                    _loadIntimacyEvents();
                  }
                  if (state is ChatMessagesLoaded) {
                    _hasMoreMessages = state.hasMore;
                    if (_isLoadingMore) {
                      _isLoadingMore = false;
                    } else {
                      _reloadSessionStatus();
                    }
                    final pendingTarget = _pendingJumpTarget;
                    if (pendingTarget != null) {
                      final targetLoaded =
                          state.messages.any((m) => m.id == pendingTarget.id);
                      if (targetLoaded) {
                        _pendingJumpTarget = null;
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) _scrollToTargetMessage(pendingTarget);
                        });
                      } else if (!state.hasMore) {
                        _pendingJumpTarget = null;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('没有找到目标消息位置'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                    }
                  }
                  // 强制刷新UI（已由 BlocConsumer.buildWhen 控制重建时机）
                  if ((state is ChatMessagesLoaded ||
                          state is ChatTransferStatusUpdated) &&
                      mounted) {
                    final wasLoadingMore = _isLoadingMore;
                    if (!wasLoadingMore) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted && !_isJumpedToMessage) {
                          _scrollToBottom(force: false);
                        }
                      });
                    }
                  }
                  if (state is ChatMessagesLoaded &&
                      _cachedMessages.isNotEmpty &&
                      state.messages.length > _cachedMessages.length &&
                      _lastMessageCount > 0 &&
                      _userScrolledUp &&
                      mounted) {
                    _showNewMessageBannerNotifier.value = true;
                  }
                },
                builder: (context, state) {
                  debugPrint(
                      '[SYNC] BlocBuilder rebuild: type=${state.runtimeType}, msgCount=${state is ChatMessagesLoaded ? state.messages.length : (state is ChatTransferStatusUpdated ? state.messages.length : (state is ChatAITyping ? state.messages.length : (state is ChatAIObserving ? state.messages.length : 0)))}');
                  // 统一更新缓存：任何含消息列表的状态都同步到 _cachedMessages
                  if (state is ChatMessagesLoaded) {
                    _cachedMessages = state.messages;
                    _lastMessageCount = state.messages.length;
                    _cancelLoadingFallbackTimer();

                    // 检测新 AI 消息并自动生成语音
                    final aiMessages = state.messages
                        .where((m) => m.isFromAI && m.type == MessageType.text)
                        .toList();
                    if (aiMessages.isNotEmpty &&
                        state.messages.length > _lastVoiceProcessedCount) {
                      final latestAI = aiMessages.last;
                      _lastVoiceProcessedCount = state.messages.length;
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) _generateVoiceForAIMessage(latestAI);
                      });
                    }
                  } else if (state is ChatTransferStatusUpdated) {
                    _cachedMessages = state.messages;
                    _lastMessageCount = state.messages.length;
                  } else if (state is ChatAITyping &&
                      state.messages.isNotEmpty) {
                    _cachedMessages = state.messages;
                  } else if (state is ChatAIObserving &&
                      state.messages.isNotEmpty) {
                    _cachedMessages = state.messages;
                  }

                  // 搜索模式
                  if (_isSearching && _searchQuery.isNotEmpty) {
                    return _buildSearchResults(context);
                  }

                  // 优先级：消息加载完成 - 直接使用 state 中的完整消息列表
                  if (state is ChatMessagesLoaded) {
                    if (state.messages.isEmpty) return _buildEmptyChat(context);
                    _logTransferStatus(state.messages, 'ChatMessagesLoaded');
                    return _buildMessageList(context, state.messages,
                        showTyping: false);
                  }

                  // 优先级：转账状态局部更新 - 同样有完整消息列表
                  if (state is ChatTransferStatusUpdated) {
                    if (state.messages.isEmpty) return _buildEmptyChat(context);
                    _logTransferStatus(
                        state.messages, 'ChatTransferStatusUpdated');
                    return _buildMessageList(context, state.messages,
                        showTyping: false);
                  }

                  // 优先级：AI正在输入 - 显示已有消息 + 输入指示器
                  if (state is ChatAITyping) {
                    if (state.messages.isNotEmpty) {
                      return _buildMessageList(context, state.messages,
                          showTyping: true);
                    }
                    if (_cachedMessages.isNotEmpty) {
                      return _buildMessageList(context, _cachedMessages,
                          showTyping: true);
                    }
                  }

                  // 优先级：AI流式输出 - 显示已有消息 + 流式气泡
                  if (state is ChatAIStreaming) {
                    final baseMessages = state.messages.isNotEmpty
                        ? state.messages
                        : _cachedMessages;
                    return _buildMessageListWithStreaming(context, baseMessages,
                        state.streamingText, state.characterName,
                        reasoning: state.reasoning);
                  }

                  if (state is ChatAIObserving) {
                    if (state.messages.isNotEmpty) {
                      return _buildMessageList(context, state.messages,
                          showTyping: false);
                    }
                    if (_cachedMessages.isNotEmpty) {
                      return _buildMessageList(context, _cachedMessages,
                          showTyping: false);
                    }
                  }

                  // 优先级：错误状态回退
                  if (state is ChatError) {
                    if (_cachedMessages.isNotEmpty) {
                      return _buildMessageList(context, _cachedMessages,
                          showTyping: false);
                    }
                    return _buildMessageListFromStorage(context);
                  }

                  // 优先级：备用方案（超时后显示已有缓存或从数据库直读）
                  if (_forceUseFallback) {
                    if (_cachedMessages.isNotEmpty) {
                      return _buildMessageList(context, _cachedMessages,
                          showTyping: false);
                    }
                    return _buildMessageListFromStorage(context);
                  }

                  // 优先级：初始化加载中
                  return _buildMessageListFromStorage(context);
                },
              ),
              ValueListenableBuilder<bool>(
                valueListenable: _showNewMessageBannerNotifier,
                builder: (context, showBanner, _) {
                  if (!showBanner) return const SizedBox.shrink();
                  return Positioned(
                    top: 8,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: GestureDetector(
                        onTap: () => _scrollToBottom(force: true),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Text(
                            '新的消息',
                            style: TextStyle(
                              color: colorScheme.onPrimaryContainer,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              ModeControlMiniPanel(visible: _modePanelVisible),
            ],
          ),
        ),
        _buildInputArea(context),
      ],
    );

    if (_currentSession?.backgroundImage != null &&
        _currentSession!.backgroundImage!.isNotEmpty) {
      return Stack(
        children: [
          Positioned.fill(
            child: _buildBackgroundImage(colorScheme),
          ),
          content,
        ],
      );
    }
    return content;
  }

  Widget _buildPureAiModeSidebar(ColorScheme colorScheme) {
    const orbSize = 64.0;
    const panelWidth = 214.0;
    const panelHeight = 116.0;
    const margin = 8.0;
    final storage = RepositoryProvider.of<LocalStorageRepository>(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark
        ? const Color(0xFF1F1F1F).withOpacity(0.94)
        : colorScheme.surface.withOpacity(0.96);
    final borderColor = colorScheme.outlineVariant.withOpacity(0.7);

    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final widgetWidth = _pureAiPanelExpanded ? panelWidth : orbSize;
          final widgetHeight = _pureAiPanelExpanded ? panelHeight : orbSize;
          final fallbackOffset = Offset(
            constraints.maxWidth - orbSize - 14,
            constraints.maxHeight - orbSize - 24,
          );
          final rawOffset = _pureAiOrbOffset ?? fallbackOffset;
          final maxLeft = constraints.maxWidth - widgetWidth - margin;
          final maxTop = constraints.maxHeight - widgetHeight - margin;
          final left = rawOffset.dx.clamp(
            margin,
            maxLeft < margin ? margin : maxLeft,
          );
          final top = rawOffset.dy.clamp(
            margin,
            maxTop < margin ? margin : maxTop,
          );

          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: left.toDouble(),
                top: top.toDouble(),
                width: widgetWidth,
                height: widgetHeight,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onPanUpdate: (details) {
                    final current = _pureAiOrbOffset ?? fallbackOffset;
                    setState(() {
                      _pureAiOrbOffset = Offset(
                        current.dx + details.delta.dx,
                        current.dy + details.delta.dy,
                      );
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    decoration: BoxDecoration(
                      color: surfaceColor,
                      borderRadius: BorderRadius.circular(
                        _pureAiPanelExpanded ? 14 : orbSize / 2,
                      ),
                      border: Border.all(color: borderColor, width: 0.5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(isDark ? 0.28 : 0.12),
                          blurRadius: _pureAiPanelExpanded ? 18 : 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: _pureAiPanelExpanded
                        ? ValueListenableBuilder<bool>(
                            valueListenable: storage.pureAiModeNotifier,
                            builder: (context, enabled, _) {
                              return Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(12, 10, 12, 10),
                                child: Row(
                                  children: [
                                    InkWell(
                                      borderRadius: BorderRadius.circular(20),
                                      onTap: () => setState(
                                          () => _pureAiPanelExpanded = false),
                                      child: SizedBox(
                                        width: 40,
                                        height: 40,
                                        child: Center(
                                          child: Text(
                                            'AI',
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w700,
                                              color: colorScheme.primary,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '纯AI视角模式',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: colorScheme.onSurface,
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            enabled ? '已开启' : '已关闭',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: colorScheme.onSurface
                                                  .withOpacity(0.55),
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Switch(
                                            value: enabled,
                                            onChanged: (value) =>
                                                storage.setPureAiMode(value),
                                            activeColor: colorScheme.primary,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          )
                        : InkWell(
                            borderRadius: BorderRadius.circular(orbSize / 2),
                            onTap: () =>
                                setState(() => _pureAiPanelExpanded = true),
                            child: Center(
                              child: Text(
                                'AI',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: colorScheme.primary,
                                ),
                              ),
                            ),
                          ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBackgroundImage(ColorScheme colorScheme) {
    final bgImage = _currentSession!.backgroundImage!;

    if (bgImage.startsWith('/')) {
      final file = File(bgImage);
      if (!file.existsSync()) {
        return Container(color: colorScheme.surface);
      }
    }

    final imageProvider = bgImage.startsWith('/')
        ? FileImage(File(bgImage)) as ImageProvider
        : NetworkImage(bgImage);

    return Container(
      decoration: BoxDecoration(
        image: DecorationImage(
          image: imageProvider,
          fit: BoxFit.cover,
          onError: (exception, stackTrace) {},
        ),
        color: colorScheme.surface,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    const MethodChannel('com.solace.solace/volume_key')
        .setMethodCallHandler((call) async {
      if (call.method == 'volume_up')
        _modePanelVisible.value = true;
      else if (call.method == 'volume_down') _modePanelVisible.value = false;
    });
    _isBlockedByAI =
        widget.session.isBlocked && widget.session.blockedBy == BlockedBy.ai;
    _isBlockedByUser =
        widget.session.isBlocked && widget.session.blockedBy == BlockedBy.user;
    _chatBloc = ChatBloc(
      RepositoryProvider.of<LocalStorageRepository>(context),
      AIService(RepositoryProvider.of<LocalStorageRepository>(context)),
    );
    _scrollController.addListener(_onScroll);
    _messageFocusNode.addListener(() {
      if (mounted)
        setState(() => _showTopics = _messageController.text.isEmpty);
    });
    _initialize();
    BuiltinStickerService.loadDefaultPack();
    _startUsageReminderTimer();
  }

  void _startUsageReminderTimer() {
    _sessionStartTime = DateTime.now();
    _usageReminderTimer?.cancel();
    _usageReminderTimer = Timer.periodic(const Duration(minutes: 10), (timer) {
      if (!mounted || _sessionStartTime == null) return;
      final elapsed = DateTime.now().difference(_sessionStartTime!);
      if (elapsed.inMinutes >= 120) {
        _showUsageReminder();
      }
    });
  }

  void _showUsageReminder() {
    if (!mounted) return;
    final colorScheme = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.timer_outlined, color: colorScheme.primary),
            const SizedBox(width: 8),
            const Text('使用时长提醒'),
          ],
        ),
        content: const Text(
          '你已经连续使用 Solace 超过 2 小时了。\n\n'
          'AI 陪伴虽然有趣，但也别忘了：\n'
          '• 起身活动一下，保护眼睛和颈椎\n'
          '• 与现实中的朋友、家人聊聊天\n'
          '• 你正在与 AI 互动，不是真实的人\n\n'
          '适度使用，健康生活',
          style: TextStyle(fontSize: 14, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('我知道了'),
          ),
        ],
      ),
    );
    _sessionStartTime = DateTime.now();
  }

  Future<void> _initialize() async {
    try {
      await _loadSessionFromDatabase();
      await _loadIntimacyEvents();
      _loadWeather();
    } catch (e) {
      debugPrint('初始化失败: $e');
    }
    if (mounted) {
      _resetSilenceTimer();
      _checkPendingReply();
      _chatBloc.add(ChatLoadMessages(widget.session.id));
      _startLoadingFallbackTimer();

      // 后台预生成常用回复音频（不阻塞 UI）
      _pregenerateVoiceReplies();

      // 后台静默预生成该角色的虚拟手机内容（仅未生成过时，省 token）
      _pregenerateVirtualPhone();

      // 从塔罗牌等活动预填消息，自动发送
      if (widget.initialMessage != null && widget.initialMessage!.isNotEmpty) {
        Future.delayed(const Duration(milliseconds: 800), () {
          if (mounted) {
            _messageController.text = widget.initialMessage!;
            _sendMessage();
          }
        });
      }
    }
  }

  /// 后台静默预生成该角色的虚拟手机内容。
  ///
  /// 只在「从未生成过 / 上次失败」时才跑一次 LLM，成功后永久缓存，
  /// 之后点手机图标进去只读缓存、不再花 token。用户仍可手动刷新重生成。
  void _pregenerateVirtualPhone() {
    Future.microtask(() async {
      try {
        final storage = RepositoryProvider.of<LocalStorageRepository>(context);
        final characterId = widget.session.aiCharacterId;

        var phone = await storage.getVirtualPhoneByCharacter(characterId);
        // 正在生成中（其它入口触发）跳过
        if (phone != null && phone.status == 'generating') return;

        final character = await storage.getAICharacter(characterId);
        if (character == null) return;
        final user = await storage.getCurrentUser();
        final generator = VirtualPhoneGenerator(
          aiService: AIService(storage),
          storage: storage,
        );

        // 已就绪：不重建，改为「生活推进」——像真人一样，手机内容跟着最近发生的事缓慢生长。
        // 仅当自上次更新以来又聊了足够多、且过了冷却期，才后台静默追加少量新内容。
        if (phone != null && phone.isReady) {
          const advanceMsgThreshold = 20; // 新增可见消息阈值
          const advanceCooldown = Duration(hours: 6); // 冷却，避免频繁增量
          final nowMsgCount =
              await storage.countVisibleChatMessages(characterId, user?.id ?? '');
          final delta = nowMsgCount - phone.lastAdvanceMsgCount;
          final cooledDown = phone.lastAdvanceAt == null ||
              DateTime.now().difference(phone.lastAdvanceAt!) >= advanceCooldown;
          if (delta >= advanceMsgThreshold && cooledDown) {
            await generator.advanceLife(
              phone: phone,
              character: character,
              userNickname: user?.nickname ?? '',
              userId: user?.id ?? '',
            );
            debugPrint(
                'VirtualPhone: 后台生活推进完成 -> ${character.name} (Δmsg=$delta)');
          }
          return;
        }

        // 从未生成/上次失败：首次全量建档
        phone ??= VirtualPhone(
          id: const Uuid().v4(),
          characterId: characterId,
          ownerName: character.name,
          createdAt: DateTime.now(),
        );
        await storage.saveVirtualPhone(phone);
        await generator.generateAll(
          phone: phone,
          character: character,
          userNickname: user?.nickname ?? '',
          userId: user?.id ?? '',
        );
        debugPrint('VirtualPhone: 后台预生成完成 -> ${character.name}');
      } catch (e) {
        debugPrint('VirtualPhone 后台预生成失败: $e');
      }
    });
  }

  /// 后台预生成角色常用回复的 TTS 音频（已禁用，避免阻塞 TTS 队列）
  void _pregenerateVoiceReplies() {
    // 跳过预生成：会占用 TTS 队列导致语音通话/回复延迟
    return;
    Future.microtask(() async {
      try {
        final storage = RepositoryProvider.of<LocalStorageRepository>(context);
        final character =
            await storage.getAICharacter(widget.session.aiCharacterId);
        if (character == null) return;
        if (!(character.interactionConfig?.voiceReplyEnabled ?? false)) return;

        final voiceClone = VoiceCloneService();
        if (!voiceClone.hasVoice(character.id)) return;

        debugPrint('VoicePregen: 开始预生成常用回复...');
        await voiceClone.pregenerateCommonReplies(character.id);
        debugPrint('VoicePregen: 预生成完成');
      } catch (e) {
        debugPrint('VoicePregen: 预生成失败 $e');
      }
    });
  }

  void _startLoadingFallbackTimer() {
    _loadingFallbackTimer?.cancel();
    _loadingFallbackTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _forceUseFallback = true);
      }
    });
  }

  void _cancelLoadingFallbackTimer() {
    _loadingFallbackTimer?.cancel();
    _loadingFallbackTimer = null;
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final currentScroll = _scrollController.position.pixels;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final threshold = 100.0;

    final isNearBottom = currentScroll < threshold;

    if (isNearBottom != _isNearBottom) {
      _isNearBottom = isNearBottom;
      if (isNearBottom) {
        _userScrolledUp = false;
        if (_isJumpedToMessage && mounted) {
          setState(() {
            _isJumpedToMessage = false;
            _jumpedToMessage = null;
          });
        }
        if (_showNewMessageBanner && mounted)
          _showNewMessageBannerNotifier.value = false;
      }
    }

    if (!isNearBottom && !_userScrolledUp) {
      _userScrolledUp = true;
    }

    if (_userScrolledUp && _hasPendingReply) {
      _triggerPendingReply();
    }

    if (_hasMoreMessages &&
        !_isLoadingMore &&
        (maxScroll - currentScroll) < 200) {
      _loadMoreMessages();
    }
  }

  void _loadMoreMessages() {
    if (_isLoadingMore || !_hasMoreMessages) return;
    _isLoadingMore = true;
    _chatBloc.add(ChatLoadMoreMessages(widget.session.id));
  }

  void _reloadSessionStatus() async {
    try {
      final storage = RepositoryProvider.of<LocalStorageRepository>(context);
      final updatedSession = await storage.getChatSession(widget.session.id);
      if (updatedSession != null && mounted) {
        setState(() {
          _currentSession = updatedSession;
        });
      }
      await _loadIntimacyEvents();
    } catch (_) {}
  }

  Future<void> _loadIntimacyEvents() async {
    try {
      final storage = RepositoryProvider.of<LocalStorageRepository>(context);
      final events =
          await storage.getIntimacyEvents(widget.session.id, limit: 20);
      if (!mounted) return;
      setState(() => _intimacyEvents = events);
    } catch (e) {
      debugPrint('loadIntimacyEvents failed: $e');
    }
  }

  Future<void> _loadWeather() async {
    try {
      final storage = RepositoryProvider.of<LocalStorageRepository>(context);
      final emotionEngine = EmotionEngine(storage);
      final weatherService = WeatherService(storage, emotionEngine);
      final weather = await weatherService.getCurrentWeather();
      if (!mounted) return;
      setState(() {
        _weatherIcon = _weatherTypeToIcon(weather.type);
      });
    } catch (_) {}
  }

  IconData _weatherTypeToIcon(WeatherType type) {
    switch (type) {
      case WeatherType.sunny:
        return Icons.wb_sunny;
      case WeatherType.cloudy:
        return Icons.cloud;
      case WeatherType.rainy:
        return Icons.water_drop;
      case WeatherType.snowy:
        return Icons.ac_unit;
      case WeatherType.windy:
        return Icons.air;
      case WeatherType.foggy:
        return Icons.foggy;
      case WeatherType.stormy:
        return Icons.thunderstorm;
      case WeatherType.unknown:
        return Icons.help_outline;
    }
  }

  Future<void> _loadSessionFromDatabase() async {
    final storage = RepositoryProvider.of<LocalStorageRepository>(context);
    var updatedSession = await storage.getChatSession(widget.session.id);

    if (updatedSession != null && mounted) {
      // 检查背景图片是否有效
      if (updatedSession.backgroundImage != null &&
          updatedSession.backgroundImage!.isNotEmpty &&
          updatedSession.backgroundImage!.startsWith('/')) {
        final file = File(updatedSession.backgroundImage!);
        if (!file.existsSync()) {
          updatedSession = updatedSession.copyWith(backgroundImage: null);
          await storage.saveChatSession(updatedSession);
        }
      }

      setState(() {
        _currentSession = updatedSession;
      });
    }
    final character =
        await storage.getAICharacter(widget.session.aiCharacterId);
    if (character != null && mounted) {
      _aiPersonality = character.personality;
      _displayName = character.userAlias ?? character.name;
      _replyMode = character.interactionConfig?.replyMode;
      _enableProactiveMessage =
          character.interactionConfig?.enableMomentInteraction ?? true;
    }
  }

  @override
  void dispose() {
    _silenceTimer?.cancel();
    _cancelLoadingFallbackTimer();
    _usageReminderTimer?.cancel();
    _highlightTimer?.cancel();
    _recordTimer?.cancel();
    _recorder.dispose();
    _messageController.dispose();
    _messageFocusNode.dispose();
    _scrollController.dispose();
    _modePanelVisible.dispose();
    _isAiTypingNotifier.dispose();
    _canSendNotifier.dispose();
    _showNewMessageBannerNotifier.dispose();
    super.dispose();
  }

  void _setReplyTo(ChatMessage message) {
    setState(() => _replyToMessage = message);
    _messageFocusNode.requestFocus();
  }

  void _cancelReply() {
    setState(() => _replyToMessage = null);
  }

  // ═══════════════════════════════════════════════════
  // 语音录制
  // ═══════════════════════════════════════════════════

  Future<void> _startRecording() async {
    try {
      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('请授予麦克风权限'), duration: Duration(seconds: 2)),
          );
        }
        return;
      }

      final dir = await getTemporaryDirectory();
      _recordPath =
          '${dir.path}/voice_msg_${DateTime.now().millisecondsSinceEpoch}.wav';

      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          numChannels: 1,
          bitRate: 32000,
          sampleRate: 16000,
        ),
        path: _recordPath!,
      );

      setState(() {
        _isRecording = true;
        _recordSeconds = 0;
      });

      _recordTimer?.cancel();
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _recordSeconds++);
      });
    } catch (e) {
      debugPrint('VoiceRecord: 开始录音失败: $e');
    }
  }

  Future<void> _stopRecording() async {
    if (!_isRecording) return;
    _recordTimer?.cancel();

    try {
      final path = await _recorder.stop();
      setState(() {
        _isRecording = false;
        _showVoiceInput = false;
      });

      if (path == null || _recordSeconds < 1) {
        _cleanupRecordFile();
        return;
      }

      // 保存为永久文件
      final appDir = await getApplicationDocumentsDirectory();
      final voiceDir = Directory('${appDir.path}/voice_messages');
      if (!await voiceDir.exists()) await voiceDir.create(recursive: true);
      final permanentPath =
          '${voiceDir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.wav';
      await File(path).copy(permanentPath);

      // 语音转文字
      final user = (context.read<AuthBloc>().state as AuthAuthenticated).user;
      final storage = RepositoryProvider.of<LocalStorageRepository>(context);
      String transcript = '';
      try {
        final transcription = AudioTranscriptionService(storage);
        transcript = await transcription.transcribe(permanentPath) ?? '';
        debugPrint('VoiceRecord: 转写结果: $transcript');
      } catch (e) {
        debugPrint('VoiceRecord: 语音转文字失败: $e');
      }

      // 由 ChatSendVoiceMessage 一次性处理：保存语音 + 触发 AI
      _chatBloc.add(ChatSendVoiceMessage(
        chatId: widget.session.id,
        userId: user.id,
        characterId: widget.session.aiCharacterId,
        audioPath: permanentPath,
        duration: _recordSeconds,
        transcript: transcript,
      ));

      _cleanupRecordFile();
    } catch (e) {
      debugPrint('VoiceRecord: 停止录音失败: $e');
      setState(() {
        _isRecording = false;
        _showVoiceInput = false;
      });
      _cleanupRecordFile();
    }
  }

  void _cancelRecording() {
    _recordTimer?.cancel();
    _recorder.stop();
    setState(() {
      _isRecording = false;
      _showVoiceInput = false;
    });
    _cleanupRecordFile();
  }

  void _cleanupRecordFile() {
    if (_recordPath != null) {
      final file = File(_recordPath!);
      if (file.existsSync()) file.deleteSync();
      _recordPath = null;
    }
    _recordSeconds = 0;
  }

  Widget _buildVoiceInputArea(bool isDark, ColorScheme colorScheme) {
    final minutes = (_recordSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (_recordSeconds % 60).toString().padLeft(2, '0');
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: GestureDetector(
        onLongPressStart: (_) => _startRecording(),
        onLongPressEnd: (_) => _stopRecording(),
        onLongPressCancel: () => _cancelRecording(),
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            color: _isRecording
                ? Colors.red.withOpacity(0.15)
                : (isDark ? const Color(0xFF2C2C2C) : const Color(0xFFEEEEEE)),
            borderRadius: BorderRadius.circular(24),
            border: _isRecording
                ? Border.all(color: Colors.red.withOpacity(0.5), width: 1)
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_isRecording) ...[
                Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '正在录音 $minutes:$seconds',
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '松开发送',
                  style: TextStyle(
                    color: isDark
                        ? Colors.white.withOpacity(0.4)
                        : Colors.black.withOpacity(0.4),
                    fontSize: 13,
                  ),
                ),
              ] else ...[
                Icon(
                  Icons.mic_rounded,
                  color: isDark
                      ? Colors.white.withOpacity(0.6)
                      : Colors.black.withOpacity(0.5),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  '按住说话',
                  style: TextStyle(
                    color: isDark
                        ? Colors.white.withOpacity(0.6)
                        : Colors.black.withOpacity(0.5),
                    fontSize: 15,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _replyPreview(ChatMessage message) {
    switch (message.type) {
      case MessageType.image:
        return '[图片]';
      case MessageType.sticker:
        return '[表情]';
      case MessageType.system:
        return '[系统消息]';
      case MessageType.voice:
        return '[语音]';
      case MessageType.text:
        return message.content.length > 50
            ? '${message.content.substring(0, 50)}...'
            : message.content;
      default:
        return '[消息]';
    }
  }

  void _showMoreActions() {
    tapHaptic();
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 16),
              child: Text('更多功能',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(0.6),
                  )),
            ),
            Row(
              children: [
                _MoreActionItem(
                  icon: Icons.card_giftcard,
                  label: '转账',
                  color: Colors.orange,
                  onTap: () {
                    Navigator.pop(ctx);
                    _showTransferDialog();
                  },
                ),
                const SizedBox(width: 16),
                _MoreActionItem(
                  icon: Icons.storefront,
                  label: '商店',
                  color: const Color(0xFF667EEA),
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => BlocProvider.value(
                          value: context.read<ShopBloc>(),
                          child: ShopScreen(
                            chatSessionId: widget.session.id,
                            receiverId: widget.session.aiCharacterId,
                            receiverName: widget.session.aiCharacterName,
                            onGiftSent: (order) {
                              final authState = context.read<AuthBloc>().state;
                              if (authState is AuthAuthenticated) {
                                context.read<ChatBloc>().add(ChatSendGift(
                                      chatId: widget.session.id,
                                      userId: authState.user.id,
                                      itemName: order.itemName,
                                      itemEmoji: order.itemEmoji,
                                      price: order.price,
                                      message: order.message,
                                    ));
                              }
                            },
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _MoreActionItem(
                  icon: Icons.call,
                  label: '语音通话',
                  color: Colors.green,
                  onTap: () {
                    Navigator.pop(ctx);
                    _startVoiceCall();
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _startVoiceCall() async {
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) return;

    final storage = RepositoryProvider.of<LocalStorageRepository>(context);
    final character =
        await storage.getAICharacter(widget.session.aiCharacterId);
    if (character == null || !mounted) return;

    final startTime = DateTime.now();
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VoiceCallScreen(
          character: character,
          userId: authState.user.id,
          storage: storage,
          chatId: widget.session.id,
        ),
      ),
    );

    // 通话结束后插入简短通话记录（不包含对话内容）
    if (mounted) {
      _insertCallRecord(character.name, startTime);
    }
  }

  /// 插入通话记录到聊天页面
  Future<void> _insertCallRecord(
      String characterName, DateTime startTime) async {
    final duration = DateTime.now().difference(startTime);
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    final durationStr =
        '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';

    final recordText = '[语音通话]\n'
        '通话时长 $durationStr\n';

    // 直接写入存储（不触发 AI 回复）
    try {
      final storage = RepositoryProvider.of<LocalStorageRepository>(context);
      await storage.saveChatMessage(ChatMessage(
        id: const Uuid().v4(),
        chatId: widget.session.id,
        senderId: 'system',
        content: recordText,
        type: MessageType.system,
        isSystem: true,
        isUser: false,
        status: MessageStatus.delivered,
        createdAt: DateTime.now(),
      ));
      // 刷新消息列表（重新加载以确保UI立即更新）
      if (mounted) {
        final bloc = context.read<ChatBloc>();
        bloc.add(ChatLoadMessages(widget.session.id));
        // 强制等待一帧确保状态更新
        await Future.delayed(const Duration(milliseconds: 100));
        // setState 已移除，BlocConsumer 已处理消息列表重建
      }
    } catch (e) {
      debugPrint('保存通话记录失败: $e');
    }
  }

  void _sendMessage() async {
    tapHaptic();
    final content = _messageController.text.trim();
    final user = (context.read<AuthBloc>().state as AuthAuthenticated).user;

    // 性能优化：通知心跳服务用户活跃
    try {
      RepositoryProvider.of<HeartbeatService>(context, listen: false)
          .notifyUserInteraction();
    } catch (_) {}

    Map<String, dynamic>? replyMetadata;
    if (_replyToMessage != null) {
      replyMetadata = {
        'replyTo': {
          'messageId': _replyToMessage!.id,
          'senderName': _replyToMessage!.senderName ??
              (_replyToMessage!.isFromAI ? 'AI' : '用户'),
          'contentPreview': _replyPreview(_replyToMessage!),
        },
      };
      setState(() => _replyToMessage = null);
    }

    if (content.isNotEmpty) {
      _chatBloc.add(ChatSendMessage(
        chatId: widget.session.id,
        userId: user.id,
        content: content,
        metadata: replyMetadata,
        enableWebSearch: _webSearchEnabled,
      ));
      _messageController.clear();
      _canSendNotifier.value = false;
    }

    _messageFocusNode.requestFocus();
    _userScrolledUp = false;
    _scrollToBottom(force: true);
    _resetSilenceTimer();
  }

  /// 策略：先显示文本，再异步逐句生成语音作为单独的语音消息发送
  Future<void> _generateVoiceForAIMessage(ChatMessage message) async {
    try {
      final storage = RepositoryProvider.of<LocalStorageRepository>(context);
      final character =
          await storage.getAICharacter(widget.session.aiCharacterId);
      if (character == null ||
          !(character.interactionConfig?.voiceReplyEnabled ?? false)) return;

      final voiceClone = VoiceCloneService();
      final voiceBase64 = voiceClone.getVoiceBase64(character.id);
      if (voiceBase64 == null) return;

      final tts = TTSService();
      final styleInstruction = voiceClone.getStyleInstruction(character.id);

      // 逐句流式合成，第一句合成完就发送语音消息
      int sentenceIndex = 0;
      await for (final audioPath in tts.synthesizeStream(
        text: message.content,
        voiceBase64: voiceBase64,
        styleInstruction: styleInstruction,
      )) {
        if (!mounted) break;

        // 永久保存音频文件
        final permanentPath = await tts.saveToPermanentDir(
            audioPath, '${message.id}_s$sentenceIndex');

        // 作为单独的语音消息发送
        await storage.saveChatMessage(ChatMessage(
          id: '${message.id}_voice_$sentenceIndex',
          chatId: message.chatId,
          senderId: message.senderId,
          senderName: message.senderName,
          content: permanentPath ?? audioPath,
          type: MessageType.voice,
          status: MessageStatus.sent,
          createdAt: message.createdAt
              .add(Duration(milliseconds: 500 * sentenceIndex)),
          metadata: {
            'text': message.content,
            'voiceGenerated': true,
            'sentenceIndex': sentenceIndex,
          },
        ));

        sentenceIndex++;

        // 第一句发送后刷新列表，后续的异步发送
        if (sentenceIndex == 1 && mounted) {
          context.read<ChatBloc>().add(ChatLoadMessages(widget.session.id));
        }
      }

      // 全部发送完后最终刷新
      if (sentenceIndex > 0 && mounted) {
        context.read<ChatBloc>().add(ChatLoadMessages(widget.session.id));
      }
    } catch (e) {
      debugPrint('VoiceGenerate: 生成语音失败: $e');
    }
  }

  void _sendSticker(String emoji) {
    tapHaptic();
    final user = (context.read<AuthBloc>().state as AuthAuthenticated).user;

    _chatBloc.add(ChatSendSticker(
      chatId: widget.session.id,
      userId: user.id,
      sticker: emoji,
    ));

    _userScrolledUp = false;
    _scrollToBottom(force: true);
    _resetSilenceTimer();
  }

  Duration _getSilenceTimeout() {
    return SilenceRules.silenceTimeout(_aiPersonality);
  }

  void _resetSilenceTimer() {
    _silenceTimer?.cancel();
    _aiBrokeSilence = false;
    _silenceTimer = Timer(_getSilenceTimeout(), _onSilenceTimeout);
  }

  void _onSilenceTimeout() {
    if (_aiBrokeSilence) return;
    if (_replyMode == ReplyMode.manual) return;
    if (!_enableProactiveMessage) return;
    _aiBrokeSilence = true;

    final user = (context.read<AuthBloc>().state is AuthAuthenticated)
        ? (context.read<AuthBloc>().state as AuthAuthenticated).user
        : null;
    if (user == null) return;

    _chatBloc.add(ChatProactiveReply(
      chatId: widget.session.id,
      userId: user.id,
    ));
  }

  void _showTransferDialog() {
    final amountController = TextEditingController();
    final msgController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
              20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.session.aiCharacterName,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 24),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Text(
                      '¥',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: amountController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        textAlign: TextAlign.start,
                        style: const TextStyle(
                            fontSize: 32, fontWeight: FontWeight.bold),
                        decoration: const InputDecoration(
                          hintText: '0.00',
                          hintStyle:
                              TextStyle(fontSize: 32, color: Colors.grey),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: TextField(
                  controller: msgController,
                  decoration: const InputDecoration(
                    hintText: '添加备注（选填）',
                    border: InputBorder.none,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    final amountText = amountController.text.trim();
                    if (amountText.isEmpty) return;
                    final amount = double.tryParse(amountText);
                    if (amount == null || amount <= 0) return;
                    if (amount > 200000) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('单次转账上限200000')),
                      );
                      return;
                    }
                    final user = context.read<AuthBloc>().state
                            is AuthAuthenticated
                        ? (context.read<AuthBloc>().state as AuthAuthenticated)
                            .user
                        : null;
                    if (user == null) return;
                    Navigator.pop(ctx);
                    _resetSilenceTimer();
                    _chatBloc.add(ChatSendRedPacket(
                      chatId: widget.session.id,
                      userId: user.id,
                      amount: amount,
                      message: msgController.text.trim().isNotEmpty
                          ? msgController.text.trim()
                          : null,
                    ));
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF07C160),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('转账',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  void _loadTopicSuggestions() {
    final topics = ['最近过得怎么样', '分享一件开心的事', '今天有什么计划'];
    setState(() => _suggestedTopics = topics);
  }

  void _checkPendingReply() async {
    final prefs = await SharedPreferences.getInstance();
    final pending = prefs.getString(PrefKeys.pendingReply(widget.session.id));
    if (mounted)
      setState(() => _hasPendingReply = pending != null && pending.isNotEmpty);
  }

  void _triggerPendingReply() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(PrefKeys.pendingReply(widget.session.id));
    setState(() => _hasPendingReply = false);
    final user = context.read<AuthBloc>().state is AuthAuthenticated
        ? (context.read<AuthBloc>().state as AuthAuthenticated).user
        : null;
    if (user == null) return;
    _chatBloc.add(ChatProactiveReply(
      chatId: widget.session.id,
      userId: user.id,
    ));
  }

  void _performSearch(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _searchTotalCount = 0;
        _searchHasMore = false;
      });
      return;
    }
    setState(() {
      _searchLoading = true;
      _searchResults = [];
      _searchTotalCount = 0;
      _searchHasMore = false;
    });
    try {
      final storage = RepositoryProvider.of<LocalStorageRepository>(context);
      final results = await storage.searchChatMessages(
        widget.session.id,
        query,
        limit: _searchPageSize,
        offset: 0,
      );
      final totalCount =
          await storage.countSearchMessages(widget.session.id, query);
      if (mounted)
        setState(() {
          _searchResults = results;
          _searchTotalCount = totalCount;
          _searchHasMore = results.length < totalCount;
        });
    } catch (_) {}
    if (mounted) setState(() => _searchLoading = false);
  }

  void _loadMoreSearchResults() async {
    if (_searchLoadingMore || !_searchHasMore) return;
    setState(() => _searchLoadingMore = true);
    try {
      final storage = RepositoryProvider.of<LocalStorageRepository>(context);
      final more = await storage.searchChatMessages(
        widget.session.id,
        _searchQuery,
        limit: _searchPageSize,
        offset: _searchResults.length,
      );
      if (mounted)
        setState(() {
          _searchResults = [..._searchResults, ...more];
          _searchHasMore = _searchResults.length < _searchTotalCount;
        });
    } catch (_) {}
    if (mounted) setState(() => _searchLoadingMore = false);
  }

  void _jumpToMessage(ChatMessage targetMessage) {
    final preservedResults = List<ChatMessage>.from(_searchResults);
    final preservedQuery = _searchQuery;
    final isLoaded =
        _cachedMessages.any((message) => message.id == targetMessage.id);

    setState(() {
      _isSearching = false;
      _searchQuery = '';
      _searchController.clear();
      _isJumpedToMessage = true;
      _jumpedToMessage = targetMessage;
      _pendingJumpTarget = isLoaded ? null : targetMessage;
      _preservedSearchResults = preservedResults;
      _preservedSearchQuery = preservedQuery;
    });

    if (isLoaded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _scrollToTargetMessage(targetMessage);
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('正在加载目标消息位置...'),
          duration: Duration(seconds: 1),
        ),
      );
      _chatBloc.add(ChatLoadUntilMessage(
        chatId: widget.session.id,
        messageId: targetMessage.id,
      ));
    }

    setState(() => _highlightedMessageId = targetMessage.id);
    _highlightTimer?.cancel();
    _highlightTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _highlightedMessageId = null);
    });
  }

  void _scrollToTargetMessage(ChatMessage target) {
    if (!_scrollController.hasClients) return;

    final messages = _cachedMessages;
    final targetIndex = messages.indexWhere((m) => m.id == target.id);

    if (targetIndex == -1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('消息未加载，请上滑加载更多历史消息后再试'),
            duration: Duration(seconds: 2)),
      );
      return;
    }

    final key = _messageKeys[target.id];
    final targetContext = key?.currentContext;
    if (targetContext != null) {
      Scrollable.ensureVisible(
        targetContext,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOut,
        alignment: 0.5,
      );
      return;
    }

    final itemsAfterTarget = messages.length - 1 - targetIndex;
    final averageItemHeight = messages.length > 1
        ? (_scrollController.position.maxScrollExtent / (messages.length - 1))
            .clamp(80.0, 260.0)
        : 80.0;
    final estimatedOffset = itemsAfterTarget * averageItemHeight;
    final clampedOffset = estimatedOffset.clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );

    _scrollController.animateTo(
      clampedOffset,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
    Timer(const Duration(milliseconds: 420), () {
      if (!mounted) return;
      final retryContext = _messageKeys[target.id]?.currentContext;
      if (retryContext != null) {
        Scrollable.ensureVisible(
          retryContext,
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeInOut,
          alignment: 0.5,
        );
      }
    });
  }

  void _returnToSearchResults() {
    setState(() {
      _isJumpedToMessage = false;
      _jumpedToMessage = null;
      _isSearching = true;
      _searchQuery = _preservedSearchQuery;
      _searchResults = _preservedSearchResults;
      _searchController.text = _preservedSearchQuery;
    });
    _searchFocusNode.requestFocus();
  }

  void _showStickerPicker() {
    tapHaptic();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.4,
        minChildSize: 0.3,
        maxChildSize: 0.7,
        expand: false,
        builder: (context, scrollController) => _StickerPickerSheet(
          onEmojiSelected: (emoji) {
            Navigator.pop(context);
            _sendSticker(emoji);
          },
          onStickerSelected: (stickerId) {
            Navigator.pop(context);
            _sendBuiltinSticker(stickerId);
          },
          onImageStickerSelected: (imagePath) {
            Navigator.pop(context);
            _sendImageSticker(imagePath);
          },
          storage: RepositoryProvider.of<LocalStorageRepository>(context),
        ),
      ),
    );
  }

  void _sendBuiltinSticker(String stickerId) {
    final user = (context.read<AuthBloc>().state as AuthAuthenticated).user;
    _chatBloc.add(ChatSendSticker(
      chatId: widget.session.id,
      userId: user.id,
      sticker: stickerId,
    ));
    _userScrolledUp = false;
    _scrollToBottom(force: true);
  }

  void _sendImageSticker(String stickerId) {
    final user = (context.read<AuthBloc>().state as AuthAuthenticated).user;
    _chatBloc.add(ChatSendSticker(
      chatId: widget.session.id,
      userId: user.id,
      sticker: stickerId,
      isImageSticker: true,
    ));
    _userScrolledUp = false;
    _scrollToBottom(force: true);
  }

  Widget _buildNewMessageBanner() {
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () {
        _showNewMessageBannerNotifier.value = false;
        _scrollToBottom(force: true);
      },
      child: Container(
        alignment: Alignment.center,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: colorScheme.primary,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: colorScheme.primary.withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.keyboard_arrow_down,
                  size: 18, color: Colors.white),
              const SizedBox(width: 4),
              const Text('新消息',
                  style: TextStyle(fontSize: 13, color: Colors.white)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorRetry(BuildContext context, String message) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off,
                size: 48, color: colorScheme.onSurface.withOpacity(0.3)),
            const SizedBox(height: 16),
            Text('消息加载失败',
                style: TextStyle(
                    fontSize: 16,
                    color: colorScheme.onSurface.withOpacity(0.5))),
            const SizedBox(height: 8),
            Text(message,
                style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurface.withOpacity(0.3)),
                textAlign: TextAlign.center),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () =>
                  _chatBloc.add(ChatLoadMessages(widget.session.id)),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }

  void _scrollToBottom({bool force = false}) {
    if (!force && _userScrolledUp) return;

    _showNewMessageBannerNotifier.value = false;

    Future.delayed(const Duration(milliseconds: 100), () {
      if (!mounted) return;
      if (!_scrollController.hasClients) return;
      if (!force && _userScrolledUp) return;

      _scrollController.jumpTo(0);
    });
  }

  Future<void> _deleteMessage(ChatMessage message) async {
    confirmHaptic();
    try {
      final storage = RepositoryProvider.of<LocalStorageRepository>(context);
      await storage.deleteChatMessage(message.id);
      _chatBloc.add(ChatLoadMessages(widget.session.id));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('消息已删除'), duration: Duration(seconds: 1)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败: $e')),
        );
      }
    }
  }

  Future<void> _recallMessage(ChatMessage message) async {
    try {
      final storage = RepositoryProvider.of<LocalStorageRepository>(context);
      final recalledMessage = message.copyWith(
        content: '已撤回',
        status: MessageStatus.failed,
        metadata: {'recalled': true, 'originalContent': message.content},
      );
      await storage.saveChatMessage(recalledMessage);
      _chatBloc.add(ChatLoadMessages(widget.session.id));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('消息已撤回'), duration: Duration(seconds: 1)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('撤回失败: $e')),
        );
      }
    }
  }

  void _showMessageOptions(BuildContext context, ChatMessage message) {
    final isUserMessage = message.isFromUser;
    final isAIMessage = message.isFromAI;
    final canRecall = isUserMessage &&
        DateTime.now().difference(message.createdAt).inMinutes <= 2 &&
        message.content != '已撤回';
    final isRecalled =
        message.metadata?['recalled'] == true || message.content == '已撤回';
    final canEditAI =
        isAIMessage && !isRecalled && message.type == MessageType.text;
    final canRegenerate = isAIMessage && !isRecalled;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.reply, color: Colors.blue),
              title: const Text('回复'),
              onTap: () {
                Navigator.pop(context);
                _setReplyTo(message);
              },
            ),
            if (!isRecalled && message.type == MessageType.text)
              ListTile(
                leading: const Icon(Icons.copy, color: Colors.teal),
                title: const Text('复制'),
                onTap: () {
                  Navigator.pop(context);
                  Clipboard.setData(ClipboardData(text: message.content));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('已复制到剪贴板'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
              ),
            if (canEditAI)
              ListTile(
                leading: const Icon(Icons.edit, color: Colors.green),
                title: const Text('编辑'),
                subtitle: const Text('修改AI的回复内容'),
                onTap: () {
                  Navigator.pop(context);
                  _showEditAIReplyDialog(message);
                },
              ),
            if (canRegenerate)
              ListTile(
                leading: const Icon(Icons.refresh, color: Colors.purple),
                title: const Text('重新生成'),
                subtitle: const Text('让AI重新回复，覆盖当前内容'),
                onTap: () {
                  Navigator.pop(context);
                  _showRegenerateConfirm(message);
                },
              ),
            if (canRecall)
              ListTile(
                leading: const Icon(Icons.undo, color: Colors.orange),
                title: const Text('撤回'),
                subtitle: const Text('2分钟内可撤回'),
                onTap: () {
                  Navigator.pop(context);
                  _recallMessage(message);
                },
              ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: Colors.red[400]),
              title: const Text('删除'),
              onTap: () {
                Navigator.pop(context);
                _showDeleteConfirm(message);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showEditAIReplyDialog(ChatMessage message) {
    final controller = TextEditingController(text: message.content);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑AI回复'),
        content: TextField(
          controller: controller,
          maxLines: null,
          minLines: 3,
          autofocus: true,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: '输入新的回复内容',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              final newContent = controller.text.trim();
              if (newContent.isEmpty) return;
              Navigator.pop(ctx);
              _chatBloc.add(ChatEditAIReply(
                chatId: widget.session.id,
                messageId: message.id,
                newContent: newContent,
              ));
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _showRegenerateConfirm(ChatMessage message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重新生成'),
        content: const Text('AI将重新回复，当前回复会被覆盖。确定吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _chatBloc.add(ChatRegenerateAIReply(
                chatId: widget.session.id,
                messageId: message.id,
              ));
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirm(ChatMessage message) {
    final ctx = context;
    showDialog(
      context: ctx,
      builder: (context) => AlertDialog(
        title: const Text('删除消息'),
        content: const Text('确定要删除这条消息吗？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteMessage(message);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  Future<void> _openChatSettings(BuildContext context) async {
    final storage = RepositoryProvider.of<LocalStorageRepository>(context);
    AICharacter? character;

    try {
      character = await storage.getAICharacter(
          _currentSession?.aiCharacterId ?? widget.session.aiCharacterId);
    } catch (e) {
      debugPrint('获取角色信息失败: $e');
    }

    if (mounted) {
      final settingsChanged = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChatSettingsScreen(
            session: _currentSession ?? widget.session,
            character: character,
          ),
        ),
      );

      if (mounted) {
        debugPrint('从设置页面返回，settingsChanged=$settingsChanged');

        // 处理从设置页面发起的转账
        if (settingsChanged is Map &&
            settingsChanged['pendingTransfer'] != null) {
          final transfer =
              settingsChanged['pendingTransfer'] as Map<String, dynamic>;
          final amount = (transfer['amount'] as num).toDouble();
          final message = transfer['message'] as String? ?? '';
          final user = context.read<AuthBloc>().state;
          if (user is AuthAuthenticated) {
            _chatBloc.add(ChatSendRedPacket(
              chatId: widget.session.id,
              userId: user.user.id,
              amount: amount,
              message: message,
            ));
          }
          _hasSettingsChanged = true;
        }

        if (settingsChanged == true || settingsChanged is Map) {
          _hasSettingsChanged = true;
          _chatBloc.add(ChatLoadMessages(widget.session.id));
        }

        final updatedSession = await storage.getChatSession(widget.session.id);
        if (updatedSession != null && mounted) {
          setState(() {
            _currentSession = updatedSession;
            _isBlockedByAI = updatedSession.isBlocked &&
                updatedSession.blockedBy == BlockedBy.ai;
            _isBlockedByUser = updatedSession.isBlocked &&
                updatedSession.blockedBy == BlockedBy.user;
          });
          debugPrint('已更新会话状态 - lastMessage: ${updatedSession.lastMessage}');
        }
        final updatedCharacter = await storage.getAICharacter(
            _currentSession?.aiCharacterId ?? widget.session.aiCharacterId);
        if (updatedCharacter != null && mounted) {
          setState(() {
            _aiPersonality = updatedCharacter.personality;
            _displayName = updatedCharacter.userAlias ?? updatedCharacter.name;
            _replyMode = updatedCharacter.interactionConfig?.replyMode;
            _enableProactiveMessage =
                updatedCharacter.interactionConfig?.enableMomentInteraction ??
                    true;
          });
        }
      }
    }
  }

  Widget _buildMessageList(BuildContext context, List<ChatMessage> messages,
      {bool showTyping = false}) {
    final authState = context.read<AuthBloc>().state;
    final userAvatarUrl =
        authState is AuthAuthenticated ? authState.user.avatarUrl : null;
    final currentAvatar =
        _currentSession?.aiCharacterAvatar ?? widget.session.aiCharacterAvatar;
    final currentName =
        _currentSession?.aiCharacterName ?? widget.session.aiCharacterName;

    final totalItems =
        messages.length + (showTyping ? 1 : 0) + (_hasMoreMessages ? 1 : 0);

    return Container(
      color: Colors.transparent,
      child: ListView.builder(
        controller: _scrollController,
        physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics()),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        reverse: true,
        itemCount: totalItems,
        itemBuilder: (context, index) {
          if (_hasMoreMessages && index == totalItems - 1) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: _isLoadingMore
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text('上滑加载更多历史消息',
                        style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withOpacity(0.4))),
              ),
            );
          }

          if (showTyping && index == 0) {
            return TypingIndicator(
              avatarUrl: currentAvatar,
              name: currentName,
            );
          }

          final msgIndex = showTyping ? index - 1 : index;
          final reversedIndex = messages.length - 1 - msgIndex;
          final message = messages[reversedIndex];
          final isHighlighted = message.id == _highlightedMessageId;
          final showTime = reversedIndex == messages.length - 1 ||
              messages[reversedIndex + 1]
                      .createdAt
                      .difference(message.createdAt)
                      .inMinutes >
                  5;

          return AnimatedListItem(
            index: msgIndex,
            key: _messageKeys.putIfAbsent(message.id, () => GlobalKey()),
            child: Container(
              decoration: isHighlighted
                  ? BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .primaryContainer
                          .withOpacity(0.3),
                      borderRadius: BorderRadius.circular(10),
                    )
                  : null,
              padding: isHighlighted
                  ? const EdgeInsets.symmetric(vertical: 4)
                  : null,
              child: Column(
                children: [
                  GestureDetector(
                    onLongPress: () {
                      confirmHaptic();
                      _showMessageOptions(context, message);
                    },
                    child: _MessageBubble(
                      message: message,
                      aiAvatarUrl: currentAvatar,
                      userAvatarUrl: userAvatarUrl,
                      aiName: currentName,
                      weatherIcon: message.isFromAI ? _weatherIcon : null,
                      novelMode: RepositoryProvider.of<LocalStorageRepository>(
                              context)
                          .isChatStyleNovelModeEnabled(),
                      hasBackgroundImage:
                          _currentSession?.backgroundImage != null &&
                              _currentSession!.backgroundImage!.isNotEmpty,
                      onImageTap: message.type == MessageType.image
                          ? () => _showFullScreenImage(message.content)
                          : null,
                    ),
                  ),
                  if (showTime)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        _formatMessageTime(message.createdAt),
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withOpacity(0.4),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildInputArea(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (_isBlockedByAI) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: colorScheme.error.withOpacity(0.08),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.block, size: 14, color: colorScheme.error),
                const SizedBox(width: 6),
                Text(
                  '你处于对方黑名单中，消息可能不会被回复',
                  style: TextStyle(fontSize: 12, color: colorScheme.error),
                ),
              ],
            ),
          ),
          _buildNormalInput(context, colorScheme),
        ],
      );
    }

    if (_isBlockedByUser) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          border: Border(
              top: BorderSide(color: colorScheme.outlineVariant, width: 0.5)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.block,
                size: 16, color: colorScheme.onSurface.withOpacity(0.5)),
            const SizedBox(width: 8),
            Text(
              '你已拉黑对方',
              style: TextStyle(
                  fontSize: 14, color: colorScheme.onSurface.withOpacity(0.5)),
            ),
          ],
        ),
      );
    }

    return _buildNormalInput(context, colorScheme);
  }

  Widget _buildNormalInput(BuildContext context, ColorScheme colorScheme) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_hasPendingReply)
          GestureDetector(
            onTap: _triggerPendingReply,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: colorScheme.primary.withOpacity(0.08),
              child: Row(
                children: [
                  Icon(Icons.unfold_more, size: 16, color: colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '上滑查看 TA 的回复',
                      style:
                          TextStyle(fontSize: 13, color: colorScheme.primary),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: colorScheme.primary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text('查看回复',
                        style: TextStyle(fontSize: 12, color: Colors.white)),
                  ),
                ],
              ),
            ),
          ),
        if (_replyToMessage != null)
          Container(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
            decoration: BoxDecoration(
              color: colorScheme.primary.withOpacity(0.08),
              border: Border(
                top: BorderSide(color: colorScheme.primary.withOpacity(0.2)),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 3,
                  height: 32,
                  decoration: BoxDecoration(
                    color: colorScheme.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _replyToMessage!.senderName ??
                            (_replyToMessage!.isFromAI ? 'AI' : '用户'),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _replyPreview(_replyToMessage!),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close,
                      size: 18, color: colorScheme.onSurface.withOpacity(0.4)),
                  onPressed: _cancelReply,
                  constraints: const BoxConstraints(),
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
        Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF000000) : const Color(0xFFF5F5F5),
            border: Border(
              top: BorderSide(
                color: isDark
                    ? Colors.white.withOpacity(0.08)
                    : Colors.black.withOpacity(0.06),
                width: 0.5,
              ),
            ),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TopicSuggestions(
                  topics: _suggestedTopics,
                  onTap: (topic) {
                    setState(() => _suggestedTopics = []);
                    _messageController.text = topic;
                    _sendMessage();
                  },
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Row(
                    children: [
                      _buildWebSearchToggle(colorScheme, isDark),
                    ],
                  ),
                ),
                if (_showVoiceInput)
                  _buildVoiceInputArea(isDark, colorScheme)
                else
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        // 语音按钮（切换语音/键盘模式）
                        GestureDetector(
                          onTap: () {
                            setState(() => _showVoiceInput = !_showVoiceInput);
                            if (!_showVoiceInput && _isRecording) {
                              _cancelRecording();
                            }
                          },
                          child: Container(
                            width: 40,
                            height: 40,
                            margin: const EdgeInsets.only(right: 8, bottom: 2),
                            child: Icon(
                              _showVoiceInput
                                  ? Icons.keyboard
                                  : Icons.mic_rounded,
                              color: isDark
                                  ? Colors.white.withOpacity(0.7)
                                  : Colors.black.withOpacity(0.6),
                              size: 24,
                            ),
                          ),
                        ),
                        // 输入框
                        Expanded(
                          child: Container(
                            constraints: const BoxConstraints(
                                minHeight: 40, maxHeight: 120),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF2C2C2C)
                                  : const Color(0xFFEEEEEE),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                // 文本输入
                                Expanded(
                                  child: TextField(
                                    controller: _messageController,
                                    focusNode: _messageFocusNode,
                                    decoration: InputDecoration(
                                      hintText: '发消息...',
                                      hintStyle: TextStyle(
                                        color: isDark
                                            ? Colors.white.withOpacity(0.35)
                                            : Colors.black.withOpacity(0.35),
                                        fontSize: 15,
                                      ),
                                      filled: false,
                                      border: InputBorder.none,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 10,
                                      ),
                                    ),
                                    style: TextStyle(
                                      color: colorScheme.onSurface,
                                      fontSize: 15,
                                    ),
                                    textInputAction: TextInputAction.send,
                                    onSubmitted: (_) => _sendMessage(),
                                    maxLines: null,
                                    onChanged: (v) {
                                      final canSend = v.trim().isNotEmpty;
                                      if (canSend != _canSend) {
                                        _canSendNotifier.value = canSend;
                                      }
                                      if (v.isEmpty &&
                                          _showTopics &&
                                          _suggestedTopics.isEmpty) {
                                        _loadTopicSuggestions();
                                      }
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // 表情按钮
                        GestureDetector(
                          onTap: _showStickerPicker,
                          child: Container(
                            width: 36,
                            height: 40,
                            alignment: Alignment.center,
                            child: Icon(
                              Icons.emoji_emotions_outlined,
                              color: isDark
                                  ? Colors.white.withOpacity(0.6)
                                  : Colors.black.withOpacity(0.5),
                              size: 24,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        // 语音通话按钮
                        GestureDetector(
                          onTap: _startVoiceCall,
                          child: Container(
                            width: 36,
                            height: 40,
                            alignment: Alignment.center,
                            child: Icon(
                              Icons.phone_outlined,
                              color: isDark
                                  ? Colors.white.withOpacity(0.6)
                                  : Colors.black.withOpacity(0.5),
                              size: 22,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        // 图片按钮 / 发送按钮（有文字时显示发送）
                        ValueListenableBuilder<bool>(
                          valueListenable: _canSendNotifier,
                          builder: (context, canSend, _) {
                            if (canSend) {
                              return GestureDetector(
                                onTap: _sendMessage,
                                child: Container(
                                  width: 40,
                                  height: 40,
                                  margin: const EdgeInsets.only(bottom: 2),
                                  decoration: BoxDecoration(
                                    color: colorScheme.primary,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.arrow_upward_rounded,
                                    color: Colors.white,
                                    size: 22,
                                  ),
                                ),
                              );
                            } else {
                              return GestureDetector(
                                onTap: _showMoreActions,
                                child: Container(
                                  width: 36,
                                  height: 40,
                                  alignment: Alignment.center,
                                  child: Icon(
                                    Icons.add_circle_outline,
                                    color: isDark
                                        ? Colors.white.withOpacity(0.6)
                                        : Colors.black.withOpacity(0.5),
                                    size: 24,
                                  ),
                                ),
                              );
                            }
                          },
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWebSearchToggle(ColorScheme colorScheme, bool isDark) {
    final enabled = _webSearchEnabled;
    final bgColor = enabled
        ? colorScheme.primary
        : (isDark ? const Color(0xFF1F1F1F) : Colors.white);
    final fgColor = enabled
        ? Colors.white
        : (isDark
            ? Colors.white.withOpacity(0.72)
            : Colors.black.withOpacity(0.62));
    final borderColor = enabled
        ? colorScheme.primary
        : (isDark
            ? Colors.white.withOpacity(0.12)
            : Colors.black.withOpacity(0.10));

    return GestureDetector(
      onTap: () => setState(() => _webSearchEnabled = !_webSearchEnabled),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: borderColor),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: colorScheme.primary.withOpacity(0.24),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.public_rounded, size: 15, color: fgColor),
            const SizedBox(width: 6),
            Text(
              '联网搜索',
              style: TextStyle(
                color: fgColor,
                fontSize: 13,
                fontWeight: enabled ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageListFromStorage(BuildContext context) {
    return FutureBuilder<List<ChatMessage>>(
      future: RepositoryProvider.of<LocalStorageRepository>(context)
          .getChatMessages(widget.session.id),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasData && snapshot.data!.isNotEmpty) {
          return _buildMessageList(context, snapshot.data!);
        }
        return _buildEmptyChat(context);
      },
    );
  }

  void _logTransferStatus(List<ChatMessage> messages, String source) {
    for (final msg in messages) {
      if (msg.type == MessageType.system &&
          msg.metadata?['type'] == 'red_packet') {
        final status = msg.metadata?['transferStatus'] as String? ?? 'unknown';
        debugPrint(
            '[SYNC] TransferCard rebuild check: source=$source, msgId=${msg.id.substring(0, 8)}..., status=$status');
        break;
      }
    }
  }

  PreferredSizeWidget _buildJumpedAppBar(ColorScheme colorScheme) {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: _returnToSearchResults,
      ),
      title: _buildChatTitle(colorScheme),
      centerTitle: true,
      elevation: 0,
      actions: [
        IconButton(
          icon: const Icon(Icons.search),
          tooltip: '搜索聊天记录',
          onPressed: _returnToSearchResults,
        ),
      ],
    );
  }

  PreferredSizeWidget _buildSearchAppBar(ColorScheme colorScheme) {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () {
          setState(() {
            _isSearching = false;
            _searchQuery = '';
            _searchResults = [];
            _searchController.clear();
          });
        },
      ),
      title: TextField(
        controller: _searchController,
        focusNode: _searchFocusNode,
        autofocus: true,
        decoration: InputDecoration(
          hintText: '搜索聊天记录',
          hintStyle: TextStyle(color: colorScheme.onSurface.withOpacity(0.4)),
          border: InputBorder.none,
        ),
        style: TextStyle(fontSize: 16, color: colorScheme.onSurface),
        onChanged: (v) {
          setState(() => _searchQuery = v);
          _performSearch(v);
        },
      ),
      elevation: 0,
      actions: [
        if (_searchQuery.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: () {
              setState(() {
                _searchQuery = '';
                _searchResults = [];
                _searchController.clear();
              });
              _searchFocusNode.requestFocus();
            },
          ),
      ],
    );
  }

  /// 带流式输出气泡的消息列表
  Widget _buildMessageListWithStreaming(BuildContext context,
      List<ChatMessage> messages, String streamingText, String characterName,
      {String reasoning = ''}) {
    final authState = context.read<AuthBloc>().state;
    final userAvatarUrl =
        authState is AuthAuthenticated ? authState.user.avatarUrl : null;
    final currentAvatar =
        _currentSession?.aiCharacterAvatar ?? widget.session.aiCharacterAvatar;
    final currentName =
        _currentSession?.aiCharacterName ?? widget.session.aiCharacterName;

    // 流式气泡占一个item（index 0），消息列表占剩余items
    final totalItems = messages.length + 1 + (_hasMoreMessages ? 1 : 0);

    return Container(
      color: Colors.transparent,
      child: ListView.builder(
        controller: _scrollController,
        physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics()),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        reverse: true,
        itemCount: totalItems,
        itemBuilder: (context, index) {
          if (_hasMoreMessages && index == totalItems - 1) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: _isLoadingMore
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text('上滑加载更多历史消息',
                        style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withOpacity(0.4))),
              ),
            );
          }

          // index 0 = 流式输出气泡（因为reverse: true，显示在最底部）
          if (index == 0) {
            if (streamingText.isEmpty) {
              return TypingIndicator(
                avatarUrl: currentAvatar,
                name: currentName,
              );
            }
            return _StreamingBubble(
              text: streamingText,
              reasoning: reasoning,
              avatarUrl: currentAvatar,
              name: currentName,
              novelMode: RepositoryProvider.of<LocalStorageRepository>(context)
                  .isChatStyleNovelModeEnabled(),
            );
          }

          // 消息列表
          final msgIndex = index - 1;
          final reversedIndex = messages.length - 1 - msgIndex;
          if (reversedIndex < 0 || reversedIndex >= messages.length)
            return const SizedBox();
          final message = messages[reversedIndex];
          final isHighlighted = message.id == _highlightedMessageId;

          return Container(
            key: ValueKey(message.id),
            decoration: isHighlighted
                ? BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .primaryContainer
                        .withOpacity(0.3),
                    borderRadius: BorderRadius.circular(10),
                  )
                : null,
            padding:
                isHighlighted ? const EdgeInsets.symmetric(vertical: 4) : null,
            child: _MessageBubble(
              message: message,
              aiAvatarUrl: currentAvatar,
              userAvatarUrl: userAvatarUrl,
              aiName: currentName,
              novelMode:
                  RepositoryProvider.of<LocalStorageRepository>(context)
                      .isChatStyleNovelModeEnabled(),
              hasBackgroundImage: _currentSession?.backgroundImage != null &&
                  _currentSession!.backgroundImage!.isNotEmpty,
              onImageTap: message.type == MessageType.image ? () {} : null,
            ),
          );
        },
      ),
    );
  }

  Widget _buildSearchResults(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final authState = context.read<AuthBloc>().state;
    final userAvatarUrl =
        authState is AuthAuthenticated ? authState.user.avatarUrl : null;
    final currentAvatar =
        _currentSession?.aiCharacterAvatar ?? widget.session.aiCharacterAvatar;
    if (_searchLoading) return const Center(child: CircularProgressIndicator());
    if (_searchResults.isEmpty)
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.search_off,
              size: 48, color: colorScheme.onSurface.withOpacity(0.2)),
          const SizedBox(height: 12),
          Text('未找到相关消息',
              style: TextStyle(color: colorScheme.onSurface.withOpacity(0.4))),
        ]),
      );
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            _searchHasMore
                ? '已加载${_searchResults.length} 条，共$_searchTotalCount 条结果'
                : '找到 $_searchTotalCount 条结果',
            style: TextStyle(
                fontSize: 12, color: colorScheme.onSurface.withOpacity(0.5)),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: _searchResults.length + (_searchHasMore ? 1 : 0),
            itemBuilder: (context, index) {
              // "Load more" button at the bottom
              if (index == _searchResults.length) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: _searchLoadingMore
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : GestureDetector(
                            onTap: _loadMoreSearchResults,
                            child: Text(
                              '加载更多',
                              style: TextStyle(
                                fontSize: 13,
                                color: colorScheme.primary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                  ),
                );
              }
              final msg = _searchResults[index];
              final senderName = msg.isFromAI
                  ? ((msg.senderName ?? '').isNotEmpty
                      ? (msg.senderName ?? 'AI')
                      : 'AI')
                  : '用户';
              return InkWell(
                onTap: () => _jumpToMessage(msg),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 4),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: msg.isFromAI
                            ? Colors.purple.withOpacity(0.1)
                            : Colors.blue.withOpacity(0.1),
                      ),
                      child: ClipOval(
                        child: _buildSearchResultAvatar(
                          msg.isFromAI ? currentAvatar : userAvatarUrl,
                          36.0,
                          msg.isFromAI,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Text(senderName,
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color:
                                      colorScheme.onSurface.withOpacity(0.6))),
                          const Spacer(),
                          Text(DateFormat('MM/dd HH:mm').format(msg.createdAt),
                              style: TextStyle(
                                  fontSize: 11,
                                  color:
                                      colorScheme.onSurface.withOpacity(0.35))),
                        ]),
                        const SizedBox(height: 3),
                        _buildHighlightedText(
                            msg.content, _searchQuery, colorScheme),
                      ],
                    )),
                  ]),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSearchResultAvatar(String? avatarUrl, double size, bool isAI) {
    Widget fallback() => Icon(
          isAI ? Icons.smart_toy_outlined : Icons.person_outline,
          size: size * 0.5,
          color: isAI ? Colors.purple : Colors.blue,
        );

    final image = AvatarResolver.imageWidget(
      avatarUrl,
      width: size,
      height: size,
      onError: fallback,
    );
    if (image != null) return image;
    return fallback();
  }

  Widget _buildHighlightedText(
      String text, String query, ColorScheme colorScheme) {
    if (query.isEmpty) {
      return Text(text,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontSize: 14, color: colorScheme.onSurface.withOpacity(0.7)));
    }
    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final spans = <TextSpan>[];
    int start = 0;
    while (true) {
      final idx = lowerText.indexOf(lowerQuery, start);
      if (idx == -1) {
        if (start < text.length) {
          spans.add(TextSpan(
              text: text.substring(start),
              style: TextStyle(
                  fontSize: 14,
                  color: colorScheme.onSurface.withOpacity(0.7))));
        }
        break;
      }
      if (idx > start) {
        spans.add(TextSpan(
            text: text.substring(start, idx),
            style: TextStyle(
                fontSize: 14, color: colorScheme.onSurface.withOpacity(0.7))));
      }
      spans.add(TextSpan(
          text: text.substring(idx, idx + query.length),
          style: TextStyle(
              fontSize: 14,
              color: colorScheme.primary,
              fontWeight: FontWeight.w600,
              backgroundColor: colorScheme.primary.withOpacity(0.15))));
      start = idx + query.length;
    }
    return RichText(
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(children: spans),
    );
  }

  Widget _buildEmptyChat(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final currentAvatar =
        _currentSession?.aiCharacterAvatar ?? widget.session.aiCharacterAvatar;
    final currentName =
        _currentSession?.aiCharacterName ?? widget.session.aiCharacterName;

    final greetings = [
      '你好呀，我是$currentName',
      '终于等到你了，想聊点什么？',
      '今天过得怎么样？和我分享一下吧',
      '我在这里，随时陪你聊天',
    ];
    final greeting =
        greetings[DateTime.now().millisecondsSinceEpoch % greetings.length];

    final suggestedTopics = [
      '今天发生了什么有趣的事？',
      '你最近有什么烦恼吗？',
      '分享一首你喜欢的歌吧',
      '你理想中的生活是什么样的？',
      '说说你最喜欢的电影',
      '你小时候的梦想是什么？',
    ];
    final randomTopics = suggestedTopics..shuffle();
    final displayTopics = randomTopics.take(3).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 40),
          TweenAnimationBuilder<double>(
            duration: const Duration(milliseconds: 800),
            curve: Curves.easeOutBack,
            tween: Tween(begin: 0, end: 1),
            builder: (context, value, child) {
              return Transform.scale(
                scale: value,
                child: child,
              );
            },
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: colorScheme.primary.withOpacity(0.3),
                  width: 3,
                ),
                boxShadow: [
                  BoxShadow(
                    color: colorScheme.primary.withOpacity(0.15),
                    blurRadius: 20,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: ClipOval(
                child: currentAvatar != null && currentAvatar.isNotEmpty
                    ? (AvatarResolver.imageWidget(currentAvatar,
                            fit: BoxFit.cover,
                            onError: () =>
                                _buildAvatarPlaceholder(currentName, colorScheme)) ??
                        _buildAvatarPlaceholder(currentName, colorScheme))
                    : _buildAvatarPlaceholder(currentName, colorScheme),
              ),
            ),
          ),
          const SizedBox(height: 24),
          TweenAnimationBuilder<double>(
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOut,
            tween: Tween(begin: 0, end: 1),
            builder: (context, value, child) {
              return Opacity(
                opacity: value,
                child: Transform.translate(
                  offset: Offset(0, 10 * (1 - value)),
                  child: child,
                ),
              );
            },
            child: Text(
              greeting,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: colorScheme.onSurface.withOpacity(0.8),
              ),
            ),
          ),
          const SizedBox(height: 8),
          TweenAnimationBuilder<double>(
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOut,
            tween: Tween(begin: 0, end: 1),
            builder: (context, value, child) {
              return Opacity(
                opacity: value,
                child: Transform.translate(
                  offset: Offset(0, 10 * (1 - value)),
                  child: child,
                ),
              );
            },
            child: Text(
              '试试下面这些话题开始聊天吧',
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.onSurface.withOpacity(0.4),
              ),
            ),
          ),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: colorScheme.outline.withOpacity(0.1),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.lightbulb_outline,
                        size: 18, color: colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      '推荐话题',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ...displayTopics.map((topic) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: GestureDetector(
                        onTap: () {
                          _messageController.text = topic;
                          _sendMessage();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color:
                                colorScheme.primaryContainer.withOpacity(0.4),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: colorScheme.primary.withOpacity(0.15),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.chat_bubble_outline,
                                size: 14,
                                color: colorScheme.primary.withOpacity(0.6),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  topic,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: colorScheme.primary,
                                  ),
                                ),
                              ),
                              Icon(
                                Icons.arrow_forward_ios,
                                size: 12,
                                color: colorScheme.primary.withOpacity(0.3),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatarPlaceholder(String name, ColorScheme colorScheme) {
    return Container(
      color: colorScheme.primaryContainer,
      child: Center(
        child: Text(
          name.isNotEmpty ? name.substring(0, 1) : 'A',
          style: TextStyle(
            fontSize: 36,
            fontWeight: FontWeight.bold,
            color: colorScheme.primary,
          ),
        ),
      ),
    );
  }

  void _showFullScreenImage(String imagePath) {
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => _FullScreenImage(imagePath: imagePath)));
  }

  String _formatMessageTime(DateTime time) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate = DateTime(time.year, time.month, time.day);
    final daysDiff = today.difference(messageDate).inDays;

    if (messageDate == today) {
      return DateFormat('HH:mm').format(time);
    } else if (daysDiff == 1) {
      return '昨天 ${DateFormat('HH:mm').format(time)}';
    } else if (daysDiff >= 2 && daysDiff <= 6) {
      return DateFormat('E HH:mm', 'zh_CN').format(time);
    } else if (time.year == now.year) {
      return DateFormat('M/d HH:mm').format(time);
    } else {
      return DateFormat('yyyy/M/d HH:mm').format(time);
    }
  }
}

class _MoreActionItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _MoreActionItem({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

class _FullScreenImage extends StatefulWidget {
  final String imagePath;
  const _FullScreenImage({required this.imagePath});

  @override
  State<_FullScreenImage> createState() => _FullScreenImageState();
}

class _FullScreenImageState extends State<_FullScreenImage>
    with SingleTickerProviderStateMixin {
  final TransformationController _transformController =
      TransformationController();
  late AnimationController _animController;

  double _scale = 1.0;
  double _minScale = 0.5;
  double _maxScale = 4.0;
  bool _showControls = true;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
  }

  @override
  void dispose() {
    _transformController.dispose();
    _animController.dispose();
    super.dispose();
  }

  void _zoomIn() {
    _scale = (_scale * 1.5).clamp(_minScale, _maxScale);
    _animController.value = 0;
    _animController.addListener(() {
      _transformController.value = Matrix4.identity()..scale(_scale);
    });
    _animController.forward();
  }

  void _zoomOut() {
    _scale = (_scale / 1.5).clamp(_minScale, _maxScale);
    _animController.value = 0;
    _animController.addListener(() {
      _transformController.value = Matrix4.identity()..scale(_scale);
    });
    _animController.forward();
  }

  void _resetZoom() {
    _scale = 1.0;
    _animController.value = 0;
    _animController.addListener(() {
      _transformController.value = Matrix4.identity()..scale(_scale);
    });
    _animController.forward();
  }

  Future<void> _saveToGallery() async {
    // Android 10+ 使用 MediaStore API 保存，确保真实出现在系统相册
    if (Platform.isAndroid) {
      try {
        final channel = MethodChannel('com.solace.solace/gallery');
        final result = await channel.invokeMethod<bool>('saveImageToGallery', {
          'filePath': widget.imagePath,
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result == true ? '已保存到系统相册' : '保存失败，请尝试截图'),
              backgroundColor: result == true ? Colors.green : Colors.red,
            ),
          );
        }
        return;
      } catch (e) {
        debugPrint('[FullScreenImage] MethodChannel 保存失败: $e');
        // 回退到文件方案
      }
    }

    // 备选方案：直接复制文件到公共目录
    try {
      final file = File(widget.imagePath);
      if (!await file.exists()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('图片文件不存在')),
          );
        }
        return;
      }

      final dir = Directory('/storage/emulated/0/DCIM/Solace');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final fileName = 'solace_${DateTime.now().millisecondsSinceEpoch}.png';
      final destPath = '${dir.path}/$fileName';
      await file.copy(destPath);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已保存到 DCIM/Solace/ 目录，请手动刷新相册'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('[FullScreenImage] 保存失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('保存失败，请尝试截图')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 主图片预览
          GestureDetector(
            onTap: () => setState(() => _showControls = !_showControls),
            child: InteractiveViewer(
              transformationController: _transformController,
              minScale: _minScale,
              maxScale: _maxScale,
              constrained: false,
              child: Image.file(
                File(widget.imagePath),
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(Icons.broken_image,
                    size: 64, color: Colors.white54),
              ),
            ),
          ),

          // 顶部栏（返回 + 文件名）
          AnimatedOpacity(
            opacity: _showControls ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: Container(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.6),
                    Colors.transparent,
                  ],
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Spacer(),
                    Text(
                      '角色图片',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.8),
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Spacer(),
                    const SizedBox(width: 48), // 平衡布局
                  ],
                ),
              ),
            ),
          ),

          // 底部工具栏（缩放 + 保存）
          AnimatedOpacity(
            opacity: _showControls ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).padding.bottom + 8,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withOpacity(0.6),
                    ],
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // 缩小
                        _ToolButton(
                          icon: Icons.zoom_out,
                          label: '缩小',
                          onTap: _zoomOut,
                        ),
                        const SizedBox(width: 8),
                        // 重置
                        _ToolButton(
                          icon: Icons.aspect_ratio,
                          label: '重置',
                          onTap: _resetZoom,
                        ),
                        const SizedBox(width: 8),
                        // 放大
                        _ToolButton(
                          icon: Icons.zoom_in,
                          label: '放大',
                          onTap: _zoomIn,
                        ),
                        const SizedBox(width: 8),
                        // 保存
                        _ToolButton(
                          icon: Icons.download_rounded,
                          label: '保存',
                          color: Colors.greenAccent,
                          onTap: _saveToGallery,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // 缩放比例指示
          if (_scale != 1.0 && _showControls)
            Positioned(
              top: MediaQuery.of(context).padding.top + 56,
              right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${(_scale * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 全屏预览底部工具按钮
class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  const _ToolButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.white.withOpacity(0.1),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color ?? Colors.white, size: 20),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: color ?? Colors.white.withOpacity(0.9),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final String? aiAvatarUrl;
  final String? userAvatarUrl;
  final String aiName;
  final VoidCallback? onImageTap;
  final bool hasBackgroundImage;
  final IconData? weatherIcon;

  /// 小说模式下，把 AI 文本里的对白（引号包裹）着蓝色，旁白保持默认色。
  final bool novelMode;

  const _MessageBubble({
    required this.message,
    this.aiAvatarUrl,
    this.userAvatarUrl,
    this.aiName = 'AI',
    this.onImageTap,
    this.hasBackgroundImage = false,
    this.weatherIcon,
    this.novelMode = false,
  });

  // 抖音风格配色
  static const Color _douyinBlue = Color(0xFF2B7BF5);
  static const Color _douyinBlueDark = Color(0xFF4A90F7);
  static const Color _bubbleLight = Color(0xFFFFFFFF);
  static const Color _bubbleDark = Color(0xFF2C2C2C);
  static const Color _textOnBlue = Colors.white;
  static const Color _textOnWhite = Color(0xFF1A1A1A);
  static const Color _textOnDark = Color(0xFFE8EAED);
  static const double _avatarSize = 32.0;
  static const double _bubbleRadius = 12.0;
  static const double _hPad = 16.0;

  /// 匹配对白：中文弯引号「”…”」、直角引号「」/『』。
  /// 故意不匹配英文直双引号 “...”——AI 日常回复中引用/强调也会用它，误判率高。
  static final RegExp _dialogueRe =
      RegExp(r'”[^”]*”|「[^」]*」|『[^』]*』');

  /// 把一段文本按「引号内=对白（蓝色）/引号外=旁白（默认色）」拆成富文本片段。
  /// 若文本里没有任何对白引号，返回 null（外层回退到普通 Text）。
  static List<InlineSpan>? _buildDialogueSpans(
      String text, TextStyle baseStyle, Color dialogueColor) {
    final matches = _dialogueRe.allMatches(text).toList();
    if (matches.isEmpty) return null;
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final m in matches) {
      if (m.start > cursor) {
        spans.add(TextSpan(
            text: text.substring(cursor, m.start), style: baseStyle));
      }
      spans.add(TextSpan(
        text: text.substring(m.start, m.end),
        style: baseStyle.copyWith(
            color: dialogueColor, fontWeight: FontWeight.w600),
      ));
      cursor = m.end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor), style: baseStyle));
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isAI = message.isFromAI;
    final isRecalled =
        message.metadata?['recalled'] == true || message.content == '已撤回';
    final isTransfer = message.type == MessageType.system &&
        message.metadata?['type'] == 'red_packet';
    final isShopOrder = message.type == MessageType.system &&
        message.metadata?['type'] == 'shop_order';
    final brightness = Theme.of(context).brightness;
    final userBubbleColor =
        brightness == Brightness.dark ? _douyinBlueDark : _douyinBlue;
    final aiBubbleColor =
        brightness == Brightness.dark ? _bubbleDark : _bubbleLight;
    final userTextColor = _textOnBlue;
    final aiTextColor =
        brightness == Brightness.dark ? _textOnDark : _textOnWhite;
    final displayText = MessageSanitizer.removeRepeatedContent(message.content);
    final webSearchTrace = message.metadata?['webSearchTrace'];

    // 系统消息居中显示（如通话记录）
    if (message.isSystem) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: _hPad),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              message.content,
              style: TextStyle(
                color: Colors.grey.shade500,
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    if (isTransfer) {
      debugPrint(
          '[SYNC] _MessageBubble.build: transferStatus=${message.metadata?['transferStatus'] ?? 'pending'}, msgId=${message.id.substring(0, 8)}...');
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment:
          isAI ? CrossAxisAlignment.start : CrossAxisAlignment.end,
      children: [
        // ═══════════════════════════════════════════════════
        // 图片消息 - 像微信那样独立显示，不包裹在气泡里
        // ═══════════════════════════════════════════════════
        if (message.type == MessageType.image)
          Padding(
            padding: EdgeInsets.only(
              left: isAI ? _hPad : _hPad + _avatarSize + 8.0,
              right: isAI ? _hPad + _avatarSize + 8.0 : _hPad,
              top: 4,
              bottom: 2,
            ),
            child: Column(
              crossAxisAlignment:
                  isAI ? CrossAxisAlignment.start : CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                // AI图片：头像在上方左侧，图片在下方
                // 用户图片：头像在右侧，图片在左侧
                if (isAI) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildAvatar(isAI: true),
                        const SizedBox(width: 8),
                      ],
                    ),
                  ),
                ],
                GestureDetector(
                  onTap: onImageTap,
                  child: Hero(
                    tag: 'chat_image_${message.id}',
                    child: Container(
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.55,
                        maxHeight: 320,
                        minWidth: 120,
                        minHeight: 120,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(
                          File(message.content),
                          width: double.infinity,
                          height: double.infinity,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) =>
                              Container(
                            width: 200,
                            height: 200,
                            color: colorScheme.surfaceContainerHighest,
                            child: Center(
                              child: Icon(Icons.broken_image,
                                  size: 48, color: colorScheme.outline),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // 用户图片：头像在图片右下角
                if (!isAI) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        const SizedBox(width: 8),
                        _buildAvatar(isAI: false),
                      ],
                    ),
                  ),
                ],
                // 图片描述文字
                if (message.metadata?['text'] != null &&
                    message.metadata!['text'].toString().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      message.metadata!['text'].toString(),
                      style: TextStyle(
                        color: colorScheme.onSurface.withOpacity(0.6),
                        fontSize: 13,
                      ),
                    ),
                  ),
              ],
            ),
          )
        else ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: _hPad),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment:
                  isAI ? MainAxisAlignment.start : MainAxisAlignment.end,
              children: [
                if (isAI) ...[
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildAvatar(isAI: true),
                      if (weatherIcon != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Icon(weatherIcon,
                              size: 12,
                              color: colorScheme.onSurfaceVariant
                                  .withOpacity(0.5)),
                        ),
                    ],
                  ),
                  const SizedBox(width: 8),
                ],
                if (!isAI && message.status == MessageStatus.failed) ...[
                  Icon(Icons.error_outline, size: 16, color: Colors.red[400]),
                  const SizedBox(width: 4),
                ],
                if (isTransfer) ...[
                  TransferCard(
                    amount: double.tryParse(message.content) ?? 0.0,
                    message: message.metadata?['message'] as String?,
                    isFromUser: !isAI,
                    transferStatus:
                        message.metadata?['transferStatus'] as String? ??
                            'pending',
                    direction: message.metadata?['direction'] as String?,
                  ),
                ] else if (isShopOrder) ...[
                  OrderCard(
                    order: ShopOrder.fromMetadata(message.metadata!),
                    isFromUser: !isAI,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => BlocProvider.value(
                            value: context.read<ShopBloc>(),
                            child: const OrderTrackingScreen(),
                          ),
                        ),
                      );
                    },
                  ),
                ] else if (message.type == MessageType.voice)
                  Flexible(
                    child: _VoiceMessageWithTranscript(
                      audioPath: message.content,
                      isFromAI: isAI,
                      transcript: message.metadata?['text'] as String?,
                    ),
                  )
                else
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: isRecalled
                            ? (brightness == Brightness.dark
                                ? _bubbleDark
                                : const Color(0xFFF0F0F0))
                            : (isAI ? aiBubbleColor : userBubbleColor),
                        borderRadius: BorderRadius.circular(_bubbleRadius),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (message.metadata?['replyTo'] != null)
                            _buildReplyPreview(
                                context,
                                colorScheme,
                                message.metadata!['replyTo']
                                    as Map<String, dynamic>),
                          if (message.type == MessageType.sticker)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: message.metadata?['isBuiltinSticker'] ==
                                      true
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: Image.asset(
                                        BuiltinStickerService
                                            .getStickerAssetPath(
                                          message.metadata?['stickerFile']
                                                  as String? ??
                                              BuiltinStickerService
                                                      .findStickerById(
                                                          message.content)
                                                  ?.file ??
                                              '',
                                        ),
                                        width: 120,
                                        height: 120,
                                        fit: BoxFit.cover,
                                        errorBuilder:
                                            (context, error, stackTrace) =>
                                                Container(
                                          width: 120,
                                          height: 120,
                                          color: colorScheme
                                              .surfaceContainerHighest,
                                          child: Center(
                                            child: Icon(Icons.broken_image,
                                                size: 32,
                                                color: colorScheme.outline),
                                          ),
                                        ),
                                      ),
                                    )
                                  : message.metadata?['isImageSticker'] == true
                                      ? ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          child: Image.file(
                                            File(message.content),
                                            width: 120,
                                            height: 120,
                                            fit: BoxFit.cover,
                                            errorBuilder:
                                                (context, error, stackTrace) =>
                                                    Container(
                                              width: 120,
                                              height: 120,
                                              color: colorScheme
                                                  .surfaceContainerHighest,
                                              child: Center(
                                                child: Icon(Icons.broken_image,
                                                    size: 32,
                                                    color: colorScheme.outline),
                                              ),
                                            ),
                                          ),
                                        )
                                      : Text(
                                          message.content,
                                          style: const TextStyle(fontSize: 32),
                                        ),
                            )
                          else ...[
                            if (isAI && webSearchTrace is Map<String, dynamic>)
                              _WebSearchSection(trace: webSearchTrace),
                            if (isAI &&
                                !isRecalled &&
                                message.reasoning != null &&
                                message.reasoning!.isNotEmpty)
                              _ReasoningSection(reasoning: message.reasoning!),
                            if (isAI &&
                                !isRecalled &&
                                message.metadata?['aiEmotion'] != null)
                              _buildEmotionChip(context,
                                  message.metadata!['aiEmotion'] as String),
                            Builder(builder: (_) {
                              final baseColor = isRecalled
                                  ? (isAI
                                      ? aiTextColor.withOpacity(0.5)
                                      : userTextColor.withOpacity(0.5))
                                  : (isAI ? aiTextColor : userTextColor);
                              final baseStyle = TextStyle(
                                color: baseColor,
                                fontSize: 15,
                                height: 1.4,
                                fontStyle: isRecalled
                                    ? FontStyle.italic
                                    : FontStyle.normal,
                              );
                              // 小说模式：AI 的对白（引号内）着蓝色，旁白保持默认。
                              if (!isRecalled && isAI && novelMode) {
                                final dialogueColor =
                                    brightness == Brightness.dark
                                        ? _douyinBlueDark
                                        : _douyinBlue;
                                final spans = _buildDialogueSpans(
                                    displayText, baseStyle, dialogueColor);
                                if (spans != null) {
                                  return Text.rich(TextSpan(children: spans));
                                }
                              }
                              return Text(
                                isRecalled ? '已撤回' : displayText,
                                style: baseStyle,
                              );
                            }),
                          ],
                        ],
                      ),
                    ),
                  ),
                if (!isAI) ...[
                  const SizedBox(width: 8),
                  _buildAvatar(isAI: false),
                ],
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.only(
              left: isAI ? _hPad + _avatarSize + 8.0 : 0,
              right: isAI ? 0 : _hPad + _avatarSize + 8.0,
              top: 2,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  DateFormat('HH:mm').format(message.createdAt),
                  style: TextStyle(
                    fontSize: 11,
                    color: isRecalled
                        ? colorScheme.onSurfaceVariant.withOpacity(0.5)
                        : colorScheme.onSurface.withOpacity(0.4),
                  ),
                ),
                if (!isAI) ...[
                  const SizedBox(width: 4),
                  _buildStatusIcon(message.status, colorScheme),
                ],
              ],
            ),
          ),
        ], // else end
      ],
    );
  }

  Widget _buildStatusIcon(MessageStatus status, ColorScheme colorScheme) {
    switch (status) {
      case MessageStatus.sending:
        return SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: colorScheme.onSurface.withOpacity(0.3)));
      case MessageStatus.sent:
        return Text('未读',
            style: TextStyle(
                fontSize: 10, color: colorScheme.onSurface.withOpacity(0.4)));
      case MessageStatus.delivered:
        return Text('未读',
            style: TextStyle(
                fontSize: 10, color: colorScheme.onSurface.withOpacity(0.4)));
      case MessageStatus.failed:
        return Text('未读',
            style: TextStyle(
                fontSize: 10, color: colorScheme.onSurface.withOpacity(0.4)));
      case MessageStatus.read:
        return Text('已读',
            style: TextStyle(
                fontSize: 10,
                color: Colors.blue[400],
                fontWeight: FontWeight.w500));
      case MessageStatus.error:
      case MessageStatus.cancelled:
        return Text('失败',
            style: TextStyle(
                fontSize: 10, color: colorScheme.error.withOpacity(0.6)));
    }
  }

  /// AI 消息上的情绪小图标（从 metadata 读取持久化情绪）
  Widget _buildEmotionChip(BuildContext context, String emotionName) {
    final emotion = EmotionType.values
        .where((e) => e.name == emotionName)
        .firstOrNull;
    if (emotion == null || emotion == EmotionType.calm) {
      return const SizedBox.shrink();
    }
    final brightness = Theme.of(context).brightness;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(emotion.icon, size: 13, color: emotion.color),
          const SizedBox(width: 3),
          Text(
            emotion.label,
            style: TextStyle(
              fontSize: 11,
              color: brightness == Brightness.dark
                  ? emotion.color.withValues(alpha: 0.8)
                  : emotion.color.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReplyPreview(BuildContext context, ColorScheme colorScheme,
      Map<String, dynamic> replyTo) {
    final senderName = replyTo['senderName'] as String? ?? '';
    final contentPreview = replyTo['contentPreview'] as String? ?? '';
    final isAI = message.isFromAI;
    final brightness = Theme.of(context).brightness;
    final replyBg = isAI
        ? (brightness == Brightness.dark
            ? Colors.white.withOpacity(0.08)
            : Colors.black.withOpacity(0.05))
        : Colors.white.withOpacity(0.15);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: BoxDecoration(
        color: replyBg,
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(
              color: isAI
                  ? colorScheme.primary.withOpacity(0.5)
                  : Colors.white.withOpacity(0.5),
              width: 3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            senderName,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isAI
                  ? colorScheme.primary.withOpacity(0.8)
                  : Colors.white.withOpacity(0.8),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            contentPreview,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: isAI
                  ? colorScheme.onSurface.withOpacity(0.65)
                  : Colors.white.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar({required bool isAI}) {
    final avatarUrl = isAI ? aiAvatarUrl : userAvatarUrl;

    return Container(
      width: _avatarSize,
      height: _avatarSize,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
      ),
      child: ClipOval(
        child: _buildAvatarImage(avatarUrl, _avatarSize, isAI),
      ),
    );
  }

  Widget _buildAvatarImage(String? avatarUrl, double size, bool isAI) {
    final image = AvatarResolver.imageWidget(
      avatarUrl,
      width: size,
      height: size,
      onError: () => _buildDefaultAvatar(isAI: isAI, size: size),
    );
    if (image != null) return image;
    return _buildDefaultAvatar(isAI: isAI, size: size);
  }

  Widget _buildDefaultAvatar({required bool isAI, required double size}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isAI ? const Color(0xFFE8E4EC) : const Color(0xFFD2E3FC),
      ),
      child: Icon(
        isAI ? Icons.smart_toy_outlined : Icons.person_outline,
        size: size * 0.6,
        color: isAI ? const Color(0xFF9C27B0) : const Color(0xFF1A73E8),
      ),
    );
  }
}

class _StickerPickerSheet extends StatefulWidget {
  final Function(String) onEmojiSelected;
  final Function(String) onStickerSelected;
  final Function(String)? onImageStickerSelected;
  final LocalStorageRepository storage;

  const _StickerPickerSheet({
    required this.onEmojiSelected,
    required this.onStickerSelected,
    this.onImageStickerSelected,
    required this.storage,
  });

  @override
  State<_StickerPickerSheet> createState() => _StickerPickerSheetState();
}

class _StickerPickerSheetState extends State<_StickerPickerSheet>
    with SingleTickerProviderStateMixin {
  BuiltinStickerPack? _pack;
  List<StickerPack> _customPacks = [];
  bool _loading = true;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadStickers();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadStickers() async {
    try {
      final pack = await BuiltinStickerService.loadDefaultPack();
      final customPacks = await widget.storage.getAllStickerPacks();
      if (mounted) {
        setState(() {
          _pack = pack;
          _customPacks = customPacks;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _onDeleteSticker(StickerItem sticker) async {
    // Find which pack this sticker belongs to
    String? packId;
    for (final pack in _customPacks) {
      if (pack.stickers.any((s) => s.id == sticker.id)) {
        packId = pack.id;
        break;
      }
    }
    if (packId == null) return;

    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('删除此表情', style: TextStyle(color: Colors.red)),
              onTap: () => Navigator.pop(ctx, 'delete_one'),
            ),
            ListTile(
              leading:
                  const Icon(Icons.delete_sweep_outlined, color: Colors.red),
              title: const Text('删除整个表情包', style: TextStyle(color: Colors.red)),
              onTap: () => Navigator.pop(ctx, 'delete_pack'),
            ),
            const Divider(height: 1),
            ListTile(
              title: const Text('取消', textAlign: TextAlign.center),
              onTap: () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
    );

    if (action == null || !mounted) return;

    final service = StickerPackService(widget.storage);
    if (action == 'delete_one') {
      await service.removeStickerFromPack(
          packId: packId, stickerId: sticker.id);
      // If pack is now empty, delete it entirely
      final pack = await service.getStickerPack(packId);
      if (pack != null && pack.stickers.isEmpty) {
        await service.deleteStickerPack(packId);
      }
    } else if (action == 'delete_pack') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('确认删除'),
          content: const Text('将删除该表情包中的所有表情，且无法恢复。'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('删除', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );
      if (confirmed == true) {
        await service.deleteStickerPack(packId);
      }
    }

    await _loadStickers();
  }

  Future<void> _addCustomSticker() async {
    try {
      final picker = ImagePicker();
      final images = await picker.pickMultiImage(imageQuality: 85);
      if (images.isEmpty) return;

      final service = StickerPackService(widget.storage);

      // 创建新表情包或添加到最近的自定义包
      StickerPack targetPack;
      if (_customPacks.isEmpty) {
        targetPack = await service.createStickerPack(
          name: '我的表情包',
          initialImagePaths: images.map((f) => f.path).toList(),
        );
      } else {
        targetPack = _customPacks.last;
        for (final img in images) {
          await service.addStickerToPack(
            packId: targetPack.id,
            imagePath: img.path,
          );
        }
        targetPack = (await service.getStickerPack(targetPack.id))!;
      }

      await _loadStickers();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已添加${images.length} 个表情'),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('添加失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Tab 栏 + 添加按钮
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: TabBar(
                    controller: _tabController,
                    labelColor: colorScheme.primary,
                    unselectedLabelColor:
                        colorScheme.onSurface.withOpacity(0.5),
                    indicatorColor: colorScheme.primary,
                    indicatorSize: TabBarIndicatorSize.label,
                    labelStyle: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600),
                    unselectedLabelStyle: const TextStyle(fontSize: 14),
                    dividerHeight: 0,
                    tabs: const [
                      Tab(text: '默认表情'),
                      Tab(text: '我的表情'),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.add_circle_outline,
                      color: colorScheme.primary, size: 22),
                  tooltip: '添加自定义表情',
                  onPressed: _addCustomSticker,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (_loading)
            const Expanded(
              child: Center(child: CircularProgressIndicator()),
            )
          else
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // 默认表情 Tab
                  _buildBuiltinTab(),
                  // 自定义表情 Tab
                  _buildCustomTab(),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBuiltinTab() {
    if (_pack == null || _pack!.stickers.isEmpty) {
      return const Center(child: Text('暂无默认表情'));
    }
    final cs = Theme.of(context).colorScheme;
    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 1,
      ),
      itemCount: _pack!.stickers.length,
      itemBuilder: (context, index) {
        final sticker = _pack!.stickers[index];
        return GestureDetector(
          onTap: () => widget.onStickerSelected(sticker.id),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: cs.surfaceContainerLow,
            ),
            clipBehavior: Clip.antiAlias,
            child: Image.asset(
              BuiltinStickerService.getStickerAssetPath(sticker.file),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Center(
                child: Icon(Icons.broken_image, color: cs.outline),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCustomTab() {
    final cs = Theme.of(context).colorScheme;
    if (_customPacks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.face_retouching_natural,
                size: 48, color: cs.outlineVariant),
            const SizedBox(height: 12),
            Text('还没有自定义表情',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14)),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _addCustomSticker,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('从相册添加'),
            ),
          ],
        ),
      );
    }

    // 收集所有自定义表情
    final allStickers = <StickerItem>[];
    for (final pack in _customPacks) {
      allStickers.addAll(pack.stickers);
    }

    if (allStickers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.face_retouching_natural,
                size: 48, color: cs.outlineVariant),
            const SizedBox(height: 12),
            Text('表情包是空的',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14)),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _addCustomSticker,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('添加表情'),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 1,
      ),
      itemCount: allStickers.length,
      itemBuilder: (context, index) {
        final sticker = allStickers[index];
        return GestureDetector(
          onTap: () => widget.onImageStickerSelected?.call(sticker.imagePath),
          onLongPress: () => _onDeleteSticker(sticker),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: cs.surfaceContainerLow,
            ),
            clipBehavior: Clip.antiAlias,
            child: Image.file(
              File(sticker.imagePath),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Center(
                child: Icon(Icons.broken_image, color: cs.outline),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 流式输出气泡 - 实时显示AI正在生成的文字，思考内容用倾斜字体
class _StreamingBubble extends StatelessWidget {
  final String text;
  final String? reasoning;
  final String? avatarUrl;
  final String name;
  final bool novelMode;

  const _StreamingBubble({
    required this.text,
    this.reasoning,
    this.avatarUrl,
    this.name = 'AI',
    this.novelMode = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // UI 兜底清洗：先提取思考标签，再清理正文，避免 <think> 泄漏到气泡外
    final cleanedParts = AIService.cleanForStreamDisplay(text);
    final cleanText = MessageSanitizer.sanitizeStream(cleanedParts[0]);
    final thinkExtracted = cleanedParts.length > 1 ? cleanedParts[1] : '';

    final cleanReasoningRaw = reasoning != null && reasoning!.isNotEmpty
        ? MessageSanitizer.sanitizeStream(reasoning!)
        : '';
    // 合并 API reasoning_content 和从 content 中提取的<think>>内容
    final allReasoning = [cleanReasoningRaw, thinkExtracted]
        .where((r) => r.isNotEmpty)
        .join('\n');
    final cleanReasoning = allReasoning.isNotEmpty ? allReasoning : null;
    final hasReasoning = cleanReasoning != null && cleanReasoning.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: colorScheme.primary.withOpacity(0.1),
            backgroundImage: AvatarResolver.imageProvider(avatarUrl),
            child: AvatarResolver.imageProvider(avatarUrl) == null
                ? Icon(Icons.auto_awesome, size: 18, color: colorScheme.primary)
                : null,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (hasReasoning) ...[
                    Text(
                      cleanReasoning!,
                      style: TextStyle(
                        color: colorScheme.onSurface.withOpacity(0.4),
                        fontSize: 13,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],
                  if (cleanText.isNotEmpty) ...[
                    Builder(builder: (ctx) {
                      final brightness = Theme.of(ctx).brightness;
                      final baseStyle = TextStyle(
                        color: colorScheme.onSurface,
                        fontSize: 15,
                      );
                      if (novelMode) {
                        final dialogueColor = brightness == Brightness.dark
                            ? _MessageBubble._douyinBlueDark
                            : _MessageBubble._douyinBlue;
                        final spans = _MessageBubble._buildDialogueSpans(
                            cleanText, baseStyle, dialogueColor);
                        if (spans != null) {
                          return Text.rich(TextSpan(children: spans));
                        }
                      }
                      return SelectableText(cleanText, style: baseStyle);
                    }),
                  ],
                  if (!hasReasoning && text.isEmpty) TypingIndicator(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 推理/思考内容折叠区域
class _ReasoningSection extends StatefulWidget {
  final String reasoning;

  const _ReasoningSection({required this.reasoning});

  @override
  State<_ReasoningSection> createState() => _ReasoningSectionState();
}

class _ReasoningSectionState extends State<_ReasoningSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          behavior: HitTestBehavior.opaque,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _expanded ? Icons.expand_less : Icons.expand_more,
                size: 16,
                color: colorScheme.onSurface.withOpacity(0.4),
              ),
              const SizedBox(width: 2),
              Text(
                '思考过程',
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurface.withOpacity(0.4),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        if (_expanded)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 6),
            child: Text(
              widget.reasoning,
              style: TextStyle(
                color: colorScheme.onSurface.withOpacity(0.45),
                fontSize: 13,
                fontStyle: FontStyle.italic,
                height: 1.4,
              ),
            ),
          ),
        if (!_expanded) const SizedBox(height: 4),
      ],
    );
  }
}

/// 语音消息 + 转文字切换
class _WebSearchSection extends StatefulWidget {
  final Map<String, dynamic> trace;

  const _WebSearchSection({required this.trace});

  @override
  State<_WebSearchSection> createState() => _WebSearchSectionState();
}

class _WebSearchSectionState extends State<_WebSearchSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final query = widget.trace['query'] as String? ?? '';
    final rawResults = widget.trace['results'];
    final results = rawResults is List ? rawResults : const [];
    final summary = results.isEmpty
        ? '已搜索：$query，未获得可用结果'
        : '已搜索：$query，共${results.length} 个结果';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          behavior: HitTestBehavior.opaque,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _expanded ? Icons.expand_less : Icons.expand_more,
                size: 16,
                color: colorScheme.primary.withOpacity(0.75),
              ),
              const SizedBox(width: 2),
              Icon(
                Icons.public_rounded,
                size: 14,
                color: colorScheme.primary.withOpacity(0.75),
              ),
              const SizedBox(width: 4),
              Text(
                '联网搜索',
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.primary.withOpacity(0.78),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        if (_expanded)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  summary,
                  style: TextStyle(
                    color: colorScheme.onSurface.withOpacity(0.55),
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 4),
                for (final item in results.take(5))
                  if (item is Map)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        _formatSearchResult(item),
                        style: TextStyle(
                          color: colorScheme.onSurface.withOpacity(0.50),
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ),
              ],
            ),
          ),
        if (!_expanded) const SizedBox(height: 4),
      ],
    );
  }

  String _formatSearchResult(Map item) {
    final title = item['title']?.toString() ?? '无标题';
    final url = item['url']?.toString() ?? '';
    final snippet = item['snippet']?.toString() ?? '';
    final text = snippet.isEmpty ? title : '$title\n$snippet';
    return url.isEmpty ? text : '$text\n$url';
  }
}

class _VoiceMessageWithTranscript extends StatefulWidget {
  final String audioPath;
  final bool isFromAI;
  final String? transcript;

  const _VoiceMessageWithTranscript({
    required this.audioPath,
    required this.isFromAI,
    this.transcript,
  });

  @override
  State<_VoiceMessageWithTranscript> createState() =>
      _VoiceMessageWithTranscriptState();
}

class _VoiceMessageWithTranscriptState
    extends State<_VoiceMessageWithTranscript> {
  bool _showTranscript = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        VoiceMessageBubble(
          audioPath: widget.audioPath,
          isFromAI: widget.isFromAI,
        ),
        if (widget.transcript != null && widget.transcript!.isNotEmpty)
          GestureDetector(
            onTap: () => setState(() => _showTranscript = !_showTranscript),
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _showTranscript
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 16,
                    color: colorScheme.onSurfaceVariant.withOpacity(0.6),
                  ),
                  const SizedBox(width: 2),
                  Text(
                    _showTranscript ? '收起文字' : '转文字',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (_showTranscript &&
            widget.transcript != null &&
            widget.transcript!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              widget.transcript!,
              style: TextStyle(
                color: colorScheme.onSurface,
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ),
      ],
    );
  }
}
