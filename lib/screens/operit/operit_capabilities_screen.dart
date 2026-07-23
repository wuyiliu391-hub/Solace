import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/tools/tool.dart';
import '../../services/tools/tool_registry.dart';
import '../../services/tools/tools.dart';

/// Operit 能力手册页面 — 从工具注册表动态生成所有可用操作
///
/// 每条工具对应一个可一键复制的自然语言指令。
class OperitCapabilitiesScreen extends StatefulWidget {
  const OperitCapabilitiesScreen({super.key});

  @override
  State<OperitCapabilitiesScreen> createState() => _OperitCapabilitiesScreenState();
}

class _OperitCapabilitiesScreenState extends State<OperitCapabilitiesScreen> {
  late final ToolRegistry _registry;

  @override
  void initState() {
    super.initState();
    _registry = createToolRegistry();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final packages = _registry.packages;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0A0A0A) : colorScheme.surface,
      appBar: AppBar(
        title: const Text('Shizuku 能力手册',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_all_outlined, size: 20),
            tooltip: '复制所有指令',
            onPressed: () => _copyAll(context),
          ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: packages.length,
        itemBuilder: (context, pkgIndex) {
          final pkg = packages[pkgIndex];
          return _buildPackageCard(context, pkg, colorScheme, isDark);
        },
      ),
    );
  }

  Widget _buildPackageCard(
    BuildContext context,
    ToolPkg pkg,
    ColorScheme colorScheme,
    bool isDark,
  ) {
    final icon = _iconForPackage(pkg.name);
    final color = _colorForPackage(pkg.name);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.08)
              : Colors.black.withOpacity(0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 18, color: color),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        pkg.name,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        pkg.description,
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurface.withOpacity(0.5),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${pkg.tools.length} 个工具',
                    style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ...pkg.tools.map((tool) =>
              _buildToolTile(context, tool, colorScheme, isDark, color)),
        ],
      ),
    );
  }

  Widget _buildToolTile(
    BuildContext context,
    Tool tool,
    ColorScheme colorScheme,
    bool isDark,
    Color accentColor,
  ) {
    final sampleCommand = _generateCommand(tool);

    return InkWell(
      onTap: () => _copyToClipboard(context, sampleCommand),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _formatToolName(tool.name),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ),
                      if (tool.isDestructive)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('危险', style: TextStyle(
                              fontSize: 9, color: Colors.orange, fontWeight: FontWeight.w600)),
                        ),
                      if (tool.requiredPermissions.isNotEmpty) ...[
                        const SizedBox(width: 4),
                        ...tool.requiredPermissions.map((p) => Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.purple.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(p,
                                  style: TextStyle(
                                      fontSize: 9,
                                      color: Colors.purple[300],
                                      fontWeight: FontWeight.w600)),
                            )),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    tool.description,
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurface.withOpacity(0.55),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: accentColor.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: accentColor.withOpacity(0.15), width: 0.5),
                    ),
                    child: Text(
                      '"$sampleCommand"',
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        fontFamilyFallback: const ['sans-serif'],
                        color: accentColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(Icons.copy_outlined,
                  size: 18, color: colorScheme.onSurface.withOpacity(0.5)),
              onPressed: () => _copyToClipboard(context, sampleCommand),
              tooltip: '复制指令',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _copyToClipboard(BuildContext context, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已复制: $text'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _copyAll(BuildContext context) async {
    final buf = StringBuffer();
    for (final pkg in _registry.packages) {
      buf.writeln('## ${pkg.name}');
      for (final tool in pkg.tools) {
        buf.writeln('- ${_generateCommand(tool)}');
      }
      buf.writeln();
    }
    await _copyToClipboard(context, buf.toString());
  }

  /// 根据工具 schema 生成自然语言指令示例
  String _generateCommand(Tool tool) {
    switch (tool.name) {
      case 'open_app':
        return '打开微信';
      case 'close_app':
        return '关闭微信';
      case 'lock_screen':
        return '锁屏';
      case 'adjust_volume':
        return '调大音量 / 调小音量';
      case 'set_mute':
        return '开启静音 / 取消静音';
      case 'toggle_wifi':
        return '打开WiFi / 关闭WiFi';
      case 'toggle_bluetooth':
        return '打开蓝牙 / 关闭蓝牙';
      case 'set_brightness':
        return '把亮度调到200';
      case 'open_gallery':
        return '打开相册';
      case 'go_home':
        return '返回桌面';
      case 'press_back':
        return '按返回键';
      case 'get_installed_apps':
        return '查看手机安装了什么软件';
      case 'get_app_usage_time':
        return '查看微信使用时间 / 查看手机应用使用时间排行';
      case 'get_current_app':
        return '查看当前前台应用';
      case 'execute_shell':
        return '执行命令: dumpsys battery';
      case 'get_notifications':
        return '查看最近通知';
      case 'get_notification_count':
        return '查看通知数量';
      case 'get_battery_info':
        return '查看电池电量';
      case 'take_screenshot':
        return '截图';
      case 'tap':
        return '点击屏幕 500 900';
      case 'swipe':
        return '从 500 1000 滑动到 500 300';
      case 'input_text':
        return '输入文本 你好';
      case 'press_key':
        return '按Home键 / 按返回键';
      default:
        return _generateDefaultCommand(tool);
    }
  }

  /// 兜底生成：安全转换 schema（修复 Map<dynamic,dynamic> 类型崩溃）
  String _generateDefaultCommand(Tool tool) {
    final rawRequired = tool.parametersSchema['required'];
    final rawProps = tool.parametersSchema['properties'];

    final required = rawRequired is List ? rawRequired.cast<String>().toSet() : <String>{};
    final props = rawProps is Map ? Map<String, dynamic>.from(rawProps) : <String, dynamic>{};

    String paramExample = '';
    for (final key in required) {
      final rawProp = props[key];
      final prop = rawProp is Map ? Map<String, dynamic>.from(rawProp) : null;
      if (prop == null) {
        paramExample = key;
        break;
      }
      final type = prop['type'] as String? ?? 'string';
      switch (type) {
        case 'string':
          final enumRaw = prop['enum'];
          if (enumRaw is List && enumRaw.isNotEmpty) {
            paramExample = enumRaw.first.toString();
          } else {
            paramExample = key;
          }
          break;
        case 'boolean':
          paramExample = 'true/false';
          break;
        case 'integer':
          paramExample = '数字';
          break;
      }
      break;
    }
    return '${_formatToolName(tool.name)}${paramExample.isNotEmpty ? ' ($paramExample)' : ''}';
  }

  String _formatToolName(String name) {
    // snake_case → 中文友好转换
    const map = {
      'open_app': '打开应用', 'close_app': '关闭应用',
      'lock_screen': '锁屏', 'adjust_volume': '调节音量',
      'set_mute': '静音模式', 'toggle_wifi': 'WiFi开关',
      'toggle_bluetooth': '蓝牙开关', 'set_brightness': '设置亮度',
      'open_gallery': '打开相册', 'go_home': '返回桌面',
      'press_back': '返回键',
      'get_installed_apps': '已安装应用', 'get_app_usage_time': '应用使用时间',
      'get_current_app': '当前前台应用',
      'execute_shell': '执行Shell', 'get_notifications': '通知列表',
      'get_notification_count': '通知数量', 'get_battery_info': '电池信息',
      'take_screenshot': '截图', 'tap': '点击', 'swipe': '滑动',
      'input_text': '输入文本', 'press_key': '按键',
    };
    return map[name] ?? name.replaceAll('_', ' ');
  }

  IconData _iconForPackage(String name) {
    switch (name) {
      case '系统操作': return Icons.apps;
      case '应用信息': return Icons.query_stats;
      case 'Shell 命令': return Icons.terminal;
      case '通知': return Icons.notifications_outlined;
      case '电池': return Icons.battery_std;
      case '截图': return Icons.camera_alt_outlined;
      case 'UI 自动化': return Icons.touch_app;
      default: return Icons.build;
    }
  }

  MaterialColor _colorForPackage(String name) {
    switch (name) {
      case '系统操作': return Colors.blue;
      case '应用信息': return Colors.green;
      case 'Shell 命令': return Colors.teal;
      case '通知': return Colors.amber;
      case '电池': return Colors.lime;
      case '截图': return Colors.indigo;
      case 'UI 自动化': return Colors.purple;
      default: return Colors.grey;
    }
  }
}
