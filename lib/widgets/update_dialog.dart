import 'dart:io';
import 'package:flutter/material.dart';
import '../services/update_service.dart';

class UpdateDialog extends StatefulWidget {
  final UpdateInfo info;

  const UpdateDialog({super.key, required this.info});

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

enum _UpdateState { initial, downloading, installing, failed }

class _UpdateDialogState extends State<UpdateDialog> {
  _UpdateState _state = _UpdateState.initial;
  double _progress = 0;
  String? _apkPath;
  bool _canInstall = true;

  @override
  void initState() {
    super.initState();
    _checkInstallPermission();
  }

  Future<void> _checkInstallPermission() async {
    if (Platform.isAndroid) {
      final can = await UpdateService().canRequestPackageInstalls();
      if (mounted) setState(() => _canInstall = can);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.system_update, color: colorScheme.primary, size: 28),
          const SizedBox(width: 10),
          Text(_state == _UpdateState.failed ? '安装失败' : '发现新版本'),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'v${widget.info.latestVersion}  (Build ${widget.info.buildNumber})',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: colorScheme.primary),
            ),
            const SizedBox(height: 12),
            const Text('更新内容：', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
            const SizedBox(height: 6),
            for (final item in widget.info.changelog)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('• ', style: TextStyle(color: colorScheme.primary, fontSize: 13)),
                    Expanded(child: Text(item, style: const TextStyle(fontSize: 13))),
                  ],
                ),
              ),
            if (_state == _UpdateState.downloading || _state == _UpdateState.installing) ...[
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: _progress > 1 || _progress < 0 ? null : _progress,
                  minHeight: 6,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _state == _UpdateState.installing
                    ? '正在安装...'
                    : _progress > 1
                        ? '正在下载... ${(_progress / 1024 / 1024).toStringAsFixed(1)} MB'
                        : _progress >= 0
                            ? '正在下载... ${(_progress * 100).toStringAsFixed(0)}%'
                            : '正在下载...',
                style: TextStyle(fontSize: 12, color: colorScheme.onSurface.withOpacity(0.5)),
              ),
            ],
            if (_state == _UpdateState.failed) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.error_outline, color: colorScheme.error, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            !_canInstall && Platform.isAndroid
                                ? '请在系统设置中允许「安装未知应用」权限'
                                : 'APK 文件已下载，请手动安装',
                            style: TextStyle(fontSize: 13, color: colorScheme.error),
                          ),
                        ),
                      ],
                    ),
                    if (_apkPath != null) ...[
                      const SizedBox(height: 8),
                      GestureDetector(
                        onLongPress: () => _showFilePath(),
                        child: Text(
                          _apkPath ?? '',
                          style: TextStyle(
                            fontSize: 10,
                            color: colorScheme.onSurface.withOpacity(0.4),
                            fontFamily: 'monospace',
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (_state == _UpdateState.initial || _state == _UpdateState.failed)
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        if (_state == _UpdateState.failed && _apkPath != null)
          TextButton(
            onPressed: _openFile,
            child: const Text('打开文件'),
          ),
        if (_state == _UpdateState.failed && Platform.isAndroid && !_canInstall)
          TextButton(
            onPressed: _openInstallSettings,
            child: const Text('去设置'),
          ),
        if (_state == _UpdateState.initial)
          ElevatedButton(
            onPressed: _startDownload,
            style: ElevatedButton.styleFrom(
              backgroundColor: colorScheme.primary,
              foregroundColor: colorScheme.onPrimary,
            ),
            child: const Text('立即更新'),
          ),
        if (_state == _UpdateState.failed)
          ElevatedButton(
            onPressed: _retryInstall,
            style: ElevatedButton.styleFrom(
              backgroundColor: colorScheme.primary,
              foregroundColor: colorScheme.onPrimary,
            ),
            child: const Text('重试安装'),
          ),
      ],
    );
  }

  Future<void> _startDownload() async {
    // 检查安装权限，未授权则先引导用户去设置
    if (Platform.isAndroid) {
      await _checkInstallPermission();
      if (!_canInstall) {
        final goSettings = await _showPermissionGuide();
        if (goSettings == true) {
          await _openInstallSettings();
          await _checkInstallPermission();
        }
        if (!_canInstall) return; // 用户未授权，不下载
      }
    }

    setState(() => _state = _UpdateState.downloading);

    _apkPath = await UpdateService().downloadApk(
      url: widget.info.downloadUrl,
      onProgress: (p) {
        if (mounted) setState(() => _progress = p);
      },
    );

    if (_apkPath == null) {
      if (mounted) {
        setState(() => _state = _UpdateState.initial);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('下载失败，请检查网络连接')),
        );
      }
      return;
    }

    await _installApk();
  }

  Future<bool?> _showPermissionGuide() {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.security, color: Colors.orange, size: 24),
            SizedBox(width: 10),
            Text('需要安装权限'),
          ],
        ),
        content: const Text(
          '安装 APK 需要开启「安装未知应用」权限。\n\n'
          '请点击「去设置」→ 找到「允许安装未知应用」→ 开启开关。\n\n'
          '开启后返回此页面即可继续安装。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消更新'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.primary,
              foregroundColor: Theme.of(ctx).colorScheme.onPrimary,
            ),
            child: const Text('去设置'),
          ),
        ],
      ),
    );
  }

  Future<void> _installApk() async {
    final apkPath = _apkPath;
    if (apkPath == null) return;
    setState(() => _state = _UpdateState.installing);

    final installed = await UpdateService().installApk(apkPath);

    if (mounted) {
      if (installed) {
        Navigator.pop(context);
      } else {
        setState(() => _state = _UpdateState.failed);
      }
    }
  }

  Future<void> _retryInstall() async {
    await _checkInstallPermission();
    await _installApk();
  }

  Future<void> _openFile() async {
    final apkPath = _apkPath;
    if (apkPath == null) return;
    final opened = await UpdateService().installApk(apkPath);
    if (mounted && !opened) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('无法打开文件: $_apkPath')),
      );
    }
  }

  Future<void> _openInstallSettings() async {
    await UpdateService().openInstallSourceSettings();
    await Future.delayed(const Duration(seconds: 2));
    await _checkInstallPermission();
  }

  void _showFilePath() {
    if (mounted && _apkPath != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('文件路径: $_apkPath')),
      );
    }
  }
}
