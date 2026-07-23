import 'package:flutter/material.dart';
import '../../services/accessibility_service.dart';

/// 无障碍 + 保活一体化引导页面
///
/// 按优先级排序引导用户完成以下步骤：
/// 1. 检测当前状态（双重检测）
/// 2. 如果未授权 → 引导开启无障碍
/// 3. 如果已授权但冻结 → 引导重新开关
/// 4. 电池优化白名单
/// 5. 自启动权限（各厂商独立跳转）
/// 6. 应用后台限制检查
class AccessibilityKeepAliveGuideScreen extends StatefulWidget {
  final VoidCallback? onComplete;

  const AccessibilityKeepAliveGuideScreen({super.key, this.onComplete});

  @override
  State<AccessibilityKeepAliveGuideScreen> createState() =>
      _AccessibilityKeepAliveGuideScreenState();
}

class _AccessibilityKeepAliveGuideScreenState
    extends State<AccessibilityKeepAliveGuideScreen> {
  final _a11y = AccessibilityService();

  AccessibilityDualCheckResult? _checkResult;
  KeepAliveStatus? _keepAliveStatus;
  bool _loading = true;
  bool _showingToast = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final result = await _a11y.performDualCheck();
    final status = await _a11y.getKeepAliveStatus();
    if (mounted) {
      setState(() {
        _checkResult = result;
        _keepAliveStatus = status;
        _loading = false;
      });
    }
    // 如果一切正常，通知完成
    if (result.isActuallyUsable) {
      widget.onComplete?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0A0A0A) : colorScheme.surface,
      appBar: AppBar(
        title: const Text('一键优化保活'),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (!_loading)
            IconButton(
              icon: const Icon(Icons.refresh, size: 20),
              onPressed: _refresh,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _buildHeader(colorScheme, isDark),
                const SizedBox(height: 24),
                _buildStatusCard(colorScheme, isDark),
                const SizedBox(height: 16),
                _buildStepList(colorScheme, isDark),
                const SizedBox(height: 24),
                _buildVendorInfo(colorScheme, isDark),
              ],
            ),
    );
  }

  Widget _buildHeader(ColorScheme colorScheme, bool isDark) {
    final isOk = _checkResult?.isActuallyUsable ?? false;
    return Column(
      children: [
        Icon(
          isOk ? Icons.check_circle_outline : Icons.engineering_outlined,
          size: 64,
          color: isOk ? Colors.green : colorScheme.primary,
        ),
        const SizedBox(height: 12),
        Text(
          isOk ? '一切正常！' : '需要优化',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          isOk
              ? '无障碍服务运行正常，保活状态良好'
              : '按以下步骤优化，提升服务稳定性',
          style: TextStyle(
            fontSize: 14,
            color: colorScheme.onSurface.withOpacity(0.6),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusCard(ColorScheme colorScheme, bool isDark) {
    final result = _checkResult;
    if (result == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('当前状态', style: TextStyle(
            fontSize: 14, fontWeight: FontWeight.w600, color: colorScheme.onSurface,
          )),
          const SizedBox(height: 12),
          _statusRow('无障碍开关', result.isSettingsEnabled),
          _statusRow('服务运行中', result.isServiceInstanceAlive),
          _statusRow('系统运行列表', result.isServiceInList),
          if (_keepAliveStatus != null) ...[
            _statusRow('电池优化白名单', !_keepAliveStatus!.isBatteryOptimized),
          ],
          _statusRow('厂商ROM', true, valueText: result.vendor.friendlyName),
          if (result.needsRetoggle) ...[
            const SizedBox(height: 12),
            _buildRetoggleBanner(colorScheme),
          ],
        ],
      ),
    );
  }

  Widget _statusRow(String label, bool ok, {String? valueText}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: ok ? Colors.green : (valueText != null ? Colors.blue : Colors.red),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label, style: const TextStyle(fontSize: 13)),
          ),
          Text(
            valueText ?? (ok ? '✓' : '✗'),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: ok ? Colors.green : Colors.red,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRetoggleBanner(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.orange[700], size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '无障碍开关已开启但服务被系统冻结。\n'
              '请先关闭开关，再重新打开一次。',
              style: TextStyle(fontSize: 12, color: Colors.orange[700]),
            ),
          ),
          FilledButton.tonal(
            onPressed: () => _a11y.requestAccess(),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.orange.withOpacity(0.15),
              foregroundColor: Colors.orange[700],
            ),
            child: const Text('去设置', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildStepList(ColorScheme colorScheme, bool isDark) {
    final result = _checkResult;
    final keepAlive = _keepAliveStatus;
    final steps = <_GuideStep>[];
    int stepNum = 1;

    // 步骤1：开启无障碍
    if (result != null) {
      final isOk = result.isSettingsEnabled && result.isServiceInstanceAlive;
      steps.add(_GuideStep(
        number: stepNum++,
        title: '开启无障碍服务',
        description: isOk
            ? '已开启 ✓'
            : '让 Solace AI 角色能够感知和操控屏幕',
        icon: Icons.accessibility_new,
        isDone: isOk,
        isCritical: true,
        actionLabel: isOk ? null : '去设置',
        onAction: isOk ? null : () => _a11y.requestAccess(),
      ));

      // 步骤1b：如果已授权但冻结
      if (result.needsRetoggle) {
        steps.add(_GuideStep(
          number: stepNum++,
          title: '重新开关无障碍',
          description: '先关闭再打开，解除系统进程冻结',
          icon: Icons.restart_alt,
          isDone: false,
          isCritical: true,
          isWarning: true,
          actionLabel: '去设置',
          onAction: () => _a11y.requestAccess(),
        ));
      }
    }

    // 步骤2：电池优化白名单
    if (keepAlive != null) {
      final batteryOk = !keepAlive.isBatteryOptimized;
      steps.add(_GuideStep(
        number: stepNum++,
        title: '关闭电池优化',
        description: batteryOk
            ? '已关闭 ✓'
            : '防止系统在后台限制 Solace',
        icon: Icons.battery_charging_full,
        isDone: batteryOk,
        isCritical: true,
        actionLabel: batteryOk ? null : '去设置',
        onAction: batteryOk ? null : () => _a11y.openBatteryOptimizationSettings(),
      ));
    }

    // 步骤3：自启动（仅国产ROM）
    if (result != null && result.vendor.needsKeepAliveAttention) {
      steps.add(_GuideStep(
        number: stepNum++,
        title: '开启自启动权限',
        description: '${result.vendor.friendlyName} 需要手动授权自启动',
        icon: Icons.rocket_launch,
        isDone: false,
        isCritical: false,
        actionLabel: '去设置',
        onAction: () => _a11y.openAutoStartSettings().then((ok) {
          if (!ok) {
            // 厂商跳转失败，打开应用详情页
            _a11y.openAppDetailsSettings();
          }
        }),
      ));
    }

    // 步骤4：应用加锁（保持后台）
    if (result != null && result.vendor.needsKeepAliveAttention) {
      steps.add(_GuideStep(
        number: stepNum++,
        title: '在最近任务中锁定应用',
        description: '在最近任务列表中将 Solace 下滑锁定，防止一键清理',
        icon: Icons.lock_outline,
        isDone: false,
        isCritical: false,
        actionLabel: '我知道了',
        onAction: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('按 Home 键回到桌面，打开最近任务，将 Solace 卡片下滑锁定即可'),
              duration: Duration(seconds: 3),
            ),
          );
        },
      ));
    }

    // 步骤5：后台活动限制（国产ROM）
    if (result != null && result.vendor.needsKeepAliveAttention) {
      steps.add(_GuideStep(
        number: stepNum++,
        title: '关闭后台活动限制',
        description: '确保 Solace 可以在后台持续运行',
        icon: Icons.settings_backup_restore,
        isDone: false,
        isCritical: false,
        actionLabel: '去设置',
        onAction: () => _a11y.openAppDetailsSettings(),
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '优化步骤（按优先级排序）',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 12),
        ...steps.map((s) => _buildStep(s, colorScheme, isDark)),
      ],
    );
  }

  Widget _buildStep(_GuideStep step, ColorScheme colorScheme, bool isDark) {
    Color borderColor;
    if (step.isDone) {
      borderColor = Colors.green.withOpacity(0.3);
    } else if (step.isWarning) {
      borderColor = Colors.orange.withOpacity(0.4);
    } else if (step.isCritical) {
      borderColor = colorScheme.primary.withOpacity(0.3);
    } else {
      borderColor = isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.08);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.03) : Colors.black.withOpacity(0.02),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          // 序号圆圈
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: step.isDone
                  ? Colors.green.withOpacity(0.15)
                  : step.isWarning
                      ? Colors.orange.withOpacity(0.15)
                      : colorScheme.primary.withOpacity(0.1),
              border: Border.all(
                color: step.isDone
                    ? Colors.green.withOpacity(0.3)
                    : step.isWarning
                        ? Colors.orange.withOpacity(0.3)
                        : colorScheme.primary.withOpacity(0.2),
              ),
            ),
            child: Center(
              child: step.isDone
                  ? const Icon(Icons.check, size: 16, color: Colors.green)
                  : Text(
                      '${step.number}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: step.isWarning ? Colors.orange : colorScheme.primary,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          // 内容
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        step.title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ),
                    if (step.isCritical && !step.isDone)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          '重要',
                          style: TextStyle(fontSize: 10, color: Colors.red),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  step.description,
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurface.withOpacity(0.55),
                  ),
                ),
                if (step.actionLabel != null && !step.isDone) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.tonal(
                      onPressed: step.onAction,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(80, 32),
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                      child: Text(step.actionLabel!),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVendorInfo(ColorScheme colorScheme, bool isDark) {
    final result = _checkResult;
    if (result == null) return const SizedBox.shrink();

    final vendor = result.vendor;
    String explanation;
    if (vendor.proneToFreeze) {
      explanation = '${vendor.friendlyName} 在某些情况下可能会冻结已授权的无障碍服务'
          '而不改变设置开关状态。如果遇到服务不可用但开关仍开启的情况，'
          '请直接重新开关一次无障碍服务即可恢复。';
    } else if (vendor.proneToAutoDisable) {
      explanation = '${vendor.friendlyName} 可能在清理后台时自动关闭无障碍开关。'
          '建议完成上述所有优化步骤以减少此类情况发生。';
    } else {
      explanation = '${vendor.friendlyName} 对无障碍服务的后台管理较为规范，'
          '但仍建议完成电池优化白名单设置以确保最佳体验。';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.03) : Colors.black.withOpacity(0.02),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline, size: 16),
              const SizedBox(width: 8),
              Text(
                '关于 ${vendor.friendlyName}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            explanation,
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
        ],
      ),
    );
  }
}

class _GuideStep {
  final int number;
  final String title;
  final String description;
  final IconData icon;
  final bool isDone;
  final bool isCritical;
  final bool isWarning;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _GuideStep({
    required this.number,
    required this.title,
    required this.description,
    required this.icon,
    this.isDone = false,
    this.isCritical = false,
    this.isWarning = false,
    this.actionLabel,
    this.onAction,
  });
}