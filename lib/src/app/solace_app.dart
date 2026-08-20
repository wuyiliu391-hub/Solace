// 应用根组件（含 _ChatLauncher 路由页）：仓库/BLoC 注入 + 主题 + 路由表。
// 本文件是 main.dart 的 part，仅与其共同构成一个库，不可单独 import。

part of '../../main.dart';

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
  final bool storageReady;

  const SolaceApp({
    super.key,
    required this.storageRepo,
    this.storageReady = true,
  });

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

  // 深色沉浸方案（18.3.0 Shine 风格：深夜蓝黑底 + 酒粉暖强调）
  static final defaultDarkColorScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: ImmersiveColors.accent,
    onPrimary: const Color(0xFF2A1416),
    primaryContainer: ImmersiveColors.accentDeep,
    onPrimaryContainer: const Color(0xFFFFF0EA),
    secondary: ImmersiveColors.accentSoft,
    onSecondary: ImmersiveColors.background,
    secondaryContainer: const Color(0xFF1C2440),
    onSecondaryContainer: const Color(0xFFD4DEFF),
    tertiary: const Color(0xFFE6C88A),
    onTertiary: const Color(0xFF2A2010),
    tertiaryContainer: const Color(0xFF3D3218),
    onTertiaryContainer: const Color(0xFFF0E2C0),
    error: const Color(0xFFF28B82),
    onError: const Color(0xFF601410),
    errorContainer: const Color(0xFF8C1D18),
    onErrorContainer: const Color(0xFFF28B82),
    surface: ImmersiveColors.background,
    onSurface: const Color(0xFFF5F0EA),
    surfaceContainerLowest: const Color(0xFF08090F),
    surfaceContainerLow: const Color(0xFF0E1120),
    surfaceContainer: const Color(0xFF131729),
    surfaceContainerHigh: const Color(0xFF1A2036),
    surfaceContainerHighest: const Color(0xFF232A45),
    onSurfaceVariant: const Color(0xFF9AA0B4),
    outline: const Color(0xFF3A4158),
    outlineVariant: const Color(0xFF262C42),
    shadow: const Color(0xFF000000),
    scrim: const Color(0xFF000000),
    inverseSurface: const Color(0xFFF5F0EA),
    onInverseSurface: ImmersiveColors.background,
    inversePrimary: const Color(0xFF8A4B52),
    surfaceTint: ImmersiveColors.accent,
  );

  // 微信风格浅色方案（18.3.0，色值逆向提取自仿微信应用 + WeUI 核对）
  static final wechatLightColorScheme = ColorScheme(
    brightness: Brightness.light,
    primary: WeChatColors.brandGreen,
    onPrimary: Colors.white,
    primaryContainer: WeChatColors.bubbleMine,
    onPrimaryContainer: WeChatColors.bubbleMineText,
    secondary: WeChatColors.linkBlue,
    onSecondary: Colors.white,
    secondaryContainer: const Color(0xFFDCE6F2),
    onSecondaryContainer: const Color(0xFF2B3A52),
    tertiary: const Color(0xFFF4AB5D),
    onTertiary: const Color(0xFF4A2D0A),
    tertiaryContainer: const Color(0xFFFDF2DF),
    onTertiaryContainer: const Color(0xFF6B4514),
    error: WeChatColors.badgeRed,
    onError: Colors.white,
    errorContainer: const Color(0xFFFFDAD6),
    onErrorContainer: const Color(0xFF410002),
    surface: WeChatColors.pageBackground,
    onSurface: WeChatColors.textPrimary,
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: WeChatColors.listItem,
    surfaceContainer: const Color(0xFFF5F5F5),
    surfaceContainerHigh: const Color(0xFFEDEDED),
    surfaceContainerHighest: WeChatColors.divider,
    onSurfaceVariant: WeChatColors.textSecondary,
    outline: WeChatColors.dividerLight,
    outlineVariant: WeChatColors.divider,
    shadow: const Color(0xFF000000),
    scrim: const Color(0xFF000000),
    inverseSurface: WeChatColors.textPrimary,
    onInverseSurface: WeChatColors.pageBackground,
    inversePrimary: WeChatColors.brandGreen,
    surfaceTint: WeChatColors.brandGreen,
  );

  // 微信风格深色方案（values-night 提取：#111111 底 + #181818 列表 + #2C2C2C 卡片）
  static final wechatDarkColorScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: WeChatColors.brandGreen,
    onPrimary: WeChatColors.darkBubbleMineText,
    primaryContainer: const Color(0xFF1F4B2A),
    onPrimaryContainer: WeChatColors.bubbleMine,
    secondary: WeChatColors.linkBlue,
    onSecondary: Colors.white,
    secondaryContainer: const Color(0xFF232C3D),
    onSecondaryContainer: const Color(0xFFB9C6DC),
    tertiary: const Color(0xFFE5A058),
    onTertiary: const Color(0xFF3D2408),
    tertiaryContainer: const Color(0xFF362A20),
    onTertiaryContainer: const Color(0xFFF0D9BC),
    error: WeChatColors.badgeRed,
    onError: Colors.white,
    errorContainer: const Color(0xFF93000A),
    onErrorContainer: const Color(0xFFFFDAD6),
    surface: WeChatColors.darkPageBackground,
    onSurface: const Color(0xFFD2D2D2),
    surfaceContainerLowest: const Color(0xFF0D0D0D),
    surfaceContainerLow: WeChatColors.darkListItem,
    surfaceContainer: WeChatColors.darkChatBottomBar,
    surfaceContainerHigh: const Color(0xFF242424),
    surfaceContainerHighest: WeChatColors.darkCard,
    onSurfaceVariant: WeChatColors.darkTextSecondary,
    outline: const Color(0xFF3A3A3A),
    outlineVariant: WeChatColors.darkDivider,
    shadow: const Color(0xFF000000),
    scrim: const Color(0xFF000000),
    inverseSurface: const Color(0xFFD2D2D2),
    onInverseSurface: WeChatColors.darkPageBackground,
    inversePrimary: const Color(0xFF0A5C30),
    surfaceTint: WeChatColors.brandGreen,
  );

  @override
  Widget build(BuildContext context) {
    // 数据库初始化/迁移失败时，进入恢复页而不是静默启动空数据主界面。
    if (!storageReady) {
      return MaterialApp(
        title: 'Solace',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: ImmersiveColors.accent,
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
          fontFamily: 'Roboto',
        ),
        home: StorageRecoveryScreen(
          controller: StorageRecoveryController(
            initialize: () => storageRepo.initialize(),
            databasePath: () async => p.join(
              await getDatabasesPath(),
              DbDefaults.dbName,
            ),
          ),
          onRecovered: () {
            runApp(
              SolaceApp(storageRepo: storageRepo, storageReady: true),
            );
          },
        ),
      );
    }

    final aiService = AIService(storageRepo);
    final aiAdapter = AIServiceAdapter(storage: storageRepo); // 桥接适配器，懒加载配置
    // v2 情绪+记忆系统
    final emotionEngine = EmotionEngine(storageRepo);
    final memoryEngine = MemoryEngine(storageRepo);
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider.value(value: storageRepo),
        RepositoryProvider.value(value: aiService),
        RepositoryProvider.value(value: emotionEngine),
        RepositoryProvider.value(value: memoryEngine),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider(
            create: (_) => ThemeBloc(storageRepo)..add(ThemeInitialized()),
          ),
          BlocProvider(
            create: (_) => AuthBloc(storageRepo)..add(AuthCheckRequested()),
          ),
          BlocProvider(
            create: (_) => GroupChatBloc(storageRepo, aiService),
          ),
          BlocProvider(
            create: (_) => ShopBloc(storageRepo),
          ),
        ],
        child: BlocBuilder<ThemeBloc, ThemeState>(
          builder: (context, themeState) {
            final lightScheme = switch (themeState.visualStyle) {
              VisualStyle.wechat => wechatLightColorScheme,
              VisualStyle.classic => defaultLightColorScheme,
            };
            final darkScheme = switch (themeState.visualStyle) {
              VisualStyle.wechat => wechatDarkColorScheme,
              VisualStyle.classic => defaultDarkColorScheme,
            };

            return MaterialApp(
              title: 'Solace',
              debugShowCheckedModeBanner: false,
              theme: ThemeData(
                colorScheme: lightScheme,
                useMaterial3: true,
                fontFamily: 'Roboto',
                textTheme: Typography.material2021().black.apply(
                  fontFamilyFallback: [
                    'Noto Sans SC',
                    'Noto Sans CJK SC',
                    'sans-serif'
                  ],
                ),
                canvasColor: lightScheme.surface,
                scaffoldBackgroundColor: lightScheme.surface,
                dialogBackgroundColor: lightScheme.surface,
                cardColor: lightScheme.surfaceContainerLow,
                dividerColor: lightScheme.outlineVariant,
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
                colorScheme: darkScheme,
                useMaterial3: true,
                fontFamily: 'Roboto',
                textTheme: Typography.material2021().white.apply(
                  fontFamilyFallback: [
                    'Noto Sans SC',
                    'Noto Sans CJK SC',
                    'sans-serif'
                  ],
                ),
                canvasColor: darkScheme.surface,
                scaffoldBackgroundColor: darkScheme.surface,
                dialogBackgroundColor: darkScheme.surface,
                cardColor: darkScheme.surfaceContainerLow,
                dividerColor: darkScheme.outlineVariant,
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
                '/': (context) => BlocConsumer<AuthBloc, AuthState>(
                      listenWhen: (prev, next) =>
                          next is AuthAuthenticated &&
                          next.loginBonusGranted > 0 &&
                          (prev is! AuthAuthenticated ||
                              prev.loginBonusGranted != next.loginBonusGranted),
                      listener: (context, authState) {
                        if (authState is! AuthAuthenticated) return;
                        final n = authState.loginBonusGranted;
                        if (n <= 0) return;
                        final messenger = ScaffoldMessenger.maybeOf(context);
                        messenger?.showSnackBar(
                          SnackBar(
                            content: Text('每日登录奖励 +$n 金币'),
                            behavior: SnackBarBehavior.floating,
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      },
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
                                    authState.message,
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
                '/lucky_wheel': (context) => const LuckyWheelScreen(),
              },
              initialRoute: '/',
            );
          },
        ),
      ),
    );
  }
}
