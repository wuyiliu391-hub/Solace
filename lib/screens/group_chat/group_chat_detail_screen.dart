// 群聊详情页面（对标 ChatDetailScreen 简化版）
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../../blocs/group_chat/group_chat_bloc.dart';
import '../../models/group_chat_session.dart';
import '../../models/group_chat_message.dart';
import '../../models/group_chat_branch.dart';
import '../../models/group_chat_lorebook_entry.dart';
import '../../models/ai_character.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../repositories/local_storage_repository.dart';
import '../../utils/avatar_resolver.dart';
import '../../utils/character_color.dart';
import '../../utils/vision_image_encoder.dart';
import '../../widgets/avatar_picker.dart';
import '../../widgets/group_chat/group_top_bar.dart';
import '../../widgets/group_chat/member_activation_bar.dart';
import '../../widgets/group_chat/group_message_bubble.dart';
import '../../widgets/message_actions_sheet.dart';
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

  /// 设置弹窗内临时头像（选图后立即显示，持久化走 GroupChatUpdateSession）
  String? _dialogAvatar;

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

  /// 引用的消息（发送时写入 metadata['replyTo']）
  GroupChatMessage? _replyToMessage;

  /// 多选模式（批量删除 / 收藏，对齐单聊）
  bool _selectionMode = false;
  final Set<String> _selectedIds = {};

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

  /// 静默刷新消息（批量操作后），不发 loading
  void _reloadMessages() {
    context.read<GroupChatBloc>().add(GroupChatLoadMessages(_groupId));
  }

  Future<void> _loadMembers() async {
    final repo = RepositoryProvider.of<LocalStorageRepository>(context);
    final all = await repo.getAllAICharacters();
    final byId = {for (final c in all) c.id: c};
    if (!mounted) return;
    final members = _session.aiCharacterIds
        .map((id) => byId[id])
        .whereType<AICharacter>()
        .toList();
    final cs = Theme.of(context).colorScheme;
    // 色相去重：多角色群聊防撞色（哈希色相可能相近导致身份混淆）
    final colors = groupMemberColors(
      memberIds: members.map((c) => c.id).toList(),
      resolve: (id) => characterColor(
        colorHex: byId[id]?.colorHex,
        name: byId[id]?.name ?? id,
        cs: cs,
      ),
      minHueGap: 30,
    );
    setState(() {
      _members = members;
      _memberColors
        ..clear()
        ..addAll(colors);
    });
  }

  /// 按角色 id 找成员（头像等）
  AICharacter? _memberById(String? characterId) {
    if (characterId == null || characterId.isEmpty) return null;
    for (final c in _members) {
      if (c.id == characterId) return c;
    }
    return null;
  }

  /// 按角色名反查成员 id（流式消息只有名字）
  String? _memberIdByName(String? name) {
    if (name == null || name.isEmpty) return null;
    for (final c in _members) {
      if (c.name == name) return c.id;
    }
    return null;
  }

  /// 根据会话变更事件刷新本地副本（静音/置顶/改名/公告）
  void _refreshSession(GroupChatState state) {
    if (state is GroupChatSessionsLoaded) {
      for (final s in state.sessions) {
        if (s.id == _groupId) {
          final prevIds = _session.aiCharacterIds.join(',');
          _session = s;
          // 成员变更（邀请/移除）→ 重新加载成员与角色色，防头像/身份混淆
          if (prevIds != s.aiCharacterIds.join(',')) {
            _loadMembers();
          }
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
      appBar: _selectionMode
          ? _buildSelectionAppBar(colorScheme)
          : AppBar(
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
                    final muted = !_session.isMuted;
                    setState(
                        () => _session = _session.copyWith(isMuted: muted));
                    context.read<GroupChatBloc>().add(GroupChatUpdateSession(
                          groupId: _groupId,
                          isMuted: muted,
                        ));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text(muted ? '已静音群聊通知' : '已开启群聊通知'),
                          duration: const Duration(seconds: 1)),
                    );
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
                    const PopupMenuItem(value: 'lorebook', child: Text('世界书')),
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
                      _isLoading = false;
                      // 发送后 MessagesLoaded 可能与本状态同帧被合并吞掉，
                      // 这里消费 state.messages 兜底（否则用户刚发的消息会消失到 AI 回复才出现）
                      if (state.messages.isNotEmpty) {
                        _messages = state.messages;
                      }
                      return _buildMessageList(streaming: state);
                    }
                    if (state is GroupChatTyping && state.groupId == _groupId) {
                      _isLoading = false;
                      if (state.messages.isNotEmpty) {
                        _messages = state.messages;
                      }
                      return _buildMessageList(
                          typingCharacter: state.characterName);
                    }
                    if (state is GroupChatMessagesLoaded &&
                        state.groupId == _groupId) {
                      _messages = state.messages;
                      _isLoading = false;
                      return _buildMessageList();
                    }
                    if (state is GroupChatBranchesLoaded &&
                        state.groupId == _groupId) {
                      // _onLoadMessages 紧随 MessagesLoaded 又 emit 本状态，
                      // 同帧合并时 MessagesLoaded 可能被吞 → 分支态自携带消息兜底，
                      // 确保空列表也有「已加载」终止分支，不再回到转圈。
                      if (state.messages.isNotEmpty) {
                        _messages = state.messages;
                      }
                      _isLoading = false;
                      return _buildMessageList();
                    }
                    if (state is GroupChatLoading && _isLoading) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (state is GroupChatError) {
                      return Center(child: Text('加载失败: ${state.message}'));
                    }
                    // 已加载过（含空列表）的终止分支：GroupChatBloc 是全局共享单例，
                    // 列表页/主页的 GroupChatLoadSessions 刷新会随时把状态切回
                    // Loading/SessionsLoaded。若此时没有此分支，页面会回到转圈。
                    if (!_isLoading) {
                      return _buildMessageList();
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
                      setState(() =>
                          _session = _session.copyWith(autoModeEnabled: v));
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
      // 流式中的 AI 消息：插入列表头部（DESC 序 index 0 = 视觉底部最新）
      // 思考阶段 streamingText 为空、reasoning 非空 → 显示「思考中…」反馈，
      // 避免用户误以为 AI 无响应（背后其实在思考/准备回复）
      final streamingContent = streaming.streamingText.isNotEmpty
          ? streaming.streamingText
          : (streaming.reasoning.isNotEmpty ? '思考中…' : '');
      displayMessages.insert(
          0,
          GroupChatMessage(
            id: '_streaming_',
            groupId: _groupId,
            senderId: '_streaming_',
            senderName: streaming.characterName,
            content: streamingContent,
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
        if (typingCharacter != null && index == 0) {
          return _TypingIndicator(
            name: typingCharacter,
            avatarUrl: _memberById(_memberIdByName(typingCharacter))?.avatarUrl,
          );
        }
        // 有打字指示器时消息整体后移一格
        final msgIndex = typingCharacter != null ? index - 1 : index;
        final msg = displayMessages[msgIndex];
        final prev = msgIndex > 0 ? displayMessages[msgIndex - 1] : null;
        final showAvatar = prev == null || prev.senderId != msg.senderId;
        // 发送者角色 id：流式消息按名字反查（senderId 为占位符）
        final isStreamingMsg = msg.id == '_streaming_';
        final senderId = isStreamingMsg
            ? _memberIdByName(streaming?.characterName)
            : (msg.senderId.startsWith('ai_')
                ? msg.senderId.substring(3)
                : null);
        final sender = _memberById(senderId);
        // 用户头像：AuthUser 自定义头像（与单聊一致）
        String? userAvatarUrl;
        try {
          final authState = context.read<AuthBloc>().state;
          userAvatarUrl =
              authState is AuthAuthenticated ? authState.user.avatarUrl : null;
        } catch (_) {
          // Standalone previews/tests may not install the app-level AuthBloc.
        }
        return GroupMessageBubble(
          message: msg,
          showAvatar: showAvatar,
          screenWidth: MediaQuery.of(context).size.width,
          speakerColor: senderId != null ? _memberColors[senderId] : null,
          avatarUrl: msg.isUser ? userAvatarUrl : sender?.avatarUrl,
          isSelected: _selectionMode && _selectedIds.contains(msg.id),
          onTap: _selectionMode ? () => _toggleSelect(msg.id) : null,
          onSwipeChanged: !_selectionMode && msg.swipeHistory.length > 1
              ? (index) => context.read<GroupChatBloc>().add(
                  GroupChatSelectSwipe(
                      groupId: _groupId, messageId: msg.id, index: index))
              : null,
          onRetry: msg.isUser && msg.status == GroupChatMessageStatus.failed
              ? () => context.read<GroupChatBloc>().add(GroupChatSendMessage(
                    groupId: _groupId,
                    userId: msg.senderId,
                    content: msg.content,
                  ))
              : null,
          onLongPress: _selectionMode
              ? null
              : isStreamingMsg
                  ? null
                  : () => _showMessageOptions(msg),
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
                clipBehavior: Clip.antiAlias,
                child: _memberAvatarSmall(shown[i], cs),
              ),
            ),
        ],
      ),
    );
  }

  /// 24px 圆形成员头像（真实头像优先，回退首字）
  Widget _memberAvatarSmall(AICharacter c, ColorScheme cs) {
    final image = AvatarResolver.imageWidget(
      c.avatarUrl,
      width: 24,
      height: 24,
      fit: BoxFit.cover,
      onError: () => _memberInitial(c),
    );
    return image ?? _memberInitial(c);
  }

  Widget _memberInitial(AICharacter c) {
    return Center(
      child: Text(
        c.name.isNotEmpty ? c.name.substring(0, 1) : '?',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildInputBar() {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
        border: Border(
            top: BorderSide(color: colorScheme.outline.withOpacity(0.2))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 引用预览条（可关闭）
          if (_replyToMessage != null)
            Container(
              margin: const EdgeInsets.fromLTRB(4, 0, 4, 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withOpacity(0.4),
                borderRadius: BorderRadius.circular(10),
                border: Border(
                  left: BorderSide(color: colorScheme.primary, width: 3),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _replyToMessage!.senderName,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.primary,
                          ),
                        ),
                        Text(
                          _replyPreview(_replyToMessage!),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: () => setState(() => _replyToMessage = null),
                    tooltip: '取消引用',
                  ),
                ],
              ),
            ),
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
                          onTap: () => setState(
                              () => _pendingImagePaths.removeAt(index)),
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
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                  maxLines: null,
                  textCapitalization: TextCapitalization.sentences,
                  onSubmitted: _sendMessage,
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _sendCurrentMessage,
                child: Container(
                  width: 40,
                  height: 40,
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
        final overflow =
            _pendingImagePaths.length - VisionImageEncoder.maxImagesPerRequest;
        setState(() => _pendingImagePaths.removeRange(
            VisionImageEncoder.maxImagesPerRequest, _pendingImagePaths.length));
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

    Map<String, dynamic>? metadata;
    if (_replyToMessage != null) {
      metadata = {
        'replyTo': {
          'messageId': _replyToMessage!.id,
          'senderName': _replyToMessage!.senderName,
          'contentPreview': _replyPreview(_replyToMessage!),
        },
      };
      setState(() => _replyToMessage = null);
    }

    context.read<GroupChatBloc>().add(GroupChatSendMessage(
          groupId: _groupId,
          userId: userId,
          content: text,
          imagePaths: hasImages ? List<String>.from(_pendingImagePaths) : null,
          metadata: metadata,
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
      case 'lorebook':
        _showLorebookDialog();
        break;
      case 'delete':
        _confirmDelete();
        break;
    }
  }

  // ─── 多选模式（批量删除 / 收藏，对齐单聊）───

  void _enterSelection(String messageId) {
    setState(() {
      _selectionMode = true;
      _selectedIds
        ..clear()
        ..add(messageId);
    });
  }

  void _exitSelection() {
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  void _toggleSelect(String messageId) {
    setState(() {
      if (!_selectedIds.remove(messageId)) _selectedIds.add(messageId);
      if (_selectedIds.isEmpty) _selectionMode = false;
    });
  }

  void _selectAllMessages() {
    setState(() {
      _selectedIds
        ..clear()
        ..addAll(_messages.map((m) => m.id));
    });
  }

  Future<void> _batchBookmark() async {
    if (_selectedIds.isEmpty) return;
    final ids = Set<String>.from(_selectedIds);
    final storage = RepositoryProvider.of<LocalStorageRepository>(context);
    var n = 0;
    for (final m in _messages) {
      if (ids.contains(m.id) && !m.isBookmarked) {
        await storage.saveGroupChatMessage(m.copyWith(metadata: {
          ...?m.metadata,
          'bookmarked': true,
        }));
        n++;
      }
    }
    _reloadMessages();
    _exitSelection();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('已收藏 $n 条消息'), duration: const Duration(seconds: 1)),
      );
    }
  }

  Future<void> _batchDelete() async {
    if (_selectedIds.isEmpty) return;
    final count = _selectedIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('批量删除'),
        content: Text('确定要删除选中的 $count 条消息吗？此操作不可恢复。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final ids = Set<String>.from(_selectedIds);
    final storage = RepositoryProvider.of<LocalStorageRepository>(context);
    for (final id in ids) {
      await storage.deleteGroupChatMessage(id);
    }
    _reloadMessages();
    _exitSelection();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('已删除 ${ids.length} 条消息'),
            duration: const Duration(seconds: 1)),
      );
    }
  }

  PreferredSizeWidget _buildSelectionAppBar(ColorScheme colorScheme) {
    return AppBar(
      backgroundColor: colorScheme.surface,
      elevation: 0,
      scrolledUnderElevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: _exitSelection,
      ),
      title: Text('已选 ${_selectedIds.length} 项'),
      actions: [
        IconButton(
          tooltip: '全选',
          icon: const Icon(Icons.select_all),
          onPressed: _selectAllMessages,
        ),
        IconButton(
          tooltip: '批量收藏',
          icon: const Icon(Icons.bookmark_add_outlined),
          onPressed: _selectedIds.isEmpty ? null : _batchBookmark,
        ),
        IconButton(
          tooltip: '批量删除',
          icon: const Icon(Icons.delete_outline),
          onPressed: _selectedIds.isEmpty ? null : _batchDelete,
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  // ─── 消息操作（对齐单聊 7 项：引用/复制/编辑/重生成/收藏/删除/撤回）───

  /// 引用摘要文本（对齐单聊 _replyPreview）
  String _replyPreview(GroupChatMessage msg) {
    final content = msg.content.trim();
    if (content.isEmpty)
      return msg.type == GroupChatMessageType.image ? '[图片]' : '';
    if (content.length <= 60) return content;
    return '${content.substring(0, 60)}…';
  }

  void _setReplyTo(GroupChatMessage message) {
    setState(() => _replyToMessage = message);
  }

  void _showMessageOptions(GroupChatMessage message) {
    final isText =
        !message.isRecalled && message.type == GroupChatMessageType.text;
    final isAIMessage = !message.isUser && !message.isSystem;
    final canRecall = message.isUser &&
        DateTime.now().difference(message.timestamp).inMinutes <= 2 &&
        !message.isRecalled;
    MessageActionsSheet.show(
      context: context,
      actions: [
        MessageActionItem(
          label: '回复',
          icon: Icons.reply,
          color: Colors.blue,
          onPressed: () => _setReplyTo(message),
        ),
        if (isText)
          MessageActionItem(
            label: '复制',
            icon: Icons.copy,
            color: Colors.teal,
            onPressed: () {
              Clipboard.setData(ClipboardData(text: message.content));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('已复制到剪贴板'),
                duration: Duration(seconds: 1),
              ));
            },
          ),
        if (isAIMessage && isText)
          MessageActionItem(
            label: '编辑',
            icon: Icons.edit,
            color: Colors.green,
            subtitle: '修改AI的回复内容',
            onPressed: () => _showEditAIReplyDialog(message),
          ),
        if (isAIMessage && !message.isRecalled)
          MessageActionItem(
            label: '重新生成',
            icon: Icons.refresh,
            color: Colors.purple,
            subtitle: '让AI重新回复，覆盖当前内容',
            onPressed: () => _showRegenerateConfirm(message),
          ),
        if (message.swipeHistory.length > 1)
          MessageActionItem(
            label: '切换候选回复',
            icon: Icons.swap_horiz,
            color: Colors.indigo,
            subtitle:
                '${message.swipeHistory.length} 个候选，当前第 ${message.swipeIndex + 1} 个',
            onPressed: () => _showSwipePicker(message),
          ),
        if (isAIMessage)
          MessageActionItem(
            label: '从此处创建分支',
            icon: Icons.account_tree_outlined,
            color: Colors.deepPurple,
            subtitle: '复制当前消息之前的聊天历史',
            onPressed: () => _showCreateBranchFromMessage(message),
          ),
        if (canRecall)
          MessageActionItem(
            label: '撤回',
            icon: Icons.undo,
            color: Colors.orange,
            subtitle: '2分钟内可撤回',
            onPressed: () => context.read<GroupChatBloc>().add(
                  GroupChatRecallMessage(
                    groupId: _groupId,
                    messageId: message.id,
                  ),
                ),
          ),
        MessageActionItem(
          label: message.isBookmarked ? '取消收藏' : '收藏',
          icon: Icons.bookmark_border,
          color: Colors.amber.shade700,
          onPressed: () => context.read<GroupChatBloc>().add(
                GroupChatToggleBookmark(
                  groupId: _groupId,
                  messageId: message.id,
                ),
              ),
        ),
        MessageActionItem(
          label: '删除',
          icon: Icons.delete_outline,
          color: Colors.red[400],
          onPressed: () => _showDeleteConfirm(message),
        ),
      ],
    );
  }

  void _showSwipePicker(GroupChatMessage message) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: message.swipeHistory.length,
          itemBuilder: (_, index) => ListTile(
            leading: CircleAvatar(child: Text('${index + 1}')),
            title: Text(
              message.swipeHistory[index],
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: index == message.swipeIndex
                ? const Icon(Icons.check, color: Colors.green)
                : null,
            onTap: () {
              Navigator.pop(ctx);
              context.read<GroupChatBloc>().add(GroupChatSelectSwipe(
                    groupId: _groupId,
                    messageId: message.id,
                    index: index,
                  ));
            },
          ),
        ),
      ),
    );
  }

  void _showCreateBranchFromMessage(GroupChatMessage message) {
    final controller =
        TextEditingController(text: '从 ${message.senderName} 分支');
    showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('从消息创建分支'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    ).then((name) {
      if (name == null || name.isEmpty) return;
      context.read<GroupChatBloc>().add(GroupChatCreateBranch(
            groupId: _groupId,
            name: name,
            forkMessageId: message.id,
          ));
    });
  }

  Future<void> _showLorebookDialog() async {
    final repository = RepositoryProvider.of<LocalStorageRepository>(context);
    final entries = await repository.getGroupChatLorebookEntries(_groupId,
        chatId: _session.chatId);
    if (!mounted) return;
    final content = TextEditingController();
    final keywords = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('世界书（${entries.length} 条）'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ...entries.map((entry) => ListTile(
                    dense: true,
                    title: Text(entry.name.isEmpty ? entry.id : entry.name),
                    subtitle:
                        Text('${entry.keywords.join('、')}\n${entry.content}'),
                    isThreeLine: true,
                    onTap: () {
                      Navigator.pop(ctx);
                      _showLorebookEditor(entry);
                    },
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        await repository.deleteGroupChatLorebookEntry(entry.id);
                        if (ctx.mounted) Navigator.pop(ctx);
                        _showLorebookDialog();
                      },
                    ),
                  )),
              const Divider(),
              TextField(
                controller: keywords,
                decoration: const InputDecoration(labelText: '触发关键词（逗号分隔）'),
              ),
              TextField(
                controller: content,
                maxLines: 3,
                decoration: const InputDecoration(labelText: '触发后注入的世界设定'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
          FilledButton(
            onPressed: () async {
              final text = content.text.trim();
              final keys = keywords.text
                  .split(RegExp(r'[,，]'))
                  .map((e) => e.trim())
                  .where((e) => e.isNotEmpty)
                  .toList();
              if (text.isEmpty || keys.isEmpty) return;
              await repository.saveGroupChatLorebookEntry(
                GroupChatLorebookEntry(
                  id: 'lore_${DateTime.now().microsecondsSinceEpoch}',
                  groupId: _groupId,
                  chatId: _session.chatId,
                  name: keys.first,
                  content: text,
                  keywords: keys,
                  priority: 10,
                ),
              );
              if (ctx.mounted) Navigator.pop(ctx);
              _showLorebookDialog();
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
  }

  Future<void> _showLorebookEditor(GroupChatLorebookEntry entry) async {
    final name = TextEditingController(text: entry.name);
    final keywords = TextEditingController(text: entry.keywords.join(', '));
    final content = TextEditingController(text: entry.content);
    final priority = TextEditingController(text: entry.priority.toString());
    final depth = TextEditingController(text: entry.depth.toString());
    var enabled = entry.enabled;
    var recursive = entry.recursive;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('编辑世界书条目'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: '名称')),
              TextField(
                  controller: keywords,
                  decoration: const InputDecoration(labelText: '关键词（逗号分隔）')),
              TextField(
                  controller: content,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: '内容')),
              TextField(
                  controller: priority,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '优先级')),
              TextField(
                  controller: depth,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '插入深度')),
              SwitchListTile(
                  title: const Text('启用'),
                  value: enabled,
                  onChanged: (v) => setDialogState(() => enabled = v)),
              SwitchListTile(
                  title: const Text('允许递归触发'),
                  value: recursive,
                  onChanged: (v) => setDialogState(() => recursive = v)),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(
              onPressed: () {
                final keys = keywords.text
                    .split(RegExp(r'[,，]'))
                    .map((e) => e.trim())
                    .where((e) => e.isNotEmpty)
                    .toList();
                if (content.text.trim().isEmpty || keys.isEmpty) return;
                context
                    .read<GroupChatBloc>()
                    .add(GroupChatSaveLorebookEntry(entry.copyWith(
                      name: name.text.trim(),
                      content: content.text.trim(),
                      keywords: keys,
                      priority: int.tryParse(priority.text) ?? entry.priority,
                      depth: int.tryParse(depth.text) ?? entry.depth,
                      enabled: enabled,
                      recursive: recursive,
                    )));
                Navigator.pop(ctx);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditAIReplyDialog(GroupChatMessage message) {
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
              context.read<GroupChatBloc>().add(GroupChatEditAIReply(
                    groupId: _groupId,
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

  void _showRegenerateConfirm(GroupChatMessage message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重新生成'),
        content: const Text('AI 将生成一个新的候选回复，当前回复会保留在候选列表中。确定吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.read<GroupChatBloc>().add(GroupChatRegenerateMessage(
                    groupId: _groupId,
                    messageId: message.id,
                  ));
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirm(GroupChatMessage message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除消息'),
        content: const Text('确定要删除这条消息吗？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.read<GroupChatBloc>().add(GroupChatDeleteMessage(
                    groupId: _groupId,
                    messageId: message.id,
                  ));
            },
            style:
                TextButton.styleFrom(foregroundColor: const Color(0xFFE53935)),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  void _showGroupSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: Theme.of(ctx).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
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
                  // 群头像：点选后立即显示并持久化（存 docs/avatars，实时同步列表/详情）
                  StatefulBuilder(builder: (ctxAvatar, setAvatar) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Center(
                        child: AvatarPicker(
                          currentAvatar: _dialogAvatar ?? _session.avatarUrl,
                          onAvatarSelected: (path) {
                            setAvatar(() => _dialogAvatar = path);
                            context.read<GroupChatBloc>().add(
                                  GroupChatUpdateSession(
                                    groupId: _groupId,
                                    avatarUrl: path,
                                  ),
                                );
                          },
                          size: 72,
                        ),
                      ),
                    );
                  }),
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
                  const Divider(height: 24),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '聊天内容',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.account_tree_outlined),
                    title: const Text('聊天记录与分支'),
                    subtitle: const Text('切换记录，或从消息节点继续另一条时间线'),
                    trailing: const Icon(Icons.chevron_right, size: 18),
                    onTap: () {
                      Navigator.pop(ctx);
                      _showBranchManager();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.menu_book_outlined),
                    title: const Text('世界书'),
                    subtitle: const Text('按关键词把群聊设定自动注入 AI 上下文'),
                    trailing: const Icon(Icons.chevron_right, size: 18),
                    onTap: () {
                      Navigator.pop(ctx);
                      _showLorebookDialog();
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
                          subtitle: Text(
                              _strategyLabel(_session.activationStrategy) ??
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
                          subtitle:
                              const Text('AI 之间持续聊天（对标 SillyTavern Auto Mode）'),
                          value: _session.autoModeEnabled ?? false,
                          onChanged: (v) {
                            _dispatchConfig(autoModeEnabled: v);
                            setSheet(() {});
                          },
                        ),
                        ListTile(
                          leading: const Icon(Icons.timer_outlined),
                          title: const Text('自动接话间隔（按角色）'),
                          subtitle: const Text('为每个角色设置独立接话冷却时间'),
                          trailing: const Icon(Icons.chevron_right, size: 18),
                          onTap: () => _showCharacterAutoModeDelayPicker(),
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
    Map<String, int>? autoModeDelaysByCharacter,
  }) {
    context.read<GroupChatBloc>().add(GroupChatUpdateConfig(
          groupId: _groupId,
          activationStrategy: activationStrategy,
          generationMode: generationMode,
          allowSelfResponses: allowSelfResponses,
          autoModeDelay: autoModeDelay,
          autoModeEnabled: autoModeEnabled,
          disabledMemberIds: disabledMemberIds,
          autoModeDelaysByCharacter: autoModeDelaysByCharacter,
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
        return '合并角色卡(排除禁言)';
      case GroupGenerationMode.appendDisabled:
        return '合并角色卡(包括禁言)';
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

  Future<void> _showCharacterAutoModeDelayPicker() async {
    final chars = await _loadMemberCharacters(_session);
    if (!mounted) return;
    final delays = Map<String, int>.from(_session.autoModeDelaysByCharacter);
    final result = await showDialog<Map<String, int>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: const Text('角色自动接话间隔'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: chars.map((character) {
                final current = delays[character.id] ?? _session.autoModeDelay;
                return ListTile(
                  dense: true,
                  title: Text(character.name),
                  subtitle: Text('$current 秒'),
                  trailing: DropdownButton<int>(
                    value: current,
                    items: [5, 10, 15, 20, 30]
                        .map((v) =>
                            DropdownMenuItem(value: v, child: Text('$v 秒')))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setDialog(() => delays[character.id] = v);
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, delays),
                child: const Text('保存')),
          ],
        ),
      ),
    );
    if (result != null) {
      setState(() =>
          _session = _session.copyWith(autoModeDelaysByCharacter: result));
      _dispatchConfig(autoModeDelaysByCharacter: result);
    }
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
                        subtitle:
                            Text(b.branchId == _session.chatId ? '当前' : ''),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.arrow_forward),
                              tooltip: '切换到此记录',
                              onPressed: b.branchId == _session.chatId
                                  ? null
                                  : () => context.read<GroupChatBloc>().add(
                                      GroupChatSwitchBranch(
                                          groupId: _groupId,
                                          chatId: b.branchId)),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              tooltip: '删除记录',
                              onPressed: branches.length <= 1
                                  ? null
                                  : () => context.read<GroupChatBloc>().add(
                                      GroupChatDeleteBranch(
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
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    ).then((name) {
      if (name != null && name.isNotEmpty) {
        context
            .read<GroupChatBloc>()
            .add(GroupChatCreateBranch(groupId: _groupId, name: name));
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
              final member = _memberById(memberId);
              final avatar = AvatarResolver.imageWidget(
                member?.avatarUrl,
                width: 32,
                height: 32,
                fit: BoxFit.cover,
                onError: () => Icon(
                  isAi ? Icons.smart_toy : Icons.person,
                  size: 18,
                  color: isAi
                      ? Theme.of(ctx).colorScheme.tertiary
                      : Theme.of(ctx).colorScheme.primary,
                ),
              );
              return ListTile(
                dense: true,
                leading: CircleAvatar(
                  backgroundColor: isAi
                      ? Theme.of(ctx).colorScheme.tertiaryContainer
                      : Theme.of(ctx).colorScheme.primaryContainer,
                  child: avatar ??
                      Icon(
                        isAi ? Icons.smart_toy : Icons.person,
                        size: 18,
                        color: isAi
                            ? Theme.of(ctx).colorScheme.tertiary
                            : Theme.of(ctx).colorScheme.primary,
                      ),
                ),
                title: Text(isAi
                    ? 'AI 角色'
                    : (memberId == 'local_user' ? '我' : memberId)),
                subtitle: Text(isAi ? 'AI' : '用户'),
                trailing: isAi && memberId != 'local_user'
                    ? IconButton(
                        icon: const Icon(Icons.exit_to_app,
                            size: 18, color: Color(0xFFE53935)),
                        tooltip: '移出群聊',
                        onPressed: () {
                          context
                              .read<GroupChatBloc>()
                              .add(GroupChatRemoveMember(_groupId, memberId));
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
        future: RepositoryProvider.of<LocalStorageRepository>(ctx)
            .getAllAICharacters(),
        builder: (ctx, snap) {
          final all = snap.data ?? <AICharacter>[];
          final inGroup = _session.aiCharacterIds.toSet();
          final candidates = all.where((c) => !inGroup.contains(c.id)).toList();

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
                            context
                                .read<GroupChatBloc>()
                                .add(GroupChatAddMember(_groupId, ch.id));
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
        content: Text('确定要从消息页隐藏群聊"${_session.name}"吗？群聊和历史内容会保留，可在联系人中继续查看。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              context.read<GroupChatBloc>().add(GroupChatUpdateSession(
                    groupId: _groupId,
                    isHidden: true,
                  ));
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
  final String? avatarUrl;
  const _TypingIndicator({required this.name, this.avatarUrl});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final avatar = AvatarResolver.imageWidget(
      avatarUrl,
      width: 32,
      height: 32,
      fit: BoxFit.cover,
      onError: () => _initial(cs),
    );
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
            clipBehavior: Clip.antiAlias,
            child: avatar ?? _initial(cs),
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

  Widget _initial(ColorScheme cs) {
    return Center(
      child: Text(
        name.isNotEmpty ? name.substring(0, 1) : '?',
        style: TextStyle(
          color: cs.tertiary,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
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
