// 语音消息与通话（拆分生成，同库 part）
part of '../chat_detail_screen.dart';

mixin _StateVoice on State<ChatDetailScreen>, _StateCore, _StateLoadCore, _StateSelection, _StateSideStory {
  Future<void> _openVoiceCall(BuildContext context) async {
    final user = (context.read<AuthBloc>().state as AuthAuthenticated).user;
    if (!context.mounted) return;
    final micOk = await PermissionService.requestMicrophonePermission();
    if (!context.mounted) return;
    if (!micOk) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('需要麦克风权限才能语音通话')),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VoiceCallScreen(
          chatBloc: _chatBloc,
          session: widget.session,
          userId: user.id,
        ),
      ),
    );
  }


  /// 确保语音模型已就绪（STT/VAD 本地模型，导入入口在语音通话页）。
  Future<bool> _ensureVoiceModel(VoiceModelKind kind) async {
    if (await VoiceModelManager.instance.isReady(kind)) return true;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('语音识别模型未导入，请先到语音通话页导入'),
          duration: const Duration(seconds: 3),
        ),
      );
    }
    return false;
  }


  Future<({String path, String text})?> _resolveVoiceReference() async {
    try {
      final store = VoiceProfileStore.instance;
      final custom = await store.loadCustom(widget.session.aiCharacterId);
      if (custom != null) return custom;
      return await store.loadDefault();
    } catch (e) {
      debugPrint('解析参考音色失败: $e');
      return null;
    }
  }


  /// AI 消息气泡上的「播放语音」：合成该条消息的语音并播放。
  Future<void> _playMessageVoice(ChatMessage message) async {
    if (_synthesizingMessageId == message.id) return;
    final cleaned = MessageSanitizer.removeRepeatedContent(message.content);
    // 语音朗读只念「说出口的对白」：小说模式下的旁白/场景/心理一律不读。
    final text = MessageSanitizer.extractSpokenText(cleaned).trim();
    if (text.isEmpty) return;

    setState(() => _synthesizingMessageId = message.id);
    try {
      final storage = RepositoryProvider.of<LocalStorageRepository>(context);
      final config = await MiMoTtsConfigStore.load();
      if (config == null || !config.isValid) {
        if (mounted) {
          await showDialog<void>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('需要配置 MiMo TTS'),
              content: const Text(
                '语音合成需要 MiMo TTS API Key。\n'
                '请到「我」→「设置」→「MiMo TTS 设置」填写。',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('知道了'),
                ),
              ],
            ),
          );
        }
        return;
      }
      // 角色选了内置预置音色：无需参考音频，synthesizeWithStyle 自动切
      // mimo-v2.5-tts + Voice ID。
      final preset =
          await VoiceProfileStore.instance.loadPreset(widget.session.aiCharacterId);
      if (preset == null) {
        final ref = await _resolveVoiceReference();
        if (ref == null || !mounted) return;
        await _localTts.setReferenceAudio(
          widget.session.aiCharacterId,
          ref.path,
          ref.text,
        );
      }
      // 导演模式：用角色人设 + 当前台词生成风格指令
      AICharacter? character;
      try {
        character = await storage.getAICharacter(widget.session.aiCharacterId);
      } catch (_) {}
      final director = buildDirectorPrompt(character, text);
      final result = await (_localTts as MiMoTtsService).synthesizeWithStyle(
        widget.session.aiCharacterId,
        text,
        style: director,
      );
      if (!mounted) return;
      await _voicePlayer.play(result.audioFilePath);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('语音合成失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _synthesizingMessageId = null);
    }
  }


  /// 输入栏麦克风按钮：点一下开始录音，再点一下停止 → 转写 → 填入输入框。
  Future<void> _handleVoiceInput() async {
    tapHaptic();
    if (_isRecordingVoice) {
      // 停止录音并转写
      setState(() => _isRecordingVoice = false);
      final path = await _voiceRecorder.stop();
      if (path == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('录音失败，请重试')),
          );
        }
        return;
      }
      if (!mounted) return;
      setState(() => _isTranscribingVoice = true);
      try {
        final ready = await _ensureVoiceModel(VoiceModelKind.senseVoiceStt);
        if (!ready) {
          if (mounted) setState(() => _isTranscribingVoice = false);
          return;
        }
        final result = await _localStt.transcribe(path);
        if (!mounted) return;
        final text = result.text.trim();
        if (text.isNotEmpty) {
          _messageController.text = text;
          _messageController.selection =
              TextSelection.collapsed(offset: text.length);
          _syncCanSend();
          _messageFocusNode.requestFocus();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('没有识别到内容，请再说一次')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('语音识别失败: $e')),
          );
        }
      } finally {
        if (mounted) setState(() => _isTranscribingVoice = false);
        try {
          final f = File(path);
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
    } else {
      // 开始录音
      final granted = await PermissionService.requestMicrophonePermission();
      if (!mounted) return;
      if (!granted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('需要麦克风权限才能语音输入')),
        );
        return;
      }
      try {
        await _voiceRecorder.start();
        if (mounted) setState(() => _isRecordingVoice = true);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('开始录音失败: $e')),
          );
        }
      }
    }
  }

}
