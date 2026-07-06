import 'dart:async';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';

/// 微信风格语音气泡
class VoiceMessageBubble extends StatefulWidget {
  final String audioPath;
  final bool isFromAI;
  final int? durationMs;

  const VoiceMessageBubble({
    super.key,
    required this.audioPath,
    required this.isFromAI,
    this.durationMs,
  });

  @override
  State<VoiceMessageBubble> createState() => _VoiceMessageBubbleState();
}

class _VoiceMessageBubbleState extends State<VoiceMessageBubble>
    with SingleTickerProviderStateMixin {
  AudioPlayer? _player;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  late AnimationController _animController;
  StreamSubscription? _stateSub;
  StreamSubscription? _positionSub;
  StreamSubscription? _durationSub;
  StreamSubscription? _completeSub;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _completeSub?.cancel();
    _player?.dispose();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    if (_isPlaying) {
      await _player?.pause();
      _animController.stop();
      return;
    }
    _player ??= AudioPlayer();
    if (_position == Duration.zero) {
      await _player!.play(DeviceFileSource(widget.audioPath));
    } else {
      await _player!.resume();
    }
    _stateSub?.cancel();
    _stateSub = _player!.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _isPlaying = state == PlayerState.playing);
    });
    _positionSub?.cancel();
    _positionSub = _player!.onPositionChanged.listen((pos) {
      if (mounted) setState(() => _position = pos);
    });
    _durationSub?.cancel();
    _durationSub = _player!.onDurationChanged.listen((dur) {
      if (mounted) setState(() => _duration = dur);
    });
    _completeSub?.cancel();
    _completeSub = _player!.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() { _isPlaying = false; _position = Duration.zero; });
        _animController.reset();
      }
    });
    _animController.repeat();
    setState(() => _isPlaying = true);
  }

  String _fmt(Duration d) {
    final s = d.inSeconds;
    return '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isMe = !widget.isFromAI;
    final durationText = _duration.inSeconds > 0
        ? _fmt(_duration)
        : widget.durationMs != null
            ? _fmt(Duration(milliseconds: widget.durationMs!))
            : '';
    // 语音条宽度根据时长动态计算，最小60，最大200
    final seconds = _duration.inSeconds > 0 ? _duration.inSeconds : (widget.durationMs ?? 3000) ~/ 1000;
    final barWidth = (60 + seconds * 8).toDouble().clamp(60.0, 200.0);

    return GestureDetector(
      onTap: _togglePlay,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isMe ? const Color(0xFFD0EBFF) : Colors.white,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 微信风格：自己的语音波形在右（箭头在右），AI的在左
            if (isMe) ...[
              Text(durationText, style: const TextStyle(fontSize: 14, color: Color(0xFF1A1A1A))),
              const SizedBox(width: 8),
            ],
            // 波形动画
            AnimatedBuilder(
              animation: _animController,
              builder: (_, __) => CustomPaint(
                size: Size(barWidth, 24),
                painter: _WaveformPainter(
                  progress: _isPlaying ? _animController.value : 0.0,
                  color: const Color(0xFF1A1A1A).withOpacity(isMe ? 0.7 : 0.5),
                  isReverse: isMe,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Icon(_isPlaying ? Icons.pause : Icons.play_arrow, size: 20, color: const Color(0xFF1A1A1A)),
            if (!isMe) ...[
              const SizedBox(width: 8),
              Text(durationText, style: const TextStyle(fontSize: 14, color: Color(0xFF1A1A1A))),
            ],
          ],
        ),
      ),
    );
  }
}

/// 微信风格语音波形
class _WaveformPainter extends CustomPainter {
  final double progress;
  final Color color;
  final bool isReverse;

  _WaveformPainter({required this.progress, required this.color, this.isReverse = false});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    final barCount = (size.width / 4).floor();
    final heights = [0.3, 0.6, 1.0, 0.8, 0.5, 0.9, 0.4, 0.7, 0.6, 0.3];

    for (int i = 0; i < barCount; i++) {
      final h = heights[i % heights.length] * size.height * 0.8;
      final x = isReverse ? size.width - (i * 4 + 2) : (i * 4 + 2).toDouble();
      final y = (size.height - h) / 2;
      canvas.drawLine(Offset(x, y), Offset(x, y + h), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter old) => old.progress != progress || old.color != color;
}
