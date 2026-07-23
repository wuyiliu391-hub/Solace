import 'package:flutter/foundation.dart';
import '../tool.dart';
import '../../device_service.dart';

/// UI 自动化工具包
///
/// 点击、滑动、输入文本、按键等 UI 交互操作
class UIAutomationToolPkg extends ToolPkg {
  final DeviceService _device = DeviceService();

  @override
  String get name => 'UI 自动化';

  @override
  String get description => '屏幕点击、滑动、文本输入、按键等 UI 交互';

  @override
  List<Tool> get tools => [
        _TapTool(_device),
        _SwipeTool(_device),
        _InputTextTool(_device),
        _PressKeyTool(_device),
      ];
}

// ═══════════════════════════════════════════════
// 点击
// ═══════════════════════════════════════════════

class _TapTool extends Tool {
  final DeviceService _device;

  _TapTool(this._device);

  @override
  String get name => 'tap';

  @override
  String get description => '点击屏幕指定坐标';

  @override
  Map<String, dynamic> get parametersSchema => {
        'type': 'object',
        'properties': {
          'x': {
            'type': 'integer',
            'description': 'X 坐标',
          },
          'y': {
            'type': 'integer',
            'description': 'Y 坐标',
          },
        },
        'required': ['x', 'y'],
      };

  @override
  Set<String> get requiredPermissions => {'shizuku'};

  @override
  bool get isDestructive => false;

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    final x = (args['x'] as num?)?.toInt() ?? 0;
    final y = (args['y'] as num?)?.toInt() ?? 0;
    if (x < 0 || y < 0) return ToolResult.error('坐标不能为负数');
    final ok = await _device.tap(x, y);
    if (ok) return ToolResult.success('点击 ($x, $y)');
    return ToolResult.error('点击失败');
  }
}

// ═══════════════════════════════════════════════
// 滑动
// ═══════════════════════════════════════════════

class _SwipeTool extends Tool {
  final DeviceService _device;

  _SwipeTool(this._device);

  @override
  String get name => 'swipe';

  @override
  String get description => '在屏幕上滑动';

  @override
  Map<String, dynamic> get parametersSchema => {
        'type': 'object',
        'properties': {
          'start_x': {
            'type': 'integer',
            'description': '起始 X 坐标',
          },
          'start_y': {
            'type': 'integer',
            'description': '起始 Y 坐标',
          },
          'end_x': {
            'type': 'integer',
            'description': '结束 X 坐标',
          },
          'end_y': {
            'type': 'integer',
            'description': '结束 Y 坐标',
          },
          'duration': {
            'type': 'integer',
            'description': '滑动持续时间（毫秒），默认 300',
          },
        },
        'required': ['start_x', 'start_y', 'end_x', 'end_y'],
      };

  @override
  Set<String> get requiredPermissions => {'shizuku'};

  @override
  bool get isDestructive => false;

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    final sx = (args['start_x'] as num?)?.toInt() ?? 0;
    final sy = (args['start_y'] as num?)?.toInt() ?? 0;
    final ex = (args['end_x'] as num?)?.toInt() ?? 0;
    final ey = (args['end_y'] as num?)?.toInt() ?? 0;
    final duration = (args['duration'] as num?)?.toInt() ?? 300;
    final ok = await _device.swipe(sx, sy, ex, ey, duration: duration);
    if (ok) return ToolResult.success('滑动完成 ($sx,$sy)→($ex,$ey)');
    return ToolResult.error('滑动失败');
  }
}

// ═══════════════════════════════════════════════
// 输入文本
// ═══════════════════════════════════════════════

class _InputTextTool extends Tool {
  final DeviceService _device;

  _InputTextTool(this._device);

  @override
  String get name => 'input_text';

  @override
  String get description => '在输入框中输入文本（通过 input text 命令）';

  @override
  Map<String, dynamic> get parametersSchema => {
        'type': 'object',
        'properties': {
          'text': {
            'type': 'string',
            'description': '要输入的文本内容',
          },
        },
        'required': ['text'],
      };

  @override
  Set<String> get requiredPermissions => {'shizuku'};

  @override
  bool get isDestructive => false;

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    final text = args['text'] as String? ?? '';
    if (text.isEmpty) return ToolResult.error('文本为空');
    if (text.length > 500) return ToolResult.error('文本过长（最大 500 字符）');
    final ok = await _device.inputText(text);
    if (ok) return ToolResult.success('已输入: "$text"');
    return ToolResult.error('输入失败');
  }
}

// ═══════════════════════════════════════════════
// 按键
// ═══════════════════════════════════════════════

class _PressKeyTool extends Tool {
  final DeviceService _device;

  _PressKeyTool(this._device);

  @override
  String get name => 'press_key';

  @override
  String get description => '模拟按键。常用：3=Home, 4=Back, 24=音量+, 25=音量-, 26=电源, 187=最近任务';

  @override
  Map<String, dynamic> get parametersSchema => {
        'type': 'object',
        'properties': {
          'key_code': {
            'type': 'integer',
            'description': 'Android KeyEvent 码，如 3=Home, 4=Back, 26=电源键',
          },
        },
        'required': ['key_code'],
      };

  @override
  Set<String> get requiredPermissions => {'shizuku'};

  @override
  bool get isDestructive => false;

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    final keyCode = (args['key_code'] as num?)?.toInt() ?? 0;
    if (keyCode <= 0) return ToolResult.error('无效的键码');
    final ok = await _device.pressKey(keyCode);
    if (ok) return ToolResult.success('按键 $keyCode 已发送');
    return ToolResult.error('按键失败');
  }
}
