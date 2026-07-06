import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

/// 头像框定义
class AvatarFrame extends Equatable {
  final String id;
  final String name;
  final int price;          // 金币价格，0 = 免费
  final List<Color> gradientColors;
  final double borderWidth;
  final Color? borderColor;  // 纯色边框（与 gradient 二选一）
  final String? emoji;       // 装饰 emoji
  final bool isGlow;         // 是否有发光效果

  const AvatarFrame({
    required this.id,
    required this.name,
    required this.price,
    required this.gradientColors,
    this.borderWidth = 3.0,
    this.borderColor,
    this.emoji,
    this.isGlow = false,
  });

  /// 是否是渐变边框
  bool get isGradient => gradientColors.length > 1;

  @override
  List<Object?> get props => [id];
}

/// 预置头像框列表
class AvatarFrames {
  AvatarFrames._();

  static const List<AvatarFrame> all = [
    AvatarFrame(
      id: 'frame_none',
      name: '无边框',
      price: 0,
      gradientColors: [Colors.transparent],
      borderWidth: 0,
    ),
    AvatarFrame(
      id: 'frame_silver',
      name: '银色经典',
      price: 50,
      gradientColors: [Color(0xFFC0C0C0), Color(0xFFE8E8E8)],
      borderWidth: 3,
    ),
    AvatarFrame(
      id: 'frame_gold',
      name: '黄金荣耀',
      price: 200,
      gradientColors: [Color(0xFFFFD700), Color(0xFFFFA500)],
      borderWidth: 3,
      isGlow: true,
    ),
    AvatarFrame(
      id: 'frame_rose',
      name: '玫瑰之恋',
      price: 150,
      gradientColors: [Color(0xFFFF6B9D), Color(0xFFC44569)],
      borderWidth: 3,
    ),
    AvatarFrame(
      id: 'frame_ocean',
      name: '深海之蓝',
      price: 150,
      gradientColors: [Color(0xFF4FACFE), Color(0xFF00F2FE)],
      borderWidth: 3,
    ),
    AvatarFrame(
      id: 'frame_forest',
      name: '翠绿森林',
      price: 150,
      gradientColors: [Color(0xFF43E97B), Color(0xFF38F9D7)],
      borderWidth: 3,
    ),
    AvatarFrame(
      id: 'frame_purple',
      name: '紫晶幻梦',
      price: 300,
      gradientColors: [Color(0xFFA855F7), Color(0xFF6366F1)],
      borderWidth: 3.5,
      isGlow: true,
    ),
    AvatarFrame(
      id: 'frame_sunset',
      name: '落日余晖',
      price: 250,
      gradientColors: [Color(0xFFFA709A), Color(0xFFFEE140)],
      borderWidth: 3,
      isGlow: true,
    ),
    AvatarFrame(
      id: 'frame_diamond',
      name: '钻石闪耀',
      price: 500,
      gradientColors: [Color(0xFFE0E0E0), Color(0xFFB0BEC5), Color(0xFFE0E0E0)],
      borderWidth: 4,
      isGlow: true,
    ),
    AvatarFrame(
      id: 'frame_star',
      name: '星辰大海',
      price: 400,
      gradientColors: [Color(0xFF0F0C29), Color(0xFF302B63), Color(0xFF24243E)],
      borderWidth: 3.5,
      isGlow: true,
    ),
  ];

  /// 根据 id 查找头像框
  static AvatarFrame? findById(String id) {
    try {
      return all.firstWhere((f) => f.id == id);
    } catch (_) {
      return null;
    }
  }
}
