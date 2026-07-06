import 'dart:io';
import 'package:flutter/material.dart';

/// 壁纸组件：支持自定义图片或默认渐变
class HomeWallpaper extends StatelessWidget {
  final String? imagePath;
  final Widget child;

  const HomeWallpaper({
    super.key,
    this.imagePath,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // 壁纸层
        if (imagePath != null && imagePath!.isNotEmpty)
          Image.file(
            File(imagePath!),
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _buildDefaultGradient(),
          )
        else
          _buildDefaultGradient(),
        // 内容层
        child,
      ],
    );
  }

  Widget _buildDefaultGradient() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFF9A8D4), // 浅粉
            Color(0xFFF472B6), // 中粉
            Color(0xFFDB2777), // 深粉
          ],
          stops: [0.0, 0.5, 1.0],
        ),
      ),
    );
  }
}
