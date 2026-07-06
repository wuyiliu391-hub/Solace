import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/constants.dart';

/// Token 预算监控服务
///
/// 追踪新世界模式下的 token 消耗，提供预算告警和用量统计。
/// 由 CoreHub 持有，单例模式不需要——通过 CoreHub.instance 访问。
class TokenBudgetService {
  final SharedPreferences _prefs;

  int _dailyConsumed = 0;
  int _totalConsumed = 0;
  DateTime? _lastResetDate;

  /// 每日 token 预算上限（超过后触发告警，不阻断）
  int dailyBudgetLimit = 50000;

  /// 每次心跳周期的 token 预算上限
  int cycleBudgetLimit = 5000;

  int _cycleConsumed = 0;

  TokenBudgetService(this._prefs);

  /// 初始化：从持久化恢复状态
  Future<void> init() async {
    _totalConsumed =
        _prefs.getInt(PrefKeys.coreHubNewWorldTokenConsumed) ?? 0;

    final todayStr = _todayKey();
    final savedDate = _prefs.getString('token_budget_last_reset_date');
    if (savedDate == todayStr) {
      _dailyConsumed = _prefs.getInt('token_budget_daily_$todayStr') ?? 0;
    } else {
      _dailyConsumed = 0;
      await _prefs.setString('token_budget_last_reset_date', todayStr);
      await _prefs.setInt('token_budget_daily_$todayStr', 0);
    }
    _lastResetDate = DateTime.now();
  }

  /// 记录 token 消耗
  Future<void> consume(int tokens) async {
    _dailyConsumed += tokens;
    _totalConsumed += tokens;
    _cycleConsumed += tokens;

    final todayStr = _todayKey();
    await _prefs.setInt('token_budget_daily_$todayStr', _dailyConsumed);
    await _prefs.setInt(PrefKeys.coreHubNewWorldTokenConsumed, _totalConsumed);

    if (_dailyConsumed > dailyBudgetLimit) {
      debugPrint(
        'TokenBudget: 日预算超限 $_dailyConsumed / $dailyBudgetLimit',
      );
    }
  }

  /// 重置周期消耗（每次心跳周期结束时调用）
  void resetCycle() {
    _cycleConsumed = 0;
  }

  /// 检查是否还有周期预算
  bool get hasCycleBudget => _cycleConsumed < cycleBudgetLimit;

  /// 检查是否还有日预算
  bool get hasDailyBudget => _dailyConsumed < dailyBudgetLimit;

  /// 当日已消耗
  int get dailyConsumed => _dailyConsumed;

  /// 总消耗
  int get totalConsumed => _totalConsumed;

  /// 本周期已消耗
  int get cycleConsumed => _cycleConsumed;

  /// 日预算使用率 (0.0 ~ 1.0+)
  double get dailyUsageRate => _dailyConsumed / dailyBudgetLimit;

  /// 获取今日 key
  String _todayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  /// 重置日预算（每天凌晨自动或手动调用）
  Future<void> resetDaily() async {
    _dailyConsumed = 0;
    _cycleConsumed = 0;
    final todayStr = _todayKey();
    await _prefs.setInt('token_budget_daily_$todayStr', 0);
    await _prefs.setString('token_budget_last_reset_date', todayStr);
  }

  /// 获取预算状态摘要
  Map<String, dynamic> getSummary() {
    return {
      'dailyConsumed': _dailyConsumed,
      'dailyLimit': dailyBudgetLimit,
      'dailyUsageRate': dailyUsageRate.toStringAsFixed(2),
      'cycleConsumed': _cycleConsumed,
      'cycleLimit': cycleBudgetLimit,
      'totalConsumed': _totalConsumed,
      'hasDailyBudget': hasDailyBudget,
      'hasCycleBudget': hasCycleBudget,
    };
  }
}
