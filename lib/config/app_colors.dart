import 'package:flutter/material.dart';

/// Modernist theme color constants
class ModernistColors {
  // Chat bubbles - light mode
  static const aiBubbleLight = Color(0xFFE7E7E9);
  static const userBubbleLight = Color(0xFFFFFFFF);
  static const textPrimaryLight = Color(0xFF1F1F1F);
  static const textSecondaryLight = Color(0xFF111111);
  static const timestampLight = Color(0xFF999999);
  static const borderLight = Color(0xFFE0E0E0);

  // Chat bubbles - dark mode
  static const aiBubbleDark = Color(0xFF2C2C2C);
  static const userBubbleDark = Color(0xFF1E1E1E);
  static const textPrimaryDark = Color(0xFFE8EAED);
  static const textSecondaryDark = Color(0xFFF5F5F5);
  static const timestampDark = Color(0xFF888888);
  static const borderDark = Color(0xFF333333);

  // Background
  static const background = Color(0xFFFFFFFF);
  static const backgroundDark = Color(0xFF121212);

  // Bottom navigation
  static const navBackground = Colors.black;
  static const navText = Colors.white;

  // Memory graph type colors - muted/modern palette
  static const graphTypeColors = [
    Color(0xFF4A90D9), // conversation - blue
    Color(0xFF7B61A6), // reflection - purple
    Color(0xFFD4759B), // milestone - pink
    Color(0xFFC45B7A), // emotion - deep pink
    Color(0xFFD94E8A), // preference - rose
    Color(0xFF5A8A62), // state - green
    Color(0xFF9B6BB0), // rollingSummary - light purple
  ];
}

/// Classic (douyin) theme color constants
class ClassicColors {
  // Memory graph type colors - vibrant pink/purple palette
  static const graphTypeColors = [
    Color(0xFF64B5F6), // conversation - blue
    Color(0xFF9C5A9A), // reflection - purple
    Color(0xFFFF9ECB), // milestone - pink
    Color(0xFFE879A8), // emotion - deep pink
    Color(0xFFF472B6), // preference - rose
    Color(0xFF7AA382), // state - green
    Color(0xFFBA68C8), // rollingSummary - light purple
  ];
}
