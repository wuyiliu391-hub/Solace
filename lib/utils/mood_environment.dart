import 'package:flutter/material.dart';
import 'sentiment_analyzer.dart';

class MoodEnvironment {
  static const Map<SentimentType, _MoodTheme> _moodThemes = {
    SentimentType.veryPositive: _MoodTheme(
      primaryColor: Color(0xFFFFF3E0),
      secondaryColor: Color(0xFFFFE0B2),
      accentColor: Color(0xFFFF9800),
      gradientColors: [Color(0xFFFFF8E1), Color(0xFFFFE0B2), Color(0xFFFFCC80)],
      atmosphere: '阳光明媚',
      description: '温暖明亮的氛围',
      icon: Icons.wb_sunny,
    ),
    SentimentType.positive: _MoodTheme(
      primaryColor: Color(0xFFE8F5E9),
      secondaryColor: Color(0xFFC8E6C9),
      accentColor: Color(0xFF4CAF50),
      gradientColors: [Color(0xFFE8F5E9), Color(0xFFC8E6C9), Color(0xFFA5D6A7)],
      atmosphere: '微风和煦',
      description: '轻松愉快的氛围',
      icon: Icons.wb_cloudy,
    ),
    SentimentType.neutral: _MoodTheme(
      primaryColor: Color(0xFFF5F5F5),
      secondaryColor: Color(0xFFE0E0E0),
      accentColor: Color(0xFF9E9E9E),
      gradientColors: [Color(0xFFFAFAFA), Color(0xFFF5F5F5), Color(0xFFEEEEEE)],
      atmosphere: '平静安宁',
      description: '平和宁静的氛围',
      icon: Icons.brightness_4,
    ),
    SentimentType.negative: _MoodTheme(
      primaryColor: Color(0xFFECEFF1),
      secondaryColor: Color(0xFFCFD8DC),
      accentColor: Color(0xFF607D8B),
      gradientColors: [Color(0xFFECEFF1), Color(0xFFCFD8DC), Color(0xFFB0BEC5)],
      atmosphere: '阴天微雨',
      description: '略显低沉的氛围',
      icon: Icons.cloud,
    ),
    SentimentType.veryNegative: _MoodTheme(
      primaryColor: Color(0xFFF3E5F5),
      secondaryColor: Color(0xFFE1BEE7),
      accentColor: Color(0xFF9C27B0),
      gradientColors: [Color(0xFFF3E5F5), Color(0xFFE1BEE7), Color(0xFFCE93D8)],
      atmosphere: '风雨欲来',
      description: '紧张压抑的氛围',
      icon: Icons.thunderstorm,
    ),
  };

  static _MoodTheme getTheme(SentimentType type) {
    return _moodThemes[type] ?? _moodThemes[SentimentType.neutral]!;
  }

  static BoxDecoration buildBackgroundDecoration({
    required SentimentType emotionType,
    BoxDecoration? existingDecoration,
  }) {
    final theme = getTheme(emotionType);

    return BoxDecoration(
      color: theme.primaryColor,
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: theme.gradientColors.map((c) => c.withOpacity(0.3)).toList(),
      ),
    );
  }

  static BoxDecoration buildOverlayDecoration({
    required SentimentType emotionType,
  }) {
    final theme = getTheme(emotionType);

    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          theme.primaryColor.withOpacity(0.08),
          theme.secondaryColor.withOpacity(0.05),
        ],
      ),
    );
  }

  static String getAtmosphere(SentimentType type) {
    return getTheme(type).atmosphere;
  }

  static IconData getIcon(SentimentType type) {
    return getTheme(type).icon;
  }
}

class _MoodTheme {
  final Color primaryColor;
  final Color secondaryColor;
  final Color accentColor;
  final List<Color> gradientColors;
  final String atmosphere;
  final String description;
  final IconData icon;

  const _MoodTheme({
    required this.primaryColor,
    required this.secondaryColor,
    required this.accentColor,
    required this.gradientColors,
    required this.atmosphere,
    required this.description,
    required this.icon,
  });
}