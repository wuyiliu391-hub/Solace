/// 单聊确定性设备指令路由
///
/// 与 Operit 快捷操作一致：明确设备指令直接映射到工具，不依赖 LLM function calling。
class DeterministicDeviceRoute {
  final String toolName;
  final Map<String, dynamic> args;

  const DeterministicDeviceRoute({required this.toolName, required this.args});
}

class DeterministicDeviceRouter {
  DeterministicDeviceRouter._();

  static const _appPattern =
      r'(微信|wechat|qq|淘宝|京东|微博|小红书|知乎|抖音|哔哩哔哩|bilibili|b站|快手|支付宝|网易云音乐|qq音乐|设置|相机|相册|图库|日历|时钟|计算器|拼多多)';

  static DeterministicDeviceRoute? match(String message) {
    final text = message.trim();
    if (text.isEmpty) return null;
    final lower = text.toLowerCase();

    final openMatch = RegExp(
      r'(?:打开|启动|进入|运行|开一下|帮我打开|帮我启动|帮我进入|请打开)\s*' + _appPattern,
      caseSensitive: false,
    ).firstMatch(lower);
    if (openMatch != null) {
      final app = _canonicalApp(openMatch.group(1)!);
      if (app == '相册' || app == '图库') {
        return const DeterministicDeviceRoute(
          toolName: 'open_gallery',
          args: {},
        );
      }
      return DeterministicDeviceRoute(
        toolName: 'open_app',
        args: {'app': app},
      );
    }

    final baOpenMatch = RegExp(
      r'把\s*' + _appPattern + r'\s*(打开|启动|进入)',
      caseSensitive: false,
    ).firstMatch(lower);
    if (baOpenMatch != null) {
      final app = _canonicalApp(baOpenMatch.group(1)!);
      if (app == '相册' || app == '图库') {
        return const DeterministicDeviceRoute(
          toolName: 'open_gallery',
          args: {},
        );
      }
      return DeterministicDeviceRoute(
        toolName: 'open_app',
        args: {'app': app},
      );
    }

    final closeMatch = RegExp(
      r'(?:关闭|退出|结束|杀掉|关掉|帮我关闭|帮我退出)\s*' + _appPattern,
      caseSensitive: false,
    ).firstMatch(lower);
    if (closeMatch != null) {
      return DeterministicDeviceRoute(
        toolName: 'close_app',
        args: {'app': _canonicalApp(closeMatch.group(1)!)},
      );
    }

    if (_containsAny(lower, ['锁屏', '锁定屏幕', '锁定手机', '帮我锁屏'])) {
      return const DeterministicDeviceRoute(
        toolName: 'lock_screen',
        args: {},
      );
    }

    if (_containsAny(lower, ['返回桌面', '回到桌面', '回桌面', '按主页键', '去桌面'])) {
      return const DeterministicDeviceRoute(
        toolName: 'go_home',
        args: {},
      );
    }

    if (_containsAny(lower, ['返回上一级', '返回上一页', '按返回键', '返回键'])) {
      return const DeterministicDeviceRoute(
        toolName: 'press_back',
        args: {},
      );
    }

    if (_containsAny(lower, ['开启静音', '打开静音', '设为静音', '静音模式', '帮我静音']) ||
        RegExp(r'(开启|打开|设置|切换到)\s*静音').hasMatch(lower)) {
      return const DeterministicDeviceRoute(
        toolName: 'set_mute',
        args: {'muted': true},
      );
    }

    if (_containsAny(lower, ['关闭静音', '取消静音', '解除静音', '关掉静音'])) {
      return const DeterministicDeviceRoute(
        toolName: 'set_mute',
        args: {'muted': false},
      );
    }

    if (RegExp(r'(音量).*(大|高|增|加|调大|调高)').hasMatch(lower) ||
        RegExp(r'(调大|调高|增大|提高).*(音量)').hasMatch(lower) ||
        lower.contains('调节音量') ||
        lower == '音量+') {
      return const DeterministicDeviceRoute(
        toolName: 'adjust_volume',
        args: {'direction': 'up'},
      );
    }

    if (RegExp(r'(音量).*(小|低|减|少|调小|调低)').hasMatch(lower) ||
        RegExp(r'(调小|调低|减小|降低).*(音量)').hasMatch(lower) ||
        lower == '音量-') {
      return const DeterministicDeviceRoute(
        toolName: 'adjust_volume',
        args: {'direction': 'down'},
      );
    }

    if (_containsAny(lower, ['打开相册', '打开图库', '进入相册', '进入图库'])) {
      return const DeterministicDeviceRoute(
        toolName: 'open_gallery',
        args: {},
      );
    }

    if (_containsAny(lower, ['截图', '截屏', '截个图', '帮我截图', '帮我截屏'])) {
      return const DeterministicDeviceRoute(
        toolName: 'take_screenshot',
        args: {},
      );
    }

    final shellMatch = RegExp(
      r'(?:执行|运行|跑一下|跑个)?\s*(?:shizuku|shell|命令|指令|cmd)\s*[:：]?\s*(.+)',
      caseSensitive: false,
    ).firstMatch(text);
    if (shellMatch != null) {
      final cmd = shellMatch.group(1)?.trim() ?? '';
      if (cmd.isNotEmpty &&
          !RegExp(r'^(命令|shell|shizuku|指令|cmd)$', caseSensitive: false)
              .hasMatch(cmd)) {
        return DeterministicDeviceRoute(
          toolName: 'execute_shell',
          args: {'command': cmd},
        );
      }
    }

    // ─── 电池 ───
    if (RegExp(r'(电量|电池|多少电|还剩多少|剩余电量|充)').hasMatch(lower)) {
      return const DeterministicDeviceRoute(
        toolName: 'get_battery_info',
        args: {},
      );
    }

    // ─── 通知 ───
    if (RegExp(r'(通知数量|几个通知|有多少通知|通知.*多少)').hasMatch(lower)) {
      return const DeterministicDeviceRoute(
        toolName: 'get_notification_count',
        args: {},
      );
    }
    if (RegExp(r'(查看通知|通知列表|最近通知|有什么通知|通知.*内容)').hasMatch(lower) ||
        lower == '通知') {
      return const DeterministicDeviceRoute(
        toolName: 'get_notifications',
        args: {},
      );
    }

    // ─── 应用信息 ───
    if (RegExp(r'(已安装|安装.*应用|应用列表|装了.*应用|有哪些.*应用|列出.*应用)').hasMatch(lower)) {
      return const DeterministicDeviceRoute(
        toolName: 'get_installed_apps',
        args: {},
      );
    }
    if (RegExp(r'(用了多久|使用时间|花了.*时间|玩了多久|用了.*小时).*(' + _appPattern + r')').hasMatch(lower)) {
      final appMatch = RegExp(_appPattern, caseSensitive: false).firstMatch(lower);
      if (appMatch != null) {
        return DeterministicDeviceRoute(
          toolName: 'get_app_usage_time',
          args: {'app': _canonicalApp(appMatch.group(1)!)},
        );
      }
    }
    if (RegExp(r'(使用排行|用了什么|什么.*用得|用得最多)').hasMatch(lower)) {
      return const DeterministicDeviceRoute(
        toolName: 'get_app_usage_time',
        args: {},
      );
    }
    if (RegExp(r'(当前.*应用|什么.*前台|在.*什么应用|现在.*用什么|前台应用|当前.*程序)').hasMatch(lower)) {
      return const DeterministicDeviceRoute(
        toolName: 'get_current_app',
        args: {},
      );
    }

    // ─── WiFi / 蓝牙 ───
    if (RegExp(r'(wifi|wi-fi|无线|无线网).*(开|打开|启用|启动|关|关闭|禁用)').hasMatch(lower) ||
        RegExp(r'(开|打开|启用|启动|关|关闭|禁用).*(wifi|wi-fi|无线|无线网)').hasMatch(lower)) {
      final enable = !RegExp(r'关|关闭|禁用', caseSensitive: false).hasMatch(lower);
      return DeterministicDeviceRoute(
        toolName: 'toggle_wifi',
        args: {'enable': enable},
      );
    }
    if (RegExp(r'(蓝牙).*(开|打开|启用|启动|关|关闭|禁用)').hasMatch(lower) ||
        RegExp(r'(开|打开|启用|启动|关|关闭|禁用).*(蓝牙)').hasMatch(lower)) {
      final enable = !RegExp(r'关|关闭|禁用', caseSensitive: false).hasMatch(lower);
      return DeterministicDeviceRoute(
        toolName: 'toggle_bluetooth',
        args: {'enable': enable},
      );
    }

    // ─── 亮度 ───
    final brightnessMatch = RegExp(
      r'亮度.*?(\d+)|(\d+).*?亮度|亮度.*(最亮|最暗|一半|适中)',
      caseSensitive: false,
    ).firstMatch(lower);
    if (brightnessMatch != null) {
      final numStr = brightnessMatch.group(1) ?? brightnessMatch.group(2);
      int level;
      if (numStr != null) {
        level = int.tryParse(numStr)?.clamp(0, 255) ?? 128;
      } else if (brightnessMatch.group(0)?.contains('最亮') == true) {
        level = 255;
      } else if (brightnessMatch.group(0)?.contains('最暗') == true) {
        level = 1;
      } else {
        level = 128;
      }
      return DeterministicDeviceRoute(
        toolName: 'set_brightness',
        args: {'level': level},
      );
    }
    if (RegExp(r'(调亮|调暗|亮度.*调|亮度.*大|亮度.*小|亮度.*高|亮度.*低|调.*亮度)').hasMatch(lower)) {
      final bright = RegExp(r'亮|大|高', caseSensitive: false).hasMatch(lower);
      return DeterministicDeviceRoute(
        toolName: 'set_brightness',
        args: {'level': bright ? 200 : 50},
      );
    }

    // ─── UI 自动化：滑动 ───
    if (_containsAny(lower, ['上滑', '向上滑动', '往上滑', '划上去'])) {
      return const DeterministicDeviceRoute(
        toolName: 'swipe',
        args: {
          'start_x': 540, 'start_y': 1500,
          'end_x': 540, 'end_y': 500,
          'duration': 300,
        },
      );
    }
    if (_containsAny(lower, ['下滑', '向下滑动', '往下滑', '划下来'])) {
      return const DeterministicDeviceRoute(
        toolName: 'swipe',
        args: {
          'start_x': 540, 'start_y': 500,
          'end_x': 540, 'end_y': 1500,
          'duration': 300,
        },
      );
    }
    if (_containsAny(lower, ['左滑', '向左滑动', '往左滑'])) {
      return const DeterministicDeviceRoute(
        toolName: 'swipe',
        args: {
          'start_x': 900, 'start_y': 1200,
          'end_x': 100, 'end_y': 1200,
          'duration': 300,
        },
      );
    }
    if (_containsAny(lower, ['右滑', '向右滑动', '往右滑'])) {
      return const DeterministicDeviceRoute(
        toolName: 'swipe',
        args: {
          'start_x': 100, 'start_y': 1200,
          'end_x': 900, 'end_y': 1200,
          'duration': 300,
        },
      );
    }

    // ─── UI 自动化：点击坐标 ───
    final tapCoordMatch = RegExp(
      r'(?:点击|点|按|触摸).*?(\d+)\s*[,，]\s*(\d+)',
      caseSensitive: false,
    ).firstMatch(lower);
    if (tapCoordMatch != null) {
      final x = int.tryParse(tapCoordMatch.group(1)!) ?? 0;
      final y = int.tryParse(tapCoordMatch.group(2)!) ?? 0;
      if (x > 0 && y > 0) {
        return DeterministicDeviceRoute(
          toolName: 'tap',
          args: {'x': x, 'y': y},
        );
      }
    }

    // ─── UI 自动化：输入文字 ───
    final inputTextMatch = RegExp(
      r'(?:输入|打出|打字|写)\s*(?:文字|字|内容)?\s*[:：]?\s*(.+)',
      caseSensitive: false,
    ).firstMatch(text);
    if (inputTextMatch != null) {
      final txt = inputTextMatch.group(1)?.trim() ?? '';
      if (txt.isNotEmpty && txt.length <= 500 &&
          !RegExp(r'^(文字|字|内容|一下)$').hasMatch(txt)) {
        return DeterministicDeviceRoute(
          toolName: 'input_text',
          args: {'text': txt},
        );
      }
    }

    // ─── UI 自动化：按键 ───
    if (_containsAny(lower, ['电源键', '锁屏键', '关机键'])) {
      return const DeterministicDeviceRoute(
        toolName: 'press_key',
        args: {'key_code': 26},
      );
    }
    if (_containsAny(lower, ['最近任务', '多任务', '任务键', '任务切换'])) {
      return const DeterministicDeviceRoute(
        toolName: 'press_key',
        args: {'key_code': 187},
      );
    }

    // ─── 通用：直接引用工具名的指令（如 "执行 open_app 微信"） ───
    final directToolMatch = RegExp(
      r'(?:执行|调用|运行|用|使用)\s*([a-z_]+)\s*(.*)',
      caseSensitive: false,
    ).firstMatch(text);
    if (directToolMatch != null) {
      final tn = directToolMatch.group(1)?.trim() ?? '';
      final rest = directToolMatch.group(2)?.trim() ?? '';
      // 只接受已知工具名
      if (_isKnownTool(tn)) {
        final args = <String, dynamic>{};
        if (rest.isNotEmpty) {
          // 尝试解析简单参数 "app=微信" 或 "微信"
          final kvMatch = RegExp(r'(\w+)\s*[=：:]\s*(.+)', caseSensitive: false)
              .firstMatch(rest);
          if (kvMatch != null) {
            args[kvMatch.group(1)!] = kvMatch.group(2)!.trim();
          } else {
            // 按工具名推断参数
            switch (tn) {
              case 'open_app':
              case 'close_app':
                args['app'] = rest;
                break;
              case 'adjust_volume':
                args['direction'] =
                    RegExp(r'大|高|增|加|up', caseSensitive: false).hasMatch(rest)
                        ? 'up'
                        : 'down';
                break;
              case 'set_mute':
                args['muted'] =
                    !RegExp(r'关|取消|解除', caseSensitive: false).hasMatch(rest);
                break;
              case 'toggle_wifi':
              case 'toggle_bluetooth':
                args['enable'] =
                    !RegExp(r'关|禁用', caseSensitive: false).hasMatch(rest);
                break;
              case 'execute_shell':
                args['command'] = rest;
                break;
              case 'input_text':
                args['text'] = rest;
                break;
              case 'set_brightness':
                args['level'] =
                    int.tryParse(rest)?.clamp(0, 255) ?? 128;
                break;
              case 'tap':
                final xy = RegExp(r'(\d+)\s*[,，\s]\s*(\d+)')
                    .firstMatch(rest);
                if (xy != null) {
                  args['x'] = int.tryParse(xy.group(1)!);
                  args['y'] = int.tryParse(xy.group(2)!);
                }
                break;
              case 'get_app_usage_time':
                args['app'] = rest;
                break;
              case 'get_notifications':
                args['limit'] = int.tryParse(rest) ?? 10;
                break;
            }
          }
        }
        return DeterministicDeviceRoute(toolName: tn, args: args);
      }
    }

    return null;
  }

  /// 所有已知工具名集合
  static const _knownTools = {
    'open_app', 'close_app', 'lock_screen', 'go_home', 'press_back',
    'adjust_volume', 'set_mute', 'toggle_wifi', 'toggle_bluetooth',
    'set_brightness', 'open_gallery', 'take_screenshot', 'execute_shell',
    'get_battery_info', 'get_notifications', 'get_notification_count',
    'get_installed_apps', 'get_app_usage_time', 'get_current_app',
    'tap', 'swipe', 'input_text', 'press_key',
  };

  static bool _isKnownTool(String name) => _knownTools.contains(name);

  static bool _containsAny(String text, List<String> candidates) {
    return candidates.any(text.contains);
  }

  static String _canonicalApp(String value) {
    final lower = value.toLowerCase();
    switch (lower) {
      case 'wechat':
        return '微信';
      case 'qq':
        return 'QQ';
      case 'bilibili':
      case 'b站':
        return '哔哩哔哩';
      case '图库':
        return '相册';
      default:
        return value;
    }
  }
}
