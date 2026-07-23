import 'dart:convert';
import 'package:uuid/uuid.dart';

/// Device Agent 全量动作 = ToolRegistry 中全部设备工具
enum DeviceActionType {
  // read
  getBatteryInfo,
  getCurrentApp,
  getInstalledApps,
  getAppUsageTime,
  getNotifications,
  getNotificationCount,
  takeScreenshot,
  // display
  setBrightness,
  // audio
  adjustVolume,
  setMute,
  // lock / nav
  lockScreen,
  goHome,
  pressBack,
  // app
  openApp,
  closeApp,
  openGallery,
  // network
  toggleWifi,
  toggleBluetooth,
  // ui
  tap,
  swipe,
  inputText,
  pressKey,
  // shell
  executeShell,
}

enum DevicePermissionCategory {
  read,
  display,
  audio,
  lock,
  app,
  network,
  ui,
  shell,
}

enum DeviceActionResult {
  success,
  rejected,
  failed,
}

enum DeviceRejectionReason {
  masterSwitchOff,
  childPermissionOff,
  permanentlyForbidden,
  rateLimited,
  whitelistMismatch,
  parseError,
  modeBlocked,
  unknown,
}

const Map<DeviceActionType, DevicePermissionCategory> deviceActionCategoryMap =
    {
  DeviceActionType.getBatteryInfo: DevicePermissionCategory.read,
  DeviceActionType.getCurrentApp: DevicePermissionCategory.read,
  DeviceActionType.getInstalledApps: DevicePermissionCategory.read,
  DeviceActionType.getAppUsageTime: DevicePermissionCategory.read,
  DeviceActionType.getNotifications: DevicePermissionCategory.read,
  DeviceActionType.getNotificationCount: DevicePermissionCategory.read,
  DeviceActionType.takeScreenshot: DevicePermissionCategory.read,
  DeviceActionType.setBrightness: DevicePermissionCategory.display,
  DeviceActionType.adjustVolume: DevicePermissionCategory.audio,
  DeviceActionType.setMute: DevicePermissionCategory.audio,
  DeviceActionType.lockScreen: DevicePermissionCategory.lock,
  DeviceActionType.goHome: DevicePermissionCategory.lock,
  DeviceActionType.pressBack: DevicePermissionCategory.lock,
  DeviceActionType.openApp: DevicePermissionCategory.app,
  DeviceActionType.closeApp: DevicePermissionCategory.app,
  DeviceActionType.openGallery: DevicePermissionCategory.app,
  DeviceActionType.toggleWifi: DevicePermissionCategory.network,
  DeviceActionType.toggleBluetooth: DevicePermissionCategory.network,
  DeviceActionType.tap: DevicePermissionCategory.ui,
  DeviceActionType.swipe: DevicePermissionCategory.ui,
  DeviceActionType.inputText: DevicePermissionCategory.ui,
  DeviceActionType.pressKey: DevicePermissionCategory.ui,
  DeviceActionType.executeShell: DevicePermissionCategory.shell,
};

/// 工具名 -> 动作类型（全量）
const Map<String, DeviceActionType> deviceToolNameMap = {
  'get_battery_info': DeviceActionType.getBatteryInfo,
  'get_current_app': DeviceActionType.getCurrentApp,
  'get_installed_apps': DeviceActionType.getInstalledApps,
  'get_app_usage_time': DeviceActionType.getAppUsageTime,
  'get_notifications': DeviceActionType.getNotifications,
  'get_notification_count': DeviceActionType.getNotificationCount,
  'take_screenshot': DeviceActionType.takeScreenshot,
  'set_brightness': DeviceActionType.setBrightness,
  'adjust_volume': DeviceActionType.adjustVolume,
  'set_mute': DeviceActionType.setMute,
  'lock_screen': DeviceActionType.lockScreen,
  'go_home': DeviceActionType.goHome,
  'press_back': DeviceActionType.pressBack,
  'open_app': DeviceActionType.openApp,
  'close_app': DeviceActionType.closeApp,
  'open_gallery': DeviceActionType.openGallery,
  'toggle_wifi': DeviceActionType.toggleWifi,
  'toggle_bluetooth': DeviceActionType.toggleBluetooth,
  'tap': DeviceActionType.tap,
  'swipe': DeviceActionType.swipe,
  'input_text': DeviceActionType.inputText,
  'press_key': DeviceActionType.pressKey,
  'execute_shell': DeviceActionType.executeShell,
};

/// 能力卡短说明（按工具）
const Map<String, String> deviceToolPromptHint = {
  'get_battery_info': '查电量',
  'get_current_app': '查当前前台应用',
  'get_installed_apps': '查已装应用',
  'get_app_usage_time': '查应用使用时长',
  'get_notifications': '读通知列表',
  'get_notification_count': '读通知数量',
  'take_screenshot': '截图',
  'set_brightness': '调亮度 params.level=0-255',
  'adjust_volume': '调音量 params.direction=up|down',
  'set_mute': '静音 params.muted=true|false',
  'lock_screen': '锁屏',
  'go_home': '回桌面',
  'press_back': '按返回键',
  'open_app': '打开应用 params.app=微信',
  'close_app': '关闭应用 params.app=微信',
  'open_gallery': '打开相册',
  'toggle_wifi': 'WiFi params.enable=true|false',
  'toggle_bluetooth': '蓝牙 params.enable=true|false',
  'tap': '点击 params.x,y',
  'swipe': '滑动 params.start_x,start_y,end_x,end_y',
  'input_text': '输入文字 params.text',
  'press_key': '按键 params.keycode',
  'execute_shell': '执行 shell params.command',
};

/// 无永久禁用：全部能力可由子权限闸门控制
const Set<String> devicePermanentlyForbidden = <String>{};

class DeviceAgentAction {
  final String id;
  final DeviceActionType actionType;
  final DevicePermissionCategory category;
  final Map<String, dynamic> params;
  final String reason;
  final String stateBefore;
  final String stateAfter;
  final DeviceActionResult result;
  final DeviceRejectionReason? rejectionReason;
  final String characterId;
  final String sessionId;
  final String message;
  final DateTime createdAt;

  DeviceAgentAction({
    String? id,
    required this.actionType,
    required this.category,
    this.params = const {},
    this.reason = '',
    this.stateBefore = '',
    this.stateAfter = '',
    required this.result,
    this.rejectionReason,
    this.characterId = '',
    this.sessionId = '',
    this.message = '',
    DateTime? createdAt,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
        'id': id,
        'actionType': actionType.name,
        'category': category.name,
        'params': jsonEncode(params),
        'reason': reason,
        'stateBefore': stateBefore,
        'stateAfter': stateAfter,
        'result': result.name,
        'rejectionReason': rejectionReason?.name,
        'characterId': characterId,
        'sessionId': sessionId,
        'message': message,
        'createdAt': createdAt.toIso8601String(),
      };

  factory DeviceAgentAction.fromMap(Map<String, dynamic> map) {
    Map<String, dynamic> params = {};
    final raw = map['params'];
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) params = Map<String, dynamic>.from(decoded);
      } catch (_) {}
    } else if (raw is Map) {
      params = Map<String, dynamic>.from(raw);
    }

    DeviceActionType actionType = DeviceActionType.getBatteryInfo;
    for (final t in DeviceActionType.values) {
      if (t.name == map['actionType']) {
        actionType = t;
        break;
      }
    }

    DevicePermissionCategory category = DevicePermissionCategory.read;
    for (final c in DevicePermissionCategory.values) {
      if (c.name == map['category']) {
        category = c;
        break;
      }
    }

    DeviceActionResult result = DeviceActionResult.failed;
    for (final r in DeviceActionResult.values) {
      if (r.name == map['result']) {
        result = r;
        break;
      }
    }

    DeviceRejectionReason? rejection;
    final rr = map['rejectionReason']?.toString();
    if (rr != null) {
      for (final r in DeviceRejectionReason.values) {
        if (r.name == rr) {
          rejection = r;
          break;
        }
      }
    }

    return DeviceAgentAction(
      id: map['id']?.toString(),
      actionType: actionType,
      category: category,
      params: params,
      reason: map['reason']?.toString() ?? '',
      stateBefore: map['stateBefore']?.toString() ?? '',
      stateAfter: map['stateAfter']?.toString() ?? '',
      result: result,
      rejectionReason: rejection,
      characterId: map['characterId']?.toString() ?? '',
      sessionId: map['sessionId']?.toString() ?? '',
      message: map['message']?.toString() ?? '',
      createdAt: DateTime.tryParse(map['createdAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

DeviceActionType? parseDeviceActionType(String name) {
  final key = name.trim();
  if (key.isEmpty) return null;
  if (deviceToolNameMap.containsKey(key)) return deviceToolNameMap[key];
  for (final t in DeviceActionType.values) {
    if (t.name == key) return t;
  }
  final snake = key
      .replaceAllMapped(RegExp(r'[A-Z]'), (m) => '_${m.group(0)!.toLowerCase()}')
      .replaceFirst(RegExp(r'^_'), '');
  return deviceToolNameMap[snake] ?? deviceToolNameMap[key.toLowerCase()];
}

String deviceActionToToolName(DeviceActionType type) {
  for (final e in deviceToolNameMap.entries) {
    if (e.value == type) return e.key;
  }
  return type.name;
}

String devicePermissionKeyFor(DevicePermissionCategory category) {
  switch (category) {
    case DevicePermissionCategory.read:
      return 'device_permission_read';
    case DevicePermissionCategory.display:
      return 'device_permission_display';
    case DevicePermissionCategory.audio:
      return 'device_permission_audio';
    case DevicePermissionCategory.lock:
      return 'device_permission_lock';
    case DevicePermissionCategory.app:
      return 'device_permission_app';
    case DevicePermissionCategory.network:
      return 'device_permission_network';
    case DevicePermissionCategory.ui:
      return 'device_permission_ui';
    case DevicePermissionCategory.shell:
      return 'device_permission_shell';
  }
}
