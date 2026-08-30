// 发送/贴图/图片输入（拆分生成，同库 part）
part of '../chat_detail_screen.dart';

mixin _StateSendInput on State<ChatDetailScreen>, _StateCore, _StateLoadCore, _StateSelection, _StateSideStory, _StateVoice {
  Future<void> _initialize() async {
    try {
      await _loadSessionFromDatabase();
    } catch (e) {
      debugPrint('初始化失败: $e');
    }
    if (mounted) {
      _resetSilenceTimer();
      _checkPendingReply();
      _chatBloc.add(ChatLoadMessages(widget.session.id));
      _startLoadingFallbackTimer();

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


  String _replyPreview(ChatMessage message) {
    switch (message.type) {
      case MessageType.image:
        return '[图片]';
      case MessageType.sticker:
        return '[表情]';
      case MessageType.system:
        return '[系统消息]';
      case MessageType.transfer:
        return '[转账]';
      case MessageType.redPacket:
        return '[红包]';
      case MessageType.text:
        return message.content.length > 50
            ? '${message.content.substring(0, 50)}...'
            : message.content;
      default:
        return '[消息]';
    }
  }


  /// 选择图片：挂到输入区待发，可继续输入文字后一起发送（不再选完即发）
  Future<void> _pickAndAttachImages() async {
    tapHaptic();
    try {
      final picker = ImagePicker();
      final images = await picker.pickMultiImage(imageQuality: 85);
      if (images.isEmpty || !mounted) return;

      // 转存到持久目录：避免系统缓存被清后历史图片裂图
      final appDir = await getApplicationDocumentsDirectory();
      final chatImgDir = Directory('${appDir.path}/chat_images');
      if (!await chatImgDir.exists()) {
        await chatImgDir.create(recursive: true);
      }

      final kept = <String>[];
      var unsupported = 0;
      for (final imgFile in images) {
        final p = imgFile.path;
        if (p.isEmpty || _pendingImagePaths.contains(p)) continue;
        final lower = p.toLowerCase();
        final isHeic = lower.endsWith('.heic') || lower.endsWith('.heif');
        try {
          if (isHeic) {
            // HEIC/HEIF → 解码转 JPEG（image 包 4.x 支持），否则丢弃
            final bytes = await File(p).readAsBytes();
            final decoded = img.decodeImage(bytes);
            if (decoded == null) {
              unsupported++;
              continue;
            }
            var out = img.bakeOrientation(decoded);
            if (out.numChannels == 4) {
              final flat = img.Image(
                width: out.width,
                height: out.height,
                numChannels: 3,
              );
              img.fill(flat, color: img.ColorRgb8(255, 255, 255));
              img.compositeImage(flat, out);
              out = flat;
            }
            final dest = '${chatImgDir.path}/chat_${const Uuid().v4()}.jpg';
            await File(dest).writeAsBytes(img.encodeJpg(out, quality: 85));
            kept.add(dest);
          } else {
            final ext =
                p.contains('.') ? p.substring(p.lastIndexOf('.')) : '.jpg';
            final dest = '${chatImgDir.path}/chat_${const Uuid().v4()}$ext';
            await File(p).copy(dest);
            kept.add(dest);
          }
        } catch (e) {
          debugPrint('图片持久化失败: $e path=$p');
          unsupported++;
        }
      }

      if (kept.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(unsupported > 0
                  ? '所选图片格式无法读取，已跳过 $unsupported 张'
                  : '未获取到可用图片'),
            ),
          );
        }
        return;
      }

      var truncated = 0;
      setState(() {
        for (final p in kept) {
          if (!_pendingImagePaths.contains(p)) {
            _pendingImagePaths.add(p);
          }
        }
        // 与 vision 请求上限对齐（OpenAI/中转稳妥）
        final maxN = VisionImageEncoder.maxImagesPerRequest;
        if (_pendingImagePaths.length > maxN) {
          truncated = _pendingImagePaths.length - maxN;
          _pendingImagePaths.removeRange(maxN, _pendingImagePaths.length);
        }
      });
      _syncCanSend();
      _messageFocusNode.requestFocus();

      if (mounted && (unsupported > 0 || truncated > 0)) {
        final hints = <String>[
          if (unsupported > 0) '跳过 $unsupported 张无法读取的图片',
          if (truncated > 0)
            '最多发送 ${VisionImageEncoder.maxImagesPerRequest} 张，已截断 $truncated 张',
        ];
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(hints.join('；'))),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('选择图片失败: $e')),
      );
    }
  }


  void _removePendingImage(int index) {
    if (index < 0 || index >= _pendingImagePaths.length) return;
    setState(() => _pendingImagePaths.removeAt(index));
    _syncCanSend();
  }


  void _clearPendingImages() {
    if (_pendingImagePaths.isEmpty) return;
    setState(() => _pendingImagePaths.clear());
    _syncCanSend();
  }


  void _sendMessage() {
    tapHaptic();
    final content = _messageController.text.trim();
    final imagePaths = List<String>.from(_pendingImagePaths);
    if (content.isEmpty && imagePaths.isEmpty) return;

    // 番外文本指令：粘贴类似 mufy 格式的番外指令，自动开启平行小剧场。
    if (!_isSideStory && imagePaths.isEmpty && _isSideStoryCommand(content)) {
      _startSideStory(initialMessage: content);
      _messageController.clear();
      _clearPendingImages();
      _canSendNotifier.value = false;
      return;
    }

    final user = (context.read<AuthBloc>().state as AuthAuthenticated).user;
    // 不再在发送后 requestFocus：用户收起键盘或 IME 发送键 unfocus 时，
    // 强拉焦点会与键盘动画 + 消息列表重建叠成卡死。

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

    // 检测括号「（动作/旁白描写）」
    // 包含中文全角括号且括号内有文字 → 标记为动作/旁白消息
    final hasActionBracket = content.isNotEmpty &&
        (RegExp(r'（[^（）]+）').hasMatch(content) ||
            RegExp(r'\([^()]+\)').hasMatch(content));
    final effectiveMetadata = <String, dynamic>{
      ...?replyMetadata,
      if (hasActionBracket) 'hasActionBracket': true,
      if (imagePaths.isNotEmpty) 'imagePaths': imagePaths,
      if (imagePaths.isNotEmpty && content.isNotEmpty) 'caption': content,
    };
    _chatBloc.add(ChatSendMessage(
      chatId: widget.session.id,
      userId: user.id,
      content: content,
      imagePaths: imagePaths.isNotEmpty ? imagePaths : null,
      metadata: effectiveMetadata.isNotEmpty ? effectiveMetadata : null,
      enableWebSearch: _webSearchEnabled,
    ));
    _messageController.clear();
    _clearPendingImages();
    _canSendNotifier.value = false;

    _userScrolledUp = false;
    _scrollToBottom(force: true);
    _resetSilenceTimer();
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
    // 主动消息现在由应用级前台心跳统一调度，避免离开本页面后丢失消息，
    // 也避免多个聊天页各自计时导致重复生成。此计时器仅保留为兼容旧状态刷新。
    _aiBrokeSilence = true;
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


  void _scrollToBottom({bool force = false}) {
    if (!force && _userScrolledUp) return;

    _showNewMessageBannerNotifier.value = false;

    void jump() {
      if (!mounted) return;
      if (!_scrollController.hasClients) return;
      if (!force && _userScrolledUp) return;
      try {
        // reverse:true 列表底部为 0
        if (_scrollController.offset != 0) {
          _scrollController.jumpTo(0);
        }
      } catch (_) {
        // 键盘动画/列表重建时 position 可能短暂不可用
      }
    }

    // 先等本帧布局，再补一帧应对键盘 viewInsets 二次布局，避免与 IME 动画抢滚动
    WidgetsBinding.instance.addPostFrameCallback((_) {
      jump();
      WidgetsBinding.instance.addPostFrameCallback((_) => jump());
    });
  }

}
