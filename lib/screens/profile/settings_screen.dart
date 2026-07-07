import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../blocs/theme/theme_bloc.dart';
import '../../config/tts_config.dart';
import '../../repositories/local_storage_repository.dart';
import '../settings/ai_config_screen.dart';
import '../settings/about_screen.dart';
import '../../utils/safe_file_picker.dart';

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

  @override
  void initState() {
    super.initState();
    _loadAgeAndModeSettings();
  }

  Future<void> _loadAgeAndModeSettings() async {
    final storage = RepositoryProvider.of<LocalStorageRepository>(context);
    final age = storage.getUserAge();

    if (mounted) {
      setState(() {
        _userAge = age;
        _isAdult = age != null && age >= 18;
        _globalMemoryMode = storage.getGlobalMemoryMode();
        _autoParagraphEnabled = storage.isAutoParagraphEnabled();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = colorScheme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF1A1A1A) : const Color(0xFFF8F9FA),
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
          _buildThemeCard(colorScheme, isDark),
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
          _buildSectionTitle('语音', colorScheme),
          _buildCard([
            _buildNavTile(
              icon: Icons.key_outlined,
              iconBgColor: Colors.orange.withOpacity(0.1),
              title: 'TTS API Key',
              subtitle: '配置小米 MiMo 语音合成密钥',
              onTap: () => _showTTSApiKeyDialog(context),
              colorScheme: colorScheme,
            ),
          ], colorScheme),
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

  Widget _buildThemeCard(ColorScheme colorScheme, bool isDark) {
    return BlocBuilder<ThemeBloc, ThemeState>(
      builder: (context, themeState) {
        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
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
    final isDark = colorScheme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
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
    required ValueChanged<bool> onChanged,
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
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 12, color: colorScheme.onSurfaceVariant)),
                ],
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
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

  Future<void> _showTTSApiKeyDialog(BuildContext context) async {
    final currentKey = await TTSConfig.getApiKey();
    final controller = TextEditingController(text: currentKey ?? '');
    final obscureNotifier = ValueNotifier<bool>(true);

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('配置 TTS API Key'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '输入小米 MiMo TTS 的 API Key，用于语音合成和音色克隆。',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 4),
            Text(
              '模型：mimo-v2.5-tts-voiceclone',
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
            ),
            const SizedBox(height: 16),
            ValueListenableBuilder<bool>(
              valueListenable: obscureNotifier,
              builder: (ctx, obscure, _) => TextField(
                controller: controller,
                obscureText: obscure,
                decoration: InputDecoration(
                  labelText: 'API Key',
                  hintText: 'sk-...',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon:
                        Icon(obscure ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => obscureNotifier.value = !obscure,
                  ),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          if (currentKey != null && currentKey.isNotEmpty)
            TextButton(
              onPressed: () async {
                await TTSConfig.clearApiKey();
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('已清除 TTS API Key')),
                  );
                }
              },
              child: const Text('清除', style: TextStyle(color: Colors.red)),
            ),
          FilledButton(
            onPressed: () async {
              final key = controller.text.trim();
              if (key.isEmpty) return;
              await TTSConfig.setApiKey(key);
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('TTS API Key 已保存'),
                      backgroundColor: Colors.green),
                );
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }
}
