import 'package:shared_preferences/shared_preferences.dart';

/// 场景引擎 — 给对话一个真实的背景锚点
///
/// 核心理念：真人聊天永远有背景——"在哪、在做什么、氛围是什么"。
/// 没有场景时 AI 活在白色盒子里；有场景时它知道自己此刻的处境。
///
/// 数据流：
///   用户/系统设置 ScenarioContext
///     → 持久化到 SharedPreferences（key: scenario_{characterId}_{userId}）
///     → AIService._buildSystemPrompt 读取并注入
///
/// 生命周期：
///   - 手动设置的场景：用户主动清除或超过 [_maxAgeHours] 小时后自动失效
///   - 基于位置自动填充的场景：每次打开对话时刷新
class ScenarioService {
  final SharedPreferences _prefs;

  ScenarioService(this._prefs);

  static Future<ScenarioService> create() async {
    final prefs = await SharedPreferences.getInstance();
    return ScenarioService(prefs);
  }

  String _key(String characterId, String userId) =>
      'scenario_${characterId}_$userId';

  /// 获取当前场景（已过期则返回 null）
  ScenarioContext? getScenario(String characterId, String userId) {
    final raw = _prefs.getString(_key(characterId, userId));
    if (raw == null) return null;
    try {
      final ctx = ScenarioContext.fromJson(raw);
      if (ctx.isExpired) {
        clearScenario(characterId, userId);
        return null;
      }
      return ctx;
    } catch (_) {
      return null;
    }
  }

  /// 保存/更新场景
  Future<void> setScenario(
      String characterId, String userId, ScenarioContext ctx) async {
    await _prefs.setString(_key(characterId, userId), ctx.toJson());
  }

  /// 清除场景（用户主动结束或超时）
  Future<void> clearScenario(String characterId, String userId) async {
    await _prefs.remove(_key(characterId, userId));
  }

  /// 构建注入 system prompt 的场景段落
  ///
  /// 返回空字符串表示无场景，调用方直接跳过注入。
  String buildScenarioPrompt(String characterId, String userId) {
    final ctx = getScenario(characterId, userId);
    if (ctx == null) return '';

    final buf = StringBuffer();
    buf.writeln('\n【当前场景】');
    buf.writeln('请将以下背景作为你此刻真实的处境，让它自然地影响你的感受和回复方式：');

    if (ctx.where != null && ctx.where!.isNotEmpty) {
      buf.writeln('- 你现在在：${ctx.where}');
    }
    if (ctx.doing != null && ctx.doing!.isNotEmpty) {
      buf.writeln('- 你正在：${ctx.doing}');
    }
    if (ctx.mood != null && ctx.mood!.isNotEmpty) {
      buf.writeln('- 氛围/心境：${ctx.mood}');
    }
    if (ctx.withUser) {
      buf.writeln('- 对方也在场，你们在一起');
    }
    if (ctx.extra != null && ctx.extra!.isNotEmpty) {
      buf.writeln('- 补充：${ctx.extra}');
    }

    buf.writeln(
        '请不要直接说出"我正在…"这种自我介绍式的陈述，让场景悄悄渗透进你的话语里。');

    return buf.toString();
  }

  /// 从位置信息自动生成场景（轻量版，不覆盖手动设置的场景）
  Future<void> autoFillFromLocation({
    required String characterId,
    required String userId,
    required String placeName,
    required String placeType,
    required String activity,
    required String emotion,
  }) async {
    // 如果已有手动设置的场景，不覆盖
    final existing = getScenario(characterId, userId);
    if (existing != null && existing.isManual) return;

    final ctx = ScenarioContext(
      where: _formatLocation(placeName, placeType),
      doing: activity,
      mood: emotion,
      withUser: false,
      isManual: false,
      setAt: DateTime.now(),
    );
    await setScenario(characterId, userId, ctx);
  }

  String _formatLocation(String placeName, String placeType) {
    const typeLabels = {
      'office': '公司',
      'cafe': '咖啡厅',
      'restaurant': '餐厅',
      'mall': '商场',
      'park': '公园',
      'cinema': '电影院',
      'gym': '健身房',
      'bookstore': '书店',
      'home': '家',
      'transit': '路上',
    };
    final label = typeLabels[placeType] ?? placeType;
    return '$placeName（$label）';
  }
}

/// 场景上下文数据模型
class ScenarioContext {
  final String? where;   // 地点描述，如"星巴克万达广场店"
  final String? doing;   // 正在做什么，如"等朋友，喝咖啡"
  final String? mood;    // 氛围/心境，如"慵懒的下午"
  final bool withUser;   // 用户是否也在同一场景
  final String? extra;   // 额外补充
  final bool isManual;   // 是否手动设置（决定是否被位置自动覆盖）
  final DateTime setAt;  // 设置时间（用于过期检测）

  static const int _maxAgeHours = 8;

  const ScenarioContext({
    this.where,
    this.doing,
    this.mood,
    this.withUser = false,
    this.extra,
    this.isManual = true,
    required this.setAt,
  });

  bool get isExpired =>
      DateTime.now().difference(setAt).inHours >= _maxAgeHours;

  bool get isEmpty =>
      (where == null || where!.isEmpty) &&
      (doing == null || doing!.isEmpty) &&
      (mood == null || mood!.isEmpty);

  String toJson() {
    return [
      where ?? '',
      doing ?? '',
      mood ?? '',
      withUser ? '1' : '0',
      extra ?? '',
      isManual ? '1' : '0',
      setAt.millisecondsSinceEpoch.toString(),
    ].join('\x00'); // null byte 分隔，避免内容中的逗号引起解析问题
  }

  factory ScenarioContext.fromJson(String raw) {
    final parts = raw.split('\x00');
    if (parts.length < 7) throw const FormatException('invalid scenario');
    return ScenarioContext(
      where: parts[0].isEmpty ? null : parts[0],
      doing: parts[1].isEmpty ? null : parts[1],
      mood: parts[2].isEmpty ? null : parts[2],
      withUser: parts[3] == '1',
      extra: parts[4].isEmpty ? null : parts[4],
      isManual: parts[5] == '1',
      setAt: DateTime.fromMillisecondsSinceEpoch(int.parse(parts[6])),
    );
  }

  ScenarioContext copyWith({
    String? where,
    String? doing,
    String? mood,
    bool? withUser,
    String? extra,
    bool? isManual,
    DateTime? setAt,
  }) {
    return ScenarioContext(
      where: where ?? this.where,
      doing: doing ?? this.doing,
      mood: mood ?? this.mood,
      withUser: withUser ?? this.withUser,
      extra: extra ?? this.extra,
      isManual: isManual ?? this.isManual,
      setAt: setAt ?? this.setAt,
    );
  }
}
