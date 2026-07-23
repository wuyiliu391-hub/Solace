import 'package:flutter/foundation.dart';
import '../tool.dart';
import '../../device_notification_service.dart';

/// 通知工具包
///
/// 读取系统通知（需要通知监听权限）
class NotificationToolPkg extends ToolPkg {
  final DeviceNotificationService _notificationService = DeviceNotificationService();

  @override
  String get name => '通知';

  @override
  String get description => '读取系统通知列表';

  @override
  List<Tool> get tools => [
        _GetNotificationsTool(_notificationService),
        _GetNotificationCountTool(_notificationService),
      ];
}

class _GetNotificationsTool extends Tool {
  final DeviceNotificationService _notificationService;

  _GetNotificationsTool(this._notificationService);

  @override
  String get name => 'get_notifications';

  @override
  String get description => '获取手机上最近的通知列表';

  @override
  Map<String, dynamic> get parametersSchema => {
        'type': 'object',
        'properties': {
          'limit': {
            'type': 'integer',
            'description': '最多返回多少条，默认 10',
          },
        },
      };

  @override
  Set<String> get requiredPermissions => {'notification'};

  @override
  bool get isDestructive => false;

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    final limit = (args['limit'] as num?)?.toInt() ?? 10;
    final hasAccess = await _notificationService.hasAccess();
    if (!hasAccess) {
      return ToolResult.error(
        '需要通知监听权限，请在系统设置中授予 Solace 通知使用权',
        needsPermission: true,
        permissionName: '通知使用权',
      );
    }
    final notifications = await _notificationService.getNotifications(limit: limit);
    if (notifications.isEmpty) {
      return ToolResult.success('最近没有通知');
    }
    final buf = StringBuffer('最近 ${notifications.length} 条通知:\n');
    for (var i = 0; i < notifications.length; i++) {
      buf.writeln('${i + 1}. ${notifications[i].toDisplayString()}');
    }
    return ToolResult.success(buf.toString().trim());
  }
}

class _GetNotificationCountTool extends Tool {
  final DeviceNotificationService _notificationService;

  _GetNotificationCountTool(this._notificationService);

  @override
  String get name => 'get_notification_count';

  @override
  String get description => '获取当前未读通知数量';

  @override
  Map<String, dynamic> get parametersSchema => {
        'type': 'object',
        'properties': {},
      };

  @override
  Set<String> get requiredPermissions => {'notification'};

  @override
  bool get isDestructive => false;

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    final count = await _notificationService.getCount();
    return ToolResult.success('当前有 $count 条通知');
  }
}
