// 番外小剧场（拆分生成，同库 part）
part of '../chat_detail_screen.dart';

mixin _StateSideStory on State<ChatDetailScreen>, _StateCore, _StateLoadCore, _StateSelection {
  /// 当前是否为番外小剧场（平行会话层）。
  bool get _isSideStory => widget.session.isSideStory;


  /// 番外小剧场顶部标识横幅（剧情不纳入主线）。
  Widget _buildSideStoryBanner(ColorScheme colorScheme, bool isDark) {
    final accent = isDark ? const Color(0xFFE6C88A) : const Color(0xFF8A6D3B);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2A2418) : const Color(0xFFF5EBD7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withOpacity(0.35)),
      ),
      child: Row(
        children: [
          Icon(Icons.auto_awesome, size: 15, color: accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '番外・平行小剧场｜剧情不纳入主线',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: accent,
                letterSpacing: 0.4,
              ),
            ),
          ),
          TextButton(
            onPressed: _exitSideStory,
            style: TextButton.styleFrom(
              foregroundColor: accent,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: const Text('退出番外', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }


  void _exitSideStory() {
    tapHaptic();
    Navigator.pop(context);
  }


  bool _isSideStoryCommand(String text) {
    final t = text.trim();
    if (t.isEmpty || !t.contains('番外')) return false;
    final lower = t.toLowerCase();
    final hasDollar = lower.startsWith('\$');
    final isPauseDirective = lower.contains('暂停当前剧情') ||
        lower.contains('暂停主线') ||
        lower.contains('暂停剧情');
    final isExplicitOpen =
        _sideStoryOpenPrefix.hasMatch(lower) && lower.contains('番外');
    return hasDollar || isPauseDirective || isExplicitOpen;
  }


  /// 开启番外小剧场：创建同角色内的临时平行会话层并跳转。
  Future<void> _startSideStory({String? initialMessage}) async {
    if (_isSideStory) return;
    final storage = RepositoryProvider.of<LocalStorageRepository>(context);
    final user = (context.read<AuthBloc>().state as AuthAuthenticated).user;
    final main = _currentSession ?? widget.session;

    String? title;
    if (initialMessage == null) {
      final controller = TextEditingController();
      final entered = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('开启番外小剧场'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 20,
            decoration: const InputDecoration(
              hintText: '给这个番外起个名字（可留空）',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('开启'),
            ),
          ],
        ),
      );
      if (entered != true || !mounted) return;
      title = controller.text.trim().isEmpty ? null : controller.text.trim();
    }

    final now = DateTime.now();
    final sideStory = ChatSession(
      id: const Uuid().v4(),
      userId: user.id,
      aiCharacterId: main.aiCharacterId,
      aiCharacterName: main.aiCharacterName,
      aiCharacterAvatar: main.aiCharacterAvatar,
      createdAt: now,
      updatedAt: now,
      sessionType: 'side_story',
      parentChatId: main.id,
      sideStoryTitle: title,
      intimacyMode: main.intimacyMode,
      novelMode: main.novelMode,
    );
    await storage.saveChatSession(sideStory);
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatDetailScreen(
          session: sideStory,
          initialMessage: initialMessage,
        ),
      ),
    );
  }


  /// 番外回看面板：列出本主线下的全部番外，可进入或删除。
  Future<void> _openSideStoryList() async {
    if (_isSideStory) return;
    final storage = RepositoryProvider.of<LocalStorageRepository>(context);
    final sessions = await storage.getSideStorySessions(widget.session.id);
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _SideStoryListSheet(
        sessions: sessions,
        onOpen: (s) {
          Navigator.pop(ctx);
          _openSideStorySession(s);
        },
        onDelete: (s) {
          Navigator.pop(ctx);
          _deleteSideStory(s);
        },
      ),
    );
  }


  Future<void> _openSideStorySession(ChatSession sideStory) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatDetailScreen(session: sideStory),
      ),
    );
  }


  Future<void> _deleteSideStory(ChatSession sideStory) async {
    final storage = RepositoryProvider.of<LocalStorageRepository>(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除番外'),
        content: Text('确定删除「${sideStory.sideStoryTitle ?? '未命名番外'}」吗？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await storage.deleteChatSessionCascade(sideStory.id);
    if (!mounted) return;
    _openSideStoryList();
  }

}
