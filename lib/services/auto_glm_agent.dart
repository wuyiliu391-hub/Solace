import 'package:flutter/foundation.dart';

import 'accessibility_service.dart';
import 'device_service.dart';

/// 设备自动化代理 — 纯 API 驱动，无视觉循环
///
/// 所有操作通过 Shizuku shell 或 Android 系统 API 直接执行，
/// 不需要截图、不需要视觉模型、不需要 UI 交互循环。
class AutoGlmAgent {
  final AccessibilityService _a11y = AccessibilityService();
  final DeviceService _device = DeviceService();

  bool _cancelled = false;

  /// 是否已取消
  bool get isCancelled => _cancelled;

  /// 取消执行
  void cancel() => _cancelled = true;

  /// 重置状态
  void reset() {
    _cancelled = false;
  }

  /// 执行用户的任务
  ///
  /// [onStep] 每步回调，用于 UI 更新
  Future<AutoGlmResult> run({
    required String task,
    Future<void> Function(AutoGlmStep step)? onStep,
  }) async {
    reset();

    // Shizuku 是唯一的设备执行通道
    final shizukuStatus = await _device.getShizukuStatus();
    final shizukuReady = shizukuStatus['available'] == true &&
        shizukuStatus['permitted'] == true;
    if (!shizukuReady) {
      return const AutoGlmResult(
        success: false,
        message: 'Shizuku不可用，无法执行设备自动化\n请启动Shizuku并授予Solace权限',
      );
    }

    // 识别系统操作任务，直接执行
    final sysAction = _matchSystemAction(task);
    if (sysAction != null) {
      debugPrint('[AutoGlmAgent] 命中系统操作: ${sysAction.actionName} ${sysAction.fields}');
      if (onStep != null) {
        await onStep(AutoGlmStep(
          step: 1,
          thinking: '识别为系统操作，直接执行',
          action: sysAction.actionName,
          actionArgs: sysAction.fields,
          isFinish: false,
        ));
      }
      final execResult = await _executeAction(sysAction.actionName!, sysAction.fields);
      final success = execResult.success;
      return AutoGlmResult(
        success: success,
        message: success ? execResult.message : '执行失败: ${execResult.message}',
        steps: 1,
        trace: execResult.trace,
      );
    }

    // 不支持的操作
    return AutoGlmResult(
      success: false,
      message: '暂不支持此操作。目前支持：打开/退出应用、锁屏、音量调节、静音、WiFi/蓝牙/亮度控制、查看应用使用时间。',
    );
  }

  // ═══════════════════════════════════════════════════
  // 系统操作匹配
  // ═══════════════════════════════════════════════════

  ParsedAction? _matchSystemAction(String task) {
    final s = task.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    final rawLower = task.toLowerCase();

    // 1. 先判断意图：是否显式“打开/启动/进入”应用（打开词必须在）
    final hasOpenIntent = RegExp(r'(?:帮我|请|麻烦)?(?:打开|开启|启动|运行|进入|进|进一下|去一下|启动一下|开一下)').hasMatch(rawLower);

    // 2. 锁屏
    if (s.contains('锁屏') || s.contains('锁定屏幕') || s.contains('熄屏')) {
      return ParsedAction(metadata: 'do', actionName: 'LockScreen', fields: {});
    }

    // 3. 应用使用时间（必须在打开应用意图之前，避免“查看微信使用时间”被当成打开微信）
    final usageMatch = RegExp(
      r'(?:查看|看看|查查|查一下|帮我查|给我看看|看一下|显示|列出|看看我|统计)'
      r'(?:我?的?)(?:手机)?'
      r'(?:应用|软件|app|App)?'
      r'(?:使用|用了)'
      r'(?:时间|多久|多长时间|时长|排行|排名|列表|情况)',
    ).firstMatch(task);
    if (usageMatch != null) return ParsedAction(metadata: 'do', actionName: 'AppUsageTime', fields: {});

    final specificUsageMatch = RegExp(
      r'(微信|QQ|微博|淘宝|抖音|小红书|知乎|B站|bilibili|支付宝|京东|'
      r'拼多多|快手|网易云音乐|QQ音乐).{0,4}'
      r'(?:使用|用了).{0,4}'
      r'(?:时间|多久|多长时间|时长)',
    ).firstMatch(task);
    if (specificUsageMatch != null) {
      final appName = specificUsageMatch.group(1)!;
      return ParsedAction(metadata: 'do', actionName: 'AppUsageTime', fields: {'app': appName});
    }

    // 4. 安装的应用列表
    if (s.contains('安装了什么') || s.contains('装了什么') || s.contains('有什么软件') ||
        s.contains('有什么app') || s.contains('有哪些应用') || s.contains('手机里有什么') ||
        s.contains('安装了哪些') || s.contains('装了哪些')) {
      return ParsedAction(metadata: 'do', actionName: 'InstalledApps', fields: {});
    }

    // 5. 打开应用（只有显式“打开/启动/进入”等意图才命中）
    if (hasOpenIntent) {
      final launchMatch = RegExp(
              r'(?:打开|启动|运行|开启|去|进入|进|进一下|帮我打开|请打开|麻烦打开|开启一下)(微信|QQ|微博|淘宝|京东|拼多多|小红书|豆瓣|知乎|抖音|bilibili|哔哩哔哩|B站|快手|支付宝|网易云音乐|QQ音乐|携程|美团|饿了么|设置|相册|相机|时钟|计算器|日历|Solace|solace)')
          .firstMatch(s);
      if (launchMatch != null) {
        final appName = launchMatch.group(1)!;
        if (appName == '相册' || appName == '相机') {
          return ParsedAction(metadata: 'do', actionName: 'OpenGallery', fields: {});
        }
        if (appName == 'Solace' || appName == 'solace') {
          // 不拦截，继续看 ExitApp 匹配
        } else {
          return ParsedAction(metadata: 'do', actionName: 'Launch', fields: {'app': appName});
        }
      }
    }

    // 单独处理“打开相册/图库/照片”
    if (s.contains('打开相册') || s.contains('打开图库') || s.contains('看相册') || s.contains('看照片')) {
      return ParsedAction(metadata: 'do', actionName: 'OpenGallery', fields: {});
    }

    // 6. 退出/关闭 应用
    final exitMatch = RegExp(
            r'(?:退出|关闭|关掉|杀掉|结束)(Solace|solace|微信|QQ|微博|淘宝|抖音|支付宝|应用|app|App|软件)')
        .firstMatch(task);
    if (exitMatch != null) {
      var target = exitMatch.group(1) ?? '';
      if (target == '应用' || target == 'app' || target == 'App' || target == '软件') {
        target = '_current_app';
      }
      return ParsedAction(metadata: 'do', actionName: 'ExitApp', fields: {'app': target});
    }
    if (s.contains('退出solace') || s.contains('关掉solace') || s.contains('关闭solace')) {
      return ParsedAction(metadata: 'do', actionName: 'ExitApp', fields: {'app': 'Solace'});
    }
    if (s.contains('退出app') || s.contains('退出App')) {
      return ParsedAction(metadata: 'do', actionName: 'ExitApp', fields: {'app': '_current_app'});
    }
    // 音量
    if (s.contains('音量调大') || s.contains('调大音量') || s.contains('音量加') ||
        s.contains('大点声') || s.contains('大声点')) {
      return ParsedAction(metadata: 'do', actionName: 'VolumeUp', fields: {});
    }
    if (s.contains('音量调小') || s.contains('调小音量') || s.contains('音量减') ||
        s.contains('小点声') || s.contains('小声点')) {
      return ParsedAction(metadata: 'do', actionName: 'VolumeDown', fields: {});
    }

    // 静音
    if (s.contains('静音') || s.contains('开启静音') || s.contains('打开静音')) {
      return ParsedAction(metadata: 'do', actionName: 'Mute', fields: {});
    }
    if (s.contains('取消静音') || s.contains('关闭静音') || s.contains('解除静音')) {
      return ParsedAction(metadata: 'do', actionName: 'Unmute', fields: {});
    }

    // WiFi/蓝牙/亮度
    final wifiMatch = RegExp(r'(?:打开|开启|关闭|关掉|关)(?:wifi|WiFi|无线网|无线)').firstMatch(task);
    if (wifiMatch != null) {
      final enable = !(wifiMatch.group(0)?.contains('关') ?? false);
      return ParsedAction(metadata: 'do', actionName: 'ToggleWifi', fields: {'enable': enable.toString()});
    }
    final btMatch = RegExp(r'(?:打开|开启|关闭|关掉|关)(?:蓝牙|bluetooth|Bluetooth)').firstMatch(task);
    if (btMatch != null) {
      final enable = !(btMatch.group(0)?.contains('关') ?? false);
      return ParsedAction(metadata: 'do', actionName: 'ToggleBluetooth', fields: {'enable': enable.toString()});
    }
    final brightMatch = RegExp(r'(?:亮度|屏幕亮度)(?:调到|设为|设成|改为)?(\d+)').firstMatch(task);
    if (brightMatch != null) {
      return ParsedAction(metadata: 'do', actionName: 'SetBrightness', fields: {'level': brightMatch.group(1) ?? '128'});
    }
    if (s.contains('调亮') || s.contains('亮一点') || s.contains('亮度调高')) {
      return ParsedAction(metadata: 'do', actionName: 'SetBrightness', fields: {'level': '200'});
    }
    if (s.contains('调暗') || s.contains('暗一点') || s.contains('亮度调低')) {
      return ParsedAction(metadata: 'do', actionName: 'SetBrightness', fields: {'level': '50'});
    }

    return null;
  }

  // ═══════════════════════════════════════════════════
  // 动作执行
  // ═══════════════════════════════════════════════════

  Future<ActionExecResult> _executeAction(String actionName, Map<String, String> fields) async {
    final trace = <ActionTraceStep>[];
    if (actionName != 'AppUsageTime' && actionName != 'InstalledApps') {
      final status = await _device.getShizukuStatus();
      final ready = status['available'] == true && status['permitted'] == true;
      if (!ready) {
        trace.add(ActionTraceStep(
          tool: actionName, args: fields.toString(),
          result: '✗ Shizuku不可用', via: 'Shizuku shell (UID 2000)',
        ));
        return ActionExecResult(success: false, message: 'Shizuku不可用，无法执行$actionName', trace: trace);
      }
    }
    const via = 'Shizuku shell (UID 2000)';

    switch (actionName) {
      case 'Launch':
        final appName = fields['app'] ?? '';
        if (appName.isEmpty) return const ActionExecResult(success: false, message: '未指定应用名称');
        final packageName = _resolvePackageName(appName);
        if (packageName == null) {
          return ActionExecResult(success: false, message: '未知应用: $appName，请尝试手动启动', trace: [
            ActionTraceStep(tool: 'am start', args: appName, result: '✗ 未识别安全包名', via: via),
          ]);
        }
        final launchOk = await _device.startApp(packageName);
        trace.add(ActionTraceStep(
            tool: 'am start', args: '$appName → $packageName',
            result: launchOk ? '✓ 已打开' : '✗ 失败', via: via));
        return ActionExecResult(success: launchOk, message: launchOk ? '已打开: $appName' : '打开失败: $appName', trace: trace);

      case 'ExitApp':
        var targetApp = fields['app'] ?? '';
        if (targetApp == '_current_app') {
          try {
            final currentApp = await _a11y.getCurrentApp();
            if (currentApp.packageName.isEmpty || currentApp.packageName == 'com.solace.solace') {
              return ActionExecResult(success: false, message: '当前已在 Solace 中，无需退出', trace: [
                ActionTraceStep(tool: 'am force-stop', args: '(当前应用=Solace)', result: '✗ 已拦截（自杀保护）', via: via),
              ]);
            }
            targetApp = currentApp.displayName.isNotEmpty ? currentApp.displayName : currentApp.packageName;
          } catch (e) {
            return ActionExecResult(success: false, message: '无法获取当前前台应用信息', trace: [
              ActionTraceStep(tool: 'am force-stop', args: '(获取前台应用失败)', result: '✗ $e', via: via),
            ]);
          }
        }
        if (targetApp.isEmpty) {
          return ActionExecResult(success: false, message: '未指定要退出的应用', trace: [
            ActionTraceStep(tool: 'am force-stop', args: '(空)', result: '✗ 未指定应用', via: via),
          ]);
        }
        final lowerTarget = targetApp.toLowerCase();
        if (lowerTarget == 'solace' || lowerTarget == 'com.solace.solace') {
          return ActionExecResult(success: false, message: '无法退出 Solace 自身，这会导致我失去与您的连接', trace: [
            ActionTraceStep(tool: 'am force-stop', args: targetApp, result: '✗ 已拦截（自杀保护）', via: via),
          ]);
        }
        final pkgName = _resolvePackageName(targetApp);
        if (pkgName == null) {
          return ActionExecResult(success: false, message: '未知应用: $targetApp，已拒绝执行退出命令', trace: [
            ActionTraceStep(tool: 'am force-stop', args: targetApp, result: '✗ 未识别安全包名', via: via),
          ]);
        }
        if (pkgName == 'com.solace.solace') {
          return ActionExecResult(success: false, message: '无法退出 Solace 自身，这会导致我失去与您的连接', trace: [
            ActionTraceStep(tool: 'am force-stop', args: '$targetApp → $pkgName', result: '✗ 已拦截（自杀保护）', via: via),
          ]);
        }
        final exitOk = await _device.exitApp(pkgName);
        trace.add(ActionTraceStep(
            tool: 'am force-stop', args: '$targetApp → $pkgName',
            result: exitOk ? '✓ 已退出' : '✗ 失败', via: via));
        return ActionExecResult(success: exitOk, message: exitOk ? '已退出: $targetApp' : '退出失败: $targetApp', trace: trace);

      case 'LockScreen':
        final ok = await _device.lockScreen();
        trace.add(ActionTraceStep(tool: 'input keyevent 26', args: '', result: ok ? '✓ 已锁屏' : '✗ 失败', via: via));
        return ActionExecResult(success: ok, message: ok ? '已锁屏' : '锁屏失败(需Shizuku)', trace: trace);

      case 'VolumeUp':
        final ok = await _device.adjustVolume(true);
        trace.add(ActionTraceStep(tool: 'input keyevent 24', args: '', result: ok ? '✓ 音量+' : '✗ 失败', via: via));
        return ActionExecResult(success: ok, message: ok ? '音量已调大' : '音量调节失败(需Shizuku)', trace: trace);

      case 'VolumeDown':
        final ok = await _device.adjustVolume(false);
        trace.add(ActionTraceStep(tool: 'input keyevent 25', args: '', result: ok ? '✓ 音量-' : '✗ 失败', via: via));
        return ActionExecResult(success: ok, message: ok ? '音量已调小' : '音量调节失败(需Shizuku)', trace: trace);

      case 'Mute':
        final ok = await _device.setMuteMode(0);
        trace.add(ActionTraceStep(tool: 'cmd audio', args: 'set-ringer-mode 0', result: ok ? '✓ 已静音' : '✗ 失败', via: via));
        return ActionExecResult(success: ok, message: ok ? '已静音' : '静音失败(需Shizuku)', trace: trace);

      case 'Unmute':
        final ok = await _device.setMuteMode(2);
        trace.add(ActionTraceStep(tool: 'cmd audio', args: 'set-ringer-mode 2', result: ok ? '✓ 已取消静音' : '✗ 失败', via: via));
        return ActionExecResult(success: ok, message: ok ? '已取消静音' : '取消静音失败(需Shizuku)', trace: trace);

      case 'OpenGallery':
        final ok = await _device.openGallery();
        trace.add(ActionTraceStep(tool: 'am start', args: 'gallery', result: ok ? '✓ 相册已打开' : '✗ 失败', via: via));
        return ActionExecResult(success: ok, message: ok ? '相册已打开' : '打开相册失败', trace: trace);

      case 'ToggleWifi':
        final enable = (fields['enable'] ?? 'true').toLowerCase() == 'true';
        final ok = await _device.toggleWifi(enable);
        trace.add(ActionTraceStep(
            tool: 'svc wifi', args: enable ? 'enable' : 'disable',
            result: ok ? '✓ 已切换' : '✗ 失败', via: via));
        return ActionExecResult(success: ok, message: ok ? 'WiFi已${enable ? "开启" : "关闭"}' : 'WiFi切换失败(需Shizuku)', trace: trace);

      case 'ToggleBluetooth':
        final enable = (fields['enable'] ?? 'true').toLowerCase() == 'true';
        final ok = await _device.toggleBluetooth(enable);
        trace.add(ActionTraceStep(
            tool: 'svc bluetooth', args: enable ? 'enable' : 'disable',
            result: ok ? '✓ 已切换' : '✗ 失败', via: via));
        return ActionExecResult(success: ok, message: ok ? '蓝牙已${enable ? "开启" : "关闭"}' : '蓝牙切换失败(需Shizuku)', trace: trace);

      case 'SetBrightness':
        final level = int.tryParse(fields['level'] ?? '') ?? 128;
        final ok = await _device.setBrightness(level.clamp(0, 255));
        trace.add(ActionTraceStep(
            tool: 'settings put system', args: 'screen_brightness $level',
            result: ok ? '✓ 亮度=$level' : '✗ 失败', via: via));
        return ActionExecResult(success: ok, message: ok ? '亮度已设为$level' : '亮度调节失败(需Shizuku)', trace: trace);

      case 'AppUsageTime':
        final appName = fields['app'];
        String? pkgName;
        if (appName != null && appName.isNotEmpty) {
          pkgName = _resolvePackageName(appName);
          if (pkgName == null) {
            return ActionExecResult(success: false, message: '无法识别应用: $appName', trace: [
              ActionTraceStep(tool: 'UsageStatsManager', args: appName, result: '✗ 未知包名', via: 'Android API'),
            ]);
          }
        }
        final usageResult = await _device.getAppUsageTime(
          packageName: pkgName, sinceHours: 24, limit: 10, includeSystemApps: false,
        );
        if (usageResult == null || usageResult['success'] != true) {
          final err = usageResult != null ? (usageResult['error'] as String? ?? '未知错误') : '调用失败';
          return ActionExecResult(success: false, message: '读取使用时间失败: $err', trace: [
            ActionTraceStep(tool: 'UsageStatsManager', args: appName ?? '所有应用', result: '✗ $err', via: 'Android API'),
          ]);
        }
        final entries = usageResult['entries'] as List<dynamic>? ?? [];
        if (entries.isEmpty) {
          return ActionExecResult(
            success: true,
            message: pkgName != null ? '最近24小时内没有 $appName 的使用记录' : '最近24小时内没有应用使用记录',
            trace: [ActionTraceStep(tool: 'UsageStatsManager', args: appName ?? '所有应用', result: '✓ 无记录', via: 'Android API')],
          );
        }
        final buf = StringBuffer();
        if (pkgName != null) {
          final e = entries.first as Map<dynamic, dynamic>;
          final ms = e['totalForegroundTimeMs'] as num;
          final hours = ms.toInt() ~/ 3600000;
          final minutes = (ms.toInt() % 3600000) ~/ 60000;
          buf.writeln('${e['appName']} 使用时间:');
          if (hours > 0) buf.write('${hours}小时');
          if (minutes > 0 || hours == 0) buf.write('${minutes}分钟');
        } else {
          buf.writeln('最近24小时应用使用排行:');
          var rank = 1;
          for (final e in entries) {
            if (e is! Map<dynamic, dynamic>) continue;
            final ms = e['totalForegroundTimeMs'] as num;
            final hours = ms.toInt() ~/ 3600000;
            final minutes = (ms.toInt() % 3600000) ~/ 60000;
            final time = hours > 0 ? '${hours}时${minutes}分' : '${minutes}分钟';
            buf.writeln('$rank. ${e['appName']} — $time');
            rank++;
          }
        }
        trace.add(ActionTraceStep(tool: 'UsageStatsManager', args: appName ?? '所有应用', result: '✓ 已获取', via: 'Android API'));
        return ActionExecResult(success: true, message: buf.toString().trim(), trace: trace, isFinish: true);

      case 'InstalledApps':
        // 通过 Shizuku shell 执行 pm list packages
        final result = await _device.shellExec('pm list packages -3');
        if (!result.success) {
          return ActionExecResult(success: false, message: '获取应用列表失败', trace: [
            ActionTraceStep(tool: 'pm list packages', args: '-3', result: '✗ ${result.stderr}', via: via),
          ]);
        }
        final lines = result.stdout.split('\n').where((l) => l.startsWith('package:')).map((l) => l.replaceFirst('package:', '').trim()).where((l) => l.isNotEmpty).toList();
        final buf = StringBuffer('已安装的第三方应用(${lines.length}个):\n');
        for (final pkg in lines) {
          final name = _appPackageMap.entries.where((e) => e.value == pkg).firstOrNull?.key ?? pkg.split('.').last;
          buf.writeln('- $name ($pkg)');
        }
        trace.add(ActionTraceStep(tool: 'pm list packages', args: '-3', result: '✓ ${lines.length}个应用', via: via));
        return ActionExecResult(success: true, message: buf.toString().trim(), trace: trace, isFinish: true);

      default:
        return ActionExecResult(success: false, message: '未知动作: $actionName');
    }
  }

  // ═══════════════════════════════════════════════════
  // 应用名 → 包名映射
  // ═══════════════════════════════════════════════════

  static const Map<String, String> _appPackageMap = {
    // 社交
    '微信': 'com.tencent.mm',
    'WeChat': 'com.tencent.mm',
    'wechat': 'com.tencent.mm',
    'QQ': 'com.tencent.mobileqq',
    'qq': 'com.tencent.mobileqq',
    '微博': 'com.sina.weibo',
    'Weibo': 'com.sina.weibo',
    'weibo': 'com.sina.weibo',
    // 电商
    '淘宝': 'com.taobao.taobao',
    'Taobao': 'com.taobao.taobao',
    'taobao': 'com.taobao.taobao',
    '京东': 'com.jingdong.app.mall',
    '拼多多': 'com.xunmeng.pinduoduo',
    // 生活
    '小红书': 'com.xingin.xhs',
    '豆瓣': 'com.douban.frodo',
    '知乎': 'com.zhihu.android',
    // 短视频
    '抖音': 'com.ss.android.ugc.aweme',
    'Douyin': 'com.ss.android.ugc.aweme',
    'douyin': 'com.ss.android.ugc.aweme',
    'bilibili': 'tv.danmaku.bili',
    '哔哩哔哩': 'tv.danmaku.bili',
    'B站': 'tv.danmaku.bili',
    '快手': 'com.smile.gifmaker',
    // 支付
    '支付宝': 'com.eg.android.AlipayGphone',
    'Alipay': 'com.eg.android.AlipayGphone',
    // 音乐
    '网易云音乐': 'com.netease.cloudmusic',
    'QQ音乐': 'com.tencent.qqmusic',
    // 系统
    '设置': 'com.android.settings',
    '相册': 'com.android.gallery3d',
    'Gallery': 'com.android.gallery3d',
    'gallery': 'com.android.gallery3d',
    '相机': 'com.android.camera',
    'Camera': 'com.android.camera',
    'camera': 'com.android.camera',
    // Solace
    'Solace': 'com.solace.solace',
    'solace': 'com.solace.solace',
  };

  String? _resolvePackageName(String appName) {
    if (_appPackageMap.containsKey(appName)) return _appPackageMap[appName];
    final lower = appName.toLowerCase();
    for (final entry in _appPackageMap.entries) {
      if (entry.key.toLowerCase() == lower) return entry.value;
    }
    for (final entry in _appPackageMap.entries) {
      if (entry.key.toLowerCase().contains(lower) || lower.contains(entry.key.toLowerCase())) {
        return entry.value;
      }
    }
    return null;
  }
}

/// 执行结果
class AutoGlmResult {
  final bool success;
  final String message;
  final int steps;
  final List<ActionTraceStep> trace;

  const AutoGlmResult({
    required this.success,
    required this.message,
    this.steps = 0,
    this.trace = const [],
  });
}

/// 执行步骤回调
class AutoGlmStep {
  final int step;
  final String? thinking;
  final String? action;
  final Map<String, String>? actionArgs;
  final bool isFinish;

  const AutoGlmStep({
    required this.step,
    this.thinking,
    this.action,
    this.actionArgs,
    required this.isFinish,
  });
}

/// 动作执行结果
class ActionExecResult {
  final bool success;
  final String message;
  final List<ActionTraceStep> trace;
  final bool isFinish;

  const ActionExecResult({
    required this.success,
    required this.message,
    this.trace = const [],
    this.isFinish = false,
  });
}

/// 单步工具调用详情
class ActionTraceStep {
  final String tool;
  final String args;
  final String result;
  final String via;

  const ActionTraceStep({
    required this.tool,
    required this.args,
    required this.result,
    required this.via,
  });
}

/// 解析后的动作
class ParsedAction {
  final String metadata;
  final String? thinking;
  final String? actionName;
  final Map<String, String> fields;

  const ParsedAction({
    required this.metadata,
    this.thinking,
    this.actionName,
    this.fields = const {},
  });
}
