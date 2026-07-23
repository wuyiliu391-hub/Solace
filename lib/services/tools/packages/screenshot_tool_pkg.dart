import 'package:flutter/foundation.dart';
import '../tool.dart';
import '../../device_service.dart';

/// 截图工具包
class ScreenshotToolPkg extends ToolPkg {
  final DeviceService _device = DeviceService();

  @override
  String get name => '截图';

  @override
  String get description => '通过 Shizuku 直接截图，不弹权限框';

  @override
  List<Tool> get tools => [
        _TakeScreenshotTool(_device),
      ];
}

class _TakeScreenshotTool extends Tool {
  final DeviceService _device;

  _TakeScreenshotTool(this._device);

  @override
  String get name => 'take_screenshot';

  @override
  String get description => '截图并保存到相册（通过 Shizuku screencap）。注：当前版本只返回截图路径，不做视觉分析。';

  @override
  Map<String, dynamic> get parametersSchema => {
        'type': 'object',
        'properties': {},
      };

  @override
  Set<String> get requiredPermissions => {'shizuku'};

  @override
  bool get isDestructive => false;

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    final path = await _device.shellScreenshot();
    if (path == null || path.isEmpty) {
      return ToolResult.error('截图失败，请确认 Shizuku 已授权');
    }
    return ToolResult.success('截图已保存到: $path', data: {'path': path});
  }
}
