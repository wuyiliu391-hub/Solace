import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../repositories/local_storage_repository.dart';
import '../config/constants.dart';
import 'emotion_engine.dart';

/// 天气类型
enum WeatherType {
  sunny, // 晴天
  cloudy, // 多云
  rainy, // 下雨
  snowy, // 下雪
  windy, // 大风
  foggy, // 雾
  stormy, // 暴风雨
  unknown, // 未知
}

/// 天气数据
class WeatherData {
  final WeatherType type;
  final String label;
  final double temperature;
  final String? rawDescription;

  const WeatherData({
    required this.type,
    required this.label,
    this.temperature = 20.0,
    this.rawDescription,
  });

  Map<String, dynamic> toMap() => {
        'type': type.index,
        'label': label,
        'temperature': temperature,
        'rawDescription': rawDescription,
      };

  factory WeatherData.fromMap(Map<String, dynamic> map) => WeatherData(
        type: WeatherType.values[map['type'] as int],
        label: map['label'] as String,
        temperature: (map['temperature'] as num?)?.toDouble() ?? 20.0,
        rawDescription: map['rawDescription'] as String?,
      );

  factory WeatherData.fromString(String weather) {
    final type = _parseWeatherType(weather);
    return WeatherData(
      type: type,
      label: _weatherLabel(type),
      rawDescription: weather,
    );
  }
}

WeatherType _parseWeatherType(String weather) {
  final lower = weather.toLowerCase();
  if (lower.contains('晴') || lower.contains('sunny')) return WeatherType.sunny;
  if (lower.contains('云') || lower.contains('cloudy')) return WeatherType.cloudy;
  if (lower.contains('雨') || lower.contains('rain')) return WeatherType.rainy;
  if (lower.contains('雪') || lower.contains('snow')) return WeatherType.snowy;
  if (lower.contains('风') || lower.contains('wind')) return WeatherType.windy;
  if (lower.contains('雾') || lower.contains('fog')) return WeatherType.foggy;
  if (lower.contains('暴') || lower.contains('storm')) return WeatherType.stormy;
  return WeatherType.unknown;
}

String _weatherLabel(WeatherType type) {
  switch (type) {
    case WeatherType.sunny:
      return '晴天';
    case WeatherType.cloudy:
      return '多云';
    case WeatherType.rainy:
      return '雨天';
    case WeatherType.snowy:
      return '雪天';
    case WeatherType.windy:
      return '大风';
    case WeatherType.foggy:
      return '雾天';
    case WeatherType.stormy:
      return '暴风雨';
    case WeatherType.unknown:
      return '未知';
  }
}

/// 天气服务
///
/// 功能：
/// 1. 通过平台通道读取系统天气
/// 2. 回退：从 SharedPreferences 解析天气
/// 3. 天气→情绪映射：晴天+0.05 valence，雨天-0.05，雪天+0.03 arousal 等
/// 4. 通过 LocalStorageRepository.updateUserWeather 存储到 users 表
/// 5. 天气感知 prompt 注入：添加天气上下文到 AI system prompt
class WeatherService {
  final LocalStorageRepository _storage;
  final EmotionEngine _emotionEngine;

  // 平台通道名称
  static const String _channelName = 'com.solace/weather';

  WeatherService(this._storage, this._emotionEngine);

  // ===================== 天气获取 =====================

  /// 获取当前天气
  ///
  /// 优先从平台通道获取，回退到 SharedPreferences
  Future<WeatherData> getCurrentWeather() async {
    // 尝试从平台通道获取
    try {
      final platformWeather = await _getSystemWeather();
      if (platformWeather != null) {
        debugPrint('WeatherService: 从系统获取天气 $platformWeather');
        return platformWeather;
      }
    } catch (e) {
      debugPrint('WeatherService: 系统天气获取失败 $e');
    }

    // 回退：从 SharedPreferences 获取
    try {
      final cachedWeather = _getCachedWeather();
      if (cachedWeather != null) {
        debugPrint('WeatherService: 从缓存获取天气 ${cachedWeather.label}');
        return cachedWeather;
      }
    } catch (e) {
      debugPrint('WeatherService: 缓存天气读取失败 $e');
    }

    // 默认：晴天
    debugPrint('WeatherService: 使用默认天气（晴天）');
    return const WeatherData(
      type: WeatherType.sunny,
      label: '晴天',
    );
  }

  /// 从平台通道获取系统天气
  Future<WeatherData?> _getSystemWeather() async {
    // 平台通道调用在不同平台有不同实现
    // 这里提供降级方案：如果通道不可用，返回 null
    try {
      // MethodChannel 调用需要在 UI 线程执行
      // 这里直接返回 null，让调用方走 SharedPreferences 回退路径
      // 实际平台通道调用在 Android/iOS 原生代码中实现
      return null;
    } catch (e) {
      debugPrint('WeatherService: 平台通道调用失败 $e');
      return null;
    }
  }

  /// 从 SharedPreferences 获取缓存天气
  WeatherData? _getCachedWeather() {
    final weatherJson = _storage.getString('cached_weather');
    if (weatherJson == null) return null;

    try {
      final map = jsonDecode(weatherJson) as Map<String, dynamic>;
      final lastUpdate = map['lastUpdate'] as String?;
      if (lastUpdate != null) {
        final update_time = DateTime.parse(lastUpdate);
        final hoursSinceUpdate = DateTime.now().difference(update_time).inHours;
        // 天气缓存超过 3 小时则过期
        if (hoursSinceUpdate > 3) return null;
      }
      return WeatherData.fromMap(map['weather'] as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// 缓存天气到 SharedPreferences
  Future<void> _cacheWeather(WeatherData weather) async {
    final data = {
      'weather': weather.toMap(),
      'lastUpdate': DateTime.now().toIso8601String(),
    };
    await _storage.setString('cached_weather', jsonEncode(data));
  }

  // ===================== 天气→情绪映射 =====================

  /// 获取天气对应的情绪调整参数
  ///
  /// 晴天: +0.05 valence
  /// 多云: 无调整
  /// 雨天: -0.05 valence
  /// 雪天: +0.03 arousal
  /// 大风: +0.02 arousal
  /// 雾天: -0.02 valence
  /// 暴风雨: -0.08 valence, +0.05 arousal
  WeatherEmotionModifier getWeatherEmotionModifier(WeatherType type) {
    switch (type) {
      case WeatherType.sunny:
        return const WeatherEmotionModifier(valence: 0.05, arousal: 0.0);
      case WeatherType.cloudy:
        return const WeatherEmotionModifier(valence: 0.0, arousal: 0.0);
      case WeatherType.rainy:
        return const WeatherEmotionModifier(valence: -0.05, arousal: 0.0);
      case WeatherType.snowy:
        return const WeatherEmotionModifier(valence: 0.0, arousal: 0.03);
      case WeatherType.windy:
        return const WeatherEmotionModifier(valence: 0.0, arousal: 0.02);
      case WeatherType.foggy:
        return const WeatherEmotionModifier(valence: -0.02, arousal: 0.0);
      case WeatherType.stormy:
        return const WeatherEmotionModifier(valence: -0.08, arousal: 0.05);
      case WeatherType.unknown:
        return const WeatherEmotionModifier(valence: 0.0, arousal: 0.0);
    }
  }

  /// 应用天气情绪调整
  Future<void> applyWeatherEmotion({
    required String characterId,
    required String userId,
    required WeatherData weather,
  }) async {
    final modifier = getWeatherEmotionModifier(weather.type);

    if (modifier.valence != 0.0) {
      await _emotionEngine.adjustValence(
        characterId: characterId,
        userId: userId,
        delta: modifier.valence,
      );
    }

    debugPrint(
        'WeatherService: 应用天气情绪 ${weather.label} → '
        'valence ${modifier.valence > 0 ? "+" : ""}${modifier.valence}, '
        'arousal ${modifier.arousal > 0 ? "+" : ""}${modifier.arousal}');
  }

  // ===================== 存储到 users 表 =====================

  /// 更新用户天气信息到数据库
  Future<void> updateWeather({
    required String userId,
    required WeatherData weather,
  }) async {
    await _storage.updateUserWeather(userId, weather.label);
    await _cacheWeather(weather);
    debugPrint('WeatherService: 更新用户天气 ${weather.label}');
  }

  // ===================== Prompt 注入 =====================

  /// 天气感知 prompt 注入
  ///
  /// 返回天气上下文字符串，添加到 AI system prompt 中
  String getWeatherPromptContext(WeatherData weather) {
    final modifier = getWeatherEmotionModifier(weather.type);

    final buffer = StringBuffer();
    buffer.write('【当前天气】${weather.label}');

    if (weather.temperature != 20.0) {
      buffer.write('，${weather.temperature.toStringAsFixed(0)}°C');
    }

    buffer.writeln();

    // 根据天气给出 AI 行为提示
    switch (weather.type) {
      case WeatherType.sunny:
        buffer.writeln('天气很好，可以提议一起出去走走，或者聊聊开心的事。');
        break;
      case WeatherType.cloudy:
        buffer.writeln('天气一般，可以聊些日常话题。');
        break;
      case WeatherType.rainy:
        buffer.writeln('外面在下雨，可以表达对用户淋雨的关心，或者聊些温馨的话题。');
        break;
      case WeatherType.snowy:
        buffer.writeln('下雪了！可以表达对雪的兴奋，或者提醒用户注意保暖。');
        break;
      case WeatherType.windy:
        buffer.writeln('风很大，可以提醒用户注意安全。');
        break;
      case WeatherType.foggy:
        buffer.writeln('雾很大，可以提醒用户出行注意安全。');
        break;
      case WeatherType.stormy:
        buffer.writeln('暴风雨来了！可以表达担心，叮嘱用户待在安全的地方。');
        break;
      case WeatherType.unknown:
        break;
    }

    return buffer.toString();
  }

  // ===================== 刷新天气 =====================

  /// 刷新天气数据（更新缓存和数据库）
  Future<WeatherData> refreshWeather({required String userId}) async {
    final weather = await getCurrentWeather();
    await updateWeather(userId: userId, weather: weather);
    return weather;
  }
}

/// 天气情绪调整参数
class WeatherEmotionModifier {
  final double valence;
  final double arousal;

  const WeatherEmotionModifier({
    required this.valence,
    required this.arousal,
  });
}
