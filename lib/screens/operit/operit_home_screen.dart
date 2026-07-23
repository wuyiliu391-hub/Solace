import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../blocs/chat/chat_bloc.dart';
import '../../models/chat_message.dart';
import '../../models/chat_session.dart';
import '../../config/constants.dart';
import '../../repositories/local_storage_repository.dart';
import '../../services/accessibility_service.dart';
import '../../services/screenshot_service.dart';
import '../../services/agnes_vision_service.dart';
import '../../services/device_notification_service.dart';
import '../../services/device_service.dart';
import '../chat/chat_detail_screen.dart';
import 'device_agent_audit_screen.dart';
import 'operit_capabilities_screen.dart';

/// Operit Tab — 设备感知+操控中心
///
/// 紧凑控制面板风格，避免大卡片堆叠。
class OperitHomeScreen extends StatefulWidget {
  const OperitHomeScreen({super.key});

  @override
  State<OperitHomeScreen> createState() => _OperitHomeScreenState();
}

class _OperitHomeScreenState extends State<OperitHomeScreen> {
  bool _a11yEnabled = false;
  bool _screenshotEnabled = false;
  bool _agnesConfigured = false;
  bool _shizukuOk = false;
  int _notificationCount = 0;
  String _currentApp = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refreshStatus();
  }

  Future<void> _refreshStatus() async {
    setState(() => _loading = true);
    try {
      final a11y =
          await AccessibilityService().isEnabled().catchError((_) => false);
      final screenshot =
          await ScreenshotService().hasPermission().catchError((_) => false);
      final agnes =
          await AgnesVisionService.isConfigured().catchError((_) => false);
      final notifCount =
          await DeviceNotificationService().getCount().catchError((_) => 0);
      final appInfo = await AccessibilityService()
          .getCurrentApp()
          .catchError((_) => CurrentAppInfo());
      final shizukuStatus = await DeviceService().getShizukuStatus();
      final shizukuOk = shizukuStatus['available'] == true &&
          shizukuStatus['permitted'] == true;

      if (mounted) {
        setState(() {
          _a11yEnabled = a11y;
          _screenshotEnabled = screenshot;
          _agnesConfigured = agnes;
          _shizukuOk = shizukuOk;
          _notificationCount = notifCount;
          _currentApp = appInfo.displayName;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dividerColor = isDark
        ? Colors.white.withOpacity(0.06)
        : Colors.black.withOpacity(0.06);

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0A0A0A) : colorScheme.surface,
      appBar: AppBar(
        title: const Text('Operit',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: _refreshStatus,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refreshStatus,
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  _buildPermissionBar(colorScheme, isDark, dividerColor),
                  _buildDeviceAgentSection(colorScheme, isDark, dividerColor),
                  _buildSectionHeader('快捷操作', colorScheme,
                      trailing: _buildCapabilityLink(colorScheme)),
                  _buildQuickActionGrid(colorScheme, isDark, dividerColor),
                  const SizedBox(height: 16),
                  _buildSectionHeader('设备状态', colorScheme),
                  _buildDeviceList(colorScheme, isDark, dividerColor),
                  const SizedBox(height: 16),
                  if (_notificationCount > 0) ...[
                    _buildSectionHeader(
                        '最近通知 ($_notificationCount)', colorScheme),
                    _buildNotificationList(colorScheme, isDark, dividerColor),
                  ],
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }

  // ═══════════════════════════════════════════
  // 权限状态条（紧凑横条，非大卡片）
  // ═══════════════════════════════════════════

  Widget _buildPermissionBar(
      ColorScheme colorScheme, bool isDark, Color dividerColor) {
    final perms = [
      ('无障碍', _a11yEnabled, _openAccessibilitySettings),
      ('截图', _screenshotEnabled, _requestScreenshotPermission),
      ('Agnes', _agnesConfigured, _showAgnesConfigDialog),
      ('Shizuku', _shizukuOk, () => _requestShizukuPermission()),
    ];

    final allOk = perms.every((p) => p.$2);

    return Column(
      children: [
        if (!allOk)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.08),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 14, color: Colors.orange[700]),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '部分权限未开启，点击对应标签快速授权',
                    style: TextStyle(fontSize: 11, color: Colors.orange[700]),
                  ),
                ),
              ],
            ),
          ),
        Container(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: dividerColor, width: 0.5)),
          ),
          child: Row(
            children: perms.map((p) {
              final (label, enabled, onTap) = p;
              return Expanded(
                child: GestureDetector(
                  onTap: enabled ? null : onTap,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: enabled ? Colors.green : Colors.red,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: enabled
                                ? colorScheme.onSurface.withOpacity(0.7)
                                : Colors.red[700],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildDeviceAgentSection(
      ColorScheme colorScheme, bool isDark, Color dividerColor) {
    final repo = context.read<LocalStorageRepository>();
    return ValueListenableBuilder<int>(
      valueListenable: repo.modeSettingsNotifier,
      builder: (context, _, __) {
        final master = repo.isDeviceAgentMasterEnabled();
        final perms = <(String, String)>[
          (PrefKeys.devicePermissionRead, '读取（电量/应用/通知/截图）'),
          (PrefKeys.devicePermissionDisplay, '亮度'),
          (PrefKeys.devicePermissionAudio, '音量/静音'),
          (PrefKeys.devicePermissionLock, '锁屏/桌面/返回'),
          (PrefKeys.devicePermissionApp, '打开/关闭应用'),
          (PrefKeys.devicePermissionNetwork, 'WiFi/蓝牙'),
          (PrefKeys.devicePermissionUi, '点击/滑动/输入'),
          (PrefKeys.devicePermissionShell, 'Shell 命令'),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader('角色主动操控', colorScheme),
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              decoration: BoxDecoration(
                border: Border.all(color: dividerColor),
                borderRadius: BorderRadius.circular(12),
                color: isDark
                    ? Colors.white.withOpacity(0.03)
                    : Colors.black.withOpacity(0.02),
              ),
              child: Column(
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text('允许角色主动操控设备',
                        style: TextStyle(fontSize: 14)),
                    subtitle: Text(
                      master
                          ? '角色聊天可输出设备动作（需 Shizuku；纯AI关闭）'
                          : '默认关闭。开启后按子权限执行全部 Shizuku 能力',
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onSurface.withOpacity(0.55),
                      ),
                    ),
                    value: master,
                    onChanged: (v) async {
                      if (v && !_shizukuOk) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('请先授权 Shizuku')),
                        );
                        return;
                      }
                      await repo.setDeviceAgentMasterEnabled(v);
                    },
                  ),
                  if (master) ...[
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: const Text('小说/法模式也允许',
                          style: TextStyle(fontSize: 13)),
                      subtitle: Text(
                        '默认关：叙事模式不注入设备能力，防混乱',
                        style: TextStyle(
                          fontSize: 10,
                          color: colorScheme.onSurface.withOpacity(0.5),
                        ),
                      ),
                      value: repo.isDeviceAgentAllowInNarrative(),
                      onChanged: (v) =>
                          repo.setDeviceAgentAllowInNarrative(v),
                    ),
                    const Divider(height: 8),
                    for (final p in perms)
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text(p.$2, style: const TextStyle(fontSize: 13)),
                        value: repo.isDevicePermissionEnabled(p.$1),
                        onChanged: (v) =>
                            repo.setDevicePermissionEnabled(p.$1, v),
                      ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const DeviceAgentAuditScreen(),
                          ),
                        ),
                        icon: const Icon(Icons.history, size: 16),
                        label: const Text('审计日志',
                            style: TextStyle(fontSize: 12)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  // ═══════════════════════════════════════════
  // 通用 section header
  // ═══════════════════════════════════════════

  Widget _buildSectionHeader(String title, ColorScheme colorScheme,
      {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 6),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface.withOpacity(0.5),
            ),
          ),
          const Spacer(),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Widget _buildCapabilityLink(ColorScheme colorScheme) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const OperitCapabilitiesScreen()),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.menu_book_outlined, size: 13, color: colorScheme.primary),
          const SizedBox(width: 3),
          Text('能力手册',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: colorScheme.primary)),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════
  // 快捷操作（紧凑网格，无阴影）
  // ═══════════════════════════════════════════

  Widget _buildQuickActionGrid(
      ColorScheme colorScheme, bool isDark, Color dividerColor) {
    final actions = [
      _QuickAction(
          '打开微信', Icons.chat_bubble_outline, '打开微信应用', _ActionType.system),
      _QuickAction('打开QQ', Icons.forum_outlined, '打开QQ应用', _ActionType.system),
      _QuickAction(
          '打开相册', Icons.photo_library_outlined, '打开相册应用', _ActionType.system),
      _QuickAction('锁屏', Icons.lock_outline, '锁定设备屏幕', _ActionType.system),
      _QuickAction(
          '调节音量', Icons.volume_up_outlined, '调节设备音量', _ActionType.system),
      _QuickAction(
          '开启静音', Icons.volume_off_outlined, '开启静音模式', _ActionType.system),
      _QuickAction(
          '关闭静音', Icons.volume_down_outlined, '关闭静音模式', _ActionType.system),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 1,
        crossAxisSpacing: 1,
        childAspectRatio: 1.1,
      ),
      itemCount: actions.length,
      itemBuilder: (context, index) {
        final action = actions[index];
        return _buildActionTile(action, colorScheme, isDark);
      },
    );
  }

  Widget _buildActionTile(
      _QuickAction action, ColorScheme colorScheme, bool isDark) {
    return GestureDetector(
      onTap: () => _pickCharacterThenRun(action),
      child: Container(
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withOpacity(0.03)
              : Colors.black.withOpacity(0.015),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(action.icon, size: 22, color: colorScheme.primary),
            const SizedBox(height: 6),
            Text(
              action.label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: colorScheme.onSurface.withOpacity(0.8),
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════
  // 设备状态（紧凑列表行）
  // ═══════════════════════════════════════════

  Widget _buildDeviceList(
      ColorScheme colorScheme, bool isDark, Color dividerColor) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: dividerColor, width: 0.5),
      ),
      child: Column(
        children: [
          _buildListTile(
            icon: Icons.phone_android,
            label: '当前应用',
            value: _currentApp.isNotEmpty ? _currentApp : '未知',
            colorScheme: colorScheme,
            dividerColor: dividerColor,
          ),
          _buildListTile(
            icon: Icons.notifications_outlined,
            label: '通知数量',
            value: '$_notificationCount 条',
            colorScheme: colorScheme,
            dividerColor: dividerColor,
          ),
        ],
      ),
    );
  }

  Widget _buildListTile({
    required IconData icon,
    required String label,
    required String value,
    required ColorScheme colorScheme,
    required Color dividerColor,
    bool showDivider = true,
  }) {
    return Container(
      decoration: showDivider
          ? BoxDecoration(
              border:
                  Border(bottom: BorderSide(color: dividerColor, width: 0.5)))
          : null,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 16, color: colorScheme.onSurface.withOpacity(0.4)),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════
  // 通知列表（紧凑行）
  // ═══════════════════════════════════════════

  Widget _buildNotificationList(
      ColorScheme colorScheme, bool isDark, Color dividerColor) {
    return FutureBuilder<List<dynamic>>(
      future: DeviceNotificationService().getNotifications(limit: 5),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: Text(
                '暂无通知',
                style: TextStyle(
                    fontSize: 13, color: colorScheme.onSurface.withOpacity(0.4)),
              ),
            ),
          );
        }
        final notifications = snapshot.data!;
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: dividerColor, width: 0.5),
          ),
          child: Column(
            children: notifications.asMap().entries.map((entry) {
              final notif = entry.value as dynamic;
              final isLast = entry.key == notifications.length - 1;
              return _buildListTile(
                icon: Icons.circle_notifications_outlined,
                label: notif.title ?? '',
                value: _formatTime(notif.timestamp),
                colorScheme: colorScheme,
                dividerColor: dividerColor,
                showDivider: !isLast,
              );
            }).toList(),
          ),
        );
      },
    );
  }

  String _formatTime(int timestamp) {
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    if (dt.day == now.day && dt.month == now.month && dt.year == now.year) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  // ═══════════════════════════════════════════
  // 角色选择 + 执行自动化任务
  // ═══════════════════════════════════════════

  void _pickCharacterThenRun(_QuickAction action) async {
    // System actions execute directly through DeviceService / Shizuku.
    if (action.actionType == _ActionType.system) {
      _executeSystemAction(action);
      return;
    }

    // VisionAction path: requires all three permissions + character selection
    if (!_a11yEnabled || !_screenshotEnabled || !_agnesConfigured) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('请先开启所需权限'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    // Load available characters for vision tasks
    final storage = context.read<LocalStorageRepository>();
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) return;

    final characters = await storage.getAllAICharacters();
    final sessions = await storage.getChatSessions(authState.user.id);

    // Find session for each character
    final charSessions = <dynamic, dynamic>{};
    for (final s in sessions) {
      final ch = characters.firstWhere(
        (c) => c.id == s.aiCharacterId,
        orElse: () => null as dynamic,
      );
      if (ch != null) charSessions[ch] = s;
    }

    if (!mounted) return;
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.smart_toy_rounded,
                      color: colorScheme.primary, size: 22),
                  const SizedBox(width: 8),
                  Text(
                    '选择角色执行',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${action.label} — 由哪个角色帮你操作？',
                style: TextStyle(
                  fontSize: 13,
                  color: colorScheme.onSurface.withOpacity(0.5),
                ),
              ),
              const SizedBox(height: 16),
              ...characters.map((ch) {
                final session = charSessions[ch];
                final avatar = ch.avatarUrl ?? '';
                return ListTile(
                  leading: CircleAvatar(
                    radius: 20,
                    backgroundColor: Colors.grey[800],
                    backgroundImage:
                        avatar.isNotEmpty ? AssetImage(avatar) : null,
                    child: avatar.isEmpty
                        ? Text(ch.name[0],
                            style: TextStyle(color: colorScheme.onSurface))
                        : null,
                  ),
                  title: Text(
                    ch.name,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  subtitle: session != null
                      ? Text('已有聊天记录',
                          style: TextStyle(
                              fontSize: 12,
                              color: colorScheme.onSurface.withOpacity(0.4)))
                      : null,
                  trailing: const Icon(Icons.chevron_right),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _executeVisionAction(action, ch, session);
                  },
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  /// Execute a system action directly via DeviceService / Shizuku.
  Future<void> _executeSystemAction(_QuickAction action) async {
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) return;

    final storage = context.read<LocalStorageRepository>();
    final device = DeviceService();

    final characters = await storage.getAllAICharacters();
    if (characters.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('没有可用的AI角色，请先创建一个角色')),
        );
      }
      return;
    }
    final character = characters.first;

    final sessions = await storage.getChatSessions(authState.user.id);
    var targetSession = sessions.cast<ChatSession?>().firstWhere(
          (s) => s!.aiCharacterId == character.id,
          orElse: () => null,
        );
    if (targetSession == null) {
      targetSession = ChatSession(
        id: const Uuid().v4(),
        userId: authState.user.id,
        aiCharacterId: character.id,
        aiCharacterName: character.name,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await storage.saveChatSession(targetSession);
    }

    String resultMessage;
    bool success;
    final executionDetail = StringBuffer();
    executionDetail.writeln('执行系统操作: ${action.label}');
    executionDetail.writeln('   时间: ${DateTime.now().toString().substring(0, 19)}');

    switch (action.label) {
      case '打开微信':
        success = await device.startApp('com.tencent.mm');
        executionDetail.writeln('   结果: ${success ? "成功" : "失败"}');
        resultMessage = success ? '微信已打开' : '打开微信失败，请确认微信已安装';
        break;
      case '打开QQ':
        success = await device.startApp('com.tencent.mobileqq');
        executionDetail.writeln('   结果: ${success ? "成功" : "失败"}');
        resultMessage = success ? 'QQ已打开' : '打开QQ失败，请确认QQ已安装';
        break;
      case '打开相册':
        success = await device.openGallery();
        executionDetail.writeln('   结果: ${success ? "成功" : "失败"}');
        resultMessage = success ? '相册已打开' : '打开相册失败';
        break;
      case '锁屏':
        success = await device.lockScreen();
        executionDetail.writeln('   结果: ${success ? "成功" : "失败"}');
        resultMessage = success ? '屏幕已锁定' : '锁屏失败，请启动Shizuku并授予Solace权限';
        break;
      case '调节音量':
        success = await device.adjustVolume(true, showUi: true);
        executionDetail.writeln('   结果: ${success ? "成功" : "失败"}');
        resultMessage = success ? '音量已调大' : '音量调节失败，请启动Shizuku并授予Solace权限';
        break;
      case '开启静音':
        success = await device.setMuteMode(0);
        executionDetail.writeln('   结果: ${success ? "成功" : "失败"}');
        resultMessage = success ? '已开启静音模式' : '静音设置失败，请启动Shizuku并授予Solace权限';
        break;
      case '关闭静音':
        success = await device.setMuteMode(2);
        executionDetail.writeln('   结果: ${success ? "成功" : "失败"}');
        resultMessage = success ? '已关闭静音模式' : '取消静音失败，请启动Shizuku并授予Solace权限';
        break;
      default:
        success = false;
        resultMessage = '未知操作';
    }

    final now = DateTime.now();

    final userMsg = ChatMessage(
      id: const Uuid().v4(),
      chatId: targetSession.id,
      senderId: authState.user.id,
      content: action.taskDescription,
      type: MessageType.text,
      status: MessageStatus.sent,
      createdAt: now,
      isUser: true,
    );
    await storage.saveChatMessage(userMsg);

    final aiMsg = ChatMessage(
      id: const Uuid().v4(),
      chatId: targetSession.id,
      senderId: 'ai_${character.id}',
      senderName: character.name,
      content: resultMessage,
      type: MessageType.text,
      status: MessageStatus.sent,
      createdAt: now.add(const Duration(milliseconds: 1)),
      isUser: false,
      reasoning: executionDetail.toString(),
      metadata: {
        'actionType': 'system',
        'actionLabel': action.label,
        'success': success,
      },
    );
    await storage.saveChatMessage(aiMsg);

    await storage.updateChatSessionLastMessage(
      targetSession.id,
      resultMessage,
      now.add(const Duration(milliseconds: 1)),
    );

    if (mounted) {
      final chatBloc = context.read<ChatBloc>();
      final session = targetSession;
      if (session == null) return;
      chatBloc.add(ChatLoadMessages(session.id));
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => BlocProvider.value(
            value: chatBloc,
            child: ChatDetailScreen(session: session),
          ),
        ),
      );
    }
  }

  /// Execute a vision-based action via AutoGLM.
  void _executeVisionAction(
      _QuickAction action, dynamic character, dynamic session) async {
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) return;
    final storage = context.read<LocalStorageRepository>();
    final chatBloc = context.read<ChatBloc>();

    var targetSession = session;
    if (targetSession == null) {
      final newSession = ChatSession(
        id: const Uuid().v4(),
        userId: authState.user.id,
        aiCharacterId: character.id,
        aiCharacterName: character.name,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await storage.saveChatSession(newSession);
      targetSession = newSession;
    }

    final task = action.taskDescription;
    if (!mounted) return;

    chatBloc.add(ChatRunAutoGlm(
      chatId: targetSession.id,
      userId: authState.user.id,
      task: task,
    ));

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => BlocProvider.value(
            value: chatBloc,
            child: ChatDetailScreen(session: targetSession),
          ),
        ),
      );
    }
  }

  // ═══════════════════════════════════════════
  // 权限跳转
  // ═══════════════════════════════════════════

  void _openAccessibilitySettings() async {
    await AccessibilityService().requestAccess();
    await Future.delayed(const Duration(seconds: 2));
    _refreshStatus();
  }

  void _requestScreenshotPermission() async {
    final ok =
        await ScreenshotService().requestPermissionAndWait(maxWaitMs: 10000);
    _refreshStatus();
  }

  void _requestShizukuPermission() async {
    final ds = DeviceService();
    final status = await ds.getShizukuStatus();
    final available = status['available'] == true;
    final permitted = status['permitted'] == true;
    if (!available) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Shizuku 服务未运行，请在 Shizuku App 中启动')),
        );
      }
      return;
    }
    if (permitted) return;
    final result = await ds.requestShizukuPermission();
    if (mounted && result == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Shizuku 授权成功')),
      );
      _refreshStatus();
    }
  }

  void _showAgnesConfigDialog() async {
    final savedKey = await AgnesVisionService.getApiKey() ?? '';
    final savedUrl = await AgnesVisionService.getBaseUrl();
    final savedModel = await AgnesVisionService.getModel();

    final keyController = TextEditingController(text: savedKey);
    final urlController = TextEditingController(text: savedUrl);
    final modelController = TextEditingController(text: savedModel);
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: isDark ? const Color(0xFF2A2A2A) : Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              const Icon(Icons.visibility, size: 20),
              const SizedBox(width: 8),
              const Text('多模态视觉 API', style: TextStyle(fontSize: 18)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '用于截图识图。支持 OpenAI 兼容接口的多模态模型。',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: keyController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'API Key',
                    hintText: 'sk-...',
                    prefixIcon: const Icon(Icons.key, size: 18),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 14),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: urlController,
                  decoration: InputDecoration(
                    labelText: 'Base URL',
                    hintText: 'https://api.openai.com/v1',
                    prefixIcon: const Icon(Icons.link, size: 18),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 14),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: modelController,
                  decoration: InputDecoration(
                    labelText: '模型名',
                    hintText: 'gpt-4o / gemini-2.0-flash / qwen-vl-max',
                    prefixIcon: const Icon(Icons.memory, size: 18),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 14),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await AgnesVisionService.setApiKey('');
                if (mounted) {
                  Navigator.pop(ctx);
                  _refreshStatus();
                }
              },
              child: Text('清空',
                  style: TextStyle(
                    color: isDark ? Colors.white70 : Colors.black54,
                  )),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('取消',
                  style: TextStyle(
                    color: isDark ? Colors.white70 : Colors.black54,
                  )),
            ),
            FilledButton(
              onPressed: () async {
                if (keyController.text.trim().isNotEmpty) {
                  await AgnesVisionService.setApiKey(keyController.text.trim());
                  if (urlController.text.trim().isNotEmpty) {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setString(
                        'agnes_base_url', urlController.text.trim());
                  }
                  if (modelController.text.trim().isNotEmpty) {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setString(
                        'agnes_model', modelController.text.trim());
                  }
                  if (mounted) {
                    Navigator.pop(ctx);
                    _refreshStatus();
                  }
                }
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickAction {
  final String label;
  final IconData icon;
  final String taskDescription;
  final _ActionType actionType;

  const _QuickAction(
      this.label, this.icon, this.taskDescription, this.actionType);
}

enum _ActionType {
  /// Direct Shizuku execution — no screenshot, vision model, or AI needed.
  system,

  /// Requires AutoGLM screenshot + vision model loop.
  vision,
}
