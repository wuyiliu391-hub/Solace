import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 单个应用在时间窗内的前台使用情况（只含包名 + 时长，无任何应用内内容）
class AppUsage {
  final String packageName;
  final int totalMs;
  final int lastUsed;

  const AppUsage(this.packageName, this.totalMs, this.lastUsed);

  Duration get duration => Duration(milliseconds: totalMs);
}

/// 作息陪伴服务 — 纯本地。
///
/// 能力边界（严格）：
///   • lockNow：本地触发锁屏（DeviceAdmin force-lock），用户 PIN 秒解、可撤销。
///   • queryUsage：读「前台 App 名 + 时长」（UsageStatsManager 数字健康接口），
///     读不到任何应用内文字/内容。
///
/// 不做、也没有能力做：数据上传、远程指令、读屏、模拟点击、跨 App 操作。
/// 所有采集结果只在本地内存/本地存储中使用，从不离开设备。
class WellbeingService {
  static const _channel = MethodChannel('com.solace.solace/wellbeing');

  // ─── 本地闸配置的存储键 ───
  static const _kEnabled = 'wellbeing_enabled';
  static const _kBedStartMin = 'wellbeing_bed_start_min'; // 就寝起点（当天分钟数）
  static const _kBedEndMin = 'wellbeing_bed_end_min';     // 就寝终点（当天分钟数）
  static const _kMaxUsageMin = 'wellbeing_max_usage_min'; // 连续使用上限（分钟）
  static const _kLockOnBedtime = 'wellbeing_lock_bedtime';
  static const _kLockOnOveruse = 'wellbeing_lock_overuse';

  // ─── 平台能力封装 ───

  /// 是否已授予设备管理员（仅锁屏）
  Future<bool> isAdminActive() async {
    if (!_isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('isAdminActive') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 拉起系统设备管理员授权页（用户主动同意才生效）
  Future<void> requestAdmin() async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod('requestAdmin');
    } catch (_) {}
  }

  /// 本地触发锁屏。仅在已授权时有效。返回是否成功。
  Future<bool> lockNow() async {
    if (!_isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('lockNow') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 是否已授予「使用情况访问」
  Future<bool> hasUsageAccess() async {
    if (!_isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('hasUsageAccess') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 拉起系统「使用情况访问」授权页
  Future<void> requestUsageAccess() async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod('requestUsageAccess');
    } catch (_) {}
  }

  /// 查询最近 [windowMinutes] 分钟的前台使用（按包名聚合）
  Future<List<AppUsage>> queryUsage({int windowMinutes = 30}) async {
    if (!_isAndroid) return const [];
    try {
      final raw = await _channel.invokeMethod<String>(
        'queryUsage',
        {'windowMinutes': windowMinutes},
      );
      if (raw == null || raw.isEmpty) return const [];
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => AppUsage(
                e['packageName'] as String? ?? '',
                (e['totalMs'] as num?)?.toInt() ?? 0,
                (e['lastUsed'] as num?)?.toInt() ?? 0,
              ))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  // 本地闸配置与判定逻辑在下方追加。
  // WELLBEING_GATE_PLACEHOLDER
}

/// 本地闸的一次判定结果
class GateDecision {
  final bool allow;      // 是否放行锁屏
  final String reason;   // 供 UI/日志说明的原因

  const GateDecision(this.allow, this.reason);

  static const denied = GateDecision(false, '');
}

/// 本地闸配置
class WellbeingConfig {
  final bool enabled;
  final int bedStartMin;  // 就寝时段起点（0-1439，当天分钟数）
  final int bedEndMin;    // 就寝时段终点（可跨零点）
  final int maxUsageMin;  // 连续使用上限（分钟）
  final bool lockOnBedtime;
  final bool lockOnOveruse;

  const WellbeingConfig({
    this.enabled = false,
    this.bedStartMin = 23 * 60, // 默认 23:00
    this.bedEndMin = 6 * 60,    // 默认 06:00
    this.maxUsageMin = 90,
    this.lockOnBedtime = true,
    this.lockOnOveruse = false,
  });
}

extension WellbeingGate on WellbeingService {
  Future<WellbeingConfig> loadConfig() async {
    final p = await SharedPreferences.getInstance();
    return WellbeingConfig(
      enabled: p.getBool(WellbeingService._kEnabled) ?? false,
      bedStartMin: p.getInt(WellbeingService._kBedStartMin) ?? 23 * 60,
      bedEndMin: p.getInt(WellbeingService._kBedEndMin) ?? 6 * 60,
      maxUsageMin: p.getInt(WellbeingService._kMaxUsageMin) ?? 90,
      lockOnBedtime: p.getBool(WellbeingService._kLockOnBedtime) ?? true,
      lockOnOveruse: p.getBool(WellbeingService._kLockOnOveruse) ?? false,
    );
  }

  Future<void> saveConfig(WellbeingConfig c) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(WellbeingService._kEnabled, c.enabled);
    await p.setInt(WellbeingService._kBedStartMin, c.bedStartMin);
    await p.setInt(WellbeingService._kBedEndMin, c.bedEndMin);
    await p.setInt(WellbeingService._kMaxUsageMin, c.maxUsageMin);
    await p.setBool(WellbeingService._kLockOnBedtime, c.lockOnBedtime);
    await p.setBool(WellbeingService._kLockOnOveruse, c.lockOnOveruse);
  }

  /// 判断当前时刻是否落在就寝时段内（支持跨零点）
  bool _inBedtime(WellbeingConfig c, DateTime now) {
    final nowMin = now.hour * 60 + now.minute;
    if (c.bedStartMin <= c.bedEndMin) {
      return nowMin >= c.bedStartMin && nowMin < c.bedEndMin;
    }
    // 跨零点：如 23:00 → 06:00
    return nowMin >= c.bedStartMin || nowMin < c.bedEndMin;
  }

  /// 本地闸核心：决定是否放行锁屏。
  ///
  /// [aiSuggests] = true  → AI 在对话中发出了 [rest_suggest]，规则命中即放行
  /// [aiSuggests] = false → 心跳定时检查，规则命中同样放行（自动模式）
  ///
  /// 真正放行必须同时满足：
  ///   1. 本地功能已开启；2. 设备管理员已授权；
  ///   3. 命中某条本地规则（就寝时段 / 连续使用超限）。
  /// 外部端点（含 AI）无法绕过本地闸——零上传、零远控。
  Future<GateDecision> evaluate({required bool aiSuggests}) async {
    final c = await loadConfig();
    if (!c.enabled) return const GateDecision(false, '作息陪伴未开启');
    if (!await isAdminActive()) return const GateDecision(false, '设备管理员权限未授权');

    final now = DateTime.now();

    // 规则一：就寝时段（自动 + AI 双路触发）
    if (c.lockOnBedtime && _inBedtime(c, now)) {
      final h = now.hour.toString().padLeft(2, '0');
      final m = now.minute.toString().padLeft(2, '0');
      return GateDecision(true, '当前 $h:$m 处于就寝时段');
    }

    // 规则二：连续使用超限（读本地 UsageStats，纯本地判定）
    if (c.lockOnOveruse) {
      final usage = await queryUsage(windowMinutes: c.maxUsageMin);
      final totalMs = usage.fold<int>(0, (sum, u) => sum + u.totalMs);
      if (totalMs >= c.maxUsageMin * 60 * 1000) {
        return GateDecision(true, '连续使用已超 ${c.maxUsageMin} 分钟');
      }
      // 还没到上限，告诉调用方已用了多少
      final usedMin = (totalMs / 60000).floor();
      return GateDecision(false, '已连续使用 $usedMin 分钟，上限 ${c.maxUsageMin} 分钟');
    }

    return const GateDecision(false, '未命中任何规则');
  }

  /// 提议 → 判定 → （放行则）本地锁屏。返回实际是否锁屏。
  Future<GateDecision> maybeLock({required bool aiSuggests}) async {
    final decision = await evaluate(aiSuggests: aiSuggests);
    if (decision.allow) {
      await lockNow();
    }
    return decision;
  }
}

