import 'package:flutter_test/flutter_test.dart';
import 'package:solace/services/tools/deterministic_device_router.dart';

void main() {
  test('natural app-list requests map to get_installed_apps', () {
    for (final text in [
      '爸爸帮我看看我手机嘛我手机里安装了很多东西',
      '看看我手机里装了什么应用',
      '查看手机上安装的软件',
      '我手机装了什么东西',
      '帮我看看手机里有哪些app',
    ]) {
      final route = DeterministicDeviceRouter.match(text);
      expect(route?.toolName, 'get_installed_apps', reason: text);
    }
  });

  test('narrative/negation does not trigger', () {
    for (final text in [
      '我手机里没什么特别的',
      '他手机里装了很多游戏',
      '手机屏幕坏了我很难过',
    ]) {
      expect(DeterministicDeviceRouter.match(text), isNull, reason: text);
    }
  });
}