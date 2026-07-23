import 'package:flutter/material.dart';
import 'package:solace/screens/settings/accessibility_keep_alive_guide_screen.dart';
import '../../services/accessibility_service.dart';

/// App 前台启动自检组件
///
/// 集成到 Operit 页面或其他需要无障碍的页面中。
/// 启动时自动执行双重检测，分三种分支处理：
///
/// - 已授权且运行 (ALL_GOOD) → 无操作
/// - 已授权但冻结 (ENABLED_BUT_FROZEN) → 弹窗引导用户重新开关
/// - 未授权 (NOT_ENABLED) → 弹窗引导去设置页
///
/// ## 使用方式
/// ```dart
/// AccessibilityStartupCheck(
///   onAllGood: () { /* 开始使用无障碍功能 */ },
///   builder: (context, result, child) { /* 你的页面内容 */ return child; },
/// )
/// ```
class AccessibilityStartupCheck extends StatefulWidget {
  /// 无障碍一切正常时的回调
  final VoidCallback? onAllGood;

  /// 状态变化时的回调（如用户成功授权后回来触发）
  final VoidCallback? onStatusChanged;

  /// 内容构建器
  final Widget Function(BuildContext context, AccessibilityDualCheckResult? result) builder;

  /// 是否在检测中显示 loading
  final bool showLoadingIndicator;

  const AccessibilityStartupCheck({
    super.key,
    this.onAllGood,
    this.onStatusChanged,
    required this.builder,
    this.showLoadingIndicator = false,
  });

  @override
  State<AccessibilityStartupCheck> createState() => _AccessibilityStartupCheckState();
}

class _AccessibilityStartupCheckState extends State<AccessibilityStartupCheck>
    with WidgetsBindingObserver {
  final _a11y = AccessibilityService();
  AccessibilityDualCheckResult? _result;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _performCheck();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // App 从后台回到前台时重新检测
    if (state == AppLifecycleState.resumed) {
      _performCheck();
    }
  }

  Future<void> _performCheck() async {
    setState(() => _checking = true);

    final result = await _a11y.performDualCheck();
    debugPrint('[A11yStartupCheck] 检测结果: $result');

    if (mounted) {
      setState(() {
        _result = result;
        _checking = false;
      });

      if (result.isActuallyUsable) {
        widget.onAllGood?.call();
      } else {
        // 根据分支显示对应的引导弹窗
        _showGuidanceDialog(result);
      }
    }
  }

  void _showGuidanceDialog(AccessibilityDualCheckResult result) {
    if (result.isActuallyUsable) return;

    // 延迟弹窗，等 build 完成
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showDialog(result);
    });
  }

  void _showDialog(AccessibilityDualCheckResult result) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (result.needsRetoggle) {
      // 分支①：已授权但冻结 — 引导重新开关
      _showActionDialog(
        title: '无障碍服务被暂停',
        message: '${result.vendor.friendlyName} 的系统进程管理暂停了 Solace 的无障碍服务。\n\n'
            '请前往设置页面：\n'
            '1. 先**关闭** Solace 的无障碍开关\n'
            '2. 再**重新打开**一次\n\n'
            '这样即可解除系统的进程冻结标记。',
        icon: Icons.restart_alt_rounded,
        iconColor: Colors.orange,
        actionLabel: '去设置',
        onAction: () async {
          await _a11y.requestAccess();
          // 用户回来后重新检测
          await Future.delayed(const Duration(seconds: 1));
          _performCheck();
        },
        secondaryLabel: '打开保活指南',
        onSecondary: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const AccessibilityKeepAliveGuideScreen(),
            ),
          ).then((_) => _performCheck());
        },
      );
    } else if (result.needsEnable) {
      // 分支②：未授权 — 引导开启
      _showActionDialog(
        title: '需要开启无障碍服务',
        message: 'Solace AI 角色需要通过无障碍服务来感知和操控屏幕。\n\n'
            '我们承诺：\n'
            '• 不会读取密码输入框\n'
            '• 不会收集或上传任何屏幕内容\n'
            '• 所有数据仅存储在您的设备上\n\n'
            '请前往设置中开启 Solace 的无障碍服务。',
        icon: Icons.accessibility_new,
        iconColor: colorScheme.primary,
        actionLabel: '去设置',
        onAction: () async {
          await _a11y.requestAccess();
          await Future.delayed(const Duration(seconds: 1));
          _performCheck();
        },
        secondaryLabel: '了解更多',
        onSecondary: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const AccessibilityKeepAliveGuideScreen(),
            ),
          ).then((_) => _performCheck());
        },
      );
    }
  }

  void _showActionDialog({
    required String title,
    required String message,
    required IconData icon,
    required Color iconColor,
    required String actionLabel,
    required VoidCallback onAction,
    String? secondaryLabel,
    VoidCallback? onSecondary,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final dark = Theme.of(ctx).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: dark ? const Color(0xFF1E1E1E) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Column(
            children: [
              Icon(icon, size: 48, color: iconColor),
              const SizedBox(height: 12),
              Text(title, style: const TextStyle(fontSize: 18), textAlign: TextAlign.center),
            ],
          ),
          content: Text(
            message,
            style: TextStyle(
              fontSize: 13,
              height: 1.6,
              color: cs.onSurface.withOpacity(0.7),
            ),
          ),
          actions: [
            if (secondaryLabel != null)
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  onSecondary?.call();
                },
                child: Text(secondaryLabel),
              ),
            const SizedBox(width: 4),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                onAction();
              },
              child: Text(actionLabel),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_checking && widget.showLoadingIndicator) {
      return const Center(child: CircularProgressIndicator());
    }
    return widget.builder(context, _result);
  }
}