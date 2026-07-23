import 'package:flutter_test/flutter_test.dart';
import 'package:solace/services/device_persona_strategy.dart';
import 'package:solace/services/device_action_policy.dart';

void main() {
  test('detect care / dominant / playful', () {
    expect(
      DevicePersonaStrategy.detect(personality: '温柔体贴，很关心你熬夜'),
      DevicePersonaArchetype.care,
    );
    expect(
      DevicePersonaStrategy.detect(personality: '病娇占有欲强，想控制你'),
      DevicePersonaArchetype.dominant,
    );
    expect(
      DevicePersonaStrategy.detect(personality: '调皮爱整蛊玩闹'),
      DevicePersonaArchetype.playful,
    );
  });

  test('care hides shell high risk from capability list', () {
    expect(
      DevicePersonaStrategy.shouldListTool(
        toolName: 'get_battery_info',
        arch: DevicePersonaArchetype.care,
        userPermissionOn: true,
      ),
      isTrue,
    );
    expect(
      DevicePersonaStrategy.shouldListTool(
        toolName: 'execute_shell',
        arch: DevicePersonaArchetype.care,
        userPermissionOn: true,
      ),
      isFalse,
    );
  });

  test('policy rate limit shared', () {
    final p = DeviceActionPolicy.instance;
    const sid = 'test-session-rate';
    // clear by consuming hour window via mark many - use unique id
    expect(p.allow(sid), isTrue);
    p.markSuccess(sid);
    expect(p.allow(sid), isFalse); // coolDown
    p.pushFeedback(
      sessionId: sid,
      toolName: 'get_battery_info',
      message: '80%',
      success: true,
      isRead: true,
    );
    final fb = p.consumeFeedback(sid);
    expect(fb, isNotNull);
    expect(fb!.contains('80%'), isTrue);
    expect(p.consumeFeedback(sid), isNull);
  });
}
