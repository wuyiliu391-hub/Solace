import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 微信机器人前台保活服务（Android）。
///
/// 通过 MethodChannel 启动/停止 Android 原生前台服务，
/// 阻止系统在 App 切后台时杀网络连接，保证 bot 长轮询不断。
class WechatForegroundService {
  static const _channel = MethodChannel('com.solace.solace/wechat_bot_foreground');

  static Future<void> start({String title = '微信机器人', String body = '在线'}) async {
    try {
      await _channel.invokeMethod('startForeground', {
        'title': title,
        'body': body,
      });
    } catch (e) {
      debugPrint('[WechatForeground] start failed: $e');
    }
  }

  static Future<void> stop() async {
    try {
      await _channel.invokeMethod('stopForeground');
    } catch (e) {
      debugPrint('[WechatForeground] stop failed: $e');
    }
  }

  /// 请求系统忽略电池优化（白名单），防止国产 ROM 后台杀前台服务。
  /// 用户可能需要在系统弹窗中确认；未确认不影响基本轮询。
  static Future<void> requestIgnoreBatteryOptimization() async {
    try {
      await _channel.invokeMethod('requestIgnoreBatteryOptimization');
    } catch (e) {
      debugPrint('[WechatForeground] request battery opt failed: $e');
    }
  }
}