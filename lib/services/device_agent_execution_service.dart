import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../config/constants.dart';
import '../models/device_agent_action.dart';
import '../repositories/local_storage_repository.dart';
import 'device_action_policy.dart';
import 'device_persona_strategy.dart';
import 'tools/tool_executor.dart';
import 'tools/tool_registry.dart';
import 'tools/tools.dart';

/// Device Agent 执行服务（BT 同构 · 全量工具）
///
/// 分层：
/// 0. 模式绝缘（pureAi / 默认叙事模式）
/// 1. 永久禁用（空集，靠子权限）
/// 2. 解析动作
/// 3. 总开关
/// 4. 子权限
/// 5. DeviceActionPolicy 频控（与 L0 共用）
/// 6. ToolExecutor
/// 7. 审计 + 回灌队列
class DeviceAgentExecutionService {
  final LocalStorageRepository _repo;
  final ToolExecutor _executor;
  final DeviceActionPolicy _policy = DeviceActionPolicy.instance;

  static const int maxActionsPerReply = 1;

  DeviceAgentExecutionService(
    this._repo, {
    ToolRegistry? registry,
    ToolExecutor? executor,
  }) : _executor =
            executor ?? ToolExecutor(registry ?? createToolRegistry());

  bool isRolePathAllowed() {
    if (!_repo.isDeviceAgentMasterEnabled()) return false;
    if (_repo.isPureAiModeEnabled()) return false;
    final narrative =
        _repo.isChatStyleNovelModeEnabled() || _repo.isFaModeEnabled();
    if (narrative && !isAllowInNarrative()) return false;
    return true;
  }

  bool isAllowInNarrative() => _repo.isDeviceAgentAllowInNarrative();

  Future<({String visibleText, List<DeviceAgentAction> actions})>
      processActionTags(
    String text, {
    required String characterId,
    required String sessionId,
  }) async {
    if (text.isEmpty || !text.contains('<DEVICE_ACTION>')) {
      return (visibleText: text, actions: <DeviceAgentAction>[]);
    }

    final pattern = RegExp(
      r'<DEVICE_ACTION>\s*(\{[\s\S]*?\})\s*</DEVICE_ACTION>',
      caseSensitive: false,
    );
    final matches = pattern.allMatches(text).toList();
    final visible = text.replaceAll(pattern, '').trim();

    if (!isRolePathAllowed()) {
      debugPrint('[DeviceAgent] 模式绝缘，仅剥离标签');
      return (visibleText: visible, actions: <DeviceAgentAction>[]);
    }
    if (matches.isEmpty) {
      return (visibleText: visible, actions: <DeviceAgentAction>[]);
    }

    final actions = <DeviceAgentAction>[];
    for (final match in matches) {
      if (actions.where((a) => a.result == DeviceActionResult.success).length >=
          maxActionsPerReply) {
        break;
      }
      final jsonStr = match.group(1)?.trim() ?? '';
      if (jsonStr.isEmpty) continue;
      final log = await executeFromJson(
        jsonStr,
        characterId: characterId,
        sessionId: sessionId,
      );
      if (log != null) actions.add(log);
    }
    return (visibleText: visible, actions: actions);
  }

  /// 工具是否被用户子权限允许（Desire 引擎裁剪时用）
  bool isToolPermitted(String toolName) {
    if (!isRolePathAllowed()) return false;
    final type = parseDeviceActionType(toolName);
    if (type == null) return false;
    final cat =
        deviceActionCategoryMap[type] ?? DevicePermissionCategory.read;
    return _repo.isDevicePermissionEnabled(_prefKey(cat));
  }

  String? consumeFeedback(String sessionId) =>
      _policy.consumeFeedback(sessionId);

  Future<DeviceAgentAction?> executeFromJson(
    String jsonStr, {
    required String characterId,
    required String sessionId,
  }) async {
    Map<String, dynamic> map;
    try {
      final cleaned = _cleanJson(jsonStr);
      final decoded = json.decode(cleaned);
      if (decoded is! Map) {
        return _reject(
          actionType: DeviceActionType.getBatteryInfo,
          category: DevicePermissionCategory.read,
          reason: '根节点不是对象',
          rejection: DeviceRejectionReason.parseError,
          characterId: characterId,
          sessionId: sessionId,
        );
      }
      map = Map<String, dynamic>.from(decoded);
    } catch (e) {
      debugPrint('[DeviceAgent] JSON 解析失败: $e');
      return _reject(
        actionType: DeviceActionType.getBatteryInfo,
        category: DevicePermissionCategory.read,
        reason: 'JSON 解析失败: $e',
        rejection: DeviceRejectionReason.parseError,
        characterId: characterId,
        sessionId: sessionId,
      );
    }

    final actionName = (map['action'] ?? map['tool'] ?? '').toString().trim();
    final reason = (map['reason'] ?? '').toString();
    Map<String, dynamic> params = {};
    final rawParams = map['params'] ?? map['args'] ?? map;
    if (rawParams is Map) {
      params = Map<String, dynamic>.from(rawParams)
        ..remove('action')
        ..remove('tool')
        ..remove('reason')
        ..remove('type');
    }

    if (!isRolePathAllowed()) {
      return _reject(
        actionType: DeviceActionType.getBatteryInfo,
        category: DevicePermissionCategory.read,
        reason: reason,
        rejection: DeviceRejectionReason.modeBlocked,
        characterId: characterId,
        sessionId: sessionId,
        message: '当前模式禁止 Device Agent',
        params: params,
      );
    }

    if (devicePermanentlyForbidden.contains(actionName) ||
        devicePermanentlyForbidden.contains(actionName.toLowerCase())) {
      return _reject(
        actionType: DeviceActionType.getBatteryInfo,
        category: DevicePermissionCategory.read,
        reason: reason.isEmpty ? '永久禁用: $actionName' : reason,
        rejection: DeviceRejectionReason.permanentlyForbidden,
        characterId: characterId,
        sessionId: sessionId,
        message: '拒绝: $actionName',
        params: params,
      );
    }

    final actionType = parseDeviceActionType(actionName);
    if (actionType == null) {
      return _reject(
        actionType: DeviceActionType.getBatteryInfo,
        category: DevicePermissionCategory.read,
        reason: reason.isEmpty ? '未知动作: $actionName' : reason,
        rejection: DeviceRejectionReason.whitelistMismatch,
        characterId: characterId,
        sessionId: sessionId,
        message: '不在工具表: $actionName',
        params: params,
      );
    }

    final category =
        deviceActionCategoryMap[actionType] ?? DevicePermissionCategory.read;

    if (!_repo.isDeviceAgentMasterEnabled()) {
      return _reject(
        actionType: actionType,
        category: category,
        reason: reason,
        rejection: DeviceRejectionReason.masterSwitchOff,
        characterId: characterId,
        sessionId: sessionId,
        params: params,
      );
    }

    final permKey = _prefKey(category);
    if (!_repo.isDevicePermissionEnabled(permKey)) {
      return _reject(
        actionType: actionType,
        category: category,
        reason: reason,
        rejection: DeviceRejectionReason.childPermissionOff,
        characterId: characterId,
        sessionId: sessionId,
        params: params,
      );
    }

    if (!_policy.allow(sessionId)) {
      return _reject(
        actionType: actionType,
        category: category,
        reason: reason,
        rejection: DeviceRejectionReason.rateLimited,
        characterId: characterId,
        sessionId: sessionId,
        message: '操作过快，已限流',
        params: params,
      );
    }

    final toolName = deviceActionToToolName(actionType);
    final toolArgs = _normalizeArgs(actionType, params);
    final stateBefore = 'tool=$toolName args=$toolArgs';

    try {
      final record = await _executor.execute(toolName, toolArgs);
      final result = record.result;
      final log = DeviceAgentAction(
        actionType: actionType,
        category: category,
        params: toolArgs,
        reason: reason,
        stateBefore: stateBefore,
        stateAfter: result.message,
        result: result.success
            ? DeviceActionResult.success
            : DeviceActionResult.failed,
        rejectionReason: result.success ? null : DeviceRejectionReason.unknown,
        characterId: characterId,
        sessionId: sessionId,
        message: result.message,
      );
      await _repo.saveDeviceAgentAction(log);
      if (result.success) {
        _policy.markSuccess(sessionId);
        _policy.pushFeedback(
          sessionId: sessionId,
          toolName: toolName,
          message: result.message,
          success: true,
          isRead: _policy.isReadAction(actionType),
        );
      }
      debugPrint(
          '[DeviceAgent] ${result.success ? "OK" : "FAIL"} $toolName → ${result.message}');
      return log;
    } catch (e) {
      final log = DeviceAgentAction(
        actionType: actionType,
        category: category,
        params: toolArgs,
        reason: reason,
        stateBefore: stateBefore,
        result: DeviceActionResult.failed,
        rejectionReason: DeviceRejectionReason.unknown,
        characterId: characterId,
        sessionId: sessionId,
        message: '执行异常: $e',
      );
      await _repo.saveDeviceAgentAction(log);
      return log;
    }
  }

  String _prefKey(DevicePermissionCategory category) {
    switch (category) {
      case DevicePermissionCategory.read:
        return PrefKeys.devicePermissionRead;
      case DevicePermissionCategory.display:
        return PrefKeys.devicePermissionDisplay;
      case DevicePermissionCategory.audio:
        return PrefKeys.devicePermissionAudio;
      case DevicePermissionCategory.lock:
        return PrefKeys.devicePermissionLock;
      case DevicePermissionCategory.app:
        return PrefKeys.devicePermissionApp;
      case DevicePermissionCategory.network:
        return PrefKeys.devicePermissionNetwork;
      case DevicePermissionCategory.ui:
        return PrefKeys.devicePermissionUi;
      case DevicePermissionCategory.shell:
        return PrefKeys.devicePermissionShell;
    }
  }

  Map<String, dynamic> _normalizeArgs(
    DeviceActionType type,
    Map<String, dynamic> params,
  ) {
    switch (type) {
      case DeviceActionType.setBrightness:
        final level = (params['level'] as num?)?.toInt() ??
            int.tryParse(params['level']?.toString() ?? '') ??
            128;
        return {'level': level.clamp(0, 255)};
      case DeviceActionType.adjustVolume:
        final d = (params['direction'] ?? 'down').toString().toLowerCase();
        return {'direction': d == 'up' ? 'up' : 'down'};
      case DeviceActionType.setMute:
        final muted = params['muted'];
        final boolVal = muted is bool
            ? muted
            : muted?.toString().toLowerCase() != 'false';
        return {'muted': boolVal};
      case DeviceActionType.openApp:
      case DeviceActionType.closeApp:
        return {
          'app': (params['app'] ?? params['package'] ?? '').toString(),
        };
      case DeviceActionType.toggleWifi:
      case DeviceActionType.toggleBluetooth:
        final enable = params['enable'];
        final boolVal = enable is bool
            ? enable
            : enable?.toString().toLowerCase() != 'false';
        return {'enable': boolVal};
      case DeviceActionType.tap:
        return {
          'x': (params['x'] as num?)?.toInt() ??
              int.tryParse(params['x']?.toString() ?? '') ??
              0,
          'y': (params['y'] as num?)?.toInt() ??
              int.tryParse(params['y']?.toString() ?? '') ??
              0,
        };
      case DeviceActionType.swipe:
        int parseCoord(List<String> keys) {
          for (final k in keys) {
            final v = params[k];
            if (v is num) return v.toInt();
            final p = int.tryParse(v?.toString() ?? '');
            if (p != null) return p;
          }
          return 0;
        }
        return {
          'start_x': parseCoord(['start_x', 'x1']),
          'start_y': parseCoord(['start_y', 'y1']),
          'end_x': parseCoord(['end_x', 'x2']),
          'end_y': parseCoord(['end_y', 'y2']),
          'duration': (params['duration'] as num?)?.toInt() ??
              int.tryParse(params['duration']?.toString() ?? '') ??
              300,
        };
      case DeviceActionType.inputText:
        return {'text': (params['text'] ?? '').toString()};
      case DeviceActionType.pressKey:
        return {
          'keycode': (params['keycode'] as num?)?.toInt() ??
              int.tryParse(params['keycode']?.toString() ?? '') ??
              0,
        };
      case DeviceActionType.executeShell:
        return {
          'command': (params['command'] ?? params['cmd'] ?? '').toString(),
        };
      case DeviceActionType.getAppUsageTime:
        return {
          if (params['app'] != null) 'app': params['app'].toString(),
          if (params['package'] != null)
            'package': params['package'].toString(),
          if (params['days'] != null)
            'days': (params['days'] as num?)?.toInt() ??
                int.tryParse(params['days']?.toString() ?? '') ??
                1,
        };
      case DeviceActionType.getNotifications:
        return {
          if (params['limit'] != null)
            'limit': (params['limit'] as num?)?.toInt() ??
                int.tryParse(params['limit']?.toString() ?? '') ??
                20,
        };
      case DeviceActionType.lockScreen:
      case DeviceActionType.getBatteryInfo:
      case DeviceActionType.getCurrentApp:
      case DeviceActionType.getInstalledApps:
      case DeviceActionType.getNotificationCount:
      case DeviceActionType.takeScreenshot:
      case DeviceActionType.goHome:
      case DeviceActionType.pressBack:
      case DeviceActionType.openGallery:
        return Map<String, dynamic>.from(params);
    }
  }

  String _cleanJson(String s) {
    var cleaned = s.trim();
    cleaned = cleaned.replaceAll(
        RegExp(r'^```(?:json)?\s*', caseSensitive: false), '');
    cleaned = cleaned.replaceAll(RegExp(r'\s*```$'), '');
    cleaned = cleaned.replaceAll(RegExp(r',\s*([}\]])'), r'$1');
    return cleaned.trim();
  }

  Future<DeviceAgentAction> _reject({
    required DeviceActionType actionType,
    required DevicePermissionCategory category,
    required String reason,
    required DeviceRejectionReason rejection,
    required String characterId,
    required String sessionId,
    String message = '',
    Map<String, dynamic> params = const {},
  }) async {
    final log = DeviceAgentAction(
      actionType: actionType,
      category: category,
      params: params,
      reason: reason,
      result: DeviceActionResult.rejected,
      rejectionReason: rejection,
      characterId: characterId,
      sessionId: sessionId,
      message: message.isEmpty ? rejection.name : message,
    );
    await _repo.saveDeviceAgentAction(log);
    debugPrint('[DeviceAgent] 拒绝 ${actionType.name}: ${rejection.name}');
    return log;
  }
}
