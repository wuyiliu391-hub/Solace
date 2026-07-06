import 'package:flutter/material.dart';
import '../models/bt_agent_action.dart';
import '../services/bt_operation_lock_service.dart';
import 'bt_operation_lock_region.dart';

/// BT 六大模块局部锁 UI 适配入口。
///
/// 这些组件只包裹“具体可编辑控件”，不会锁全屏、不会影响底部导航、不会影响 BT 设置页。
class BtModuleLockAdapters {
  BtModuleLockAdapters._();

  static Widget singleChat({
    required BtActionType actionType,
    required String targetId,
    required Widget child,
    bool showHint = true,
  }) =>
      _wrap(actionType, targetId, child, showHint);

  static Widget groupChat({
    required BtActionType actionType,
    required String targetId,
    required Widget child,
    bool showHint = true,
  }) =>
      _wrap(actionType, targetId, child, showHint);

  static Widget contact({
    required BtActionType actionType,
    required String targetId,
    required Widget child,
    bool showHint = true,
  }) =>
      _wrap(actionType, targetId, child, showHint);

  static Widget discover({
    required BtActionType actionType,
    required String targetId,
    required Widget child,
    bool showHint = true,
  }) =>
      _wrap(actionType, targetId, child, showHint);

  static Widget profile({
    required BtActionType actionType,
    required String targetId,
    required Widget child,
    bool showHint = true,
  }) =>
      _wrap(actionType, targetId, child, showHint);

  static Widget themeSetting({
    required BtActionType actionType,
    required Widget child,
    bool showHint = true,
  }) =>
      _wrap(actionType, 'current', child, showHint);

  static Widget _wrap(
    BtActionType actionType,
    String targetId,
    Widget child,
    bool showHint,
  ) {
    final lockKey = BtOperationLockService.instance.buildUiLockKey(
      actionType: actionType,
      targetId: targetId,
    );
    return BtOperationLockRegion(
      lockKey: lockKey,
      showHint: showHint,
      child: child,
    );
  }
}
