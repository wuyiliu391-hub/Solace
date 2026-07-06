import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../blocs/group_chat/group_chat_bloc.dart';
import '../../blocs/group_chat/group_chat_event.dart';
import '../../blocs/group_chat/group_chat_state.dart';
import '../../models/group_chat_session.dart';
import '../../models/chat_message.dart';
import '../../repositories/local_storage_repository.dart';
import '../../widgets/typing_indicator.dart';
import '../../widgets/mode_control_mini_panel.dart';
import 'package:flutter/services.dart';
import '../../utils/message_sanitizer.dart';
import 'group_chat_settings_screen.dart';

class GroupChatDetailScreen extends StatefulWidget {
  final GroupChatSession session;

  const GroupChatDetailScreen({super.key, required this.session});

  @override
  State<GroupChatDetailScreen> createState() => _GroupChatDetailScreenState();
}

class _GroupChatDetailScreenState extends State<GroupChatDetailScreen>
    with TickerProviderStateMixin {
  final TextEditingController _messageController = TextEditingController();
  final FocusNode _messageFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  static const List<Color> _roleColors = [
    Color(0xFFE3F2FD),
    Color(0xFFFCE4EC),
    Color(0xFFE8F5E9),
    Color(0xFFFFF3E0),
    Color(0xFFF3E5F5),
    Color(0xFFE0F7FA),
  ];

  // P7: 深色模式下使用更深的背景色，避免浅色贴纸在暗色主题中过亮
  List<Color> _roleColorsForTheme(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (!isDark) return _roleColors;
    return const [
      Color(0xFF1A2733), // 深蓝
      Color(0xFF2A1A20), // 深粉
      Color(0xFF1A2A1E), // 深绿
      Color(0xFF2A2218), // 深橙
      Color(0xFF221A2A), // 深紫
      Color(0xFF1A2A28), // 深青
    ];
  }

  List<ChatMessage> _cachedMessages = [];
  late AnimationController _typingBlinkController;
  OverlayEntry? _mentionOverlayEntry;
  bool _isLoadingMore = false;
  bool _hasMoreMessages = true;
  static const int _messagesPerPage = 50;
  late GroupChatSession _currentSession;
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
  final ValueNotifier<bool> _modePanelVisible = ValueNotifier<bool>(false);

  @override
  void initState() {
    const MethodChannel('com.solace.solace/volume_key')
        .setMethodCallHandler((call) async {
      if (call.method == 'volume_up')
        _modePanelVisible.value = true;
      else if (call.method == 'volume_down') _modePanelVisible.value = false;
    });
    super.initState();
    _currentSession = widget.session;
    _typingBlinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _scrollController.addListener(_onScroll);
    _loadMessages();
    _checkFirstTimeGuide();
  }

  Future<void> _checkFirstTimeGuide() async {
    final prefs = await SharedPreferences.getInstance();
    final hasShownGuide = prefs.getBool('group_chat_guide_shown') ?? false;
    if (!hasShownGuide && mounted) {
      await prefs.setBool('group_chat_guide_shown', true);
      _showGuideDialog();
    }
  }

  void _showGuideDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const GroupChatGuideDialog(),
    );
  }

  Future<void> _openSettings() async {
    final groupChatBloc = context.read<GroupChatBloc>();
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => BlocProvider.value(
          value: groupChatBloc,
          child: GroupChatSettingsScreen(session: _currentSession),
        ),
      ),
    );

    // 如果设置有更改，刷新会话数据
    if (result == true && mounted) {
      await _reloadSession();
    }
  }

  void _refreshMessages() {
    _cachedMessages.clear();
    _hasMoreMessages = true;
    _loadMessages();
    _reloadSession();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('对话已刷新'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  /// 重新加载会话数据（用于更新头像等）
  Future<void> _reloadSession() async {
    try {
      final storage = RepositoryProvider.of<LocalStorageRepository>(context);
      final updatedSession =
          await storage.getGroupChatSession(widget.session.id);
      if (updatedSession != null && mounted) {
        setState(() {
          _currentSession = updatedSession;
        });
      }
    } catch (e) {
      debugPrint('重新加载会话失败: $e');
    }
  }

  void _loadMessages() {
    context.read<GroupChatBloc>().add(GroupChatLoadMessages(widget.session.id));
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_isLoadingMore || !_hasMoreMessages) return;

    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;

    // 当滚动到底部（因为是 reverse: true，所以是 maxScroll）时加载更多
    if (currentScroll >= maxScroll - 100) {
      _loadMoreMessages();
    }
  }

  Future<void> _loadMoreMessages() async {
    if (_isLoadingMore || !_hasMoreMessages) return;

    setState(() => _isLoadingMore = true);

    try {
      final storage = RepositoryProvider.of<LocalStorageRepository>(context);
      final offset = _cachedMessages.length;
      final moreMessages = await storage.getChatMessages(
        _currentSession.id,
        limit: _messagesPerPage,
        offset: offset,
      );

      if (moreMessages.isEmpty) {
        setState(() => _hasMoreMessages = false);
      } else {
        setState(() {
          _cachedMessages.addAll(moreMessages);
        });
      }
    } catch (e) {
      debugPrint('加载更多消息失败: $e');
    } finally {
      setState(() => _isLoadingMore = false);
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _messageFocusNode.dispose();
    _modePanelVisible.dispose();
    _scrollController.dispose();
    _typingBlinkController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _removeMentionOverlay();
    super.dispose();
  }

  void _removeMentionOverlay() {
    _mentionOverlayEntry?.remove();
    _mentionOverlayEntry = null;
  }

  Color _getCharacterColor(String senderId) {
    if (!senderId.startsWith('ai_')) return Colors.transparent;
    final characterId = senderId.replaceFirst('ai_', '');
    final index = widget.session.participantIds.indexOf(characterId);
    final colors = _roleColorsForTheme(context);
    if (index < 0) return colors[0];
    return colors[index % colors.length];
  }

  String? _getCharacterAvatar(String senderId) {
    if (!senderId.startsWith('ai_')) return null;
    final characterId = senderId.replaceFirst('ai_', '');
    final index = _currentSession.participantIds.indexOf(characterId);
    if (index < 0) return null;
    if (index < _currentSession.participantAvatars.length) {
      return _currentSession.participantAvatars[index];
    }
    return null;
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final userId =
        (context.read<AuthBloc>().state as AuthAuthenticated).user.id;
    context.read<GroupChatBloc>().add(GroupChatSendMessage(
          groupChatId: _currentSession.id,
          userId: userId,
          content: text,
        ));

    _messageController.clear();
    _removeMentionOverlay();
  }

  void _continueObserve() {
    if (_currentSession.participantIds.isEmpty) return;
    final userId =
        (context.read<AuthBloc>().state as AuthAuthenticated).user.id;
    final firstCharacterId = _currentSession.participantIds.first;
    context.read<GroupChatBloc>().add(GroupChatForceReply(
          groupChatId: _currentSession.id,
          userId: userId,
          characterId: firstCharacterId,
          observeContinue: true,
        ));
  }

  void _forceReply(String characterId) {
    final userId =
        (context.read<AuthBloc>().state as AuthAuthenticated).user.id;
    context.read<GroupChatBloc>().add(GroupChatForceReply(
          groupChatId: _currentSession.id,
          userId: userId,
          characterId: characterId,
        ));
  }

  void _showCharacterActionSheet(int index) {
    final characterId = _currentSession.participantIds[index];
    final name = _currentSession.participantNames[index];
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                '点击后会邀请 TA 在当前酒馆里回应。',
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.record_voice_over_rounded),
                title: const Text('让 TA 回应'),
                onTap: () {
                  Navigator.pop(ctx);
                  _forceReply(characterId);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _onTextChanged(String text) {
    final cursorPos = _messageController.selection.baseOffset;
    if (cursorPos <= 0) {
      _removeMentionOverlay();
      return;
    }

    final beforeCursor = text.substring(0, cursorPos);
    final mentionMatch = RegExp(r'@(\S{0,20})$').firstMatch(beforeCursor);

    if (mentionMatch != null) {
      _showMentionPopup(mentionMatch.group(1) ?? '');
    } else {
      _removeMentionOverlay();
    }
  }

  void _showMentionPopup(String query) {
    _removeMentionOverlay();

    final participants = _currentSession.participantNames;
    final filtered = <MapEntry<int, String>>[];
    for (int i = 0; i < participants.length; i++) {
      if (query.isEmpty || participants[i].contains(query)) {
        filtered.add(MapEntry(i, participants[i]));
      }
    }

    if (filtered.isEmpty) return;

    final colorScheme = Theme.of(context).colorScheme;

    _mentionOverlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        bottom: MediaQuery.of(context).viewInsets.bottom + 70,
        left: 16,
        right: 16,
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            constraints: const BoxConstraints(maxHeight: 200),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: filtered.length,
              itemBuilder: (context, index) {
                final entry = filtered[index];
                final avatar =
                    entry.key < _currentSession.participantAvatars.length
                        ? _currentSession.participantAvatars[entry.key]
                        : null;
                return ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 16,
                    backgroundColor:
                        _roleColorsForTheme(context)[entry.key % _roleColorsForTheme(context).length],
                    backgroundImage:
                        avatar != null ? FileImage(File(avatar)) : null,
                    child: avatar == null
                        ? Text(
                            entry.value.characters.first,
                            style: const TextStyle(fontSize: 14),
                          )
                        : null,
                  ),
                  title:
                      Text(entry.value, style: const TextStyle(fontSize: 14)),
                  onTap: () => _selectMention(entry.value),
                );
              },
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_mentionOverlayEntry!);
  }

  void _selectMention(String name) {
    final text = _messageController.text;
    final cursorPos = _messageController.selection.baseOffset;
    final beforeCursor = text.substring(0, cursorPos);
    final afterCursor =
        cursorPos < text.length ? text.substring(cursorPos) : '';

    final mentionStart = beforeCursor.lastIndexOf('@');
    if (mentionStart >= 0) {
      final newText =
          '${beforeCursor.substring(0, mentionStart)}@$name $afterCursor';
      _messageController.text = newText;
      _messageController.selection = TextSelection.fromPosition(
        TextPosition(offset: mentionStart + name.length + 2),
      );
    }

    _removeMentionOverlay();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: _isSearching
          ? _buildSearchAppBar(colorScheme)
          : _buildAppBar(colorScheme),
      body: _isSearching && _searchQuery.isNotEmpty
          ? _buildSearchResults(colorScheme)
          : BlocConsumer<GroupChatBloc, GroupChatState>(
              listenWhen: (previous, current) =>
                  current is GroupChatError ||
                  current is GroupChatMessagesLoaded ||
                  current is GroupChatAITyping ||
                  current is GroupChatAIStreaming,
              listener: (context, state) {
                if (state is GroupChatError) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(state.message),
                      backgroundColor: colorScheme.error,
                    ),
                  );
                }
                if (state is GroupChatAITyping &&
                    state.characterName.isNotEmpty) {
                  if (!_typingBlinkController.isAnimating) {
                    _typingBlinkController.repeat(reverse: true);
                  }
                }
                if (state is GroupChatAIStreaming) {
                  if (!_typingBlinkController.isAnimating) {
                    _typingBlinkController.repeat(reverse: true);
                  }
                  _scrollToBottom();
                }
                if (state is GroupChatMessagesLoaded) {
                  _typingBlinkController.stop();
                  _typingBlinkController.value = 0.0;
                  _scrollToBottom();
                }
              },
              buildWhen: (previous, current) =>
                  current is GroupChatMessagesLoaded ||
                  current is GroupChatLoading ||
                  current is GroupChatAITyping ||
                  current is GroupChatAIStreaming,
              builder: (context, state) {
                if (state is GroupChatMessagesLoaded) {
                  _cachedMessages = state.messages;
                }
                final isStreaming = state is GroupChatAIStreaming;
                final streamingText = isStreaming ? state.streamingText : '';
                final streamingReasoning = isStreaming ? state.reasoning : '';
                final typingName = state is GroupChatAITyping
                    ? state.characterName
                    : (isStreaming ? state.characterName : null);
                final isTyping =
                    (typingName != null && typingName.isNotEmpty) ||
                        isStreaming;

                return Stack(
                  children: [
                    Column(
                      children: [
                        _buildTavernInfoBar(colorScheme),
                        _buildCharacterStatusBar(
                          colorScheme,
                          typingName: typingName,
                          isTyping: isTyping,
                        ),
                        Expanded(
                          child: _buildMessageList(
                            colorScheme,
                            isTyping: isTyping,
                            streamingText: isStreaming ? streamingText : null,
                            streamingReasoning:
                                isStreaming ? streamingReasoning : null,
                          ),
                        ),
                        _buildInputArea(
                          colorScheme,
                          isAiTyping: state is GroupChatAITyping,
                        ),
                      ],
                    ),
                    ModeControlMiniPanel(visible: _modePanelVisible),
                  ],
                );
              },
            ),
    );
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    });
  }

  PreferredSizeWidget _buildAppBar(ColorScheme colorScheme) {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => Navigator.pop(context),
      ),
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.local_bar, size: 20, color: colorScheme.primary),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              _currentSession.name,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ],
      ),
      centerTitle: true,
      elevation: 0,
      actions: [
        IconButton(
          icon: const Icon(Icons.search),
          tooltip: '搜索聊天记录',
          onPressed: () {
            setState(() => _isSearching = true);
            _searchFocusNode.requestFocus();
          },
        ),
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: _refreshMessages,
          tooltip: '刷新对话',
        ),
        IconButton(
          icon: const Icon(Icons.help_outline),
          onPressed: _showGuideDialog,
          tooltip: '玩法说明',
        ),
        IconButton(
          icon: const Icon(Icons.settings_outlined),
          onPressed: _openSettings,
          tooltip: '酒馆设置',
        ),
      ],
    );
  }

  Widget _buildTavernInfoBar(ColorScheme colorScheme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          bottom:
              BorderSide(color: colorScheme.outlineVariant.withOpacity(0.25)),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.local_bar_rounded, size: 16, color: colorScheme.primary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '${_currentSession.tavernMode.label} · ${_currentSession.immersion.label} · ${_currentSession.participantIds.length} 位角色',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            _currentSession.interactionFrequency.label,
            style: TextStyle(
              color: colorScheme.primary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCharacterStatusBar(ColorScheme colorScheme,
      {String? typingName, required bool isTyping}) {
    return Container(
      height: 72,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
        border: Border(
          bottom:
              BorderSide(color: colorScheme.outlineVariant.withOpacity(0.3)),
        ),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        itemCount: _currentSession.participantIds.length,
        itemBuilder: (context, index) {
          final name = _currentSession.participantNames[index];
          final avatar = index < _currentSession.participantAvatars.length
              ? _currentSession.participantAvatars[index]
              : null;
          final isTyping =
              typingName != null && typingName == name && typingName.isNotEmpty;
          final color = _roleColorsForTheme(context)[index % _roleColorsForTheme(context).length];

          return GestureDetector(
            onTap: () => _showCharacterActionSheet(index),
            child: Container(
              width: 60,
              margin: const EdgeInsets.only(right: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 头像区域 - 带粉色呼吸灯边框
                  AnimatedBuilder(
                    animation: _typingBlinkController,
                    builder: (context, child) {
                      // 呼吸灯效果：只在输入中时显示
                      final glowOpacity = isTyping
                          ? 0.4 + 0.6 * _typingBlinkController.value
                          : 0.0;
                      final glowSpread = isTyping
                          ? 2.0 + 4.0 * _typingBlinkController.value
                          : 0.0;

                      return Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          // 粉色呼吸灯边框
                          boxShadow: isTyping
                              ? [
                                  BoxShadow(
                                    color: Colors.pink.withOpacity(glowOpacity),
                                    blurRadius: glowSpread * 2,
                                    spreadRadius: glowSpread,
                                  ),
                                  BoxShadow(
                                    color: Colors.pinkAccent
                                        .withOpacity(glowOpacity * 0.5),
                                    blurRadius: glowSpread * 4,
                                    spreadRadius: glowSpread * 0.5,
                                  ),
                                ]
                              : null,
                          border: isTyping
                              ? Border.all(
                                  color: Colors.pink.withOpacity(
                                      0.6 + 0.4 * _typingBlinkController.value),
                                  width: 2,
                                )
                              : null,
                        ),
                        child: Center(
                          child: CircleAvatar(
                            radius: 16,
                            backgroundColor: color,
                            backgroundImage:
                                avatar != null ? FileImage(File(avatar)) : null,
                            child: avatar == null
                                ? Text(
                                    name.characters.first,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: colorScheme.onSurface,
                                    ),
                                  )
                                : null,
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 3),
                  SizedBox(
                    height: 24,
                    child: Text(
                      name,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 10,
                        color: isTyping
                            ? Colors.pink
                            : colorScheme.onSurfaceVariant,
                        fontWeight:
                            isTyping ? FontWeight.w600 : FontWeight.normal,
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

  Widget _buildMessageList(ColorScheme colorScheme,
      {required bool isTyping,
      String? streamingText,
      String? streamingReasoning}) {
    final isTypingActive = isTyping;
    final isStreaming = streamingText != null;

    if (_cachedMessages.isEmpty && !isTypingActive && !isStreaming) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.forum_outlined,
                size: 48, color: colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              '开始聊天吧',
              style:
                  TextStyle(fontSize: 14, color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    final totalItems = _cachedMessages.length +
        (isTypingActive || isStreaming ? 1 : 0) +
        (_hasMoreMessages ? 1 : 0);

    return ListView.builder(
      controller: _scrollController,
      reverse: true,
      physics:
          const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: totalItems,
      itemBuilder: (context, index) {
        // 最后一个位置显示加载更多提示（因为是 reverse: true，所以是底部）
        if (_hasMoreMessages && index == totalItems - 1) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: _isLoadingMore
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      '上滑加载更多历史消息',
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurface.withOpacity(0.4),
                      ),
                    ),
            ),
          );
        }

        // 流式输出气泡（reverse: true，index 0 在最底部）
        if (isStreaming && index == 0) {
          if (streamingText!.isEmpty) {
            return _buildGroupTypingIndicator();
          }
          // UI 兜底清洗
          final cleanStreamingText =
              MessageSanitizer.sanitizeStream(streamingText!);
          final cleanStreamingReasoning =
              streamingReasoning != null && streamingReasoning.isNotEmpty
                  ? MessageSanitizer.sanitizeStream(streamingReasoning)
                  : null;
          return Align(
            alignment: Alignment.centerLeft,
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.75),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (cleanStreamingReasoning != null &&
                      cleanStreamingReasoning.isNotEmpty)
                    Text(
                      cleanStreamingReasoning,
                      style: TextStyle(
                        color: colorScheme.onSurface.withOpacity(0.4),
                        fontSize: 13,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  if (cleanStreamingReasoning != null &&
                      cleanStreamingReasoning.isNotEmpty)
                    const SizedBox(height: 6),
                  if (cleanStreamingText.isNotEmpty)
                    SelectableText(
                      cleanStreamingText,
                      style:
                          TextStyle(color: colorScheme.onSurface, fontSize: 15),
                    ),
                  if ((cleanStreamingReasoning == null ||
                          cleanStreamingReasoning.isEmpty) &&
                      cleanStreamingText.isEmpty)
                    const TypingIndicator(),
                ],
              ),
            ),
          );
        }

        // 第一个位置显示输入指示器（因为 reverse: true）
        if (isTypingActive && index == 0) {
          return _buildGroupTypingIndicator();
        }
        final messageIndex = isTypingActive ? index - 1 : index;
        final message = _cachedMessages[messageIndex];
        return _buildMessageBubble(message, colorScheme);
      },
    );
  }

  Widget _buildGroupTypingIndicator() {
    final state = context.read<GroupChatBloc>().state;
    final typingName = state is GroupChatAITyping ? state.characterName : null;
    if (typingName == null || typingName.isEmpty) {
      return const SizedBox.shrink();
    }

    final index = _currentSession.participantNames.indexOf(typingName);
    if (index < 0) {
      return TypingIndicator(name: typingName);
    }

    final avatar = index < _currentSession.participantAvatars.length
        ? _currentSession.participantAvatars[index]
        : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          GestureDetector(
            onTap: () => _forceReply(_currentSession.participantIds[index]),
            child: CircleAvatar(
              radius: 18,
              backgroundColor: _roleColorsForTheme(context)[index % _roleColorsForTheme(context).length],
              backgroundImage: avatar != null ? FileImage(File(avatar)) : null,
              child: avatar == null
                  ? Text(
                      typingName.characters.first,
                      style: const TextStyle(fontSize: 14),
                    )
                  : null,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  margin: const EdgeInsets.only(bottom: 4),
                  decoration: BoxDecoration(
                    color: _roleColorsForTheme(context)[index % _roleColorsForTheme(context).length]
                        .withOpacity(0.6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    typingName,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.7),
                    ),
                  ),
                ),
                _buildTypingDotsBubble(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypingDotsBubble() {
    final colorScheme = Theme.of(context).colorScheme;
    final state = context.read<GroupChatBloc>().state;
    final typingName = state is GroupChatAITyping ? state.characterName : null;
    final bubbleColor = typingName != null
        ? _getCharacterColorByName(typingName)
        : colorScheme.surfaceContainerHighest;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: bubbleColor,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(4),
          topRight: Radius.circular(16),
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          return Padding(
            padding: EdgeInsets.only(right: i < 2 ? 4 : 0),
            child: AnimatedBuilder(
              animation: _typingBlinkController,
              builder: (context, child) {
                final delay = i * 0.3;
                final value = (_typingBlinkController.value + delay) % 1.0;
                return Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: colorScheme.onSurface.withOpacity(0.3 + 0.4 * value),
                    shape: BoxShape.circle,
                  ),
                );
              },
            ),
          );
        }),
      ),
    );
  }

  Color _getCharacterColorByName(String name) {
    final index = _currentSession.participantNames.indexOf(name);
    final colors = _roleColorsForTheme(context);
    if (index < 0) return colors[0];
    return colors[index % colors.length];
  }

  Widget _buildMessageBubble(ChatMessage message, ColorScheme colorScheme) {
    if (message.type == MessageType.narration) {
      return _buildNarrationMessage(message, colorScheme);
    }
    if (message.senderId == 'system' || message.type == MessageType.system) {
      return _buildSystemMessage(message, colorScheme);
    }

    final isUser = !message.senderId.startsWith('ai_');

    if (isUser) {
      return _buildUserMessage(message, colorScheme);
    }

    return _buildAIMessage(message, colorScheme);
  }

  Widget _buildNarrationMessage(ChatMessage message, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 28),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: colorScheme.secondaryContainer.withOpacity(0.28),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colorScheme.secondary.withOpacity(0.12)),
          ),
          child: Text(
            '—— ${message.content} ——',
            style: TextStyle(
              fontSize: 13,
              height: 1.45,
              color: colorScheme.onSurface.withOpacity(0.68),
              fontStyle: FontStyle.italic,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  Widget _buildSystemMessage(ChatMessage message, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withOpacity(0.4),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            message.content,
            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  Widget _buildUserMessage(ChatMessage message, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(4),
                ),
              ),
              child: _buildRichContent(
                message.content,
                colorScheme,
                isUser: true,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAIMessage(ChatMessage message, ColorScheme colorScheme) {
    final bubbleColor = _getCharacterColor(message.senderId);
    final avatarUrl = _getCharacterAvatar(message.senderId);
    final characterId = message.senderId.replaceFirst('ai_', '');
    final characterName =
        message.senderName.isNotEmpty ? message.senderName : '角色';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => _forceReply(characterId),
            child: CircleAvatar(
              radius: 18,
              backgroundColor: bubbleColor,
              backgroundImage:
                  avatarUrl != null ? FileImage(File(avatarUrl)) : null,
              child: avatarUrl == null
                  ? Text(
                      characterName.characters.first,
                      style:
                          TextStyle(fontSize: 14, color: colorScheme.onSurface),
                    )
                  : null,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: bubbleColor.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        characterName,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface.withOpacity(0.7),
                        ),
                      ),
                    ),
                    if (message.metadata != null &&
                        message.metadata!['replyToCharacterName'] != null) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest
                              .withOpacity(0.5),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.reply_rounded,
                                size: 11,
                                color: colorScheme.onSurface.withOpacity(0.45)),
                            const SizedBox(width: 2),
                            Text(
                              '${message.metadata!['replyToCharacterName']}',
                              style: TextStyle(
                                fontSize: 10,
                                color: colorScheme.onSurface.withOpacity(0.45),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: bubbleColor,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(4),
                      topRight: Radius.circular(16),
                      bottomLeft: Radius.circular(16),
                      bottomRight: Radius.circular(16),
                    ),
                  ),
                  child: _buildRichContent(
                    message.content,
                    colorScheme,
                    isUser: false,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRichContent(
    String content,
    ColorScheme colorScheme, {
    required bool isUser,
  }) {
    final pattern = RegExp(r'\*([^*]+)\*');
    final spans = <TextSpan>[];
    int lastEnd = 0;

    for (final match in pattern.allMatches(content)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(
          text: content.substring(lastEnd, match.start),
          style: TextStyle(
            fontSize: 15,
            color:
                isUser ? colorScheme.onPrimaryContainer : colorScheme.onSurface,
          ),
        ));
      }
      spans.add(TextSpan(
        text: match.group(1),
        style: TextStyle(
          fontSize: 15,
          fontStyle: FontStyle.italic,
          color: colorScheme.onSurface.withOpacity(0.5),
        ),
      ));
      lastEnd = match.end;
    }

    if (lastEnd < content.length) {
      spans.add(TextSpan(
        text: content.substring(lastEnd),
        style: TextStyle(
          fontSize: 15,
          color:
              isUser ? colorScheme.onPrimaryContainer : colorScheme.onSurface,
        ),
      ));
    }

    if (spans.isEmpty) {
      return Text(
        content,
        style: TextStyle(
          fontSize: 15,
          color:
              isUser ? colorScheme.onPrimaryContainer : colorScheme.onSurface,
        ),
      );
    }

    return RichText(
      text: TextSpan(children: spans),
    );
  }

  Widget _buildInputArea(ColorScheme colorScheme, {required bool isAiTyping}) {
    final isObserve = _currentSession.tavernMode == TavernMode.observe;
    return Container(
      padding: const EdgeInsets.only(
        left: 12,
        right: 8,
        top: 8,
        bottom: 8,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          top: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.3)),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isObserve) ...[
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: isAiTyping ? null : _continueObserve,
                icon: const Icon(Icons.forum_rounded, size: 18),
                label: Text('让他们继续聊 · ${_currentSession.immersion.label}'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                '沉浸度越高，对话会越丰富。',
                style: TextStyle(
                  color: colorScheme.onSurface.withOpacity(0.42),
                  fontSize: 11,
                ),
              ),
            ),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 120),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: TextField(
                    controller: _messageController,
                    focusNode: _messageFocusNode,
                    maxLines: null,
                    textInputAction: TextInputAction.send,
                    onChanged: _onTextChanged,
                    onSubmitted: (_) => _sendMessage(),
                    decoration: InputDecoration(
                      hintText: _currentSession.tavernMode == TavernMode.story
                          ? '输入对白或动作...'
                          : _currentSession.tavernMode == TavernMode.observe
                              ? '想插话也可以说一句...'
                              : '对大家说点什么...',
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                    ),
                    style: const TextStyle(fontSize: 15),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isAiTyping
                      ? colorScheme.surfaceContainerHighest
                      : colorScheme.primary,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: Icon(
                    isAiTyping ? Icons.hourglass_top : Icons.send,
                    size: 20,
                    color: isAiTyping
                        ? colorScheme.onSurfaceVariant
                        : colorScheme.onPrimary,
                  ),
                  onPressed: isAiTyping ? null : _sendMessage,
                ),
              ),
            ],
          ),
        ],
      ),
    );
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
        _currentSession.id,
        query,
        limit: _searchPageSize,
        offset: 0,
      );
      final totalCount =
          await storage.countSearchMessages(_currentSession.id, query);
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
        _currentSession.id,
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

  Widget _buildSearchResults(ColorScheme colorScheme) {
    if (_searchLoading) return const Center(child: CircularProgressIndicator());
    if (_searchResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off,
                size: 48, color: colorScheme.onSurface.withOpacity(0.2)),
            const SizedBox(height: 12),
            Text('未找到相关消息',
                style:
                    TextStyle(color: colorScheme.onSurface.withOpacity(0.4))),
          ],
        ),
      );
    }
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            _searchHasMore
                ? '已加载 ${_searchResults.length} 条，共 $_searchTotalCount 条结果'
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
              final senderName = (msg.senderName ?? '').isNotEmpty
                  ? (msg.senderName ?? '')
                  : '未知';
              final isAI = msg.senderId.startsWith('ai_');
              return InkWell(
                onTap: () {
                  setState(() {
                    _isSearching = false;
                    _searchQuery = '';
                    _searchController.clear();
                  });
                },
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
                        color: isAI
                            ? colorScheme.primaryContainer
                            : colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Icon(
                        isAI ? Icons.smart_toy_outlined : Icons.person_outline,
                        size: 18,
                        color: isAI
                            ? colorScheme.onPrimaryContainer
                            : colorScheme.onSecondaryContainer,
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
                          Text(_formatSearchTime(msg.createdAt),
                              style: TextStyle(
                                  fontSize: 11,
                                  color:
                                      colorScheme.onSurface.withOpacity(0.35))),
                        ]),
                        const SizedBox(height: 3),
                        _buildGroupHighlightedText(msg.content, colorScheme),
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

  String _formatSearchTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inDays == 0)
      return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    if (diff.inDays == 1) return '昨天';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    return '${time.month}/${time.day}';
  }

  Widget _buildGroupHighlightedText(String text, ColorScheme colorScheme) {
    if (_searchQuery.isEmpty) {
      return Text(text,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontSize: 14, color: colorScheme.onSurface.withOpacity(0.7)));
    }
    final lowerText = text.toLowerCase();
    final lowerQuery = _searchQuery.toLowerCase();
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
          text: text.substring(idx, idx + _searchQuery.length),
          style: TextStyle(
              fontSize: 14,
              color: colorScheme.primary,
              fontWeight: FontWeight.w600,
              backgroundColor: colorScheme.primary.withOpacity(0.15))));
      start = idx + _searchQuery.length;
    }
    return RichText(
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(children: spans),
    );
  }
}

/// 酒馆玩法引导弹窗
class GroupChatGuideDialog extends StatefulWidget {
  const GroupChatGuideDialog({super.key});

  @override
  State<GroupChatGuideDialog> createState() => _GroupChatGuideDialogState();
}

class _GroupChatGuideDialogState extends State<GroupChatGuideDialog> {
  int _currentPage = 0;
  final int _totalPages = 4;

  final List<_GuidePage> _pages = const [
    _GuidePage(
      icon: Icons.local_bar,
      title: '欢迎来到酒馆！',
      description: '酒馆是多角色群聊互动空间。你可以邀请多个 AI 角色一起聊天，看他们互动、聊天、甚至互相调侃。',
      color: Colors.amber,
    ),
    _GuidePage(
      icon: Icons.people,
      title: '角色互动',
      description: '点击顶部的角色头像，可以强制让该角色回复消息。角色们会根据彼此的关系（盟友/仇敌/恋人等）产生不同的互动效果。',
      color: Colors.blue,
    ),
    _GuidePage(
      icon: Icons.alternate_email,
      title: '@提及功能',
      description: '输入 @ 可以提及特定角色，被提及的角色更有可能回复你。试试 @你喜欢的角色名！',
      color: Colors.green,
    ),
    _GuidePage(
      icon: Icons.flash_on,
      title: '快闪模式',
      description: '酒馆支持快闪模式，一次生成多个角色的回复，模拟真实的七嘴八舌场景。动作描写用 *星号* 包裹，如 *微微一笑*。',
      color: Colors.purple,
    ),
  ];

  void _nextPage() {
    if (_currentPage < _totalPages - 1) {
      setState(() => _currentPage++);
    } else {
      Navigator.pop(context);
    }
  }

  void _skip() {
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final page = _pages[_currentPage];

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 320,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 图标
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: page.color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                page.icon,
                size: 40,
                color: page.color,
              ),
            ),
            const SizedBox(height: 20),
            // 标题
            Text(
              page.title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            // 描述
            Text(
              page.description,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.onSurface.withOpacity(0.7),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            // 页码指示器
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_totalPages, (index) {
                return Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: index == _currentPage
                        ? colorScheme.primary
                        : colorScheme.onSurface.withOpacity(0.2),
                  ),
                );
              }),
            ),
            const SizedBox(height: 24),
            // 按钮
            Row(
              children: [
                if (_currentPage < _totalPages - 1) ...[
                  Expanded(
                    child: TextButton(
                      onPressed: _skip,
                      child: const Text('跳过'),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  flex: _currentPage < _totalPages - 1 ? 1 : 2,
                  child: FilledButton(
                    onPressed: _nextPage,
                    child:
                        Text(_currentPage < _totalPages - 1 ? '下一步' : '开始玩吧！'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _GuidePage {
  final IconData icon;
  final String title;
  final String description;
  final Color color;

  const _GuidePage({
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
  });
}
