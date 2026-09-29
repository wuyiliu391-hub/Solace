// 后台任务拆分 part
part of '../background_service.dart';

Future<void> _showMomentNotification({
  required String characterName,
  required String content,
  required String momentId,
}) async {
  final flp = FlutterLocalNotificationsPlugin();
  const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  await flp.initialize(const InitializationSettings(
    android: androidSettings,
    iOS: DarwinInitializationSettings(),
  ));

  final body = content.length > 50 ? '${content.substring(0, 50)}...' : content;
  await flp.show(
    DateTime.now().millisecondsSinceEpoch % 100000,
    '$characterName 发了新动态',
    body,
    const NotificationDetails(
      android: AndroidNotificationDetails(
        NotificationChannels.moments,
        '朋友圈动态',
        channelDescription: 'AI 角色的朋友圈动态',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      ),
    ),
    payload: 'moment_$momentId',
  );
}

Future<void> _showCommentNotification({
  required String characterName,
  required String content,
  required String momentId,
}) async {
  final flp = FlutterLocalNotificationsPlugin();
  const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  await flp.initialize(const InitializationSettings(
    android: androidSettings,
    iOS: DarwinInitializationSettings(),
  ));

  final body = content.length > 50 ? '${content.substring(0, 50)}...' : content;
  await flp.show(
    DateTime.now().millisecondsSinceEpoch % 100000,
    '$characterName 回复了你的评论',
    body,
    const NotificationDetails(
      android: AndroidNotificationDetails(
        NotificationChannels.moments,
        '朋友圈动态',
        channelDescription: 'AI 角色的朋友圈动态',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      ),
    ),
    payload: 'moment_$momentId',
  );
}

Future<void> _showLetterNotification({
  required String characterName,
  required String letterId,
}) async {
  final flp = FlutterLocalNotificationsPlugin();
  const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  await flp.initialize(const InitializationSettings(
    android: androidSettings,
    iOS: DarwinInitializationSettings(),
  ));

  await flp.show(
    DateTime.now().millisecondsSinceEpoch % 100000,
    '$characterName 给你写了一封信',
    '点开信箱查看 TA 想对你说的话',
    const NotificationDetails(
      android: AndroidNotificationDetails(
        NotificationChannels.scheduled,
        'AI 来信',
        channelDescription: 'AI 角色写给你的信',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      ),
    ),
    payload: 'letter_$letterId',
  );
}

