import 'package:flutter/material.dart';
import '../../config/wechat_theme.dart';

/// 微信聊天气泡 — 1:1 还原
///
/// 白色左气泡（对方）+ 绿色右气泡（我），带三角尾巴。
/// 色值/圆角/边距全部来自逆向资源，非目测。
class WxBubble extends StatelessWidget {
  final Widget child;
  final bool isMe;
  final bool isPressed;

  const WxBubble({
    super.key,
    required this.child,
    required this.isMe,
    this.isPressed = false,
  });

  @override
  Widget build(BuildContext context) {
    final Color bg = isMe
        ? (isPressed ? WxColors.bubbleMePressed : WxColors.bubbleMe)
        : (isPressed ? WxColors.bubbleOtherPressed : WxColors.bubbleOther);

    return CustomPaint(
      painter: _BubbleTailPainter(color: bg, isMe: isMe),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * WxDimens.bubbleMaxRatio,
        ),
        margin: EdgeInsets.only(
          // 为尾巴让出空间：对方在左、我在右
          left: isMe ? 0 : 6,
          right: isMe ? 6 : 0,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: WxDimens.bubblePadH,
          vertical: WxDimens.bubblePadV,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(WxDimens.bubbleRadius),
        ),
        child: child,
      ),
    );
  }
}

/// 气泡三角尾巴（微信是直角小三角，贴近头像上缘）
class _BubbleTailPainter extends CustomPainter {
  final Color color;
  final bool isMe;
  _BubbleTailPainter({required this.color, required this.isMe});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path();
    const double tw = 6.0;  // 尾巴宽
    const double th = 10.0; // 尾巴高
    const double top = 8.0; // 距气泡顶

    if (isMe) {
      // 右侧：贴气泡右缘，尖朝右
      path.moveTo(size.width, top);
      path.lineTo(size.width + tw, top + th / 2);
      path.lineTo(size.width, top + th);
    } else {
      // 左侧：贴气泡左缘，尖朝左
      path.moveTo(0, top);
      path.lineTo(-tw, top + th / 2);
      path.lineTo(0, top + th);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_BubbleTailPainter old) =>
      old.color != color || old.isMe != isMe;
}

/// 微信文字消息气泡（便捷封装）
class WxTextBubble extends StatelessWidget {
  final String text;
  final bool isMe;

  const WxTextBubble({super.key, required this.text, required this.isMe});

  @override
  Widget build(BuildContext context) {
    return WxBubble(
      isMe: isMe,
      child: Text(
        text,
        style: isMe ? WxText.messageMe : WxText.message,
      ),
    );
  }
}

/// 微信消息行：头像 + 气泡（含昵称），左右自适应
class WxMessageRow extends StatelessWidget {
  final String text;
  final bool isMe;
  final String? nickname;      // 群聊显示发送者昵称
  final ImageProvider? avatar; // 头像
  final String? avatarText;    // 无图头像的占位文字

  const WxMessageRow({
    super.key,
    required this.text,
    required this.isMe,
    this.nickname,
    this.avatar,
    this.avatarText,
  });

  @override
  Widget build(BuildContext context) {
    final avatarWidget = WxAvatar(image: avatar, text: avatarText);

    final bubbleCol = Column(
      crossAxisAlignment:
          isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        if (!isMe && nickname != null)
          Padding(
            padding: const EdgeInsets.only(left: 6, bottom: 3),
            child: Text(nickname!, style: WxText.nickname),
          ),
        WxTextBubble(text: text, isMe: isMe),
      ],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: WxDimens.msgSideMargin,
        vertical: 9,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: isMe
            ? [Flexible(child: bubbleCol), const SizedBox(width: 10), avatarWidget]
            : [avatarWidget, const SizedBox(width: 10), Flexible(child: bubbleCol)],
      ),
    );
  }
}

/// 微信头像：方形小圆角（不是圆形！）
class WxAvatar extends StatelessWidget {
  final ImageProvider? image;
  final String? text;
  final double size;

  const WxAvatar({super.key, this.image, this.text, this.size = WxDimens.avatar});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(WxDimens.avatarRadius),
      child: Container(
        width: size,
        height: size,
        color: const Color(0xFFDDDEDD),
        child: image != null
            ? Image(image: image!, fit: BoxFit.cover)
            : Center(
                child: Text(
                  (text ?? '').isEmpty ? '' : text!.characters.first,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                ),
              ),
      ),
    );
  }
}
