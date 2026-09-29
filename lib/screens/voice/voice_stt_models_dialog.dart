// 语音识别模型管理对话框：SenseVoice（STT）+ Silero VAD 的导入/删除。
// 入口：设置页 → 语音 → 语音识别模型。
// 导入：选文件夹 → sha1 校验 → 复制到私有目录（VoiceModelManager）。

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../services/voice/voice_model_manager.dart';

class VoiceSttModelsDialog extends StatefulWidget {
  const VoiceSttModelsDialog({super.key});

  @override
  State<VoiceSttModelsDialog> createState() => _VoiceSttModelsDialogState();
}

class _VoiceSttModelsDialogState extends State<VoiceSttModelsDialog> {
  Map<VoiceModelKind, bool> _statuses = {};
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final statuses = <VoiceModelKind, bool>{};
    for (final kind in _kinds) {
      statuses[kind] = await VoiceModelManager.instance.isReady(kind);
    }
    if (mounted) setState(() => _statuses = statuses);
  }

  static const _kinds = [VoiceModelKind.senseVoiceStt, VoiceModelKind.sileroVad];

  String _kindName(VoiceModelKind kind) => switch (kind) {
        VoiceModelKind.senseVoiceStt => '语音识别（SenseVoice）',
        VoiceModelKind.sileroVad => '语音断句（Silero VAD）',
      };

  Future<void> _importAll() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final path = await FilePicker.platform.getDirectoryPath();
      if (path == null) return;
      final result = await VoiceModelManager.instance
          .importAllFromDirectory(Directory(path));
      if (!mounted) return;
      setState(() {
        _message = result.allOk
            ? '导入成功（${result.ok}/${result.total} 个文件）'
            : '导入不完整：${result.missing.join('、')}${result.verifyFailed.isNotEmpty ? ' 校验失败：${result.verifyFailed.join('、')}' : ''}';
      });
      await _refresh();
    } catch (e) {
      if (mounted) setState(() => _message = '导入失败: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(VoiceModelKind kind) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除模型'),
        content: Text('确定删除「${_kindName(kind)}」模型文件以释放空间？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await VoiceModelManager.instance.delete(kind);
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('语音识别模型'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '语音通话 / 语音输入需要以下本地模型\n'
              '（模型文件不内置，选择文件夹后自动校验导入）',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            for (final kind in _kinds) ...[
              _modelRow(colorScheme, kind),
              const SizedBox(height: 8),
            ],
            if (_message != null) ...[
              const SizedBox(height: 4),
              Text(
                _message!,
                style: TextStyle(
                  fontSize: 12,
                  color: _message!.startsWith('导入成功')
                      ? Colors.green
                      : Colors.orange,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : _importAll,
          child: Text(_busy ? '导入中…' : '选择文件夹导入'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }

  Widget _modelRow(ColorScheme colorScheme, VoiceModelKind kind) {
    final ready = _statuses[kind] ?? false;
    final spec = VoiceModelRegistry.specOf(kind);
    return Row(
      children: [
        Icon(
          ready ? Icons.check_circle : Icons.circle_outlined,
          size: 18,
          color: ready ? Colors.green : colorScheme.outline,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _kindName(kind),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
              Text(
                '${(spec.totalBytes / 1024 / 1024).toStringAsFixed(1)} MB'
                ' · ${ready ? '已就绪' : '未导入'}',
                style: TextStyle(
                  fontSize: 11,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        if (ready)
          IconButton(
            icon: Icon(Icons.delete_outline, size: 18, color: Colors.red),
            onPressed: () => _delete(kind),
            tooltip: '删除模型',
          ),
      ],
    );
  }
}
