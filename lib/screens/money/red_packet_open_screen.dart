import 'dart:async';

import 'package:flutter/material.dart';

/// 微信式拆红包动效页。
///
/// 红色渐变底 + 金色「開」按钮，点击后按钮旋转 → 卡片内容淡入金额与
/// 「已存入余额」→ 自动 pop，返回值由调用方继续走 ChatClaimMoney 领款。
/// 纯动画，不碰资金逻辑（资金由 ChatBloc 落账）。
class RedPacketOpenScreen extends StatefulWidget {
  final int amount;
  final String? note;

  /// 发送方名字（红包页顶部「来自 XX 的红包」）
  final String? senderName;

  const RedPacketOpenScreen({
    super.key,
    required this.amount,
    this.note,
    this.senderName,
  });

  @override
  State<RedPacketOpenScreen> createState() => _RedPacketOpenScreenState();
}

class _RedPacketOpenScreenState extends State<RedPacketOpenScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _opened = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _open() {
    if (_opened || !mounted) return;
    setState(() => _opened = true);
    _controller.forward().then((_) {
      if (!mounted) return;
      setState(() {});
      Future.delayed(const Duration(milliseconds: 900), () {
        if (mounted) Navigator.pop(context, widget.amount);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final opened = _controller.status == AnimationStatus.completed;
    return Scaffold(
      backgroundColor: const Color(0xFFF0684E),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFE85D3E), Color(0xFFC03A28)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  widget.senderName != null && widget.senderName!.isNotEmpty
                      ? '${widget.senderName} 的红包'
                      : 'TA 的红包',
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                ),
                const SizedBox(height: 8),
                if (widget.note != null && widget.note!.isNotEmpty)
                  Text(
                    widget.note!,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.75),
                      fontSize: 12,
                    ),
                  ),
                const SizedBox(height: 48),
                // 红包卡
                Container(
                  width: 240,
                  padding: const EdgeInsets.symmetric(vertical: 34),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0604A),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: const Color(0xFFF5C84C).withOpacity(0.6)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: AnimatedBuilder(
                    animation: _controller,
                    builder: (context, _) {
                      if (opened || _controller.value > 0.5) {
                        return Opacity(
                          opacity: _controller.value >= 0.5
                              ? (_controller.value - 0.5) * 2
                              : 0,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '¥${widget.amount}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 34,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '已存入余额',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.8),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        );
                      }
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.card_giftcard_rounded,
                              color: Color(0xFFF5C84C), size: 44),
                          const SizedBox(height: 14),
                          const Text(
                            '恭喜发财',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 4,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '大吉大利',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.7),
                              fontSize: 13,
                              letterSpacing: 4,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 56),
                // 開 按钮：点击旋转后淡出
                AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) {
                    if (opened || _controller.value > 0.6) {
                      return const SizedBox(height: 64);
                    }
                    return GestureDetector(
                      onTap: _open,
                      child: Transform.rotate(
                        angle: _controller.value * 2 * 3.1415926,
                        child: Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF5C84C),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.15),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Center(
                            child: Text(
                              '開',
                              style: TextStyle(
                                fontSize: 26,
                                color: Color(0xFF9A2B1D),
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 24),
                Text(
                  '拆开后自动存入余额',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.55),
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 36),
                TextButton(
                  onPressed: () => Navigator.pop(context, widget.amount),
                  child: const Text(
                    '跳过',
                    style: TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
