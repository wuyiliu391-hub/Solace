// 【对标来源：KouriChat-1.4.3.2 — modules/reminder/service.py ReminderTask】
// 1:1 转译自 KouriChat 提醒任务数据结构，扩展 createdAt/isCompleted
// 参考文件：modules/reminder/service.py:ReminderTask

/// 提醒任务（对标 KouriChat ReminderTask）
class ReminderTask {
  /// 任务 ID（对标 task_id）
  final String id;

  /// 会话 ID（对标 chat_id）
  final String chatId;

  /// 目标时间（对标 target_time）
  final DateTime targetTime;

  /// 提醒内容（对标 content）
  final String content;

  /// 发送者名称（对标 sender_name）
  final String senderName;

  /// 创建时间
  final DateTime createdAt;

  /// 是否已完成
  final bool isCompleted;

  /// 提醒类型：text / voice（对标 reminder_type）
  final String reminderType;

  /// 预生成的语音文件路径（对标 audio_path）
  final String? audioPath;

  const ReminderTask({
    required this.id,
    required this.chatId,
    required this.targetTime,
    this.content = '',
    this.senderName = '',
    required this.createdAt,
    this.isCompleted = false,
    this.reminderType = 'text',
    this.audioPath,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'chatId': chatId,
        'targetTime': targetTime.toIso8601String(),
        'content': content,
        'senderName': senderName,
        'createdAt': createdAt.toIso8601String(),
        'isCompleted': isCompleted,
        'reminderType': reminderType,
        'audioPath': audioPath,
      };

  factory ReminderTask.fromJson(Map<String, dynamic> json) {
    return ReminderTask(
      id: json['id'] as String? ?? '',
      chatId: json['chatId'] as String? ?? '',
      targetTime: json['targetTime'] != null
          ? DateTime.parse(json['targetTime'] as String)
          : DateTime.now(),
      content: json['content'] as String? ?? '',
      senderName: json['senderName'] as String? ?? '',
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now(),
      isCompleted: json['isCompleted'] as bool? ?? false,
      reminderType: json['reminderType'] as String? ?? 'text',
      audioPath: json['audioPath'] as String?,
    );
  }
}
