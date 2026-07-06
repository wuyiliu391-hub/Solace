import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../models/ai_character.dart';
import '../../repositories/local_storage_repository.dart';
import '../../services/voice_clone_service.dart';
import '../../services/tts_service.dart';
import '../../config/tts_config.dart';

/// 音色克隆设置页面
///
/// 功能：
/// 1. 上传音色样本（支持 mp3/wav）
/// 2. 试听合成效果
/// 3. 管理已保存的音色
class VoiceCloneScreen extends StatefulWidget {
  final AICharacter character;
  final LocalStorageRepository storage;

  const VoiceCloneScreen({
    super.key,
    required this.character,
    required this.storage,
  });

  @override
  State<VoiceCloneScreen> createState() => _VoiceCloneScreenState();
}

class _VoiceCloneScreenState extends State<VoiceCloneScreen> {
  final VoiceCloneService _voiceClone = VoiceCloneService();
  final TTSService _tts = TTSService();
  AudioPlayer? _player;
  
  bool _hasVoice = false;
  bool _isGenerating = false;
  bool _isPlaying = false;
  bool _isUploading = false;
  String? _previewPath;

  @override
  void initState() {
    super.initState();
    _loadVoiceStatus();
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  void _loadVoiceStatus() {
    setState(() {
      _hasVoice = _voiceClone.hasVoice(widget.character.id);
    });
  }

  Future<void> _pickAndUploadVoice() async {
    if (_isUploading) return;

    // 检查 TTS API Key（上传可以，但试听需要 Key）
    final hasKey = await TTSConfig.hasApiKey();

    setState(() => _isUploading = true);

    try {
      final result = await _voiceClone.pickAndSaveVoice(
        widget.character.id,
        previewText: TTSConfig.previewText,
      );

      if (result != null && mounted) {
        setState(() {
          _hasVoice = true;
          _previewPath = result.previewPath;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.previewPath != null
                ? '音色样本已保存，试听已就绪'
                : '音色已保存，但试听生成失败。请检查网络或 API Key 后点击试听重试'),
            backgroundColor: result.previewPath != null ? Colors.green : Colors.orange,
            duration: const Duration(seconds: 4),
          ),
        );

        // 自动播放试听
        if (result.previewPath != null) {
          await _playPreview(result.previewPath!);
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('上传失败，请重试'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('上传失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  Future<void> _generatePreview() async {
    if (!_hasVoice || _isGenerating || _isPlaying) return;

    // 检查 TTS API Key
    if (!await TTSConfig.hasApiKey()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('请先配置 TTS API Key：设置 → 语音 → TTS API Key'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 4),
          ),
        );
      }
      return;
    }

    setState(() => _isGenerating = true);

    try {
      // 冷却等待：避免连续点击触发 429
      await Future.delayed(const Duration(milliseconds: 500));

      final path = await _voiceClone.generatePreview(widget.character.id);
      if (path != null && mounted) {
        setState(() => _previewPath = path);
        await _playPreview(path);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('试听生成失败，请稍后重试'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final msg = e.toString().contains('频繁')
            ? '请求过于频繁，请等待几秒后重试'
            : e.toString().contains('超时')
                ? 'TTS 请求超时，请检查网络'
                : '生成失败: $e';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isGenerating = false);
      }
    }
  }

  Future<void> _playPreview(String path) async {
    try {
      // 校验文件是否存在且有效
      final file = File(path);
      if (!file.existsSync()) {
        debugPrint('VoiceClone: 音频文件不存在: $path');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('音频文件不存在，请重新生成'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      final size = await file.length();
      if (size < 100) {
        debugPrint('VoiceClone: 音频文件过小 ($size bytes)，可能损坏');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('音频文件异常，请重新生成'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      _player?.dispose();
      _player = AudioPlayer();

      setState(() => _isPlaying = true);

      await _player!.play(DeviceFileSource(path));
      // 加超时兜底，防止 onPlayerComplete 事件丢失导致卡死
      await _player!.onPlayerComplete.first
          .timeout(const Duration(seconds: 60), onTimeout: () {
        debugPrint('VoiceClone: 播放超时');
      });

      if (mounted) {
        setState(() => _isPlaying = false);
      }
    } catch (e) {
      debugPrint('VoiceClone: 播放失败: $e');
      if (mounted) {
        setState(() => _isPlaying = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('播放失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteVoice() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除音色'),
        content: const Text('确定要删除该角色的音色样本吗？'),
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

    if (confirmed == true) {
      await _voiceClone.deleteVoice(widget.character.id);
      if (mounted) {
        setState(() {
          _hasVoice = false;
          _previewPath = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('音色已删除'),
            backgroundColor: Colors.grey,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('音色克隆'),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: colorScheme.onSurface,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 角色信息
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withOpacity(0.3),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: colorScheme.primary.withOpacity(0.2),
                  child: Text(
                    widget.character.name.isNotEmpty
                        ? widget.character.name[0]
                        : '?',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.character.name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _hasVoice ? '已设置音色' : '未设置音色',
                        style: TextStyle(
                          fontSize: 14,
                          color: _hasVoice
                              ? Colors.green
                              : colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // 音色操作
          Container(
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                // 上传音色
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: _isUploading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.blue,
                            ),
                          )
                        : const Icon(Icons.upload_file, color: Colors.blue),
                  ),
                  title: const Text('上传音色样本'),
                  subtitle: const Text('支持 MP3、WAV 格式'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _isUploading ? null : _pickAndUploadVoice,
                ),

                if (_hasVoice) ...[
                  const Divider(height: 1, indent: 72),
                  // 试听
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: _isGenerating
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.green,
                              ),
                            )
                          : const Icon(Icons.play_circle_outline,
                              color: Colors.green),
                    ),
                    title: Text(_isPlaying ? '播放中...' : '试听效果'),
                    subtitle: const Text('使用示例文本生成语音'),
                    onTap: _isGenerating || _isPlaying
                        ? null
                        : _generatePreview,
                  ),

                  const Divider(height: 1, indent: 72),
                  // 删除
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child:
                          const Icon(Icons.delete_outline, color: Colors.red),
                    ),
                    title: const Text(
                      '删除音色',
                      style: TextStyle(color: Colors.red),
                    ),
                    subtitle: const Text('移除已保存的音色样本'),
                    onTap: _deleteVoice,
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 24),

          // 使用说明
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.surfaceVariant.withOpacity(0.3),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline,
                        size: 18, color: colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      '使用说明',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  '1. 上传一段清晰的语音样本（建议 10-30 秒）\n'
                  '2. 样本应只包含一个人的声音\n'
                  '3. 避免背景噪音和音乐\n'
                  '4. 设置后，AI 回复将使用该音色朗读\n'
                  '5. 语音通话功能也需要先设置音色',
                  style: TextStyle(fontSize: 13, height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}