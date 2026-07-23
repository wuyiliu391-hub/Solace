import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

/// 通知监听服务 — 读取系统通知的 Flutter 桥接
///
/// 对标 Operit 的 getNotifications 工具，提供：
/// - 检查/请求通知使用权
/// - 读取最近的通知列表
/// - 通知计数
class DeviceNotificationService {
  static const _channel = MethodChannel('com.solace.solace/notification');

  /// 检查是否已授予通知使用权
  Future<bool> hasAccess() async {
    try {
      final result = await _channel.invokeMethod<bool>('hasNotificationAccess');
      return result ?? false;
    } catch (e) {
      debugPrint('DeviceNotificationService.hasAccess error: $e');
      return false;
    }
  }

  /// 打开系统通知使用权设置页面
  Future<bool> requestAccess() async {
    try {
      final result = await _channel.invokeMethod<bool>('requestNotificationAccess');
      return result ?? false;
    } catch (e) {
      debugPrint('DeviceNotificationService.requestAccess error: $e');
      return false;
    }
  }

  /// 获取最近的通知列表
  /// [limit] 最大返回数量，默认 20
  Future<List<DeviceNotification>> getNotifications({int limit = 20}) async {
    try {
      final result = await _channel.invokeMethod<List<dynamic>>(
        'getNotifications',
        {'limit': limit},
      );
      if (result == null) return [];
      return result
          .map((e) => DeviceNotification.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      debugPrint('DeviceNotificationService.getNotifications error: $e');
      return [];
    }
  }

  /// 获取当前缓存的未读通知数
  Future<int> getCount() async {
    try {
      final result = await _channel.invokeMethod<int>('getNotificationCount');
      return result ?? 0;
    } catch (e) {
      debugPrint('DeviceNotificationService.getCount error: $e');
      return 0;
    }
  }
}

/// 系统通知数据模型
class DeviceNotification {
  final String packageName;
  final String title;
  final String text;
  final int timestamp;
  final String? tag;

  const DeviceNotification({
    required this.packageName,
    required this.title,
    required this.text,
    required this.timestamp,
    this.tag,
  });

  factory DeviceNotification.fromMap(Map<String, dynamic> map) {
    return DeviceNotification(
      packageName: map['packageName'] as String? ?? '',
      title: map['title'] as String? ?? '',
      text: map['text'] as String? ?? '',
      timestamp: map['timestamp'] as int? ?? 0,
      tag: map['tag'] as String?,
    );
  }

  DateTime get dateTime => DateTime.fromMillisecondsSinceEpoch(timestamp);

  /// 格式化为 AI 可读的字符串
  String toDisplayString() {
    final time = '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    final app = _appNameFromPackage(packageName);
    final content = title.isNotEmpty ? '$title: $text' : text;
    return '[$time] $app — $content';
  }

  static String _appNameFromPackage(String pkg) {
    return switch (pkg) {
      'com.tencent.mm' => '微信',
      'com.tencent.mobileqq' => 'QQ',
      'com.tencent.wework' => '企业微信',
      'com.alibaba.android.rimet' => '钉钉',
      'com.ss.android.ugc.aweme' => '抖音',
      'com.xingin.xhs' => '小红书',
      'com.taobao.taobao' => '淘宝',
      'com.jingdong.app.mall' => '京东',
      'com.android.mms' => '短信',
      'com.android.phone' => '电话',
      'com.android.email' => '邮件',
      'com.google.android.gm' => 'Gmail',
      'com.eg.android.AlipayGphone' => '支付宝',
      'com.sina.weibo' => '微博',
      'com.zhihu.android' => '知乎',
      'com.netease.cloudmusic' => '网易云音乐',
      'com.kugou.android' => '酷狗音乐',
      'tv.danmaku.bili' => 'B站',
      'com.douban.frodo' => '豆瓣',
      _ => pkg.split('.').last,
    };
  }
}