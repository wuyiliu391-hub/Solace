import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';

/// 播放模式
enum PlayMode {
  /// 单曲循环
  singleLoop,
  /// 顺序播放（当前只有一首歌，等同于单曲循环）
  sequence,
}

/// 音乐播放器服务 — 全局单例
///
/// 管理音频播放状态、进度、播放模式。
/// 独立于 UI，任何页面都可以控制播放。
class MusicPlayerService {
  static final MusicPlayerService _instance = MusicPlayerService._();
  factory MusicPlayerService() => _instance;
  MusicPlayerService._();

  final AudioPlayer _player = AudioPlayer();

  /// 当前播放状态
  bool get isPlaying => _player.state == PlayerState.playing;
  PlayerState get playerState => _player.state;

  /// 播放模式
  PlayMode _playMode = PlayMode.singleLoop;
  PlayMode get playMode => _playMode;

  /// 当前播放位置（秒）
  Duration _position = Duration.zero;
  Duration get position => _position;

  /// 总时长
  Duration? _duration;
  Duration? get duration => _duration;

  /// 是否已初始化（已设置音频源）
  bool _initialized = false;
  bool get initialized => _initialized;

  /// 当前音频源路径
  String? _currentSource;

  /// 内部订阅（dispose 时取消）
  StreamSubscription? _stateSub;
  StreamSubscription? _positionSub;
  StreamSubscription? _durationSub;
  StreamSubscription? _completeSub;

  /// 音量 (0.0 ~ 1.0)
  double _volume = 0.5;
  double get volume => _volume;

  /// 是否静音
  bool _isMuted = false;
  bool get isMuted => _isMuted;

  /// 静音前的音量
  double _volumeBeforeMute = 0.5;

  /// 音量流
  final _volumeController = StreamController<double>.broadcast();
  Stream<double> get volumeStream => _volumeController.stream;

  /// 进度流（用于 UI 更新）
  final _positionController = StreamController<Duration>.broadcast();
  Stream<Duration> get positionStream => _positionController.stream;

  /// 状态流（用于 UI 更新）
  final _stateController = StreamController<PlayerState>.broadcast();
  Stream<PlayerState> get stateStream => _stateController.stream;

  /// 播放模式流
  final _modeController = StreamController<PlayMode>.broadcast();
  Stream<PlayMode> get modeStream => _modeController.stream;

  /// 初始化监听器
  void initialize() {
    // 播放状态监听
    _stateSub?.cancel();
    _stateSub = _player.onPlayerStateChanged.listen((state) {
      _stateController.add(state);
    });

    // 播放进度监听
    _positionSub?.cancel();
    _positionSub = _player.onPositionChanged.listen((pos) {
      _position = pos;
      _positionController.add(pos);
    });

    // 总时长监听
    _durationSub?.cancel();
    _durationSub = _player.onDurationChanged.listen((dur) {
      _duration = dur;
    });

    // 播放完成监听 — 单曲循环时自动重播
    _completeSub?.cancel();
    _completeSub = _player.onPlayerComplete.listen((_) {
      if (_playMode == PlayMode.singleLoop) {
        _player.seek(Duration.zero);
        _player.resume();
      }
    });
  }

  /// 释放资源
  void dispose() {
    _stateSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _completeSub?.cancel();
    _player.dispose();
    _volumeController.close();
    _positionController.close();
    _stateController.close();
    _modeController.close();
  }

  /// 设置并播放音频源
  Future<void> setSource(String assetPath) async {
    try {
      _currentSource = assetPath;
      await _player.setSource(AssetSource(assetPath));
      _initialized = true;
      await _loadVolume();
      debugPrint('MusicPlayer: 已设置音频源 $assetPath');
    } catch (e) {
      debugPrint('MusicPlayer: 设置音频源失败: $e');
    }
  }

  /// 播放
  Future<void> play() async {
    if (!_initialized) {
      debugPrint('MusicPlayer: 未初始化音频源');
      return;
    }
    try {
      await _player.resume();
      debugPrint('MusicPlayer: 播放');
    } catch (e) {
      debugPrint('MusicPlayer: 播放失败: $e');
    }
  }

  /// 暂停
  Future<void> pause() async {
    try {
      await _player.pause();
      debugPrint('MusicPlayer: 暂停');
    } catch (e) {
      debugPrint('MusicPlayer: 暂停失败: $e');
    }
  }

  /// 播放/暂停切换
  Future<void> togglePlay() async {
    if (isPlaying) {
      await pause();
    } else {
      await play();
    }
  }

  /// 前进 10 秒
  Future<void> seekForward() async {
    if (_duration == null) return;
    final newPos = _position + const Duration(seconds: 10);
    final target = newPos > _duration! ? _duration! : newPos;
    await _player.seek(target);
  }

  /// 后退 10 秒
  Future<void> seekBackward() async {
    final newPos = _position - const Duration(seconds: 10);
    final target = newPos < Duration.zero ? Duration.zero : newPos;
    await _player.seek(target);
  }

  /// 跳转到指定位置
  Future<void> seekTo(Duration position) async {
    await _player.seek(position);
  }

  /// 加载保存的音量
  Future<void> _loadVolume() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _volume = prefs.getDouble('bgm_volume') ?? 0.5;
      _isMuted = prefs.getBool('bgm_muted') ?? false;
      final effectiveVolume = _isMuted ? 0.0 : _volume;
      await _player.setVolume(effectiveVolume);
      _volumeController.add(_volume);
    } catch (e) {
      debugPrint('MusicPlayer: 加载音量失败: $e');
    }
  }

  /// 保存音量到本地
  Future<void> _saveVolume() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('bgm_volume', _volume);
      await prefs.setBool('bgm_muted', _isMuted);
    } catch (e) {
      debugPrint('MusicPlayer: 保存音量失败: $e');
    }
  }

  /// 设置音量 (0.0 ~ 1.0)
  Future<void> setVolume(double vol) async {
    _volume = vol.clamp(0.0, 1.0);
    _isMuted = _volume == 0.0;
    await _player.setVolume(_volume);
    _volumeController.add(_volume);
    await _saveVolume();
  }

  /// 切换静音
  Future<void> toggleMute() async {
    if (_isMuted) {
      _isMuted = false;
      await _player.setVolume(_volumeBeforeMute);
      _volume = _volumeBeforeMute;
    } else {
      _volumeBeforeMute = _volume;
      _isMuted = true;
      await _player.setVolume(0.0);
    }
    _volumeController.add(_volume);
    await _saveVolume();
  }

  /// 切换播放模式
  void togglePlayMode() {
    _playMode = _playMode == PlayMode.singleLoop
        ? PlayMode.sequence
        : PlayMode.singleLoop;
    _modeController.add(_playMode);
    debugPrint('MusicPlayer: 播放模式切换为 $_playMode');
  }

}
