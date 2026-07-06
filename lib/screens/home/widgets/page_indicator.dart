import 'package:flutter/material.dart';
import '../../../utils/ios_colors.dart';

/// iOS 18 风格的药丸页码指示器
class PageIndicator extends StatelessWidget {
  final int pageCount;
  final int currentPage;

  const PageIndicator({
    super.key,
    required this.pageCount,
    required this.currentPage,
  });

  @override
  Widget build(BuildContext context) {
    if (pageCount <= 1) return const SizedBox.shrink();

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(pageCount, (index) {
        final isActive = currentPage == index;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          margin: const EdgeInsets.symmetric(horizontal: 4.5),
          height: 7,
          width: isActive ? 20 : 7,
          decoration: BoxDecoration(
            color: isActive
                ? IOSColors.pageDotActive
                : IOSColors.pageDotInactive,
            borderRadius: BorderRadius.circular(3.5),
          ),
        );
      }),
    );
  }
}
