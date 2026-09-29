import 'package:equatable/equatable.dart';

/// 日志来源
enum LifeLogSource {
  schedule,    // 由日程块自动生成
  share,       // 由主动分享产生
  crossVisit,  // 跨角色互访产生（主线二/A3）
  manual,      // 用户手动补充
}

LifeLogSource _parseSource(String? v) {
  switch (v) {
    case 'share':
      return LifeLogSource.share;
    case 'cross_visit':
    case 'crossVisit':
      return LifeLogSource.crossVisit;
    case 'manual':
      return LifeLogSource.manual;
    case 'schedule':
    default:
      return LifeLogSource.schedule;
  }
}

/// 角色生活日志 — 一天中某个时刻的第一人称记录
class LifeLog extends Equatable {
  final String id;
  final String characterId;
  final String userId;

  /// 归属日期 yyyy-MM-dd
  final String date;

  /// 记录时间 HH:mm
  final String time;

  /// 日志正文（第一人称）
  final String content;

  /// 情绪标签（对应 EmotionEngine 的 7 种基础情绪）
  final String? mood;

  /// 情绪强度 0.0 - 1.0
  final double moodIntensity;

  final LifeLogSource source;

  /// 关联事件 ID（如跨角色互访 ID）
  final String? relatedEventId;

  /// 是否已注入记忆库（避免重复）
  final bool pushedToMemory;

  final DateTime createdAt;

  const LifeLog({
    required this.id,
    required this.characterId,
    required this.userId,
    required this.date,
    required this.time,
    required this.content,
    this.mood,
    this.moodIntensity = 0.5,
    this.source = LifeLogSource.schedule,
    this.relatedEventId,
    this.pushedToMemory = false,
    required this.createdAt,
  });

  LifeLog copyWith({
    String? id,
    String? characterId,
    String? userId,
    String? date,
    String? time,
    String? content,
    String? mood,
    double? moodIntensity,
    LifeLogSource? source,
    String? relatedEventId,
    bool? pushedToMemory,
    DateTime? createdAt,
  }) {
    return LifeLog(
      id: id ?? this.id,
      characterId: characterId ?? this.characterId,
      userId: userId ?? this.userId,
      date: date ?? this.date,
      time: time ?? this.time,
      content: content ?? this.content,
      mood: mood ?? this.mood,
      moodIntensity: moodIntensity ?? this.moodIntensity,
      source: source ?? this.source,
      relatedEventId: relatedEventId ?? this.relatedEventId,
      pushedToMemory: pushedToMemory ?? this.pushedToMemory,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'character_id': characterId,
        'user_id': userId,
        'date': date,
        'time': time,
        'content': content,
        'mood': mood,
        'mood_intensity': moodIntensity,
        'source': _sourceToDb(source),
        'related_event_id': relatedEventId,
        'pushed_to_memory': pushedToMemory ? 1 : 0,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory LifeLog.fromMap(Map<String, dynamic> map) => LifeLog(
        id: map['id'] as String,
        characterId: map['character_id'] as String,
        userId: map['user_id'] as String,
        date: map['date'] as String,
        time: map['time'] as String,
        content: map['content'] as String,
        mood: map['mood'] as String?,
        moodIntensity: (map['mood_intensity'] as num?)?.toDouble() ?? 0.5,
        source: _parseSource(map['source'] as String?),
        relatedEventId: map['related_event_id'] as String?,
        pushedToMemory: (map['pushed_to_memory'] as int?) == 1,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
            (map['created_at'] as int?) ?? 0),
      );

  static String _sourceToDb(LifeLogSource s) {
    switch (s) {
      case LifeLogSource.crossVisit:
        return 'cross_visit';
      default:
        return s.name;
    }
  }

  @override
  List<Object?> get props => [
        id,
        characterId,
        userId,
        date,
        time,
        content,
        mood,
        moodIntensity,
        source,
        relatedEventId,
        pushedToMemory,
        createdAt,
      ];
}
