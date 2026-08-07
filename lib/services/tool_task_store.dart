import 'dart:convert';

import '../models/tool_task_state.dart';
import '../repositories/local_storage_repository.dart';

class ToolTaskStore {
  final LocalStorageRepository storage;

  const ToolTaskStore(this.storage);

  String _key(String taskId) => 'tool_task_$taskId';

  Future<void> save(ToolTaskState task) =>
      storage.setString(_key(task.taskId), jsonEncode(task.toJson()));

  ToolTaskState? load(String taskId) {
    final raw = storage.getString(_key(taskId));
    if (raw == null || raw.isEmpty) return null;
    try {
      return ToolTaskState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> remove(String taskId) => storage.remove(_key(taskId));
}
