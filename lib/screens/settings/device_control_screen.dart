import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../repositories/local_storage_repository.dart';
import '../../config/constants.dart';
import '../../services/device_automation_service.dart';

/// 设备操控设置页面
///
/// 管理 AI 对手机的无障碍操控权限（AccessibilityService + Shizuku）。
class DeviceControlScreen extends StatefulWidget {
  const DeviceControlScreen({super.key});

  @override
  State<DeviceControlScreen> createState() => _DeviceControlScreenState();
}

class _DeviceControlScreenState extends State<DeviceControlScreen> {
  bool _a11yEnabled = false;
  bool _shizukuAvailable = false;
  bool _shizukuAuthorized = false;
  String _engineStatus = 'none';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refreshStatus();
  }

  Future<void> _refreshStatus() async {
    final a11y = await DeviceAutomationService.instance.isAccessibilityEnabled();
    final shizukuAvail = await DeviceAutomationService.instance.isShizukuAvailable();
    final shizukuAuth = await DeviceAutomationService.instance.isShizukuAuthorized();
    final status = await DeviceAutomationService.instance.getEngineStatus();
    if (!mounted) return;
    setState(() {
      _a11yEnabled = a11y;
      _shizukuAvailable = shizukuAvail;
      _shizukuAuthorized = shizukuAuth;
      _engineStatus = status.name;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<LocalStorageRepository>();
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('设备操控'),
        backgroundColor: cs.surface,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refreshStatus,
              child: ValueListenableBuilder<int>(
                valueListenable: s.modeSettingsNotifier,
                builder: (ctx, _, __) {
                  // 读取设备操控总开关状态
                  final master = s.getBool(PrefKeys.btPermissionDeviceMaster) ?? false;
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                    children: [
                      // ─── 状态面板 ───
                      _statusCard(cs, tt),
                      const SizedBox(height: 12),

                      // ─── 总开关 ───
                      _masterCard(ctx, s, cs, tt, master),
                      const SizedBox(height: 12),

                      if (!master)
                        _frozenBanner(cs, tt)
                      else ...[
                        // ─── 引擎引导 ───
                        if (!_a11yEnabled) _a11yGuideCard(cs, tt),
                        if (_shizukuAvailable && !_shizukuAuthorized)
                          _shizukuGuideCard(cs, tt),
                        if (_a11yEnabled) ...[
                          const SizedBox(height: 8),
                          _groupCard(ctx, s, cs, tt, '屏幕操作', Icons.touch_app_outlined, [
                            _item('点击', PrefKeys.btPermissionDeviceTap,
                                'AI 可点击屏幕指定位置'),
                            _item('滑动/滚动', PrefKeys.btPermissionDeviceSwipe,
                                'AI 可滑动和滚动屏幕'),
                            _item('长按', PrefKeys.btPermissionDeviceLongPress,
                                'AI 可长按屏幕位置'),
                            _item('导航按键', PrefKeys.btPermissionDeviceNavigate,
                                '返回、主页、最近任务'),
                          ]),
                          const SizedBox(height: 10),
                          _groupCard(ctx, s, cs, tt, '文字输入', Icons.keyboard_outlined, [
                            _item('输入文字', PrefKeys.btPermissionDeviceTypeText,
                                'AI 可在输入框内打字'),
                            _item('点击文字', PrefKeys.btPermissionDeviceClickText,
                                'AI 可点击包含指定文字的按钮'),
                          ]),
                          const SizedBox(height: 10),
                          _groupCard(ctx, s, cs, tt, '屏幕读取', Icons.visibility_outlined, [
                            _item('读取屏幕内容', PrefKeys.btPermissionDeviceScreenRead,
                                'AI 可获取当前屏幕的文字信息'),
                            _item('读取通知', PrefKeys.btPermissionDeviceNotifications,
                                'AI 可读取通知栏内容'),
                            _item('截屏', PrefKeys.btPermissionDeviceScreenshot,
                                'AI 可截取当前屏幕（需 Android 12+）'),
                          ]),
                          const SizedBox(height: 10),
                          _groupCard(ctx, s, cs, tt, '应用操作', Icons.apps_outlined, [
                            _item('打开 App', PrefKeys.btPermissionDeviceOpenApp,
                                'AI 可打开手机上的应用'),
                          ]),
                          if (_shizukuAuthorized) ...[
                            const SizedBox(height: 10),
                            _groupCard(ctx, s, cs, tt, '系统设置（Shizuku）',
                                Icons.settings_outlined, [
                              _item('WiFi/蓝牙开关', PrefKeys.btPermissionDeviceSystemSettings,
                                  'AI 可开关 WiFi 和蓝牙'),
                              _item('音量/亮度调节', PrefKeys.btPermissionDeviceSystemSettings,
                                  'AI 可调节媒体音量和屏幕亮度'),
                            ]),
                            const SizedBox(height: 10),
                            _groupCard(ctx, s, cs, tt, '高级（Shizuku）',
                                Icons.terminal_outlined, [
                              _item('Shell 命令', PrefKeys.btPermissionDeviceShell,
                                  'AI 可执行任意 shell 命令'),
                              _item('安装/卸载 App', PrefKeys.btPermissionDeviceAppManagement,
                                  'AI 可安装和卸载应用'),
                            ]),
                          ],
                        ],
                      ],
                      const SizedBox(height: 12),
                      _infoCard(cs, tt),
                    ],
                  );
                },
              ),
            ),
    );
  }

  Widget _statusCard(ColorScheme cs, TextTheme tt) {
    final statusText = switch (_engineStatus) {
      'dual' => '✅ 双引擎已就绪',
      'a11y_only' => '✅ 无障碍服务已开启',
      'shizuku_only' => '✅ Shizuku 已激活',
      _ => '❌ 未检测到可用引擎',
    };
    final statusSubtitle = switch (_engineStatus) {
      'dual' => 'AccessibilityService + Shizuku 均可使用',
      'a11y_only' => 'UI 操控可用，系统设置需激活 Shizuku',
      'shizuku_only' => 'Shell 命令可用，UI 操作需开启无障碍',
      _ => '请开启无障碍服务或激活 Shizuku',
    };

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: cs.outlineVariant.withOpacity(0.5)),
      ),
      color: cs.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              switch (_engineStatus) {
                'dual' => Icons.check_circle,
                'a11y_only' => Icons.check_circle_outline,
                'shizuku_only' => Icons.check_circle_outline,
                _ => Icons.error_outline,
              },
              color: switch (_engineStatus) {
                'dual' => Colors.green,
                'a11y_only' => Colors.blue,
                'shizuku_only' => Colors.orange,
                _ => cs.error,
              },
              size: 28,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(statusText, style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(statusSubtitle, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _masterCard(
    BuildContext ctx,
    LocalStorageRepository s,
    ColorScheme cs,
    TextTheme tt,
    bool master,
  ) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: cs.outlineVariant.withOpacity(0.5)),
      ),
      color: cs.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.phone_android,
                    color: master ? Colors.orange : cs.onSurfaceVariant),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('设备操控 总开关',
                      style: tt.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: master ? Colors.orange : cs.onSurface)),
                ),
                Switch(
                  value: master,
                  activeColor: Colors.orange,
                  onChanged: (v) async {
                    if (v && !_a11yEnabled) {
                      final ok = await showDialog<bool>(
                        context: ctx,
                        builder: (_) => AlertDialog(
                          title: const Text('开启确认'),
                          content: const Text(
                            '启用设备操控后，AI 将获得操控手机的能力。\n\n'
                            '⚠️ 请先开启无障碍服务，否则设备操控功能无法使用。\n\n'
                            '确认开启？',
                          ),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('取消')),
                            TextButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('确认开启',
                                    style: TextStyle(color: Colors.orange))),
                          ],
                        ),
                      );
                      if (ok != true) return;
                    }
                    await s.setBool(PrefKeys.btPermissionDeviceMaster, v);
                    s.modeSettingsNotifier.value++;
                  },
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              master
                  ? '已开启：AI 可在权限范围内操控手机'
                  : '已关闭：所有设备操控权限冻结',
              style: tt.bodySmall?.copyWith(
                  color: master ? Colors.orange.shade300 : cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _frozenBanner(ColorScheme cs, TextTheme tt) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.5)),
      ),
      child: Column(
        children: [
          Icon(Icons.lock_outline, size: 40, color: cs.onSurfaceVariant),
          const SizedBox(height: 12),
          Text('总开关已关闭',
              style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text('所有设备操控子权限已冻结，AI 不会获得任何手机操控能力。\n开启总开关后可配置具体权限。',
              textAlign: TextAlign.center,
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _a11yGuideCard(ColorScheme cs, TextTheme tt) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.blue.withOpacity(0.3)),
      ),
      color: Colors.blue.withOpacity(0.05),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.accessibility_new, color: Colors.blue, size: 20),
                const SizedBox(width: 8),
                Text('需要开启无障碍服务',
                    style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '1. 点击下方按钮跳转到「无障碍」设置\n'
              '2. 找到「已安装的应用」→「Solace」\n'
              '3. 开启 Solace 的无障碍开关\n'
              '4. 在弹出的对话框中点击「允许」\n\n'
              '💡 不同手机路径略有差异，华为/荣耀设备请在设置中搜索「无障碍」。',
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () async {
                  await DeviceAutomationService.instance.openAccessibilitySettings();
                },
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('跳转到无障碍设置'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _shizukuGuideCard(ColorScheme cs, TextTheme tt) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.purple.withOpacity(0.3)),
      ),
      color: Colors.purple.withOpacity(0.05),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.terminal, color: Colors.purple, size: 20),
                const SizedBox(width: 8),
                Text('Shizuku 待激活',
                    style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Shizuku 可提供 Shell 级别的系统控制能力（WiFi/蓝牙/音量/亮度/安装App等）。\n\n'
              '激活步骤：\n'
              '1. 安装 Shizuku Manager App（需侧载）\n'
              '2. 开启「开发者选项」→「无线调试」\n'
              '3. 在 Shizuku App 中点击「无线调试」激活\n'
              '4. 返回本页，下拉刷新状态\n\n'
              '⚠️ 重启后需要重新激活 Shizuku。\n'
              '💡 仅开启无障碍服务也可使用大部分 UI 操控功能。',
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  final opened = await DeviceAutomationService.instance.openShizuku();
                  if (!opened && mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Shizuku Manager 未安装，请先侧载 Shizuku App')),
                    );
                  }
                },
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('打开 Shizuku Manager'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _groupCard(
    BuildContext ctx,
    LocalStorageRepository s,
    ColorScheme cs,
    TextTheme tt,
    String title,
    IconData icon,
    List<_PermItem> items,
  ) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: cs.outlineVariant.withOpacity(0.5)),
      ),
      color: cs.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: cs.primary),
                const SizedBox(width: 8),
                Text(title,
                    style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 6),
            ...items.map((item) {
              final enabled = s.getBool(item.key) ?? false;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    SizedBox(
                      width: 42,
                      child: Transform.scale(
                        scale: 0.8,
                        child: Switch(
                          value: enabled,
                          activeColor: cs.primary,
                          onChanged: (v) async {
                            await s.setBool(item.key, v);
                            s.modeSettingsNotifier.value++;
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.label,
                              style: tt.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w500)),
                          if (item.desc != null && item.desc!.isNotEmpty)
                            Text(item.desc!,
                                style: tt.bodySmall
                                    ?.copyWith(color: cs.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _infoCard(ColorScheme cs, TextTheme tt) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: cs.outlineVariant.withOpacity(0.5)),
      ),
      color: cs.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, size: 18, color: cs.primary),
                const SizedBox(width: 8),
                Text('隐私与安全说明',
                    style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '• 所有设备操控操作均记录在 BT 审计日志中\n'
              '• 密码输入框系统会自动屏蔽，AI 无法读取\n'
              '• 无障碍服务仅获取界面文字，不采集隐私信息\n'
              '• Shizuku 仅在激活后可用，重启需重新激活\n'
              '• 可随时关闭总开关，所有权限立即冻结\n'
              '• 华为/荣耀设备建议将 Solace 加入受保护应用',
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  _PermItem _item(String label, String key, [String? desc]) =>
      _PermItem(label: label, key: key, desc: desc);
}

class _PermItem {
  final String label;
  final String key;
  final String? desc;
  _PermItem({required this.label, required this.key, this.desc});
}
