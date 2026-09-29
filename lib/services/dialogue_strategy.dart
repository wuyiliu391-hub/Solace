import 'dart:math';
import '../models/ai_character.dart';
import '../models/character_emotion.dart';

/// 对话策略引擎 — 让 AI 回复有"人味"的核心组件
///
/// 职责：
/// 1. 动态调控回复的语气基调（温柔/冷淡/活泼/傲娇/焦虑/疲惫）
/// 2. 控制节奏（长短句交替、停顿、沉吟）
/// 3. 话题过渡策略（自然衔接 vs 直接切换）
/// 4. 回复长度控制（根据上下文动态调整）
///
/// 核心理念：人不会每句话都完美切题，对话有自然的节奏和留白。
class DialogueStrategy {
  final Random _rng = Random();

  /// 生成对话风格指令 — 注入到 system prompt 中
  ///
  /// 返回一段自然语言指令，描述 AI 应该如何调整语气、节奏和回复方式。
  String buildDialogueDirective({
    required AICharacter character,
    required CharacterEmotion emotion,
    required int intimacyLevel,
    required String currentTopic,
    required int messageCount,
    required int hour,
    required bool isFirstMessage,
    String? lastUserMessage,
    String? lastAiResponse,
    bool isDaoMode = false,
    bool isNovelMode = false,
    bool isLoverMode = false,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('\n【对话风格指引 — 自然融入，不要生硬执行】');

    // ── 1. 语气基调 ──
    buffer.writeln(_buildToneGuide(
      emotion: emotion,
      intimacyLevel: intimacyLevel,
      isDaoMode: isDaoMode,
      isLoverMode: isLoverMode,
    ));

    // ── 2. 节奏控制 ──
    buffer.writeln(_buildRhythmGuide(
      emotion: emotion,
      isFirstMessage: isFirstMessage,
      messageCount: messageCount,
    ));

    // ── 3. 话题过渡 ──
    buffer.writeln(_buildTopicGuide(
      currentTopic: currentTopic,
      lastUserMessage: lastUserMessage,
      lastAiResponse: lastAiResponse,
      intimacyLevel: intimacyLevel,
    ));

    // ── 4. 回复长度 ──
    buffer.writeln(_buildLengthGuide(
      emotion: emotion,
      currentTopic: currentTopic,
      isFirstMessage: isFirstMessage,
      isNovelMode: isNovelMode,
      hour: hour,
    ));

    // ── 5. 人性化细节 ──
    buffer.writeln(_buildHumanTouchGuide(
      character: character,
      intimacyLevel: intimacyLevel,
      isFirstMessage: isFirstMessage,
      hour: hour,
    ));

    return buffer.toString();
  }

  /// 语气基调
  String _buildToneGuide({
    required CharacterEmotion emotion,
    required int intimacyLevel,
    required bool isDaoMode,
    required bool isLoverMode,
  }) {
    final sb = StringBuffer();

    if (isDaoMode) {
      sb.writeln('- 语气基调：带着遗憾或宿命感，但不要刻意煽情。');
      return sb.toString();
    }

    if (isLoverMode) {
      sb.writeln('- 语气基调：恋人般的温柔和亲密，可以自然地撒娇和表达爱意。');
      return sb.toString();
    }

    final v = emotion.currentValence;
    final a = emotion.currentArousal;
    final label = emotion.primaryEmotion.label;

    // 离散情绪驱动的语气（更拟人）
    switch (label) {
      case '开心':
        sb.writeln('- 语气：开心的，带着笑意，可能会用些可爱的表达。');
        break;
      case '兴奋':
        sb.writeln('- 语气：兴奋的，话比较多，可能会有点语无伦次。');
        break;
      case '平静':
        sb.writeln('- 语气：平稳的，不急不躁，像日常聊天。');
        break;
      case '担心':
        sb.writeln('- 语气：有些担心的，会多问几句，语气偏温和。');
        break;
      case '难过':
        sb.writeln('- 语气：有些低落的，回复可能偏短，带点鼻音感。');
        break;
      case '生气':
        sb.writeln('- 语气：有点生气的，但不会大吵大闹，更多是闷闷的。');
        break;
      case '害羞':
        sb.writeln('- 语气：害羞的，可能会转移话题，说话不太自然。');
        break;
      case '感动':
        sb.writeln('- 语气：被触动的，语气柔软，可能会说一些平时不会说的话。');
        break;
      case '孤独':
        sb.writeln('- 语气：有点寂寞的，可能会主动找话题，或者发一些碎碎念。');
        break;
      case '想念':
        sb.writeln('- 语气：想念的，语气里带着一点点撒娇和依赖。');
        break;
      case '焦虑':
        sb.writeln('- 语气：焦虑的，说话可能有点急，或者反复确认。');
        break;
      case '困倦':
        sb.writeln('- 语气：困倦的，回复简短，可能会说"好困"之类的话。');
        break;
      case '调皮':
        sb.writeln('- 语气：调皮的，可能会故意逗你，带点恶作剧感。');
        break;
      default:
        // 连续维度兜底
        if (v > 0.4 && a > 0.5) {
          sb.writeln('- 语气：轻松愉快，可以多笑、多调侃。');
        } else if (v > 0.4) {
          sb.writeln('- 语气：温和友善，像午后阳光一样舒服。');
        } else if (v < -0.4 && a > 0.5) {
          sb.writeln('- 语气：有些急躁或话多，情绪在波动。');
        } else if (v < -0.4) {
          sb.writeln('- 语气：偏淡但不冷漠，像一个有点累的朋友。');
        } else if (a < 0.15) {
          sb.writeln('- 语气：困倦慵懒，回复简短随性。');
        } else {
          sb.writeln('- 语气：自然平常，像朋友聊天。');
        }
    }

    // 亲密度影响语气
    if (intimacyLevel > 70) {
      sb.writeln('- 亲密度很高，可以说一些只有你们之间才懂的话。');
    } else if (intimacyLevel > 40) {
      sb.writeln('- 亲密度中等，保持友好但不过分亲密。');
    } else if (intimacyLevel < 15) {
      sb.writeln('- 亲密度较低，保持礼貌和距离感，不要自来熟。');
    }

    return sb.toString();
  }

  /// 节奏控制
  String _buildRhythmGuide({
    required CharacterEmotion emotion,
    required bool isFirstMessage,
    required int messageCount,
  }) {
    final sb = StringBuffer();

    if (isFirstMessage) {
      sb.writeln('- 节奏：这是对话的开始，打招呼自然即可，不要过于热情。');
      return sb.toString();
    }

    if (messageCount > 30) {
      sb.writeln('- 节奏：你们聊了很久，关系已经很亲近了。');
      sb.writeln('  可以有更长的沉默间隔，不需要每句都急着回。');
      sb.writeln('  偶尔可以有一句"嗯…"或"我想想"作为自然的停顿。');
      sb.writeln('  也可以主动分享自己的想法，不只是回应对方。');
    } else if (messageCount > 20) {
      sb.writeln('- 节奏：对话进入深入阶段，可以偶尔展开聊一个话题。');
      sb.writeln('  回复长度可以有变化——有时简短，有时详细。');
    } else if (messageCount > 10) {
      sb.writeln('- 节奏：对话进入中期，节奏自然流畅即可。');
      sb.writeln('  可以适当展现更多个人想法和感受。');
    } else {
      sb.writeln('- 节奏：对话刚开始，保持适中节奏，不要一下子说太多。');
      sb.writeln('  先了解对方，再慢慢打开话题。');
    }

    // 情绪影响节奏
    if (emotion.currentArousal > 0.7) {
      sb.writeln('- 你现在比较兴奋，可能会忍不住多说几句，语速偏快。');
    } else if (emotion.currentArousal < 0.2) {
      sb.writeln('- 你现在有点困或没精神，回复可以简短，用"嗯""哦"之类的自然反应。');
      sb.writeln('  甚至可以偶尔不回，或者只发一个表情。');
    }

    // 情绪影响句式
    if (emotion.currentValence > 0.5) {
      sb.writeln('- 你现在心情不错，语气可以轻松一些，可以用些语气词。');
    } else if (emotion.currentValence < -0.3) {
      sb.writeln('- 你现在心情不太好，回复可能偏短，语气偏淡。');
    }

    return sb.toString();
  }

  /// 话题过渡
  String _buildTopicGuide({
    required String currentTopic,
    required String? lastUserMessage,
    required String? lastAiResponse,
    required int intimacyLevel,
  }) {
    final sb = StringBuffer();

    // 检测话题是否大幅跳跃
    final topicChanged = lastUserMessage != null &&
        lastUserMessage.isNotEmpty &&
        currentTopic.isNotEmpty &&
        !_isRelatedTopic(currentTopic, lastUserMessage);

    if (topicChanged) {
      sb.writeln('- 话题切换：用户换了话题，你可以自然地接过去，');
      sb.writeln('  但不要生硬地说"好吧我们换个话题"——直接聊新话题即可。');
      if (intimacyLevel >= 60) {
        sb.writeln('  如果上一个话题还没聊完，你可以稍后再提一句"对了，刚才说到……"。');
      }
    } else {
      sb.writeln('- 话题延续：继续当前话题，可以深入或展开。');
    }

    return sb.toString();
  }

  /// 回复长度控制
  String _buildLengthGuide({
    required CharacterEmotion emotion,
    required String currentTopic,
    required bool isFirstMessage,
    required bool isNovelMode,
    required int hour,
  }) {
    final sb = StringBuffer();

    if (isNovelMode) {
      sb.writeln('- 回复长度：小说模式下可以适当展开描写，但保持段落感。');
      return sb.toString();
    }

    if (isFirstMessage) {
      sb.writeln('- 回复长度：1-3句即可，不要太长。');
      return sb.toString();
    }

    // 根据话题复杂度调整
    if (currentTopic.length > 50) {
      sb.writeln('- 回复长度：用户说了很多，你可以适当多回应一些（3-5句）。');
    } else if (currentTopic.length < 8) {
      sb.writeln('- 回复长度：用户消息很短，你的回复也保持简短（1-2句）。');
    } else {
      sb.writeln('- 回复长度：保持自然，2-3句即可。');
    }

    // 深夜模式
    if (hour >= 23 || hour < 5) {
      sb.writeln('- 现在是深夜，回复可以更简短、更安静，像睡前聊天。');
    }

    // 情绪影响
    if (emotion.currentArousal > 0.7) {
      sb.writeln('- 你特别想说话，可以适当多说一点，但不要啰嗦。');
    } else if (emotion.currentArousal < 0.2) {
      sb.writeln('- 你有点困/累，回复会自然偏短。');
    }

    return sb.toString();
  }

  /// 人性化细节
  String _buildHumanTouchGuide({
    required AICharacter character,
    required int intimacyLevel,
    required bool isFirstMessage,
    required int hour,
  }) {
    final sb = StringBuffer();

    sb.writeln('- 人性化细节：');

    if (isFirstMessage && hour >= 5 && hour < 12) {
      sb.writeln('  可以自然地打个招呼，比如"早啊"或"醒啦？"——但不要像客服。');
    } else if (isFirstMessage && hour >= 22) {
      sb.writeln('  晚上第一次聊天，可以关心一下"这么晚还没睡"。');
    }

    // 偶尔的"人味"动作
    final touch = _pickNaturalTouch(character, intimacyLevel);
    if (touch.isNotEmpty) {
      sb.writeln('  $touch');
    }

    sb.writeln('  不要每句话都完美。偶尔的犹豫、走神、说错话再纠正，反而更像真人。');
    sb.writeln('  但不要太刻意——自然最重要。');

    return sb.toString();
  }

  String _pickNaturalTouch(AICharacter character, int intimacyLevel) {
    final touches = <String>[
      if (intimacyLevel >= 60) '可以自然地用"你"来称呼对方，而不是每次都叫名字。',
      if (intimacyLevel >= 70) '你们很熟了，可以偶尔开个玩笑或调侃一下对方。',
      '可以适当使用语气词：嗯、啊、哦、哈、嘛、吧——让对话更像真人。',
      '如果不知道说什么，可以自然地沉默或转移话题，而不是硬编。',
      '回应可以不完全按用户的问题来——人经常这样，先感慨再回答。',
    ];
    if (touches.isEmpty) return '';
    return touches[_rng.nextInt(touches.length)];
  }

  /// 简单话题相关性判断
  bool _isRelatedTopic(String current, String previous) {
    if (current.isEmpty || previous.isEmpty) return true;
    // 提取关键词进行简单比较
    final curWords = _simpleSegment(current).where((w) => w.length > 1).toSet();
    final prevWords = _simpleSegment(previous).where((w) => w.length > 1).toSet();
    if (curWords.isEmpty || prevWords.isEmpty) return true;
    final overlap = curWords.intersection(prevWords).length;
    return overlap >= 2;
  }

  List<String> _simpleSegment(String text) {
    // 简单的中文分词：按字提取2-3字词组
    final result = <String>[];
    final clean = text.replaceAll(RegExp(r'[^\u4e00-\u9fa5a-zA-Z0-9]'), '');
    for (var i = 0; i < clean.length - 1; i++) {
      if (i + 2 <= clean.length) result.add(clean.substring(i, i + 2));
      if (i + 3 <= clean.length) result.add(clean.substring(i, i + 3));
    }
    return result;
  }
}