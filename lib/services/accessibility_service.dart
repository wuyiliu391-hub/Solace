import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

/// 无障碍服务 — Flutter 桥接层
///
/// 仅负责：
/// - 权限状态查询与引导
/// - 当前窗口 UI 树读取（完整 XML 与简化信息）
/// - 当前前台应用信息
///
/// 所有执行类操作（点击、滑动、按键、打开应用、系统控制）已迁移到 DeviceService / Shizuku。
class AccessibilityService {
  static const _channel = MethodChannel('com.solace.solace/accessibility');

  // ═══════════════════════════════════
  // 权限管理
  // ═══════════════════════════════════

  /// 检查无障碍服务是否已启用（实例是否存活）
  Future<bool> isEnabled() async {
    try {
      final result = await _channel.invokeMethod<bool>('isEnabled');
      return result ?? false;
    } catch (e) {
      debugPrint('AccessibilityService.isEnabled error: $e');
      return false;
    }
  }

  /// 打开系统无障碍设置页面（引导用户手动开启）
  Future<bool> requestAccess() async {
    try {
      final result = await _channel.invokeMethod<bool>('requestAccess');
      return result ?? false;
    } catch (e) {
      debugPrint('AccessibilityService.requestAccess error: $e');
      return false;
    }
  }

  // ═══════════════════════════════════
  // 双重检测 + 保活 (v2)
  // ═══════════════════════════════════

  /// 执行双重无障碍状态检测（Settings开关 + 运行列表 + 实例存活）
  Future<AccessibilityDualCheckResult> performDualCheck() async {
    try {
      final result = await _channel
          .invokeMethod<Map<dynamic, dynamic>>('performDualCheck');
      if (result == null) {
        return const AccessibilityDualCheckResult(
          isSettingsEnabled: false,
          isServiceInList: false,
          isServiceInstanceAlive: false,
          vendor: VendorInfo.unknown,
          suggestedAction: SuggestedAccessibilityAction.notEnabled,
        );
      }
      return AccessibilityDualCheckResult(
        isSettingsEnabled: (result['isSettingsEnabled'] as bool?) ?? false,
        isServiceInList: (result['isServiceInList'] as bool?) ?? false,
        isServiceInstanceAlive:
            (result['isServiceInstanceAlive'] as bool?) ?? false,
        vendor:
            VendorInfo.fromString((result['vendor'] as String?) ?? 'UNKNOWN'),
        suggestedAction: SuggestedAccessibilityAction.fromString(
          (result['suggestedAction'] as String?) ?? 'NOT_ENABLED',
        ),
      );
    } catch (e) {
      debugPrint('AccessibilityService.performDualCheck error: $e');
      return const AccessibilityDualCheckResult(
        isSettingsEnabled: false,
        isServiceInList: false,
        isServiceInstanceAlive: false,
        vendor: VendorInfo.unknown,
        suggestedAction: SuggestedAccessibilityAction.notEnabled,
      );
    }
  }

  /// 获取保活状态摘要
  Future<KeepAliveStatus> getKeepAliveStatus() async {
    try {
      final result = await _channel
          .invokeMethod<Map<dynamic, dynamic>>('getKeepAliveStatus');
      if (result == null) {
        return const KeepAliveStatus(
          isBatteryOptimized: true,
          isAutoStartLikelyOk: false,
          vendorFriendlyName: '未知',
        );
      }
      return KeepAliveStatus(
        isBatteryOptimized: (result['isBatteryOptimized'] as bool?) ?? false,
        isAutoStartLikelyOk: (result['isAutoStartLikelyOk'] as bool?) ?? false,
        vendorFriendlyName: (result['vendorFriendlyName'] as String?) ?? '未知',
      );
    } catch (e) {
      debugPrint('AccessibilityService.getKeepAliveStatus error: $e');
      return const KeepAliveStatus(
        isBatteryOptimized: true,
        isAutoStartLikelyOk: false,
        vendorFriendlyName: '未知',
      );
    }
  }

  /// 检查电池优化是否已忽略
  Future<bool> isIgnoringBatteryOptimizations() async {
    try {
      final result =
          await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations');
      return result ?? false;
    } catch (e) {
      debugPrint(
          'AccessibilityService.isIgnoringBatteryOptimizations error: $e');
      return false;
    }
  }

  /// 跳转到电池优化设置
  Future<bool> openBatteryOptimizationSettings() async {
    try {
      final result =
          await _channel.invokeMethod<bool>('openBatteryOptimizationSettings');
      return result ?? false;
    } catch (e) {
      debugPrint(
          'AccessibilityService.openBatteryOptimizationSettings error: $e');
      return false;
    }
  }

  /// 跳转到各厂商的自启动设置页
  Future<bool> openAutoStartSettings() async {
    try {
      final result = await _channel.invokeMethod<bool>('openAutoStartSettings');
      return result ?? false;
    } catch (e) {
      debugPrint('AccessibilityService.openAutoStartSettings error: $e');
      return false;
    }
  }

  /// 跳转到应用详情设置页
  Future<bool> openAppDetailsSettings() async {
    try {
      final result =
          await _channel.invokeMethod<bool>('openAppDetailsSettings');
      return result ?? false;
    } catch (e) {
      debugPrint('AccessibilityService.openAppDetailsSettings error: $e');
      return false;
    }
  }

  /// 获取具体厂商信息
  Future<VendorInfo> getVendorInfo() async {
    try {
      final result =
          await _channel.invokeMethod<Map<dynamic, dynamic>>('getVendorInfo');
      return VendorInfo.fromString((result?['vendor'] as String?) ?? 'UNKNOWN');
    } catch (e) {
      return VendorInfo.unknown;
    }
  }

  /// 引导用户解决"已授权但冻结"问题：先关再开
  Future<bool> openAccessibilitySettingsForToggle() async {
    return requestAccess();
  }

  // ═══════════════════════════════════
  // 屏幕感知（唯一职责）
  // ═══════════════════════════════════

  /// 获取当前窗口的完整 UI 层次结构（XML 格式）
  Future<String> getUiHierarchy() async {
    try {
      final result = await _channel.invokeMethod<String>('getUiHierarchy');
      return result ?? '';
    } catch (e) {
      debugPrint('AccessibilityService.getUiHierarchy error: $e');
      return '';
    }
  }

  /// 获取简化版 UI 信息：当前应用 + 可交互元素列表
  Future<SimplifiedUiInfo?> getSimplifiedUiInfo() async {
    try {
      final result = await _channel
          .invokeMethod<Map<dynamic, dynamic>>('getSimplifiedUiInfo');
      if (result == null) return null;
      return SimplifiedUiInfo.fromMap(result);
    } catch (e) {
      debugPrint('AccessibilityService.getSimplifiedUiInfo error: $e');
      return null;
    }
  }

  /// 获取当前前台应用信息
  Future<CurrentAppInfo> getCurrentApp() async {
    try {
      final result =
          await _channel.invokeMethod<Map<dynamic, dynamic>>('getCurrentApp');
      if (result == null) return const CurrentAppInfo();
      return CurrentAppInfo(
        packageName: (result['packageName'] as String?) ?? '',
        activityName: (result['activityName'] as String?) ?? '',
      );
    } catch (e) {
      debugPrint('AccessibilityService.getCurrentApp error: $e');
      return const CurrentAppInfo();
    }
  }
}

/// 简化版 UI 信息
class SimplifiedUiInfo {
  final String packageName;
  final String activityName;
  final List<UiElement> elements;

  const SimplifiedUiInfo({
    required this.packageName,
    required this.activityName,
    required this.elements,
  });

  factory SimplifiedUiInfo.fromMap(Map<dynamic, dynamic> map) {
    final rawElements = map['elements'] as List<dynamic>? ?? [];
    return SimplifiedUiInfo(
      packageName: (map['packageName'] as String?) ?? '',
      activityName: (map['activityName'] as String?) ?? '',
      elements: rawElements.map((e) => UiElement.fromMap(e)).toList(),
    );
  }

  /// 格式化为 AI 可读的文本
  String toDisplayString() {
    final app = AccessibilityServiceHelper.appNameFromPackage(packageName);
    final buf = StringBuffer();
    buf.writeln('当前应用：$app ($packageName)');
    buf.writeln('可交互元素：');
    for (final e in elements) {
      buf.writeln('  - ${e.toShortString()}');
    }
    return buf.toString();
  }
}

/// UI 元素
class UiElement {
  final String className;
  final String text;
  final String contentDesc;
  final String resourceId;
  final bool clickable;
  final bool focusable;
  final bool editable;
  final Map<String, int> bounds; // {left, top, right, bottom}

  const UiElement({
    required this.className,
    this.text = '',
    this.contentDesc = '',
    this.resourceId = '',
    this.clickable = false,
    this.focusable = false,
    this.editable = false,
    this.bounds = const {},
  });

  factory UiElement.fromMap(Map<dynamic, dynamic> map) {
    final rawBounds = map['bounds'] as Map<dynamic, dynamic>? ?? {};
    return UiElement(
      className: (map['class'] as String?) ?? '',
      text: (map['text'] as String?) ?? '',
      contentDesc: (map['contentDesc'] as String?) ?? '',
      resourceId: (map['resourceId'] as String?) ?? '',
      clickable: map['clickable'] as bool? ?? false,
      focusable: map['focusable'] as bool? ?? false,
      editable: map['editable'] as bool? ?? false,
      bounds:
          rawBounds.map((k, v) => MapEntry(k.toString(), (v as num).toInt())),
    );
  }

  int get centerX {
    final l = bounds['left'] ?? 0;
    final r = bounds['right'] ?? 0;
    return (l + r) ~/ 2;
  }

  int get centerY {
    final t = bounds['top'] ?? 0;
    final b = bounds['bottom'] ?? 0;
    return (t + b) ~/ 2;
  }

  String toShortString() {
    final label = text.isNotEmpty ? text : contentDesc;
    final action = clickable ? '[可点击]' : (editable ? '[可输入]' : '');
    final fallback =
        resourceId.split('/').lastOrNull ?? className.split('.').last;
    return '$action ${label.isNotEmpty ? label : fallback} @($centerX,$centerY)';
  }
}

/// 当前前台应用
class CurrentAppInfo {
  final String packageName;
  final String activityName;

  const CurrentAppInfo({this.packageName = '', this.activityName = ''});

  String get displayName =>
      AccessibilityServiceHelper.appNameFromPackage(packageName);
  bool get isUnknown => packageName.isEmpty;
}

/// 双重检测结果
class AccessibilityDualCheckResult {
  final bool isSettingsEnabled;
  final bool isServiceInList;
  final bool isServiceInstanceAlive;
  final VendorInfo vendor;
  final SuggestedAccessibilityAction suggestedAction;

  const AccessibilityDualCheckResult({
    required this.isSettingsEnabled,
    required this.isServiceInList,
    required this.isServiceInstanceAlive,
    required this.vendor,
    required this.suggestedAction,
  });

  /// 是否真正可用
  bool get isActuallyUsable => isSettingsEnabled && isServiceInstanceAlive;

  /// 是否需要引导用户重新开关
  bool get needsRetoggle => isSettingsEnabled && !isServiceInstanceAlive;

  /// 是否需要引导用户去设置页开启
  bool get needsEnable => !isSettingsEnabled;

  @override
  String toString() =>
      'AccessibilityDualCheckResult(settings=$isSettingsEnabled, inList=$isServiceInList, '
      'alive=$isServiceInstanceAlive, vendor=$vendor, action=$suggestedAction)';
}

/// 建议操作
enum SuggestedAccessibilityAction {
  allGood,
  enabledButFrozen,
  notEnabled,
  bindingInProgress;

  static SuggestedAccessibilityAction fromString(String s) => switch (s) {
        'ALL_GOOD' => allGood,
        'ENABLED_BUT_FROZEN' => enabledButFrozen,
        'NOT_ENABLED' => notEnabled,
        'BINDING_IN_PROGRESS' => bindingInProgress,
        _ => notEnabled,
      };
}

/// 厂商信息
enum VendorInfo {
  xiaomi,
  huawei,
  honor,
  oppo,
  vivo,
  samsung,
  google,
  unknown;

  static VendorInfo fromString(String s) => switch (s.toUpperCase()) {
        'XIAOMI' => xiaomi,
        'HUAWEI' => huawei,
        'HONOR' => honor,
        'OPPO' => oppo,
        'VIVO' => vivo,
        'SAMSUNG' => samsung,
        'GOOGLE' => google,
        _ => unknown,
      };

  String get friendlyName => switch (this) {
        xiaomi => '小米/HyperOS',
        huawei => '华为/鸿蒙',
        honor => '荣耀/MagicOS',
        oppo => 'OPPO/ColorOS',
        vivo => 'vivo/OriginOS',
        samsung => '三星/OneUI',
        google => '原生Android',
        unknown => '未知系统',
      };

  /// 该厂商是否需要特别关注保活
  bool get needsKeepAliveAttention => this != google && this != samsung;

  /// 该厂商是否容易出现"开关保留但服务冻结"（现象①）
  bool get proneToFreeze => this == huawei || this == xiaomi || this == honor;

  /// 该厂商是否容易出现"上滑后开关被关闭"（现象②）
  bool get proneToAutoDisable => this == oppo || this == vivo;
}

/// 保活状态
class KeepAliveStatus {
  final bool isBatteryOptimized;
  final bool isAutoStartLikelyOk;
  final String vendorFriendlyName;

  const KeepAliveStatus({
    required this.isBatteryOptimized,
    required this.isAutoStartLikelyOk,
    required this.vendorFriendlyName,
  });
}

/// 辅助方法
class AccessibilityServiceHelper {
  static String appNameFromPackage(String pkg) {
    return switch (pkg) {
      'com.tencent.mm' => '微信',
      'com.tencent.mobileqq' => 'QQ',
      'com.tencent.wework' => '企业微信',
      'com.alibaba.android.rimet' => '钉钉',
      'com.ss.android.ugc.aweme' => '抖音',
      'com.xingin.xhs' => '小红书',
      'com.taobao.taobao' => '淘宝',
      'com.jingdong.app.mall' => '京东',
      'com.android.mms' => '短信',
      'com.android.phone' => '电话',
      'com.android.settings' => '设置',
      'com.android.chrome' => 'Chrome',
      'com.eg.android.AlipayGphone' => '支付宝',
      'com.sina.weibo' => '微博',
      'com.zhihu.android' => '知乎',
      'com.netease.cloudmusic' => '网易云音乐',
      'tv.danmaku.bili' => 'B站',
      'com.douban.frodo' => '豆瓣',
      'com.solace.solace' => 'Solace',
      'com.android.launcher' => '桌面',
      _ => pkg.split('.').last,
    };
  }
}
