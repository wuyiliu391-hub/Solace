import 'dart:io';
import 'package:flutter/material.dart';
import '../../config/moments_theme.dart';

/// 复用头像组件，支持本地文件和网络 URL
class CircularAvatar extends StatelessWidget {
  final String? avatarPath;
  final String name;
  final double radius;
  final VoidCallback? onTap;

  const CircularAvatar({
    super.key,
    this.avatarPath,
    required this.name,
    this.radius = 20,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final avatar = GestureDetector(
      onTap: onTap,
      child: CircleAvatar(
        radius: radius,
        backgroundColor: MomentsTheme.primary(context).withOpacity(0.2),
        child: _buildImage(context),
      ),
    );
    return avatar;
  }

  Widget _buildImage(BuildContext context) {
    if (avatarPath != null && avatarPath!.isNotEmpty) {
      if (avatarPath!.startsWith('http')) {
        return ClipOval(
          child: Image.network(
            avatarPath!,
            width: radius * 2,
            height: radius * 2,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _fallbackInitial(context),
          ),
        );
      } else {
        final file = File(avatarPath!);
        if (file.existsSync()) {
          return ClipOval(
            child: Image.file(
              file,
              width: radius * 2,
              height: radius * 2,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _fallbackInitial(context),
            ),
          );
        }
      }
    }
    return _fallbackInitial(context);
  }

  Widget _fallbackInitial(BuildContext context) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Text(
      initial,
      style: TextStyle(
        color: MomentsTheme.primary(context),
        fontWeight: FontWeight.bold,
        fontSize: radius * 0.8,
      ),
    );
  }
}
