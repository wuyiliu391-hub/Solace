import 'package:flutter/material.dart';
import '../../config/wechat_theme.dart';

/// 微信聊天输入栏 — 1:1 还原
///
/// 结构（activity_chat / fragment_wxchat）：
/// [语音/键盘切换] [输入框/按住说话] [表情] [加号 / 发送]
/// 背景 #F5F5F5，顶部 0.5dp hairline，输入框白底圆角 5dp。
class WxChatInputBar extends StatefulWidget {
  final TextEditingController? controller;
  final ValueChanged<String>? onSend;
  final VoidCallback? onVoiceHold;   // 按住说话
  final VoidCallback? onEmoji;       // 表情面板
  final VoidCallback? onMore;        // + 更多面板

  const WxChatInputBar({
    super.key,
    this.controller,
    this.onSend,
    this.onVoiceHold,
    this.onEmoji,
    this.onMore,
  });

  @override
  State<WxChatInputBar> createState() => _WxChatInputBarState();
}

class _WxChatInputBarState extends State<WxChatInputBar> {
  late final TextEditingController _c;
  bool _voiceMode = false;
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _c = widget.controller ?? TextEditingController();
    _c.addListener(() => setState(() => _hasText = _c.text.trim().isNotEmpty));
  }

  @override
  void dispose() {
    if (widget.controller == null) _c.dispose();
    super.dispose();
  }

  void _send() {
    final t = _c.text.trim();
    if (t.isEmpty) return;
    widget.onSend?.call(t);
    _c.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: WxColors.inputBar,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(height: WxDimens.divider, color: WxColors.divider),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // 语音/键盘切换
                _RoundIcon(
                  icon: _voiceMode ? Icons.keyboard : Icons.mic_none,
                  onTap: () => setState(() => _voiceMode = !_voiceMode),
                ),
                const SizedBox(width: 8),
                // 输入框 / 按住说话
                Expanded(
                  child: _voiceMode
                      ? _HoldToTalk(onHold: widget.onVoiceHold)
                      : _InputField(controller: _c, onSubmit: _send),
                ),
                const SizedBox(width: 8),
                // 表情
                _RoundIcon(icon: Icons.tag_faces_outlined, onTap: widget.onEmoji),
                const SizedBox(width: 8),
                // 加号 / 发送
                _hasText && !_voiceMode
                    ? _SendButton(onTap: _send)
                    : _RoundIcon(
                        icon: Icons.add_circle_outline, onTap: widget.onMore),
              ],
            ),
          ),
          // 底部安全区
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }
}

class _RoundIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _RoundIcon({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, size: 28, color: WxColors.textPrimary),
      ),
    );
  }
}

class _InputField extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSubmit;
  const _InputField({required this.controller, required this.onSubmit});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 40),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(WxDimens.inputRadius),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.center,
      child: TextField(
        controller: controller,
        maxLines: 4,
        minLines: 1,
        style: WxText.message,
        cursorColor: WxColors.brand,
        decoration: const InputDecoration(
          isDense: true,
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(vertical: 9),
        ),
        onSubmitted: (_) => onSubmit(),
      ),
    );
  }
}

class _HoldToTalk extends StatelessWidget {
  final VoidCallback? onHold;
  const _HoldToTalk({this.onHold});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPressStart: (_) => onHold?.call(),
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(WxDimens.inputRadius),
        ),
        alignment: Alignment.center,
        child: const Text(
          '按住 说话',
          style: TextStyle(
              fontSize: 16,
              color: WxColors.textPrimary,
              fontWeight: FontWeight.w500),
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  final VoidCallback onTap;
  const _SendButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: WxColors.brand,
      borderRadius: BorderRadius.circular(WxDimens.sendBtnRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(WxDimens.sendBtnRadius),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: Text('发送',
              style: TextStyle(color: Colors.white, fontSize: 15)),
        ),
      ),
    );
  }
}
