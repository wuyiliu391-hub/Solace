import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/storage/storage_recovery_controller.dart';

/// 数据库启动失败恢复页。
///
/// 当主数据库初始化/迁移失败时展示，提供：
/// - 重试初始化；
/// - 导出原始数据库文件（复制到备份目录，供人工抢救）；
/// - 重置数据库（先自动备份再删除，危险操作需二次确认）；
/// - 退出应用。
class StorageRecoveryScreen extends StatefulWidget {
  const StorageRecoveryScreen({
    super.key,
    required this.controller,
    required this.onRecovered,
  });

  final StorageRecoveryController controller;

  /// 重试成功后由外部（main）重新启动正常 App。
  final VoidCallback onRecovered;

  @override
  State<StorageRecoveryScreen> createState() => _StorageRecoveryScreenState();
}

class _StorageRecoveryScreenState extends State<StorageRecoveryScreen> {
  String? _lastBackupPath;
  String? _actionMessage;

  @override
  void initState() {
    super.initState();
    // 进入页面即自动重试一次
    WidgetsBinding.instance.addPostFrameCallback((_) => _retry());
  }

  Future<void> _retry() async {
    final ok = await widget.controller.retry();
    if (!mounted) return;
    if (ok) {
      widget.onRecovered();
    }
  }

  Future<void> _exportBackup() async {
    setState(() => _actionMessage = null);
    final path = await widget.controller.exportBackup();
    if (!mounted) return;
    setState(() {
      _lastBackupPath = path;
      _actionMessage = path == null ? '未找到数据库文件，无需导出。' : '数据库原始文件已复制到备份目录。';
    });
  }

  Future<void> _confirmReset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重置数据库？'),
        content: const Text(
          '将先自动备份当前数据库文件，然后删除数据库。'
          '删除后应用会重新创建一个空数据库，角色、聊天、记忆等数据都会清空。'
          '该操作不可撤销（除非从备份目录恢复）。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认重置'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _actionMessage = null);
    final backupPath = await widget.controller.resetDatabase();
    if (!mounted) return;
    setState(() {
      _lastBackupPath = backupPath;
      _actionMessage =
          backupPath == null ? '未找到数据库文件，无需重置。' : '数据库已重置，备份已保存。请重新启动应用。';
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: ListenableBuilder(
                listenable: widget.controller,
                builder: (context, _) {
                  final c = widget.controller;
                  final busy = c.busy;
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(
                        Icons.storage_rounded,
                        size: 56,
                        color: scheme.error,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '数据库启动失败',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '本地数据未能完成初始化或迁移。'
                        '你可以重试，或先导出数据库文件备份，再重置数据库。',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                      if (c.errorMessage != null &&
                          c.errorMessage!.trim().isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: scheme.errorContainer.withValues(
                              alpha: 0.4,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            c.errorMessage!,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: scheme.onErrorContainer),
                            maxLines: 6,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                      if (_actionMessage != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _actionMessage!,
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: scheme.primary),
                        ),
                      ],
                      if (_lastBackupPath != null) ...[
                        const SizedBox(height: 8),
                        SelectableText(
                          _lastBackupPath!,
                          textAlign: TextAlign.center,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                    fontFamily: 'monospace',
                                  ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: busy ? null : _retry,
                        icon: busy
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.refresh),
                        label: Text(
                          c.state == StorageRecoveryState.retrying
                              ? '正在重试…'
                              : '重试初始化',
                        ),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: busy ? null : _exportBackup,
                        icon: const Icon(Icons.save_alt),
                        label: const Text('导出数据库文件备份'),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: busy ? null : _confirmReset,
                        icon: const Icon(Icons.delete_forever),
                        label: const Text('重置数据库'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: scheme.error,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: () => SystemNavigator.pop(),
                        child: const Text('退出应用'),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
