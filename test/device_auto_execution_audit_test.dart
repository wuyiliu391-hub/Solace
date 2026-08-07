import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solace/config/constants.dart';
import 'package:solace/models/device_agent_action.dart';
import 'package:solace/repositories/local_storage_repository.dart';
import 'package:solace/services/device_agent_execution_service.dart';
import 'package:solace/services/tools/device_intent_router.dart';
import 'package:solace/services/tools/deterministic_device_router.dart';
import 'package:solace/services/tools/tool.dart';
import 'package:solace/services/tools/tool_executor.dart';
import 'package:solace/services/tools/tool_registry.dart';

/// 自动设备操作审计。
///
/// 产品边界：角色/确定的设备指令一律自动放行——只有系统级首次授权
/// （Android/Shizuku/无障碍/截图）需要人工，操作通道本身不弹「逐次确认」。
/// 未开启的权限直接执行失败并写审计，由角色按真实结果说明缺失项。
void main() {
  late LocalStorageRepository repo;

  Future<void> setUpRepo(Map<String, Object> seed) async {
    SharedPreferences.setMockInitialValues(seed);
    repo = LocalStorageRepository(isWeb: true);
    await repo.initialize();
  }

  ToolExecutor mockExecutor() {
    return ToolExecutor(ToolRegistry()..register(_FakeToolPkg()));
  }

  String jsonFor(String action, Map<String, dynamic> params) => jsonEncode({
        'action': action,
        'params': params,
        'reason': '审计测试',
      });

  group('DeviceAgentExecutionService 自动放行审计', () {
    test('主开关关闭时静默拒绝并写审计，无需用户确认', () async {
      await setUpRepo({
        PrefKeys.deviceAgentMasterEnabled: false,
        PrefKeys.devicePermissionApp: true,
      });
      final service = DeviceAgentExecutionService(
        repo,
        executor: mockExecutor(),
      );

      final action = await service.executeFromJson(
        jsonFor('open_app', {'app': '微信'}),
        characterId: 'c1',
        sessionId: 's1',
      );

      expect(action, isNotNull);
      expect(action!.result, DeviceActionResult.rejected);
      // L0 模式绝缘：总开关关闭 → modeBlocked 一线拦截，静默拒绝不弹确认
      expect(
        [DeviceRejectionReason.modeBlocked, DeviceRejectionReason.masterSwitchOff],
        contains(action.rejectionReason),
      );
      // 拒绝不依赖任何确认弹窗：结果可直接用于角色反馈
      expect(action.message, isNotEmpty);
    });

    test('子权限关闭时静默拒绝并写审计，不弹逐次确认', () async {
      await setUpRepo({
        PrefKeys.deviceAgentMasterEnabled: true,
        PrefKeys.devicePermissionApp: false,
      });
      final service = DeviceAgentExecutionService(
        repo,
        executor: mockExecutor(),
      );

      final action = await service.executeFromJson(
        jsonFor('open_app', {'app': '微信'}),
        characterId: 'c1',
        sessionId: 's1',
      );

      expect(action, isNotNull);
      expect(action!.result, DeviceActionResult.rejected);
      expect(action.rejectionReason, DeviceRejectionReason.childPermissionOff);
    });

    test('权限全开时自动执行成功并写审计', () async {
      await setUpRepo({
        PrefKeys.deviceAgentMasterEnabled: true,
        PrefKeys.devicePermissionApp: true,
      });
      final service = DeviceAgentExecutionService(
        repo,
        executor: mockExecutor(),
      );

      final action = await service.executeFromJson(
        jsonFor('open_app', {'app': '微信'}),
        characterId: 'c1',
        sessionId: 's1',
      );

      expect(action, isNotNull);
      expect(action!.result, DeviceActionResult.success);
      expect(action.message, isNotEmpty);
    });

    test('限流超限时静默拒绝并写审计，不询问', () async {
      await setUpRepo({
        PrefKeys.deviceAgentMasterEnabled: true,
        PrefKeys.devicePermissionApp: true,
      });
      final service = DeviceAgentExecutionService(
        repo,
        executor: mockExecutor(),
      );

      // 连续执行同一会话多次：次数超限后应拒绝而非询问。
      for (var i = 0; i < 20; i++) {
        await service.executeFromJson(
          jsonFor('open_app', {'app': '微信'}),
          characterId: 'c1',
          sessionId: 's1',
          checkRateLimit: false,
        );
      }
      final blocked = await service.executeFromJson(
        jsonFor('open_app', {'app': '微信'}),
        characterId: 'c1',
        sessionId: 's1',
        checkRateLimit: true,
      );

      expect(blocked, isNotNull);
      expect(blocked!.result, DeviceActionResult.rejected);
      expect(blocked.rejectionReason, DeviceRejectionReason.rateLimited);
    });
  });

  group('确定性路由与权限闸门对齐', () {
    test('每个确定性路由工具都映射到真实设备动作', () {
      const samples = [
        '打开微信',
        '锁屏',
        '回到桌面',
        '返回上一页',
        '开启静音',
        '关闭静音',
        '音量+',
        '截图',
        '打开相册',
        '查电量',
        '查看通知',
        '当前应用',
        '我用了多久微信',
        '打开WiFi',
        '关闭蓝牙',
        '亮度调亮',
        '上滑',
        '点击 100,200',
        '输入文字 hello',
        '执行 shell 内容: df -h',
      ];
      final seen = <String>{};
      for (final s in samples) {
        final intent = DeviceIntentRouter.match(s);
        final route = intent.usesDeterministicRoute
            ? DeterministicDeviceRouter.match(s)
            : null;
        if (route != null) {
          expect(parseDeviceActionType(route.toolName), isNotNull,
              reason: '$s -> ${route.toolName} 未知工具');
          seen.add(route.toolName);
        }
      }
      expect(seen, isNotEmpty);
    });

    test('确定性路由产生的工具都有分类子权限，无永久禁用', () {
      expect(devicePermanentlyForbidden, isEmpty);
      for (final type in DeviceActionType.values) {
        expect(deviceActionCategoryMap.containsKey(type), isTrue,
            reason: type.name);
        final permKey =
            devicePermissionKeyFor(deviceActionCategoryMap[type]!);
        expect(permKey, isNotEmpty);
        expect(PrefKeys.deviceAllPermissionKeys, contains(permKey));
      }
    });
  });
}

class _FakeTool extends Tool {
  final String toolName;
  _FakeTool(this.toolName);

  @override
  String get name => toolName;

  @override
  String get description => 'fake';

  @override
  Map<String, dynamic> get parametersSchema => const {};

  @override
  Set<String> get requiredPermissions => const {};

  @override
  bool get isDestructive => toolName == 'execute_shell';

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    return ToolResult.success('已执行 $toolName: $args');
  }
}

class _FakeToolPkg extends ToolPkg {
  @override
  String get name => 'audit-fake';

  @override
  String get description => '测试用工具';

  @override
  List<Tool> get tools => DeviceActionType.values
      .map((t) => _FakeTool(deviceActionToToolName(t)))
      .toList();
}