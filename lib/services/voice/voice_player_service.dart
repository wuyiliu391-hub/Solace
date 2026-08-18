// 语音播放服务：封装 audioplayers 播放本地 wav。
import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';

class VoicePlayerService {
  final AudioPlayer _player = AudioPlayer();
  Completer<void>? _pending;
  bool _speakerOn = false;

  Stream<void> get onComplete => _player.onPlayerComplete;

  /// 扬声器/听筒切换（仅 Android；iOS 由系统音频会话管理）。
  Future<void> setSpeakerphone(bool on) async {
    if (_speakerOn == on) return;
    _speakerOn = on;
    if (Platform.isAndroid) {
      await _player.setAudioContext(
        AudioContext(
          android: AudioContextAndroid(isSpeakerphoneOn: on),
        ),
      );
    }
  }

  /// 播放本地音频文件（会先停掉正在播的）。不等待播放结束。
  Future<void> play(String filePath) async {
    await _player.stop();
    await _player.play(DeviceFileSource(filePath));
  }

  /// 播放并等待自然播放结束（语音通话逐句播放用）。
  /// 外部调用 [stop] / [dispose] 会中断本次等待。
  Future<void> playAndWait(String filePath) async {
    final done = Completer<void>();
    _pending = done;
    late final StreamSubscription<void> sub;
    sub = _player.onPlayerComplete.listen((_) {
      if (!done.isCompleted) done.complete();
    });
    try {
      await _player.stop();
      await _player.play(DeviceFileSource(filePath));
      await done.future;
    } finally {
      await sub.cancel();
      if (_pending == done) _pending = null;
    }
  }

  /// 停止播放，并中断正在等待的 [playAndWait]。
  Future<void> stop() async {
    final pending = _pending;
    _pending = null;
    if (pending != null && !pending.isCompleted) pending.complete();
    await _player.stop();
  }

  Future<void> dispose() async {
    final pending = _pending;
    _pending = null;
    if (pending != null && !pending.isCompleted) pending.complete();
    await _player.dispose();
  }
}
