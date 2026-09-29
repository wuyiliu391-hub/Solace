import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 页面切换动画：缩放 + 淡入
Route slideFadeRoute(Widget page) {
  return PageRouteBuilder(
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      const begin = 0.96;
      const end = 1.0;
      final scaleTween = Tween(begin: begin, end: end);
      final fadeTween = Tween(begin: 0.0, end: 1.0);
      final curvedAnimation = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return FadeTransition(
        opacity: fadeTween.animate(curvedAnimation),
        child: ScaleTransition(
          scale: scaleTween.animate(curvedAnimation),
          child: child,
        ),
      );
    },
    transitionDuration: const Duration(milliseconds: 300),
  );
}

/// 轻触震动
void tapHaptic() {
  HapticFeedback.lightImpact();
}

/// 确认震动（长按等）
void confirmHaptic() {
  HapticFeedback.mediumImpact();
}

/// 成功震动
void successHaptic() {
  HapticFeedback.heavyImpact();
}
