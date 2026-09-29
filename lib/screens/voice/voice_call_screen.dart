// 实时语音通话全屏界面（v2 全面升级）。
//
// 布局：深色渐变背景；顶部通话计时 + 状态标签；中央声波环（CustomPaint 动态
// 波瓣，按 phase 变色）+ 呼吸头像；底部控制条（扬声器 / 挂断 / 静音）。
// 通话逻辑由 VoiceCallController 编排（回合制：VAD 断句 → 转写 → AI → 逐句播放）。

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

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
  Timer? _ticker;
  Timer? _cursorTick;
  bool _cursorOn = false;
  bool _captionsOn = true; // 实时打印机（豆包式字幕）默认开
  final DateTime _screenStartedAt = DateTime.now();
  bool _popping = false;
  bool _canPop = false;

  // 手动输入（不方便说话时，如环境嘈杂/NSFW 场景）
  bool _showInput = false;
  final TextEditingController _inputCtrl = TextEditingController();

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
    _ringScale = Tween<double>(begin: 1.0, end: 1.12).animate(
      CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
    );
    // 通话计时（1s 刷新；controller 无 startedAt 时退回屏幕进入时刻）
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && !_controller.isEnded) setState(() {});
    });
    // 打字机光标闪烁（仅实时打印机开启时消耗）
    _cursorTick = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted && _captionsOn) setState(() => _cursorOn = !_cursorOn);
    });
    unawaited(_controller.start());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _cursorTick?.cancel();
    _pulse.dispose();
    _inputCtrl.dispose();
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

  String get _elapsedText {
    final start = _controller.callStartedAt ?? _screenStartedAt;
    final d = DateTime.now().difference(start);
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    String two(int v) => v.toString().padLeft(2, '0');
    return h > 0 ? '${two(h)}:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
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
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF101528), Color(0xFF0B0E1A), Color(0xFF0A0C16)],
              stops: [0.0, 0.55, 1.0],
            ),
          ),
          child: SafeArea(
            child: ListenableBuilder(
              listenable: _controller,
              builder: (context, _) {
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    Column(
                      children: [
                        const SizedBox(height: 12),
                        _buildTopBar(),
                        const SizedBox(height: 28),
                        _buildAvatarRing(),
                        const SizedBox(height: 22),
                        Text(
                          widget.session.aiCharacterName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _buildStatusLine(),
                        const SizedBox(height: 20),
                        Expanded(child: _buildTranscript()),
                        if (_showInput) _buildTextInput(),
                        _buildControlBar(),
                        const SizedBox(height: 28),
                      ],
                    ),
                    // 模型未就绪：覆盖层提示（不插入布局流）
                    if (_controller.needsModels)
                      Positioned.fill(
                        child: Container(
                          color: const Color(0xFF0B0E1A).withValues(alpha: 0.94),
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
      ),
    );
  }

  // ── 顶部：标签 + 通话计时 + 右上角实时打印机开关 ────────────────────────
  Widget _buildTopBar() {
    final active = _controller.phase != VoiceCallPhase.ended;
    return Row(
      children: [
        const SizedBox(width: 44),
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: active ? const Color(0xFF34D399) : Colors.white24,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '语音通话',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 14,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                _elapsedText,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 13,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
        // 右上角：实时打印机（字幕）开关
        SizedBox(
          width: 44,
          height: 44,
          child: IconButton(
            tooltip: _captionsOn ? '关闭实时字幕' : '开启实时字幕',
            icon: Icon(
              _captionsOn
                  ? Icons.subtitles_rounded
                  : Icons.subtitles_off_rounded,
              size: 22,
              color: _captionsOn
                  ? const Color(0xFF6C8CFF)
                  : Colors.white38,
            ),
            onPressed: () => setState(() => _captionsOn = !_captionsOn),
          ),
        ),
      ],
    );
  }

  // ── 中央：声波环 + 呼吸头像 ──────────────────────────────────────────────
  Widget _buildAvatarRing() {
    final avatar = AvatarResolver.imageWidget(
      widget.session.aiCharacterAvatar,
      width: 128,
      height: 128,
    );
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        return SizedBox(
          width: 280,
          height: 280,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // 动态声波环
              Positioned.fill(
                child: CustomPaint(
                  painter: _WaveRingPainter(
                    progress: _pulse.value,
                    color: _waveColor,
                    intensity: _waveIntensity,
                  ),
                ),
              ),
              // 呼吸光环
              Container(
                width: 168 * _ringScale.value,
                height: 168 * _ringScale.value,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _waveColor.withValues(alpha: 0.35),
                    width: 2,
                  ),
                ),
              ),
              // 头像
              ClipOval(
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
            ],
          ),
        );
      },
    );
  }

  Color get _waveColor => switch (_controller.phase) {
        VoiceCallPhase.listening => const Color(0xFF34D399),
        VoiceCallPhase.aiSpeaking => const Color(0xFF6C8CFF),
        VoiceCallPhase.thinking => const Color(0xFFF5B84C),
        VoiceCallPhase.connecting => Colors.white38,
        VoiceCallPhase.ended => Colors.white24,
      };

  /// 波瓣活跃度 0..1（听/说时起伏最大，思考时弱脉动，其余静置）。
  double get _waveIntensity => switch (_controller.phase) {
        VoiceCallPhase.listening ||
        VoiceCallPhase.aiSpeaking =>
          1.0,
        VoiceCallPhase.thinking => 0.45,
        _ => 0.12,
      };

  // ── 状态行（含静音徽标） ─────────────────────────────────────────────────
  Widget _buildStatusLine() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: Row(
        key: ValueKey(_controller.statusText),
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (_controller.muted) ...[
            const Icon(Icons.mic_off_rounded,
                size: 15, color: Color(0xFFF5B84C)),
            const SizedBox(width: 6),
          ],
          Text(
            _controller.statusText,
            style: const TextStyle(color: Colors.white60, fontSize: 15),
          ),
        ],
      ),
    );
  }

  // ── 中部：实时打印机（豆包式字幕）+ 全量文字记录气泡 ──────────────────
  //
  // 模拟单聊页：ListView(reverse) 底部贴齐 + 可上下滚动；历史来自控制器
  // 的 transcript（每轮 用户→AI 先后记录），倒序渲染后视觉上即「用户气泡
  // 在上、AI 气泡在下」，最新内容始终贴底。
  Widget _buildTranscript() {
    final history = _controller.transcript;
    final aiLive = _controller.aiStreamingText;
    // 小说模式：打字机强制只留对话，旁白实时剔除
    final liveClean =
        _captionsOn ? VoiceCallController.cleanSpokenText(aiLive) : '';
    final err = _controller.lastError;
    final hasLive = _captionsOn && (liveClean.isNotEmpty || err != null);
    if (history.isEmpty && !hasLive) {
      return const SizedBox.shrink();
    }

    // reverse:true 时 children[0] 渲染在视觉底部 → 实时行放最前（贴底），
    // 历史按倒序接在其上（越旧越靠上），与单聊页消息顺序一致。
    final children = <Widget>[
      if (hasLive && err != null) ...[
        _errorLine(err),
        const SizedBox(height: 10),
      ],
      if (hasLive && liveClean.isNotEmpty) ...[
        const SizedBox(height: 14),
        _typewriterLine(liveClean),
      ],
    ];
    for (final m in history.reversed) {
      final text =
          m.isUser ? m.content : VoiceCallController.cleanSpokenText(m.content);
      if (text.isEmpty) continue; // 纯旁白回复不占气泡
      children.add(_bubble(text, alignRight: m.isUser));
      children.add(const SizedBox(height: 10));
    }

    return ListView(
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      children: children,
    );
  }

  Widget _errorLine(String err) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFE5484D).withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: const Color(0xFFE5484D).withValues(alpha: 0.4),
          ),
        ),
        child: Text(
          err,
          style: const TextStyle(color: Color(0xFFFF8A8F), fontSize: 13),
        ),
      ),
    );
  }

  /// 打字机字幕行：AI 流式文本 + 闪烁光标。
  Widget _typewriterLine(String aiLive) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              aiLive,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
                height: 1.5,
              ),
            ),
          ),
          if (_cursorOn)
            const Padding(
              padding: EdgeInsets.only(left: 2, top: 2),
              child: Text(
                '▍',
                style: TextStyle(color: Colors.white70, fontSize: 20),
              ),
            ),
        ],
      ),
    );
  }

  Widget _bubble(String text, {required bool alignRight}) {
    return Align(
      alignment: alignRight ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 280),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: alignRight
                ? const [Color(0xFF3E5CFF), Color(0xFF5A6CFF)]
                : [Colors.white.withValues(alpha: 0.10), Colors.white.withValues(alpha: 0.06)],
          ),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(alignRight ? 14 : 4),
            bottomRight: Radius.circular(alignRight ? 4 : 14),
          ),
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

  // ── 底部控制条 ───────────────────────────────────────────────────────────
  Widget _buildControlBar() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _RoundControlButton(
          icon: _controller.speakerOn
              ? Icons.volume_up_rounded
              : Icons.volume_down_rounded,
          label: _controller.speakerOn ? '扬声器' : '听筒',
          active: _controller.speakerOn,
          color: const Color(0xFF6C8CFF),
          onTap: () => unawaited(_controller.toggleSpeaker()),
        ),
        _RoundControlButton(
          icon: _showInput
              ? Icons.keyboard_alt_rounded
              : Icons.chat_bubble_outline_rounded,
          label: _showInput ? '收起' : '打字',
          active: _showInput,
          color: const Color(0xFF9B8CFF),
          onTap: () => setState(() => _showInput = !_showInput),
        ),
        _buildHangUp(),
        _RoundControlButton(
          icon: _controller.muted
              ? Icons.mic_off_rounded
              : Icons.mic_rounded,
          label: _controller.muted ? '已静音' : '静音',
          active: _controller.muted,
          color: const Color(0xFFF5B84C),
          onTap: () => _controller.toggleMute(),
        ),
      ],
    );
  }

  /// 手动输入行：文字直接进回合管线（AI 回复照常 TTS 播放）。
  Widget _buildTextInput() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _inputCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 15),
              cursorColor: const Color(0xFF6C8CFF),
              minLines: 1,
              maxLines: 3,
              textInputAction: TextInputAction.send,
              decoration: const InputDecoration(
                hintText: '不方便说话时，在这里输入…',
                hintStyle: TextStyle(color: Colors.white38, fontSize: 14),
                border: InputBorder.none,
                isDense: true,
              ),
              onSubmitted: (_) => _sendTextInput(),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.send_rounded, color: Color(0xFF6C8CFF)),
            tooltip: '发送',
            onPressed: _sendTextInput,
          ),
        ],
      ),
    );
  }

  void _sendTextInput() {
    final t = _inputCtrl.text;
    if (t.trim().isEmpty) return;
    _inputCtrl.clear();
    unawaited(_controller.sendText(t)); // 保持输入框打开，可连续发送
  }

  Widget _buildHangUp() {
    return GestureDetector(
      onTap: _hangUp,
      child: Container(
        width: 76,
        height: 76,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFE5484D), Color(0xFFC93A3F)],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFE5484D).withValues(alpha: 0.35),
              blurRadius: 22,
              spreadRadius: 1,
            ),
          ],
        ),
        child: const Icon(Icons.call_end, color: Colors.white, size: 34),
      ),
    );
  }

  // ── 模型导入覆盖层 ───────────────────────────────────────────────────────
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
}

// ── 圆形控制按钮 ────────────────────────────────────────────────────────────
class _RoundControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final Color color;
  final VoidCallback onTap;

  const _RoundControlButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active
                  ? color.withValues(alpha: 0.22)
                  : Colors.white.withValues(alpha: 0.08),
              border: Border.all(
                color: active
                    ? color.withValues(alpha: 0.6)
                    : Colors.white.withValues(alpha: 0.12),
                width: 1.2,
              ),
            ),
            child: Icon(icon, color: active ? color : Colors.white70, size: 24),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              color: active ? color : Colors.white54,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

// ── 声波环画笔：N 个正弦调制波瓣，随 progress 旋转、按 intensity 起伏 ─────
class _WaveRingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final double intensity;

  _WaveRingPainter({
    required this.progress,
    required this.color,
    required this.intensity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final base = size.shortestSide / 2;
    const lobes = 12;
    final rot = progress * 2 * math.pi;
    final phase = progress * 2 * math.pi * 2;
    final paint = Paint()
      ..color = color.withValues(alpha: 0.35 * intensity.clamp(0.05, 1.0))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    final innerPaint = Paint()
      ..color = color.withValues(alpha: 0.12 * intensity.clamp(0.05, 1.0))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;

    // 静态内圈
    canvas.drawCircle(center, base * 0.62, innerPaint);

    final path = Path();
    for (var i = 0; i < lobes; i++) {
      final a = rot + i * 2 * math.pi / lobes;
      final wobble =
          0.78 + 0.22 * math.sin(phase + i * 1.7) * intensity.clamp(0.05, 1.0);
      final r = base * 0.86 * wobble;
      final p = center + Offset(math.cos(a), math.sin(a)) * r;
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_WaveRingPainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.intensity != intensity;
}
