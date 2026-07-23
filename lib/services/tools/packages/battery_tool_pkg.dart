import 'package:flutter/foundation.dart';
import '../tool.dart';
import '../../battery_service.dart';

/// 电池信息工具包
class BatteryToolPkg extends ToolPkg {
  @override
  String get name => '电池';

  @override
  String get description => '查询设备电池状态';

  @override
  List<Tool> get tools => [
        _GetBatteryInfoTool(),
      ];
}

class _GetBatteryInfoTool extends Tool {
  @override
  String get name => 'get_battery_info';

  @override
  String get description => '获取设备电池信息：电量百分比、是否充电、充电方式';

  @override
  Map<String, dynamic> get parametersSchema => {
        'type': 'object',
        'properties': {},
      };

  @override
  Set<String> get requiredPermissions => {};

  @override
  bool get isDestructive => false;

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    final info = await BatteryService.refresh();
    final chargingStatus = info.isFull
        ? '已充满'
        : info.isCharging
            ? '充电中'
            : '未充电';
    final source = switch (info.chargeSource) {
      'ac' => '交流电',
      'usb' => 'USB',
      'wireless' => '无线充电',
      _ => '电池',
    };
    return ToolResult.success(
      '电量 ${info.percentage}%，$chargingStatus（$source）',
      data: {
        'percentage': info.percentage,
        'isCharging': info.isCharging,
        'isFull': info.isFull,
        'chargeSource': info.chargeSource,
      },
    );
  }
}
