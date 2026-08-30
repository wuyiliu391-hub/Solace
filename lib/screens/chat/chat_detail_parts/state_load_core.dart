// 状态/加载/计时器/杂项基础（拆分生成，同库 part）
part of '../chat_detail_screen.dart';

mixin _StateLoadCore on State<ChatDetailScreen>, _StateCore {
  bool get _showNewMessageBanner => _showNewMessageBannerNotifier.value;

  bool get _isAiTyping => _isAiTypingNotifier.value;

  bool get _canSend => _canSendNotifier.value;

  /// 小说模式全局生效（会话级覆盖已随调色板下线移除）
  bool _isNovelModeEnabled() {
    return RepositoryProvider.of<LocalStorageRepository>(context)
        .isChatStyleNovelModeEnabled();
  }


  /// 气泡是否需要按「有背景」处理（深色沉浸渐变同样算背景，保证文字对比）。
  bool get _hasVisibleBackground =>
      (_currentSession?.backgroundImage != null &&
          _currentSession!.backgroundImage!.isNotEmpty) ||
      Theme.of(context).brightness == Brightness.dark;


  /// 微信视觉风格是否生效（第三主题，微信骨架适配）。
  bool get _isWeChatStyle => context.read<ThemeBloc>().state.isWeChat;


  Future<void> _loadTurnState() async {
    final raw = RepositoryProvider.of<LocalStorageRepository>(context)
        .getString('turn_state_${widget.session.id}');
    if (raw == null || raw.isEmpty) return;
    try {
      final data = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      if (!mounted) return;
      setState(() {
        _turnEmotion = data['emotion']?.toString() ?? _turnEmotion;
        _turnIntensity = (data['intensity'] as num?)?.toDouble() ?? 0;
        _turnThought = data['thought']?.toString() ?? _turnThought;
      });
    } catch (_) {
      // 旧版本没有结构化状态，保留首次进入时的明确空态。
    }
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
          const advanceMsgThreshold = 8; // 新增可见消息阈值
          const advanceCooldown = Duration(hours: 1); // 冷却，避免频繁增量
          final nowMsgCount = await storage.countVisibleChatMessages(
              characterId, user?.id ?? '');
          final delta = nowMsgCount - phone.lastAdvanceMsgCount;
          final cooledDown = phone.lastAdvanceAt == null ||
              DateTime.now().difference(phone.lastAdvanceAt!) >=
                  advanceCooldown;
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
    } catch (_) {}
  }


  Future<void> _loadSessionFromDatabase() async {
    final storage = RepositoryProvider.of<LocalStorageRepository>(context);
    var updatedSession = await storage.getChatSession(widget.session.id);

    if (updatedSession != null && mounted) {
      // 检查背景图片是否有效（兼容 file://、Windows 路径）
      final bg = updatedSession.backgroundImage?.trim() ?? '';
      if (bg.isNotEmpty) {
        final isLocal = !(bg.startsWith('http://') ||
            bg.startsWith('https://') ||
            bg.startsWith('content://'));
        if (isLocal) {
          final path =
              bg.startsWith('file://') ? Uri.parse(bg).toFilePath() : bg;
          final file = File(path);
          if (!file.existsSync()) {
            updatedSession =
                updatedSession.copyWith(clearBackgroundImage: true);
            await storage.saveChatSession(updatedSession);
          }
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


  void _setReplyTo(ChatMessage message) {
    setState(() => _replyToMessage = message);
    _messageFocusNode.requestFocus();
  }


  void _cancelReply() {
    setState(() => _replyToMessage = null);
  }


  void _syncCanSend() {
    final canSend = _messageController.text.trim().isNotEmpty ||
        _pendingImagePaths.isNotEmpty;
    if (canSend != _canSend) {
      _canSendNotifier.value = canSend;
    }
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
