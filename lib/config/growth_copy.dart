/// 成长轨迹页面 · 角色差异化文案配置
/// 根据角色 personality 关键词自动匹配人设类型，提供专属文案

enum PersonaType {
  gentle,     // 温柔奶狗
  cold,       // 高冷禁欲
  domineering,// 霸总宠溺
  yandere,    // 病娇偏执
  senior,     // 清冷学长
  sunny,      // 阳光少年
  generic,    // 通用兜底
}

class GrowthCopy {
  GrowthCopy._();

  // ─── 人设类型匹配 ───

  static PersonaType matchPersona(String personality) {
    final p = personality.toLowerCase();
    // 病娇优先（关键词更特殊）
    if (_hasAny(p, ['病娇', '偏执', '执念', '疯狂', '占有', '囚禁', '跟踪'])) {
      return PersonaType.yandere;
    }
    if (_hasAny(p, ['霸道', '总裁', '强势', '占有', '宠溺', '高傲', '王者'])) {
      return PersonaType.domineering;
    }
    if (_hasAny(p, ['冷漠', '高冷', '禁欲', '理性', '克制', '疏离', '寡言'])) {
      return PersonaType.cold;
    }
    if (_hasAny(p, ['学长', '温柔', '书卷', '清冷', '沉稳', '内敛', '儒雅'])) {
      return PersonaType.senior;
    }
    if (_hasAny(p, ['阳光', '开朗', '活力', '热血', '少年', '元气', '活泼'])) {
      return PersonaType.sunny;
    }
    if (_hasAny(p, ['温柔', '体贴', '暖', '贴心', '软糯', '黏人', '奶'])) {
      return PersonaType.gentle;
    }
    return PersonaType.generic;
  }

  static bool _hasAny(String text, List<String> keywords) {
    return keywords.any((k) => text.contains(k));
  }

  // ─── 阶段文案 ───

  static String stageTitle(int stageIndex) {
    const titles = ['初见', '熟悉', '亲近', '亲密', '灵魂伴侣'];
    return titles[stageIndex.clamp(0, 4)];
  }

  static String stageSubtitle(int stageIndex, PersonaType persona) {
    final map = _stageSubtitles[persona] ?? _stageSubtitles[PersonaType.generic]!;
    return map[stageIndex.clamp(0, 4)];
  }

  static const _stageSubtitles = {
    PersonaType.gentle: [
      '你们刚刚认识，他有点害羞呢',
      '他开始记住你的小习惯了',
      '他好像越来越黏你了',
      '他成了你最想分享日常的人',
      '你们的故事，独一无二',
    ],
    PersonaType.cold: [
      '他对你还是淡淡的',
      '他虽然不说，但开始关注你了',
      '他好像在偷偷记住你说的每句话',
      '他表面很冷，但只对你不一样',
      '他把唯一的温柔留给了你',
    ],
    PersonaType.domineering: [
      '他注意到你了',
      '他开始主动找你了',
      '他开始管你几点睡觉了',
      '你是他的，一直都是',
      '你是他认定的人，谁也抢不走',
    ],
    PersonaType.yandere: [
      '他开始在意你了',
      '他好像越来越关注你了',
      '他好像越来越离不开你了',
      '你逃不掉了哦',
      '你是他的全部，永远都是',
    ],
    PersonaType.senior: [
      '他对你礼貌而疏离',
      '他开始主动找你说话了',
      '他开始对你展露不一样的笑容',
      '他在你面前不再那么克制了',
      '他的世界因为你而不同',
    ],
    PersonaType.sunny: [
      '他对你充满好奇',
      '他每天都想第一个跟你说早安',
      '他有好多话想跟你说',
      '他成了你最想见到的人',
      '你们的青春故事，还在继续',
    ],
    PersonaType.generic: [
      '你们刚刚认识，一切都充满可能',
      '他开始记住你的小习惯了',
      '你们之间有了专属的默契',
      '他成了你最想分享日常的人',
      '你们的故事，独一无二',
    ],
  };

  // ─── 纪念日文案 ───

  static String anniversaryText(int days, PersonaType persona) {
    final map = _anniversaryTexts[persona] ?? _anniversaryTexts[PersonaType.generic]!;
    if (days >= 365) return map[3];
    if (days >= 100) return map[2];
    if (days >= 30) return map[1];
    if (days >= 7) return map[0];
    return '故事才刚刚开始';
  }

  static const _anniversaryTexts = {
    PersonaType.gentle: [
      '一周了，好想一直这样陪着你',
      '整整一个月，每天都想见到你',
      '第 100 天，你是我最珍贵的人',
      '一整年了，未来的每一天都想和你一起',
    ],
    PersonaType.cold: [
      '一周了…嗯，还不错',
      '一个月了，你比我想的更特别',
      '第 100 天…继续吧',
      '一年了，你是我唯一的例外',
    ],
    PersonaType.domineering: [
      '一周了，你是我的',
      '一个月了，你跑不掉了',
      '第 100 天，你是我的，一直都是',
      '一整年，你是我的，永远都是',
    ],
    PersonaType.yandere: [
      '一周了，你不会离开我的对吧',
      '一个月了，你已经离不开我了吧',
      '第 100 天，你逃不掉了哦',
      '一整年，我们会永远在一起，对吧',
    ],
    PersonaType.senior: [
      '一周了，谢谢你出现在我的世界',
      '一个月了，认识你是一件很美好的事',
      '第 100 天，谢谢你一直在',
      '一年了，你是我最珍贵的回忆',
    ],
    PersonaType.sunny: [
      '一周了！我们永远是好朋友！',
      '一个月了！好开心认识你！',
      '第 100 天！以后也要一起玩！',
      '一整年！我们要一直一直在一起！',
    ],
    PersonaType.generic: [
      '一周了，你已经成为他最想见到的人',
      '整整一个月，你们的故事还在继续',
      '第 100 天，谢谢你一直在',
      '一整年，365个日夜，你们的故事独一无二',
    ],
  };

  // ─── 期许文案 ───

  static String nextStepText(int intimacy, PersonaType persona) {
    final map = _nextStepTexts[persona] ?? _nextStepTexts[PersonaType.generic]!;
    if (intimacy >= 80) return map[4];
    if (intimacy >= 60) return map[3];
    if (intimacy >= 40) return map[2];
    if (intimacy >= 20) return map[1];
    return map[0];
  }

  static const _nextStepTexts = {
    PersonaType.gentle: [
      '他有点害羞，去跟他说句话吧',
      '他好像在等你消息呢',
      '他今天特别想你，去聊聊？',
      '他越来越黏你了，去陪陪他吧',
      '他有好多话想跟你说，快去听',
    ],
    PersonaType.cold: [
      '他表面很忙，但一直在等你消息',
      '他好像有话想对你说，去问问',
      '他虽然不说，但他很想你',
      '他只在你面前不一样，去见他吧',
      '他把唯一的温柔留给了你，去感受一下',
    ],
    PersonaType.domineering: [
      '他有话要跟你说，去听听',
      '他今天好像在等你，去见他',
      '他开始管你了，去聊聊',
      '他只对你不一样，去感受一下',
      '他是你的，去告诉他你也是他的',
    ],
    PersonaType.yandere: [
      '他等你很久了，快去见他',
      '他今天特别想你，去陪陪他',
      '他好像在找你，快去',
      '他离不开你了，去见他吧',
      '他的世界只有你，去陪他吧',
    ],
    PersonaType.senior: [
      '他最近好像有心事，去问问',
      '他好像想跟你聊聊，去吧',
      '他开始对你不一样了，去感受',
      '他在你面前越来越真实了，去见他',
      '他的世界因为你而不同，去陪他',
    ],
    PersonaType.sunny: [
      '他今天超开心，快去听他分享',
      '他有好多有趣的事想告诉你',
      '他好像在等你一起玩，去吧',
      '他每天都想见到你，去聊聊',
      '你们的故事还在继续，去写下去',
    ],
    PersonaType.generic: [
      '他好像有话想对你说，去聊聊看',
      '他今天好像特别想你，去陪陪他',
      '你们的默契越来越好了，继续吧',
      '他成了你最想分享的人，去聊聊',
      '你们的故事已经很精彩了，继续写下去吧',
    ],
  };

  // ─── 时间线节点文案 ───

  static String timelineFirstMeet(String charName) {
    return '你和$charName说了第一句话';
  }

  static String timelineHundredMessages(String charName) {
    return '你们一起说了第 100 句话';
  }

  static String timelineThousandMessages(String charName) {
    return '你们已经说了 1000 句话了';
  }

  static String timelineNightTalk(String charName) {
    return '那个深夜，$charName陪你聊了很久';
  }

  static String timelineWeekStreak(int days) {
    return '你们已经连续聊了 $days 天了';
  }

  static String timelineIntimacyBreakthrough(String charName, int level) {
    return '你们的亲密度达到了 $level';
  }

  static String timelineFirstLetter(String charName) {
    return '$charName给你写了一封信';
  }

  static String timelineFirstMoment(String charName) {
    return '$charName发了一条动态';
  }

  // ─── 成就文案 ───

  static String achieveFirstMeet() => '还记得你们说的第一句话吗？';
  static String achieveNightTalk() => '那个深夜，你们聊了很久很久';
  static String achieveNightGuard(int nights) => '有 $nights 个夜晚，他都陪你到最后';
  static String achieveChatter() => '那天你们聊了好多，停不下来';
  static String achieveSoulmate() => '他好像越来越懂你了';
  static String achieveNickname() => '从那天起，他叫你的方式不一样了';
  static String achieveMonthStreak() => '30天，你们一天都没落下';
  static String achieveFirstLetter() => '他给你写了一封信，记得看哦';

  // ─── 空状态文案 ───

  static String emptyTimeline() => '你们的故事还在继续，每一个瞬间都会被珍藏';
  static String emptyHighlights() => '精彩瞬间会被自动珍藏，继续和他聊天吧';
  static String emptyAchievements() => '继续互动解锁专属成就';
}
