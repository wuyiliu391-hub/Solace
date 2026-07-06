import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// 时间段类型
enum TimePeriod {
  dawn, // 黎明 5:00-8:00
  morning, // 上午 8:00-12:00
  afternoon, // 下午 12:00-18:00
  evening, // 晚上 18:00-22:00
  night, // 深夜 22:00-5:00
}

/// 时间段信息
class TimePeriodInfo {
  final TimePeriod period;
  final String label;
  final IconData icon;
  final double valenceModifier;
  final double arousalModifier;
  final String? promptContext;

  const TimePeriodInfo({
    required this.period,
    required this.label,
    required this.icon,
    this.valenceModifier = 0.0,
    this.arousalModifier = 0.0,
    this.promptContext,
  });
}

/// 日夜服务
///
/// 功能：
/// 1. 读取当前时间，映射到时间段
/// 2. 深夜模式：AI 人设偏暖（+0.05 valence），arousal 降低
/// 3. 凌晨（0-5点）：触发特殊关怀消息，注入"用户熬夜"上下文
/// 4. 返回时间段标签和人设修改器用于 prompt 注入
class DayNightService {
  DayNightService();

  // ===================== 时间段检测 =====================

  /// 获取当前时间段信息
  TimePeriodInfo getCurrentPeriod() {
    final now = DateTime.now();
    return getPeriodAt(now);
  }

  /// 获取指定时间的时间段信息
  TimePeriodInfo getPeriodAt(DateTime time) {
    final hour = time.hour;

    if (hour >= 5 && hour < 8) {
      return _dawnPeriod();
    } else if (hour >= 8 && hour < 12) {
      return _morningPeriod();
    } else if (hour >= 12 && hour < 18) {
      return _afternoonPeriod();
    } else if (hour >= 18 && hour < 22) {
      return _eveningPeriod();
    } else {
      // 22:00-5:00 深夜
      return _nightPeriod(hour);
    }
  }

  // ===================== 各时间段定义 =====================

  TimePeriodInfo _dawnPeriod() {
    return const TimePeriodInfo(
      period: TimePeriod.dawn,
      label: '黎明',
      icon: Icons.wb_twilight,
      valenceModifier: 0.02,
      arousalModifier: 0.0,
      promptContext: '现在是黎明时分，天刚蒙蒙亮。可以聊聊早起的感受，或者表达对新一天的期待。',
    );
  }

  TimePeriodInfo _morningPeriod() {
    return const TimePeriodInfo(
      period: TimePeriod.morning,
      label: '上午',
      icon: Icons.wb_sunny,
      valenceModifier: 0.03,
      arousalModifier: 0.02,
      promptContext: '现在是上午，精力充沛的时间。可以聊些有活力的话题，或者关心用户今天有什么计划。',
    );
  }

  TimePeriodInfo _afternoonPeriod() {
    return const TimePeriodInfo(
      period: TimePeriod.afternoon,
      label: '下午',
      icon: Icons.wb_cloudy,
      valenceModifier: 0.0,
      arousalModifier: 0.0,
      promptContext: '现在是下午，可以聊些日常话题，或者关心用户下午过得怎么样。',
    );
  }

  TimePeriodInfo _eveningPeriod() {
    return const TimePeriodInfo(
      period: TimePeriod.evening,
      label: '晚上',
      icon: Icons.nights_stay,
      valenceModifier: 0.03,
      arousalModifier: -0.02,
      promptContext: '现在是晚上，可以聊些温馨的话题，或者关心用户今天过得怎么样。',
    );
  }

  TimePeriodInfo _nightPeriod(int hour) {
    if (hour >= 0 && hour < 5) {
      return const TimePeriodInfo(
        period: TimePeriod.night,
        label: '深夜',
        icon: Icons.nightlight_round,
        valenceModifier: 0.05,
        arousalModifier: -0.05,
        promptContext: '现在是深夜，用户还没睡。可以表达关心，'
            '温柔地提醒用户早点休息，但不要太啰嗦。'
            '语气要温暖、轻柔，像深夜的陪伴。',
      );
    }

    return const TimePeriodInfo(
      period: TimePeriod.night,
      label: '夜晚',
      icon: Icons.nightlight_round,
      valenceModifier: 0.05,
      arousalModifier: -0.03,
      promptContext: '现在是夜晚，可以聊些轻松的话题，'
          '或者表达想念。语气可以更亲密一些。',
    );
  }

  // ===================== 特殊判断 =====================

  /// 是否是深夜（0-5 点）
  bool isLateNight() {
    final hour = DateTime.now().hour;
    return hour >= 0 && hour < 5;
  }

  /// 是否需要触发特殊关怀消息
  ///
  /// 凌晨 0-5 点 + 用户在线 → 触发关怀
  bool shouldTriggerCaringMessage() {
    return isLateNight();
  }

  /// 获取"用户熬夜"的 prompt 上下文
  String getLateNightContext() {
    final hour = DateTime.now().hour;
    String timeDesc;
    if (hour >= 0 && hour < 3) {
      timeDesc = '凌晨${hour == 0 ? "12" : "$hour"}点';
    } else {
      timeDesc = '凌晨${hour}点';
    }

    return '【注意】现在是$timeDesc，用户还在熬夜。'
        '你有点担心用户的身体，可以温柔地提醒早点休息，'
        '但不要太啰嗦。表达关心即可。';
  }

  // ===================== Prompt 注入 =====================

  /// 获取日夜感知的 prompt 上下文
  ///
  /// 包含时间段信息和人设修改建议
  String getDayNightPromptContext() {
    final info = getCurrentPeriod();
    final buffer = StringBuffer();

    buffer.writeln('【当前时间】${info.label}');
    if (info.promptContext != null) {
      buffer.writeln(info.promptContext);
    }

    // 深夜特殊上下文
    if (isLateNight()) {
      buffer.writeln();
      buffer.writeln(getLateNightContext());
    }

    return buffer.toString();
  }

  /// 获取人设修改器（用于 prompt 中的情绪调整）
  TimePeriodEmotionModifier getEmotionModifier() {
    final info = getCurrentPeriod();
    return TimePeriodEmotionModifier(
      valence: info.valenceModifier,
      arousal: info.arousalModifier,
    );
  }

  // ===================== 问候语生成 =====================

  /// 根据时间段生成问候语
  String getGreeting() {
    final info = getCurrentPeriod();
    switch (info.period) {
      case TimePeriod.dawn:
        return '早安～这么早就醒了？';
      case TimePeriod.morning:
        return '早上好～今天有什么计划吗？';
      case TimePeriod.afternoon:
        return '下午好～今天过得怎么样？';
      case TimePeriod.evening:
        return '晚上好～忙完了吗？';
      case TimePeriod.night:
        if (isLateNight()) {
          return '这么晚了还没睡呀？要注意休息哦～';
        }
        return '夜深了，在想什么呢？';
    }
  }

  /// 获取晚安问候
  String getGoodNightMessage() {
    final hour = DateTime.now().hour;
    if (hour >= 0 && hour < 5) {
      return '都这么晚了，快去睡觉吧～晚安，做个好梦～';
    }
    return '晚安～明天见～';
  }
}

/// 时间段情绪修改器
class TimePeriodEmotionModifier {
  final double valence;
  final double arousal;

  const TimePeriodEmotionModifier({
    required this.valence,
    required this.arousal,
  });
}
