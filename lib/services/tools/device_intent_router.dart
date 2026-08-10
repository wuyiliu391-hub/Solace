/// 用户自然语言中的设备操作意图。
enum DeviceIntentKind { none, deterministic, agent }

/// 独立于 ChatBloc 的设备意图判定结果。
///
/// [deterministic] 表示可以交给本地确定性路由直接执行；[agent] 表示
/// 请求明确是设备操作，但参数或步骤需要模型选择工具。
class DeviceIntentMatch {
  final DeviceIntentKind kind;
  final String reason;

  const DeviceIntentMatch(this.kind, this.reason);

  bool get isDeviceRequest => kind != DeviceIntentKind.none;
  bool get usesDeterministicRoute => kind == DeviceIntentKind.deterministic;
}

/// Operit 的自然语言入口闸门。
///
/// 设备词本身不足以触发操作：必须同时具有明确的命令、查询或快捷指令结构。
/// 这层在确定性路由之前运行，避免剧情、转述和比喻文本被当作真实设备操作。
class DeviceIntentRouter {
  DeviceIntentRouter._();

  static const int _maxMessageLength = 150;

  static final RegExp _narrativePrefix = RegExp(
    r'^(?:他|她|它|角色|故事里|剧情里|小说里|梦里|想象中|如果|假如|要是|别|不要|别再|别去)',
    caseSensitive: false,
  );
  static final RegExp _quotedCommand = RegExp('''[“"‘'].*[”"’']''');
  static final RegExp _politePrefix = RegExp(
    r'^(?:能不能帮我|可以帮我|能不能|请你|麻烦你|你帮|让你|帮我|请|麻烦|可以|能)\s*',
    caseSensitive: false,
  );

  static final List<RegExp> _deterministicPatterns = [
    RegExp(
        r'^(?:(?:打开|启动|进入|运行|开一下|关闭|退出|结束|杀掉|关掉).*(?:微信|wechat|qq|淘宝|京东|微博|小红书|知乎|抖音|哔哩哔哩|bilibili|b站|快手|支付宝|网易云音乐|qq音乐|设置|相机|相册|图库|日历|时钟|计算器|拼多多)|锁屏|锁定手机|回到桌面|回桌面|返回上一级|返回上一页|截图|截屏|截个图|上滑|下滑|左滑|右滑|音量[+-])'),
    RegExp(r'^(?:电量|电池|通知|通知列表|通知数量|最近通知|当前应用|前台应用|应用列表|进程|进程列表|运行中的进程)$'),
    RegExp(r'^(?:查看|看看|看下|查询|告诉我).*(?:电量|电池|多少电|通知|通知数量|未读通知|当前应用|前台应用|已安装应用|应用列表|进程|运行中的进程)$'),
    RegExp(r'(?:(?:电量|电池).*(?:多少|还剩|剩余|充)|(?:还有|还剩|剩余).*(?:电量|电池|电))'),
    RegExp(r'^(?:(?:查看|看看|查询|获取|列出).*(?:进程|运行中的进程)|(?:进程|运行中的进程).*(?:有哪些|列表|情况))$'),
    RegExp(r'^(?:(?:查看|看看|查询|获取).*(?:通知数量|未读通知数|有几个通知)|(?:通知数量|未读通知数|有几个通知))$'),
    RegExp(r'^(?:把\s*.+\s*(?:打开|启动|关闭|关掉|调大|调小|调高|调低))'),
    RegExp(r'^(?:(?:开启|关闭|取消|解除|切换).*(?:静音|wifi|wi-fi|无线网|蓝牙))'),
    RegExp(
        r'^(?:(?:调大|调小|调高|调低|提高|降低).*(?:音量|声音|亮度)|(?:音量|声音|亮度).*(?:调大|调小|调高|调低|提高|降低|最亮|最暗|一半|适中|\d+))'),
    RegExp(
        r'^(?:执行|调用|运行|使用)\s*(?:open_|close_|get_|set_|toggle_|take_|go_|press_|input_|execute_|tap|swipe)'),
    RegExp(r'^(?:执行|运行|跑一下|跑个)?\s*(?:shizuku|shell|命令|指令|cmd)\s*[:：]'),
    RegExp(
        r'^(?:(?:在|往|向)(?:当前)?(?:输入框|文本框|搜索框|页面|屏幕).*(?:输入|打字|填入)|(?:执行|调用|使用)\s*input_text\b)'),
  ];

  static final List<RegExp> _agentPatterns = [
    RegExp(r'^(?:设置|设个|定个).*(?:闹钟|提醒|闹铃)'),
    RegExp(r'^(?:发送|分享|转发|把).*(?:短信|消息|邮件).*(?:给|到|至|发送|转发)'),
    RegExp(r'^(?:拨打|打给|打电话给|呼叫).*(?:电话|号码|联系人|手机)'),
    RegExp(r'^(?:安装|卸载|删除).*(?:应用|app|软件|包)'),
    RegExp(r'^(?:帮我|帮忙|替我).*(?:操作|处理|执行).*(?:手机|设备|应用|app|系统)'),
  ];

  static DeviceIntentMatch match(String message) {
    final raw = message.trim();
    if (raw.isEmpty) {
      return const DeviceIntentMatch(DeviceIntentKind.none, 'empty');
    }
    if (raw.length > _maxMessageLength) {
      return const DeviceIntentMatch(DeviceIntentKind.none, 'too_long');
    }

    final normalized = raw.replaceFirst(_politePrefix, '').trim();
    if (_narrativePrefix.hasMatch(normalized) || _quotedCommand.hasMatch(raw)) {
      return const DeviceIntentMatch(
          DeviceIntentKind.none, 'narrative_or_quote');
    }

    for (final pattern in _deterministicPatterns) {
      if (pattern.hasMatch(normalized)) {
        return DeviceIntentMatch(
            DeviceIntentKind.deterministic, pattern.pattern);
      }
    }
    for (final pattern in _agentPatterns) {
      if (pattern.hasMatch(normalized)) {
        return DeviceIntentMatch(DeviceIntentKind.agent, pattern.pattern);
      }
    }
    return const DeviceIntentMatch(DeviceIntentKind.none, 'no_match');
  }

  /// 向真实设备输入文本风险很高，不能从普通聊天中的“输入/写”触发。
  /// 必须明确说明目标是当前设备页面/输入框，或直接调用 input_text 工具。
  static bool isExplicitTextInputRequest(String message) {
    final raw = message.trim();
    if (raw.isEmpty || raw.length > _maxMessageLength) return false;
    final normalized = raw.replaceFirst(_politePrefix, '').trim();
    if (_narrativePrefix.hasMatch(normalized) || _quotedCommand.hasMatch(raw)) {
      return false;
    }
    return RegExp(
      r'^(?:(?:在|往|向)(?:当前)?(?:输入框|文本框|搜索框|页面|屏幕).*(?:输入|打字|填入)|(?:执行|调用|使用)\s*input_text\b)',
      caseSensitive: false,
    ).hasMatch(normalized);
  }
}
