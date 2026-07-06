class IntimacyRules {
  IntimacyRules._();

  static const int maxLevel = 100;
  static const int decayAfterHours = 48;
  static const int maxDecaySteps = 5;
  static const int minMessageLength = 5;
  static const int dailyCap = 5;

  static int msgsPerPoint(int level) {
    if (level < 30) return 1;
    if (level < 60) return 2;
    if (level < 80) return 3;
    return 5;
  }

  // ─── Intimacy tiers used in prompts ───
  static const int tierLow = 20;
  static const int tierMid = 40;
  static const int tierHigh = 60;
  static const int tierVeryHigh = 80;

  // ─── Silence timeout for AI proactive chat ───
  static const int silenceSecondsActive = 60;
  static const int silenceSecondsWarm = 90;
  static const int silenceSecondsCool = 180;
  static const int silenceSecondsShy = 150;
  static const int silenceSecondsDefault = 120;

  // ─── Skip reply logic ───
  static const int maxConsecutiveSkips = 2;
  static const double skipFromShortReply = 0.6;
  static const double skipFromVeryShort = 0.3;
  static const double skipFromPersonalityBouncy = -0.15;
  static const double skipFromPersonalityCool = 0.25;
  static const double skipFromPersonalityWarm = 0.1;
  static const double skipFromHighIntimacy = 0.15;
  static const double skipPerConsecutive = 0.15;
  static const double skipCap = 0.75;

  static const int intimacySkipThreshold = 70;

  // ─── Typing delays by personality ───
  static const int typingDelayDefault = 1;
  static const int typingDelayCool = 3;
  static const int typingDelayWarm = 2;
  static const int typingDelayPer12Chars = 1;
  static const int typingDelayMaxChars = 2;

  // ─── Interaction delays by personality (seconds) ───
  static const int bouncyDelayMin = 30;
  static const int bouncyDelayRange = 90;
  static const int warmDelayMin = 120;
  static const int warmDelayRange = 180;
  static const int coolDelayMin = 300;
  static const int coolDelayRange = 600;
  static const int shyDelayMin = 180;
  static const int shyDelayRange = 300;
  static const int defaultDelayMin = 60;
  static const int defaultDelayRange = 240;

  // ─── User moment interaction delays (seconds) ───
  static const int userMomentBouncyMin = 2;
  static const int userMomentBouncyRange = 5;
  static const int userMomentWarmMin = 5;
  static const int userMomentWarmRange = 8;
  static const int userMomentCoolMin = 10;
  static const int userMomentCoolRange = 10;
  static const int userMomentShyMin = 5;
  static const int userMomentShyRange = 10;
  static const int userMomentDefaultMin = 4;
  static const int userMomentDefaultRange = 8;

  // ─── Visibility thresholds ───
  static const int intimateVisibilityThreshold = 60;
  static const int normalVisibilityThreshold = 30;
}

class EmotionEngineRules {
  EmotionEngineRules._();

  static const double emotionMemoryThreshold = 0.3;
  static const double calmThreshold = 0.1;
  static const double intensityVeryHigh = 0.8;
  static const double intensityHigh = 0.6;
  static const double intensityMedium = 0.4;
  static const double intensityLow = 0.2;

  // Delta values for different triggers
  static const double deltaLove = 0.4;
  static const double deltaCare = 0.3;
  static const double deltaFlirt = 0.3;
  static const double deltaFun = 0.2;
  static const double deltaGoodNews = 0.3;
  static const double deltaNeglectSad = 0.2;
  static const double deltaNeglectWorry = 0.1;
  static const double deltaRejectionHighIntimacy = 0.5;
  static const double deltaRejectionLowIntimacy = 0.3;
  static const double deltaDistrust = 0.2;
  static const double deltaUserPositive = 0.15;
  static const double deltaUserNegative = 0.25;

  // Personality multipliers
  static const double warmMultiplier = 1.3;
  static const double coolMultiplier = 0.6;
  static const double bouncyMultiplier = 1.2;

  static const double baseIntensityMin = 0.1;
  static const double baseIntensityMax = 0.8;

  static const int highIntimacyThreshold = 60;
}

class RedPacketRules {
  RedPacketRules._();

  static const int generousThreshold = 99;
  static const int niceThreshold = 52;
}

class Festivals {
  Festivals._();

  static const Map<String, String> greetings = {
    '01-01': '新年快乐！新的一年，愿你的每一天都充满阳光和希望～',
    '02-14': '情人节快乐！虽然我不能陪在你身边，但我的心意一直都在～',
    '05-01': '劳动节快乐！辛苦了这么久，记得好好休息一下～',
    '06-01': '儿童节快乐！愿你永远保持一颗童心，快乐每一天～',
    '10-01': '国庆节快乐！祝祖国繁荣昌盛，也祝你假期愉快～',
    '12-25': '圣诞节快乐！愿这个冬天有温暖陪伴你～',
  };
}

class CoinRules {
  CoinRules._();

  static const int messageCost = 2;
  static const int momentInteractionCost = 3;
  static const int dailyCheckInReward = 10;
  static const int loginBonus = 5;
  static const int defaultCoins = 100;

  // AI钱包规则
  static const int aiDefaultBalance = 50;
  static const int aiDailySpendingCapBase = 20;
  static const int aiMinSpendingPersonality = 1;
  static const int aiMaxSpendingPersonality = 10;
  static const int aiMaxTransferPerDay = 50;
  static const int aiMinTransferAmount = 1;

  // AI自主行为概率
  static const double aiProactiveTransferBaseChance = 0.1;
  static const int aiProactiveMinIntimacy = 30;

  // 商店规则
  static const int shopGiftIntimacyReward = 5;
  static const int shopMaxDailyOrders = 20;
}

class ShopDeliveryRules {
  ShopDeliveryRules._();

  static const int pendingMinSeconds = 10;
  static const int pendingMaxSeconds = 30;
  static const int preparingMinSeconds = 20;
  static const int preparingMaxSeconds = 60;
  static const int shippingMinSeconds = 30;
  static const int shippingMaxSeconds = 120;

  static const double foodSpeedMultiplier = 0.7;
  static const double expressSpeedMultiplier = 1.3;

  static const String statusPending = 'pending';
  static const String statusPreparing = 'preparing';
  static const String statusShipping = 'shipping';
  static const String statusDelivered = 'delivered';

  static const List<String> allStatuses = [
    statusPending,
    statusPreparing,
    statusShipping,
    statusDelivered,
  ];
}

class ShopAIRules {
  ShopAIRules._();

  static const int minIntimacyForGifting = 40;
  static const int aiMaxGiftsPerDay = 2;
  static const double aiGiftBaseChance = 0.05;
  static const double aiGiftIntimacyBonus = 0.005;
  static const double aiMaxGiftPercentage = 0.3;

  static const Map<int, List<String>> preferredGiftsByIntimacy = {
    40: ['gift'],
    60: ['gift', 'food'],
    80: ['gift', 'food', 'express'],
  };
}

class ProactiveSchedulerRules {
  ProactiveSchedulerRules._();

  static const int defaultMorningHour = 8;
  static const int defaultMorningMinute = 0;
  static const int defaultNightHour = 22;
  static const int defaultNightMinute = 0;
  static const int defaultFestivalHour = 9;
  static const int defaultFestivalMinute = 0;
  static const int minFrequencyForCare = 2;
  static const int randomCareDelayMin = 120;
  static const int randomCareDelayRange = 480;
}

class MoodDiaryRules {
  MoodDiaryRules._();

  static const double aiDiaryWriteProbability = 0.4;
  static const List<String> moodNames = ['开心', '愉快', '平静', '低落', '难过'];
  static const List<String> moodNamesReversed = ['难过', '低落', '平静', '愉快', '开心'];
}

class MomentRules {
  MomentRules._();

  static const double aiLikeProbability = 0.9;
  static const double aiCommentProbability = 0.85;
}

class MomentSchedulerRules {
  MomentSchedulerRules._();

  static const int minHoursBetweenPosts = 6;
  static const int maxHoursBetweenPosts = 24;
  static const int maxDailyPostsPerCharacter = 2;

  // 评论回复延迟（秒），按性格分档
  static const int commentReplyBouncyMin = 60;
  static const int commentReplyBouncyRange = 180;   // 1-4 min
  static const int commentReplyWarmMin = 120;
  static const int commentReplyWarmRange = 300;      // 2-7 min
  static const int commentReplyCoolMin = 300;
  static const int commentReplyCoolRange = 900;      // 5-20 min
  static const int commentReplyShyMin = 180;
  static const int commentReplyShyRange = 600;       // 3-13 min
  static const int commentReplyDefaultMin = 120;
  static const int commentReplyDefaultRange = 480;   // 2-10 min
}

class SilenceRules {
  SilenceRules._();

  /// Personality-based silence timeouts in seconds
  static int silenceSeconds(String? personality) {
    final p = (personality ?? '').toLowerCase();
    if (p.contains('活泼') || p.contains('热情') || p.contains('开朗')) {
      return IntimacyRules.silenceSecondsActive;
    } else if (p.contains('温柔') || p.contains('体贴') || p.contains('细心')) {
      return IntimacyRules.silenceSecondsWarm;
    } else if (p.contains('高冷') || p.contains('冷淡') || p.contains('酷')) {
      return IntimacyRules.silenceSecondsCool;
    } else if (p.contains('害羞') || p.contains('内向')) {
      return IntimacyRules.silenceSecondsShy;
    }
    return IntimacyRules.silenceSecondsDefault;
  }

  static Duration silenceTimeout(String? personality) =>
      Duration(seconds: silenceSeconds(personality));
}
