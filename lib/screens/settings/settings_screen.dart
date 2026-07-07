import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path_provider/path_provider.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../blocs/theme/theme_bloc.dart';
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