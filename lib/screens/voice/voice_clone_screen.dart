// 角色音色克隆：录 3~5 秒该角色的声音（或选一个音频文件），
// 保存后该角色所有本地语音（气泡播放 / 语音通话）都用这个克隆音色。
//
// MiMo-V2.5-TTS-voiceclone：参考音频样本上传云端复刻音色，
// 不需要逐字文字稿（文字稿仅作参考展示）。样本支持 mp3/wav。

import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../services/permission_service.dart';
import '../../services/voice/audio_converter_service.dart';
import '../../services/voice/local_tts_service.dart';
import '../../services/voice/mimo_tts_service.dart';
import '../../services/voice/voice_player_service.dart';
import '../../services/voice/voice_profile_store.dart';
import '../../services/voice/voice_recorder_service.dart';

class VoiceCloneScreen extends StatefulWidget {
  final String characterId;
  final String characterName;

  const VoiceCloneScreen({
    super.key,
    required this.characterId,
    required this.characterName,
  });

  @override
  State<VoiceCloneScreen> createState() => _VoiceCloneScreenState();
}

class _VoiceCloneScreenState extends State<VoiceCloneScreen> {
  final LocalTtsService _tts = createLocalTtsService();
  final VoicePlayerService _player = VoicePlayerService();
  final VoiceRecorderService _recorder = VoiceRecorderService();
  final VoiceProfileStore _store = VoiceProfileStore.instance;
  final TextEditingController _transcriptController = TextEditingController();

  String? _refPath;
  bool _hasCustom = false;
  bool _recording = false;
  bool _converting = false;
  List<String>? _previewResults;
  int _recordSeconds = 0;
  Timer? _recordTimer;
  Timer? _tickTimer;
  bool _previewing = false;
  bool _saving = false;

  bool get _canPreview =>
      !_previewing &&
      !_converting &&
      _refPath != null;

  bool get _canSave =>
      !_saving &&
      !_converting &&
      _refPath != null;

  @override
  void initState() {
    super.initState();
    _loadCurrent();
  }

  Future<void> _loadCurrent() async {
    final custom = await _store.loadCustom(widget.characterId);
    if (!mounted) return;
    setState(() {
      if (custom != null) {
        _hasCustom = true;
        _refPath = custom.path;
        _transcriptController.text = custom.text;
      }
    });
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    _tickTimer?.cancel();
    _transcriptController.dispose();
    _recorder.dispose();
    _player.dispose();
    super.dispose();
  }

  // ───────────────────────────────────────────────────────────────────────────

  Future<void> _toggleRecord() async {
    if (_recording) {
      await _stopRecord();
      return;
    }
    final granted = await PermissionService.requestMicrophonePermission();
    if (!mounted) return;
    if (!granted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('需要麦克风权限才能录制参考音频')),
      );
      return;
    }
    try {
      // 参考音频：MiMo 接受 mp3/wav，录制 48kHz 双声道保证音质。
      await _recorder.start(sampleRate: 48000, channels: 2);
      setState(() {
        _recording = true;
        _recordSeconds = 0;
      });
      _tickTimer?.cancel();
      _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _recordSeconds++);
      });
      _recordTimer?.cancel();
      _recordTimer = Timer(const Duration(seconds: 6), _stopRecord);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('开始录音失败: $e')),
        );
      }
    }
  }

  Future<void> _stopRecord() async {
    if (!_recording) return;
    _recordTimer?.cancel();
    _tickTimer?.cancel();
    final path = await _recorder.stop();
    if (!mounted) return;
    setState(() {
      _recording = false;
      if (path != null && path.isNotEmpty) _refPath = path;
    });
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['wav', 'mp3', 'm4a', 'aac', 'ogg', 'flac'],
    );
    final path = result?.files.single.path;
    if (path == null || path.isEmpty) return;
    if (!mounted) return;

    // 非 wav（mp3/m4a 等）先转成 16-bit 单声道 wav 再用作参考音频。
    if (AudioConverterService.isWav(path)) {
      setState(() => _refPath = path);
      return;
    }

    setState(() => _converting = true);
    try {
      final wavPath = await AudioConverterService.instance.convertToWav(path);
      if (!mounted) return;
      setState(() => _refPath = wavPath);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '已转换为 wav：${wavPath.split(Platform.pathSeparator).last}',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('音频转换失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _converting = false);
    }
  }

  Future<void> _preview() async {
    if (!_canPreview) return;
    final refPath = _refPath!;
    final text = _transcriptController.text.trim();
    setState(() => _previewing = true);
    try {
      if (!await _tts.isModelReady) {
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            title: const Text('需要配置 MiMo TTS'),
            content: const Text(
              '音色克隆需要 MiMo TTS API Key。\n'
              '请到「我」→「设置」→「MiMo TTS 设置」填写 API Key 后重试。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('知道了'),
              ),
            ],
          ),
        );
        return;
      }
      await _tts.setReferenceAudio(widget.characterId, refPath, text);
      // 一次生成 3 版供挑选（官方建议：TTS 有随机性，多生成挑选）
      final tts = _tts as MiMoTtsService;
      final results = await tts.synthesizeMultiple(
        widget.characterId,
        '你好，我是${widget.characterName}，这是我的声音。',
        count: 3,
      );
      _previewResults = [for (final r in results) r.audioFilePath];
      if (!mounted) return;
      await _showPickVersionDialog();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('试听失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _previewing = false);
    }
  }

  /// 多版本挑选对话框：播放每版试听，点选满意的一版。
  Future<void> _showPickVersionDialog() async {
    final results = _previewResults;
    if (results == null || results.isEmpty) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                '已生成 3 个版本，试听后选一个满意的',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
            for (var i = 0; i < results.length; i++) ...[
              ListTile(
                leading: Icon(
                  Icons.graphic_eq,
                  color: Theme.of(ctx).colorScheme.primary,
                ),
                title: Text('版本 ${i + 1}'),
                trailing: IconButton(
                  icon: const Icon(Icons.play_arrow_rounded),
                  onPressed: () => _player.play(results[i]),
                ),
                onTap: () async {
                  await _player.stop();
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('已选版本 ${i + 1}，可点击「试听」重新挑选'),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  }
                },
              ),
              if (i < results.length - 1) const Divider(height: 1),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_canSave) return;
    final refPath = _refPath!;
    final text = _transcriptController.text.trim();
    setState(() => _saving = true);
    try {
      await _store.save(widget.characterId, refPath, text);
      if (!mounted) return;
      setState(() => _hasCustom = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已保存，该角色语音将使用这个音色')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _resetToDefault() async {
    await _store.delete(widget.characterId);
    if (!mounted) return;
    setState(() {
      _hasCustom = false;
      _refPath = null;
      _transcriptController.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已恢复默认示例音色')),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isDark ? const Color(0xFFE6C88A) : const Color(0xFF8A6D3B);

    return Scaffold(
      appBar: AppBar(
        title: Text('音色克隆 · ${widget.characterName}'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _hintCard(context, accent),
          const SizedBox(height: 16),

          // 当前状态
          Row(
            children: [
              Icon(
                _hasCustom ? Icons.check_circle : Icons.info_outline,
                size: 18,
                color: _hasCustom ? Colors.green : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(
                _hasCustom ? '当前音色：自定义（已生效）' : '当前音色：默认示例音色',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 参考音频
          _sectionTitle('① 参考音频（3~5 秒该角色的声音）'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _previewing || _saving || _converting
                      ? null
                      : _toggleRecord,
                  icon: Icon(_recording ? Icons.stop_rounded : Icons.mic_rounded),
                  label: Text(
                    _recording ? '停止（已录 $_recordSeconds 秒）' : '录制参考音频',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _previewing || _saving || _converting
                      ? null
                      : _pickFile,
                  icon: _converting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.audio_file_outlined),
                  label: Text(_converting ? '转换中…' : '选择音频文件'),
                ),
              ),
            ],
          ),
          if (_recording)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: LinearProgressIndicator(
                value: (_recordSeconds / 6).clamp(0.0, 1.0),
                backgroundColor: colorScheme.surfaceContainerHighest,
              ),
            ),
          if (_refPath != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '已选：${_refPath!.split(Platform.pathSeparator).last}',
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          const SizedBox(height: 16),

          // 文字稿（可选）
          _sectionTitle('② 文字稿（可选，仅作参考）'),
          const SizedBox(height: 8),
          TextField(
            controller: _transcriptController,
            maxLines: 3,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: '例如：各位村民, 大家新年好! 近期, 湖北省武汉市等多个地区',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              helperText: 'MiMo 音色克隆不要求文字稿，可不填',
            ),
          ),
          const SizedBox(height: 16),

          // 操作
          FilledButton.icon(
            onPressed: _canPreview ? _preview : null,
            icon: _previewing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.play_arrow_rounded),
            label: Text(_previewing ? '合成试听中…' : '试听（合成一句话）'),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _canSave ? _save : null,
            icon: const Icon(Icons.check_rounded),
            label: Text(_saving ? '保存中…' : '保存为该角色音色'),
          ),
          if (_hasCustom) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _previewing || _saving ? null : _resetToDefault,
              icon: const Icon(Icons.restore_rounded),
              label: const Text('恢复默认示例音色'),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            '保存后：单聊气泡播放、语音通话都会用这个音色。'
            '合成走 MiMo TTS 云端（需在设置中配置 API Key），无需本地模型。',
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _hintCard(BuildContext context, Color accent) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.graphic_eq_rounded, size: 18, color: accent),
              const SizedBox(width: 8),
              Text(
                '零样本音色克隆',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: accent,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '录一段 3~5 秒、干净无背景音的说话声，或选一个 mp3/m4a 音频文件；'
            '模型会复刻音色，之后所有语音都用它。文字稿可留空。',
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
    );
  }
}
