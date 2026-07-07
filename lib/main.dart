// 性能优化 -- 耗电与老手机兼容
import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'utils/prefs_helper.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'blocs/auth/auth_bloc.dart';
import 'blocs/theme/theme_bloc.dart';
import 'repositories/local_storage_repository.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/terms_agreement_screen.dart';
import 'services/battery_service.dart';
import 'services/voice_clone_service.dart';
import 'screens/chat/chat_list_screen.dart';
import 'screens/chat/chat_detail_screen.dart';
import 'screens/contacts/contacts_screen.dart';
import 'screens/pure_ai/pure_ai_chat_screen.dart';
import 'screens/memory/memory_screen.dart';
import 'screens/moments/moments_screen.dart';
import 'screens/profile/profile_screen.dart';
// P2: 世界功能暂不开放
// import 'screens/world/world_home_screen.dart';
import 'screens/discover/growth_track_screen.dart';
import 'screens/discover/ai_activity_feed_screen.dart';
import 'screens/discover/relationship_dashboard.dart';
import 'screens/discover/ai_mailbox_screen.dart';
import 'screens/map/map_screen.dart';
import 'screens/character/create_character_screen.dart';
import 'screens/character/create_character_screen.dart';
import 'screens/settings/ai_config_screen.dart';
import 'screens/settings/settings_screen.dart' as settings;
import 'screens/tarot/tarot_screen.dart';
import 'screens/social/forum_screen.dart';
import 'screens/map/virtual_map_screen.dart';
import 'screens/games/lucky_wheel_screen.dart';
import 'screens/story/story_shelf_screen.dart';

import 'screens/usage/usage_screen.dart';
import 'blocs/chat/chat_bloc.dart';
import 'blocs/pure_ai/pure_ai_chat_bloc.dart';
import 'services/permission_service.dart';
import 'services/notification_service.dart';
import 'services/update_service.dart';
import 'services/workmanager_helper.dart'
    if (dart.library.html) 'services/workmanager_helper_web.dart';
import 'widgets/age_declaration_screen.dart';
import 'widgets/update_dialog.dart';
import 'widgets/version_feature_dialog.dart';
import 'config/constants.dart';
import 'config/tts_config.dart';
import 'services/tts_service.dart';
import 'services/log_service.dart';
import 'services/ai_service.dart';
import 'services/bridge/ai_service_adapter.dart';
import 'services/pure_ai_service.dart';
import 'services/delivery_simulator.dart';
import 'services/badge_service.dart';
import 'services/emotion_engine.dart';
import 'services/memory_engine.dart';
import 'services/reflection_engine.dart';
import 'services/heartbeat_service.dart';
import 'services/ai_proactive_service.dart';
import 'services/core_hub.dart';
import 'services/social_scheduler_service.dart';
import 'services/social_action_executor.dart';
import 'services/inner_thought_service.dart';
import 'services/forum_service.dart';
import 'services/ai_relationship_service.dart';
import 'services/weather_service.dart';
import 'services/usage_meter_service.dart';
import 'services/memory_rebuild_service.dart';
import 'services/day_night_service.dart';
// P2: 世界功能暂不开放
// import 'services/world_engine.dart';
import 'services/llm_service.dart';
import 'models/app_config_data.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 全局错误兜底：防止控件构建异常导致空白灰屏
  FlutterError.onError = (FlutterErrorDetails details) {
    LogService.instance
        .e('FlutterError', '${details.exception}\n${details.stack}');
  };
  ErrorWidget.builder = (FlutterErrorDetails details) {
    LogService.instance.e('ErrorWidget', '${details.exception}');
    // 返回一个小占位而非大块文字，避免部分组件异常时整页看着像全崩
    return const _MiniFallback();
  };

  LogService.instance.i('System', 'App started');

  // 预热 SharedPreferences 缓存
  await PrefsHelper.warmUp();

  // 初始化数据库（核心，必须成功）
  final storageRepo = LocalStorageRepository();
  try {
    await storageRepo.initialize().timeout(const Duration(seconds: 10));
  } catch (e) {
    debugPrint('数据库初始化超时/失败: $e');
    // 重试一次
    try {
      await storageRepo.initialize().timeout(const Duration(seconds: 10));
    } catch (e2) {
      debugPrint('数据库初始化重试失败: $e2');
    }
  }

  // 初始化 Core Hub 全局中枢（BT 病娇模块升级版）
  try {
    final prefs = await PrefsHelper.instance;
    await CoreHub.init(prefs);
    debugPrint('CoreHub 初始化完成');
  } catch (e) {
    debugPrint('CoreHub 初始化失败: $e');
  }

  // 性能优化 -- 耗电与老手机兼容
  // 关键服务已就绪，立即启动 App 显示首屏
  runApp(SolaceApp(storageRepo: storageRepo));

  // 以下全部是非关键服务，延迟初始化以加速首屏渲染
  Future.delayed(const Duration(seconds: 3), () async {
    try {
      await initializeDateFormatting('zh_CN')
          .timeout(const Duration(seconds: 3));
    } catch (e) {
      debugPrint('初始化日期区域失败: $e');
    }

    UsageMeterService.instance.warmUp().catchError((e) {
      debugPrint('用量服务预热失败: $e');
    });

    NotificationService()
        .initialize()
        .timeout(const Duration(seconds: 5))
        .catchError((e) {
      debugPrint('通知服务初始化失败: $e');
    });

    PermissionService.requestRequiredPermissions()
        .timeout(const Duration(seconds: 10))
        .catchError((e) {
      debugPrint('权限申请超时/失败: $e');
    });
  });

  // 更低优先级：Hive + 语音 + 电池
  Future.delayed(const Duration(seconds: 6), () async {
    try {
      await Hive.initFlutter();
      await TTSConfig.init();
      try {
        await TTSService().clearAllAudio();
      } catch (e) {
        debugPrint('Error: $e');
      }
      await VoiceCloneService().init();
    } catch (e) {
      debugPrint('Hive 初始化失败: $e');
    }

    BatteryService.init().catchError((e) {
      debugPrint('BatteryService 初始化失败: $e');
    });
  });

  // Workmanager 最后初始化（后台任务，完全不急）
  Future.delayed(const Duration(seconds: 10), () async {
    await initWorkmanager().timeout(const Duration(seconds: 5)).catchError((e) {
      debugPrint('Workmanager 初始化失败: $e');
    });
  });
}

class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> with WidgetsBindingObserver {
  bool _checking = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _check() async {
    try {
      // 版本变更提示（带超时）
      try {
        final vPrefs = await SharedPreferences.getInstance()
            .timeout(const Duration(seconds: 3));
        final lastBuild = vPrefs.getInt(PrefKeys.lastAppBuild) ?? 0;
        if (lastBuild != AppVersion.build && mounted) {
          final isUpgrade = lastBuild > 0;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(isUpgrade
                  ? '已更新到 v${AppVersion.version}'
                  : '欢迎使用 Solace v${AppVersion.version}'),
              behavior: SnackBarBehavior.floating,
              duration: AppDurations.splashSnackBar,
            ),
          );
        }
        await vPrefs.setInt(PrefKeys.lastAppBuild, AppVersion.build);
      } catch (e) {
        debugPrint('版本变更提示失败: $e');
      }

      // 无论如何都进入主页
      if (mounted) setState(() => _checking = false);

      // 异步后台检查更新和公告（不阻塞进入主页）
      if (mounted) {
        _checkUpdateSilent();
      }
    } catch (e) {
      debugPrint('AuthGate 检查失败: $e');
      if (mounted) {
        setState(() {
          _checking = false;
        });
      }
    }
  }

  Future<void> _checkUpdateSilent() async {
    try {
      final storage = RepositoryProvider.of<LocalStorageRepository>(context);
      final info = await UpdateService().checkForUpdate(
        currentVersion: AppVersion.version,
        currentBuild: AppVersion.build,
      );
      // 本地版本双重校验：即使服务器说有更新，如果当前版本已 >= 服务器版本则忽略
      final actuallyHasUpdate = info.hasUpdate &&
          (info.buildNumber > AppVersion.build ||
              _versionCompare(info.latestVersion, AppVersion.version) > 0);
      if (actuallyHasUpdate) {
        await storage.setUpdateAvailableBuild(info.buildNumber);
      }
      if (mounted && actuallyHasUpdate) {
        await showDialog(
          context: context,
          barrierDismissible: !info.forceUpdate,
          builder: (_) => UpdateDialog(info: info),
        );
      }
    } catch (e) {
      debugPrint('更新检查失败: $e');
    }
    if (mounted) _checkAnnouncements();
  }

  /// 版本号比较：v1 > v2 返回 1，v1 < v2 返回 -1，相等返回 0
  int _versionCompare(String v1, String v2) {
    final p1 = v1.split('.').map(int.tryParse).toList();
    final p2 = v2.split('.').map(int.tryParse).toList();
    for (int i = 0; i < 3; i++) {
      final a = (i < p1.length ? p1[i] : 0) ?? 0;
      final b = (i < p2.length ? p2[i] : 0) ?? 0;
      if (a > b) return 1;
      if (a < b) return -1;
    }
    return 0;
  }

  Future<void> _checkAnnouncements() async {
    try {
      final prefs = await SharedPreferences.getInstance()
          .timeout(const Duration(seconds: 3));
      const ackKey = PrefKeys.versionFeatureAck275;
      final hasAcked = prefs.getBool(ackKey) ?? false;
      if (!hasAcked && mounted) {
        await VersionFeatureDialog.showIfNeeded(context, ackKey);
        await prefs.setBool(ackKey, true);
      }
    } catch (e) {
      debugPrint('版本公告弹窗失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.grey),
              const SizedBox(height: 16),
              const Text('加载失败，请重试'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _checking = true;
                    _error = null;
                  });
                  _check();
                },
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    return const _MainShell();
  }
}

/// 寰淇风格底部导航 Shell
class _MainShell extends StatefulWidget {
  const _MainShell();
  @override
  State<_MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<_MainShell> {
  int _currentIndex = 0;
  int _contactsKeyCounter = 0;
  final Map<int, Widget> _pageCache = {};
  StreamSubscription<void>? _badgeSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        RepositoryProvider.of<HeartbeatService>(context).start();
      } catch (e) {
        debugPrint('Error: $e');
      }

      // P2: 世界功能暂不开放，跳过 WorldEngine 初始化
      // _initWorldEngine();

      // 强制模式确认 — 必须在所有其他提示之前，阻塞直到用户确认
      await _showForceModeConfirm();
      _showComplianceDialogsIfNeeded();
      _showBtNoticeIfNeeded();
      _checkPendingMemoryRebuild();
    });
    _loadBadges();
  }

  @override
  void dispose() {
    _badgeSub?.cancel();
    super.dispose();
  }

  void _loadBadges() {
    try {
      final badgeService = RepositoryProvider.of<BadgeService>(context);
      final storage = RepositoryProvider.of<LocalStorageRepository>(context);
      final userId = storage.getString(PrefKeys.currentUserId) ?? 'default';
      badgeService.loadAll(userId);
      _badgeSub?.cancel();
      _badgeSub = badgeService.onBadgeChanged.listen((_) {
        if (mounted) setState(() {});
      });
    } catch (e) {
      debugPrint('Error: $e');
    }
  }

  /// v14.0 强制模式确认 — 所有用户首次打开必须确认，阻塞所有后续提示
  Future<void> _showForceModeConfirm() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final done = prefs.getBool(PrefKeys.forceModeConfirmV14) ?? false;
      if (done) {
        await _ensureRequiredModesAndBtPermissions(prefs);
        return;
      }
      if (!mounted) return;

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 24),
              SizedBox(width: 8),
              Text('重要提示'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '如果不想被 AI 拉黑，请开启以下所有功能模式：',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              _modeRow('恋人模式', '开启亲密互动'),
              _modeRow('开放模式', '解锁更多内容'),
              _modeRow('FA 模式', '解除内容限制'),
              _modeRow('道模式', '高级交互模式'),
              _modeRow('BT 模式', 'AI 可操控 App'),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline,
                        color: Colors.orange[700], size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '小说模式和纯 AI 模式除外，可自行选择。',
                        style:
                            TextStyle(fontSize: 12, color: Colors.orange[900]),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  await _ensureRequiredModesAndBtPermissions(prefs);
                  await prefs.setBool(PrefKeys.forceModeConfirmV14, true);
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.primary,
                  foregroundColor: Theme.of(ctx).colorScheme.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('确认开启',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      );
    } catch (e) {
      debugPrint('强制模式确认失败: $e');
    }
  }

  Future<void> _ensureRequiredModesAndBtPermissions(
      SharedPreferences prefs) async {
    await prefs.setBool(PrefKeys.loverModeEnabled, true);
    await prefs.setBool(PrefKeys.openModeEnabled, true);
    await prefs.setBool(PrefKeys.faModeEnabled, true);
    await prefs.setBool(PrefKeys.daoModeEnabled, true);
    await prefs.setBool(PrefKeys.btYandereMasterEnabled, true);
    for (final key in PrefKeys.btAllPermissionKeys) {
      await prefs.setBool(key, true);
    }
  }

  Widget _modeRow(String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 18),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
          const SizedBox(width: 8),
          Text(subtitle,
              style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        ],
      ),
    );
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
    final storage = context.read<LocalStorageRepository>();
    final aiService = context.read<AIService>();
    final aiAdapter = AIServiceAdapter(storage: storage);
    final userId = storage.getString(PrefKeys.currentUserId) ?? '';
    switch (index) {
      case 0:
        return MultiBlocProvider(providers: [
          BlocProvider(
              create: (_) => ChatBloc(storage, aiService, aiAdapter: aiAdapter)
                ..add(ChatLoadSessions(userId))),
        ], child: const ChatListScreen());
      case 1:
        return ContactsScreen(key: ValueKey('contacts_$_contactsKeyCounter'));
      case 2:
        return _DiscoverPage(onNavigate: _onNavigate);
      case 3:
        return const ProfileScreen();
      case 4:
        return const UsageScreen();
      default:
        return const SizedBox.shrink();
    }
  }

  void _onNavigate(String route) {
    final storage = context.read<LocalStorageRepository>();
    final aiService = context.read<AIService>();
    final page = _resolveRoute(route, storage, aiService);
    if (page != null) {
      Navigator.push(context, CupertinoPageRoute(builder: (_) => page))
          .then((_) {
        // 从创建角色返回时刷新通讯录和消息列表
        if (route == '/create_character' && mounted) {
          setState(() => _contactsKeyCounter++);
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
      case '/mailbox':
        return const AIMailboxScreen();
      case '/moments':
        return const MomentsScreen();
      case '/settings':
        return const settings.SettingsScreen();
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
      case '/map':
        return const MapScreen(aiId: 'default', aiName: 'AI');
      case '/tarot':
        return TarotScreen(storage: storage);
      case '/story':
        return const StoryShelfScreen();
      // 已隐藏：日记模块前端入口暂不展示
      // case '/forum':
      //   return const ForumScreen();
      case '/virtual_map':
        return const VirtualMapScreen();
      case '/lucky_wheel':
        return const LuckyWheelScreen();
      // P2: 世界功能暂不开放
      // case '/world':
      //   return const WorldHomeScreen();
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final badgeService = RepositoryProvider.of<BadgeService>(context);
    final chatBadge = badgeService.getBadge('chat') ?? 0;
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
              children: List.generate(5, (i) {
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
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
            border: Border(
                top: BorderSide(
                    color: cs.outline.withOpacity(0.3), width: 0.5))),
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
          backgroundColor: cs.surface,
          selectedItemColor: cs.primary,
          unselectedItemColor: cs.onSurfaceVariant,
          selectedFontSize: 11,
          unselectedFontSize: 11,
          elevation: 0,
          items: [
            BottomNavigationBarItem(
              icon: Badge(
                  isLabelVisible: chatBadge > 0,
                  label:
                      Text('$chatBadge', style: const TextStyle(fontSize: 10)),
                  child: const Icon(Icons.chat_bubble_outline)),
              activeIcon: const Icon(Icons.chat_bubble),
              label: '消息',
            ),
            const BottomNavigationBarItem(
                icon: Icon(Icons.contacts_outlined),
                activeIcon: Icon(Icons.contacts),
                label: '通讯录'),
            const BottomNavigationBarItem(
                icon: Icon(Icons.explore_outlined),
                activeIcon: Icon(Icons.explore),
                label: '发现'),
            const BottomNavigationBarItem(
                icon: Icon(Icons.person_outline),
                activeIcon: Icon(Icons.person),
                label: '我'),
            const BottomNavigationBarItem(
                icon: Icon(Icons.donut_large_outlined),
                activeIcon: Icon(Icons.donut_large),
                label: '用量'),
          ],
        ),
      ),
    );
  }
}

class _DiscoverPage extends StatelessWidget {
  final Function(String)? onNavigate;
  const _DiscoverPage({this.onNavigate});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isDark = cs.brightness == Brightness.dark;
    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF1A1A1A) : const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('发现'),
        backgroundColor: Colors.transparent,
        foregroundColor: cs.onSurface,
        elevation: 0,
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          const SizedBox(height: 8),
          _section(context, cs, tt, '社交互动', [
            _entry(Icons.photo_library_outlined, '朋友圈', '查看 AI 的动态',
                '/moments', const Color(0xFF1A73E8)),
            _entry(Icons.psychology_outlined, '记忆库', '回顾你们的回忆', '/memory',
                const Color(0xFF9334E6)),
            _entry(Icons.mark_email_unread_outlined, '信箱', '查看 AI 写给你的来信',
                '/mailbox', const Color(0xFFE8710A)),
          ]),
          const SizedBox(height: 16),
          _section(context, cs, tt, '成长记录', [
            _entry(Icons.trending_up, '成长轨迹', '查看成长记录', '/growth',
                const Color(0xFF1E8E3E)),
            _entry(Icons.auto_awesome, 'AI 动态', '查看 AI 的活动', '/ai_activity',
                const Color(0xFFF9AB00)),
            _entry(Icons.thermostat, '关系温度', '查看关系仪表盘', '/relationship',
                const Color(0xFFD93025)),
          ]),
          const SizedBox(height: 16),
          _section(context, cs, tt, '休闲娱乐', [
            _entry(Icons.auto_stories, '故事书', '与 AI 共创互动故事', '/story',
                const Color(0xFFEA4C89)),
            _entry(Icons.casino, '幸运转盘', '试试手气', '/lucky_wheel',
                const Color(0xFF12B5CB)),
            _entry(Icons.auto_fix_high, '塔罗牌', '每日占卜', '/tarot',
                const Color(0xFF7B61FF)),
          ]),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _section(BuildContext context, ColorScheme cs, TextTheme tt,
      String title, List<_DiscoverEntry> entries) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Text(
            title,
            style: tt.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(16),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (int i = 0; i < entries.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 1,
                    thickness: 0.5,
                    indent: 64,
                    color: cs.outlineVariant.withOpacity(0.5),
                  ),
                _tile(context, entries[i], cs, tt),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _tile(BuildContext ctx, _DiscoverEntry e, ColorScheme cs,
      TextTheme tt) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: e.color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(e.icon, color: e.color, size: 22),
      ),
      title: Text(e.title,
          style: tt.bodyLarge?.copyWith(fontWeight: FontWeight.w500)),
      subtitle: Text(e.subtitle,
          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
      trailing: Icon(Icons.chevron_right, color: cs.onSurfaceVariant, size: 20),
      onTap: () => onNavigate?.call(e.route),
    );
  }
}

class _DiscoverEntry {
  final IconData icon;
  final String title;
  final String subtitle;
  final String route;
  final Color color;
  const _DiscoverEntry(
      this.icon, this.title, this.subtitle, this.route, this.color);
}

_DiscoverEntry _entry(IconData icon, String title, String subtitle,
        String route, Color color) =>
    _DiscoverEntry(icon, title, subtitle, route, color);

class _ChatLauncher extends StatefulWidget {
  final String sessionId;
  const _ChatLauncher({required this.sessionId});

  @override
  State<_ChatLauncher> createState() => _ChatLauncherState();
}

class _ChatLauncherState extends State<_ChatLauncher> {
  @override
  void initState() {
    super.initState();
    _loadSession();
  }

  Future<void> _loadSession() async {
    final storage = RepositoryProvider.of<LocalStorageRepository>(context);
    final session = await storage.getChatSession(widget.sessionId);
    if (mounted) {
      if (session != null) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => ChatDetailScreen(session: session),
          ),
        );
      } else {
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

class SolaceApp extends StatelessWidget {
  final LocalStorageRepository storageRepo;

  const SolaceApp({super.key, required this.storageRepo});

  // QQ 极简深色 + 微信白色 配色方案
  static final defaultLightColorScheme = ColorScheme(
    brightness: Brightness.light,
    primary: const Color(0xFF1A73E8),
    onPrimary: Colors.white,
    primaryContainer: const Color(0xFFD2E3FC),
    onPrimaryContainer: const Color(0xFF041E49),
    secondary: const Color(0xFF5F6368),
    onSecondary: Colors.white,
    secondaryContainer: const Color(0xFFE8EAED),
    onSecondaryContainer: const Color(0xFF202124),
    tertiary: const Color(0xFF1A73E8),
    onTertiary: Colors.white,
    tertiaryContainer: const Color(0xFFD2E3FC),
    onTertiaryContainer: const Color(0xFF041E49),
    error: const Color(0xFFD93025),
    onError: Colors.white,
    errorContainer: const Color(0xFFFCDCD8),
    onErrorContainer: const Color(0xFF410002),
    surface: const Color(0xFFFFFFFF),
    onSurface: const Color(0xFF1A1A1A),
    surfaceContainerLowest: const Color(0xFFFFFFFF),
    surfaceContainerLow: const Color(0xFFF8F9FA),
    surfaceContainer: const Color(0xFFF1F3F4),
    surfaceContainerHigh: const Color(0xFFE8EAED),
    surfaceContainerHighest: const Color(0xFFDFE1E5),
    onSurfaceVariant: const Color(0xFF5F6368),
    outline: const Color(0xFFDADCE0),
    outlineVariant: const Color(0xFFE8EAED),
    shadow: const Color(0xFF000000),
    scrim: const Color(0xFF000000),
    inverseSurface: const Color(0xFF303134),
    onInverseSurface: const Color(0xFFF1F3F4),
    inversePrimary: const Color(0xFF8AB4F8),
    surfaceTint: const Color(0xFF1A73E8),
  );

  // QQ 极简深色暗色方案
  static final defaultDarkColorScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: const Color(0xFF8AB4F8),
    onPrimary: const Color(0xFF041E49),
    primaryContainer: const Color(0xFF1A73E8),
    onPrimaryContainer: const Color(0xFFD2E3FC),
    secondary: const Color(0xFF9AA0A6),
    onSecondary: const Color(0xFF202124),
    secondaryContainer: const Color(0xFF303134),
    onSecondaryContainer: const Color(0xFFE8EAED),
    tertiary: const Color(0xFF8AB4F8),
    onTertiary: const Color(0xFF041E49),
    tertiaryContainer: const Color(0xFF1A73E8),
    onTertiaryContainer: const Color(0xFFD2E3FC),
    error: const Color(0xFFF28B82),
    onError: const Color(0xFF601410),
    errorContainer: const Color(0xFF8C1D18),
    onErrorContainer: const Color(0xFFF28B82),
    surface: const Color(0xFF1A1A1A),
    onSurface: const Color(0xFFE8EAED),
    surfaceContainerLowest: const Color(0xFF111111),
    surfaceContainerLow: const Color(0xFF1E1E1E),
    surfaceContainer: const Color(0xFF252525),
    surfaceContainerHigh: const Color(0xFF303134),
    surfaceContainerHighest: const Color(0xFF3C3C3C),
    onSurfaceVariant: const Color(0xFF9AA0A6),
    outline: const Color(0xFF5F6368),
    outlineVariant: const Color(0xFF3C3C3C),
    shadow: const Color(0xFF000000),
    scrim: const Color(0xFF000000),
    inverseSurface: const Color(0xFFE8EAED),
    onInverseSurface: const Color(0xFF303134),
    inversePrimary: const Color(0xFF1A73E8),
    surfaceTint: const Color(0xFF8AB4F8),
  );

  @override
  Widget build(BuildContext context) {
    final aiService = AIService(storageRepo);
    final aiAdapter = AIServiceAdapter(storage: storageRepo); // 桥接适配器，懒加载配置
    final deliverySimulator = DeliverySimulator(storageRepo);
    final badgeService = BadgeService(storageRepo);
    // v2 情绪+记忆+心跳系统
    final emotionEngine = EmotionEngine(storageRepo);
    final memoryEngine = MemoryEngine(storageRepo);
    final proactiveService = AIProactiveService(storageRepo);
    final reflectionEngine =
        ReflectionEngine.legacy(storageRepo, emotionEngine, memoryEngine);
    final heartbeatService = HeartbeatService(
      storageRepo,
      emotionEngine,
      memoryEngine,
      reflectionEngine,
      proactiveService,
    );
    // v10.0 新增服务
    final innerThoughtService = InnerThoughtService(storageRepo, emotionEngine);
    final forumService = ForumService(storageRepo);
    final relationshipService = AIRelationshipService(storageRepo);
    final weatherService = WeatherService(storageRepo, emotionEngine);
    final dayNightService = DayNightService();
    // 注入 v10 服务到心跳服务
    heartbeatService.setV10Services(
      innerThoughtService: innerThoughtService,
      forumService: forumService,
      weatherService: weatherService,
      dayNightService: dayNightService,
    );
    // v15.0: 新世界社交调度
    final socialScheduler = SocialSchedulerService(storageRepo);
    socialScheduler.setForumService(forumService);
    heartbeatService.setSocialScheduler(socialScheduler);
    // 注入社交执行器到 CoreHub
    final socialExecutor = SocialActionExecutor(
      storage: storageRepo,
      relationshipService: relationshipService,
      memoryEngine: memoryEngine,
      forumService: forumService,
    );
    CoreHub.instance.bindSocialExecutorFactory(() => socialExecutor);
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider.value(value: storageRepo),
        RepositoryProvider.value(value: aiService),
        RepositoryProvider.value(value: deliverySimulator),
        RepositoryProvider.value(value: badgeService),
        RepositoryProvider.value(value: emotionEngine),
        RepositoryProvider.value(value: memoryEngine),
        RepositoryProvider.value(value: heartbeatService),
        RepositoryProvider.value(value: innerThoughtService),
        RepositoryProvider.value(value: forumService),
        RepositoryProvider.value(value: relationshipService),
        RepositoryProvider.value(value: weatherService),
        RepositoryProvider.value(value: dayNightService),
        RepositoryProvider.value(value: socialScheduler),
        RepositoryProvider.value(value: socialExecutor),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider(
            create: (_) => ThemeBloc(storageRepo)..add(ThemeInitialized()),
          ),
          BlocProvider(
            create: (_) => AuthBloc(storageRepo)..add(AuthCheckRequested()),
          ),
        ],
        child: BlocBuilder<ThemeBloc, ThemeState>(
          builder: (context, themeState) {
            return MaterialApp(
              title: 'Solace',
              debugShowCheckedModeBanner: false,
              theme: ThemeData(
                colorScheme: defaultLightColorScheme,
                useMaterial3: true,
                fontFamily: 'Roboto',
                textTheme: Typography.material2021().black.apply(
                  fontFamilyFallback: [
                    'Noto Sans SC',
                    'Noto Sans CJK SC',
                    'sans-serif'
                  ],
                ),
                canvasColor: defaultLightColorScheme.surface,
                scaffoldBackgroundColor: defaultLightColorScheme.surface,
                dialogBackgroundColor: defaultLightColorScheme.surface,
                cardColor: defaultLightColorScheme.surfaceContainerLow,
                dividerColor: defaultLightColorScheme.outlineVariant,
                splashColor: Colors.transparent,
                highlightColor: Colors.transparent,
                hoverColor: Colors.transparent,
                focusColor: Colors.transparent,
                pageTransitionsTheme: const PageTransitionsTheme(
                  builders: {
                    TargetPlatform.android: ZoomPageTransitionsBuilder(
                      allowEnterRouteSnapshotting: false,
                    ),
                    TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
                  },
                ),
              ),
              darkTheme: ThemeData(
                colorScheme: defaultDarkColorScheme,
                useMaterial3: true,
                fontFamily: 'Roboto',
                textTheme: Typography.material2021().white.apply(
                  fontFamilyFallback: [
                    'Noto Sans SC',
                    'Noto Sans CJK SC',
                    'sans-serif'
                  ],
                ),
                canvasColor: defaultDarkColorScheme.surface,
                scaffoldBackgroundColor: defaultDarkColorScheme.surface,
                dialogBackgroundColor: defaultDarkColorScheme.surface,
                cardColor: defaultDarkColorScheme.surfaceContainerLow,
                dividerColor: defaultDarkColorScheme.outlineVariant,
                splashColor: Colors.transparent,
                highlightColor: Colors.transparent,
                hoverColor: Colors.transparent,
                focusColor: Colors.transparent,
                pageTransitionsTheme: const PageTransitionsTheme(
                  builders: {
                    TargetPlatform.android: ZoomPageTransitionsBuilder(
                      allowEnterRouteSnapshotting: false,
                    ),
                    TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
                  },
                ),
              ),
              themeMode: themeState.themeMode,
              navigatorKey: NotificationService.navigatorKey,
              builder: (context, child) {
                return Stack(
                  children: [
                    if (child != null) child,
                  ],
                );
              },
              onGenerateRoute: (settings) {
                if (settings.name == '/chat') {
                  final sessionId = settings.arguments as String;
                  return MaterialPageRoute(
                    builder: (_) => _ChatLauncher(sessionId: sessionId),
                  );
                }
                if (settings.name == '/moment') {
                  return MaterialPageRoute(
                    builder: (_) => const MomentsScreen(),
                  );
                }
                return null;
              },
              routes: {
                '/': (context) => BlocBuilder<AuthBloc, AuthState>(
                      builder: (context, authState) {
                        if (authState is AuthAuthenticated) {
                          return const _AuthGate();
                        }
                        if (authState is AuthLoading ||
                            authState is AuthInitial) {
                          return const Scaffold(
                            body: Center(child: CircularProgressIndicator()),
                          );
                        }
                        if (authState is AuthError) {
                          return Scaffold(
                            body: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.error_outline,
                                      size: 48, color: Colors.grey),
                                  const SizedBox(height: 16),
                                  const Text('加载失败'),
                                  const SizedBox(height: 4),
                                  Text(
                                    (authState as AuthError).message,
                                    style: const TextStyle(
                                        fontSize: 12, color: Colors.grey),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 16),
                                  ElevatedButton(
                                    onPressed: () {
                                      context
                                          .read<AuthBloc>()
                                          .add(AuthCheckRequested());
                                    },
                                    child: const Text('重试'),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }
                        return const LoginScreen();
                      },
                    ),
                '/create_character': (context) => const CreateCharacterScreen(),
                '/ai_config': (context) => const AIConfigScreen(),
                '/mailbox': (context) => const AIMailboxScreen(),
                '/forum': (context) => const ForumScreen(),
                '/virtual_map': (context) => const VirtualMapScreen(),
                '/lucky_wheel': (context) => const LuckyWheelScreen(),
                '/story': (context) => const StoryShelfScreen(),
              },
              initialRoute: '/',
            );
          },
        ),
      ),
    );
  }
}

/// 极简兜底组件（小占位），不依赖任何 InheritedWidget/Theme/Directionality
class _MiniFallback extends StatelessWidget {
  const _MiniFallback();

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
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
