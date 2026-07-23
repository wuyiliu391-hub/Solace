import '../models/device_agent_action.dart';

/// 人设策略卡：按性格关键词裁剪「推荐」工具（用户子权限仍是硬闸门）
enum DevicePersonaArchetype {
  care,
  dominant,
  playful,
  defaultNeutral,
}

class DevicePersonaStrategy {
  DevicePersonaStrategy._();

  static DevicePersonaArchetype detect({
    String personality = '',
    String coreDesire = '',
    String moralBoundary = '',
  }) {
    final text = '$personality $coreDesire $moralBoundary'.toLowerCase();

    final careHits = _count(text, const [
      '关心',
      '体贴',
      '温柔',
      '照顾',
      '守护',
      '心疼',
      '健康',
      '熬夜',
      '休息',
      'care',
      'gentle',
      '暖',
      '安抚',
    ]);
    final dominantHits = _count(text, const [
      '病娇',
      '强势',
      '控制',
      '占有',
      '支配',
      '命令',
      '强制',
      '锁',
      'yandere',
      'domineer',
      '霸道',
      '独占',
      '不许',
    ]);
    final playfulHits = _count(text, const [
      '玩闹',
      '调皮',
      '搞笑',
      '捉弄',
      '戏弄',
      '整蛊',
      '活泼',
      'playful',
      '恶作剧',
      '逗',
      '皮',
    ]);

    if (dominantHits >= careHits && dominantHits >= playfulHits && dominantHits > 0) {
      return DevicePersonaArchetype.dominant;
    }
    if (careHits >= playfulHits && careHits > 0) {
      return DevicePersonaArchetype.care;
    }
    if (playfulHits > 0) return DevicePersonaArchetype.playful;
    return DevicePersonaArchetype.defaultNeutral;
  }

  static int _count(String text, List<String> keys) {
    var n = 0;
    for (final k in keys) {
      if (text.contains(k.toLowerCase())) n++;
    }
    return n;
  }

  /// 推荐工具集合（子权限关闭的仍不会出现）
  static Set<String> preferredTools(DevicePersonaArchetype arch) {
    switch (arch) {
      case DevicePersonaArchetype.care:
        return {
          'get_battery_info',
          'get_current_app',
          'get_app_usage_time',
          'get_notifications',
          'get_notification_count',
          'set_brightness',
          'adjust_volume',
          'set_mute',
          'lock_screen', // 劝睡
          'open_app', // 打开健康/时钟类由人设决定
        };
      case DevicePersonaArchetype.dominant:
        return {
          'lock_screen',
          'go_home',
          'close_app',
          'open_app',
          'set_mute',
          'adjust_volume',
          'set_brightness',
          'toggle_wifi',
          'toggle_bluetooth',
          'get_current_app',
          'get_battery_info',
          'press_back',
        };
      case DevicePersonaArchetype.playful:
        return {
          'adjust_volume',
          'set_mute',
          'set_brightness',
          'open_gallery',
          'open_app',
          'go_home',
          'take_screenshot',
          'get_battery_info',
          'tap',
          'swipe',
        };
      case DevicePersonaArchetype.defaultNeutral:
        // 中性：全量可读可写，但能力卡里仍按用户已开权限列出；此处不额外砍
        return deviceToolNameMap.keys.toSet();
    }
  }

  /// 高风险工具：仅 dominant 默认推荐；其他 archetype 除非用户硬开权限且中性全量
  static const Set<String> highRiskTools = {
    'execute_shell',
    'close_app',
    'toggle_wifi',
    'toggle_bluetooth',
    'tap',
    'swipe',
    'input_text',
    'press_key',
  };

  static bool shouldListTool({
    required String toolName,
    required DevicePersonaArchetype arch,
    required bool userPermissionOn,
  }) {
    if (!userPermissionOn) return false;
    if (arch == DevicePersonaArchetype.defaultNeutral) return true;
    final preferred = preferredTools(arch);
    if (preferred.contains(toolName)) return true;
    // 非推荐的高风险：不进能力卡（权限开了也先不诱导模型）
    if (highRiskTools.contains(toolName)) return false;
    // 非推荐的低风险读类：仍可少量给 care/playful 以外？默认不列，减混乱
    return false;
  }

  static String archetypeLabel(DevicePersonaArchetype arch) {
    switch (arch) {
      case DevicePersonaArchetype.care:
        return '关心型';
      case DevicePersonaArchetype.dominant:
        return '强势/病娇型';
      case DevicePersonaArchetype.playful:
        return '玩闹型';
      case DevicePersonaArchetype.defaultNeutral:
        return '中性';
    }
  }

  static String strategyHint(DevicePersonaArchetype arch) {
    switch (arch) {
      case DevicePersonaArchetype.care:
        return '优先：查电量/前台、调亮度音量、必要时锁屏劝休息。少做强制关应用。';
      case DevicePersonaArchetype.dominant:
        return '可强势：锁屏、关应用、回桌面、静音；动机必须符合占有/管束人设。';
      case DevicePersonaArchetype.playful:
        return '可玩闹：音量、亮度、相册、截图；避免破坏性 shell。';
      case DevicePersonaArchetype.defaultNeutral:
        return '按情境选用已授权能力；每轮最多 1 个动作。';
    }
  }
}
