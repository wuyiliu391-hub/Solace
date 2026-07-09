import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../blocs/theme/theme_bloc.dart';
import '../../config/constants.dart';
import '../../services/wellbeing_service.dart';
import '../../widgets/avatar_picker.dart';
import 'about_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final user = (context.read<AuthBloc>().state as AuthAuthenticated).user;

    return Scaffold(
      appBar: AppBar(
        title: const Text('我'),
        centerTitle: true,
        elevation: 0,
      ),
      body: ListView(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                BlocBuilder<AuthBloc, AuthState>(
                  builder: (context, state) {
                    String? avatarUrl;
                    if (state is AuthAuthenticated) {
                      avatarUrl = state.user.avatarUrl;
                    }
                    return AvatarPicker(
                      currentAvatar: avatarUrl,
                      onAvatarSelected: (avatar) {
                        _updateAvatar(avatar);
                      },
                      size: 80,
                    );
                  },
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.nickname,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'ID: ${user.id}',
                        style: TextStyle(
                          fontSize: 13,
                          color: colorScheme.onSurface.withOpacity(0.5),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.qr_code,
                  color: colorScheme.onSurface.withOpacity(0.3),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: colorScheme.outline.withOpacity(0.1)),
          _SettingsItem(
            icon: Icons.palette_outlined,
            title: '主题设置',
            onTap: () => _showThemeDialog(context),
          ),
          Divider(height: 1, color: colorScheme.outline.withOpacity(0.1)),
          _AppUsageAwarenessTile(),
          Divider(height: 1, color: colorScheme.outline.withOpacity(0.1)),
          _SettingsItem(
            icon: Icons.storage_outlined,
            title: '数据管理',
            subtitle: '清除本地数据',
            onTap: () {
            },
          ),
          Divider(height: 1, color: colorScheme.outline.withOpacity(0.1)),
          _SettingsItem(
            icon: Icons.info_outline,
            title: '关于 Solace',
            subtitle: '版本 1.0.0',
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const AboutScreen()));
            },
          ),
          Divider(height: 1, color: colorScheme.outline.withOpacity(0.1)),
          const SizedBox(height: 32),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ElevatedButton(
              onPressed: () {
                context.read<AuthBloc>().add(const AuthLogoutRequested());
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: colorScheme.errorContainer,
                foregroundColor: colorScheme.onErrorContainer,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text('退出登录'),
            ),
          ),
        ],
      ),
    );
  }

  void _updateAvatar(String? avatar) {
    if (avatar == null || avatar.isEmpty) {
      _saveAvatar(null);
      return;
    }
    _copyToPersistentPath(avatar);
  }

  Future<void> _copyToPersistentPath(String sourcePath) async {
    try {
      final source = File(sourcePath);
      if (!await source.exists()) {
        _saveAvatar(sourcePath);
        return;
      }
      final dir = await getApplicationDocumentsDirectory();
      final avatarDir = Directory('${dir.path}/avatars');
      if (!await avatarDir.exists()) {
        await avatarDir.create(recursive: true);
      }
      final ext = sourcePath.contains('.') ? sourcePath.split('.').last : 'jpg';
      final destPath = '${avatarDir.path}/user_avatar.$ext';
      await source.copy(destPath);
      _saveAvatar(destPath);
    } catch (e) {
      _saveAvatar(sourcePath);
    }
  }

  void _saveAvatar(String? path) {
    final authBloc = context.read<AuthBloc>();
    final currentState = authBloc.state as AuthAuthenticated;
    final updatedUser = currentState.user.copyWith(avatarUrl: path);
    authBloc.add(AuthUserUpdated(updatedUser));
  }

  void _showThemeDialog(BuildContext context) {
    final currentMode = context.read<ThemeBloc>().state.themeMode;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('选择主题'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<ThemeMode>(
              title: const Text('跟随系统'),
              value: ThemeMode.system,
              groupValue: currentMode,
              onChanged: (mode) {
                if (mode != null) {
                  context.read<ThemeBloc>().add(ThemeChanged(mode));
                  Navigator.pop(context);
                }
              },
            ),
            RadioListTile<ThemeMode>(
              title: const Text('浅色模式'),
              value: ThemeMode.light,
              groupValue: currentMode,
              onChanged: (mode) {
                if (mode != null) {
                  context.read<ThemeBloc>().add(ThemeChanged(mode));
                  Navigator.pop(context);
                }
              },
            ),
            RadioListTile<ThemeMode>(
              title: const Text('深色模式'),
              value: ThemeMode.dark,
              groupValue: currentMode,
              onChanged: (mode) {
                if (mode != null) {
                  context.read<ThemeBloc>().add(ThemeChanged(mode));
                  Navigator.pop(context);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

}

class _SettingsItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  const _SettingsItem({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            Icon(
              icon,
              color: colorScheme.primary,
              size: 28,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.onSurface.withOpacity(0.5),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: colorScheme.onSurface.withOpacity(0.3),
            ),
          ],
        ),
      ),
    );
  }
}

/// App 使用感知开关 — 让 AI 了解用户最近在用哪些 App
class _AppUsageAwarenessTile extends StatefulWidget {
  @override
  State<_AppUsageAwarenessTile> createState() => _AppUsageAwarenessTileState();
}

class _AppUsageAwarenessTileState extends State<_AppUsageAwarenessTile> {
  bool _enabled = false;
  bool _hasPermission = false;
  final _wellbeing = WellbeingService();

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  Future<void> _loadState() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(PrefKeys.appUsageAwareness) ?? false;
    final hasPerm = await _wellbeing.hasUsageAccess();
    if (mounted) {
      setState(() {
        _enabled = enabled;
        _hasPermission = hasPerm;
      });
    }
  }

  Future<void> _onChanged(bool value) async {
    if (value && !_hasPermission) {
      await _wellbeing.requestUsageAccess();
      final hasPerm = await _wellbeing.hasUsageAccess();
      if (!hasPerm) return;
      setState(() => _hasPermission = true);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(PrefKeys.appUsageAwareness, value);
    setState(() => _enabled = value);
  }

  void _showUsagePanel() async {
    if (!_hasPermission) {
      // 未授权，先引导授权
      await _wellbeing.requestUsageAccess();
      final hasPerm = await _wellbeing.hasUsageAccess();
      if (!hasPerm) return;
      setState(() => _hasPermission = true);
    }
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => const _UsageStatsDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Row(
        children: [
          Icon(Icons.insights_outlined, color: colorScheme.primary, size: 28),
          const SizedBox(width: 16),
          Expanded(
            child: GestureDetector(
              onTap: () => _onChanged(!_enabled),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'App 使用感知',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _enabled
                        ? 'AI 可感知你最近使用的 App'
                        : '开启后 AI 能了解你的 App 使用情况',
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurface.withOpacity(0.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_enabled)
            TextButton(
              onPressed: _showUsagePanel,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                '查看',
                style: TextStyle(fontSize: 13, color: colorScheme.primary),
              ),
            ),
          Switch(
            value: _enabled,
            onChanged: _onChanged,
            activeColor: colorScheme.primary,
          ),
        ],
      ),
    );
  }
}

/// App 使用情况面板 — 展示最近各 App 使用时长
class _UsageStatsDialog extends StatefulWidget {
  const _UsageStatsDialog();

  @override
  State<_UsageStatsDialog> createState() => _UsageStatsDialogState();
}

class _UsageStatsDialogState extends State<_UsageStatsDialog> {
  List<AppUsage> _usage = [];
  bool _loading = true;
  int _windowMinutes = 120; // 默认查看最近 2 小时

  @override
  void initState() {
    super.initState();
    _loadUsage();
  }

  Future<void> _loadUsage() async {
    setState(() => _loading = true);
    final usage = await WellbeingService().queryUsage(windowMinutes: _windowMinutes);
    // 过滤掉自身和极短使用，按时长降序
    usage.sort((a, b) => b.totalMs.compareTo(a.totalMs));
    final filtered = usage
        .where((u) => u.totalMs >= 60000 && !u.packageName.contains('com.solace.solace'))
        .toList();
    if (mounted) {
      setState(() {
        _usage = filtered;
        _loading = false;
      });
    }
  }

  String _formatDuration(int ms) {
    final minutes = (ms / 60000).round();
    if (minutes < 60) return '$minutes 分钟';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m > 0 ? '$h 小时 $m 分钟' : '$h 小时';
  }

  String _windowLabel() {
    switch (_windowMinutes) {
      case 60:
        return '1 小时';
      case 120:
        return '2 小时';
      case 360:
        return '6 小时';
      case 720:
        return '12 小时';
      case 1440:
        return '24 小时';
      default:
        return '$_windowMinutes 分钟';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AlertDialog(
      title: Row(
        children: [
          const Text('App 使用情况'),
          const Spacer(),
          // 时间窗口选择
          PopupMenuButton<int>(
            icon: Icon(Icons.schedule, size: 20, color: colorScheme.primary),
            onSelected: (v) {
              _windowMinutes = v;
              _loadUsage();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 60, child: Text('1 小时')),
              const PopupMenuItem(value: 120, child: Text('2 小时')),
              const PopupMenuItem(value: 360, child: Text('6 小时')),
              const PopupMenuItem(value: 720, child: Text('12 小时')),
              const PopupMenuItem(value: 1440, child: Text('24 小时')),
            ],
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: _loading
            ? const Center(child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(),
              ))
            : _usage.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        '最近${_windowLabel()}内没有其他 App 使用记录',
                        style: TextStyle(
                          color: colorScheme.onSurface.withOpacity(0.5),
                        ),
                      ),
                    ),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          '最近 ${_windowLabel()}',
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurface.withOpacity(0.4),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Flexible(
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: _usage.length,
                          itemBuilder: (_, i) {
                            final u = _usage[i];
                            final name = u.appName.isNotEmpty ? u.appName : u.packageName;
                            // 时长条形图：最长的是满宽
                            final maxMs = _usage.first.totalMs;
                            final ratio = maxMs > 0 ? u.totalMs / maxMs : 0.0;
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          name,
                                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        _formatDuration(u.totalMs),
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: colorScheme.primary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: LinearProgressIndicator(
                                      value: ratio,
                                      minHeight: 6,
                                      backgroundColor: isDark
                                          ? Colors.white.withOpacity(0.08)
                                          : Colors.black.withOpacity(0.06),
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        colorScheme.primary.withOpacity(0.7),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}