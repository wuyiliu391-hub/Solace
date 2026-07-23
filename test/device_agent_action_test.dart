import 'package:flutter_test/flutter_test.dart';
import 'package:solace/models/device_agent_action.dart';

void main() {
  test('all registry tool names map to DeviceActionType', () {
    const tools = [
      'get_battery_info',
      'get_current_app',
      'get_installed_apps',
      'get_app_usage_time',
      'get_notifications',
      'get_notification_count',
      'take_screenshot',
      'set_brightness',
      'adjust_volume',
      'set_mute',
      'lock_screen',
      'go_home',
      'press_back',
      'open_app',
      'close_app',
      'open_gallery',
      'toggle_wifi',
      'toggle_bluetooth',
      'tap',
      'swipe',
      'input_text',
      'press_key',
      'execute_shell',
    ];
    expect(tools.length, deviceToolNameMap.length);
    for (final t in tools) {
      expect(parseDeviceActionType(t), isNotNull, reason: t);
      expect(deviceToolNameMap.containsKey(t), isTrue);
    }
  });

  test('deviceActionToToolName roundtrip full set', () {
    for (final t in DeviceActionType.values) {
      final name = deviceActionToToolName(t);
      expect(parseDeviceActionType(name), t);
    }
  });

  test('categories cover every action', () {
    for (final t in DeviceActionType.values) {
      expect(deviceActionCategoryMap.containsKey(t), isTrue);
    }
  });

  test('shell/ui/network not permanently forbidden', () {
    expect(devicePermanentlyForbidden, isEmpty);
    expect(parseDeviceActionType('execute_shell'),
        DeviceActionType.executeShell);
    expect(parseDeviceActionType('close_app'), DeviceActionType.closeApp);
    expect(parseDeviceActionType('tap'), DeviceActionType.tap);
  });

  test('DeviceAgentAction toMap/fromMap', () {
    final a = DeviceAgentAction(
      actionType: DeviceActionType.toggleWifi,
      category: DevicePermissionCategory.network,
      params: {'enable': true},
      reason: '连网',
      result: DeviceActionResult.success,
      characterId: 'c1',
      sessionId: 's1',
      message: 'ok',
    );
    final b = DeviceAgentAction.fromMap(a.toMap());
    expect(b.actionType, DeviceActionType.toggleWifi);
    expect(b.params['enable'], true);
    expect(b.category, DevicePermissionCategory.network);
  });
}
