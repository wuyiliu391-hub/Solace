import 'package:flutter/foundation.dart';
import '../tool.dart';
import '../../device_service.dart';
import '../../accessibility_service.dart';

/// 应用信息工具包
///
/// 查询已安装应用、应用使用时间、当前前台应用
class AppInfoToolPkg extends ToolPkg {
  final DeviceService _device = DeviceService();
  final AccessibilityService _a11y = AccessibilityService();

  @override
  String get name => '应用信息';

  @override
  String get description => '查询应用列表、使用时间、前台应用';

  @override
  List<Tool> get tools => [
        _GetInstalledAppsTool(_device),
        _GetAppUsageTimeTool(_device),
        _GetCurrentAppTool(_a11y),
      ];
}

// ═══════════════════════════════════════════════
// 已安装应用列表
// ═══════════════════════════════════════════════

class _GetInstalledAppsTool extends Tool {
  final DeviceService _device;

  _GetInstalledAppsTool(this._device);

  @override
  String get name => 'get_installed_apps';

  @override
  String get description => '获取手机上安装的第三方应用列表';

  @override
  Map<String, dynamic> get parametersSchema => {
        'type': 'object',
        'properties': {
          'include_system': {
            'type': 'boolean',
            'description': '是否包含系统应用，默认 false',
          },
        },
      };

  @override
  Set<String> get requiredPermissions => {'shizuku'};

  @override
  bool get isDestructive => false;

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    final includeSystem = args['include_system'] as bool? ?? false;
    final flag = includeSystem ? '' : '-3';
    final result = await _device.shellExec('pm list packages $flag');
    if (!result.success && result.stderr.isNotEmpty) {
      return ToolResult.error('获取应用列表失败: ${result.stderr}');
    }
    final lines = result.stdout
        .split('\n')
        .where((l) => l.startsWith('package:'))
        .map((l) => l.replaceFirst('package:', '').trim())
        .where((l) => l.isNotEmpty)
        .toList();

    final buf = StringBuffer('找到 ${lines.length} 个${includeSystem ? '' : '第三方'}应用:\n');
    for (var i = 0; i < lines.length && i < 100; i++) {
      buf.writeln('${i + 1}. ${lines[i]}');
    }
    if (lines.length > 100) buf.writeln('...还有 ${lines.length - 100} 个');
    return ToolResult.success(buf.toString().trim(), data: {
      'count': lines.length,
      'packages': lines.take(100).toList(),
    });
  }
}

// ═══════════════════════════════════════════════
// 应用使用时间
// ═══════════════════════════════════════════════

class _GetAppUsageTimeTool extends Tool {
  final DeviceService _device;

  _GetAppUsageTimeTool(this._device);

  @override
  String get name => 'get_app_usage_time';

  @override
  String get description => '查询应用使用时间。不指定 app 则返回使用排行。';

  @override
  Map<String, dynamic> get parametersSchema => {
        'type': 'object',
        'properties': {
          'app': {
            'type': 'string',
            'description': '应用名称或包名，不填则返回所有应用排行',
          },
          'hours': {
            'type': 'integer',
            'description': '查询最近多少小时的数据，默认 24',
          },
        },
      };

  @override
  Set<String> get requiredPermissions => {'usage_stats'};

  @override
  bool get isDestructive => false;

  static const _packageMap = {
    '微信': 'com.tencent.mm', 'QQ': 'com.tencent.mobileqq',
    '微博': 'com.sina.weibo', '淘宝': 'com.taobao.taobao',
    '京东': 'com.jingdong.app.mall', '抖音': 'com.ss.android.ugc.aweme',
    '小红书': 'com.xingin.xhs', '知乎': 'com.zhihu.android',
    'bilibili': 'tv.danmaku.bili', '哔哩哔哩': 'tv.danmaku.bili', 'B站': 'tv.danmaku.bili',
    '支付宝': 'com.eg.android.AlipayGphone',
    '网易云音乐': 'com.netease.cloudmusic',
    'QQ音乐': 'com.tencent.qqmusic', '快手': 'com.smile.gifmaker',
  };

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    final app = args['app'] as String?;
    final hours = (args['hours'] as num?)?.toInt() ?? 24;

    String? pkgName;
    if (app != null && app.isNotEmpty) {
      if (app.contains('.')) {
        pkgName = app;
      } else if (_packageMap.containsKey(app)) {
        pkgName = _packageMap[app];
      } else {
        final lower = app.toLowerCase();
        pkgName = _packageMap.entries
            .firstWhere((e) => e.key.toLowerCase() == lower,
                orElse: () => const MapEntry('', ''))
            .value;
        if (pkgName == null || pkgName.isEmpty) {
          return ToolResult.error('无法识别应用: $app');
        }
      }
    }

    final usageResult = await _device.getAppUsageTime(
      packageName: pkgName,
      sinceHours: hours,
      limit: 10,
      includeSystemApps: false,
    );

    if (usageResult == null || usageResult['success'] != true) {
      final err = usageResult != null
          ? (usageResult['error'] as String? ?? '未知错误')
          : '调用失败';
      if (err == 'NO_PERMISSION') {
        return ToolResult.error(
          '需要「使用情况访问」权限，请在系统设置中授予 Solace 使用情况访问权限',
          needsPermission: true,
          permissionName: '使用情况访问',
        );
      }
      return ToolResult.error('读取使用时间失败: $err');
    }

    final entries = usageResult['entries'] as List<dynamic>? ?? [];
    if (entries.isEmpty) {
      return ToolResult.success(
        app != null ? '最近 ${hours} 小时内没有 $app 的使用记录' : '最近 ${hours} 小时内没有应用使用记录',
      );
    }

    final buf = StringBuffer();
    if (pkgName != null && entries.isNotEmpty) {
      final e = entries.first as Map<dynamic, dynamic>;
      final ms = e['totalForegroundTimeMs'] as num;
      final m = ms.toInt();
      final h = m ~/ 3600000;
      final min = (m % 3600000) ~/ 60000;
      buf.write('${e['appName']} 最近 ${hours} 小时使用时间: ');
      if (h > 0) buf.write('${h}小时');
      if (min > 0 || h == 0) buf.write('${min}分钟');
    } else {
      buf.writeln('最近 ${hours} 小时应用使用排行:');
      var rank = 1;
      for (final e in entries) {
        if (e is! Map<dynamic, dynamic>) continue;
        final ms = e['totalForegroundTimeMs'] as num;
        final h = ms.toInt() ~/ 3600000;
        final min = (ms.toInt() % 3600000) ~/ 60000;
        final time = h > 0 ? '${h}时${min}分' : '${min}分钟';
        buf.writeln('$rank. ${e['appName']} — $time');
        rank++;
      }
    }
    return ToolResult.success(buf.toString().trim());
  }
}

// ═══════════════════════════════════════════════
// 当前前台应用
// ═══════════════════════════════════════════════

class _GetCurrentAppTool extends Tool {
  final AccessibilityService _a11y;

  _GetCurrentAppTool(this._a11y);

  @override
  String get name => 'get_current_app';

  @override
  String get description => '获取当前前台显示的应用';

  @override
  Map<String, dynamic> get parametersSchema => {
        'type': 'object',
        'properties': {},
      };

  @override
  Set<String> get requiredPermissions => {'accessibility'};

  @override
  bool get isDestructive => false;

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    try {
      final info = await _a11y.getCurrentApp();
      final name = info.displayName.isNotEmpty ? info.displayName : info.packageName;
      return ToolResult.success(
        '当前应用: $name',
        data: {
          'packageName': info.packageName,
          'displayName': name,
        },
      );
    } catch (e) {
      return ToolResult.error('获取前台应用失败: $e');
    }
  }
}
