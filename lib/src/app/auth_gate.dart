// 登录闸门：首启合规弹窗链 + 版本提示，全部通过后进入主界面。
// 本文件是 main.dart 的 part，仅与其共同构成一个库，不可单独 import。

part of '../../main.dart';

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
    _lockPortrait();
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 锁定屏幕方向为竖屏。在设备操控（Shizuku shell 命令）后，
  /// Activity 可能经历 onPause→onResume 导致 Flutter 引擎丢失方向设定，
  /// 因此在每次 App 回到前台时重新锁定。
  void _lockPortrait() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // App 从后台回到前台 — 重新锁定竖屏，
      // 防止 Shizuku 设备操控（input keyevent 等）引起的方向配置丢失
      _lockPortrait();
    }
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
