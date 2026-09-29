import 'package:equatable/equatable.dart';

/// 定时事件类型
enum TimedEventType {
  birthday,     // 生日
  anniversary,  // 纪念日
  festival,     // 节日
  custom,       // 自定义
}

TimedEventType _parseType(String? v) {
  switch (v) {
    case 'birthday':
      return TimedEventType.birthday;
    case 'anniversary':
      return TimedEventType.anniversary;
    case 'festival':
      return TimedEventType.festival;
    case 'custom':
    default:
      return TimedEventType.custom;
  }
}

/// 定时事件 — 角色或用户设置的日期提醒（生日/纪念日/节日）
class TimedEvent extends Equatable {
  final String id;
  final String characterId;
  final String userId;
  final TimedEventType eventType;
  final String title;

  /// yyyy-MM-dd（如 2026-09-10）
  final String date;

  /// 是否每年重复
  final bool recurring;

  /// 提前几天提醒
  final int reminderDays;

  /// 已触发时间戳（毫秒），null 表示未触发
  final int? firedAt;

  /// 附加参数（JSON 字符串）
  final String? payloadJson;

  final DateTime createdAt;

  const TimedEvent({
    required this.id,
    required this.characterId,
    required this.userId,
    required this.eventType,
    required this.title,
    required this.date,
    this.recurring = false,
    this.reminderDays = 1,
    this.firedAt,
    this.payloadJson,
    required this.createdAt,
  });

  TimedEvent copyWith({
    String? id,
    String? characterId,
    String? userId,
    TimedEventType? eventType,
    String? title,
    String? date,
    bool? recurring,
    int? reminderDays,
    int? firedAt,
    bool clearFiredAt = false,
    String? payloadJson,
    DateTime? createdAt,
  }) {
    return TimedEvent(
      id: id ?? this.id,
      characterId: characterId ?? this.characterId,
      userId: userId ?? this.userId,
      eventType: eventType ?? this.eventType,
      title: title ?? this.title,
      date: date ?? this.date,
      recurring: recurring ?? this.recurring,
      reminderDays: reminderDays ?? this.reminderDays,
      firedAt: clearFiredAt ? null : (firedAt ?? this.firedAt),
      payloadJson: payloadJson ?? this.payloadJson,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  /// 是否为今天（含重复事件）
  bool isToday(DateTime now) {
    final today = _fmtDate(now);
    if (date == today) return true;
    if (!recurring) return false;
    // 重复：只比较月-日
    if (date.length < 10) return false;
    return date.substring(5) == today.substring(5);
  }

  /// 未来 N 天内（含重复事件）
  bool isWithin(DateTime now, int days) {
    for (var i = 0; i < days; i++) {
      if (isToday(now.add(Duration(days: i)))) return true;
    }
    return false;
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'character_id': characterId,
        'user_id': userId,
        'event_type': eventType.name,
        'title': title,
        'date': date,
        'recurring': recurring ? 1 : 0,
        'reminder_days': reminderDays,
        'fired_at': firedAt,
        'payload_json': payloadJson,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory TimedEvent.fromMap(Map<String, dynamic> map) => TimedEvent(
        id: map['id'] as String,
        characterId: map['character_id'] as String,
        userId: map['user_id'] as String,
        eventType: _parseType(map['event_type'] as String?),
        title: map['title'] as String? ?? '',
        date: map['date'] as String? ?? '',
        recurring: (map['recurring'] as int?) == 1,
        reminderDays: (map['reminder_days'] as int?) ?? 1,
        firedAt: map['fired_at'] as int?,
        payloadJson: map['payload_json'] as String?,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
            (map['created_at'] as int?) ?? 0),
      );

  @override
  List<Object?> get props => [
        id,
        characterId,
        userId,
        eventType,
        title,
        date,
        recurring,
        reminderDays,
        firedAt,
        payloadJson,
        createdAt,
      ];

  static String _fmtDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
