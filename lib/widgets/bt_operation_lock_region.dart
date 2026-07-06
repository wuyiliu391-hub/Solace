import 'package:flutter/material.dart';
import '../services/bt_operation_lock_service.dart';

/// BT 局部操作锁区域
///
/// 页面控件按 lockKey 包裹本组件后，可在 BT 操作中局部置灰并禁止编辑。
/// 不会遮挡全屏，不影响页面切换、底部导航和 BT 设置页。
class BtOperationLockRegion extends StatelessWidget {
  final String lockKey;
  final Widget child;
  final bool showHint;
  final EdgeInsetsGeometry hintPadding;

  const BtOperationLockRegion({
    super.key,
    required this.lockKey,
    required this.child,
    this.showHint = true,
    this.hintPadding = const EdgeInsets.only(top: 4),
  });

  @override
  Widget build(BuildContext context) {
    final service = BtOperationLockService.instance;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return ValueListenableBuilder<int>(
      valueListenable: service.revision,
      builder: (_, __, ___) {
        final locked = service.isLocked(lockKey);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            AbsorbPointer(
              absorbing: locked,
              child: Opacity(
                opacity: locked ? 0.45 : 1,
                child: DecoratedBox(
                  decoration: locked
                      ? BoxDecoration(
                          color: Colors.grey.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.grey.withOpacity(0.28),
                          ),
                        )
                      : const BoxDecoration(),
                  child: child,
                ),
              ),
            ),
            if (locked && showHint)
              Padding(
                padding: hintPadding,
                child: Text(
                  'BT模式正在操作中，暂不可编辑',
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
          ],
        );
      },
    );
  }
}
