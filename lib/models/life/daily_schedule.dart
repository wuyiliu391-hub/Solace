import 'dart:convert';
import 'package:equatable/equatable.dart';

/// 日程活动类型 — 角色一天中可能做的事
enum LifeActivity {
  sleep,      // 睡眠
  wake,       // 起床/洗漱
  commute,    // 通勤
  work,       // 工作/学习
  meal,       // 吃饭
  rest,       // 休息/发呆
  hobby,      // 兴趣/娱乐
  social,     // 社交
  exercise,   // 运动
  relax,      // 放松（看剧/听歌）
  outing,     // 外出
}

LifeActivity _parseActivity(String? v) {
  if (v == null || v.isEmpty) return LifeActivity.rest;
  for (final a in LifeActivity.values) {
    if (a.name == v) return a;
  }
  return LifeActivity.rest;
}

/// 日程时间块 — 一个连续时间段内角色在做的事
class ScheduleBlock extends Equatable {
  /// 开始时间 HH:mm
  final String start;

  /// 结束时间 HH:mm
  final String end;

  /// 活动类型
  final LifeActivity activity;

  /// 展示给用户的短标签（如"在开会"、"午休"）
  final String label;

  /// 情绪基调提示（可选，用于影响日志/分享语气）
  final String? moodHint;

  /// 是否可被主动分享（决定 ActiveShareService 是否能消费）
  final bool shareable;

  /// 分享时的场景提示（用于生成分享文案/配图 prompt）
  final String? sharePrompt;

  const ScheduleBlock({
    required this.start,
    required this.end,
    required this.activity,
    required this.label,
    this.moodHint,
    this.shareable = false,
    this.sharePrompt,
  });

  Map<String, dynamic> toMap() => {
        'start': start,
        'end': end,
        'activity': activity.name,
        'label': label,
        'moodHint': moodHint,
        'shareable': shareable,
        'sharePrompt': sharePrompt,
      };

  factory ScheduleBlock.fromMap(Map<String, dynamic> map) => ScheduleBlock(
        start: map['start'] as String? ?? '00:00',
        end: map['end'] as String? ?? '00:00',
        activity: _parseActivity(map['activity'] as String?),
        label: map['label'] as String? ?? '',
        moodHint: map['moodHint'] as String?,
        shareable: map['shareable'] as bool? ?? false,
        sharePrompt: map['sharePrompt'] as String?,
      );

  /// 分钟表示的开始时间（用于区间判断）
  int get startMinutes => _toMinutes(start);

  /// 分钟表示的结束时间
  int get endMinutes => _toMinutes(end);

  /// 判断某个 HH:mm 是否落在本时间块内（含 start，不含 end）
  bool contains(String time) {
    final t = _toMinutes(time);
    if (endMinutes > startMinutes) {
      return t >= startMinutes && t < endMinutes;
    }
    // 跨零点
    return t >= startMinutes || t < endMinutes;
  }

  static int _toMinutes(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length < 2) return 0;
    final h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;
    return h * 60 + m;
  }

  @override
  List<Object?> get props =>
      [start, end, activity, label, moodHint, shareable, sharePrompt];
}

/// 日程来源
enum ScheduleSource { rule, llm }

/// 角色一天的日程
class DailySchedule extends Equatable {
  final String id;
  final String characterId;
  final String userId;

  /// 归属日期 yyyy-MM-dd
  final String date;

  /// 时间块列表（按时间顺序）
  final List<ScheduleBlock> blocks;

  final DateTime generatedAt;
  final ScheduleSource generatedBy;
  final DateTime createdAt;

  const DailySchedule({
    required this.id,
    required this.characterId,
    required this.userId,
    required this.date,
    required this.blocks,
    required this.generatedAt,
    this.generatedBy = ScheduleSource.rule,
    required this.createdAt,
  });

  DailySchedule copyWith({
    String? id,
    String? characterId,
    String? userId,
    String? date,
    List<ScheduleBlock>? blocks,
    DateTime? generatedAt,
    ScheduleSource? generatedBy,
    DateTime? createdAt,
  }) {
    return DailySchedule(
      id: id ?? this.id,
      characterId: characterId ?? this.characterId,
      userId: userId ?? this.userId,
      date: date ?? this.date,
      blocks: blocks ?? this.blocks,
      generatedAt: generatedAt ?? this.generatedAt,
      generatedBy: generatedBy ?? this.generatedBy,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'character_id': characterId,
        'user_id': userId,
        'date': date,
        'blocks_json': jsonEncode(blocks.map((b) => b.toMap()).toList()),
        'generated_at': generatedAt.millisecondsSinceEpoch,
        'generated_by': generatedBy.name,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory DailySchedule.fromMap(Map<String, dynamic> map) {
    List<ScheduleBlock> blocks = const [];
    final raw = map['blocks_json'] as String?;
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List<dynamic>;
        blocks = list
            .map((e) => ScheduleBlock.fromMap(e as Map<String, dynamic>))
            .toList();
      } catch (_) {
        blocks = const [];
      }
    }
    return DailySchedule(
      id: map['id'] as String,
      characterId: map['character_id'] as String,
      userId: map['user_id'] as String,
      date: map['date'] as String,
      blocks: blocks,
      generatedAt: DateTime.fromMillisecondsSinceEpoch(
          (map['generated_at'] as int?) ?? 0),
      generatedBy: (map['generated_by'] as String?) == 'llm'
          ? ScheduleSource.llm
          : ScheduleSource.rule,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
          (map['created_at'] as int?) ?? 0),
    );
  }

  @override
  List<Object?> get props => [
        id,
        characterId,
        userId,
        date,
        blocks,
        generatedAt,
        generatedBy,
        createdAt,
      ];
}
