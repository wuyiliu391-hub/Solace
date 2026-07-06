import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../config/constants.dart';
import '../models/bt_agent_action.dart';
import '../repositories/local_storage_repository.dart';
import 'bt_operation_lock_service.dart';
import 'device_automation_service.dart';

/// BT Agent 执行服务
///
/// 职责：
/// 1. 解析 AI 返回的结构化 JSON 动作
/// 2. 校验总开关 → 子权限 → 禁用项 → 白名单
/// 3. 派发到 Repository 层执行
/// 4. 记录审计日志（成功/拒绝/失败均记录）
class BtAgentExecutionService {
  final LocalStorageRepository _repo;

  BtAgentExecutionService(this._repo);

  // ─── 动作 → 子权限键映射 ───
  static const Map<BtActionType, String> _actionPermissionKeyMap = {
    // 通讯录
    BtActionType.updateContactRemark: PrefKeys.btPermissionContactRemark,
    BtActionType.updateContactAvatar: PrefKeys.btPermissionContactAvatar,
    BtActionType.hideContact: PrefKeys.btPermissionContactHide,
    BtActionType.deleteContact: PrefKeys.btPermissionContactDelete,
    // 角色 & 互动
    BtActionType.setOnlineStatus: PrefKeys.btPermissionOnlineStatus,
    BtActionType.setSaveStatus: PrefKeys.btPermissionSaveStatus,
    BtActionType.setMessageDisturb: PrefKeys.btPermissionMessageDisturb,
    BtActionType.setVideoChat: PrefKeys.btPermissionVideoChat,
    BtActionType.toggleBlock: PrefKeys.btPermissionBlock,
    BtActionType.clearChatHistory: PrefKeys.btPermissionClearHistory,
    BtActionType.deleteMessage: PrefKeys.btPermissionClearHistory,
    BtActionType.deleteCharacter: PrefKeys.btPermissionResetPersonaMemory,
    BtActionType.clearCharacterMemory: PrefKeys.btPermissionResetPersonaMemory,
    BtActionType.resetCharacterPersona: PrefKeys.btPermissionResetPersonaMemory,
    BtActionType.deleteChatSession: PrefKeys.btPermissionClearHistory,
    BtActionType.clearGroupContent: PrefKeys.btPermissionClearHistory,
    BtActionType.insertSystemMessage: PrefKeys.btPermissionMessageDisturb,
    BtActionType.reportCharacter: PrefKeys.btPermissionReport,

    // 设备操控
    BtActionType.phoneTap: PrefKeys.btPermissionDeviceTap,
    BtActionType.phoneSwipe: PrefKeys.btPermissionDeviceSwipe,
    BtActionType.phoneLongPress: PrefKeys.btPermissionDeviceLongPress,
    BtActionType.phoneBack: PrefKeys.btPermissionDeviceNavigate,
    BtActionType.phoneHome: PrefKeys.btPermissionDeviceNavigate,
    BtActionType.phoneRecentApps: PrefKeys.btPermissionDeviceNavigate,
    BtActionType.phoneScroll: PrefKeys.btPermissionDeviceSwipe,
    BtActionType.phoneTypeText: PrefKeys.btPermissionDeviceTypeText,
    BtActionType.phoneClickText: PrefKeys.btPermissionDeviceClickText,
    BtActionType.phoneOpenApp: PrefKeys.btPermissionDeviceOpenApp,
    BtActionType.phoneScreenRead: PrefKeys.btPermissionDeviceScreenRead,
    BtActionType.phoneGetNotifications: PrefKeys.btPermissionDeviceNotifications,
    BtActionType.phoneTakeScreenshot: PrefKeys.btPermissionDeviceScreenshot,
    BtActionType.phoneOpenNotificationsPanel: PrefKeys.btPermissionDeviceNotifications,
    BtActionType.phoneQuickSettings: PrefKeys.btPermissionDeviceNotifications,
    BtActionType.phoneSetWifi: PrefKeys.btPermissionDeviceSystemSettings,
    BtActionType.phoneSetBluetooth: PrefKeys.btPermissionDeviceSystemSettings,
    BtActionType.phoneSetVolume: PrefKeys.btPermissionDeviceSystemSettings,
    BtActionType.phoneSetBrightness: PrefKeys.btPermissionDeviceSystemSettings,
    BtActionType.phoneExecShell: PrefKeys.btPermissionDeviceShell,
    BtActionType.phoneInstallApp: PrefKeys.btPermissionDeviceAppManagement,
    BtActionType.phoneUninstallApp: PrefKeys.btPermissionDeviceAppManagement,
    BtActionType.phoneGrantPermission: PrefKeys.btPermissionDeviceShell,
    // 发现页
    BtActionType.postMoment: PrefKeys.btPermissionMoments,
    BtActionType.deleteMoment: PrefKeys.btPermissionMoments,
    BtActionType.hideMoment: PrefKeys.btPermissionMoments,
    BtActionType.commentMoment: PrefKeys.btPermissionMoments,
    BtActionType.clearMomentsData: PrefKeys.btPermissionMoments,
    BtActionType.sendLetter: PrefKeys.btPermissionLetters,
    BtActionType.deleteLetter: PrefKeys.btPermissionLetters,
    BtActionType.markLetter: PrefKeys.btPermissionLetters,
    BtActionType.clearLettersData: PrefKeys.btPermissionLetters,
    BtActionType.createDiary: PrefKeys.btPermissionDiary,
    BtActionType.modifyDiary: PrefKeys.btPermissionDiary,
    BtActionType.deleteDiary: PrefKeys.btPermissionDiary,
    BtActionType.clearDiaryData: PrefKeys.btPermissionDiary,
    BtActionType.triggerLuckyWheel: PrefKeys.btPermissionLuckyWheel,
    BtActionType.clearLuckyWheelData: PrefKeys.btPermissionLuckyWheel,
    BtActionType.queryGlobalMemory: PrefKeys.btPermissionGlobalMemory,
    BtActionType.organizeGlobalMemory: PrefKeys.btPermissionGlobalMemory,
    BtActionType.deleteGlobalMemoryItem: PrefKeys.btPermissionGlobalMemory,
    // 个人资料
    BtActionType.updateProfileAvatar: PrefKeys.btPermissionProfileAvatar,
    BtActionType.updateProfileNickname: PrefKeys.btPermissionProfileNickname,
    // 外观主题
    BtActionType.setLightTheme: PrefKeys.btPermissionLightTheme,
    BtActionType.setDarkTheme: PrefKeys.btPermissionDarkTheme,
    BtActionType.setSystemTheme: PrefKeys.btPermissionSystemTheme,
  };

  // ─── 永久禁用动作关键字 ───
  static const Set<String> _permanentlyForbiddenActions = {
    'logout',
    'sign_out',
    'signOut',
    'export_data',
    'exportData',
    'import_data',
    'importData',
    'change_api_key',
    'changeApiKey',
    'modify_model',
    'modifyModel',
    'change_model',
    'changeModel',
    'reset_ai_config',
    'resetAiConfig',
  };

  /// 解析并执行 AI 返回的 BT 动作 JSON
  ///
  /// 输入格式：单个 JSON 对象或 JSON 数组
  Future<List<BtAgentAction>> executeFromJson(
    String jsonStr, {
    required String characterId,
    required String sessionId,
    String chatType = 'single',
  }) async {
    final results = <BtAgentAction>[];

    List<Map<String, dynamic>> actionMaps;
    try {
      final decoded = json.decode(jsonStr.trim());
      if (decoded is List) {
        actionMaps = decoded.cast<Map<String, dynamic>>();
      } else if (decoded is Map<String, dynamic>) {
        final type = decoded['type']?.toString() ?? '';
        if (type == 'chat') {
          return results;
        }
        if (type == 'action') {
          final params = decoded['params'];
          final paramMap =
              params is Map<String, dynamic> ? params : <String, dynamic>{};
          actionMaps = [
            {
              'action': decoded['action']?.toString() ?? '',
              'target_id': (paramMap['target_id'] ??
                      paramMap['targetId'] ??
                      paramMap['id'] ??
                      decoded['targetControl'] ??
                      '')
                  .toString(),
              'value': (paramMap['value'] ?? '').toString(),
              'reason': (paramMap['reason'] ??
                      decoded['reason'] ??
                      'BT 模式动作请求：${decoded['targetPage'] ?? ''}/${decoded['targetControl'] ?? ''}')
                  .toString(),
            }
          ];
        } else {
          actionMaps = [decoded];
        }
      } else {
        return results;
      }
    } catch (e) {
      debugPrint('[BT] JSON 解析失败: $e');
      return results;
    }

    for (final map in actionMaps) {
      if (!_repo.isBtYandereMasterEnabled() ||
          BtOperationLockService.instance.isInterrupted) {
        await _repo.saveBtAgentAction(BtAgentAction(
          actionType: BtActionType.deleteMessage,
          category: BtPermissionCategory.interaction,
          scope: BtActionScope.chatScope,
          targetType: BtTargetType.none,
          reason: '用户主动关停模式，操作中断；剩余排队动作已取消',
          result: BtActionResult.rejected,
          rejectionReason: BtRejectionReason.masterSwitchOff,
          characterId: characterId,
          sessionId: sessionId,
          chatType: chatType,
        ));
        break;
      }
      final action = await _executeSingle(
        map,
        characterId: characterId,
        sessionId: sessionId,
        chatType: chatType,
      );
      if (action != null) results.add(action);
    }

    return results;
  }

  /// 执行单个动作
  Future<BtAgentAction?> _executeSingle(
    Map<String, dynamic> map, {
    required String characterId,
    required String sessionId,
    required String chatType,
  }) async {
    final actionName = map['action'] as String? ?? '';
    final targetId = map['target_id'] as String? ?? '';
    final value = map['value']?.toString() ?? '';
    final reason = map['reason'] as String? ?? '';

    // ── 层 1：永久禁用拦截 ──
    if (_permanentlyForbiddenActions.contains(actionName)) {
      final log = _buildLog(
        actionType: BtActionType.deleteMessage,
        category: BtPermissionCategory.interaction,
        scope: BtActionScope.chatScope,
        targetType: BtTargetType.none,
        targetId: targetId,
        reason: reason,
        result: BtActionResult.rejected,
        rejectionReason: BtRejectionReason.permanentlyForbidden,
        characterId: characterId,
        sessionId: sessionId,
        chatType: chatType,
      );
      await _repo.saveBtAgentAction(log);
      debugPrint('[BT] 拒绝(永久禁用): $actionName');
      return log;
    }

    // ── 层 2：解析动作类型 ──
    final actionType = _parseActionType(actionName);
    if (actionType == null) {
      final log = _buildLog(
        actionType: BtActionType.deleteMessage,
        category: BtPermissionCategory.interaction,
        scope: BtActionScope.chatScope,
        targetType: BtTargetType.none,
        targetId: targetId,
        reason: reason,
        result: BtActionResult.rejected,
        rejectionReason: BtRejectionReason.parseError,
        characterId: characterId,
        sessionId: sessionId,
        chatType: chatType,
      );
      await _repo.saveBtAgentAction(log);
      debugPrint('[BT] 拒绝(解析失败): $actionName');
      return log;
    }

    final lockKey = _buildOperationLockKey(actionType, targetId);
    final lockedAt = DateTime.now();
    var lockStarted = false;

    try {
      await _lockOperation(
        lockKey: lockKey,
        actionType: actionType,
        targetId: targetId,
        reason: reason,
        characterId: characterId,
        sessionId: sessionId,
        chatType: chatType,
        lockedAt: lockedAt,
      );
      lockStarted = true;

      // ── 层 3：总开关校验 ──
      if (!_repo.isBtYandereMasterEnabled() ||
          BtOperationLockService.instance.isInterrupted) {
        final log = _buildActionLog(
          actionType: actionType,
          targetId: targetId,
          reason: reason,
          result: BtActionResult.rejected,
          rejectionReason: BtRejectionReason.masterSwitchOff,
          characterId: characterId,
          sessionId: sessionId,
          chatType: chatType,
        );
        await _repo.saveBtAgentAction(log);
        debugPrint('[BT] 拒绝(总开关关闭): $actionName');
        return log;
      }

      // ── 层 4：子权限校验 ──
      final permKey = _actionPermissionKeyMap[actionType];
      if (permKey != null && !_repo.isBtPermissionEnabled(permKey)) {
        final log = _buildActionLog(
          actionType: actionType,
          targetId: targetId,
          reason: reason,
          result: BtActionResult.rejected,
          rejectionReason: BtRejectionReason.childPermissionOff,
          characterId: characterId,
          sessionId: sessionId,
          chatType: chatType,
        );
        await _repo.saveBtAgentAction(log);
        debugPrint('[BT] 拒绝(子权限关闭): $actionName');
        return log;
      }

      // ── 层 5：执行白名单派发 ──
      final stateBefore = await _captureState(actionType, targetId);
      if (!_repo.isBtYandereMasterEnabled() ||
          BtOperationLockService.instance.isInterrupted) {
        final log = _buildActionLog(
          actionType: actionType,
          targetId: targetId,
          reason: '用户主动关停模式，操作中断',
          stateBefore: stateBefore,
          result: BtActionResult.rejected,
          rejectionReason: BtRejectionReason.masterSwitchOff,
          characterId: characterId,
          sessionId: sessionId,
          chatType: chatType,
        );
        await _repo.saveBtAgentAction(log);
        return log;
      }
      await _dispatch(actionType,
          targetId: targetId, value: value, sessionId: sessionId);
      final stateAfter = await _captureState(actionType, targetId);

      final log = _buildActionLog(
        actionType: actionType,
        targetId: targetId,
        reason: reason,
        stateBefore: stateBefore,
        stateAfter: stateAfter,
        result: BtActionResult.success,
        characterId: characterId,
        sessionId: sessionId,
        chatType: chatType,
      );
      await _repo.saveBtAgentAction(log);
      debugPrint('[BT] 执行成功: $actionName → $targetId');
      return log;
    } catch (e) {
      final log = _buildActionLog(
        actionType: actionType,
        targetId: targetId,
        reason: reason,
        result: BtActionResult.failed,
        rejectionReason: BtRejectionReason.unknown,
        characterId: characterId,
        sessionId: sessionId,
        chatType: chatType,
      );
      await _repo.saveBtAgentAction(log);
      debugPrint('[BT] 执行失败: $actionName → $e');
      return log;
    } finally {
      if (lockStarted) {
        await _unlockOperation(
          lockKey: lockKey,
          actionType: actionType,
          targetId: targetId,
          reason: reason,
          characterId: characterId,
          sessionId: sessionId,
          chatType: chatType,
          lockedAt: lockedAt,
        );
      }
    }
  }

  String _buildOperationLockKey(BtActionType actionType, String targetId) {
    final category =
        btActionCategoryMap[actionType] ?? BtPermissionCategory.interaction;
    final scope = _inferScope(category);
    final targetType = _inferTargetType(actionType);
    return BtOperationLockService.instance.buildLockKey(
      category: category,
      scope: scope,
      targetType: targetType,
      targetId: targetId,
      actionType: actionType,
    );
  }

  Future<void> _lockOperation({
    required String lockKey,
    required BtActionType actionType,
    required String targetId,
    required String reason,
    required String characterId,
    required String sessionId,
    required String chatType,
    required DateTime lockedAt,
  }) async {
    final category =
        btActionCategoryMap[actionType] ?? BtPermissionCategory.interaction;
    final scope = _inferScope(category);
    final targetType = _inferTargetType(actionType);
    BtOperationLockService.instance.lock(
      key: lockKey,
      actionType: actionType,
      category: category,
      scope: scope,
      targetType: targetType,
      targetId: targetId,
      characterId: characterId,
      sessionId: sessionId,
      chatType: chatType,
      reason: reason,
    );
    await _repo.saveBtAgentAction(BtAgentAction(
      actionType: actionType,
      category: category,
      scope: scope,
      targetType: targetType,
      targetId: targetId,
      reason:
          '局部锁定开始：$reason；lockKey=$lockKey；lockedAt=${lockedAt.toIso8601String()}',
      result: BtActionResult.success,
      characterId: characterId,
      sessionId: sessionId,
      chatType: chatType,
    ));
  }

  Future<void> _unlockOperation({
    required String lockKey,
    required BtActionType actionType,
    required String targetId,
    required String reason,
    required String characterId,
    required String sessionId,
    required String chatType,
    required DateTime lockedAt,
  }) async {
    BtOperationLockService.instance.unlock(lockKey);
    final unlockedAt = DateTime.now();
    final category =
        btActionCategoryMap[actionType] ?? BtPermissionCategory.interaction;
    final scope = _inferScope(category);
    final targetType = _inferTargetType(actionType);
    await _repo.saveBtAgentAction(BtAgentAction(
      actionType: actionType,
      category: category,
      scope: scope,
      targetType: targetType,
      targetId: targetId,
      reason:
          '局部锁定解除：$reason；lockKey=$lockKey；lockedAt=${lockedAt.toIso8601String()}；unlockedAt=${unlockedAt.toIso8601String()}',
      result: BtActionResult.success,
      characterId: characterId,
      sessionId: sessionId,
      chatType: chatType,
    ));
  }

  /// 解析动作名称到枚举
  BtActionType? _parseActionType(String name) {
    for (final t in BtActionType.values) {
      if (t.name == name) return t;
    }
    return null;
  }

  /// 执行前捕获状态快照
  Future<String> _captureState(BtActionType type, String targetId) async {
    try {
      switch (type) {
        case BtActionType.setOnlineStatus:
          final ch = await _repo.getAICharacter(targetId);
          return ch != null ? 'isOnline=${ch.isOnline}' : '';
        case BtActionType.hideContact:
          final ch = await _repo.getAICharacter(targetId);
          return ch != null ? 'isHidden=${ch.isHidden}' : '';
        case BtActionType.toggleBlock:
          final session = await _repo.getChatSession(targetId);
          return session != null ? 'isBlocked=${session.isBlocked}' : '';
        case BtActionType.setLightTheme:
        case BtActionType.setDarkTheme:
        case BtActionType.setSystemTheme:
          return 'themeMode=${_repo.getString(PrefKeys.themeMode) ?? 'system'}';
        case BtActionType.updateProfileNickname:
          final userId = _repo.getString(PrefKeys.currentUserId) ?? 'default';
          final user = await _repo.getUser(userId);
          return user != null ? 'nickname=${user.nickname}' : '';
        default:
          return '';
      }
    } catch (_) {
      return '';
    }
  }

  /// 白名单派发执行
  Future<void> _dispatch(
    BtActionType type, {
    required String targetId,
    required String value,
    String sessionId = '',
  }) async {
    switch (type) {
      // ─── 通讯录 ───
      case BtActionType.updateContactRemark:
        if (targetId.isNotEmpty) {
          final ch = await _repo.getAICharacter(targetId);
          if (ch != null) {
            await _repo.saveAICharacter(ch.copyWith(name: value));
          }
        }
      case BtActionType.updateContactAvatar:
        if (targetId.isNotEmpty) {
          final ch = await _repo.getAICharacter(targetId);
          if (ch != null) {
            await _repo.saveAICharacter(ch.copyWith(avatarUrl: value));
          }
        }
      case BtActionType.hideContact:
        await _repo.setCharacterHidden(targetId, true);
      case BtActionType.deleteContact:
        await _repo.deleteAICharacterCascade(targetId);

      // ─── 角色 & 互动 ───
      case BtActionType.setOnlineStatus:
        await _repo.setCharacterOnline(targetId, value == 'true');
      case BtActionType.setSaveStatus:
        // AICharacter 无 isSaved 字段，通过 isOnline 间接实现保存状态
        debugPrint('[BT] setSaveStatus: AICharacter 无此字段，跳过');
      case BtActionType.setMessageDisturb:
        // 通过 session isMuted 实现
        if (sessionId.isNotEmpty) {
          final session = await _repo.getChatSession(sessionId);
          if (session != null) {
            await _repo
                .saveChatSession(session.copyWith(isMuted: value == 'true'));
          }
        }
      case BtActionType.setVideoChat:
        // 当前模型不支持视频聊天设置，记录但不执行
        debugPrint('[BT] setVideoChat: 当前不支持，跳过');
      case BtActionType.toggleBlock:
        // targetId 为 sessionId
        final session = await _repo.getChatSession(targetId);
        if (session != null) {
          await _repo
              .saveChatSession(session.copyWith(isBlocked: !session.isBlocked));
        }
      case BtActionType.clearChatHistory:
        await _repo.clearChatMessages(targetId);
      case BtActionType.deleteMessage:
        if (targetId.isNotEmpty) {
          await _repo.deleteChatMessage(targetId);
        }
      case BtActionType.deleteCharacter:
        await _repo.deleteAICharacterCascade(targetId);
      case BtActionType.clearCharacterMemory:
        final userId = _repo.getString(PrefKeys.currentUserId) ?? 'default';
        await _repo.clearMemories(targetId, userId);
      case BtActionType.resetCharacterPersona:
        final ch = await _repo.getAICharacter(targetId);
        if (ch != null) {
          await _repo.saveAICharacter(ch.copyWith(
            personality: '',
            coreDesire: '',
            moralBoundary: '',
            clearBackgroundStory: true,
            clearWorldSetting: true,
            clearLanguageStyle: true,
          ));
          final userId = _repo.getString(PrefKeys.currentUserId) ?? 'default';
          await _repo.clearMemories(targetId, userId);
        }
      case BtActionType.deleteChatSession:
        await _repo.deleteChatSessionCascade(targetId);
      case BtActionType.clearGroupContent:
        // 群聊消息也在 chat_messages 表中，chatId = groupSessionId
        await _repo.clearChatMessages(targetId);
      case BtActionType.insertSystemMessage:
        if (sessionId.isNotEmpty && value.isNotEmpty) {
          await _repo.insertSystemChatMessage(sessionId, value);
        }
      case BtActionType.reportCharacter:
        // 当前模型无 isReported 字段，记录审计即可
        debugPrint('[BT] reportCharacter: 已记录审计');

      // ─── 发现页 ───
      case BtActionType.postMoment:
        await _repo.btPostMoment(targetId, value);
      case BtActionType.deleteMoment:
        await _repo.deleteMoment(targetId);
      case BtActionType.hideMoment:
        await _repo.btHideMoment(targetId);
      case BtActionType.commentMoment:
        final parts = value.split('|');
        if (parts.length >= 2) {
          await _repo.btCommentMoment(parts[0], targetId, parts[1]);
        }
      case BtActionType.clearMomentsData:
        await _repo.btClearCharacterMoments(targetId);
      case BtActionType.sendLetter:
        final parts = value.split('|');
        if (parts.length >= 2) {
          await _repo.btSendLetter(
            fromId: targetId,
            toId: parts[0],
            content: parts[1],
          );
        }
      case BtActionType.deleteLetter:
        await _repo.deleteAILetter(targetId);
      case BtActionType.markLetter:
        await _repo.markAILetterRead(targetId);
      case BtActionType.clearLettersData:
        await _repo.btClearCharacterLetters(targetId);
      case BtActionType.createDiary:
        await _repo.btCreateDiary(targetId, value);
      case BtActionType.modifyDiary:
        final parts = value.split('|');
        if (parts.length >= 2) {
          await _repo.btModifyDiary(parts[0], parts[1]);
        }
      case BtActionType.deleteDiary:
        await _repo.btDeleteDiary(targetId);
      case BtActionType.clearDiaryData:
        await _repo.btClearDiary(targetId);
      case BtActionType.triggerLuckyWheel:
        debugPrint('[BT] triggerLuckyWheel: 需 UI 交互，仅记录审计');
      case BtActionType.clearLuckyWheelData:
        debugPrint('[BT] clearLuckyWheelData: 已记录审计');
      case BtActionType.queryGlobalMemory:
        // 查询操作不修改数据，仅记录审计
        break;
      case BtActionType.organizeGlobalMemory:
        debugPrint('[BT] organizeGlobalMemory: 已记录审计');
      case BtActionType.deleteGlobalMemoryItem:
        await _repo.deleteMemory(targetId);

      // ─── 设备操控 — UI 操作（AccessibilityService） ───
      case BtActionType.phoneTap:
        {
          final pts = value.split(',');
          if (pts.length >= 2) {
            final x = double.tryParse(pts[0]) ?? 0;
            final y = double.tryParse(pts[1]) ?? 0;
            await DeviceAutomationService.instance.tap(x, y);
          }
        }
      case BtActionType.phoneSwipe:
        {
          final pts = value.split(',');
          if (pts.length >= 4) {
            final x1 = double.tryParse(pts[0]) ?? 0;
            final y1 = double.tryParse(pts[1]) ?? 0;
            final x2 = double.tryParse(pts[2]) ?? 0;
            final y2 = double.tryParse(pts[3]) ?? 0;
            final duration = pts.length >= 5 ? int.tryParse(pts[4]) ?? 300 : 300;
            await DeviceAutomationService.instance.swipe(
              x1: x1, y1: y1, x2: x2, y2: y2, durationMs: duration,
            );
          }
        }
      case BtActionType.phoneLongPress:
        {
          final pts = value.split(',');
          if (pts.length >= 2) {
            final x = double.tryParse(pts[0]) ?? 0;
            final y = double.tryParse(pts[1]) ?? 0;
            final duration = pts.length >= 3 ? int.tryParse(pts[2]) ?? 800 : 800;
            await DeviceAutomationService.instance.longPress(x, y, durationMs: duration);
          }
        }
      case BtActionType.phoneBack:
        await DeviceAutomationService.instance.goBack();
        break;
      case BtActionType.phoneHome:
        await DeviceAutomationService.instance.goHome();
        break;
      case BtActionType.phoneRecentApps:
        await DeviceAutomationService.instance.openRecentApps();
        break;
      case BtActionType.phoneScroll:
        {
          // value: "direction,x,y" e.g. "DOWN,500,500"
          final pts = value.split(',');
          if (pts.isNotEmpty) {
            final direction = pts[0].toUpperCase();
            final sx = pts.length >= 2 ? double.tryParse(pts[1]) ?? 500.0 : 500.0;
            final sy = pts.length >= 3 ? double.tryParse(pts[2]) ?? 500.0 : 500.0;
            if (direction == 'DOWN') {
              await DeviceAutomationService.instance.swipe(
                x1: sx, y1: sy - 200, x2: sx, y2: sy + 200, durationMs: 300,
              );
            } else {
              await DeviceAutomationService.instance.swipe(
                x1: sx, y1: sy + 200, x2: sx, y2: sy - 200, durationMs: 300,
              );
            }
          }
        }
      case BtActionType.phoneTypeText:
        if (value.isNotEmpty) {
          await DeviceAutomationService.instance.typeText(value);
        }
        break;
      case BtActionType.phoneClickText:
        if (value.isNotEmpty) {
          await DeviceAutomationService.instance.clickText(value);
        }
        break;
      case BtActionType.phoneOpenApp:
        if (value.isNotEmpty) {
          await DeviceAutomationService.instance.openApp(value);
        }
        break;
      case BtActionType.phoneScreenRead:
        // 只读操作，结果存储到审计日志的 stateAfter
        {
          final content = await DeviceAutomationService.instance.getScreenContent();
          debugPrint('[BT] phoneScreenRead: $content');
        }
      case BtActionType.phoneGetNotifications:
        {
          final notifications = await DeviceAutomationService.instance.getNotifications();
          debugPrint('[BT] phoneGetNotifications: ${notifications.length}条');
        }
      case BtActionType.phoneTakeScreenshot:
        debugPrint('[BT] phoneTakeScreenshot: 已记录请求');
        break;
      case BtActionType.phoneOpenNotificationsPanel:
        await DeviceAutomationService.instance.openNotifications();
        break;
      case BtActionType.phoneQuickSettings:
        await DeviceAutomationService.instance.openQuickSettings();
        break;

      // ─── 设备操控 — 系统操作（Shizuku） ───
      case BtActionType.phoneSetWifi:
        await DeviceAutomationService.instance.setWifiEnabled(value == 'true' || value == '1');
        break;
      case BtActionType.phoneSetBluetooth:
        await DeviceAutomationService.instance.setBluetoothEnabled(value == 'true' || value == '1');
        break;
      case BtActionType.phoneSetVolume:
        {
          final level = int.tryParse(value) ?? 50;
          await DeviceAutomationService.instance.setVolume(level);
        }
      case BtActionType.phoneSetBrightness:
        {
          final level = int.tryParse(value) ?? 128;
          await DeviceAutomationService.instance.setBrightness(level);
        }
      case BtActionType.phoneExecShell:
        if (value.isNotEmpty) {
          final result = await DeviceAutomationService.instance.executeShell(value);
          debugPrint('[BT] phoneExecShell: success=${result.success}');
        }
        break;
      case BtActionType.phoneInstallApp:
        if (value.isNotEmpty) {
          await DeviceAutomationService.instance.installApp(value);
        }
        break;
      case BtActionType.phoneUninstallApp:
        if (value.isNotEmpty) {
          await DeviceAutomationService.instance.uninstallApp(value);
        }
        break;
      case BtActionType.phoneGrantPermission:
        {
          final pts = value.split('|');
          if (pts.length >= 2) {
            await DeviceAutomationService.instance.grantPermission(pts[0], pts[1]);
          }
        }

      // ─── 个人资料 ───
      case BtActionType.updateProfileAvatar:
        final userId = _repo.getString(PrefKeys.currentUserId) ?? 'default';
        await _repo.updateUserAvatar(userId, value);
      case BtActionType.updateProfileNickname:
        final userId = _repo.getString(PrefKeys.currentUserId) ?? 'default';
        await _repo.updateUserNickname(userId, value);

      // ─── 外观主题 ───
      case BtActionType.setLightTheme:
        await _repo.setString(PrefKeys.themeMode, '1');
      case BtActionType.setDarkTheme:
        await _repo.setString(PrefKeys.themeMode, '2');
      case BtActionType.setSystemTheme:
        await _repo.setString(PrefKeys.themeMode, '0');
    }
  }

  // ─── 审计日志构建 ───

  BtAgentAction _buildLog({
    required BtActionType actionType,
    required BtPermissionCategory category,
    required BtActionScope scope,
    required BtTargetType targetType,
    required String targetId,
    required String reason,
    required BtActionResult result,
    BtRejectionReason? rejectionReason,
    String stateBefore = '',
    String stateAfter = '',
    String characterId = '',
    String sessionId = '',
    String chatType = 'single',
  }) {
    return BtAgentAction(
      actionType: actionType,
      category: category,
      scope: scope,
      targetType: targetType,
      targetId: targetId,
      reason: reason,
      stateBefore: stateBefore,
      stateAfter: stateAfter,
      result: result,
      rejectionReason: rejectionReason,
      characterId: characterId,
      sessionId: sessionId,
      chatType: chatType,
    );
  }

  BtAgentAction _buildActionLog({
    required BtActionType actionType,
    required String targetId,
    required String reason,
    required BtActionResult result,
    BtRejectionReason? rejectionReason,
    String stateBefore = '',
    String stateAfter = '',
    String characterId = '',
    String sessionId = '',
    String chatType = 'single',
  }) {
    final category =
        btActionCategoryMap[actionType] ?? BtPermissionCategory.interaction;
    final scope = _inferScope(category);
    final targetType = _inferTargetType(actionType);

    return BtAgentAction(
      actionType: actionType,
      category: category,
      scope: scope,
      targetType: targetType,
      targetId: targetId,
      reason: reason,
      stateBefore: stateBefore,
      stateAfter: stateAfter,
      result: result,
      rejectionReason: rejectionReason,
      characterId: characterId,
      sessionId: sessionId,
      chatType: chatType,
    );
  }

  BtActionScope _inferScope(BtPermissionCategory cat) {
    switch (cat) {
      case BtPermissionCategory.contact:
        return BtActionScope.contactScope;
      case BtPermissionCategory.interaction:
        return BtActionScope.characterScope;
      case BtPermissionCategory.discover:
        return BtActionScope.discoverScope;
      case BtPermissionCategory.profile:
        return BtActionScope.profileScope;
      case BtPermissionCategory.appearance:
        return BtActionScope.appearanceScope;
      case BtPermissionCategory.device:
        return BtActionScope.deviceScope;
    }
  }

  BtTargetType _inferTargetType(BtActionType type) {
    switch (type) {
      case BtActionType.deleteMessage:
        return BtTargetType.message;
      case BtActionType.clearChatHistory:
      case BtActionType.deleteChatSession:
      case BtActionType.clearGroupContent:
      case BtActionType.insertSystemMessage:
        return BtTargetType.chatSession;
      case BtActionType.deleteCharacter:
      case BtActionType.clearCharacterMemory:
      case BtActionType.resetCharacterPersona:
      case BtActionType.toggleBlock:
      case BtActionType.setOnlineStatus:
      case BtActionType.setSaveStatus:
      case BtActionType.setMessageDisturb:
      case BtActionType.setVideoChat:
      case BtActionType.reportCharacter:
        return BtTargetType.character;
      case BtActionType.updateContactRemark:
      case BtActionType.updateContactAvatar:
      case BtActionType.hideContact:
      case BtActionType.deleteContact:
        return BtTargetType.contact;
      case BtActionType.postMoment:
      case BtActionType.deleteMoment:
      case BtActionType.hideMoment:
      case BtActionType.commentMoment:
      case BtActionType.clearMomentsData:
        return BtTargetType.moment;
      case BtActionType.sendLetter:
      case BtActionType.deleteLetter:
      case BtActionType.markLetter:
      case BtActionType.clearLettersData:
        return BtTargetType.letter;
      case BtActionType.createDiary:
      case BtActionType.modifyDiary:
      case BtActionType.deleteDiary:
      case BtActionType.clearDiaryData:
        return BtTargetType.diary;
      case BtActionType.triggerLuckyWheel:
      case BtActionType.clearLuckyWheelData:
        return BtTargetType.luckyWheel;
      case BtActionType.queryGlobalMemory:
      case BtActionType.organizeGlobalMemory:
      case BtActionType.deleteGlobalMemoryItem:
        return BtTargetType.globalMemory;
      case BtActionType.updateProfileAvatar:
      case BtActionType.updateProfileNickname:
        return BtTargetType.user;
      case BtActionType.setLightTheme:
      case BtActionType.setDarkTheme:
      case BtActionType.setSystemTheme:
        return BtTargetType.theme;

      // 设备操控 — UI
      case BtActionType.phoneTap:
      case BtActionType.phoneSwipe:
      case BtActionType.phoneLongPress:
      case BtActionType.phoneScroll:
        return BtTargetType.device;
      case BtActionType.phoneBack:
      case BtActionType.phoneHome:
      case BtActionType.phoneRecentApps:
        return BtTargetType.device;
      case BtActionType.phoneTypeText:
      case BtActionType.phoneClickText:
        return BtTargetType.device;
      case BtActionType.phoneOpenApp:
        return BtTargetType.phoneApp;
      case BtActionType.phoneScreenRead:
        return BtTargetType.phoneScreen;
      case BtActionType.phoneGetNotifications:
        return BtTargetType.phoneNotification;
      case BtActionType.phoneTakeScreenshot:
        return BtTargetType.phoneScreen;
      case BtActionType.phoneOpenNotificationsPanel:
        return BtTargetType.phoneNotification;
      case BtActionType.phoneQuickSettings:
        return BtTargetType.phoneNotification;

      // 设备操控 — 系统
      case BtActionType.phoneSetWifi:
      case BtActionType.phoneSetBluetooth:
      case BtActionType.phoneSetVolume:
      case BtActionType.phoneSetBrightness:
        return BtTargetType.phoneSystemSetting;
      case BtActionType.phoneExecShell:
      case BtActionType.phoneInstallApp:
      case BtActionType.phoneUninstallApp:
      case BtActionType.phoneGrantPermission:
        return BtTargetType.device;
    }
  }
}
