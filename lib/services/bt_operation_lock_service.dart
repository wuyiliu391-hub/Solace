import 'package:flutter/foundation.dart';
import '../models/bt_agent_action.dart';

/// BT 局部操作锁服务
///
/// 仅做内存临时标记，不持久化。
/// 不锁定全屏、不影响底部导航和 BT 设置页，只由具体控件按 lockKey 局部订阅。
class BtOperationLockService {
  BtOperationLockService._();

  static final BtOperationLockService instance = BtOperationLockService._();

  final ValueNotifier<int> revision = ValueNotifier<int>(0);
  final Map<String, BtOperationLockRecord> _locks = {};
  bool _interrupted = false;

  bool get isInterrupted => _interrupted;

  List<BtOperationLockRecord> get activeLocks =>
      List.unmodifiable(_locks.values);

  bool isLocked(String key) => _locks.containsKey(key);

  BtOperationLockRecord? getLock(String key) => _locks[key];

  String buildLockKey({
    required BtPermissionCategory category,
    required BtActionScope scope,
    required BtTargetType targetType,
    required String targetId,
    required BtActionType actionType,
  }) {
    final objectId = targetId.isEmpty ? 'current' : targetId;
    return '${category.name}:${scope.name}:${targetType.name}:$objectId:${actionType.name}';
  }

  /// UI 页面使用：按动作和目标对象生成与执行服务完全一致的局部锁 key
  String buildUiLockKey({
    required BtActionType actionType,
    required String targetId,
  }) {
    final category =
        btActionCategoryMap[actionType] ?? BtPermissionCategory.interaction;
    final scope = _inferScope(category);
    final targetType = _inferTargetType(actionType);
    return buildLockKey(
      category: category,
      scope: scope,
      targetType: targetType,
      targetId: targetId,
      actionType: actionType,
    );
  }

  BtActionScope _inferScope(BtPermissionCategory category) {
    switch (category) {
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
    }
  }

  BtOperationLockRecord lock({
    required String key,
    required BtActionType actionType,
    required BtPermissionCategory category,
    required BtActionScope scope,
    required BtTargetType targetType,
    required String targetId,
    required String characterId,
    required String sessionId,
    required String chatType,
    String reason = '',
  }) {
    _interrupted = false;
    final now = DateTime.now();
    final record = BtOperationLockRecord(
      key: key,
      actionType: actionType,
      category: category,
      scope: scope,
      targetType: targetType,
      targetId: targetId,
      characterId: characterId,
      sessionId: sessionId,
      chatType: chatType,
      reason: reason,
      lockedAt: now,
    );
    _locks[key] = record;
    revision.value++;
    return record;
  }

  BtOperationLockRecord? unlock(String key) {
    final record = _locks.remove(key);
    if (record != null) {
      revision.value++;
    }
    return record;
  }

  List<BtOperationLockRecord> interruptAll({String reason = '用户主动关停模式，操作中断'}) {
    _interrupted = true;
    final records = List<BtOperationLockRecord>.from(_locks.values);
    _locks.clear();
    revision.value++;
    return records;
  }

  void resetInterruptFlag() {
    _interrupted = false;
  }
}

class BtOperationLockRecord {
  final String key;
  final BtActionType actionType;
  final BtPermissionCategory category;
  final BtActionScope scope;
  final BtTargetType targetType;
  final String targetId;
  final String characterId;
  final String sessionId;
  final String chatType;
  final String reason;
  final DateTime lockedAt;

  const BtOperationLockRecord({
    required this.key,
    required this.actionType,
    required this.category,
    required this.scope,
    required this.targetType,
    required this.targetId,
    required this.characterId,
    required this.sessionId,
    required this.chatType,
    required this.reason,
    required this.lockedAt,
  });
}
