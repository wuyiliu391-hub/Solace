import 'package:flutter/material.dart';

/// 塔罗牌数据模型
class TarotCard {
  final int id;
  final String name; // 英文名
  final String nameCn; // 中文名
  final String arcana; // major / minor
  final String? suit; // cups / pentacles / swords / wands (小牌才有)
  final String uprightMeaning; // 正位含义
  final String reversedMeaning; // 逆位含义
  final IconData icon; // Material Icon 代表

  const TarotCard({
    required this.id,
    required this.name,
    required this.nameCn,
    required this.arcana,
    this.suit,
    required this.uprightMeaning,
    required this.reversedMeaning,
    required this.icon,
  });
}

/// 牌阵类型
enum SpreadType {
  single, // 单张牌
  threeCard, // 三张牌（过去/现在/未来）
  celticCross, // 凯尔特十字（简化版5张）
}

extension SpreadTypeX on SpreadType {
  String get name {
    switch (this) {
      case SpreadType.single:
        return '单张牌';
      case SpreadType.threeCard:
        return '三张牌';
      case SpreadType.celticCross:
        return '五张牌阵';
    }
  }

  String get description {
    switch (this) {
      case SpreadType.single:
        return '快速指引，一牌定乾坤';
      case SpreadType.threeCard:
        return '过去 · 现在 · 未来';
      case SpreadType.celticCross:
        return '深度探索，全面解读';
    }
  }

  IconData get icon {
    switch (this) {
      case SpreadType.single:
        return Icons.style;
      case SpreadType.threeCard:
        return Icons.view_week;
      case SpreadType.celticCross:
        return Icons.auto_awesome;
    }
  }

  int get cardCount {
    switch (this) {
      case SpreadType.single:
        return 1;
      case SpreadType.threeCard:
        return 3;
      case SpreadType.celticCross:
        return 5;
    }
  }

  List<String> get positionNames {
    switch (this) {
      case SpreadType.single:
        return ['指引'];
      case SpreadType.threeCard:
        return ['过去', '现在', '未来'];
      case SpreadType.celticCross:
        return ['现状', '挑战', '过去', '近期', '建议'];
    }
  }
}

/// 三牌阵解读模式
enum ThreeCardMode {
  timeline,       // 过去 · 现在 · 未来
  decision,       // 现状 · 阻力 · 建议
  relationship,   // 你 · 对方 · 关系走向
  mindBodySpirit, // 心智 · 身体 · 灵性
}

extension ThreeCardModeX on ThreeCardMode {
  String get name {
    switch (this) {
      case ThreeCardMode.timeline:
        return '时间流';
      case ThreeCardMode.decision:
        return '抉择指引';
      case ThreeCardMode.relationship:
        return '感情解读';
      case ThreeCardMode.mindBodySpirit:
        return '身心灵';
    }
  }

  String get description {
    switch (this) {
      case ThreeCardMode.timeline:
        return '过去 · 现在 · 未来';
      case ThreeCardMode.decision:
        return '现状 · 阻力 · 建议';
      case ThreeCardMode.relationship:
        return '你 · 对方 · 关系走向';
      case ThreeCardMode.mindBodySpirit:
        return '心智 · 身体 · 灵性';
    }
  }

  IconData get icon {
    switch (this) {
      case ThreeCardMode.timeline:
        return Icons.timeline;
      case ThreeCardMode.decision:
        return Icons.compare_arrows;
      case ThreeCardMode.relationship:
        return Icons.favorite;
      case ThreeCardMode.mindBodySpirit:
        return Icons.self_improvement;
    }
  }

  List<String> get positionNames {
    switch (this) {
      case ThreeCardMode.timeline:
        return ['过去', '现在', '未来'];
      case ThreeCardMode.decision:
        return ['现状', '阻力', '建议'];
      case ThreeCardMode.relationship:
        return ['你', '对方', '关系走向'];
      case ThreeCardMode.mindBodySpirit:
        return ['心智', '身体', '灵性'];
    }
  }
}

/// 根据用户问题智能推荐三牌阵解读模式
ThreeCardMode recommendThreeCardMode(String question) {
  final q = question.toLowerCase();

  // 感情类关键词
  if (RegExp(r'喜欢|恋爱|爱情|对象|暗恋|表白|分手|复合|男朋友|女朋友|老公|老婆|另一半| crush |暧昧|约会|异地|出轨|挽回|桃花')
      .hasMatch(q)) {
    return ThreeCardMode.relationship;
  }

  // 抉择类关键词
  if (RegExp(r'选择|抉择|决定|怎么办|该不该|要不要|犹豫|纠结|辞职|跳槽|考研|考公|创业|转行|换工作|A还是B|哪个好')
      .hasMatch(q)) {
    return ThreeCardMode.decision;
  }

  // 灵性/成长类关键词
  if (RegExp(r'灵性|成长|内心|修行|冥想|心灵|情绪|焦虑|抑郁|自我|方向|人生|意义|迷茫|状态')
      .hasMatch(q)) {
    return ThreeCardMode.mindBodySpirit;
  }

  return ThreeCardMode.timeline;
}

/// 塔罗牌数据库 — 22张大阿卡纳 + 56张小阿卡纳
class TarotDeck {
  TarotDeck._();

  static const List<TarotCard> majorArcana = [
    TarotCard(
      id: 0, name: 'The Fool', nameCn: '愚者', arcana: 'major',
      icon: Icons.child_care,
      uprightMeaning: '新的开始、冒险精神、天真无邪、自由',
      reversedMeaning: '鲁莽、冒险、缺乏计划、不成熟',
    ),
    TarotCard(
      id: 1, name: 'The Magician', nameCn: '魔术师', arcana: 'major',
      icon: Icons.auto_fix_high,
      uprightMeaning: '创造力、意志力、技能、自信',
      reversedMeaning: '欺骗、操纵、能力不足、浪费天赋',
    ),
    TarotCard(
      id: 2, name: 'The High Priestess', nameCn: '女祭司', arcana: 'major',
      icon: Icons.nightlight_round,
      uprightMeaning: '直觉、潜意识、内在智慧、神秘',
      reversedMeaning: '秘密被揭露、缺乏直觉、表面化',
    ),
    TarotCard(
      id: 3, name: 'The Empress', nameCn: '女皇', arcana: 'major',
      icon: Icons.workspace_premium,
      uprightMeaning: '丰饶、母性、自然、创造力',
      reversedMeaning: '依赖他人、缺乏安全感、创造力受阻',
    ),
    TarotCard(
      id: 4, name: 'The Emperor', nameCn: '皇帝', arcana: 'major',
      icon: Icons.account_balance,
      uprightMeaning: '权威、稳定、领导力、秩序',
      reversedMeaning: '专制、固执、控制欲、缺乏灵活性',
    ),
    TarotCard(
      id: 5, name: 'The Hierophant', nameCn: '教皇', arcana: 'major',
      icon: Icons.church,
      uprightMeaning: '传统、信仰、教育、精神指导',
      reversedMeaning: '教条主义、叛逆、打破常规',
    ),
    TarotCard(
      id: 6, name: 'The Lovers', nameCn: '恋人', arcana: 'major',
      icon: Icons.favorite,
      uprightMeaning: '爱情、和谐、关系、选择',
      reversedMeaning: '失衡、分离、价值观冲突、不忠',
    ),
    TarotCard(
      id: 7, name: 'The Chariot', nameCn: '战车', arcana: 'major',
      icon: Icons.directions_car,
      uprightMeaning: '胜利、意志力、决心、前进',
      reversedMeaning: '失控、方向不明、挫败、缺乏自制',
    ),
    TarotCard(
      id: 8, name: 'Strength', nameCn: '力量', arcana: 'major',
      icon: Icons.fitness_center,
      uprightMeaning: '勇气、内在力量、耐心、温柔的力量',
      reversedMeaning: '自我怀疑、软弱、缺乏自信',
    ),
    TarotCard(
      id: 9, name: 'The Hermit', nameCn: '隐者', arcana: 'major',
      icon: Icons.hiking,
      uprightMeaning: '内省、孤独、寻求真理、智慧',
      reversedMeaning: '孤立、逃避、固步自封',
    ),
    TarotCard(
      id: 10, name: 'Wheel of Fortune', nameCn: '命运之轮', arcana: 'major',
      icon: Icons.autorenew,
      uprightMeaning: '转折、命运、好运、循环',
      reversedMeaning: '坏运、抗拒改变、失控',
    ),
    TarotCard(
      id: 11, name: 'Justice', nameCn: '正义', arcana: 'major',
      icon: Icons.balance,
      uprightMeaning: '公正、真理、因果、法律',
      reversedMeaning: '不公正、欺骗、逃避责任',
    ),
    TarotCard(
      id: 12, name: 'The Hanged Man', nameCn: '倒吊人', arcana: 'major',
      icon: Icons.accessibility_new,
      uprightMeaning: '牺牲、放下、新视角、等待',
      reversedMeaning: '拖延、抗拒、无谓的牺牲',
    ),
    TarotCard(
      id: 13, name: 'Death', nameCn: '死神', arcana: 'major',
      icon: Icons.change_circle,
      uprightMeaning: '结束、转变、新生、放下过去',
      reversedMeaning: '抗拒改变、停滞、恐惧转变',
    ),
    TarotCard(
      id: 14, name: 'Temperance', nameCn: '节制', arcana: 'major',
      icon: Icons.water_drop,
      uprightMeaning: '平衡、耐心、节制、和谐',
      reversedMeaning: '失衡、过度、缺乏耐心',
    ),
    TarotCard(
      id: 15, name: 'The Devil', nameCn: '恶魔', arcana: 'major',
      icon: Icons.whatshot,
      uprightMeaning: '束缚、欲望、物质主义、阴暗面',
      reversedMeaning: '解脱、释放、打破束缚',
    ),
    TarotCard(
      id: 16, name: 'The Tower', nameCn: '塔', arcana: 'major',
      icon: Icons.bolt,
      uprightMeaning: '突变、破坏、真相揭露、觉醒',
      reversedMeaning: '避免灾难、延迟转变、恐惧改变',
    ),
    TarotCard(
      id: 17, name: 'The Star', nameCn: '星星', arcana: 'major',
      icon: Icons.star,
      uprightMeaning: '希望、灵感、宁静、更新',
      reversedMeaning: '绝望、失去信心、不切实际',
    ),
    TarotCard(
      id: 18, name: 'The Moon', nameCn: '月亮', arcana: 'major',
      icon: Icons.dark_mode,
      uprightMeaning: '幻觉、直觉、潜意识、迷惑',
      reversedMeaning: '恐惧消退、真相显露、清醒',
    ),
    TarotCard(
      id: 19, name: 'The Sun', nameCn: '太阳', arcana: 'major',
      icon: Icons.wb_sunny,
      uprightMeaning: '快乐、成功、活力、光明',
      reversedMeaning: '暂时的挫折、过度乐观',
    ),
    TarotCard(
      id: 20, name: 'Judgement', nameCn: '审判', arcana: 'major',
      icon: Icons.gavel,
      uprightMeaning: '觉醒、重生、反思、召唤',
      reversedMeaning: '自我怀疑、拒绝反思、逃避判断',
    ),
    TarotCard(
      id: 21, name: 'The World', nameCn: '世界', arcana: 'major',
      icon: Icons.public,
      uprightMeaning: '完成、圆满、成就、新旅程',
      reversedMeaning: '未完成、缺乏终结、延迟成功',
    ),
  ];

  static const List<TarotCard> minorArcana = [
    // ─── 权杖 Wands ───
    TarotCard(id: 22, name: 'Ace of Wands', nameCn: '权杖王牌', arcana: 'minor', suit: 'wands', icon: Icons.auto_fix_high, uprightMeaning: '新灵感、创造力、力量', reversedMeaning: '延迟、缺乏方向'),
    TarotCard(id: 23, name: 'Two of Wands', nameCn: '权杖二', arcana: 'minor', suit: 'wands', icon: Icons.public, uprightMeaning: '规划、决策、未来展望', reversedMeaning: '缺乏规划、恐惧'),
    TarotCard(id: 24, name: 'Three of Wands', nameCn: '权杖三', arcana: 'minor', suit: 'wands', icon: Icons.sailing, uprightMeaning: '拓展、远见、机会', reversedMeaning: '延迟、挫折'),
    TarotCard(id: 25, name: 'Four of Wands', nameCn: '权杖四', arcana: 'minor', suit: 'wands', icon: Icons.home, uprightMeaning: '庆祝、和谐、家庭', reversedMeaning: '不安定、缺乏支持'),
    TarotCard(id: 26, name: 'Five of Wands', nameCn: '权杖五', arcana: 'minor', suit: 'wands', icon: Icons.flash_on, uprightMeaning: '竞争、冲突、挑战', reversedMeaning: '避免冲突、妥协'),
    TarotCard(id: 27, name: 'Six of Wands', nameCn: '权杖六', arcana: 'minor', suit: 'wands', icon: Icons.emoji_events, uprightMeaning: '胜利、认可、自信', reversedMeaning: '失败、缺乏认可'),
    TarotCard(id: 28, name: 'Seven of Wands', nameCn: '权杖七', arcana: 'minor', suit: 'wands', icon: Icons.shield, uprightMeaning: '坚持、防御、勇气', reversedMeaning: '放弃、无力感'),
    TarotCard(id: 29, name: 'Eight of Wands', nameCn: '权杖八', arcana: 'minor', suit: 'wands', icon: Icons.speed, uprightMeaning: '迅速、行动、消息', reversedMeaning: '延迟、混乱'),
    TarotCard(id: 30, name: 'Nine of Wands', nameCn: '权杖九', arcana: 'minor', suit: 'wands', icon: Icons.fence, uprightMeaning: '韧性、坚持、毅力', reversedMeaning: '疲惫、固执'),
    TarotCard(id: 31, name: 'Ten of Wands', nameCn: '权杖十', arcana: 'minor', suit: 'wands', icon: Icons.inventory_2, uprightMeaning: '负担、责任、压力', reversedMeaning: '放下、委派'),
    TarotCard(id: 32, name: 'Page of Wands', nameCn: '权杖侍从', arcana: 'minor', suit: 'wands', icon: Icons.person, uprightMeaning: '探索、热情、新消息', reversedMeaning: '幼稚、延迟'),
    TarotCard(id: 33, name: 'Knight of Wands', nameCn: '权杖骑士', arcana: 'minor', suit: 'wands', icon: Icons.directions_run, uprightMeaning: '冒险、行动、激情', reversedMeaning: '冲动、急躁'),
    TarotCard(id: 34, name: 'Queen of Wands', nameCn: '权杖王后', arcana: 'minor', suit: 'wands', icon: Icons.person_2, uprightMeaning: '自信、温暖、独立', reversedMeaning: '嫉妒、控制'),
    TarotCard(id: 35, name: 'King of Wands', nameCn: '权杖国王', arcana: 'minor', suit: 'wands', icon: Icons.person_4, uprightMeaning: '领导、远见、魅力', reversedMeaning: '专制、急躁'),

    // ─── 圣杯 Cups ───
    TarotCard(id: 36, name: 'Ace of Cups', nameCn: '圣杯王牌', arcana: 'minor', suit: 'cups', icon: Icons.local_drink, uprightMeaning: '新感情、直觉、灵感', reversedMeaning: '情感封闭、空虚'),
    TarotCard(id: 37, name: 'Two of Cups', nameCn: '圣杯二', arcana: 'minor', suit: 'cups', icon: Icons.people, uprightMeaning: '结合、合作、吸引', reversedMeaning: '分离、失衡'),
    TarotCard(id: 38, name: 'Three of Cups', nameCn: '圣杯三', arcana: 'minor', suit: 'cups', icon: Icons.celebration, uprightMeaning: '庆祝、友谊、社交', reversedMeaning: '过度、孤立'),
    TarotCard(id: 39, name: 'Four of Cups', nameCn: '圣杯四', arcana: 'minor', suit: 'cups', icon: Icons.sentiment_neutral, uprightMeaning: '冥想、不满、内省', reversedMeaning: '新机会、觉醒'),
    TarotCard(id: 40, name: 'Five of Cups', nameCn: '圣杯五', arcana: 'minor', suit: 'cups', icon: Icons.sentiment_dissatisfied, uprightMeaning: '失落、悲伤、后悔', reversedMeaning: '接受、前进'),
    TarotCard(id: 41, name: 'Six of Cups', nameCn: '圣杯六', arcana: 'minor', suit: 'cups', icon: Icons.child_care, uprightMeaning: '怀旧、纯真、回忆', reversedMeaning: '沉溺过去、不切实际'),
    TarotCard(id: 42, name: 'Seven of Cups', nameCn: '圣杯七', arcana: 'minor', suit: 'cups', icon: Icons.cloud, uprightMeaning: '幻想、选择、想象力', reversedMeaning: '清醒、集中注意力'),
    TarotCard(id: 43, name: 'Eight of Cups', nameCn: '圣杯八', arcana: 'minor', suit: 'cups', icon: Icons.directions_walk, uprightMeaning: '离开、寻找、放弃', reversedMeaning: '徘徊、恐惧改变'),
    TarotCard(id: 44, name: 'Nine of Cups', nameCn: '圣杯九', arcana: 'minor', suit: 'cups', icon: Icons.sentiment_very_satisfied, uprightMeaning: '满足、愿望成真、幸福', reversedMeaning: '贪婪、不满'),
    TarotCard(id: 45, name: 'Ten of Cups', nameCn: '圣杯十', arcana: 'minor', suit: 'cups', icon: Icons.wb_sunny, uprightMeaning: '和谐、幸福、家庭美满', reversedMeaning: '家庭问题、失和'),
    TarotCard(id: 46, name: 'Page of Cups', nameCn: '圣杯侍从', arcana: 'minor', suit: 'cups', icon: Icons.child_care, uprightMeaning: '创意、直觉、好消息', reversedMeaning: '情感不成熟'),
    TarotCard(id: 47, name: 'Knight of Cups', nameCn: '圣杯骑士', arcana: 'minor', suit: 'cups', icon: Icons.local_florist, uprightMeaning: '浪漫、魅力、理想主义', reversedMeaning: '不切实际、情绪化'),
    TarotCard(id: 48, name: 'Queen of Cups', nameCn: '圣杯王后', arcana: 'minor', suit: 'cups', icon: Icons.person_2, uprightMeaning: '同情心、直觉、温柔', reversedMeaning: '情绪不稳定、依赖'),
    TarotCard(id: 49, name: 'King of Cups', nameCn: '圣杯国王', arcana: 'minor', suit: 'cups', icon: Icons.person_4, uprightMeaning: '情感平衡、智慧、外交', reversedMeaning: '情绪压抑、操控'),

    // ─── 宝剑 Swords ───
    TarotCard(id: 50, name: 'Ace of Swords', nameCn: '宝剑王牌', arcana: 'minor', suit: 'swords', icon: Icons.gavel, uprightMeaning: '真相、清晰、突破', reversedMeaning: '混乱、误解'),
    TarotCard(id: 51, name: 'Two of Swords', nameCn: '宝剑二', arcana: 'minor', suit: 'swords', icon: Icons.do_not_disturb, uprightMeaning: '僵局、选择、犹豫', reversedMeaning: '信息过载、偏见'),
    TarotCard(id: 52, name: 'Three of Swords', nameCn: '宝剑三', arcana: 'minor', suit: 'swords', icon: Icons.heart_broken, uprightMeaning: '心碎、悲伤、分离', reversedMeaning: '释放、原谅'),
    TarotCard(id: 53, name: 'Four of Swords', nameCn: '宝剑四', arcana: 'minor', suit: 'swords', icon: Icons.hotel, uprightMeaning: '休息、恢复、冥想', reversedMeaning: '疲惫、焦虑'),
    TarotCard(id: 54, name: 'Five of Swords', nameCn: '宝剑五', arcana: 'minor', suit: 'swords', icon: Icons.sentiment_very_dissatisfied, uprightMeaning: '冲突、失败、屈辱', reversedMeaning: '和解、放下'),
    TarotCard(id: 55, name: 'Six of Swords', nameCn: '宝剑六', arcana: 'minor', suit: 'swords', icon: Icons.directions_boat, uprightMeaning: '离开、过渡、平静', reversedMeaning: '无法逃避、停滞'),
    TarotCard(id: 56, name: 'Seven of Swords', nameCn: '宝剑七', arcana: 'minor', suit: 'swords', icon: Icons.visibility_off, uprightMeaning: '策略、机智、欺骗', reversedMeaning: '坦诚、面对后果'),
    TarotCard(id: 57, name: 'Eight of Swords', nameCn: '宝剑八', arcana: 'minor', suit: 'swords', icon: Icons.link, uprightMeaning: '束缚、限制、无力', reversedMeaning: '自由、新视角'),
    TarotCard(id: 58, name: 'Nine of Swords', nameCn: '宝剑九', arcana: 'minor', suit: 'swords', icon: Icons.nightlight_round, uprightMeaning: '焦虑、恐惧、噩梦', reversedMeaning: '希望、最坏已过'),
    TarotCard(id: 59, name: 'Ten of Swords', nameCn: '宝剑十', arcana: 'minor', suit: 'swords', icon: Icons.warning, uprightMeaning: '结束、背叛、痛苦', reversedMeaning: '恢复、新生'),
    TarotCard(id: 60, name: 'Page of Swords', nameCn: '宝剑侍从', arcana: 'minor', suit: 'swords', icon: Icons.person, uprightMeaning: '好奇、机智、新想法', reversedMeaning: '八卦、缺乏经验'),
    TarotCard(id: 61, name: 'Knight of Swords', nameCn: '宝剑骑士', arcana: 'minor', suit: 'swords', icon: Icons.directions_run, uprightMeaning: '果断、行动、勇敢', reversedMeaning: '冲动、鲁莽'),
    TarotCard(id: 62, name: 'Queen of Swords', nameCn: '宝剑王后', arcana: 'minor', suit: 'swords', icon: Icons.person_2, uprightMeaning: '独立、智慧、公正', reversedMeaning: '冷酷、偏见'),
    TarotCard(id: 63, name: 'King of Swords', nameCn: '宝剑国王', arcana: 'minor', suit: 'swords', icon: Icons.person_4, uprightMeaning: '权威、理性、公正', reversedMeaning: '独裁、冷血'),

    // ─── 金币 Pentacles ───
    TarotCard(id: 64, name: 'Ace of Pentacles', nameCn: '金币王牌', arcana: 'minor', suit: 'pentacles', icon: Icons.monetization_on, uprightMeaning: '新机会、财富、稳定', reversedMeaning: '错失机会、财务问题'),
    TarotCard(id: 65, name: 'Two of Pentacles', nameCn: '金币二', arcana: 'minor', suit: 'pentacles', icon: Icons.balance, uprightMeaning: '平衡、适应、灵活', reversedMeaning: '过度承担、失衡'),
    TarotCard(id: 66, name: 'Three of Pentacles', nameCn: '金币三', arcana: 'minor', suit: 'pentacles', icon: Icons.construction, uprightMeaning: '合作、技能、团队', reversedMeaning: '缺乏合作、平庸'),
    TarotCard(id: 67, name: 'Four of Pentacles', nameCn: '金币四', arcana: 'minor', suit: 'pentacles', icon: Icons.savings, uprightMeaning: '储蓄、安全、保守', reversedMeaning: '贪婪、吝啬'),
    TarotCard(id: 68, name: 'Five of Pentacles', nameCn: '金币五', arcana: 'minor', suit: 'pentacles', icon: Icons.ac_unit, uprightMeaning: '困难、贫穷、孤立', reversedMeaning: '恢复、援助到来'),
    TarotCard(id: 69, name: 'Six of Pentacles', nameCn: '金币六', arcana: 'minor', suit: 'pentacles', icon: Icons.volunteer_activism, uprightMeaning: '慷慨、给予、平衡', reversedMeaning: '不公平、债务'),
    TarotCard(id: 70, name: 'Seven of Pentacles', nameCn: '金币七', arcana: 'minor', suit: 'pentacles', icon: Icons.grass, uprightMeaning: '耐心、等待收获、投资', reversedMeaning: '缺乏耐心、急于求成'),
    TarotCard(id: 71, name: 'Eight of Pentacles', nameCn: '金币八', arcana: 'minor', suit: 'pentacles', icon: Icons.build, uprightMeaning: '勤奋、专注、技能提升', reversedMeaning: '缺乏野心、重复'),
    TarotCard(id: 72, name: 'Nine of Pentacles', nameCn: '金币九', arcana: 'minor', suit: 'pentacles', icon: Icons.wine_bar, uprightMeaning: '独立、富足、享受', reversedMeaning: '过度依赖、孤独'),
    TarotCard(id: 73, name: 'Ten of Pentacles', nameCn: '金币十', arcana: 'minor', suit: 'pentacles', icon: Icons.home_work, uprightMeaning: '财富、传承、家族', reversedMeaning: '家庭纷争、财务不稳'),
    TarotCard(id: 74, name: 'Page of Pentacles', nameCn: '金币侍从', arcana: 'minor', suit: 'pentacles', icon: Icons.person, uprightMeaning: '学习、新机会、勤奋', reversedMeaning: '缺乏目标、懒惰'),
    TarotCard(id: 75, name: 'Knight of Pentacles', nameCn: '金币骑士', arcana: 'minor', suit: 'pentacles', icon: Icons.directions_run, uprightMeaning: '可靠、勤奋、稳定', reversedMeaning: '停滞、缺乏动力'),
    TarotCard(id: 76, name: 'Queen of Pentacles', nameCn: '金币王后', arcana: 'minor', suit: 'pentacles', icon: Icons.person_2, uprightMeaning: '富足、实际、关怀', reversedMeaning: '物质主义、忽视自我'),
    TarotCard(id: 77, name: 'King of Pentacles', nameCn: '金币国王', arcana: 'minor', suit: 'pentacles', icon: Icons.person_4, uprightMeaning: '成功、富裕、稳定', reversedMeaning: '贪婪、固执'),
  ];

  /// 完整78张牌
  static List<TarotCard> get fullDeck => [...majorArcana, ...minorArcana];

  /// 随机抽取n张不重复的牌
  static List<TarotCard> drawRandom(int count) {
    final deck = List<TarotCard>.from(fullDeck);
    deck.shuffle();
    return deck.take(count).toList();
  }

  /// 获取花色中文名
  static String suitName(String? suit) {
    switch (suit) {
      case 'wands': return '权杖';
      case 'cups': return '圣杯';
      case 'swords': return '宝剑';
      case 'pentacles': return '金币';
      default: return '大阿卡纳';
    }
  }
}
