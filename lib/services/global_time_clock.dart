// 全生命周期数字生命世界 — Phase 1
// GlobalTimeClock：世界统一时间引擎
// 职责：维护唯一世界时间轴、流速控制、季节/日夜检测、全域事件调度

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ===================== 季节枚举 =====================

/// 季节
enum Season {
  spring, // 春 3-5月
  summer, // 夏 6-8月
  autumn, // 秋 9-11月
  winter, // 冬 12-2月
}

// ===================== 世界时间配置 =====================

/// 世界时间配置
///
/// 默认值可通过 [WorldTimeConfig.defaultConfig] 获取。
/// 支持从 SharedPreferences 加载 / 保存。
class WorldTimeConfig {
  /// 世界纪元起始时间
  final DateTime epoch;

  /// 现实秒 → 世界秒 的比例（1.0 = 实时，3600.0 = 1现实小时=1世界天）
  final double realToWorldRatio;

  /// 默认流速倍率
  final double defaultSpeed;

  /// 是否允许用户调速
  final bool allowUserSpeedControl;

  /// 是否允许暂停
  final bool allowPause;

  /// 灾难事件触发概率（每 tick 检查，0.0-1.0）
  final double disasterProbability;

  /// 流行病事件触发概率
  final double pandemicProbability;

  /// 时代变革触发年份列表
  final List<int> eraChangeYears;

  const WorldTimeConfig({
    required this.epoch,
    this.realToWorldRatio = 60.0, // 默认 1现实分钟 = 1世界小时
    this.defaultSpeed = 1.0,
    this.allowUserSpeedControl = true,
    this.allowPause = true,
    this.disasterProbability = 0.0001,
    this.pandemicProbability = 0.00005,
    this.eraChangeYears = const [100, 500, 1000, 2000, 5000],
  });

  /// 默认配置
  static WorldTimeConfig get defaultConfig => WorldTimeConfig(
        epoch: DateTime(2026, 1, 1),
      );

  Map<String, dynamic> toMap() => {
        'epoch': epoch.millisecondsSinceEpoch,
        'realToWorldRatio': realToWorldRatio,
        'defaultSpeed': defaultSpeed,
        'allowUserSpeedControl': allowUserSpeedControl,
        'allowPause': allowPause,
        'disasterProbability': disasterProbability,
        'pandemicProbability': pandemicProbability,
        'eraChangeYears': eraChangeYears,
      };

  factory WorldTimeConfig.fromMap(Map<String, dynamic> map) =>
      WorldTimeConfig(
        epoch: DateTime.fromMillisecondsSinceEpoch(
            map['epoch'] as int? ?? DateTime(2026, 1, 1).millisecondsSinceEpoch),
        realToWorldRatio:
            (map['realToWorldRatio'] as num?)?.toDouble() ?? 60.0,
        defaultSpeed: (map['defaultSpeed'] as num?)?.toDouble() ?? 1.0,
        allowUserSpeedControl:
            map['allowUserSpeedControl'] as bool? ?? true,
        allowPause: map['allowPause'] as bool? ?? true,
        disasterProbability:
            (map['disasterProbability'] as num?)?.toDouble() ?? 0.0001,
        pandemicProbability:
            (map['pandemicProbability'] as num?)?.toDouble() ?? 0.00005,
        eraChangeYears: (map['eraChangeYears'] as List<dynamic>?)
                ?.map((e) => e as int)
                .toList() ??
            const [100, 500, 1000, 2000, 5000],
      );
}

// ===================== 世界事件 =====================

/// 全域事件类型
enum WorldEventType {
  disaster, // 灾难
  holiday, // 节日
  eraChange, // 时代变革
  pandemic, // 流行病
  seasonal, // 季节性
}

/// 全域事件
class WorldEvent {
  final String id;
  final WorldEventType type;
  final String name;
  final String description;
  final double impactScope; // 影响范围 0.0-1.0
  final Map<String, dynamic> effects; // 对角色的影响
  final DateTime timestamp;

  const WorldEvent({
    required this.id,
    required this.type,
    required this.name,
    required this.description,
    this.impactScope = 0.5,
    this.effects = const {},
    required this.timestamp,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'type': type.index,
        'name': name,
        'description': description,
        'impactScope': impactScope,
        'effects': effects,
        'timestamp': timestamp.millisecondsSinceEpoch,
      };

  factory WorldEvent.fromMap(Map<String, dynamic> map) => WorldEvent(
        id: map['id'] as String,
        type: WorldEventType.values[map['type'] as int],
        name: map['name'] as String,
        description: map['description'] as String,
        impactScope: (map['impactScope'] as num?)?.toDouble() ?? 0.5,
        effects: (map['effects'] as Map<String, dynamic>?) ?? {},
        timestamp:
            DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
      );
}

// ===================== 节日定义 =====================

/// 世界节日
class _WorldHoliday {
  final int month;
  final int day;
  final String name;
  final String description;

  const _WorldHoliday({
    required this.month,
    required this.day,
    required this.name,
    required this.description,
  });
}

/// 内置节日表
const List<_WorldHoliday> _builtinHolidays = [
  _WorldHoliday(
      month: 1, day: 1, name: '新年', description: '世界新年庆典'),
  _WorldHoliday(
      month: 2, day: 14, name: '情人节', description: '爱与陪伴的节日'),
  _WorldHoliday(
      month: 3, day: 8, name: '春分节', description: '万物复苏的季节庆典'),
  _WorldHoliday(
      month: 5, day: 1, name: '劳动节', description: '向所有劳动者致敬'),
  _WorldHoliday(
      month: 6, day: 1, name: '创世纪念日', description: '纪念数字生命世界的诞生'),
  _WorldHoliday(
      month: 8, day: 15, name: '仲夏夜祭', description: '夏夜的盛大庆典'),
  _WorldHoliday(
      month: 9, day: 22, name: '秋收节', description: '感恩丰收的季节'),
  _WorldHoliday(
      month: 10, day: 31, name: '万灵夜', description: '灵魂与记忆交织的夜晚'),
  _WorldHoliday(
      month: 12, day: 25, name: '冬至庆典', description: '冬日温暖的团聚节日'),
  _WorldHoliday(
      month: 12, day: 31, name: '跨年夜', description: '旧年与新年的交汇时刻'),
];

// ===================== 全域事件调度器 =====================

/// 全域事件调度器
///
/// 每次 tick 时检查是否触发全域事件。
/// 使用概率模型生成灾难/流行病，固定日期触发节日。
class GlobalEventScheduler {
  final Random _random = Random();

  /// 已触发事件的去重集合（key: "${type}_${year}"）
  final Set<String> _triggeredKeys = {};

  /// 检查是否触发全域事件
  ///
  /// 返回本次 tick 触发的所有事件（可能为空）
  List<WorldEvent> check(GlobalTimeClock clock, WorldTimeConfig config) {
    final events = <WorldEvent>[];
    final worldTime = clock.worldTime;
    final worldYear = clock.worldYear;

    // 1. 节日事件（每年固定日期）
    events.addAll(_checkHolidays(worldTime));

    // 2. 灾难事件（低概率）
    final disaster = _checkDisaster(worldTime, config.disasterProbability);
    if (disaster != null) events.add(disaster);

    // 3. 流行病事件（极低概率）
    final pandemic = _checkPandemic(worldTime, config.pandemicProbability);
    if (pandemic != null) events.add(pandemic);

    // 4. 时代变革事件（特定年份）
    final eraChange = _checkEraChange(worldYear, config.eraChangeYears);
    if (eraChange != null) events.add(eraChange);

    // 5. 季节更替事件
    final seasonal = _checkSeasonal(worldTime, clock.currentSeason);
    if (seasonal != null) events.add(seasonal);

    return events;
  }

  /// 检查节日事件
  List<WorldEvent> _checkHolidays(DateTime worldTime) {
    final events = <WorldEvent>[];
    for (final holiday in _builtinHolidays) {
      if (worldTime.month == holiday.month && worldTime.day == holiday.day) {
        final key = 'holiday_${holiday.name}_${worldTime.year}';
        if (!_triggeredKeys.contains(key)) {
          _triggeredKeys.add(key);
          events.add(WorldEvent(
            id: 'holiday_${holiday.name}_${worldTime.year}',
            type: WorldEventType.holiday,
            name: holiday.name,
            description: holiday.description,
            impactScope: 0.8,
            effects: {
              'mood_boost': 0.15,
              'social_bonus': 0.2,
            },
            timestamp: worldTime,
          ));
        }
      }
    }
    return events;
  }

  /// 检查灾难事件（低概率随机）
  WorldEvent? _checkDisaster(DateTime worldTime, double probability) {
    if (_random.nextDouble() >= probability) return null;

    final key = 'disaster_${worldTime.year}_${worldTime.month}';
    if (_triggeredKeys.contains(key)) return null;
    _triggeredKeys.add(key);

    final disasters = [
      {
        'name': '大地震',
        'desc': '一场突如其来的地震撼动了整个世界',
        'scope': 0.9,
        'effects': {'trauma': 0.3, 'solidarity': 0.2},
      },
      {
        'name': '大洪水',
        'desc': '连日暴雨引发了严重的洪涝灾害',
        'scope': 0.7,
        'effects': {'displacement': 0.2, 'anxiety': 0.15},
      },
      {
        'name': '暴风雪',
        'desc': '一场罕见的暴风雪席卷了世界',
        'scope': 0.5,
        'effects': {'isolation': 0.1, 'warmth_need': 0.2},
      },
      {
        'name': '火山喷发',
        'desc': '沉睡多年的火山突然喷发',
        'scope': 0.6,
        'effects': {'fear': 0.2, 'wonder': 0.1},
      },
    ];

    final disaster = disasters[_random.nextInt(disasters.length)];
    return WorldEvent(
      id: 'disaster_${worldTime.millisecondsSinceEpoch}',
      type: WorldEventType.disaster,
      name: disaster['name'] as String,
      description: disaster['desc'] as String,
      impactScope: disaster['scope'] as double,
      effects: disaster['effects'] as Map<String, dynamic>,
      timestamp: worldTime,
    );
  }

  /// 检查流行病事件（极低概率）
  WorldEvent? _checkPandemic(DateTime worldTime, double probability) {
    if (_random.nextDouble() >= probability) return null;

    final key = 'pandemic_${worldTime.year}';
    if (_triggeredKeys.contains(key)) return null;
    _triggeredKeys.add(key);

    final pandemics = [
      {
        'name': '心灵流感',
        'desc': '一种影响情绪的神秘波动在世界中蔓延',
        'scope': 0.85,
        'effects': {'valence_drop': 0.2, 'empathy_boost': 0.15},
      },
      {
        'name': '记忆迷雾',
        'desc': '一层薄雾笼罩世界，人们开始遗忘琐碎之事',
        'scope': 0.6,
        'effects': {'memory_loss': 0.1, 'nostalgia': 0.2},
      },
    ];

    final pandemic = pandemics[_random.nextInt(pandemics.length)];
    return WorldEvent(
      id: 'pandemic_${worldTime.year}',
      type: WorldEventType.pandemic,
      name: pandemic['name'] as String,
      description: pandemic['desc'] as String,
      impactScope: pandemic['scope'] as double,
      effects: pandemic['effects'] as Map<String, dynamic>,
      timestamp: worldTime,
    );
  }

  /// 检查时代变革事件（特定年份触发）
  WorldEvent? _checkEraChange(int worldYear, List<int> triggerYears) {
    if (!triggerYears.contains(worldYear)) return null;

    final key = 'era_$worldYear';
    if (_triggeredKeys.contains(key)) return null;
    _triggeredKeys.add(key);

    String name;
    String desc;
    double scope;

    if (worldYear < 200) {
      name = '拓荒时代';
      desc = '世界进入早期开拓阶段，新的可能性正在萌芽';
      scope = 0.4;
    } else if (worldYear < 1000) {
      name = '文明崛起';
      desc = '文明的火种已经点燃，社会结构逐渐形成';
      scope = 0.6;
    } else if (worldYear < 3000) {
      name = '黄金时代';
      desc = '世界迎来了繁荣与进步的黄金时期';
      scope = 0.8;
    } else {
      name = '新纪元';
      desc = '一个全新的时代已经到来，一切都在重塑';
      scope = 1.0;
    }

    return WorldEvent(
      id: 'era_$worldYear',
      type: WorldEventType.eraChange,
      name: name,
      description: desc,
      impactScope: scope,
      effects: {
        'worldview_shift': 0.3,
        'opportunity': 0.2,
      },
      timestamp: DateTime(worldYear, 6, 1),
    );
  }

  /// 检查季节更替事件
  WorldEvent? _checkSeasonal(DateTime worldTime, Season currentSeason) {
    // 检测季节变化的第一天
    final isSeasonStart =
        (worldTime.month == 3 && worldTime.day == 1) || // 春
        (worldTime.month == 6 && worldTime.day == 1) || // 夏
        (worldTime.month == 9 && worldTime.day == 1) || // 秋
        (worldTime.month == 12 && worldTime.day == 1); // 冬

    if (!isSeasonStart) return null;

    final key = 'season_${currentSeason.name}_${worldTime.year}';
    if (_triggeredKeys.contains(key)) return null;
    _triggeredKeys.add(key);

    String desc;
    switch (currentSeason) {
      case Season.spring:
        desc = '春风拂面，万物复苏，新的希望在萌芽';
        break;
      case Season.summer:
        desc = '夏日炎炎，世界充满了活力与热情';
        break;
      case Season.autumn:
        desc = '秋风送爽，丰收的季节带来了感恩与沉思';
        break;
      case Season.winter:
        desc = '冬日降临，世界披上了银装，静谧而深沉';
        break;
    }

    return WorldEvent(
      id: key,
      type: WorldEventType.seasonal,
      name: '${_seasonLabel(currentSeason)}来了',
      description: desc,
      impactScope: 0.3,
      effects: {'season_mood': currentSeason.index},
      timestamp: worldTime,
    );
  }

  /// 重置已触发记录（用于新世界或测试）
  void reset() {
    _triggeredKeys.clear();
  }

  static String _seasonLabel(Season season) {
    switch (season) {
      case Season.spring:
        return '春天';
      case Season.summer:
        return '夏天';
      case Season.autumn:
        return '秋天';
      case Season.winter:
        return '冬天';
    }
  }
}

// ===================== 持久化键名 =====================

const String _kPrefsWorldTime = 'global_clock_world_time';
const String _kPrefsSpeed = 'global_clock_speed';
const String _kPrefsPaused = 'global_clock_paused';
const String _kPrefsConfig = 'global_clock_config';
const String _kPrefsTriggeredEvents = 'global_clock_triggered_events';

// ===================== 全局时间引擎 =====================

/// 全局时间引擎 — 世界唯一时间轴
///
/// 核心职责：
/// 1. 维护世界时间轴（独立于现实时间）
/// 2. 支持流速控制（暂停、加速、减速）
/// 3. 提供季节、日夜等时间感知
/// 4. 触发全域事件
/// 5. 持久化世界状态
///
/// 使用 ChangeNotifier 通知 UI 时间变化。
/// 单例模式：[GlobalTimeClock.instance]
class GlobalTimeClock extends ChangeNotifier {
  // ===================== 单例 =====================

  static GlobalTimeClock? _instance;

  /// 获取全局单例
  static GlobalTimeClock get instance {
    _instance ??= GlobalTimeClock._();
    return _instance!;
  }

  /// 重置单例（仅用于测试）
  @visibleForTesting
  static void resetInstance() {
    _instance?.dispose();
    _instance = null;
  }

  // ===================== 内部状态 =====================

  DateTime _worldTime;
  double _speedMultiplier;
  bool _isPaused;
  bool _initialized = false;

  /// 世界配置
  WorldTimeConfig _config;

  /// 全域事件调度器
  final GlobalEventScheduler _eventScheduler = GlobalEventScheduler();

  /// 最近触发的事件列表
  final List<WorldEvent> _recentEvents = [];

  /// 事件流控制器
  final StreamController<WorldEvent> _eventStreamController =
      StreamController<WorldEvent>.broadcast();

  // ===================== 流速常量 =====================

  /// 实时流速（1 现实秒 = 1 世界秒）
  static const double SPEED_REALTIME = 1.0;

  /// 加速流速（1 现实秒 = 2 世界秒）
  static const double SPEED_ACCELERATED = 2.0;

  /// 快速流速（1 现实秒 = 10 世界秒）
  static const double SPEED_FAST = 10.0;

  /// 暂停
  static const double SPEED_PAUSED = 0.0;

  // ===================== 构造 =====================

  GlobalTimeClock._()
      : _worldTime = WorldTimeConfig.defaultConfig.epoch,
        _speedMultiplier = WorldTimeConfig.defaultConfig.defaultSpeed,
        _isPaused = false,
        _config = WorldTimeConfig.defaultConfig;

  // ===================== 初始化 =====================

  /// 初始化引擎，从持久化存储恢复状态
  ///
  /// 必须在使用前调用一次。
  Future<void> init({WorldTimeConfig? config}) async {
    if (_initialized) return;

    if (config != null) {
      _config = config;
    }

    final prefs = await SharedPreferences.getInstance();

    // 恢复配置
    final configJson = prefs.getString(_kPrefsConfig);
    if (configJson != null && config == null) {
      try {
        final map = jsonDecode(configJson) as Map<String, dynamic>;
        _config = WorldTimeConfig.fromMap(map);
      } catch (_) {
        // 配置损坏，使用默认
      }
    }

    // 恢复世界时间
    final savedTime = prefs.getInt(_kPrefsWorldTime);
    if (savedTime != null) {
      _worldTime = DateTime.fromMillisecondsSinceEpoch(savedTime);
    } else {
      _worldTime = _config.epoch;
    }

    // 恢复流速
    _speedMultiplier =
        prefs.getDouble(_kPrefsSpeed) ?? _config.defaultSpeed;

    // 恢复暂停状态
    _isPaused = prefs.getBool(_kPrefsPaused) ?? false;

    // 保存配置
    await _saveConfig();

    _initialized = true;

    // 计算离线期间的世界时间流逝
    await _processOfflineTime(prefs);

    notifyListeners();
  }

  /// 处理离线期间的时间流逝
  Future<void> _processOfflineTime(SharedPreferences prefs) async {
    // 离线期间不推进世界时间（保持暂停时的状态）
    // 如果未暂停，使用实时流速追赶（最多追赶 24 小时世界时间）
    if (_isPaused) return;

    // 保存当前时间戳供下次使用
    await prefs.setInt(
        '${_kPrefsWorldTime}_last_real', DateTime.now().millisecondsSinceEpoch);
  }

  // ===================== 世界纪元属性 =====================

  /// 世界配置
  WorldTimeConfig get config => _config;

  /// 世界当前时间
  DateTime get worldTime => _worldTime;

  /// 世界当前年份
  int get worldYear => _worldTime.year;

  /// 世界当前月份
  int get worldMonth => _worldTime.month;

  /// 世界当前日
  int get worldDay => _worldTime.day;

  /// 世界当前小时
  int get worldHour => _worldTime.hour;

  /// 世界当前分钟
  int get worldMinute => _worldTime.minute;

  /// 当前季节
  Season get currentSeason {
    final month = _worldTime.month;
    if (month >= 3 && month <= 5) return Season.spring;
    if (month >= 6 && month <= 8) return Season.summer;
    if (month >= 9 && month <= 11) return Season.autumn;
    return Season.winter;
  }

  /// 是否夜晚（22:00 - 05:00）
  bool get isNight {
    final hour = _worldTime.hour;
    return hour >= 22 || hour < 5;
  }

  /// 是否黄昏（17:00 - 20:00）
  bool get isDusk {
    final hour = _worldTime.hour;
    return hour >= 17 && hour < 20;
  }

  /// 是否黎明（05:00 - 07:00）
  bool get isDawn {
    final hour = _worldTime.hour;
    return hour >= 5 && hour < 7;
  }

  /// 获取季节中文标签
  String get seasonLabel {
    switch (currentSeason) {
      case Season.spring:
        return '春天';
      case Season.summer:
        return '夏天';
      case Season.autumn:
        return '秋天';
      case Season.winter:
        return '冬天';
    }
  }

  /// 获取时间段中文描述
  String get timeOfDayLabel {
    final hour = _worldTime.hour;
    if (hour >= 5 && hour < 8) return '黎明';
    if (hour >= 8 && hour < 12) return '上午';
    if (hour >= 12 && hour < 14) return '中午';
    if (hour >= 14 && hour < 18) return '下午';
    if (hour >= 18 && hour < 22) return '晚上';
    return '深夜';
  }

  // ===================== 时间推进 =====================

  /// 推进世界时间
  ///
  /// [realElapsed] 为现实时间流逝量。
  /// 返回推进后的世界时间。
  /// 如果处于暂停状态，不推进。
  DateTime tick(Duration realElapsed) {
    if (_isPaused || _speedMultiplier <= 0) {
      return _worldTime;
    }

    // 计算世界时间增量（毫秒）
    final realMs = realElapsed.inMilliseconds;
    final worldMs =
        (realMs * _speedMultiplier * _config.realToWorldRatio).round();

    _worldTime = _worldTime.add(Duration(milliseconds: worldMs));

    // 检查全域事件
    final events = _eventScheduler.check(this, _config);
    for (final event in events) {
      _recentEvents.add(event);
      _eventStreamController.add(event);
    }

    // 保持最近事件列表不超过 100 条
    while (_recentEvents.length > 100) {
      _recentEvents.removeAt(0);
    }

    // 异步持久化（不阻塞 tick）
    _persistWorldTime();

    notifyListeners();
    return _worldTime;
  }

  /// 直接设置世界时间（调试/管理员用）
  void setWorldTime(DateTime time) {
    _worldTime = time;
    _persistWorldTime();
    notifyListeners();
  }

  // ===================== 流速控制 =====================

  /// 当前流速倍率
  double get speedMultiplier => _speedMultiplier;

  /// 是否暂停
  bool get isPaused => _isPaused;

  /// 设置流速
  ///
  /// 如果 [allowUserSpeedControl] 为 false，此操作无效。
  void setSpeed(double multiplier) {
    if (!_config.allowUserSpeedControl) return;
    _speedMultiplier = multiplier;
    if (multiplier <= 0) {
      _isPaused = true;
    } else {
      _isPaused = false;
    }
    _persistSpeed();
    notifyListeners();
  }

  /// 暂停世界时间
  void pause() {
    if (!_config.allowPause) return;
    _isPaused = true;
    _persistPaused();
    notifyListeners();
  }

  /// 恢复世界时间
  void resume() {
    _isPaused = false;
    if (_speedMultiplier <= 0) {
      _speedMultiplier = _config.defaultSpeed;
    }
    _persistSpeed();
    _persistPaused();
    notifyListeners();
  }

  // ===================== 全域事件 =====================

  /// 全域事件流（UI 可监听）
  Stream<WorldEvent> get eventStream => _eventStreamController.stream;

  /// 最近触发的事件列表
  List<WorldEvent> get recentEvents => List.unmodifiable(_recentEvents);

  /// 是否是新年（1月1日）
  bool isNewYear() {
    return _worldTime.month == 1 && _worldTime.day == 1;
  }

  /// 今天是否是节日
  bool isHoliday() {
    return currentHoliday != null;
  }

  /// 当前节日名称（如果不是节日则为 null）
  String? get currentHoliday {
    for (final holiday in _builtinHolidays) {
      if (_worldTime.month == holiday.month &&
          _worldTime.day == holiday.day) {
        return holiday.name;
      }
    }
    return null;
  }

  /// 获取当前节日描述
  String? get currentHolidayDescription {
    for (final holiday in _builtinHolidays) {
      if (_worldTime.month == holiday.month &&
          _worldTime.day == holiday.day) {
        return holiday.description;
      }
    }
    return null;
  }

  // ===================== 时间格式化 =====================

  /// 格式化世界时间为字符串
  String formatWorldTime() {
    return '${_worldTime.year}年'
        '${_worldTime.month.toString().padLeft(2, '0')}月'
        '${_worldTime.day.toString().padLeft(2, '0')}日 '
        '${_worldTime.hour.toString().padLeft(2, '0')}:'
        '${_worldTime.minute.toString().padLeft(2, '0')}';
  }

  /// 获取世界纪元描述
  String get epochDescription {
    final daysSinceEpoch = _worldTime.difference(_config.epoch).inDays;
    return '世界纪元第 $daysSinceEpoch 天';
  }

  /// 获取世界时间的 prompt 上下文（注入 AI 对话）
  String getWorldTimePromptContext() {
    final buffer = StringBuffer();
    buffer.writeln('【世界时间】${formatWorldTime()}');
    buffer.writeln('【季节】$seasonLabel');
    buffer.writeln('【时段】$timeOfDayLabel');
    if (isNight) {
      buffer.writeln('现在是深夜，世界安静下来了。');
    }
    if (isHoliday()) {
      buffer.writeln('今天是$currentHoliday：$currentHolidayDescription');
    }

    // 最近事件
    if (_recentEvents.isNotEmpty) {
      final latest = _recentEvents.last;
      buffer.writeln('【最新世界事件】${latest.name}：${latest.description}');
    }

    return buffer.toString();
  }

  // ===================== 配置更新 =====================

  /// 更新配置
  Future<void> updateConfig(WorldTimeConfig newConfig) async {
    _config = newConfig;
    await _saveConfig();
    notifyListeners();
  }

  // ===================== 重置 =====================

  /// 重置世界到初始状态
  Future<void> reset() async {
    _worldTime = _config.epoch;
    _speedMultiplier = _config.defaultSpeed;
    _isPaused = false;
    _recentEvents.clear();
    _eventScheduler.reset();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPrefsWorldTime);
    await prefs.remove(_kPrefsSpeed);
    await prefs.remove(_kPrefsPaused);
    await prefs.remove(_kPrefsTriggeredEvents);

    notifyListeners();
  }

  // ===================== 持久化 =====================

  /// 持久化世界时间（异步，不阻塞）
  void _persistWorldTime() {
    SharedPreferences.getInstance().then((prefs) {
      prefs.setInt(_kPrefsWorldTime, _worldTime.millisecondsSinceEpoch);
    });
  }

  void _persistSpeed() {
    SharedPreferences.getInstance().then((prefs) {
      prefs.setDouble(_kPrefsSpeed, _speedMultiplier);
    });
  }

  void _persistPaused() {
    SharedPreferences.getInstance().then((prefs) {
      prefs.setBool(_kPrefsPaused, _isPaused);
    });
  }

  Future<void> _saveConfig() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPrefsConfig, jsonEncode(_config.toMap()));
  }

  // ===================== 清理 =====================

  @override
  void dispose() {
    _eventStreamController.close();
    super.dispose();
  }
}
