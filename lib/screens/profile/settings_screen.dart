import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../blocs/theme/theme_bloc.dart';
import '../../config/constants.dart';
import '../../repositories/local_storage_repository.dart';
import '../settings/ai_config_screen.dart';
import '../settings/about_screen.dart';
import '../phone/phone_icon_preview_screen.dart';

import '../../utils/safe_file_picker.dart';
import '../../services/voice/mimo_tts_service.dart';
import '../voice/voice_stt_models_dialog.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notificationsEnabled = true;
  bool _vibrationEnabled = true;
  bool _momentsPublic = true;
  bool _isAdult = false;
  int? _userAge;
  String _globalMemoryMode = 'full';
  bool _autoParagraphEnabled = true;
  bool _phoneDesktopShell = false;

  @override
  void initState() {
    super.initState();
    _loadAgeAndModeSettings();
  }

  Future<void> _loadAgeAndModeSettings() async {
    final storage = RepositoryProvider.of<LocalStorageRepository>(context);
    final phoneDesktop = storage.isPhoneDesktopShellEnabled();
    final age = storage.getUserAge();

    if (mounted) {
      setState(() {
        _phoneDesktopShell = phoneDesktop;
        _userAge = age;
        _isAdult = age != null && age >= 18;
        _globalMemoryMode = storage.getGlobalMemoryMode();
        _autoParagraphEnabled = storage.isAutoParagraphEnabled();
      });
    }
  }

  Future<void> _openMiMoTtsSettings() async {
    final config = await MiMoTtsConfigStore.load();
    final controller = TextEditingController(text: config?.apiKey ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('MiMo TTS 设置'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '在 platform.xiaomimimo.com 注册后获取 API Key。\n'
              '用于音色克隆与角色语音合成（当前限时免费）。',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'API Key',
                hintText: 'sk-xxxxx',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              final key = controller.text.trim();
              if (key.isEmpty) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('API Key 不能为空')),
                );
                return;
              }
              await MiMoTtsConfigStore.save(key);
              if (ctx.mounted) Navigator.pop(ctx, true);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('MiMo TTS API Key 已保存')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text('设置'),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: colorScheme.onSurface,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          const SizedBox(height: 8),
          _buildThemeCard(colorScheme),
          const SizedBox(height: 12),
          _buildCard([
            _buildSwitchTile(
              icon: Icons.notifications_outlined,
              iconBgColor: colorScheme.primary.withOpacity(0.1),
              title: '接收通知',
              subtitle: '接收 AI 好友的消息通知',
              value: _notificationsEnabled,
              onChanged: (v) => setState(() => _notificationsEnabled = v),
              colorScheme: colorScheme,
            ),
            _buildDivider(colorScheme),
            _buildSwitchTile(
              icon: Icons.vibration,
              iconBgColor: colorScheme.secondary.withOpacity(0.1),
              title: '震动',
              subtitle: '消息震动提醒',
              value: _vibrationEnabled,
              onChanged: (v) => setState(() => _vibrationEnabled = v),
              colorScheme: colorScheme,
            ),
          ], colorScheme),
          const SizedBox(height: 12),
          _buildSectionTitle('AI 设置', colorScheme),
          _buildCard([
            _buildNavTile(
              icon: Icons.psychology_outlined,
              iconBgColor: Colors.amber.withOpacity(0.1),
              title: 'AI 配置',
              subtitle: '配置 AI 接口和模型',
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const AIConfigScreen())),
              colorScheme: colorScheme,
            ),
          ], colorScheme),
          const SizedBox(height: 12),
          _buildModeSettingsSection(colorScheme),
          const SizedBox(height: 12),
          _buildSectionTitle('AI 输出风格', colorScheme),
          _buildCard([
            _buildSwitchTile(
              icon: Icons.wrap_text,
              iconBgColor: Colors.cyan.withOpacity(0.1),
              title: '自动分段',
              subtitle:
                  _autoParagraphEnabled ? 'AI 长回复自动拆分为多条气泡' : 'AI 回复完整显示在一条气泡中',
              value: _autoParagraphEnabled,
              onChanged: (v) async {
                final storage =
                    RepositoryProvider.of<LocalStorageRepository>(context);
                await storage.setAutoParagraphEnabled(v);
                setState(() => _autoParagraphEnabled = v);
              },
              colorScheme: colorScheme,
            ),
            _buildDivider(colorScheme),
            _buildChoiceTile(
              icon: Icons.memory_outlined,
              iconBgColor: Colors.indigo.withOpacity(0.1),
              title: '记忆模式',
              subtitle: _memoryModeLabel(_globalMemoryMode),
              options: const ['full', 'token_saver', 'off'],
              labels: const ['完整', '省 token', '关闭'],
              current: _globalMemoryMode,
              onChanged: (v) async {
                final storage =
                    RepositoryProvider.of<LocalStorageRepository>(context);
                await storage.setGlobalMemoryMode(v);
                setState(() => _globalMemoryMode = v);
              },
              colorScheme: colorScheme,
            ),
          ], colorScheme),
          const SizedBox(height: 12),
          _buildSectionTitle('语音', colorScheme),
          _buildCard([
            _buildNavTile(
              icon: Icons.record_voice_over_outlined,
              iconBgColor: Colors.deepOrange.withOpacity(0.1),
              title: 'MiMo TTS 设置',
              subtitle: '配置 MiMo 语音合成 API Key（音色克隆 / 角色语音）',
              onTap: _openMiMoTtsSettings,
              colorScheme: colorScheme,
            ),
            _buildDivider(colorScheme),
            _buildNavTile(
              icon: Icons.hearing_outlined,
              iconBgColor: Colors.teal.withOpacity(0.1),
              title: '语音识别模型',
              subtitle: '导入/管理 STT（SenseVoice）与 VAD（Silero）本地模型',
              onTap: () => showDialog<void>(
                context: context,
                builder: (_) => const VoiceSttModelsDialog(),
              ),
              colorScheme: colorScheme,
            ),
          ], colorScheme),
          const SizedBox(height: 12),
          _buildSectionTitle('数据', colorScheme),
          _buildCard([
            _buildNavTile(
              icon: Icons.file_upload_outlined,
              iconBgColor: Colors.blue.withOpacity(0.1),
              title: '导出数据备份',
              subtitle: '将所有数据保存为备份文件',
              onTap: _exportBackup,
              colorScheme: colorScheme,
            ),
            _buildDivider(colorScheme),
            _buildNavTile(
              icon: Icons.file_download_outlined,
              iconBgColor: Colors.green.withOpacity(0.1),
              title: '导入数据备份',
              subtitle: '从备份文件恢复数据',
              onTap: _importBackup,
              colorScheme: colorScheme,
            ),
            _buildDivider(colorScheme),
            _buildNavTile(
              icon: Icons.shield_outlined,
              iconBgColor: Colors.blue.withOpacity(0.1),
              title: '年龄声明',
              subtitle: _userAge != null
                  ? '已完成 · ${_isAdult ? "18岁以上" : "15-18岁"}'
                  : '未完成',
              onTap: null,
              colorScheme: colorScheme,
            ),
          ], colorScheme),
          const SizedBox(height: 12),
          _buildSectionTitle('账号', colorScheme),
          _buildCard([
            _buildNavTile(
              icon: Icons.logout,
              iconBgColor: Colors.red.withOpacity(0.1),
              title: '退出登录',
              subtitle: '退出后数据将被清除，建议先备份',
              onTap: _showLogoutConfirm,
              colorScheme: colorScheme,
              isDanger: true,
            ),
          ], colorScheme),
          const SizedBox(height: 12),
          _buildSectionTitle('关于', colorScheme),
          _buildCard([
            _buildNavTile(
              icon: Icons.info_outline,
              iconBgColor: colorScheme.tertiary.withOpacity(0.1),
              title: '关于 Solace',
              subtitle: null,
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const AboutScreen())),
              colorScheme: colorScheme,
            ),
            _buildDivider(colorScheme),
            _buildNavTile(
              icon: Icons.privacy_tip_outlined,
              iconBgColor: colorScheme.tertiary.withOpacity(0.1),
              title: '隐私政策',
              subtitle: null,
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const AboutScreen())),
              colorScheme: colorScheme,
            ),
          ], colorScheme),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // 小说对白颜色预设（亮色主题；暗色在 hue 不变基础上提亮）——沿用旧模式面板 8 色
  static const List<Color> _kNovelPresetColors = [
    Color(0xFF2B7BF5), // 默认蓝
    Color(0xFF7B61FF), // 紫
    Color(0xFFE91E8C), // 粉
    Color(0xFF4CAF50), // 绿
    Color(0xFFFF9800), // 橙
    Color(0xFF00BCD4), // 青
    Color(0xFFF44336), // 红
    Color(0xFFFFAB00), // 金
  ];

  Widget _buildModeSettingsSection(ColorScheme colorScheme) {
    final storage = RepositoryProvider.of<LocalStorageRepository>(context);
    return ValueListenableBuilder<int>(
      valueListenable: storage.modeSettingsNotifier,
      builder: (context, _, __) {
        final novelOn = storage.isChatStyleNovelModeEnabled();
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _buildSectionTitle('模式与颜色', colorScheme),
          _buildCard([
            _buildSwitchTile(
              icon: Icons.smart_toy_outlined,
              iconBgColor: Colors.deepPurple.withOpacity(0.1),
              title: '纯AI视角',
              subtitle: 'AI 以底层模型本体身份回应，不进入角色',
              value: storage.isPureAiModeEnabled(),
              onChanged: (v) => _setModeSwitch(
                  storage, () => storage.setPureAiMode(v), v, '纯AI视角'),
              colorScheme: colorScheme,
            ),
            _buildDivider(colorScheme),
            _buildSwitchTile(
              icon: Icons.auto_stories_outlined,
              iconBgColor: Colors.teal.withOpacity(0.1),
              title: '小说模式',
              subtitle: '全局生效：所有聊天与 AI 创作使用小说叙事风格',
              value: novelOn,
              onChanged: (v) => _setModeSwitch(
                  storage, () => storage.setChatStyleMode(v), v, '小说模式'),
              colorScheme: colorScheme,
            ),
            if (novelOn) _buildNovelColorRow(storage, colorScheme),
            _buildDivider(colorScheme),
            _buildSwitchTile(
              icon: Icons.favorite_border,
              iconBgColor: Colors.pink.withOpacity(0.1),
              title: '恋人模式',
              subtitle: '允许恋爱陪伴、亲密称呼与情感互动',
              value: storage.isLoverModeEnabled(),
              onChanged: _isAdult
                  ? (v) => _setModeSwitch(
                      storage, () => storage.setLoverMode(v), v, '恋人模式')
                  : null,
              locked: !_isAdult,
              colorScheme: colorScheme,
            ),
            _buildDivider(colorScheme),
            _buildSwitchTile(
              icon: Icons.lock_open_outlined,
              iconBgColor: Colors.purple.withOpacity(0.1),
              title: '开放模式',
              subtitle: '允许更开放、更大胆的表达主题',
              value: storage.isOpenModeEnabled(),
              onChanged: _isAdult
                  ? (v) => _setModeSwitch(
                      storage, () => storage.setOpenMode(v), v, '开放模式')
                  : null,
              locked: !_isAdult,
              colorScheme: colorScheme,
            ),
            _buildDivider(colorScheme),
            _buildSwitchTile(
              icon: Icons.auto_awesome,
              iconBgColor: Colors.deepOrange.withOpacity(0.1),
              title: '法功能',
              subtitle: '沉浸式创作：不拒答、保留括号动作（18+）',
              value: storage.isFaModeEnabled(),
              onChanged: _isAdult
                  ? (v) => _setModeSwitch(storage, () async {
                        await storage.setFaMode(v);
                        await storage.setFaVerified(v);
                      }, v, '法功能')
                  : null,
              locked: !_isAdult,
              colorScheme: colorScheme,
            ),
            _buildDivider(colorScheme),
            _buildSwitchTile(
              icon: Icons.local_florist_outlined,
              iconBgColor: Colors.blueGrey.withOpacity(0.1),
              title: '刀模式',
              subtitle: '叠加小说模式：悲剧、虐心、遗憾与宿命感',
              value: storage.isDaoModeEnabled(),
              onChanged: (v) => _setModeSwitch(
                  storage, () => storage.setDaoMode(v), v, '刀模式'),
              colorScheme: colorScheme,
            ),
            _buildDivider(colorScheme),
            _buildSwitchTile(
              icon: Icons.book_rounded,
              iconBgColor: Colors.orange.withOpacity(0.1),
              title: '自动写日记',
              subtitle: '聊天结束后角色自动写一篇私人日记',
              value: storage.isAutoDiaryEnabled(),
              onChanged: (v) => _setModeSwitch(
                  storage, () => storage.setAutoDiaryEnabled(v), v, '自动写日记'),
              colorScheme: colorScheme,
            ),
          ], colorScheme),
        ]);
      },
    );
  }

  Widget _buildNovelColorRow(LocalStorageRepository storage, ColorScheme cs) {
    final current = storage.getNovelDialogueColor();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Row(
        children: [
          Icon(Icons.palette_outlined,
              size: 16, color: cs.onSurface.withOpacity(0.45)),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final color in _kNovelPresetColors)
                    _novelColorDot(storage, cs, color, current == color),
                  const SizedBox(width: 4),
                  Tooltip(
                    message: '恢复默认',
                    child: GestureDetector(
                      onTap: () => storage.setNovelDialogueColor(null),
                      child: Container(
                        width: 18,
                        height: 18,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: cs.outlineVariant.withOpacity(0.6),
                              width: 1),
                          color: cs.surfaceContainerHighest,
                        ),
                        child: Icon(Icons.refresh_rounded,
                            size: 11, color: cs.onSurface.withOpacity(0.5)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _novelColorDot(LocalStorageRepository storage, ColorScheme cs,
      Color color, bool selected) {
    return Tooltip(
      message:
          '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
      child: GestureDetector(
        onTap: () => storage.setNovelDialogueColor(color),
        child: Container(
          width: 18,
          height: 18,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            border: selected
                ? Border.all(color: cs.onSurface, width: 2)
                : Border.all(color: Colors.transparent, width: 2),
            boxShadow: selected
                ? [BoxShadow(color: color.withOpacity(0.5), blurRadius: 4)]
                : null,
          ),
        ),
      ),
    );
  }

  Future<void> _setModeSwitch(LocalStorageRepository storage,
      Future<void> Function() save, bool enabled, String name) async {
    await save();
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(enabled ? '$name已开启' : '$name已关闭'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Widget _buildThemeCard(ColorScheme colorScheme) {
    return BlocBuilder<ThemeBloc, ThemeState>(
      builder: (context, themeState) {
        return Container(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: colorScheme.shadow.withOpacity(0.08),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.palette_outlined,
                        size: 20, color: colorScheme.primary),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    '外观设置',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  _buildThemeOption(
                    context: context,
                    label: '浅色',
                    icon: Icons.light_mode_outlined,
                    isSelected: themeState.themeMode == ThemeMode.light,
                    onTap: () => context
                        .read<ThemeBloc>()
                        .add(const ThemeChanged(ThemeMode.light)),
                    colorScheme: colorScheme,
                  ),
                  const SizedBox(width: 10),
                  _buildThemeOption(
                    context: context,
                    label: '深色',
                    icon: Icons.dark_mode_outlined,
                    isSelected: themeState.themeMode == ThemeMode.dark,
                    onTap: () => context
                        .read<ThemeBloc>()
                        .add(const ThemeChanged(ThemeMode.dark)),
                    colorScheme: colorScheme,
                  ),
                  const SizedBox(width: 10),
                  _buildThemeOption(
                    context: context,
                    label: '跟随系统',
                    icon: Icons.settings_suggest_outlined,
                    isSelected: themeState.themeMode == ThemeMode.system,
                    onTap: () => context
                        .read<ThemeBloc>()
                        .add(const ThemeChanged(ThemeMode.system)),
                    colorScheme: colorScheme,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // 分割线
              Divider(
                  height: 1,
                  color: colorScheme.outlineVariant.withOpacity(0.5)),
              const SizedBox(height: 14),
              // 视觉风格切换
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colorScheme.secondary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.style_outlined,
                        size: 20, color: colorScheme.secondary),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    '视觉风格',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  // 风格切换按钮组
                  Container(
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildVisualStyleChip(
                          label: '经典',
                          isSelected:
                              themeState.visualStyle == VisualStyle.classic,
                          onTap: () => context.read<ThemeBloc>().add(
                              const VisualStyleChanged(VisualStyle.classic)),
                          colorScheme: colorScheme,
                        ),
                        _buildVisualStyleChip(
                          label: '现代',
                          isSelected:
                              themeState.visualStyle == VisualStyle.modernist,
                          onTap: () => context.read<ThemeBloc>().add(
                              const VisualStyleChanged(VisualStyle.modernist)),
                          colorScheme: colorScheme,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Divider(
                  height: 1,
                  color: colorScheme.outlineVariant.withOpacity(0.5)),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.phone_iphone_rounded,
                      size: 20, color: colorScheme.primary),
                ),
                title: const Text('虚拟手机桌面',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                subtitle: const Text('默认关闭。开启后主界面切换为小手机系统，可随时关闭回经典底部导航',
                    style: TextStyle(fontSize: 12)),
                value: _phoneDesktopShell,
                onChanged: (v) async {
                  final storage =
                      RepositoryProvider.of<LocalStorageRepository>(context);
                  await storage.setPhoneDesktopShellEnabled(v);
                  setState(() => _phoneDesktopShell = v);
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(v
                          ? '已开启小手机桌面。返回主界面即可看到；小手机内可点「关闭手机」退出。'
                          : '已关闭小手机桌面，主界面恢复经典底部导航。'),
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(seconds: 3),
                    ),
                  );
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.tertiary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.apps_rounded,
                      size: 20, color: colorScheme.tertiary),
                ),
                title: const Text('桌面图标预览',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                subtitle:
                    const Text('查看玻璃软图标效果', style: TextStyle(fontSize: 12)),
                trailing: const Icon(Icons.chevron_right, size: 20),
                onTap: () => Navigator.push(
                  context,
                  PhoneIconPreviewScreen.route(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildThemeOption({
    required BuildContext context,
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
    required ColorScheme colorScheme,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: isSelected ? colorScheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color:
                  isSelected ? colorScheme.primary : colorScheme.outlineVariant,
            ),
          ),
          child: Column(
            children: [
              Icon(icon,
                  size: 22,
                  color: isSelected
                      ? colorScheme.onPrimary
                      : colorScheme.onSurfaceVariant),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected
                      ? colorScheme.onPrimary
                      : colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVisualStyleChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    required ColorScheme colorScheme,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? colorScheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            color: isSelected
                ? colorScheme.onPrimary
                : colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: colorScheme.primary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildCard(List<Widget> children, ColorScheme colorScheme) {
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(children: children),
      ),
    );
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required Color iconBgColor,
    required String title,
    required String? subtitle,
    required bool value,
    required ValueChanged<bool>? onChanged,
    required ColorScheme colorScheme,
    bool locked = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconBgColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: colorScheme.onSurface),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Flexible(
                    child: Text(title,
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: locked
                                ? colorScheme.onSurface.withOpacity(0.45)
                                : null)),
                  ),
                  if (locked) ...[
                    const SizedBox(width: 6),
                    Icon(Icons.lock,
                        size: 13, color: colorScheme.onSurfaceVariant),
                  ],
                ]),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 12,
                          color: locked
                              ? colorScheme.onSurfaceVariant.withOpacity(0.6)
                              : colorScheme.onSurfaceVariant)),
                ],
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: locked ? null : onChanged,
            activeColor: colorScheme.primary,
          ),
        ],
      ),
    );
  }

  Widget _buildNavTile({
    required IconData icon,
    required Color iconBgColor,
    required String title,
    required String? subtitle,
    required VoidCallback? onTap,
    required ColorScheme colorScheme,
    bool isDanger = false,
  }) {
    final textColor = isDanger ? const Color(0xFFE53935) : null;

    return InkWell(
      onTap: onTap ?? () {},
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: iconBgColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon,
                  size: 20, color: textColor ?? colorScheme.onSurface),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: textColor)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: TextStyle(
                            fontSize: 12, color: colorScheme.onSurfaceVariant)),
                  ],
                ],
              ),
            ),
            Icon(Icons.chevron_right,
                size: 20, color: colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  Widget _buildChoiceTile({
    required IconData icon,
    required Color iconBgColor,
    required String title,
    required String subtitle,
    required List<String> options,
    required List<String> labels,
    required String current,
    required ValueChanged<String> onChanged,
    required ColorScheme colorScheme,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconBgColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: colorScheme.onSurface),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: TextStyle(
                        fontSize: 12, color: colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          DropdownButton<String>(
            value: current,
            underline: const SizedBox.shrink(),
            items: List.generate(
              options.length,
              (i) =>
                  DropdownMenuItem(value: options[i], child: Text(labels[i])),
            ),
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDivider(ColorScheme colorScheme) {
    return Divider(
        height: 1,
        indent: 58,
        endIndent: 16,
        color: colorScheme.outlineVariant);
  }

  String _memoryModeLabel(String mode) {
    switch (mode) {
      case 'full':
        return '完整 · 保留最佳记忆体';
      case 'token_saver':
        return '省 token · 压缩记忆';
      case 'off':
        return '关闭 · 对话请求不携带长期记忆';
      default:
        return mode;
    }
  }

  Future<void> _exportBackup() async {
    try {
      final storage = RepositoryProvider.of<LocalStorageRepository>(context);

      // 显示进度弹窗
      final progress = ValueNotifier<String>('准备导出...');
      final progressVal = ValueNotifier<double>(0);
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => ValueListenableBuilder<String>(
            valueListenable: progress,
            builder: (_, msg, __) => ValueListenableBuilder<double>(
              valueListenable: progressVal,
              builder: (_, val, __) => AlertDialog(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(value: val > 0 ? val : null),
                    const SizedBox(height: 16),
                    Text(msg),
                    if (val > 0) ...[
                      const SizedBox(height: 8),
                      LinearProgressIndicator(value: val),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      }

      final bytes = await storage.exportToBytes(
        onProgress: (p, msg) {
          progressVal.value = p;
          progress.value = msg;
        },
      );

      // 关闭进度弹窗
      if (mounted) Navigator.pop(context);

      // 先验证导出内容完整性
      try {
        await storage.importFromBytes(bytes, validateOnly: true);
      } catch (e) {
        throw Exception('导出数据验证失败: $e');
      }

      if (!mounted) return;

      final fileName =
          'Solace_备份_${DateTime.now().millisecondsSinceEpoch}.solace';

      // 保存策略：
      // 1. 优先保存到外部公共下载目录 /Download/（用户可访问）
      // 2. 如果不可用，保存到 /storage/emulated/0/Solace/（应用专属公共目录）
      // 3. 最后才使用内部应用目录（用户无法访问，作为兜底）
      String? savePath;

      // 尝试 1: /storage/emulated/0/Download/
      try {
        final downloadDir = Directory('/storage/emulated/0/Download');
        if (await downloadDir.exists()) {
          final file = File('${downloadDir.path}/$fileName');
          await file.writeAsBytes(bytes);
          savePath = file.path;
        }
      } catch (_) {}

      // 尝试 2: /storage/emulated/0/Solace/（应用专属公共目录）
      if (savePath == null) {
        try {
          final solaceDir = Directory('/storage/emulated/0/Solace');
          if (!await solaceDir.exists()) {
            await solaceDir.create(recursive: true);
          }
          final file = File('${solaceDir.path}/$fileName');
          await file.writeAsBytes(bytes);
          savePath = file.path;
        } catch (_) {}
      }

      // 尝试 3: 内部应用目录（兜底）
      if (savePath == null) {
        final internalDir = await getApplicationDocumentsDirectory();
        final file = File('${internalDir.path}/$fileName');
        await file.writeAsBytes(bytes);
        savePath = file.path;
      }

      if (!mounted) return;

      // 判断保存位置是否用户可访问
      final isPublicPath = savePath!.contains('/storage/emulated/0/');

      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green),
              SizedBox(width: 8),
              Text('导出成功'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isPublicPath) ...[
                const Text('备份文件已保存到公共目录。'),
              ] else ...[
                const Text('备份文件已保存到应用内部目录。'),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.lightbulb_outline,
                        size: 16, color: Colors.amber),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        '提示：该目录需要 root 权限才能访问。',
                        style: TextStyle(fontSize: 12, color: Colors.orange),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  fileName,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                ),
              ),
              if (isPublicPath) ...[
                const SizedBox(height: 8),
                Text(
                  '路径：$savePath',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.lightbulb_outline,
                      size: 16, color: Colors.amber),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '备份文件可用于换设备迁移，可通过微信/QQ/蓝牙等方式传输。',
                      style: TextStyle(fontSize: 13, color: Colors.orange),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('导出失败: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _importBackup() async {
    try {
      final result = await SafeFilePicker.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('未选择文件')));
        }
        return;
      }
      final filePath = result.files.single.path;
      if (filePath == null) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('无法读取文件路径')));
        }
        return;
      }

      // 显示 loading
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => const Center(
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('正在读取备份文件...'),
                  ],
                ),
              ),
            ),
          ),
        );
      }

      Map<String, dynamic> validationResult;
      List<int> bytes;
      try {
        final file = File(filePath);
        bytes = await file.readAsBytes();
        final storage = RepositoryProvider.of<LocalStorageRepository>(context);
        validationResult =
            await storage.importFromBytes(bytes, validateOnly: true);
      } catch (e) {
        if (mounted) Navigator.pop(context); // 关闭 loading
        rethrow;
      }

      if (mounted) Navigator.pop(context); // 关闭 loading

      if (mounted) {
        final accountInfo = validationResult['accountInfo'] as String?;
        final version = validationResult['version'] as int;
        final exportTime = validationResult['exportTime'] as String?;

        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text('确认导入备份'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('备份版本: $version'),
                const SizedBox(height: 4),
                Text('导出时间: ${exportTime ?? "未知"}'),
                if (accountInfo != null) ...[
                  const SizedBox(height: 4),
                  Text('账号信息: $accountInfo'),
                ],
                const SizedBox(height: 12),
                const Text(
                  '将合并导入备份数据：已有数据更新，缺少数据补齐，本地独有数据保留。',
                  style: TextStyle(
                      color: Colors.orange, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
              TextButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  // 显示带进度的导入弹窗
                  final progress = ValueNotifier<String>('准备导入...');
                  final progressVal = ValueNotifier<double>(0);
                  if (mounted) {
                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) => ValueListenableBuilder<String>(
                        valueListenable: progress,
                        builder: (_, msg, __) => ValueListenableBuilder<double>(
                          valueListenable: progressVal,
                          builder: (_, val, __) => AlertDialog(
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20)),
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircularProgressIndicator(
                                    value: val > 0 ? val : null),
                                const SizedBox(height: 16),
                                Text(msg),
                                if (val > 0) ...[
                                  const SizedBox(height: 8),
                                  LinearProgressIndicator(value: val),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }
                  try {
                    final storage =
                        RepositoryProvider.of<LocalStorageRepository>(context);
                    await storage.importFromBytes(
                      bytes,
                      onProgress: (p, msg) {
                        progressVal.value = p;
                        progress.value = msg;
                      },
                    );
                    if (mounted) Navigator.pop(context); // 关闭进度弹窗
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('数据恢复成功！重启应用后生效'),
                          backgroundColor: Colors.green));
                    }
                  } catch (e) {
                    if (mounted) Navigator.pop(context); // 关闭进度弹窗
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text('导入失败: $e'),
                          backgroundColor: Colors.red));
                    }
                  }
                },
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('确认导入'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('导入失败: $e'), backgroundColor: Colors.red));
      }
    }
  }

  void _showLogoutConfirm() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [
          Icon(Icons.warning_amber, color: Colors.orange),
          SizedBox(width: 8),
          Text('退出确认 1/3')
        ]),
        content: const Text('是否先导出备份？退出后所有本地数据将被清除，无法恢复。'),
        actions: [
          TextButton(
              onPressed: () {
                Navigator.pop(context);
                _confirmLogoutStep2();
              },
              child:
                  const Text('不备份，直接退出', style: TextStyle(color: Colors.red))),
          TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await _exportBackup();
                _confirmLogoutStep2();
              },
              child: const Text('先导出备份')),
        ],
      ),
    );
  }

  void _confirmLogoutStep2() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [
          Icon(Icons.warning_amber, color: Colors.orange),
          SizedBox(width: 8),
          Text('退出确认 2/3')
        ]),
        content: const Text('确定要退出登录吗？退出后当前账号的所有数据将被清除。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(
              onPressed: () {
                Navigator.pop(context);
                _confirmLogoutStep3();
              },
              style: TextButton.styleFrom(foregroundColor: Colors.orange),
              child: const Text('继续')),
        ],
      ),
    );
  }

  void _confirmLogoutStep3() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [
          Icon(Icons.logout, size: 22, color: Colors.red),
          SizedBox(width: 8),
          Text('退出确认 3/3')
        ]),
        content: const Text('最后确认：退出后将清除所有本地数据，此操作不可恢复！'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                final storage =
                    RepositoryProvider.of<LocalStorageRepository>(context);
                await storage.clearAllData();
                if (mounted) {
                  context.read<AuthBloc>().add(AuthLogoutRequested());
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('退出失败: $e'), backgroundColor: Colors.red));
                }
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('确认退出并清除数据'),
          ),
        ],
      ),
    );
  }
}
