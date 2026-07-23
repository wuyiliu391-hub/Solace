import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// 音乐播放状态
enum MusicPlaybackState { idle, loading, playing, paused, completed }

/// 播放循环模式
enum PlaybackLoopMode { sequential, singleRepeat, listRepeat }

/// 音乐共情模式的本地音频播放服务
class MusicPlaybackService {
  AudioPlayer? _player;
  MusicPlaybackState _state = MusicPlaybackState.idle;
  String? _currentFilePath;

  StreamSubscription? _stateSub;
  StreamSubscription? _positionSub;
  StreamSubscription? _durationSub;
  StreamSubscription? _completeSub;

  final _stateController = StreamController<MusicPlaybackState>.broadcast();
  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration>.broadcast();

  Stream<MusicPlaybackState> get stateStream => _stateController.stream;
  Stream<Duration> get positionStream => _positionController.stream;
  Stream<Duration> get durationStream => _durationController.stream;

  MusicPlaybackState get state => _state;
  String? get currentFilePath => _currentFilePath;
  Duration _position = Duration.zero;
  Duration get position => _position;
  Duration _duration = Duration.zero;
  Duration get duration => _duration;

  PlaybackLoopMode _loopMode = PlaybackLoopMode.sequential;
  PlaybackLoopMode get loopMode => _loopMode;

  /// 列表循环时由外部切下一首
  VoidCallback? onNextTrack;

  /// 防 completed 双通道重复触发
  bool _handlingComplete = false;
  /// 单曲循环重播中：忽略中间 stopped/completed 抖动
  bool _replaying = false;

  static const _notificationId = 999;
  static const _notificationChannelId = 'solace_music';
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  bool _notificationCreated = false;

  String _trackTitle = '';
  String _trackArtist = '';

  static final instance = MusicPlaybackService._();
  MusicPlaybackService._();

  Future<void> play(String filePath,
      {String title = '', String artist = ''}) async {
    await _player?.stop();
    await _player?.dispose();
    _unsubscribe();

    _player = AudioPlayer();
    _currentFilePath = filePath;
    _position = Duration.zero;
    _duration = Duration.zero;
    _trackTitle = title;
    _trackArtist = artist;
    _handlingComplete = false;
    _replaying = false;

    _setState(MusicPlaybackState.loading);

    _stateSub = _player!.onPlayerStateChanged.listen((s) {
      if (_replaying) return;
      switch (s) {
        case PlayerState.playing:
          _setState(MusicPlaybackState.playing);
          _showMediaNotification();
        case PlayerState.paused:
          _setState(MusicPlaybackState.paused);
          _showMediaNotification();
        case PlayerState.completed:
          _onCompleted();
        case PlayerState.stopped:
          if (_state != MusicPlaybackState.completed &&
              _state != MusicPlaybackState.loading) {
            _setState(MusicPlaybackState.idle);
          }
        default:
          break;
      }
    });

    _positionSub = _player!.onPositionChanged.listen((pos) {
      _position = pos;
      _positionController.add(pos);
    });

    _durationSub = _player!.onDurationChanged.listen((dur) {
      _duration = dur;
      _durationController.add(dur);
    });

    // 与 onPlayerStateChanged(completed) 二选一即可，但部分平台只发其一
    _completeSub = _player!.onPlayerComplete.listen((_) {
      _onCompleted();
    });

    // 本地 MP3：ReleaseMode.loop 在 Android 上常不重播，统一 stop + 手动循环
    await _player!.setReleaseMode(ReleaseMode.stop);
    await _player!.play(DeviceFileSource(filePath));
  }

  void _onCompleted() {
    if (_handlingComplete || _replaying) return;
    _handlingComplete = true;
    debugPrint('[MusicPlayback] 播放完成 (loop=$_loopMode)');

    switch (_loopMode) {
      case PlaybackLoopMode.singleRepeat:
        unawaited(_replayCurrent());
        return;
      case PlaybackLoopMode.listRepeat:
        if (onNextTrack != null) {
          _setState(MusicPlaybackState.completed);
          _handlingComplete = false;
          onNextTrack!();
        } else {
          unawaited(_replayCurrent());
        }
        return;
      case PlaybackLoopMode.sequential:
        _setState(MusicPlaybackState.completed);
        _handlingComplete = false;
        onNextTrack?.call();
        return;
    }
  }

  /// 单曲循环：本地 mp3 在 completed 后 resume 常无效，直接重新 play 源文件
  Future<void> _replayCurrent() async {
    final path = _currentFilePath;
    if (path == null || path.isEmpty) {
      _setState(MusicPlaybackState.completed);
      _handlingComplete = false;
      return;
    }

    _replaying = true;
    try {
      final player = _player;
      if (player == null) {
        await play(path, title: _trackTitle, artist: _trackArtist);
        return;
      }

      // 优先：同 player 重绑源再播（比 seek+resume 稳）
      await player.setReleaseMode(ReleaseMode.stop);
      await player.stop();
      await player.play(DeviceFileSource(path));
      _position = Duration.zero;
      _positionController.add(Duration.zero);
      _setState(MusicPlaybackState.playing);
      _showMediaNotification();
      debugPrint('[MusicPlayback] 单曲循环重播: $path');
    } catch (e) {
      debugPrint('[MusicPlayback] 单曲循环重播失败，整实例重建: $e');
      try {
        await play(path, title: _trackTitle, artist: _trackArtist);
      } catch (e2) {
        debugPrint('[MusicPlayback] 单曲循环彻底失败: $e2');
        _setState(MusicPlaybackState.completed);
      }
    } finally {
      _replaying = false;
      // 稍后再放闸，避免 completed 回声立刻二次触发
      Future<void>.delayed(const Duration(milliseconds: 200), () {
        _handlingComplete = false;
      });
    }
  }

  void toggleLoopMode() {
    const modes = PlaybackLoopMode.values;
    _loopMode = modes[(_loopMode.index + 1) % modes.length];
    debugPrint('[MusicPlayback] 循环模式: $_loopMode');
  }

  String get loopModeLabel {
    switch (_loopMode) {
      case PlaybackLoopMode.sequential:
        return '顺序';
      case PlaybackLoopMode.singleRepeat:
        return '单曲循环';
      case PlaybackLoopMode.listRepeat:
        return '列表循环';
    }
  }

  IconData get loopModeIcon {
    switch (_loopMode) {
      case PlaybackLoopMode.sequential:
        return Icons.repeat;
      case PlaybackLoopMode.singleRepeat:
        return Icons.repeat_one;
      case PlaybackLoopMode.listRepeat:
        return Icons.repeat;
    }
  }

  Future<void> pause() async {
    await _player?.pause();
  }

  Future<void> resume() async {
    final p = _player;
    if (p == null) return;
    if (_state == MusicPlaybackState.completed) {
      final path = _currentFilePath;
      if (path != null) {
        await play(path, title: _trackTitle, artist: _trackArtist);
        return;
      }
    }
    await p.resume();
  }

  Future<void> togglePlayPause() async {
    switch (_state) {
      case MusicPlaybackState.playing:
        await pause();
      case MusicPlaybackState.paused:
        await resume();
      case MusicPlaybackState.completed:
        final path = _currentFilePath;
        if (path != null) {
          await play(path, title: _trackTitle, artist: _trackArtist);
        }
      case MusicPlaybackState.idle:
        final path = _currentFilePath;
        if (path != null) {
          await play(path, title: _trackTitle, artist: _trackArtist);
        }
      case MusicPlaybackState.loading:
        break;
    }
  }

  Future<void> stop() async {
    _replaying = false;
    _handlingComplete = false;
    await _player?.stop();
    _setState(MusicPlaybackState.idle);
    _cancelMediaNotification();
  }

  Future<void> seek(Duration position) async {
    await _player?.seek(position);
    _position = position;
    _positionController.add(position);
  }

  Future<void> dispose() async {
    _unsubscribe();
    await _player?.dispose();
    _player = null;
    _currentFilePath = null;
    _setState(MusicPlaybackState.idle);
    _cancelMediaNotification();
  }

  void _setState(MusicPlaybackState s) {
    _state = s;
    _stateController.add(s);
  }

  void _unsubscribe() {
    _stateSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _completeSub?.cancel();
    _stateSub = null;
    _positionSub = null;
    _durationSub = null;
    _completeSub = null;
  }

  Future<void> _createNotificationChannel() async {
    if (_notificationCreated) return;
    final androidPlugin = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          _notificationChannelId,
          '音乐播放',
          description: 'Solace 音乐播放控制',
          importance: Importance.low,
          playSound: false,
          enableVibration: false,
          showBadge: false,
        ),
      );
    }
    _notificationCreated = true;
  }

  Future<void> _showMediaNotification() async {
    await _createNotificationChannel();
    final isPlaying = _state == MusicPlaybackState.playing;
    await _notifications.show(
      _notificationId,
      _trackTitle.isNotEmpty ? _trackTitle : 'Solace 音乐',
      _trackArtist.isNotEmpty
          ? '$_trackArtist ${isPlaying ? "● 正在播放" : "▮▮ 已暂停"}'
          : (isPlaying ? '● 正在播放' : '▮▮ 已暂停'),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _notificationChannelId,
          '音乐播放',
          channelDescription: 'Solace 音乐播放控制',
          importance: Importance.low,
          priority: Priority.low,
          ongoing: true,
          autoCancel: false,
          showWhen: false,
          playSound: false,
          enableVibration: false,
          icon: '@mipmap/ic_launcher',
        ),
      ),
    );
  }

  Future<void> _cancelMediaNotification() async {
    await _notifications.cancel(_notificationId);
  }
}
