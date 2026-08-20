import 'package:flutter/material.dart';

import '../utils/avatar_resolver.dart';

/// 微信风格头像：圆角方形（逆向实测圆角 ≈ 边长 * 0.1，如 40px 头像 4px 圆角）。
///
/// 全 App 统一走本组件，保证会话列表/聊天页/通讯录/朋友圈头像形状一致。
/// image 解析复用 [AvatarResolver]，失败回退为名字首字色块。
class WeChatAvatar extends StatelessWidget {
  final String? imageUrl;
  final double size;

  /// 圆角半径，默认 size * 0.1（微信逆向实测比例）
  final double? radius;

  /// 回退色块上显示的文字（通常取名字首字）
  final String fallbackText;

  /// 回退色块背景（不传则按 fallbackText hash 取色）
  final Color? fallbackColor;

  const WeChatAvatar({
    super.key,
    this.imageUrl,
    this.size = 40,
    this.radius,
    this.fallbackText = '?',
    this.fallbackColor,
  });

  static const List<Color> _palette = [
    Color(0xFF5B93D0),
    Color(0xFF6BBE7F),
    Color(0xFFE8A855),
    Color(0xFFD77B7B),
    Color(0xFF9A7FD0),
    Color(0xFF5BB8BE),
    Color(0xFFC078B5),
  ];

  Color get _autoColor {
    final code = fallbackText.isEmpty ? 0 : fallbackText.codeUnitAt(0);
    return _palette[code.abs() % _palette.length];
  }

  BorderRadius get _borderRadius =>
      BorderRadius.circular(radius ?? size * 0.1);

  @override
  Widget build(BuildContext context) {
    final image = AvatarResolver.imageWidget(
      imageUrl,
      width: size,
      height: size,
      fit: BoxFit.cover,
    );
    return ClipRRect(
      borderRadius: _borderRadius,
      child: SizedBox(
        width: size,
        height: size,
        child: image ??
            Container(
              color: fallbackColor ?? _autoColor,
              alignment: Alignment.center,
              child: Text(
                fallbackText.isNotEmpty ? fallbackText[0] : '?',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: size * 0.42,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
      ),
    );
  }
}
