import '../tool.dart';
import '../../device_service.dart';

/// 应用名→包名解析（公有，供其他工具包复用）
class OpenAppResolver {
  OpenAppResolver._();

  static const Map<String, String> packageMap = {
    '微信': 'com.tencent.mm', 'WeChat': 'com.tencent.mm', 'wechat': 'com.tencent.mm',
    'QQ': 'com.tencent.mobileqq', 'qq': 'com.tencent.mobileqq',
    '微博': 'com.sina.weibo',
    '淘宝': 'com.taobao.taobao',
    '京东': 'com.jingdong.app.mall',
    '拼多多': 'com.xunmeng.pinduoduo',
    '小红书': 'com.xingin.xhs',
    '知乎': 'com.zhihu.android',
    '抖音': 'com.ss.android.ugc.aweme',
    'bilibili': 'tv.danmaku.bili', '哔哩哔哩': 'tv.danmaku.bili', 'B站': 'tv.danmaku.bili',
    '快手': 'com.smile.gifmaker',
    '支付宝': 'com.eg.android.AlipayGphone',
    '网易云音乐': 'com.netease.cloudmusic',
    'QQ音乐': 'com.tencent.qqmusic',
    '设置': 'com.android.settings',
    '相机': 'com.android.camera',
    '相册': 'com.android.gallery3d',
    '日历': 'com.android.calendar',
    '时钟': 'com.android.deskclock',
    '计算器': 'com.android.calculator2',
    'Solace': 'com.solace.solace', 'solace': 'com.solace.solace',
  };

  static String? resolve(String app) {
    if (app.contains('.')) return app;
    if (packageMap.containsKey(app)) return packageMap[app];
    final lower = app.toLowerCase();
    for (final e in packageMap.entries) {
      if (e.key.toLowerCase() == lower) return e.value;
    }
    return null;
  }
}

/// 系统操作工具包
class SystemOperationToolPkg extends ToolPkg {
  final DeviceService _device = DeviceService();

  @override
  String get name => '系统操作';

  @override
  String get description => '应用控制、锁屏、音量、WiFi、蓝牙、亮度等系统操作';

  @override
  List<Tool> get tools => [
        _OpenAppTool(_device),
        _CloseAppTool(_device),
        _LockScreenTool(_device),
        _AdjustVolumeTool(_device),
        _SetMuteTool(_device),
        _ToggleWifiTool(_device),
        _ToggleBluetoothTool(_device),
        _SetBrightnessTool(_device),
        _OpenGalleryTool(_device),
        _GoHomeTool(_device),
        _PressBackTool(_device),
      ];
}

// ═══════════════════════════════════════════════
// 打开应用
// ═══════════════════════════════════════════════

class _OpenAppTool extends Tool {
  final DeviceService _device;
  _OpenAppTool(this._device);

  @override String get name => 'open_app';
  @override String get description => '打开指定应用。支持中文名称（微信、QQ、淘宝等）或包名（com.tencent.mm）。';
  @override Map<String, dynamic> get parametersSchema => {
    'type': 'object',
    'properties': {'app': {'type': 'string', 'description': '应用名称（中文）或包名'}},
    'required': ['app'],
  };
  @override Set<String> get requiredPermissions => {'shizuku'};
  @override bool get isDestructive => false;

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    final app = args['app'] as String? ?? '';
    if (app.isEmpty) return ToolResult.error('请指定要打开的应用名称或包名');
    final pkg = OpenAppResolver.resolve(app);
    if (pkg == null) return ToolResult.error('未知应用: $app，请使用包名或常用名称');
    final ok = await _device.startApp(pkg);
    return ok ? ToolResult.success('已打开: $app ($pkg)') : ToolResult.error('打开失败: $app');
  }
}

// ═══════════════════════════════════════════════
// 关闭应用
// ═══════════════════════════════════════════════

class _CloseAppTool extends Tool {
  final DeviceService _device;
  _CloseAppTool(this._device);

  @override String get name => 'close_app';
  @override String get description => '强制关闭指定应用（am force-stop）。不能关闭 Solace 自身。';
  @override Map<String, dynamic> get parametersSchema => {
    'type': 'object',
    'properties': {'app': {'type': 'string', 'description': '应用名称（中文）或包名'}},
    'required': ['app'],
  };
  @override Set<String> get requiredPermissions => {'shizuku'};
  @override bool get isDestructive => true;

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    final app = args['app'] as String? ?? '';
    if (app.isEmpty) return ToolResult.error('请指定要关闭的应用');
    final lower = app.toLowerCase();
    if (lower == 'solace' || lower == 'com.solace.solace') return ToolResult.error('不能关闭 Solace 自身');
    final pkg = OpenAppResolver.resolve(app);
    if (pkg == null) return ToolResult.error('未知应用: $app');
    if (pkg == 'com.solace.solace') return ToolResult.error('不能关闭 Solace 自身');
    final ok = await _device.exitApp(pkg);
    return ok ? ToolResult.success('已关闭: $app ($pkg)') : ToolResult.error('关闭失败: $app');
  }
}

// ═══════════════════════════════════════════════
// 锁屏
// ═══════════════════════════════════════════════

class _LockScreenTool extends Tool {
  final DeviceService _device;
  _LockScreenTool(this._device);

  @override String get name => 'lock_screen';
  @override String get description => '锁定设备屏幕';
  @override Map<String, dynamic> get parametersSchema => {'type': 'object', 'properties': {}};
  @override Set<String> get requiredPermissions => {'shizuku'};
  @override bool get isDestructive => false;

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    final ok = await _device.lockScreen();
    return ok ? ToolResult.success('屏幕已锁定') : ToolResult.error('锁屏失败');
  }
}

// ═══════════════════════════════════════════════
// 音量调节
// ═══════════════════════════════════════════════

class _AdjustVolumeTool extends Tool {
  final DeviceService _device;
  _AdjustVolumeTool(this._device);

  @override String get name => 'adjust_volume';
  @override String get description => '调节设备音量';
  @override Map<String, dynamic> get parametersSchema => {
    'type': 'object',
    'properties': {'direction': {'type': 'string', 'enum': ['up', 'down'], 'description': 'up=调大, down=调小'}},
    'required': ['direction'],
  };
  @override Set<String> get requiredPermissions => {'shizuku'};
  @override bool get isDestructive => false;

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    final up = (args['direction'] as String? ?? 'up').toLowerCase() == 'up';
    final ok = await _device.adjustVolume(up, showUi: true);
    return ok ? ToolResult.success(up ? '音量已调大' : '音量已调小') : ToolResult.error('音量调节失败');
  }
}

// ═══════════════════════════════════════════════
// 静音模式
// ═══════════════════════════════════════════════

class _SetMuteTool extends Tool {
  final DeviceService _device;
  _SetMuteTool(this._device);

  @override String get name => 'set_mute';
  @override String get description => '设置静音模式';
  @override Map<String, dynamic> get parametersSchema => {
    'type': 'object',
    'properties': {'muted': {'type': 'boolean', 'description': 'true=静音, false=取消静音'}},
    'required': ['muted'],
  };
  @override Set<String> get requiredPermissions => {'shizuku'};
  @override bool get isDestructive => false;

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    final muted = args['muted'] as bool? ?? true;
    final ok = await _device.setMuteMode(muted ? 0 : 2);
    return ok ? ToolResult.success(muted ? '已静音' : '已取消静音') : ToolResult.error('静音设置失败');
  }
}

// ═══════════════════════════════════════════════
// WiFi
// ═══════════════════════════════════════════════

class _ToggleWifiTool extends Tool {
  final DeviceService _device;
  _ToggleWifiTool(this._device);

  @override String get name => 'toggle_wifi';
  @override String get description => '打开或关闭 WiFi';
  @override Map<String, dynamic> get parametersSchema => {
    'type': 'object',
    'properties': {'enable': {'type': 'boolean', 'description': 'true=打开, false=关闭'}},
    'required': ['enable'],
  };
  @override Set<String> get requiredPermissions => {'shizuku'};
  @override bool get isDestructive => false;

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    final enable = args['enable'] as bool? ?? true;
    final ok = await _device.toggleWifi(enable);
    return ok ? ToolResult.success(enable ? 'WiFi 已打开' : 'WiFi 已关闭') : ToolResult.error('WiFi 切换失败');
  }
}

// ═══════════════════════════════════════════════
// 蓝牙
// ═══════════════════════════════════════════════

class _ToggleBluetoothTool extends Tool {
  final DeviceService _device;
  _ToggleBluetoothTool(this._device);

  @override String get name => 'toggle_bluetooth';
  @override String get description => '打开或关闭蓝牙';
  @override Map<String, dynamic> get parametersSchema => {
    'type': 'object',
    'properties': {'enable': {'type': 'boolean', 'description': 'true=打开, false=关闭'}},
    'required': ['enable'],
  };
  @override Set<String> get requiredPermissions => {'shizuku'};
  @override bool get isDestructive => false;

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    final enable = args['enable'] as bool? ?? true;
    final ok = await _device.toggleBluetooth(enable);
    return ok ? ToolResult.success(enable ? '蓝牙已打开' : '蓝牙已关闭') : ToolResult.error('蓝牙切换失败');
  }
}

// ═══════════════════════════════════════════════
// 亮度
// ═══════════════════════════════════════════════

class _SetBrightnessTool extends Tool {
  final DeviceService _device;
  _SetBrightnessTool(this._device);

  @override String get name => 'set_brightness';
  @override String get description => '设置屏幕亮度（0-255）';
  @override Map<String, dynamic> get parametersSchema => {
    'type': 'object',
    'properties': {'level': {'type': 'integer', 'description': '亮度值，0=最暗, 255=最亮'}},
    'required': ['level'],
  };
  @override Set<String> get requiredPermissions => {'shizuku'};
  @override bool get isDestructive => false;

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    final level = (args['level'] as num?)?.toInt().clamp(0, 255) ?? 128;
    final ok = await _device.setBrightness(level);
    return ok ? ToolResult.success('亮度已设为 $level') : ToolResult.error('亮度调节失败');
  }
}

// ═══════════════════════════════════════════════
// 打开相册
// ═══════════════════════════════════════════════

class _OpenGalleryTool extends Tool {
  final DeviceService _device;
  _OpenGalleryTool(this._device);

  @override String get name => 'open_gallery';
  @override String get description => '打开系统相册/图库';
  @override Map<String, dynamic> get parametersSchema => {'type': 'object', 'properties': {}};
  @override Set<String> get requiredPermissions => {'shizuku'};
  @override bool get isDestructive => false;

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    final ok = await _device.openGallery();
    return ok ? ToolResult.success('相册已打开') : ToolResult.error('打开相册失败');
  }
}

// ═══════════════════════════════════════════════
// 返回桌面
// ═══════════════════════════════════════════════

class _GoHomeTool extends Tool {
  final DeviceService _device;
  _GoHomeTool(this._device);

  @override String get name => 'go_home';
  @override String get description => '返回设备桌面';
  @override Map<String, dynamic> get parametersSchema => {'type': 'object', 'properties': {}};
  @override Set<String> get requiredPermissions => {'shizuku'};
  @override bool get isDestructive => false;

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    final ok = await _device.pressKey(3); // KEYCODE_HOME
    return ok ? ToolResult.success('已返回桌面') : ToolResult.error('返回桌面失败');
  }
}

// ═══════════════════════════════════════════════
// 返回键
// ═══════════════════════════════════════════════

class _PressBackTool extends Tool {
  final DeviceService _device;
  _PressBackTool(this._device);

  @override String get name => 'press_back';
  @override String get description => '按返回键';
  @override Map<String, dynamic> get parametersSchema => {'type': 'object', 'properties': {}};
  @override Set<String> get requiredPermissions => {'shizuku'};
  @override bool get isDestructive => false;

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    final ok = await _device.pressKey(4); // KEYCODE_BACK
    return ok ? ToolResult.success('已按返回键') : ToolResult.error('按返回键失败');
  }
}
