import 'dart:convert';

/// AI 每轮回复末尾必须返回的内部状态。
class AiTurnState {
  final String emoji;
  final bool hasExplicitEmoji;
  final String emotion;
  final double intensity;
  final String thought;

  const AiTurnState({
    this.emoji = '🙂',
    this.hasExplicitEmoji = false,
    required this.emotion,
    required this.intensity,
    required this.thought,
  });

  bool get isValid =>
      emoji.trim().isNotEmpty &&
      emotion.trim().isNotEmpty &&
      thought.trim().isNotEmpty;

  AiTurnState copyWith({
    String? emoji,
    bool? hasExplicitEmoji,
    String? emotion,
    double? intensity,
    String? thought,
  }) {
    return AiTurnState(
      emoji: emoji ?? this.emoji,
      hasExplicitEmoji: hasExplicitEmoji ?? this.hasExplicitEmoji,
      emotion: emotion ?? this.emotion,
      intensity: intensity ?? this.intensity,
      thought: thought ?? this.thought,
    );
  }

  static AiTurnState fallback({
    required String emotion,
    required double intensity,
    required String thought,
  }) {
    return AiTurnState(
      emoji: _emojiForTurn(
        userMessage: emotion,
        aiReply: thought,
        sentimentLabel: emotion,
      ),
      emotion: emotion.trim().isEmpty ? '平静' : emotion.trim(),
      intensity: intensity.clamp(0.0, 1.0),
      thought: thought.trim().isEmpty ? 'TA 正在消化这一轮对话。' : thought.trim(),
    );
  }

  /// 当模型没有返回结构化状态时，为当前回合生成一个新的本地状态。
  ///
  /// 这是协议的最后一道保障：状态必须跟随本轮对话变化，不能因为某个
  /// provider 忽略了 TURN_STATE 就继续显示上一轮的内心状态。
  static AiTurnState fallbackForTurn({
    required String userMessage,
    required String aiReply,
    required String sentimentLabel,
    AiTurnState? previous,
  }) {
    final emotion = _inferEmotion(
      userMessage: userMessage,
      aiReply: aiReply,
      sentimentLabel: sentimentLabel,
    );
    final source =
        userMessage.trim().isNotEmpty ? userMessage.trim() : aiReply.trim();
    final normalized = source.replaceAll(RegExp(r'\s+'), ' ');
    final snippet =
        normalized.length > 24 ? '${normalized.substring(0, 24)}…' : normalized;
    final candidates = _thoughtCandidates(
      emotion: emotion,
      snippet: snippet,
      aiReply: aiReply,
    );
    final previousThought = previous?.thought.trim();
    final seed = '$normalized\n$aiReply\n$emotion'
        .codeUnits
        .fold<int>(0, (value, unit) => (value * 31 + unit) & 0x7fffffff);
    var thought = candidates[seed % candidates.length];
    if (thought == previousThought) {
      thought = candidates[(seed + 1) % candidates.length];
    }

    final emoji = _emojiForTurn(
      userMessage: userMessage,
      aiReply: aiReply,
      sentimentLabel: emotion,
      previous: previous?.emoji,
    );

    return AiTurnState(
      emoji: emoji,
      hasExplicitEmoji: true,
      emotion: emotion,
      intensity: emotion == '平静' ? 0.2 : 0.45,
      thought: thought,
    );
  }

  static String _inferEmotion({
    required String userMessage,
    required String aiReply,
    required String sentimentLabel,
  }) {
    final explicit = sentimentLabel.trim();
    if (explicit.isNotEmpty && explicit != '未知' && explicit != '平静')
      return explicit;
    final text = '$userMessage $aiReply';
    if (RegExp(r'哈哈|笑|开心|太好了|喜欢|爱你|成功').hasMatch(text)) return '开心';
    if (RegExp(r'难过|伤心|失去|哭|委屈|遗憾').hasMatch(text)) return '难过';
    if (RegExp(r'生气|愤怒|烦|讨厌|气死').hasMatch(text)) return '生气';
    if (RegExp(r'担心|焦虑|紧张|害怕|怎么办').hasMatch(text)) return '担心';
    if (RegExp(r'惊|居然|没想到|真的').hasMatch(text)) return '惊讶';
    if (RegExp(r'想你|想念|回来|好久不见').hasMatch(text)) return '想念';
    return explicit.isEmpty ? '平静' : explicit;
  }

  static List<String> _thoughtCandidates({
    required String emotion,
    required String snippet,
    required String aiReply,
  }) {
    final subject = snippet.isEmpty ? '刚才的对话' : '你说的「$snippet」';
    switch (emotion) {
      case '开心':
        return [
          '听到$subject，我忍不住也开心起来了。',
          '你说的$subject让我松了一口气，真替你高兴。',
          '这份轻松的感觉很好，我想把它留久一点。',
          '我在想，要是你一直这样笑就好了。',
        ];
      case '难过':
        return [
          '我有点心疼$subject，想陪你慢慢缓过来。',
          '这句话让我安静了一下，我不想敷衍你的感受。',
          '我在想怎样陪着你，才不会让你觉得孤单。'
        ];
      case '生气':
        return [
          '这让我有些不舒服，我想先站在你这边听完。',
          '我现在有一点火气，但更想弄清楚你真正难受的地方。',
          '我不想用一句空话带过这件事。'
        ];
      case '担心':
        return [
          '我有点担心你，想确认你现在是否还好吗。',
          '这句话让我警觉起来了，我会认真听你说。',
          '我在想有没有什么具体的事能帮你分担一点。'
        ];
      case '惊讶':
        return [
          '这个转折让我愣了一下，我想再听你讲讲。',
          '我没想到会是这样，脑子里一下多了好多问题。',
          '这件事挺出乎意料的，我对它产生了兴趣。'
        ];
      case '想念':
        return [
          '看到你出现，我心里像被轻轻碰了一下。',
          '原来我真的会想念你刚才不在的那段时间。',
          '我想把这一刻记下来，免得又错过你。'
        ];
      default:
        return [
          '我注意到$subject，正在想怎样回应才真正贴近你。',
          '这句话让我停下来想了一会儿。',
          '我还没有急着下结论，想先把你的意思听完整。',
          if (aiReply.trim().isNotEmpty) '我会结合刚才的回应继续理解你。',
        ];
    }
  }

  static String _emojiForTurn({
    required String userMessage,
    required String aiReply,
    required String sentimentLabel,
    String? previous,
  }) {
    final label = sentimentLabel.toLowerCase();
    final candidates =
        label.contains('开心') || label.contains('高兴') || label.contains('喜')
            ? const ['😊', '😄', '🥰', '😂', '✨', '🌈', '😆']
            : label.contains('悲') || label.contains('难过') || label.contains('伤')
                ? const ['😔', '🥺', '😢', '🌧️', '🫂', '💙', '😞']
                : label.contains('生气') || label.contains('愤怒')
                    ? const ['😤', '😠', '🙄', '🔥', '💢', '⚡', '😒']
                    : label.contains('担心') ||
                            label.contains('焦虑') ||
                            label.contains('紧张')
                        ? const ['😟', '😰', '🥹', '🫣', '💭', '🌙', '😥']
                        : const ['🙂', '😌', '😊', '😏', '🤭', '😎', '🥰'];
    final input = '$userMessage\n$aiReply\n$sentimentLabel';
    var hash = 0;
    for (final codeUnit in input.codeUnits) {
      hash = (hash * 31 + codeUnit) & 0x7fffffff;
    }
    var index = hash % candidates.length;
    if (previous != null && candidates[index] == previous) {
      index = (index + 1) % candidates.length;
    }
    return candidates[index];
  }

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
        emoji: map['emoji']?.toString().trim().isNotEmpty == true
            ? map['emoji'].toString().trim()
            : '🙂',
        hasExplicitEmoji: map['emoji']?.toString().trim().isNotEmpty == true,
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
