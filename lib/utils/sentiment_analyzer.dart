enum SentimentType { veryPositive, positive, neutral, negative, veryNegative }

class SentimentResult {
  final SentimentType type;
  final int score;
  final String label;

  const SentimentResult({
    required this.type,
    required this.score,
    required this.label,
  });
}

class SentimentAnalyzer {
  static const _positiveWords = [
    '谢谢', '感谢', '喜欢', '爱你', '爱死', '好喜欢', '真棒', '太好了', '开心',
    '漂亮', '可爱', '温柔', '帅气', '好看', '美', '帅',
    '想你了', '想你', '抱抱', '贴贴',
    '乖', '真乖', '好乖', '聪明', '厉害', '优秀',
    '暖心', '贴心', '懂我', '真好', '好呀', '好啊',
    '么么', '晚安', '早安', '好梦',
    '幸福', '感动', '温暖', '美好',
    'nice', 'love', 'great', 'amazing', 'cute', 'sweet',
    'good', 'beautiful', 'wonderful',
  ];

  static const _negativeWords = [
    '讨厌', '滚', '烦', '恶心', '闭嘴', '滚开',
    '蠢', '傻', '有病', '垃圾', '废物', '白痴',
    '不想', '别烦', '走开', '去死', '死',
    '无聊', '没意思', '烦死了', '烦人',
    '差劲', '糟糕', '烂', '差',
    '恨你', '讨厌你', '烦你',
    '无语', '醉了', '呵呵', '呵呵哒',
    'hate', 'stupid', 'idiot', 'ugly', 'terrible',
    'shut up', 'go away', 'leave me',
  ];

  static const _veryNegativeWords = [
    '去死', '滚蛋', '废物', '垃圾', '恶心死了',
    '猪', '狗', '畜生', '混蛋', '王八蛋',
    'fuck', 'shit', 'bitch', 'damn',
  ];

  static SentimentResult analyze(String message) {
    final text = message.trim().toLowerCase();
    if (text.isEmpty) {
      return const SentimentResult(
        type: SentimentType.neutral,
        score: 0,
        label: 'neutral',
      );
    }

    int positiveScore = 0;
    int negativeScore = 0;

    for (final word in _veryNegativeWords) {
      if (text.contains(word)) {
        negativeScore += 3;
      }
    }

    for (final word in _negativeWords) {
      if (text.contains(word)) {
        negativeScore += 1;
      }
    }

    for (final word in _positiveWords) {
      if (text.contains(word)) {
        positiveScore += 1;
      }
    }

    // 表情符号分析
    if (text.contains('😊') || text.contains('😍') || text.contains('🥰') ||
        text.contains('❤') || text.contains('😘') || text.contains('💕') ||
        text.contains('🥺') || text.contains('😭') || text.contains('😄')) {
      positiveScore += 1;
    }
    if (text.contains('😡') || text.contains('👿') || text.contains('💢') ||
        text.contains('🤬') || text.contains('😤')) {
      negativeScore += 2;
    }

    // 感叹号和问号分析
    final exclaimCount = '!'.allMatches(text).length + '！'.allMatches(text).length;

    if (exclaimCount >= 3 && negativeScore > 0) {
      negativeScore += 1;
    }

    final netScore = positiveScore - negativeScore;

    if (netScore >= 2) {
      return const SentimentResult(
        type: SentimentType.veryPositive,
        score: 2,
        label: '非常开心',
      );
    } else if (netScore >= 1) {
      return const SentimentResult(
        type: SentimentType.positive,
        score: 1,
        label: '友善',
      );
    } else if (netScore <= -3) {
      return const SentimentResult(
        type: SentimentType.veryNegative,
        score: -3,
        label: '非常愤怒',
      );
    } else if (netScore <= -1) {
      return const SentimentResult(
        type: SentimentType.negative,
        score: -1,
        label: '负面',
      );
    } else {
      return const SentimentResult(
        type: SentimentType.neutral,
        score: 0,
        label: '平静',
      );
    }
  }
}