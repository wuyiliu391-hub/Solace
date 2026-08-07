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

  const ToolTaskState({
    required this.taskId,
    required this.chatId,
    required this.task,
    this.status = ToolTaskStatus.running,
    this.step = 0,
    this.maxSteps = 10,
    this.trace = const [],
    this.error,
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
      };

  @override
  List<Object?> get props =>
      [taskId, chatId, task, status, step, maxSteps, trace, error];
}
