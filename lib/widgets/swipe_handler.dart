// 【对标来源：SillyTavern-1.18.0 — script.js swipe_left/swipe_right】
// 1:1 转译自 SillyTavern 消息滑动翻页逻辑
// 参考文件：public/script.js (swipe_left, swipe_right, SWIPE_DIRECTION)

import 'package:flutter/material.dart';

/// 滑动方向（对标 SillyTavern SWIPE_DIRECTION）
enum SwipeDirection {
  left,
  right,
}

/// 滑动处理器组件（对标 SillyTavern swipe_left/swipe_right）
/// 为消息气泡提供左右滑动翻页功能
class SwipeHandler extends StatefulWidget {
  /// 子组件
  final Widget child;

  /// 滑动历史数量
  final int swipeCount;

  /// 当前滑动索引
  final int currentIndex;

  /// 左滑回调（对标 swipe_left，切换到上一条）
  final VoidCallback? onSwipeLeft;

  /// 右滑回调（对标 swipe_right，切换到下一条）
  final VoidCallback? onSwipeRight;

  /// 是否启用滑动
  final bool enabled;

  /// 滑动阈值（像素）
  final double threshold;

  const SwipeHandler({
    super.key,
    required this.child,
    this.swipeCount = 0,
    this.currentIndex = 0,
    this.onSwipeLeft,
    this.onSwipeRight,
    this.enabled = true,
    this.threshold = 50.0,
  });

  @override
  State<SwipeHandler> createState() => _SwipeHandlerState();
}

class _SwipeHandlerState extends State<SwipeHandler>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  Animation<Offset>? _animation;
  double _dragExtent = 0.0;
  bool _isAnimating = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _controller.addListener(() {
      if (_animation != null) {
        setState(() {
          _dragExtent = _animation!.value.dx;
        });
      }
    });
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() {
          _isAnimating = false;
          _dragExtent = 0.0;
        });
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _canSwipeLeft =>
      widget.enabled &&
      widget.currentIndex > 0 &&
      widget.onSwipeLeft != null;

  bool get _canSwipeRight =>
      widget.enabled &&
      widget.currentIndex < widget.swipeCount - 1 &&
      widget.onSwipeRight != null;

  void _onDragStart(DragStartDetails details) {
    if (_isAnimating) return;
    _dragExtent = 0.0;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (_isAnimating) return;
    setState(() {
      _dragExtent += details.delta.dx;
      // 限制拖动范围
      _dragExtent = _dragExtent.clamp(-100.0, 100.0);
    });
  }

  void _onDragEnd(DragEndDetails details) {
    if (_isAnimating) return;

    final velocity = details.primaryVelocity ?? 0.0;
    final isSwipe = _dragExtent.abs() > widget.threshold ||
        velocity.abs() > 300.0;

    if (isSwipe) {
      if (_dragExtent < 0 || velocity < -300) {
        // 左滑 → 下一条（对标 swipe_right 的语义：向右翻页）
        if (_canSwipeRight) {
          widget.onSwipeRight!();
        }
      } else if (_dragExtent > 0 || velocity > 300) {
        // 右滑 → 上一条（对标 swipe_left 的语义：向左翻页）
        if (_canSwipeLeft) {
          widget.onSwipeLeft!();
        }
      }
    }

    // 回弹动画
    _animation = Tween<Offset>(
      begin: Offset(_dragExtent, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    ));
    _controller.forward(from: 0.0);
    _isAnimating = true;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || widget.swipeCount <= 1) {
      return widget.child;
    }

    return GestureDetector(
      onHorizontalDragStart: _onDragStart,
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      child: Stack(
        children: [
          // 滑动指示器背景
          if (_dragExtent.abs() > 10)
            Positioned.fill(
              child: Container(
                color: _dragExtent > 0
                    ? Colors.blue.withOpacity(0.1)
                    : Colors.green.withOpacity(0.1),
                alignment: _dragExtent > 0
                    ? Alignment.centerLeft
                    : Alignment.centerRight,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Icon(
                  _dragExtent > 0
                      ? Icons.chevron_left
                      : Icons.chevron_right,
                  color: _dragExtent > 0
                      ? Colors.blue.withOpacity(0.5)
                      : Colors.green.withOpacity(0.5),
                ),
              ),
            ),

          // 消息内容（带滑动偏移）
          Transform.translate(
            offset: Offset(_dragExtent, 0),
            child: widget.child,
          ),

          // 滑动计数器（对标 .swipes-counter）
          if (widget.swipeCount > 1)
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${widget.currentIndex + 1}/${widget.swipeCount}',
                  style: const TextStyle(
                    fontSize: 10,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 滑动箭头按钮（对标 SillyTavern .swipe_left / .swipe_right）
class SwipeArrowButton extends StatelessWidget {
  final SwipeDirection direction;
  final VoidCallback? onPressed;
  final bool enabled;

  const SwipeArrowButton({
    super.key,
    required this.direction,
    this.onPressed,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    if (!enabled) return const SizedBox.shrink();

    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.3),
          shape: BoxShape.circle,
        ),
        child: Icon(
          direction == SwipeDirection.left
              ? Icons.chevron_left
              : Icons.chevron_right,
          size: 16,
          color: Colors.white,
        ),
      ),
    );
  }
}
