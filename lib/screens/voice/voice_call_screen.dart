// 实时语音通话全屏界面。
//
// 布局：Stack 固定定位（顶部头像区居中、底部挂断键、文字记录在中下部），
// 不再用 Spacer 挤压，避免内容增减时头像/名字偏移。
// 通话逻辑由 VoiceCallController 编排（回合制：VAD 断句 → 转写 → AI → 逐句播放）。

import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../blocs/chat/chat_bloc.dart';
import '../../models/chat_session.dart';
import '../../services/voice/voice_call_controller.dart';
import '../../utils/avatar_resolver.dart';

class VoiceCallScreen extends StatefulWidget {
  final ChatBloc chatBloc;
  final ChatSession session;
  final String userId;

  const VoiceCallScreen({
    super.key,
    required this.chatBloc,
    required this.session,
    required this.userId,
  });

  @override
  State<VoiceCallScreen> createState() => _VoiceCallScreenState();
}

class _VoiceCallScreenState extends State<VoiceCallScreen>
    with SingleTickerProviderStateMixin {
  late final VoiceCallController _controller;
  late final AnimationController _pulse;
  late final Animation<double> _ringScale;
  bool _popping = false;
  bool _canPop = false;

  @override
  void initState() {
    super.initState();
    _controller = VoiceCallController(
      chatBloc: widget.chatBloc,
      session: widget.session,
      userId: widget.userId,
    );
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
    _ringScale = Tween<double>(begin: 1.0, end: 1.25).animate(
      CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
    );
    unawaited(_controller.start());
  }

  @override
  void dispose() {
    _pulse.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _hangUp() async {
    if (_popping) return;
    _popping = true;
    await _controller.hangUp();
    if (mounted) {
      setState(() => _canPop = true);
      Navigator.of(context).pop();
    }
  }

  Future<void> _importModels() async {
    final path = await FilePicker.platform.getDirectoryPath();
    if (path == null) return;
    await _controller.importModels(Directory(path));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _canPop,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        unawaited(_hangUp());
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0B0E1A),
        body: SafeArea(
          child: ListenableBuilder(
            listenable: _controller,
            builder: (context, _) {
              return Stack(
                fit: StackFit.expand,
                children: [
                  // 顶部：头像 + 名字 + 状态（固定位置，不随内容偏移）
                  Column(
                    children: [
                      const SizedBox(height: 48),
                      _buildAvatarRing(),
                      const SizedBox(height: 24),
                      Text(
                        widget.session.aiCharacterName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _controller.statusText,
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                  // 底部：挂断键（固定）
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 48),
                      child: _buildHangUp(),
                    ),
                  ),
                  // 中部：文字记录（不参与顶部布局挤压）
                  Positioned(
                    top: 320,
                    left: 24,
                    right: 24,
                    bottom: 140,
                    child: _buildTranscript(),
                  ),
                  // 模型未就绪：覆盖层提示（不插入布局流）
                  if (_controller.needsModels)
                    Positioned.fill(
                      child: Container(
                        color: const Color(0xFF0B0E1A).withValues(alpha: 0.92),
                        child: Center(
                          child: _buildModelActions(),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildAvatarRing() {
    final avatar = AvatarResolver.imageWidget(
      widget.session.aiCharacterAvatar,
      width: 128,
      height: 128,
    );
    return AnimatedBuilder(
      animation: _ringScale,
      builder: (context, child) {
        final active = _controller.phase == VoiceCallPhase.aiSpeaking ||
            _controller.phase == VoiceCallPhase.listening;
        return Container(
          width: 168,
          height: 168,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: active
                  ? const Color(0xFF6C8CFF)
                      .withValues(alpha: 0.5 * _ringScale.value)
                  : Colors.white.withValues(alpha: 0.12),
              width: 2,
            ),
          ),
          child: Center(
            child: ClipOval(
              child: avatar ??
                  Container(
                    width: 128,
                    height: 128,
                    color: const Color(0xFF2A2F45),
                    child: const Icon(
                      Icons.person,
                      size: 64,
                      color: Colors.white38,
                    ),
                  ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTranscript() {
    final userText = _controller.lastUserText;
    final aiText = _controller.lastAiText;
    if (userText.isEmpty && aiText.isEmpty) {
      return const SizedBox.shrink();
    }
    return Align(
      alignment: Alignment.bottomLeft,
      child: SingleChildScrollView(
        reverse: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (aiText.isNotEmpty) ...[
              _bubble(aiText, alignRight: false),
              const SizedBox(height: 12),
            ],
            if (userText.isNotEmpty) ...[
              _bubble(userText, alignRight: true),
            ],
          ],
        ),
      ),
    );
  }

  Widget _bubble(String text, {required bool alignRight}) {
    return Align(
      alignment: alignRight ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 260),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: alignRight
              ? const Color(0xFF3E5CFF).withValues(alpha: 0.22)
              : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: alignRight ? Colors.white : Colors.white70,
            fontSize: 14,
            height: 1.4,
          ),
        ),
      ),
    );
  }

  Widget _buildModelActions() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '语音通话需要语音识别模型（SenseVoice + Silero VAD）\n'
            '请先下载模型分发包解压到文件夹后导入',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white54, fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _importModels,
            icon: const Icon(Icons.folder_open_outlined, size: 20),
            label: const Text('手动导入模型'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF3E5CFF),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHangUp() {
    return GestureDetector(
      onTap: _hangUp,
      child: Container(
        width: 72,
        height: 72,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Color(0xFFE5484D),
        ),
        child: const Icon(Icons.call_end, color: Colors.white, size: 32),
      ),
    );
  }
}
