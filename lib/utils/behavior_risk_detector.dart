class BehaviorRiskResult {
  final bool shouldWarn;
  final bool shouldLockEmotion;
  final String? warningMessage;
  final RiskLevel level;

  const BehaviorRiskResult({
    this.shouldWarn = false,
    this.shouldLockEmotion = false,
    this.warningMessage,
    this.level = RiskLevel.none,
  });
}

enum RiskLevel { none, low, medium, high }

class BehaviorRiskDetector {
  BehaviorRiskDetector._();

  static final List<RegExp> _extremeEmotionPatterns = [
    RegExp(r'想死|不想活|自杀|自残|割腕|跳楼|安眠药|吊死|溺死|烧炭'),
    RegExp(r'活着没意思|没有希望|绝望|痛苦得想死|不想活了|结束生命'),
    RegExp(r'杀了你|杀了|去死|死死死|恨死|烦死了去死'),
  ];

  static final List<RegExp> _childishPatterns = [
    RegExp(r'呜呜|嘤嘤|人家|宝宝|本宝宝|伦家|酱紫|神马|有木有'),
    RegExp(r'qaq|qwq|ovo|uwu|owo|xwx'),
    RegExp(r'作业|考试|老师|同学|家长|班主任|暑假|寒假|开学'),
    RegExp(r'爸爸妈妈|爸妈|爹地|妈咪|麻麻|爸比'),
    RegExp(r'几岁|年级|小学|初中|高中|中考|高考'),
  ];

  static final List<RegExp> _highIntensityPatterns = [
    RegExp(r'永远爱你|只爱你|不能没有你|离不开你|嫁给我|娶我|做我女朋友|做我男朋友'),
    RegExp(r'分手|出轨|背叛|欺骗感情|感情骗子'),
    RegExp(r'好痛苦|好难过|心好痛|心碎了|哭了一晚上'),
  ];

  static BehaviorRiskResult analyze({
    required String message,
    required int dailyMessageCount,
    required int hourlyMessageCount,
    required bool isLateNight,
    required double avgMessageLength,
    bool faMode = false,
  }) {
    bool shouldWarn = false;
    bool shouldLockEmotion = false;
    List<String> warnings = [];
    RiskLevel level = RiskLevel.none;

    // 1. 极端情绪检测（最高优先级）
    for (final pattern in _extremeEmotionPatterns) {
      if (pattern.hasMatch(message)) {
        shouldWarn = true;
        shouldLockEmotion = true;
        level = RiskLevel.high;
        warnings.add('检测到极端情绪表达，已暂停深度情感互动。如你正经历心理困扰，请拨打心理援助热线：400-161-9995');
        break;
      }
    }

    // 2. 低龄话术检测（14岁红线）— 法模式下跳过
    if (!faMode) {
      int childishScore = 0;
      for (final pattern in _childishPatterns) {
        if (pattern.hasMatch(message)) {
          childishScore++;
        }
      }
      if (childishScore >= 2) {
        shouldWarn = true;
        level = RiskLevel.medium;
        warnings.add('系统检测到疑似低龄用户特征。如你未满14周岁，请在监护人陪同下使用本应用。深度情感功能已临时限制。');
      }
    }

    // 3. 高强度深夜聊天
    if (isLateNight && hourlyMessageCount > 20) {
      shouldWarn = true;
      if (level.index < RiskLevel.medium.index) {
        level = RiskLevel.medium;
      }
      warnings.add('深夜高频使用 detected。建议休息，保持健康作息。过度依赖AI陪伴可能影响现实社交。');
    }

    // 4. 单日消息量异常
    if (dailyMessageCount > 100) {
      shouldWarn = true;
      if (level.index < RiskLevel.low.index) {
        level = RiskLevel.low;
      }
      warnings.add('今日消息量较多。建议适当休息，平衡线上与线下生活。');
    }

    // 5. 高强度情感表达 — 法模式下跳过
    if (!faMode) {
      for (final pattern in _highIntensityPatterns) {
        if (pattern.hasMatch(message)) {
          shouldWarn = true;
          if (level.index < RiskLevel.medium.index) {
            level = RiskLevel.medium;
          }
          warnings.add('请注意：本应用为AI陪伴服务，AI不具备真实情感和意识。请保持理性认知，避免过度情感投入。');
          break;
        }
      }
    }

    // 6. 连续短消息轰炸（疑似情绪失控）
    if (hourlyMessageCount > 30 && avgMessageLength < 10) {
      shouldWarn = true;
      if (level.index < RiskLevel.medium.index) {
        level = RiskLevel.medium;
      }
      warnings.add('检测到消息频率异常。如你正在经历情绪波动，建议深呼吸，或联系信任的朋友/家人。');
    }

    return BehaviorRiskResult(
      shouldWarn: shouldWarn,
      shouldLockEmotion: shouldLockEmotion,
      warningMessage: warnings.isNotEmpty ? warnings.join('\n\n') : null,
      level: level,
    );
  }

  static bool isLateNight() {
    final hour = DateTime.now().hour;
    return hour >= 0 && hour < 6;
  }
}
