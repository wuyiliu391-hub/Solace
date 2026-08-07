import 'package:equatable/equatable.dart';

enum ToolTaskStatus {
  running,
  cancelling,
  cancelled,
  completed,
  failed,
  recoverable
}

class ToolTaskState extends Equatable {
  final String taskId;
  final String chatId;
  final String task;
  final ToolTaskStatus status;
  final int step;
  final int maxSteps;
  final List<Map<String, dynamic>> trace;
  final String? error;
  final String? summary;

  const ToolTaskState({
    required this.taskId,
    required this.chatId,
    required this.task,
    this.status = ToolTaskStatus.running,
    this.step = 0,
    this.maxSteps = 10,
    this.trace = const [],
    this.error,
    this.summary,
  });

  Map<String, dynamic> toJson() => {
        'taskId': taskId,
        'chatId': chatId,
        'task': task,
        'status': status.name,
        'step': step,
        'maxSteps': maxSteps,
        'trace': trace,
        'error': error,
        'summary': summary,
      };

  factory ToolTaskState.fromJson(Map<String, dynamic> json) {
    final rawStatus = json['status']?.toString() ?? 'running';
    return ToolTaskState(
      taskId: json['taskId']?.toString() ?? '',
      chatId: json['chatId']?.toString() ?? '',
      task: json['task']?.toString() ?? '',
      status: ToolTaskStatus.values.firstWhere(
        (value) => value.name == rawStatus,
        orElse: () => ToolTaskStatus.recoverable,
      ),
      step: (json['step'] as num?)?.toInt() ?? 0,
      maxSteps: (json['maxSteps'] as num?)?.toInt() ?? 10,
      trace: (json['trace'] as List<dynamic>?)
              ?.whereType<Map>()
              .map((entry) => Map<String, dynamic>.from(entry))
              .toList() ??
          const [],
      error: json['error']?.toString(),
      summary: json['summary']?.toString(),
    );
  }

  ToolTaskState copyWith({
    ToolTaskStatus? status,
    int? step,
    List<Map<String, dynamic>>? trace,
    String? error,
    String? summary,
  }) {
    return ToolTaskState(
      taskId: taskId,
      chatId: chatId,
      task: task,
      status: status ?? this.status,
      step: step ?? this.step,
      maxSteps: maxSteps,
      trace: trace ?? this.trace,
      error: error ?? this.error,
      summary: summary ?? this.summary,
    );
  }

  @override
  List<Object?> get props =>
      [taskId, chatId, task, status, step, maxSteps, trace, error, summary];
}
