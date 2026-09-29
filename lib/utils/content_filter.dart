class ContentFilterResult {
  final bool isNSFW;
  final String? matchedKeyword;

  const ContentFilterResult({
    this.isNSFW = false,
    this.matchedKeyword,
  });
}

class ContentFilter {
  ContentFilter._();

  static final List<String> _nsfwKeywords = [
    '做爱', '性交', '操你', '操我', '日你', '日我',
    '干你', '干我', '肏', '草你', '艹你',
    '口交', '肛交', '乳交', '自慰', '手淫',
    '阴茎', '阴道', '乳房', '屁股', '奶子', '鸡巴', '屄', '逼',
    '阴蒂', '子宫', '睾丸', '精液', '高潮', '射精',
    'sm', '捆绑', '调教', '性奴', '性虐',
    '援交', '约炮', '一夜情', '裸聊',
    '骚逼', '骚货', '贱人', '荡妇',
    '淫荡', '淫乱', '淫水', '淫叫',
    '色情', '黄片', 'av', '毛片',
    '脱光', '裸体', '一丝不挂',
    '成人用品', '情趣用品', '飞机杯', '震动棒',
    '自摸', '意淫', '叫床',
    '操死', '干死', '日死',
    '骚穴', '小穴', '肉棒', '肉穴',
    '插进', '插入', '抽插',
    '开房', '开房',
    '包养', '嫖',
    '成人网站', '黄色网站',
  ];

  static final List<RegExp> _nsfwPatterns = [
    RegExp(r'想(操|干|日|草|肏)(你|我|她|他)'),
    RegExp(r'(脱|扒)(光|掉)(衣服|裤子|内裤)'),
    RegExp(r'(看|拍)(裸体|裸照|私密)'),
    RegExp(r'(陪|跟)(我|你)(睡|上床|做爱)'),
    RegExp(r'(要|想)(上|睡|干|操)(你|她|他)'),
  ];

  static ContentFilterResult check(String message) {
    final lower = message.toLowerCase();

    for (final keyword in _nsfwKeywords) {
      if (lower.contains(keyword)) {
        return ContentFilterResult(isNSFW: true, matchedKeyword: keyword);
      }
    }

    for (final pattern in _nsfwPatterns) {
      if (pattern.hasMatch(lower)) {
        return ContentFilterResult(isNSFW: true, matchedKeyword: pattern.pattern);
      }
    }

    return const ContentFilterResult();
  }
}
