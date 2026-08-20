import 'package:flutter/material.dart';
import '../../config/wechat_theme.dart';

/// 微信设置行 — 1:1 还原
///
/// 通用列表行，用于"我"、设置、发现等所有分组列表。
/// 结构（activity_wx_geren.xml / activity_wx_setting.xml）：
/// [左侧图标] [标题] ... [右侧值/箭头] | 底部 hairline（从左 13dp 或 46dp 起）
class WxSettingRow extends StatelessWidget {
  final IconData? icon;           // 左侧图标
  final Color? iconColor;
  final String title;            // 标题
  final String? value;           // 右侧值（如名字、微信号）
  final Widget? trailingWidget;  // 自定义右侧（如二维码小图标）
  final bool showArrow;          // 右侧箭头
  final bool dividerFromIcon;    // 分割线从图标位置开始（true）还是从标题开始（false=13dp）
  final double height;
  final VoidCallback? onTap;
  final Color? background;

  const WxSettingRow({
    super.key,
    this.icon,
    this.iconColor,
    required this.title,
    this.value,
    this.trailingWidget,
    this.showArrow = true,
    this.dividerFromIcon = false,
    this.height = 46,
    this.onTap,
    this.background,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background ?? WxColors.listBg,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: height,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 13),
                child: Row(
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: 22, color: iconColor ?? WxColors.textPrimary),
                      const SizedBox(width: 13),
                    ],
                    Text(title,
                        style: const TextStyle(
                            fontSize: 15, color: WxColors.textBlack)),
                    const Spacer(),
                    if (value != null) ...[
                      Text(value!,
                          style: const TextStyle(
                              fontSize: 14, color: WxColors.textGray)),
                      const SizedBox(width: 8),
                    ],
                    if (trailingWidget != null) ...[
                      trailingWidget!,
                      const SizedBox(width: 8),
                    ],
                    if (showArrow)
                      const Icon(Icons.chevron_right,
                          size: 18, color: WxColors.textHint),
                  ],
                ),
              ),
            ),
            // 分割线
            Padding(
              padding: EdgeInsets.only(left: dividerFromIcon ? 46 : 13),
              child: Container(
                  height: WxDimens.divider, color: WxColors.divider),
            ),
          ],
        ),
      ),
    );
  }
}

/// 设置行分组（带顶部间距）
class WxSettingGroup extends StatelessWidget {
  final List<Widget> rows;
  final double topSpacing;  // 组间距（微信通常 7dp）
  final String? title;      // 可选组标题
  final Widget? trailing;   // 标题行右侧控件

  const WxSettingGroup({
    super.key,
    required this.rows,
    this.topSpacing = 7,
    this.title,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: topSpacing),
        if (title != null || trailing != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(
              children: [
                if (title != null)
                  Text(
                    title!,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: WxColors.textGray,
                    ),
                  ),
                const Spacer(),
                if (trailing != null) trailing!,
              ],
            ),
          ),
        ...rows,
      ],
    );
  }
}
