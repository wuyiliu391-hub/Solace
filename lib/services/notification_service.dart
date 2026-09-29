import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import '../config/constants.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    tz_data.initializeTimeZones();

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    // 创建朋友圈通知通道
    if (defaultTargetPlatform == TargetPlatform.android) {
      final androidPlugin = _notifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        await androidPlugin.createNotificationChannel(
          const AndroidNotificationChannel(
            NotificationChannels.moments,
            '朋友圈动态',
            description: 'AI 角色的朋友圈动态',
            importance: Importance.high,
          ),
        );
      }
    }

    _initialized = true;
    debugPrint('NotificationService 初始化完成');
  }

  void _onNotificationTapped(NotificationResponse response) {
    debugPrint('通知被点击: ${response.payload}');
    final payload = response.payload;
    if (payload != null && payload.startsWith('chat_')) {
      final sessionId = payload.substring(5);
      navigatorKey.currentState?.pushNamed('/chat', arguments: sessionId);
    } else if (payload != null && payload.startsWith('moment_')) {
      navigatorKey.currentState?.pushNamed('/moment');
    } else if (payload != null && payload.startsWith('letter_')) {
      navigatorKey.currentState?.pushNamed('/mailbox');
    }
  }

  Future<bool> requestPermission() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      final androidPlugin = _notifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      return await androidPlugin?.requestNotificationsPermission() ?? false;
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      final iosPlugin = _notifications.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      return await iosPlugin?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
    }
    return false;
  }

  Future<void> showInstantNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      NotificationChannels.messages,
      'Solace 消息',
      channelDescription: '来自 AI 好友的消息通知',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      enableVibration: true,
      enableLights: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(id, title, body, details, payload: payload);
    debugPrint('即时通知已发送: $title - $body');
  }

  Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
    String? payload,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      NotificationChannels.scheduled,
      'Solace 定时消息',
      channelDescription: 'AI 好友的定时问候',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      enableVibration: true,
      enableLights: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.from(scheduledTime, tz.local),
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: payload,
    );
    debugPrint('定时通知已安排: $title - ${scheduledTime.toString()}');
  }

  Future<void> scheduleDailyNotification({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
    String? payload,
  }) async {
    final now = DateTime.now();
    var scheduledDate = DateTime(now.year, now.month, now.day, hour, minute);
    
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    final androidDetails = AndroidNotificationDetails(
      NotificationChannels.daily,
      'Solace 每日问候',
      channelDescription: 'AI 好友的每日问候',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      enableVibration: true,
      enableLights: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.from(scheduledDate, tz.local),
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: payload,
    );
    debugPrint('每日通知已安排: $title - $hour:$minute');
  }

  Future<void> cancelNotification(int id) async {
    await _notifications.cancel(id);
    debugPrint('通知已取消: $id');
  }

  Future<void> cancelAllNotifications() async {
    await _notifications.cancelAll();
    debugPrint('所有通知已取消');
  }

  Future<List<PendingNotificationRequest>> getPendingNotifications() async {
    return await _notifications.pendingNotificationRequests();
  }
}
