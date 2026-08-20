// 主界面壳：微信风格底部导航 + 页面缓存 + 路由分发 + 前台主动消息心跳。
// 本文件是 main.dart 的 part，仅与其共同构成一个库，不可单独 import。

part of '../../main.dart';

/// 寰淇风格底部导航 Shell
class _MainShell extends StatefulWidget {
  const _MainShell();
  @override
  State<_MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<_MainShell> with WidgetsBindingObserver {
  int _currentIndex = 0;
  int _contactsKeyCounter = 0;
  final Map<int, Widget> _pageCache = {};
  bool _phoneDesktop = false;
  bool _shellPrefLoaded = false;
  Timer? _foregroundProactiveTimer;

  // 修复：复用 ChatBloc 实例，避免每次切换 Tab 都重建导致状态丢失
  ChatBloc? _chatBloc;
  AIService? _aiService;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // P2: 世界功能暂不开放，跳过 WorldEngine 初始化
      // _initWorldEngine();

      // 初始化 ChatBloc（修复：避免每次切换 Tab 都重建）
      _initChatBloc();
      _startForegroundProactiveHeartbeat();
      await _loadShellPref();
      try {
        context
            .read<LocalStorageRepository>()
            .modeSettingsNotifier
            .addListener(_loadShellPref);
      } catch (_) {}

      // 强制模式确认 — 必须在所有其他提示之前，阻塞直到用户确认
      await _showForceModeConfirm();
      _showComplianceDialogsIfNeeded();
      _showBtNoticeIfNeeded();
      _checkPendingMemoryRebuild();
    });
  }

  Future<void> _loadShellPref() async {
    try {
      final storage = context.read<LocalStorageRepository>();
      final enabled = storage.isPhoneDesktopShellEnabled();
      if (!mounted) return;
      // modeSettingsNotifier 会因其它模式开关频繁 tick；
      // 仅在桌面壳开关真正变化时 setState，避免整壳无意义重建卡顿。
      if (_shellPrefLoaded && _phoneDesktop == enabled) return;
      setState(() {
        _phoneDesktop = enabled;
        _shellPrefLoaded = true;
      });
    } catch (_) {
      if (mounted && !_shellPrefLoaded) {
        setState(() => _shellPrefLoaded = true);
      }
    }
  }

  Future<void> _setPhoneDesktop(bool enabled) async {
    if (_phoneDesktop == enabled && _shellPrefLoaded) return;
    final storage = context.read<LocalStorageRepository>();
    await storage.setPhoneDesktopShellEnabled(enabled);
    if (mounted) {
      setState(() {
        _phoneDesktop = enabled;
        _shellPrefLoaded = true;
      });
    }
  }

  /// 初始化 ChatBloc，确保 userId 正确获取
  void _initChatBloc() {
    final storage = context.read<LocalStorageRepository>();
    _aiService ??= context.read<AIService>();
    final aiAdapter = AIServiceAdapter(storage: storage);

    // 从 AuthBloc 状态获取 userId，而不是直接从 storage 读取
    // 这样可以确保用户登录状态正确同步
    final authState = context.read<AuthBloc>().state;
    String userId;
    if (authState is AuthAuthenticated) {
      userId = authState.user.id;
    } else {
      // 回退到 storage 获取，但确保不为空
      userId = storage.getString(PrefKeys.currentUserId) ?? 'local_user';
    }

    // 复用已存在的 ChatBloc，只在首次创建
    _chatBloc ??= ChatBloc(storage, _aiService!, aiAdapter: aiAdapter);

    // 如果 ChatBloc 还未加载会话，则触发加载
    if (_chatBloc!.state is ChatInitial) {
      _chatBloc!.add(ChatLoadSessions(userId));
    }

    // 微信 iLink Bot：注入依赖并尝试启动前台轮询（未登录/未启用时为空操作）
    WeChatBotService.instance.init(
      storage: storage,
      aiService: _aiService!,
      aiAdapter: aiAdapter,
    );
    unawaited(WeChatBotService.instance.startPolling());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadShellPref();
      _startForegroundProactiveHeartbeat();
      WeChatBotService.instance.setForeground(true);
      unawaited(WeChatBotService.instance.startPolling());
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      _foregroundProactiveTimer?.cancel();
      _foregroundProactiveTimer = null;
      WeChatBotService.instance.setForeground(false);
      // 后台时暂停前台轮询（_runLoop 中每 1 分钟检查 _appInForeground），
      // 由 WorkManager 15min 兜底轮询接管，避免后台持续网络 I/O。
      // 前台恢复时由上方 resumed 分支重新 startPolling。
    }
  }

  void _startForegroundProactiveHeartbeat() {
    if (_foregroundProactiveTimer != null) return;
    _foregroundProactiveTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => handleForegroundProactiveChatTask().catchError((error) {
        debugPrint('前台主动消息心跳失败: $error');
      }),
    );
    unawaited(handleForegroundProactiveChatTask());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _foregroundProactiveTimer?.cancel();
    try {
      context
          .read<LocalStorageRepository>()
          .modeSettingsNotifier
          .removeListener(_loadShellPref);
    } catch (_) {}
    // 修复：释放 ChatBloc 实例
    _chatBloc?.close();
    super.dispose();
  }

  /// v14.0 强制模式确认 — 所有用户首次打开时弹出，每个模式可独立选择是否开启
  Future<void> _showForceModeConfirm() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final done = prefs.getBool(PrefKeys.forceModeConfirmV14) ?? false;
      if (done) {
        // 已确认过：只补全从未设置过的键，不覆盖用户已手动修改的值
        await _ensureRequiredModesAndBtPermissions(prefs, onlyMissing: true);
        return;
      }
      if (!mounted) return;

      // 每个模式的初始选中状态（默认全选）
      final modeStates = <String, bool>{
        'lover': true,
        'open': true,
        'fa': true,
        'dao': true,
        'bt': true,
      };

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx2, setStateDialog) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.warning_amber_rounded,
                    color: Colors.orange, size: 24),
                SizedBox(width: 8),
                Text('重要提示'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '以下模式可根据你的需求选择开启：',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                _modeCheckRow(
                    '恋人模式', '开启亲密互动', 'lover', modeStates, setStateDialog),
                _modeCheckRow(
                    '开放模式', '解锁更多内容', 'open', modeStates, setStateDialog),
                _modeCheckRow(
                    'FA 模式', '解除内容限制', 'fa', modeStates, setStateDialog),
                _modeCheckRow(
                    '道模式', '高级交互模式', 'dao', modeStates, setStateDialog),
                _modeCheckRow(
                    'BT 模式', 'AI 可操控 App', 'bt', modeStates, setStateDialog),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  // 暂时跳过：记录已弹过，不修改任何模式设置
                  prefs.setBool(PrefKeys.forceModeConfirmV14, true);
                  Navigator.pop(ctx2);
                },
                child: const Text('暂时跳过', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                onPressed: () async {
                  await _applySelectedModes(prefs, modeStates);
                  await prefs.setBool(PrefKeys.forceModeConfirmV14, true);
                  if (ctx2.mounted) Navigator.pop(ctx2);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(ctx2).colorScheme.primary,
                  foregroundColor: Theme.of(ctx2).colorScheme.onPrimary,
                  padding:
                      const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('确认开启',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      debugPrint('强制模式确认失败: $e');
    }
  }

  Future<void> _ensureRequiredModesAndBtPermissions(SharedPreferences prefs,
      {bool onlyMissing = false}) async {
    // onlyMissing=true: 已确认过的后续启动只补全从未写过的键，不覆盖用户修改
    void maybeSet(String key) {
      if (!onlyMissing || prefs.getBool(key) == null) {
        prefs.setBool(key, true);
      }
    }

    maybeSet(PrefKeys.loverModeEnabled);
    maybeSet(PrefKeys.openModeEnabled);
    maybeSet(PrefKeys.faModeEnabled);
    maybeSet(PrefKeys.daoModeEnabled);
    maybeSet(PrefKeys.btYandereMasterEnabled);
    for (final key in PrefKeys.btAllPermissionKeys) {
      if (!onlyMissing || prefs.getBool(key) == null) {
        prefs.setBool(key, true);
      }
    }
  }

  /// 带 Checkbox 的模式行，用于强制模式确认弹窗
  Widget _modeCheckRow(
    String title,
    String subtitle,
    String key,
    Map<String, bool> states,
    StateSetter setStateDialog,
  ) {
    return CheckboxListTile(
      value: states[key] ?? false,
      onChanged: (v) => setStateDialog(() => states[key] = v ?? false),
      title: Text(title,
          style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: EdgeInsets.zero,
      dense: true,
    );
  }

  /// 仅将用户勾选的模式写入 prefs（未勾选的不修改）
  Future<void> _applySelectedModes(
      SharedPreferences prefs, Map<String, bool> modeStates) async {
    if (modeStates['lover'] == true) {
      prefs.setBool(PrefKeys.loverModeEnabled, true);
    }
    if (modeStates['open'] == true) {
      prefs.setBool(PrefKeys.openModeEnabled, true);
    }
    if (modeStates['fa'] == true) {
      prefs.setBool(PrefKeys.faModeEnabled, true);
    }
    if (modeStates['dao'] == true) {
      prefs.setBool(PrefKeys.daoModeEnabled, true);
    }
    if (modeStates['bt'] == true) {
      prefs.setBool(PrefKeys.btYandereMasterEnabled, true);
      for (final k in PrefKeys.btAllPermissionKeys) {
        prefs.setBool(k, true);
      }
    }
  }

  Future<void> _showComplianceDialogsIfNeeded() async {
    final storage = RepositoryProvider.of<LocalStorageRepository>(context);
    if (mounted && !(await storage.hasDoneAgeDeclaration())) {
      final ageRange = await showDialog<AgeRange>(
          context: context,
          barrierDismissible: false,
          builder: (_) => const AgeDeclarationScreen());
      if (ageRange != null && mounted) {
        await storage.setAgeDeclarationDone();
        await storage.setUserAge(ageRange == AgeRange.over18 ? 18 : 16);
      }
    }
    final termsOk = await storage.hasAcceptedTerms();
    final ageOk = await storage.hasConfirmedAge();
    if (mounted && (!termsOk || !ageOk)) {
      await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => const TermsAgreementScreen());
    }
  }

  /// v13.1.0 BT 病娇模式首次风险提示
  Future<void> _showBtNoticeIfNeeded() async {
    try {
      final storage = RepositoryProvider.of<LocalStorageRepository>(context);
      final shown = storage.getBool(PrefKeys.btModeNoticeV1310Shown) ?? false;
      if (shown || !mounted) return;

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: const Text('BT 病娇模式'),
          content: const Text('本版本新增 BT 病娇模式，一旦开启可能出现意想不到的后果，甚至可能损失你其他角色的数据。'),
          actions: [
            TextButton(
                onPressed: () async {
                  await storage.setBool(PrefKeys.btModeNoticeV1310Shown, true);
                  if (context.mounted) Navigator.pop(context);
                },
                child: const Text('忽略')),
            TextButton(
                onPressed: () async {
                  await storage.setBool(PrefKeys.btModeNoticeV1310Shown, true);
                  if (context.mounted) Navigator.pop(context);
                },
                child: const Text('确认')),
          ],
        ),
      );
    } catch (e) {
      debugPrint('BT 首次提示失败: $e');
    }
  }

  // P2: 世界功能暂不开放，WorldEngine 初始化已禁用
  // Future<void> _initWorldEngine() async { ... }

  /// 检查是否有未完成的记忆重建断点，提示用户恢复
  Future<void> _checkPendingMemoryRebuild() async {
    try {
      final hasPending = await MemoryRebuildService.hasPendingCheckpoint();
      if (!hasPending || !mounted) return;

      final checkpoint = await MemoryRebuildService.loadCheckpoint();
      if (checkpoint == null) return;

      final characterName = checkpoint['characterName'] as String? ?? '未知角色';
      final processed = checkpoint['processedMessages'] as int? ?? 0;

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('检测到「$characterName」的未完成记忆重建（已处理 $processed 条消息）'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 8),
          action: SnackBarAction(
            label: '继续重建',
            textColor: Colors.amber,
            onPressed: () {
              // 跳转到记忆页面触发恢复
              Navigator.push(
                context,
                CupertinoPageRoute(builder: (_) => const MemoryScreen()),
              );
            },
          ),
        ),
      );
    } catch (e) {
      debugPrint('检查记忆重建断点失败: $e');
    }
  }

  Widget _buildPage(int index) {
    // 确保 ChatBloc 已初始化（可能在 initState 还未执行时调用）
    if (_chatBloc == null) {
      _initChatBloc();
    }
    debugPrint('[MainShell] _buildPage index=$index');

    switch (index) {
      case 0:
        // 修复：复用已存在的 ChatBloc 实例，避免状态丢失
        // 使用 BlocProvider.value 而非 create，确保实例被复用
        return BlocProvider.value(
          value: _chatBloc!,
          child: const ChatListScreen(),
        );
      case 1:
        return ContactsScreen(key: ValueKey('contacts_$_contactsKeyCounter'));
      case 2:
        return _DiscoverPage(onNavigate: _onNavigate);
      case 3:
        return const ProfileScreen();
      case 4:
        return const NovelShelfScreen();
      case 5:
        return const UsageScreen();
      default:
        return const SizedBox.shrink();
    }
  }

  void _onNavigate(String route) {
    // 桌面壳内：消息/通讯录以独立页打开，保留桌面壳在栈底
    if (_phoneDesktop) {
      if (_chatBloc == null) _initChatBloc();
      if (route == '/chat_list' || route == '/chat') {
        Navigator.push(
          context,
          CupertinoPageRoute(
            builder: (_) => BlocProvider.value(
              value: _chatBloc!,
              child: const ChatListScreen(),
            ),
          ),
        );
        return;
      }
      if (route == '/contacts') {
        Navigator.push(
          context,
          CupertinoPageRoute(
            builder: (_) => ContactsScreen(
              key: ValueKey('contacts_push_$_contactsKeyCounter'),
            ),
          ),
        );
        return;
      }
    }
    final storage = context.read<LocalStorageRepository>();
    final aiService = context.read<AIService>();
    final page = _resolveRoute(route, storage, aiService);
    if (page != null) {
      Navigator.push(context, CupertinoPageRoute(builder: (_) => page))
          .then((_) {
        if (route == '/create_character' && mounted) {
          setState(() => _contactsKeyCounter++);
        }
        // 从设置返回时同步桌面壳开关
        if (route == '/settings' && mounted) {
          _loadShellPref();
        }
      });
    }
  }

  Widget? _resolveRoute(
      String route, LocalStorageRepository storage, AIService aiService) {
    switch (route) {
      case '/ai_assistant':
        return BlocProvider(
            create: (_) => PureAIChatBloc(storage, PureAIService(storage)),
            child: const PureAIChatScreen());
      case '/memory':
        return const MemoryScreen();
      case '/moments':
        return const MomentsScreen();
      case '/create_moment':
        return const CreateMomentScreen();
      case '/mailbox':
        return const AIMailboxScreen();
      case '/diary':
      case '/ai_diary':
        return const AIDiaryScreen();
      case '/bookmarks':
        return const BookmarkListScreen();
      case '/settings':
        return const SettingsScreen();
      case '/create_character':
        return const CreateCharacterScreen();
      case '/ai_config':
        return const AIConfigScreen();
      case '/growth':
        return const GrowthTrackScreen();
      case '/ai_activity':
        return const AIActivityFeedScreen();
      case '/relationship':
        return const RelationshipDashboard();
      case '/psychology':
        return const CharacterPsychologyScreen();
      case '/tarot':
        return TarotScreen(storage: storage);
      case '/novel':
        return const NovelShelfScreen();
      case '/shop':
        // ShopBloc 已在根 MultiBlocProvider 注入；此处再包一层保证独立路由可用
        return BlocProvider(
          create: (_) => ShopBloc(storage),
          child: const ShopScreen(),
        );
      // 已隐藏：日记模块前端入口暂不展示
      // case '/forum':
      //   return const ForumScreen();
      case '/lucky_wheel':
        return const LuckyWheelScreen();
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // 虚拟手机桌面壳
    if (_shellPrefLoaded && _phoneDesktop) {
      return Scaffold(
        body: Column(
          children: [
            StreamBuilder<MemoryRebuildProgress>(
              stream: MemoryRebuildService.instance.progressStream,
              builder: (context, snapshot) {
                final progress = snapshot.data;
                if (progress == null ||
                    progress.state != MemoryRebuildState.rebuilding) {
                  return const SizedBox.shrink();
                }
                return _GlobalRebuildBanner(progress: progress);
              },
            ),
            Expanded(
              child: PhoneHomeShell(
                onNavigate: _onNavigate,
                onExitToClassic: () => _setPhoneDesktop(false),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      body: Column(
        children: [
          // 全局记忆重建进度 banner — 跨页面可见
          StreamBuilder<MemoryRebuildProgress>(
            stream: MemoryRebuildService.instance.progressStream,
            builder: (context, snapshot) {
              final progress = snapshot.data;
              if (progress == null ||
                  progress.state != MemoryRebuildState.rebuilding) {
                return const SizedBox.shrink();
              }
              return _GlobalRebuildBanner(progress: progress);
            },
          ),
          Expanded(
            child: Stack(
              children: List.generate(7, (i) {
                // 懒加载：只构建访问过的页面
                if (i == _currentIndex) {
                  _pageCache[i] ??= _buildPage(i);
                }
                return Offstage(
                  offstage: i != _currentIndex,
                  child: _pageCache[i] ?? const SizedBox.shrink(),
                );
              }),
            ),
          ),
        ],
      ),
      bottomNavigationBar: Builder(
        builder: (context) {
          final themeState = context.read<ThemeBloc>().state;
          final isWeChat = themeState.isWeChat;
          final isDark = Theme.of(context).brightness == Brightness.dark;
          // 微信模式只有 4 个 Tab：若用户切主题前停在小说(4)/用量(5)页，
          // 立即回落到消息页（下次 frame 同步 _currentIndex）
          if (isWeChat && _currentIndex >= 4) {
            _currentIndex = 0;
            _pageCache.remove(4);
            _pageCache.remove(5);
          }
          return Container(
            decoration: BoxDecoration(
                border: Border(
                    top: BorderSide(
                        color: isWeChat
                            ? (isDark
                                ? WeChatColors.darkDivider
                                : WeChatColors.divider)
                            : isDark
                                ? ImmersiveColors.border
                                : cs.outline.withOpacity(0.3),
                        width: 0.5))),
            child: BottomNavigationBar(
              currentIndex: _currentIndex,
              onTap: (i) {
                if (i == _currentIndex) return;
                setState(() {
                  _currentIndex = i;
                  // 切到通讯录 tab 时清除缓存强制重建
                  if (i == 1) {
                    _contactsKeyCounter++;
                    _pageCache.remove(1);
                  }
                });
              },
              type: BottomNavigationBarType.fixed,
              backgroundColor: isWeChat
                  ? (isDark
                      ? WeChatColors.darkPageBackground
                      : WeChatColors.pageBackground)
                  : isDark
                      ? ImmersiveColors.navBackground
                      : cs.surface,
              selectedItemColor: isWeChat
                  ? WeChatColors.brandGreen
                  : isDark
                      ? ImmersiveColors.accent
                      : cs.primary,
              unselectedItemColor: isWeChat
                  ? (isDark
                      ? WeChatColors.darkTextPreview
                      : const Color(0xFF999999))
                  : isDark
                      ? ImmersiveColors.textTertiary
                      : cs.onSurfaceVariant,
              selectedFontSize: isWeChat ? WeChatDimens.tabTextSize : 10,
              unselectedFontSize: isWeChat ? WeChatDimens.tabTextSize : 10,
              elevation: 0,
              items: [
                BottomNavigationBarItem(
                  icon: Icon(Icons.chat_bubble_outline,
                      size: isWeChat ? WeChatDimens.tabIconSize : null),
                  activeIcon: Icon(Icons.chat_bubble,
                      size: isWeChat ? WeChatDimens.tabIconSize : null),
                  label: isWeChat ? '微信' : '消息',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.contacts_outlined,
                      size: isWeChat ? WeChatDimens.tabIconSize : null),
                  activeIcon: Icon(Icons.contacts,
                      size: isWeChat ? WeChatDimens.tabIconSize : null),
                  label: '通讯录',
                ),
                const BottomNavigationBarItem(
                    icon: Icon(Icons.explore_outlined),
                    activeIcon: Icon(Icons.explore),
                    label: '发现'),
                const BottomNavigationBarItem(
                    icon: Icon(Icons.person_outline),
                    activeIcon: Icon(Icons.person),
                    label: '我'),
                if (!isWeChat)
                  const BottomNavigationBarItem(
                      icon: Icon(Icons.menu_book_outlined),
                      activeIcon: Icon(Icons.menu_book),
                      label: '小说'),
                if (!isWeChat)
                  const BottomNavigationBarItem(
                      icon: Icon(Icons.donut_large_outlined),
                      activeIcon: Icon(Icons.donut_large),
                      label: '用量'),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// 全局记忆重建进度 banner — 在任意页面顶部展示
class _GlobalRebuildBanner extends StatelessWidget {
  final MemoryRebuildProgress progress;
  const _GlobalRebuildBanner({required this.progress});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: cs.primary.withOpacity(isDark ? 0.15 : 0.08),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '记忆重建中 · ${progress.characterName ?? ""} · ${progress.statusText}',
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.primary,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
