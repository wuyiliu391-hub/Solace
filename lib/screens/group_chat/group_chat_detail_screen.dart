// 群聊详情页面（对标 ChatDetailScreen 简化版）
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../../blocs/group_chat/group_chat_bloc.dart';
import '../../models/group_chat_session.dart';
import '../../models/group_chat_message.dart';
import '../../models/group_chat_branch.dart';
import '../../models/ai_character.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../repositories/local_storage_repository.dart';
import '../../utils/avatar_resolver.dart';
import '../../utils/character_color.dart';
import '../../utils/vision_image_encoder.dart';
import '../../widgets/group_chat/group_top_bar.dart';
import '../../widgets/group_chat/member_activation_bar.dart';
import '../../widgets/group_chat/group_message_bubble.dart';
import '../../widgets/group_chat/group_member_drawer.dart';

class GroupChatDetailScreen extends StatefulWidget {
  final GroupChatSession session;
  const GroupChatDetailScreen({super.key, required this.session});

  @override
  State<GroupChatDetailScreen> createState() => _GroupChatDetailScreenState();
}

class _GroupChatDetailScreenState extends State<GroupChatDetailScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late String _groupId;

  /// 会话可变副本：静音/置顶/改名后即时刷新
  late GroupChatSession _session;
  List<GroupChatMessage> _messages = [];
  bool _isLoading = true;

  /// 当前流式输出的 AI 角色名 + 文本（来自 GroupChatStreaming）
  String? _streamingCharacter;
  String _streamingText = '';
  bool _aiTyping = false;

  /// 群内 AI 成员（激活条/侧滑面板/角色色）
  List<AICharacter> _members = [];

  /// 角色 id → 角色色缓存
  final Map<String, Color> _memberColors = {};

  /// 手动锁定发言人（内存态）
  List<String> _forcedSpeakerIds = [];

  /// 当前聊天记录名（顶部悬浮条显示）
  String _chatName = '默认聊天';

  /// 待发图片
  final List<String> _pendingImagePaths = [];

  @override
  void initState() {
    super.initState();
    _groupId = widget.session.id;
    _session = widget.session;
    _loadMessages();
    _loadMembers();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    context.read<GroupChatBloc>().add(GroupChatLoadMessages(_groupId));
    _isLoading = true;
    if (mounted) setState(() {});
  }

  Future<void> _loadMembers() async {
    final repo = RepositoryProvider.of<LocalStorageRepository>(context);
    final all = await repo.getAllAICharacters();
    final byId = {for (final c in all) c.id: c};
    if (!mounted) return;
    setState(() {
      _members = _session.aiCharacterIds
          .map((id) => byId[id])
          .whereType<AICharacter>()
          .toList();
      _memberColors
        ..clear()
        ..addEntries(_members.map((c) => MapEntry(
              c.id,
              characterColor(
                colorHex: c.colorHex,
                name: c.name,
                cs: Theme.of(context).colorScheme,
              ),
            )));
    });
  }

  /// 根据会话变更事件刷新本地副本（静音/置顶/改名/公告）
  void _refreshSession(GroupChatState state) {
    if (state is GroupChatSessionsLoaded) {
      for (final s in state.sessions) {
        if (s.id == _groupId) {
          _session = s;
          break;
        }
      }
    }
    if (state is GroupChatBranchesLoaded && state.groupId == _groupId) {
      _chatName = state.branches
              .where((b) => b.branchId == state.currentChatId)
              .firstOrNull
              ?.name ??
          _chatName;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: InkWell(
          onTap: () => _scaffoldKey.currentState?.openEndDrawer(),
          borderRadius: BorderRadius.circular(8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _memberStackAvatar(),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  _session.name,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(_session.isMuted
                ? Icons.notifications_off
                : Icons.notifications),
            onPressed: () {
              context.read<GroupChatBloc>().add(GroupChatUpdateSession(
                    groupId: _groupId,
                    isMuted: !_session.isMuted,
                  ));
            },
          ),
          PopupMenuButton<String>(
            onSelected: _handleMenuAction,
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: 'pin',
                child: Text(_session.isPinned ? '取消置顶' : '置顶群聊'),
              ),
              const PopupMenuItem(value: 'settings', child: Text('群设置')),
              const PopupMenuItem(value: 'branches', child: Text('聊天记录')),
              const PopupMenuItem(value: 'delete', child: Text('删除群聊')),
            ],
          ),
        ],
      ),
      endDrawer: GroupMemberDrawer(
        session: _session,
        members: _members,
        forcedSpeakerIds: _forcedSpeakerIds,
        onToggleMute: (id) {
          final next = List<String>.from(_session.disabledMemberIds);
          next.contains(id) ? next.remove(id) : next.add(id);
          _dispatchConfig(disabledMemberIds: next);
        },
        onRemove: (id) {
          context
              .read<GroupChatBloc>()
              .add(GroupChatRemoveMember(_groupId, id));
          Navigator.pop(context);
        },
        onSpeakersChanged: _setForcedSpeakers,
      ),
      body: Column(
        children: [
          // 群公告条
          if (_session.notice != null && _session.notice!.trim().isNotEmpty)
            _buildNoticeBar(_session.notice!),
          Expanded(
            child: Stack(
              children: [
                BlocBuilder<GroupChatBloc, GroupChatState>(
                  builder: (context, state) {
                    _refreshSession(state);

                    // 流式输出中：AI 回复实时显示
                    if (state is GroupChatStreaming &&
                        state.groupId == _groupId) {
                      _streamingCharacter = state.characterName;
                      _streamingText = state.streamingText;
                      _aiTyping = true;
                      _isLoading = false;
                      return _buildMessageList(streaming: state);
                    }
                    if (state is GroupChatTyping &&
                        state.groupId == _groupId) {
                      _aiTyping = true;
                      _streamingText = '';
                      _isLoading = false;
                      return _buildMessageList(
                          typingCharacter: state.characterName);
                    }
                    if (state is GroupChatMessagesLoaded &&
                        state.groupId == _groupId) {
                      _messages = state.messages;
                      _aiTyping = false;
                      _isLoading = false;
                      return _buildMessageList();
                    }
                    if (state is GroupChatLoading && _isLoading) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (state is GroupChatError) {
                      return Center(child: Text('加载失败: ${state.message}'));
                    }
                    return const Center(child: CircularProgressIndicator());
                  },
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: GroupTopBar(
                    chatName: _chatName,
                    autoModeEnabled: _session.autoModeEnabled ?? false,
                    onChatTap: _showBranchManager,
                    onAutoModeChanged: (v) {
                      _dispatchConfig(autoModeEnabled: v);
                    },
                  ),
                ),
              ],
            ),
          ),
          MemberActivationBar(
            members: _members,
            disabledIds: _session.disabledMemberIds.toSet(),
            forcedSpeakerIds: _forcedSpeakerIds,
            onSpeakersChanged: _setForcedSpeakers,
          ),
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildNoticeBar(String notice) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.4),
      child: Row(
        children: [
          Icon(Icons.campaign_outlined,
              size: 16, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              notice,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList({
    GroupChatStreaming? streaming,
    String? typingCharacter,
  }) {
    final displayMessages = List<GroupChatMessage>.from(_messages);

    if (streaming != null) {
      // 流式中的 AI 消息：临时追加为气泡
      displayMessages.add(GroupChatMessage(
        id: '_streaming_',
        groupId: _groupId,
        senderId: '_streaming_',
        senderName: streaming.characterName,
        content: streaming.streamingText,
        isUser: false,
        type: GroupChatMessageType.text,
        timestamp: DateTime.now(),
      ));
    }

    if (displayMessages.isEmpty && typingCharacter == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chat_bubble_outline,
                size: 48,
                color: Theme.of(context).colorScheme.primary.withOpacity(0.4)),
            const SizedBox(height: 16),
            Text(
              '暂无消息',
              style: TextStyle(
                  color:
                      Theme.of(context).colorScheme.onSurface.withOpacity(0.5)),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      reverse: true,
      padding: const EdgeInsets.all(12),
      itemCount: displayMessages.length + (typingCharacter != null ? 1 : 0),
      itemBuilder: (context, index) {
        if (typingCharacter != null &&
            index == displayMessages.length) {
          return _TypingIndicator(name: typingCharacter);
        }
        final msg = displayMessages[index];
        final showAvatar = index == 0 ||
            _messages.isEmpty ||
            (index < _messages.length &&
                _messages[index - 1].senderId != msg.senderId) ||
            index >= _messages.length;
        return GroupMessageBubble(
          message: msg,
          showAvatar: showAvatar,
          screenWidth: MediaQuery.of(context).size.width,
          speakerColor: msg.senderId.startsWith('ai_')
              ? _memberColors[msg.senderId.substring(3)]
              : null,
        );
      },
    );
  }

  void _setForcedSpeakers(List<String> ids) {
    setState(() => _forcedSpeakerIds = List<String>.from(ids));
    context
        .read<GroupChatBloc>()
        .add(GroupChatSetSpeakers(groupId: _groupId, speakerIds: ids));
  }

  Widget _memberStackAvatar() {
    final cs = Theme.of(context).colorScheme;
    final avatarUrl = _session.avatarUrl;
    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      return SizedBox(
        width: 40,
        height: 30,
        child: Center(
          child: ClipOval(
            child: AvatarResolver.imageWidget(
              avatarUrl,
              width: 32,
              height: 32,
              fit: BoxFit.cover,
              onError: () => const Icon(Icons.group, size: 14),
            ),
          ),
        ),
      );
    }
    final shown = _members.take(3).toList();
    if (shown.isEmpty) {
      return CircleAvatar(
        radius: 12,
        backgroundColor: cs.tertiaryContainer,
        child: Icon(Icons.group, size: 14, color: cs.tertiary),
      );
    }
    return SizedBox(
      width: 40,
      height: 30,
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              left: i * 12,
              top: i * 3,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _memberColors[shown[i].id] ?? cs.tertiaryContainer,
                  border: Border.all(color: cs.surface, width: 1.5),
                ),
                child: Center(
                  child: Text(
                    shown[i].name.isNotEmpty
                        ? shown[i].name.substring(0, 1)
                        : '?',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 发送箭头：先横向、右端向上直角弯折 90°、顶端箭头尖朝上
  Widget _sendArrowIcon() {
    return CustomPaint(
      size: const Size(20, 20),
      painter: const _SendArrowPainter(),
    );
  }

  Widget _buildInputBar() {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
        border:
            Border(top: BorderSide(color: colorScheme.outline.withOpacity(0.2))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 待发图片预览
          if (_pendingImagePaths.isNotEmpty)
            SizedBox(
              height: 72,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                itemCount: _pendingImagePaths.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final p = _pendingImagePaths[index];
                  return Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                          File(p),
                          width: 64,
                          height: 64,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 64,
                            height: 64,
                            color: colorScheme.surfaceContainerHighest,
                            child: const Icon(Icons.broken_image, size: 20),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 0,
                        right: 0,
                        child: GestureDetector(
                          onTap: () =>
                              setState(() => _pendingImagePaths.removeAt(index)),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.close,
                                size: 14, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.add_photo_alternate_outlined),
                onPressed: _pickAndAttachImages,
                tooltip: '发送图片',
              ),
              Expanded(
                child: TextField(
                  controller: _messageController,
                  decoration: InputDecoration(
                    hintText: '输入消息...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: colorScheme.surface,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                  ),
                  maxLines: null,
                  textCapitalization: TextCapitalization.sentences,
                  onSubmitted: _sendMessage,
                ),
              ),
              const SizedBox(width: 8),
              CircleAvatar(
                radius: 18,
                backgroundColor: colorScheme.primary,
                child: IconButton(
                  icon: _sendArrowIcon(),
                  onPressed: _sendCurrentMessage,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _sendCurrentMessage() {
    _sendMessage(_messageController.text);
  }

  Future<void> _pickAndAttachImages() async {
    try {
      final picker = ImagePicker();
      final images = await picker.pickMultiImage(imageQuality: 85);
      if (images.isEmpty || !mounted) return;

      // 转存持久目录，避免清缓存后裂图
      final appDir = await getApplicationDocumentsDirectory();
      final imgDir = Directory('${appDir.path}/chat_images');
      if (!await imgDir.exists()) {
        await imgDir.create(recursive: true);
      }

      final kept = <String>[];
      for (final imgFile in images) {
        final p = imgFile.path;
        if (p.isEmpty) continue;
        try {
          final ext =
              p.contains('.') ? p.substring(p.lastIndexOf('.')) : '.jpg';
          final dest = '${imgDir.path}/gc_${const Uuid().v4()}$ext';
          await File(p).copy(dest);
          kept.add(dest);
        } catch (e) {
          debugPrint('群聊图片持久化失败: $e');
        }
      }

      if (kept.isEmpty || !mounted) return;
      setState(() => _pendingImagePaths.addAll(kept));

      // 与 vision 请求上限对齐
      if (_pendingImagePaths.length > VisionImageEncoder.maxImagesPerRequest) {
        final overflow = _pendingImagePaths.length -
            VisionImageEncoder.maxImagesPerRequest;
        setState(() => _pendingImagePaths.removeRange(
            VisionImageEncoder.maxImagesPerRequest,
            _pendingImagePaths.length));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  '最多发送 ${VisionImageEncoder.maxImagesPerRequest} 张，已截断 $overflow 张')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('选择图片失败: $e')),
      );
    }
  }

  void _sendMessage(String content) {
    final text = content.trim();
    final hasImages = _pendingImagePaths.isNotEmpty;
    if (text.isEmpty && !hasImages) return;

    final authState = context.read<AuthBloc>().state;
    String userId = 'local_user';
    if (authState is AuthAuthenticated) {
      userId = authState.user.id;
    }

    context.read<GroupChatBloc>().add(GroupChatSendMessage(
          groupId: _groupId,
          userId: userId,
          content: text,
          imagePaths: hasImages ? List<String>.from(_pendingImagePaths) : null,
        ));
    _messageController.clear();
    if (hasImages) setState(() => _pendingImagePaths.clear());

    // 滚动到底部
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _handleMenuAction(String action) {
    switch (action) {
      case 'pin':
        context.read<GroupChatBloc>().add(GroupChatUpdateSession(
              groupId: _groupId,
              isPinned: !_session.isPinned,
            ));
        break;
      case 'settings':
        _showGroupSettings();
        break;
      case 'branches':
        _showBranchManager();
        break;
      case 'delete':
        _confirmDelete();
        break;
    }
  }

  void _showGroupSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: Theme.of(ctx).colorScheme.surface,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Theme.of(ctx)
                        .colorScheme
                        .onSurfaceVariant
                        .withOpacity(0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.drive_file_rename_outline),
                  title: const Text('重命名群聊'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showRenameDialog();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.campaign_outlined),
                  title: const Text('群公告'),
                  subtitle: Text(_session.notice?.isNotEmpty == true
                      ? _session.notice!
                      : '未设置'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showNoticeDialog();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.group),
                  title: const Text('群成员'),
                  subtitle: Text('${_session.memberIds.length} 人'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showMembers();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.person_add_alt_outlined),
                  title: const Text('邀请 AI 角色'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showInviteDialog();
                  },
                ),
                // ─── SillyTavern 引擎配置 ───
                StatefulBuilder(builder: (ctx2, setSheet) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Divider(height: 24),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text('群聊引擎',
                              style: TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(height: 4),
                      ListTile(
                        leading: const Icon(Icons.rule),
                        title: const Text('激活策略'),
                        subtitle: Text(_strategyLabel(_session
                                .activationStrategy) ??
                            '自然'),
                        trailing: const Icon(Icons.chevron_right, size: 18),
                        onTap: () async {
                          final v = await _showStrategyPicker();
                          if (v != null) {
                            _dispatchConfig(activationStrategy: v);
                            setSheet(() {});
                          }
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.merge_type),
                        title: const Text('生成模式'),
                        subtitle: Text(
                            _generationModeLabel(_session.generationMode) ??
                                '逐角色切换'),
                        trailing: const Icon(Icons.chevron_right, size: 18),
                        onTap: () async {
                          final v = await _showGenerationModePicker();
                          if (v != null) {
                            _dispatchConfig(generationMode: v);
                            setSheet(() {});
                          }
                        },
                      ),
                      SwitchListTile(
                        secondary: const Icon(Icons.repeat),
                        title: const Text('允许同一角色连续发言'),
                        value: _session.allowSelfResponses ?? false,
                        onChanged: (v) {
                          _dispatchConfig(allowSelfResponses: v);
                          setSheet(() {});
                        },
                      ),
                      SwitchListTile(
                        secondary: const Icon(Icons.auto_awesome),
                        title: const Text('自动接话'),
                        subtitle: const Text('AI 之间持续聊天（对标 SillyTavern Auto Mode）'),
                        value: _session.autoModeEnabled ?? false,
                        onChanged: (v) {
                          _dispatchConfig(autoModeEnabled: v);
                          setSheet(() {});
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.timer_outlined),
                        title: const Text('自动接话间隔'),
                        subtitle: Text('${_session.autoModeDelay ?? 5} 秒'),
                        trailing: const Icon(Icons.chevron_right, size: 18),
                        onTap: () => _showAutoModeDelayPicker(),
                      ),
                      ListTile(
                        leading: const Icon(Icons.block),
                        title: const Text('禁言成员'),
                        subtitle: Text(_session.disabledMemberIds.isEmpty
                            ? '无'
                            : '${_session.disabledMemberIds.length} 人被禁言'),
                        onTap: () {
                          Navigator.pop(ctx);
                          _showMuteMembersPicker();
                        },
                      ),
                    ],
                  );
                }),
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('群信息'),
                  subtitle:
                      Text('创建者: ${_session.creatorId.substring(0, 8)}...'),
                  onTap: () {
                    Navigator.pop(ctx);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── 群聊引擎配置辅助 ───

  void _dispatchConfig({
    GroupActivationStrategy? activationStrategy,
    GroupGenerationMode? generationMode,
    bool? allowSelfResponses,
    int? autoModeDelay,
    bool? autoModeEnabled,
    List<String>? disabledMemberIds,
  }) {
    context.read<GroupChatBloc>().add(GroupChatUpdateConfig(
          groupId: _groupId,
          activationStrategy: activationStrategy,
          generationMode: generationMode,
          allowSelfResponses: allowSelfResponses,
          autoModeDelay: autoModeDelay,
          autoModeEnabled: autoModeEnabled,
          disabledMemberIds: disabledMemberIds,
        ));
  }

  String _strategyLabel(GroupActivationStrategy s) {
    switch (s) {
      case GroupActivationStrategy.natural:
        return '自然(提及+健谈度)';
      case GroupActivationStrategy.list:
        return '按列表轮流';
      case GroupActivationStrategy.pooled:
        return '轮转池';
      case GroupActivationStrategy.manual:
        return '手动点名';
    }
  }

  String _generationModeLabel(GroupGenerationMode m) {
    switch (m) {
      case GroupGenerationMode.swap:
        return '逐角色切换';
      case GroupGenerationMode.append:
        return '合并角色卡';
      case GroupGenerationMode.appendDisabled:
        return '合并卡(排除禁言)';
    }
  }

  Future<GroupActivationStrategy?> _showStrategyPicker() {
    return showDialog<GroupActivationStrategy>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('激活策略'),
        children: GroupActivationStrategy.values
            .map((s) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, s),
                  child: Text(_strategyLabel(s)),
                ))
            .toList(),
      ),
    );
  }

  Future<GroupGenerationMode?> _showGenerationModePicker() {
    return showDialog<GroupGenerationMode>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('生成模式'),
        children: GroupGenerationMode.values
            .map((m) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, m),
                  child: Text(_generationModeLabel(m)),
                ))
            .toList(),
      ),
    );
  }

  void _showAutoModeDelayPicker() {
    showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('自动接话间隔（秒）'),
        children: [5, 10, 15, 20, 30]
            .map((d) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, d),
                  child: Text('$d 秒'),
                ))
            .toList(),
      ),
    ).then((d) {
      if (d != null) _dispatchConfig(autoModeDelay: d);
    });
  }

  void _showMuteMembersPicker() {
    final session = _session;
    final disabled = Set<String>.from(session.disabledMemberIds);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('禁言成员'),
        content: FutureBuilder<List<AICharacter>>(
          future: _loadMemberCharacters(session),
          builder: (ctx, snap) {
            final chars = snap.data ?? [];
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: chars.map((c) {
                  return CheckboxListTile(
                    title: Text(c.name),
                    value: disabled.contains(c.id),
                    onChanged: (v) {
                      v == true ? disabled.add(c.id) : disabled.remove(c.id);
                    },
                  );
                }).toList(),
              ),
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              _dispatchConfig(disabledMemberIds: disabled.toList());
              Navigator.pop(ctx);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Future<List<AICharacter>> _loadMemberCharacters(
      GroupChatSession session) async {
    final repo = RepositoryProvider.of<LocalStorageRepository>(context);
    final list = <AICharacter>[];
    for (final id in session.aiCharacterIds) {
      final c = await repo.getAICharacter(id);
      if (c != null) list.add(c);
    }
    return list;
  }

  // ─── 聊天记录（分支）管理 ───

  void _showBranchManager() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => BlocBuilder<GroupChatBloc, GroupChatState>(
        builder: (ctx, state) {
          final branches = state is GroupChatBranchesLoaded
              ? state.branches
              : const <GroupChatBranch>[];
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.add),
                  title: const Text('新建聊天记录'),
                  onTap: () => _createBranch(),
                ),
                const Divider(height: 1),
                if (branches.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('暂无聊天记录'),
                  )
                else
                  ...branches.map((b) => ListTile(
                        title: Text(b.name),
                        subtitle: Text(b.branchId == _session.chatId
                            ? '当前'
                            : ''),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.arrow_forward),
                              tooltip: '切换到此记录',
                              onPressed: b.branchId == _session.chatId
                                  ? null
                                  : () => context
                                      .read<GroupChatBloc>()
                                      .add(GroupChatSwitchBranch(
                                          groupId: _groupId,
                                          chatId: b.branchId)),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              tooltip: '删除记录',
                              onPressed: branches.length <= 1
                                  ? null
                                  : () => context
                                      .read<GroupChatBloc>()
                                      .add(GroupChatDeleteBranch(
                                          groupId: _groupId,
                                          chatId: b.branchId)),
                            ),
                          ],
                        ),
                      )),
              ],
            ),
          );
        },
      ),
    );
  }

  void _createBranch() {
    final controller = TextEditingController();
    showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建聊天记录'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 20,
          decoration: const InputDecoration(hintText: '记录名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(ctx, controller.text.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    ).then((name) {
      if (name != null && name.isNotEmpty) {
        context.read<GroupChatBloc>().add(
            GroupChatCreateBranch(groupId: _groupId, name: name));
      }
    });
  }

  void _showRenameDialog() {
    final controller = TextEditingController(text: _session.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名群聊'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 20,
          decoration: const InputDecoration(hintText: '输入新群名'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isEmpty) return;
              context.read<GroupChatBloc>().add(GroupChatUpdateSession(
                    groupId: _groupId,
                    name: name,
                  ));
              Navigator.pop(ctx);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _showNoticeDialog() {
    final controller = TextEditingController(text: _session.notice ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('群公告'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 50,
          maxLines: 3,
          decoration: const InputDecoration(hintText: '输入群公告'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              final notice = controller.text.trim();
              context.read<GroupChatBloc>().add(GroupChatUpdateSession(
                    groupId: _groupId,
                    notice: notice.isEmpty ? null : notice,
                  ));
              Navigator.pop(ctx);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _showMembers() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${_session.name} - 成员'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: _session.memberIds.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (ctx, index) {
              final memberId = _session.memberIds[index];
              final isAi = _session.aiCharacterIds.contains(memberId);
              return ListTile(
                dense: true,
                leading: CircleAvatar(
                  backgroundColor: isAi
                      ? Theme.of(ctx).colorScheme.tertiaryContainer
                      : Theme.of(ctx).colorScheme.primaryContainer,
                  child: Icon(
                    isAi ? Icons.smart_toy : Icons.person,
                    size: 18,
                    color: isAi
                        ? Theme.of(ctx).colorScheme.tertiary
                        : Theme.of(ctx).colorScheme.primary,
                  ),
                ),
                title: Text(
                    isAi ? 'AI 角色' : (memberId == 'local_user' ? '我' : memberId)),
                subtitle: Text(isAi ? 'AI' : '用户'),
                trailing: isAi && memberId != 'local_user'
                    ? IconButton(
                        icon: const Icon(Icons.exit_to_app,
                            size: 18, color: Color(0xFFE53935)),
                        tooltip: '移出群聊',
                        onPressed: () {
                          context.read<GroupChatBloc>().add(
                              GroupChatRemoveMember(_groupId, memberId));
                          Navigator.pop(ctx);
                        },
                      )
                    : null,
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  void _showInviteDialog() {
    showDialog(
      context: context,
      builder: (ctx) => FutureBuilder<List<AICharacter>>(
        future:
            RepositoryProvider.of<LocalStorageRepository>(ctx).getAllAICharacters(),
        builder: (ctx, snap) {
          final all = snap.data ?? <AICharacter>[];
          final inGroup = _session.aiCharacterIds.toSet();
          final candidates =
              all.where((c) => !inGroup.contains(c.id)).toList();

          return AlertDialog(
            title: const Text('邀请 AI 角色'),
            content: SizedBox(
              width: double.maxFinite,
              height: 320,
              child: candidates.isEmpty
                  ? const Center(child: Text('所有 AI 角色都已在群里'))
                  : ListView.separated(
                      itemCount: candidates.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (ctx, index) {
                        final ch = candidates[index];
                        return ListTile(
                          dense: true,
                          leading: CircleAvatar(
                            backgroundColor:
                                Theme.of(ctx).colorScheme.tertiaryContainer,
                            child: const Icon(Icons.smart_toy, size: 18),
                          ),
                          title: Text(ch.name),
                          subtitle: Text(ch.personality.length > 20
                              ? ch.personality.substring(0, 20)
                              : ch.personality),
                          trailing: const Icon(Icons.add, size: 20),
                          onTap: () {
                            context.read<GroupChatBloc>().add(
                                GroupChatAddMember(_groupId, ch.id));
                            Navigator.pop(ctx);
                          },
                        );
                      },
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('关闭'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _confirmDelete() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除群聊'),
        content: Text('确定要删除群聊"${_session.name}"吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              context.read<GroupChatBloc>().add(GroupChatDelete(_groupId));
              if (context.mounted) {
                Navigator.pop(context, true);
              }
            },
            style:
                TextButton.styleFrom(foregroundColor: const Color(0xFFE53935)),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}

/// 群聊 AI 输入中指示
class _TypingIndicator extends StatelessWidget {
  final String name;
  const _TypingIndicator({required this.name});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: cs.tertiaryContainer,
            ),
            child: Center(
              child: Text(
                name.isNotEmpty ? name.substring(0, 1) : '?',
                style: TextStyle(
                  color: cs.tertiary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16).copyWith(
                bottomLeft: const Radius.circular(4),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _dot(cs),
                const SizedBox(width: 4),
                _dot(cs),
                const SizedBox(width: 4),
                _dot(cs),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dot(ColorScheme cs) {
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(
        color: cs.onSurfaceVariant.withOpacity(0.5),
        shape: BoxShape.circle,
      ),
    );
  }
}

/// 先横向、再向上直角弯折 90° 的箭头（箭头尖朝上）
class _SendArrowPainter extends CustomPainter {
  const _SendArrowPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final w = size.width;
    final h = size.height;
    final path = Path();
    // 横向线段
    path.moveTo(2, h - 4);
    path.lineTo(w - 4, h - 4);
    // 右端向上直角弯折 90°
    path.lineTo(w - 4, 6);
    // 箭头尖朝上（左右两条斜线）
    path.moveTo(w - 4, 6);
    path.lineTo(w - 9.5, 2);
    path.moveTo(w - 4, 6);
    path.lineTo(w + 1.5, 2);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

