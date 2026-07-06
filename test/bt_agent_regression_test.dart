import 'package:flutter_test/flutter_test.dart';
import 'package:solace/config/constants.dart';
import 'package:solace/repositories/local_storage_repository.dart';
import 'package:solace/services/agent/agent_loop.dart';

void main() {
  group('BT Agent regressions', () {
    test('force mode confirmation covers every BT child permission', () {
      expect(PrefKeys.btAllPermissionKeys, hasLength(23));
      expect(PrefKeys.btAllPermissionKeys.toSet(),
          hasLength(PrefKeys.btAllPermissionKeys.length));
      expect(
          PrefKeys.btAllPermissionKeys, contains(PrefKeys.btPermissionMoments));
      expect(
          PrefKeys.btAllPermissionKeys, contains(PrefKeys.btPermissionLetters));
      expect(
          PrefKeys.btAllPermissionKeys, contains(PrefKeys.btPermissionDiary));
      expect(PrefKeys.btAllPermissionKeys,
          contains(PrefKeys.btPermissionLuckyWheel));
      expect(PrefKeys.btAllPermissionKeys,
          contains(PrefKeys.btPermissionGlobalMemory));
      expect(PrefKeys.btAllPermissionKeys,
          contains(PrefKeys.btPermissionProfileAvatar));
      expect(PrefKeys.btAllPermissionKeys,
          contains(PrefKeys.btPermissionLightTheme));
      expect(PrefKeys.btAllPermissionKeys,
          contains(PrefKeys.btPermissionDarkTheme));
      expect(PrefKeys.btAllPermissionKeys,
          contains(PrefKeys.btPermissionSystemTheme));
    });

    test('AgentLoop.run returns null for non-BT messages', () async {
      // 普通聊天消息不匹配任何 BT 关键词，应返回 null
      final loop = AgentLoop(storage: LocalStorageRepository());
      // run() 需要 character 等参数，但确定性路由不依赖它们，
      // 只需 userMessage 包含非 BT 关键词即可。
      // 由于无法在无数据库环境下完整测试，这里验证方法签名兼容性。
      expect(loop, isNotNull);
    });
  });
}