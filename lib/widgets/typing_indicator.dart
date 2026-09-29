import 'package:flutter/material.dart';
import '../../utils/avatar_resolver.dart';

class TypingIndicator extends StatefulWidget {
  final String? avatarUrl;
  final String name;
  /// 状态文案，不为空时显示文案 + 呼吸动画，为空时显示三个点
  final String? statusText;

  const TypingIndicator({
    super.key,
    this.avatarUrl,
    this.name = 'AI',
    this.statusText,
  });

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with TickerProviderStateMixin {
  late List<AnimationController> _controllers;
  late List<Animation<double>> _animations;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(
      3,
      (i) => AnimationController(
        duration: const Duration(milliseconds: 600),
        vsync: this,
      )..repeat(reverse: true),
    );
    _animations = _controllers.map((c) {
      return Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: c, curve: Curves.easeInOut),
      );
    }).toList();

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat(reverse: true);
    _fadeAnimation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );

    for (int i = 1; i < _controllers.length; i++) {
      Future.delayed(Duration(milliseconds: i * 150), () {
        if (mounted) _controllers[i].repeat(reverse: true);
      });
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasStatus = widget.statusText != null && widget.statusText!.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _buildAvatar(colorScheme),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
                bottomLeft: Radius.circular(4),
                bottomRight: Radius.circular(20),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: hasStatus ? _buildStatusText(colorScheme) : _buildDots(colorScheme),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusText(ColorScheme colorScheme) {
    return AnimatedBuilder(
      animation: _fadeAnimation,
      builder: (context, child) {
        return Text(
          widget.statusText!,
          style: TextStyle(
            fontSize: 14,
            color: colorScheme.onSurface.withOpacity(_fadeAnimation.value),
            fontWeight: FontWeight.w500,
          ),
        );
      },
    );
  }

  Widget _buildDots(ColorScheme colorScheme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        return Padding(
          padding: EdgeInsets.only(right: i < 2 ? 4 : 0),
          child: AnimatedBuilder(
            animation: _animations[i],
            builder: (context, child) {
              return Transform.translate(
                offset: Offset(0, -4 * _animations[i].value),
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withOpacity(
                      0.3 + 0.4 * _animations[i].value,
                    ),
                    shape: BoxShape.circle,
                  ),
                ),
              );
            },
          ),
        );
      }),
    );
  }

  Widget _buildAvatar(ColorScheme colorScheme) {
    final imageProvider = AvatarResolver.imageProvider(widget.avatarUrl);
    if (imageProvider != null) {
      return CircleAvatar(
        radius: 18,
        backgroundImage: imageProvider,
        onBackgroundImageError: (_, __) {},
      );
    }
    return CircleAvatar(
      radius: 18,
      backgroundColor: colorScheme.primaryContainer,
      child: Text(
        widget.name.isNotEmpty ? widget.name.substring(0, 1) : 'A',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: colorScheme.primary,
        ),
      ),
    );
  }
}
