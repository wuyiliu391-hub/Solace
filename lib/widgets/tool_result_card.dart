import 'package:flutter/material.dart';

/// 工具执行结果卡片 — 借鉴 Operit 的 CompactToolDisplay + ToolResultDisplay 设计
///
/// 在聊天消息气泡中渲染工具执行结果，视觉上与普通文本消息区分：
/// - 工具图标 + 工具名 + 成功/失败状态
/// - 结果摘要
/// - 可展开的执行详情
class ToolResultCard extends StatefulWidget {
  /// 工具名称（如"打开微信"、"锁屏"）
  final String toolName;

  /// 执行结果摘要（如"微信已打开"）
  final String summary;

  /// 是否执行成功
  final bool isSuccess;

  /// 执行详情（原 reasoning 内容，如时间戳、执行细节）
  final String? detail;

  /// 工具图标（根据工具类型自动推断，也可手动指定）
  final IconData? icon;

  const ToolResultCard({
    super.key,
    required this.toolName,
    required this.summary,
    this.isSuccess = true,
    this.detail,
    this.icon,
  });

  /// 根据工具名推断图标（借鉴 Operit 的 getToolIcon 逻辑）
  static IconData inferToolIcon(String toolName) {
    if (toolName.contains('微信')) return Icons.chat_bubble_outline;
    if (toolName.contains('QQ')) return Icons.forum_outlined;
    if (toolName.contains('相册') || toolName.contains('图片')) {
      return Icons.photo_library_outlined;
    }
    if (toolName.contains('锁屏') || toolName.contains('锁定')) {
      return Icons.lock_outline;
    }
    if (toolName.contains('音量')) return Icons.volume_up_outlined;
    if (toolName.contains('静音')) return Icons.volume_off_outlined;
    if (toolName.contains('WiFi') || toolName.contains('wifi')) {
      return Icons.wifi;
    }
    if (toolName.contains('蓝牙') || toolName.contains('bluetooth')) {
      return Icons.bluetooth;
    }
    if (toolName.contains('亮度')) return Icons.brightness_6;
    if (toolName.contains('截图')) return Icons.screenshot;
    if (toolName.contains('通知')) return Icons.notifications_outlined;
    if (toolName.contains('电池')) return Icons.battery_std;
    if (toolName.contains('返回') || toolName.contains('桌面')) {
      return Icons.home;
    }
    if (toolName.contains('打开') || toolName.contains('启动')) {
      return Icons.open_in_new;
    }
    if (toolName.contains('关闭') || toolName.contains('退出')) {
      return Icons.close;
    }
    // 英文工具名匹配（ToolAwareService 产生的 open_app / close_app 等）
    if (toolName.contains('app') || toolName.contains('open')) {
      return Icons.open_in_new;
    }
    if (toolName.contains('close') || toolName.contains('kill')) {
      return Icons.close;
    }
    if (toolName.contains('volume') || toolName.contains('mute')) {
      return Icons.volume_up_outlined;
    }
    if (toolName.contains('lock')) return Icons.lock_outline;
    if (toolName.contains('screenshot')) return Icons.screenshot;
    if (toolName.contains('wifi')) return Icons.wifi;
    if (toolName.contains('bluetooth')) return Icons.bluetooth;
    if (toolName.contains('battery')) return Icons.battery_std;
    if (toolName.contains('notification')) return Icons.notifications_outlined;
    if (toolName.contains('shell') || toolName.contains('exec')) {
      return Icons.terminal;
    }
    return Icons.build_outlined;
  }

  @override
  State<ToolResultCard> createState() => _ToolResultCardState();
}

class _ToolResultCardState extends State<ToolResultCard>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late final AnimationController _controller;
  late final Animation<double> _rotationAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _rotationAnim = Tween<double>(begin: 0, end: 0.5).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() {
      _expanded = !_expanded;
      if (_expanded) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final accentColor =
        widget.isSuccess ? colorScheme.primary : colorScheme.error;
    final icon = widget.icon ?? ToolResultCard.inferToolIcon(widget.toolName);
    final hasDetail =
        widget.detail != null && widget.detail!.trim().isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.04)
            : Colors.black.withOpacity(0.02),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: accentColor.withOpacity(0.2),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ═══ 工具调用行 ═══
          InkWell(
            onTap: hasDetail ? _toggle : null,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(10)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  // 工具图标
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: accentColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(icon, size: 14, color: accentColor),
                  ),
                  const SizedBox(width: 8),
                  // 工具名
                  Expanded(
                    child: Text(
                      widget.toolName,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface.withOpacity(0.85),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // 成功/失败状态
                  _buildStatusBadge(colorScheme, accentColor, isDark),
                  // 展开箭头
                  if (hasDetail) ...[
                    const SizedBox(width: 4),
                    RotationTransition(
                      turns: _rotationAnim,
                      child: Icon(
                        Icons.expand_more,
                        size: 16,
                        color: colorScheme.onSurface.withOpacity(0.4),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          // ═══ 结果摘要行 ═══
          Padding(
            padding: const EdgeInsets.only(left: 10, right: 10, bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 箭头缩进指示器（借鉴 Operit 的 SubdirectoryArrowRight）
                Padding(
                  padding: const EdgeInsets.only(right: 6, top: 1),
                  child: Icon(
                    Icons.subdirectory_arrow_right,
                    size: 14,
                    color: accentColor.withOpacity(0.6),
                  ),
                ),
                Expanded(
                  child: Text(
                    widget.summary,
                    style: TextStyle(
                      fontSize: 13,
                      color: widget.isSuccess
                          ? colorScheme.onSurface.withOpacity(0.75)
                          : colorScheme.error.withOpacity(0.85),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // ═══ 可展开的详情区域 ═══
          if (hasDetail && _expanded) ...[
            Padding(
              padding: const EdgeInsets.only(
                  left: 10, right: 10, bottom: 8),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withOpacity(0.03)
                      : Colors.black.withOpacity(0.015),
                  borderRadius: BorderRadius.circular(6),
                ),
                constraints: const BoxConstraints(maxHeight: 120),
                child: SingleChildScrollView(
                  child: Text(
                    widget.detail!,
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: colorScheme.onSurface.withOpacity(0.5),
                      height: 1.4,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusBadge(
      ColorScheme colorScheme, Color accentColor, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: accentColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            widget.isSuccess ? Icons.check : Icons.close,
            size: 10,
            color: accentColor,
          ),
          const SizedBox(width: 3),
          Text(
            widget.isSuccess ? '成功' : '失败',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: accentColor,
            ),
          ),
        ],
      ),
    );
  }
}

/// 工具执行 trace 列表卡片 — 用于渲染 ChatBloc ToolAwareService 路径中的多条工具执行记录
///
/// 每条记录显示：工具图标 + 工具名 + 成功/失败状态
/// 嵌入在系统消息中，居中展示，紧凑风格
class ToolTraceCard extends StatelessWidget {
  /// 工具执行记录列表
  /// 每条记录包含 'tool' (String) 和 'success' (bool) 字段
  final List<Map<String, dynamic>> traces;

  const ToolTraceCard({super.key, required this.traces});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.04)
            : Colors.black.withOpacity(0.02),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: colorScheme.primary.withOpacity(0.15),
          width: 0.5,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 标题行
          Row(
            children: [
              Icon(Icons.build_circle_outlined,
                  size: 14, color: colorScheme.primary),
              const SizedBox(width: 6),
              Text(
                '工具执行 (${traces.length})',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // 每条工具记录
          ...traces.map((trace) {
            final toolName = trace['tool'] as String? ?? '未知工具';
            final success = trace['success'] as bool? ?? false;
            final icon = ToolResultCard.inferToolIcon(toolName);
            final accentColor =
                success ? colorScheme.primary : colorScheme.error;

            return Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  Icon(icon, size: 13, color: accentColor.withOpacity(0.7)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      toolName,
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurface.withOpacity(0.7),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    success ? Icons.check_circle : Icons.cancel,
                    size: 14,
                    color: accentColor,
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
