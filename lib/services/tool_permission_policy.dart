import '../repositories/local_storage_repository.dart';

enum ToolPermissionMode { ask, alwaysAllow, alwaysDeny }

/// Local, per-tool permission policy. The UI can use [pendingConfirmation]
/// to present a one-shot confirmation without granting future access.
class ToolPermissionPolicy {
  final LocalStorageRepository storage;
  static const _prefix = 'tool_permission_mode_';
  static const _pendingPrefix = 'tool_permission_pending_';

  const ToolPermissionPolicy(this.storage);

  ToolPermissionMode mode(String toolName) {
    final saved = storage.getString('$_prefix$toolName');
    if (saved == null && !isHighRisk(toolName)) {
      return ToolPermissionMode.alwaysAllow;
    }
    switch (saved) {
      case 'alwaysAllow':
        return ToolPermissionMode.alwaysAllow;
      case 'alwaysDeny':
        return ToolPermissionMode.alwaysDeny;
      default:
        return ToolPermissionMode.ask;
    }
  }

  bool isHighRisk(String toolName) {
    final name = toolName.toLowerCase();
    return name.contains('shell') ||
        name.contains('exec') ||
        name.contains('lock') ||
        name.contains('input') ||
        name.contains('ui_') ||
        name.contains('write') ||
        name.contains('edit') ||
        name.contains('command') ||
        name.contains('delete') ||
        name.contains('kill');
  }

  Future<void> setMode(String toolName, ToolPermissionMode value) {
    return storage.setString('$_prefix$toolName', value.name);
  }

  bool isAllowed(String toolName) =>
      mode(toolName) == ToolPermissionMode.alwaysAllow;

  bool isDenied(String toolName) =>
      mode(toolName) == ToolPermissionMode.alwaysDeny;

  Future<void> requestOnce(
      String taskId, String toolName, Map<String, dynamic> args) {
    return storage.setString(
      '$_pendingPrefix$taskId',
      '$toolName\n$args',
    );
  }

  Future<void> resolveOnce(String taskId) =>
      storage.remove('$_pendingPrefix$taskId');

  String? pendingConfirmation(String taskId) =>
      storage.getString('$_pendingPrefix$taskId');
}
