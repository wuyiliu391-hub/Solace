import 'dart:convert';

/// AI 每轮回复末尾必须返回的内部状态。
class AiTurnState {
  final String emotion;
  final double intensity;
  final String thought;

  const AiTurnState({
    required this.emotion,
    required this.intensity,
    required this.thought,
  });

  bool get isValid => emotion.trim().isNotEmpty && thought.trim().isNotEmpty;

  static AiTurnState? parse(String content) {
    final match = RegExp(
      r'\[TURN_STATE\]\s*(.*?)\s*\[/TURN_STATE\]',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(content);
    if (match == null) return null;
    try {
      final decoded = jsonDecode(match.group(1)?.trim() ?? '');
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      return AiTurnState(
        emotion: map['emotion']?.toString().trim() ?? '',
        intensity:
            ((map['intensity'] as num?)?.toDouble() ?? 0.5).clamp(0.0, 1.0),
        thought: map['thought']?.toString().trim() ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  static String? parseLegacyStatus(String content) {
    final match = RegExp(
      r'\[STATUS\](.*?)\[/STATUS\]',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(content);
    return match?.group(1)?.trim();
  }
}
