import 'package:flutter/material.dart';

class SkeletonLoading extends StatefulWidget {
  final int itemCount;

  const SkeletonLoading({super.key, this.itemCount = 6});

  @override
  State<SkeletonLoading> createState() => _SkeletonLoadingState();
}

class _SkeletonLoadingState extends State<SkeletonLoading>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final opacity = 0.3 + (_controller.value * 0.3);
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: widget.itemCount,
          itemBuilder: (context, index) {
            final isLeft = index.isEven;
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: isLeft ? MainAxisAlignment.start : MainAxisAlignment.end,
                children: [
                  if (isLeft) _avatarSkeleton(colorScheme),
                  if (isLeft) const SizedBox(width: 8),
                  Container(
                    width: 120 + (index % 3) * 60.0,
                    height: 40,
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withOpacity(opacity),
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(16),
                        topRight: const Radius.circular(16),
                        bottomLeft: Radius.circular(isLeft ? 4 : 16),
                        bottomRight: Radius.circular(isLeft ? 16 : 4),
                      ),
                    ),
                  ),
                  if (!isLeft) const SizedBox(width: 8),
                  if (!isLeft) _avatarSkeleton(colorScheme),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _avatarSkeleton(ColorScheme colorScheme) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.4),
        shape: BoxShape.circle,
      ),
    );
  }
}
