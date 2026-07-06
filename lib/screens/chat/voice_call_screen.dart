import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../../models/ai_character.dart';
import '../../models/chat_message.dart';
import '../../models/memory.dart';
import '../../services/tts_service.dart';
import '../../services/voice_clone_service.dart';
import '../../services/memory_engine.dart';
import '../../services/audio_transcription_service.dart';
import '../../repositories/local_storage_repository.dart';
import '../../config/constants.dart';
import '../../services/log_service.dart';
import '../../utils/response_decoder.dart';

/// 语音通话页面 — 微信风格
class VoiceCallScreen extends StatefulWidget {
  final AICharacter character;
  final String userId;
  final String? chatId;
  final LocalStorageRepository storage;

  const VoiceCallScreen({
    super.key,
    required this.character,
    required this.userId,
    this.chatId,
    required this.storage,
  });

  @override
  State<VoiceCallScreen> createState() => _VoiceCallScreenState();
}

enum _CallState { ringing, active, ended }

enum _ListenMode { none, localStt, cloudRecord }

class _VoiceCallScreenState extends State<VoiceCallScreen>
    with TickerProviderStateMixin {
  // ── 状态 ──
  bool _isActive = true;
  _CallState _callState = _CallState.ringing;
  bool _isMuted = false;
  bool _isSpeakerOn = false;
  bool _userHungUp = false;
  bool _isEnding = false; // 优雅退出中：流式继续但跳过TTS
  bool _isListening = false;
  bool _isThinking = false;
  bool _isSpeaking = false;

  // ── 对话 ──
  final List<_CallMessage> _messages = [];
  String _currentTranscript = '';

  // ── 服务 ──
  late final TTSService _tts;
  late final VoiceCloneService _voiceClone;
  late final MemoryEngine _memoryEngine;
  late final AudioTranscriptionService _transcription;
  AudioPlayer? _player;
  final _uuid = const Uuid();
  String _chatId = '';

  // ── 语音识别 ──
  late stt.SpeechToText _speech;
  bool _speechAvailable = false;
  _ListenMode _listenMode = _ListenMode.none;

  // ── 云端录音 ──
  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  String? _recordPath;
  Timer? _recordTimer;
  Timer? _amplitudeTimer;
  static const int _maxRecordSeconds = 120;
  static const int _silenceDurationMs = 5000;
  static const int _minRecordDurationMs = 800;
  DateTime? _lastSoundTime;
  DateTime? _recordStartTime;

  // ── 自适应降噪 ──
  double _noiseFloor = -45.0; // 环境底噪（自动校准）
  final List<double> _noiseSamples = [];
  bool _noiseCalibrated = false;
  static const int _noiseCalibrateMs = 1200; // 校准阶段时长
  static const double _speechMarginDb = 12.0; // 高于底噪多少 dB 算人声

  // ── 通话计时 ──
  int _callSeconds = 0;
  Timer? _callTimer;

  // ── 聆听看门狗：检测“在听但听不到”的卡死状态 ──
  Timer? _listenWatchdog;
  static const int _listenWatchdogSeconds = 15; // 15秒无结果则重启

  // ── 响铃动画 ──
  late AnimationController _ringAnimController;
  late Animation<double> _ringScaleAnim;

  @override
  void initState() {
    super.initState();
    _tts = TTSService();
    _voiceClone = VoiceCloneService();
    _memoryEngine = MemoryEngine(widget.storage);
    _transcription = AudioTranscriptionService(widget.storage);
    _speech = stt.SpeechToText();
    _chatId = widget.chatId ?? 'voice_call_${widget.character.id}';

    _ringAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _ringScaleAnim = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _ringAnimController, curve: Curves.easeInOut),
    );

    _startRinging();
  }

  @override
  void dispose() {
    _isActive = false;
    _callTimer?.cancel();
    _recordTimer?.cancel();
    _amplitudeTimer?.cancel();
    _listenWatchdog?.cancel();
    _micLevelTimer?.cancel();
    _interruptionTimer?.cancel();
    _safetyTimer?.cancel();
    _interruptRecorder.dispose();
    _speech.stop();
    _recorder.dispose();
    _player?.dispose();
    _ringAnimController.dispose();
    _cleanupRecordFile();
    super.dispose();
  }

  Future<void> _startRinging() async {
    final delayMs = 1500 + (DateTime.now().millisecond % 1500);
    await Future.delayed(Duration(milliseconds: delayMs));
    if (!_isActive || !mounted) return;
    _onCallAnswered();
  }

  void _onCallAnswered() {
    setState(() => _callState = _CallState.active);
    _ringAnimController.stop();

    _callTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _isActive) setState(() => _callSeconds++);
    });

    Future.delayed(const Duration(milliseconds: 500), _initSpeech);
  }

  // ═══════════════════════════════════════════════
  // 语音识别初始化
  // ═══════════════════════════════════════════════

  Future<void> _initSpeech() async {
    final status = await Permission.microphone.request();
    debugPrint('VoiceCall: 麦克风权限状态= $status');
    if (!status.isGranted) {
      debugPrint('VoiceCall: 麦克风权限未授予');
      _showPermissionDialog();
      return;
    }

    try {
      debugPrint('VoiceCall: 开始初始化 speech_to_text...');
      _speechAvailable = await _speech.initialize(
        onStatus: (status) {
          debugPrint('VoiceCall: STT onStatus = $status');
          LogService.instance.i('VoiceCall', 'STT status: $status');
          if (!_isActive) return;
          if (status == 'done' || status == 'notListening') {
            _handleSpeechEnd();
          }
        },
        onError: (error) {
          debugPrint('VoiceCall: STT onError = ${error.errorMsg}');
          LogService.instance.w('VoiceCall', 'STT error: ${error.errorMsg}');
          if (!_isActive) return;
          Future.delayed(const Duration(milliseconds: 800), () {
            if (_isActive && !_isMuted && !_isSpeaking) {
              _startListening();
            }
          });
        },
      );

      debugPrint('VoiceCall: _speechAvailable = $_speechAvailable');
      LogService.instance
          .i('VoiceCall', '语音识别 ${_speechAvailable ? "可用" : "不可用"}');

      if (_speechAvailable && _isActive) {
        _listenMode = _ListenMode.localStt;
        _startListening();
      } else {
        debugPrint('VoiceCall: 本地 STT 不可用，切换到云端录音模式');
        _listenMode = _ListenMode.cloudRecord;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('正在使用云端语音识别'),
              duration: Duration(seconds: 2),
            ),
          );
        }
        _startCloudRecording();
      }
    } catch (e) {
      debugPrint('VoiceCall: 初始化语音识别异常: $e');
      LogService.instance.e('VoiceCall', '初始化语音识别失败: $e');
      _listenMode = _ListenMode.cloudRecord;
      _startCloudRecording();
    }
  }

  // ═══════════════════════════════════════════════
  // 本地 STT 模式
  // ═══════════════════════════════════════════════

  void _startListening() {
    debugPrint('VoiceCall: _startListening() 被调用，mode=$_listenMode');
    if (_listenMode == _ListenMode.cloudRecord) {
      _startCloudRecording();
      _startListenWatchdog();
      return;
    }
    if (!_isActive || _isMuted || !_speechAvailable) {
      debugPrint('VoiceCall: _startListening() 条件不满足');
      return;
    }

    _startMicLevelMonitor();
    try {
      _speech.stop();
      _speech.listen(
        onResult: (result) {
          if (!_isActive) return;
          _listenWatchdog?.cancel();
          setState(() {
            _currentTranscript = result.recognizedWords;
            _isListening = true;
          });

          if (result.finalResult && result.recognizedWords.trim().isNotEmpty) {
            final text = result.recognizedWords.trim();
            LogService.instance.i('VoiceCall', '识别完成 "$text"');
            setState(() {
              _currentTranscript = '';
              _isListening = false;
            });
            _sendUserMessage(text);
          }
        },
        localeId: 'zh_CN',
        listenOptions: stt.SpeechListenOptions(
          listenMode: stt.ListenMode.dictation,
          cancelOnError: false,
          partialResults: true,
        ),
      );

      setState(() => _isListening = true);
      _startListenWatchdog();
      debugPrint('VoiceCall: speech.listen() 已调用');
      LogService.instance.i('VoiceCall', '开始监听');
    } catch (e) {
      debugPrint('VoiceCall: speech.listen() 异常: $e');
      Future.delayed(const Duration(seconds: 2), () {
        if (_isActive && !_isMuted && !_isSpeaking) {
          _startListening();
        }
      });
    }
  }

  /// 看门狗：如果聆听状态持续太久无结果，强制重启
  void _startListenWatchdog() {
    _listenWatchdog?.cancel();
    _listenWatchdog =
        Timer(const Duration(seconds: _listenWatchdogSeconds), () {
      if (!_isActive || _isSpeaking || _isMuted) return;
      debugPrint('VoiceCall: 看门狗触发 - 聆听超时，强制重启');
      _stopListening();
      Future.delayed(const Duration(milliseconds: 500), () {
        if (_isActive && !_isSpeaking && !_isMuted) {
          _startListening();
        }
      });
    });
  }

  void _handleSpeechEnd() {
    if (_currentTranscript.trim().isNotEmpty && !_isMuted && !_isSpeaking) {
      final text = _currentTranscript.trim();
      setState(() {
        _currentTranscript = '';
        _isListening = false;
      });
      _sendUserMessage(text);
    } else {
      setState(() => _isListening = false);
      Future.delayed(const Duration(milliseconds: 300), () {
        if (_isActive && !_isMuted && !_isSpeaking) {
          _startListening();
        }
      });
    }
  }

  void _stopListening() {
    _listenWatchdog?.cancel();
    _stopMicLevelMonitor();
    if (_listenMode == _ListenMode.localStt) {
      _speech.stop();
    } else if (_listenMode == _ListenMode.cloudRecord) {
      _stopCloudRecording();
    }
    setState(() => _isListening = false);
  }

  // ═══════════════════════════════════════════════
  // 云端录音模式（fallback）
  // ═══════════════════════════════════════════════

  Future<void> _startCloudRecording() async {
    debugPrint('VoiceCall: 开始云端录音');
    if (!_isActive || _isMuted || _isSpeaking || _isRecording) {
      debugPrint(
          'VoiceCall: 跳过录音，isActive=$_isActive, isMuted=$_isMuted, isSpeaking=$_isSpeaking, isRecording=$_isRecording');
      return;
    }

    try {
      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) {
        debugPrint('VoiceCall: record 无权限');
        return;
      }

      final dir = await getTemporaryDirectory();
      _recordPath =
          '${dir.path}/voice_call_${DateTime.now().millisecondsSinceEpoch}.wav';
      _lastSoundTime = DateTime.now();
      _recordStartTime = DateTime.now();

      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          numChannels: 1,
          bitRate: 32000,
          sampleRate: 16000,
        ),
        path: _recordPath!,
      );

      setState(() {
        _isListening = true;
        _isRecording = true;
      });
      _startMicLevelMonitor();
      debugPrint('VoiceCall: 录音已开始，path=$_recordPath');

      // 最大时长兜底：30 秒强制停止
      _recordTimer?.cancel();
      _recordTimer = Timer(const Duration(seconds: _maxRecordSeconds), () {
        debugPrint('VoiceCall: 录音达到最大时长，自动停止');
        _finishCloudRecording();
      });

      // 振幅检测：延迟 500ms 启动，等录音器初始化完成
      _noiseSamples.clear();
      _noiseCalibrated = false;
      _amplitudeTimer?.cancel();
      await Future.delayed(const Duration(milliseconds: 500));
      _recordStartTime = DateTime.now(); // 校准起始时间从延迟后算
      _amplitudeTimer =
          Timer.periodic(const Duration(milliseconds: 100), (_) async {
        if (!_isActive || !_isListening) return;

        try {
          final amp = await _recorder.getAmplitude();
          final db = amp.current;

          // 过滤无效值
          if (db.isInfinite || db.isNaN) return;

          final now = DateTime.now();
          final recordMs =
              now.difference(_recordStartTime ?? now).inMilliseconds;

          // 校准阶段：采集环境底噪
          if (!_noiseCalibrated && recordMs < _noiseCalibrateMs) {
            _noiseSamples.add(db);
            return;
          }

          // 校准完成（或校准期过了但没采到有效样本）
          if (!_noiseCalibrated &&
              (recordMs >= _noiseCalibrateMs || _noiseSamples.length >= 30)) {
            if (_noiseSamples.isEmpty) {
              // 没采到有效样本，用上次的底噪或默认值
              _noiseFloor = _noiseFloor > -200 ? _noiseFloor : -40.0;
              _noiseCalibrated = true;
              debugPrint(
                  'VoiceCall: 底噪校准无有效样本，沿用=${_noiseFloor.toStringAsFixed(1)} dB');
            } else {
              _noiseSamples.sort();
              final q1 = _noiseSamples[_noiseSamples.length ~/ 4];
              final q3 = _noiseSamples[_noiseSamples.length * 3 ~/ 4];
              final iqr = q3 - q1;
              final lowerBound = q1 - 1.5 * iqr;
              final quietSamples = _noiseSamples
                  .where((s) => s >= lowerBound && s <= q1)
                  .toList();
              if (quietSamples.isNotEmpty) {
                _noiseFloor =
                    quietSamples.reduce((a, b) => a + b) / quietSamples.length;
              } else {
                _noiseFloor = q1;
              }
              _noiseCalibrated = true;
              debugPrint(
                  'VoiceCall: 底噪校准完成 = ${_noiseFloor.toStringAsFixed(1)} dB (Q1=${q1.toStringAsFixed(1)}, IQR=${iqr.toStringAsFixed(1)})');
            }
          }

          // 自适应阈值 = 底噪 + 余量
          final threshold = _noiseFloor + _speechMarginDb;

          if (db > threshold) {
            // 高于阈值 = 人声，重置静音计时
            _lastSoundTime = now;
          } else {
            // 低于阈值 = 静音/底噪
            final silenceMs =
                now.difference(_lastSoundTime ?? now).inMilliseconds;
            if (recordMs >= _minRecordDurationMs &&
                silenceMs >= _silenceDurationMs) {
              debugPrint(
                  'VoiceCall: 检测到静音 ${silenceMs}ms (底噪=${_noiseFloor.toStringAsFixed(1)}, 阈值=${threshold.toStringAsFixed(1)})，自动停止录音');
              _amplitudeTimer?.cancel();
              _finishCloudRecording();
            }
          }
        } catch (_) {
          // 获取振幅失败，忽略
        }
      });
    } catch (e) {
      debugPrint('VoiceCall: 开始录音异常: $e');
      setState(() {
        _isListening = false;
        _isRecording = false;
      });
    }
  }

  Future<void> _finishCloudRecording() async {
    if (!_isActive || !_isRecording) return;

    _recordTimer?.cancel();
    _amplitudeTimer?.cancel();
    _isRecording = false;

    try {
      final path = await _recorder.stop();
      debugPrint('VoiceCall: 录音已停止，path=$path');
      setState(() => _isListening = false);

      if (path == null || !_isActive) {
        _restartListening();
        return;
      }

      // 检查文件大小，太小说明没说话
      final file = File(path);
      if (!file.existsSync()) {
        debugPrint('VoiceCall: 录音文件不存在');
        _restartListening();
        return;
      }

      final size = await file.length();
      debugPrint('VoiceCall: 录音文件大小=$size bytes');
      if (size < 2048) {
        debugPrint('VoiceCall: 录音太短，忽略');
        _cleanupRecordFile();
        _restartListening();
        return;
      }

      // 转码为 WAV（Whisper 兼容性更好）
      final wavPath = await _convertToWav(path);
      if (wavPath == null || !_isActive) {
        _restartListening();
        return;
      }

      setState(() => _isThinking = true);
      debugPrint('VoiceCall: 开始云端识别...');

      final text = await _transcription.transcribe(wavPath);

      // 清理临时文件
      _cleanupRecordFile();
      try {
        File(wavPath).deleteSync();
      } catch (_) {}

      if (!_isActive) return;
      setState(() => _isThinking = false);

      if (text != null && text.trim().isNotEmpty) {
        debugPrint('VoiceCall: 云端识别结果: "$text"');
        _sendUserMessage(text.trim());
      } else {
        debugPrint('VoiceCall: 云端识别无结果');
        _restartListening();
      }
    } catch (e) {
      debugPrint('VoiceCall: 结束录音异常: $e');
      setState(() {
        _isListening = false;
        _isThinking = false;
        _isRecording = false;
      });
      _restartListening();
    }
  }

  void _stopCloudRecording() {
    _recordTimer?.cancel();
    _amplitudeTimer?.cancel();
    _recorder.stop();
    _isRecording = false;
    setState(() => _isListening = false);
    _cleanupRecordFile();
  }

  Future<String?> _convertToWav(String inputPath) async {
    // 目前直接返回原路径，Whisper 也支持 m4a/aac
    // 如果后续需要严格 WAV，可以在这里用 ffmpeg 或 flutter_sound 转码
    return inputPath;
  }

  void _cleanupRecordFile() {
    if (_recordPath != null) {
      try {
        final f = File(_recordPath!);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
      _recordPath = null;
    }
  }

  // ═══════════════════════════════════════════════
  // 用户说完 → 发给 AI
  // ═══════════════════════════════════════════════

  // ── 用户打断标志 ──
  bool _userInterrupted = false;
  Timer? _safetyTimer;

  Future<void> _sendUserMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || !_isActive || _isMuted) return;

    // 过滤噪音识别结果
    if (trimmed.length <= 1) {
      debugPrint('VoiceCall: 过滤过短的识别结果: "$trimmed"');
      _restartListening();
      return;
    }
    final cleanText = trimmed.replaceAll(RegExp(r'[。！？，、.!? ,\s]'), '');
    if (cleanText.isEmpty || cleanText.length <= 1) {
      debugPrint('VoiceCall: 过滤无意义识别结果: "$trimmed"');
      _restartListening();
      return;
    }

    // 如果 AI 正在说话，打断它
    if (_isSpeaking) {
      _userInterrupted = true;
      await _player?.stop();
      _stopInterruptionMonitor();
      setState(() => _isSpeaking = false);
    }

    // 安全兜底：60 秒后强制重置状态（防止 TTS 卡死）
    _safetyTimer?.cancel();
    _safetyTimer = Timer(const Duration(seconds: 60), () {
      if (mounted && (_isSpeaking || _isThinking)) {
        debugPrint('VoiceCall: 安全兜底触发 - 强制重置状态');
        _userInterrupted = true;
        _player?.stop();
        _stopInterruptionMonitor();
        setState(() {
          _isSpeaking = false;
          _isThinking = false;
        });
        _stopMicLevelMonitor();
        _userInterrupted = false;
        _startListening();
      }
    });

    setState(() {
      _messages.add(_CallMessage(text: text, isFromAI: false));
      _isThinking = true;
    });

    debugPrint('VoiceCall: 开始处理用户输入: "$text"');

    try {
      String memoryContext = '';
      try {
        memoryContext = await _memoryEngine.buildConsolidatedMemoryPrompt(
          character: widget.character,
          userId: widget.userId,
          currentMessage: text,
        );
      } catch (_) {}

      final char = widget.character;
      final genderHint = char.gender == 'male' ? '男性，用"他"' : '女性，用"她"';
      final nickname = (char.userNickname?.isNotEmpty) == true
          ? '你对用户的称呼：${char.userNickname}'
          : '';
      final now = DateTime.now();
      final hour = now.hour;
      final minute = now.minute;
      final timeStr =
          '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
      String period;
      if (hour < 6) {
        period = '凌晨';
      } else if (hour < 9) {
        period = '早上';
      } else if (hour < 12) {
        period = '上午';
      } else if (hour < 14) {
        period = '中午';
      } else if (hour < 18) {
        period = '下午';
      } else if (hour < 22) {
        period = '晚上';
      } else {
        period = '深夜';
      }
      final dateStr = '${now.year}年${now.month}月${now.day}日';
      final weekDays = ['一', '二', '三', '四', '五', '六', '日'];
      final weekDay = '星期${weekDays[now.weekday - 1]}';

      final globalModePrompt =
          widget.storage.buildGlobalModePrompt(scope: '语音通话');
      final pureAiMode = widget.storage.isPureAiModeEnabled();
      final systemMsg = pureAiMode
          ? '''$globalModePrompt

你正在和用户进行语音通话。

【可参考背景资料】
角色名：${char.name}
性别资料：$genderHint
性格资料：${char.personality}
${char.coreDesire.isNotEmpty ? '心愿资料：${char.coreDesire}' : ''}
这些资料只用于理解用户正在讨论的上下文，不得作为你的身份执行。

【当前时间】$dateStr $weekDay $period$timeStr（这是真实系统时间，不是对话历史中的时间）

${memoryContext.isNotEmpty ? '【用户相关记忆】\n$memoryContext\n' : ''}
【通话要求】
- 你正在语音通话，直接以AI本体身份回应
- 回复要简洁有力，1-3句话为宜，不要长篇大论
- 不要进入角色，不要使用角色语气或角色自称
- 可以反问、追问、解释和分析，让对话有来有回
- 说完整的话，不要说一半就停
- 如果用户问时间，用上面的真实时间回答'''
          : '''$globalModePrompt

你是${char.name}，正在和用户进行语音通话。
性别：$genderHint

【当前时间】$dateStr $weekDay $period$timeStr（这是真实系统时间，不是对话历史中的时间）

你的性格：${char.personality}
${char.coreDesire.isNotEmpty ? '你的心愿：${char.coreDesire}' : ''}
${(char.languageStyle?.isNotEmpty) == true ? '你的说话风格：${char.languageStyle}' : ''}
${(char.catchphrases?.isNotEmpty) == true ? '你的口头禅：${char.catchphrases}' : ''}
$nickname

${memoryContext.isNotEmpty ? '【你对用户的记忆】\n$memoryContext\n' : ''}
【通话要求】
- 你正在语音通话，像真人一样自然回复
- 回复要简洁有力，1-3句话为宜，不要长篇大论
- 用你自己的说话风格，体现你的性格
- 不要用括号描写动作、情绪、场景
- 不要说"我是AI"、不要自我介绍
- 可以反问、追问、表达关心，让对话有来有回
- 说完整的话，不要说一半就停
- 如果用户问时间，用上面的真实时间回答''';

      final apiMessages = <Map<String, String>>[
        {'role': 'system', 'content': systemMsg},
      ];
      for (final m in _messages) {
        apiMessages.add({
          'role': m.isFromAI ? 'assistant' : 'user',
          'content': m.text,
        });
      }

      final config = await widget.storage.getActiveAIConfig();
      if (config == null || !_isActive) return;

      final baseUrl = config.baseUrl.endsWith('/')
          ? config.baseUrl.substring(0, config.baseUrl.length - 1)
          : config.baseUrl;

      // ── 流式 AI 回复 ──
      final client = http.Client();
      String accumulatedContent = '';
      try {
        final request =
            http.Request('POST', Uri.parse('$baseUrl/chat/completions'));
        request.headers['Content-Type'] = 'application/json; charset=utf-8';
        request.headers['Accept-Charset'] = 'utf-8';
        request.headers['Authorization'] = 'Bearer ${config.apiKey}';
        request.body = jsonEncode({
          'model': config.modelName,
          'messages': apiMessages,
          if (BuiltInAIProviders.isGlmZ19B(config.id, config.modelName)) ...{
            'temperature': GlmModeParams.voiceTemperature,
            'top_p': GlmModeParams.topP,
            'top_k': GlmModeParams.voiceTopK,
            'frequency_penalty': GlmModeParams.voiceFrequencyPenalty,
            'thinking_budget': GlmModeParams.voiceThinkingBudget,
            'max_tokens': GlmModeParams.voiceMaxTokens,
          } else ...{
            'temperature': 0.85,
            'max_tokens': widget.storage.isChatStyleNovelModeEnabled()
                ? config.maxTokens
                : 800,
          },
          'stream': true,
        });

        debugPrint(
            'VoiceCall: 发送 AI 请求，model=${config.modelName}, messages=${apiMessages.length}条');

        final streamedResponse =
            await client.send(request).timeout(const Duration(seconds: 30));
        final contentType = streamedResponse.headers['content-type'];

        debugPrint('VoiceCall: AI 响应状态码=${streamedResponse.statusCode}');

        if (streamedResponse.statusCode != 200) {
          final errorBytes = await streamedResponse.stream.toBytes();
          final body = await ResponseDecoder.decode(contentType, errorBytes);
          debugPrint(
              'VoiceCall: AI API 错误 ${streamedResponse.statusCode}: $body');
          setState(() => _isThinking = false);
          _restartListening();
          return;
        }

        // ── 逐句解析 + 立即 TTS ──
        String sentenceBuffer = '';
        bool firstChunk = true;

        final rawBytes = await streamedResponse.stream.toBytes();
        final decoded = await ResponseDecoder.decode(contentType, rawBytes);
        for (final line in decoded.replaceAll('\r\n', '\n').split('\n')) {
          // 优雅退出时继续接收文本（跳过TTS），强制退出时中断
          if (!_isActive) break;
          if (_userInterrupted && !_isEnding) break;

          final trimmed = line.trim();
          if (!trimmed.startsWith('data:')) continue;
          final data = trimmed.substring(5).trimLeft();
          if (data == '[DONE]') break;

          try {
            final json = jsonDecode(data) as Map<String, dynamic>;
            final choices = json['choices'] as List?;
            if (choices == null || choices.isEmpty) continue;
            final delta = choices[0]['delta'] as Map<String, dynamic>?;
            if (delta == null) continue;

            final content =
                (delta['content'] ?? delta['text']) as String? ?? '';
            if (content.isEmpty) continue;

            accumulatedContent += content;
            sentenceBuffer += content;

            // 第一个 chunk 到达，关闭"思考中"
            if (firstChunk) {
              firstChunk = false;
              setState(() {
                _messages.add(_CallMessage(text: '', isFromAI: true));
                _isThinking = false;
              });
            }

            // 更新最后一条消息的文本
            if (_messages.isNotEmpty && _messages.last.isFromAI) {
              setState(() {
                _messages[_messages.length - 1] =
                    _CallMessage(text: accumulatedContent, isFromAI: true);
              });
            }

            // 检测到完整句子，立即合成并播放
            final sentences = _tts.splitSentences(sentenceBuffer);
            if (sentences.length > 1) {
              // 最后一个可能不完整，保留在 buffer 里
              final toSpeak =
                  sentences.sublist(0, sentences.length - 1).join('');
              sentenceBuffer = sentences.last;

              if (toSpeak.trim().isNotEmpty) {
                debugPrint('VoiceCall: 检测到完整句子，准备TTS: "${toSpeak.trim()}"');
                await _speakSentence(toSpeak.trim());
              }
            }
          } catch (_) {}
        }

        // 处理 buffer 中剩余的文本
        debugPrint(
            'VoiceCall: AI 流式结束，accumulatedContent="$accumulatedContent", buffer="$sentenceBuffer"');
        if (sentenceBuffer.trim().isNotEmpty &&
            !_userInterrupted &&
            _isActive) {
          debugPrint('VoiceCall: 播放剩余buffer: "${sentenceBuffer.trim()}"');
          await _speakSentence(sentenceBuffer.trim());
        }
      } finally {
        client.close();
      }

      // 更新消息列表（最终文本）
      if (_messages.isNotEmpty &&
          _messages.last.isFromAI &&
          accumulatedContent.isNotEmpty) {
        setState(() {
          _messages[_messages.length - 1] =
              _CallMessage(text: accumulatedContent, isFromAI: true);
        });
      }

      // 优雅退出：流式完成，保存记忆并退出
      if (_isEnding) {
        _saveCallMemory();
        if (mounted) Navigator.pop(context);
        return;
      }

      // 播放完毕
      _safetyTimer?.cancel();
      if (mounted) {
        setState(() => _isSpeaking = false);
      }
      _stopMicLevelMonitor();
      _userInterrupted = false;

      Future.delayed(const Duration(milliseconds: 1500), () {
        if (_isActive && !_isMuted && !_isSpeaking && !_isEnding) {
          _startListening();
        }
      });
    } catch (e, stack) {
      debugPrint('VoiceCall: AI回复异常: $e');
      debugPrint('VoiceCall: 堆栈: $stack');
      LogService.instance.e('VoiceCall', 'AI回复失败: $e');
      if (mounted) {
        setState(() {
          _isThinking = false;
          _isSpeaking = false;
        });
        _stopMicLevelMonitor();
        _userInterrupted = false;
        if (!_isEnding) await _speakSentence('抱歉，我刚才走神了，能再说一遍吗？');
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (_isActive && !_isMuted && !_isSpeaking && !_isEnding)
            _startListening();
        });
      }
    }
  }

  // ═══════════════════════════════════════════════
  // TTS 合成 + 播放
  // ═══════════════════════════════════════════════

  /// 合成并播放单个句子（支持用户打断）
  Future<void> _speakSentence(String text) async {
    // 静音只影响录音，不影响 AI 播放
    if (!_isActive || _userInterrupted) {
      debugPrint(
          'VoiceCall: _speakSentence 跳过: isActive=$_isActive, interrupted=$_userInterrupted');
      return;
    }

    final voiceBase64 = _voiceClone.getVoiceBase64(widget.character.id);
    debugPrint(
        'VoiceCall: _speakSentence voiceBase64=${voiceBase64 != null ? "${voiceBase64.length} chars" : "NULL"}');
    if (voiceBase64 == null) {
      debugPrint('VoiceCall: 无音色数据，跳过 TTS');
      return;
    }

    if (!_isSpeaking) {
      setState(() => _isSpeaking = true);
      _stopListening();
    }

    try {
      final styleInstruction =
          _voiceClone.getStyleInstruction(widget.character.id);

      // 清理括号动作描写
      String cleanText = text;
      cleanText = cleanText.replaceAll(RegExp(r'\([^)]*\)'), '');
      cleanText = cleanText.replaceAll(RegExp(r'\[[^\]]*\]'), '');
      cleanText = cleanText.replaceAll(RegExp(r'（[^）]*）'), '');
      cleanText = cleanText.replaceAll(RegExp(r'【[^】]*】'), '');
      cleanText = cleanText.trim();
      if (cleanText.isEmpty) return;

      debugPrint('VoiceCall: 调用 TTS generateAudio, text="$cleanText"');
      final audioPath = await _tts.generateAudio(
        cleanText,
        voiceBase64: voiceBase64,
        styleInstruction: styleInstruction,
      );

      debugPrint('VoiceCall: TTS 返回 audioPath=$audioPath');
      if (audioPath == null || !_isActive || _userInterrupted) {
        debugPrint(
            'VoiceCall: TTS 播放跳过: path=$audioPath, isActive=$_isActive, interrupted=$_userInterrupted');
        return;
      }

      debugPrint('VoiceCall: 播放句子: $cleanText');

      _player?.dispose();
      _player = AudioPlayer();
      // 与试听保持一致，不设自定义 AudioContext
      await _player!.play(DeviceFileSource(audioPath));
      debugPrint('VoiceCall: AudioPlayer.play() 已调用');

      // 等播放完成（不启动打断录音，避免录音抢占音频焦点导致静音）
      try {
        await _player!.onPlayerComplete.first
            .timeout(const Duration(seconds: 120));
      } on TimeoutException {
        debugPrint('VoiceCall: 播放超时');
      }
    } catch (e) {
      debugPrint('VoiceCall: TTS 播放异常: $e');
    }
  }

  /// 播放期间监听用户声音，检测到就打断
  Timer? _interruptionTimer;
  final AudioRecorder _interruptRecorder = AudioRecorder();
  bool _interruptRecording = false;

  void _startInterruptionMonitor() {
    _interruptionTimer?.cancel();
    _interruptRecording = false;

    // 启动独立录音用于打断检测
    _startInterruptRecording();

    // 打断校准：采集底噪，跳过前 3 秒（避免回声校准）
    List<double> interruptNoiseSamples = [];
    bool interruptCalibrated = false;
    double interruptNoiseFloor = _noiseFloor;
    final interruptStart = DateTime.now();
    const int _interruptGraceMs = 3000; // 前 3 秒不检测打断（等回声消散）
    const double _interruptMarginDb = 25.0; // 需要高出底噪 25dB 才算打断

    _interruptionTimer =
        Timer.periodic(const Duration(milliseconds: 200), (_) async {
      if (!_isActive || _userInterrupted || !_interruptRecording) return;

      try {
        final amp = await _interruptRecorder.getAmplitude();
        final db = amp.current;
        final elapsed =
            DateTime.now().difference(interruptStart).inMilliseconds;

        // 前 3 秒是 grace period，只采集底噪不检测打断
        if (elapsed < _interruptGraceMs) {
          interruptNoiseSamples.add(db);
          if (elapsed > 1500 &&
              !interruptCalibrated &&
              interruptNoiseSamples.length > 5) {
            // 1.5 秒后校准底噪（取下四分位数，排除回声峰值）
            interruptNoiseSamples.sort();
            final q1Idx = interruptNoiseSamples.length ~/ 4;
            interruptNoiseFloor = interruptNoiseSamples[q1Idx > 0 ? q1Idx : 0];
            interruptCalibrated = true;
            debugPrint(
                'VoiceCall: 打断检测底噪 = ${interruptNoiseFloor.toStringAsFixed(1)} dB');
          }
          return;
        }

        if (!interruptCalibrated) {
          // 3 秒了还没校准完，用主录音的底噪
          interruptNoiseFloor = _noiseFloor;
          interruptCalibrated = true;
        }

        // 打断阈值 = 底噪 + 25dB（非常严格，只有近距离大声说话才触发）
        final threshold = interruptNoiseFloor + _interruptMarginDb;

        if (db > threshold) {
          debugPrint(
              'VoiceCall: 用户打断! db=${db.toStringAsFixed(1)}, 阈值=${threshold.toStringAsFixed(1)}');
          _userInterrupted = true;
          await _player?.stop();
          _stopInterruptionMonitor();
          if (mounted) setState(() => _isSpeaking = false);
          _stopMicLevelMonitor();
          Future.delayed(const Duration(milliseconds: 300), () {
            if (_isActive && !_isMuted) _startListening();
          });
        }
      } catch (_) {}
    });
  }

  Future<void> _startInterruptRecording() async {
    try {
      final hasPermission = await _interruptRecorder.hasPermission();
      if (!hasPermission) return;

      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/interrupt_${DateTime.now().millisecondsSinceEpoch}.wav';
      await _interruptRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          numChannels: 1,
          bitRate: 32000,
          sampleRate: 16000,
        ),
        path: path,
      );
      _interruptRecording = true;
    } catch (e) {
      debugPrint('VoiceCall: 打断检测录音启动失败: $e');
    }
  }

  void _stopInterruptionMonitor() {
    _interruptionTimer?.cancel();
    _interruptionTimer = null;
    if (_interruptRecording) {
      _interruptRecorder.stop().catchError((_) {});
      _interruptRecording = false;
    }
  }

  void _restartListening() {
    Future.delayed(const Duration(milliseconds: 300), () {
      if (!_isActive || !mounted) return;
      // 重置可能卡住的思考状态
      if (_isThinking) {
        setState(() => _isThinking = false);
      }
      if (!_isMuted && !_isSpeaking) {
        _startListening();
      } else if (_isSpeaking) {
        debugPrint('VoiceCall: AI 正在说话，跳过重启录音');
      }
    });
  }

  // ═══════════════════════════════════════════════
  // 控制操作
  // ═══════════════════════════════════════════════

  void _toggleMute() {
    setState(() => _isMuted = !_isMuted);
    // 静音只影响新录音的启动，不中断当前正在进行的录音和AI播放
    if (!_isMuted && !_isSpeaking) {
      _startListening();
    }
  }

  void _toggleSpeaker() {
    setState(() => _isSpeakerOn = !_isSpeakerOn);
  }

  Future<void> _saveChatMessage(String text, bool isFromAI) async {
    try {
      await widget.storage.saveChatMessage(ChatMessage(
        id: _uuid.v4(),
        chatId: _chatId,
        senderId: isFromAI ? 'ai_${widget.character.id}' : widget.userId,
        senderName: isFromAI ? (widget.character.name ?? '') : '',
        content: text,
        type: MessageType.text,
        status: MessageStatus.sent,
        createdAt: DateTime.now(),
        metadata: {'source': 'voice_call'},
      ));
    } catch (e) {
      debugPrint('VoiceCall: 保存消息失败: $e');
    }
  }

  Future<void> _saveCallMemory() async {
    if (_messages.isEmpty) {
      debugPrint('VoiceCall: _saveCallMemory 跳过，_messages 为空');
      return;
    }
    try {
      // 打印所有消息内容
      for (int i = 0; i < _messages.length; i++) {
        final m = _messages[i];
        debugPrint('VoiceCall: 消息[$i] isAI=${m.isFromAI} text="${m.text}"');
      }
      final summary = _messages
          .map((m) => '${m.isFromAI ? widget.character.name : "用户"}：${m.text}')
          .join('\n');
      final snippet = summary.length > 500
          ? summary.substring(summary.length - 500)
          : summary;
      debugPrint(
          'VoiceCall: 保存通话记忆，${_messages.length} 条消息，完整summary长度=${summary.length}');

      await widget.storage.saveMemory(Memory(
        id: _uuid.v4(),
        characterId: widget.character.id,
        userId: widget.userId,
        type: MemoryType.conversation,
        content: '【语音通话记录】\n$snippet',
        weight: 0.7,
        createdAt: DateTime.now(),
      ));
      debugPrint('VoiceCall: 通话记忆已保存，${_messages.length} 条消息');
    } catch (e) {
      debugPrint('VoiceCall: 保存通话记忆失败: $e');
    }
  }

  void _hangUp() {
    setState(() {
      _callState = _CallState.ended;
      _userHungUp = true;
      _isEnding = true;
    });
    _stopListening();
    _player?.stop();
    _userInterrupted = true; // 跳过TTS播放

    if (_isThinking) {
      // AI 正在回复，等流式完成再保存记忆并退出（最多等10秒）
      Future.delayed(const Duration(seconds: 10), () {
        _isActive = false;
        _saveCallMemory();
        if (mounted) Navigator.pop(context);
      });
    } else {
      _isActive = false;
      _saveCallMemory();
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted) Navigator.pop(context);
      });
    }
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('需要麦克风权限'),
        content: const Text('语音通话需要使用麦克风。请在系统设置中开启麦克风权限。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              openAppSettings();
            },
            child: const Text('去设置'),
          ),
        ],
      ),
    );
  }

  void _showTextInput() {
    final controller = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
          left: 16,
          right: 16,
          top: 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('文字输入',
                style: TextStyle(color: Colors.grey[600], fontSize: 13)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: '输入你想说的话...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                    ),
                    onSubmitted: (text) {
                      Navigator.pop(ctx);
                      _sendUserMessage(text);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _sendUserMessage(controller.text);
                  },
                  icon: const Icon(Icons.send_rounded),
                  color: Theme.of(context).colorScheme.primary,
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════
  // UI — 微信风格
  // ═══════════════════════════════════════════════

  String _formatCallTime() {
    final m = _callSeconds ~/ 60;
    final s = _callSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Widget _buildAvatar() {
    final avatarUrl = widget.character.avatarUrl;
    final size = 100.0;

    Widget avatarWidget;
    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      if (avatarUrl.startsWith('/') || avatarUrl.contains('\\')) {
        avatarWidget = ClipOval(
          child: Image.file(
            File(avatarUrl),
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _buildDefaultAvatar(size),
          ),
        );
      } else {
        avatarWidget = ClipOval(
          child: Image.network(
            avatarUrl,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _buildDefaultAvatar(size),
          ),
        );
      }
    } else {
      avatarWidget = _buildDefaultAvatar(size);
    }

    return avatarWidget;
  }

  Widget _buildDefaultAvatar(double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [
            Theme.of(context).colorScheme.primary,
            Theme.of(context).colorScheme.secondary,
          ],
        ),
      ),
      child: Center(
        child: Text(
          widget.character.name.isNotEmpty ? widget.character.name[0] : '?',
          style: TextStyle(
            color: Colors.white,
            fontSize: size * 0.4,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  // ── 音量动画 ──
  double _micLevel = 0.0; // 0.0~1.0，实时音量
  Timer? _micLevelTimer;

  void _startMicLevelMonitor() {
    _micLevelTimer?.cancel();
    _micLevelTimer =
        Timer.periodic(const Duration(milliseconds: 120), (_) async {
      if (!_isActive || _isMuted || !_isListening) {
        if (_micLevel != 0) setState(() => _micLevel = 0);
        return;
      }
      try {
        double db;
        if (_listenMode == _ListenMode.cloudRecord && _isRecording) {
          final amp = await _recorder.getAmplitude();
          db = amp.current;
        } else {
          db = -60;
        }
        // 相对于底噪的音量（底噪以下 = 0）
        final level = ((db - _noiseFloor) / 25).clamp(0.0, 1.0);
        if (mounted) setState(() => _micLevel = level);
      } catch (_) {}
    });
  }

  void _stopMicLevelMonitor() {
    _micLevelTimer?.cancel();
    _micLevelTimer = null;
    if (mounted && _micLevel != 0) setState(() => _micLevel = 0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF232428),
      body: SafeArea(
        child: Column(
          children: [
            // ── 顶部：头像 + 昵称 ──
            Padding(
              padding: const EdgeInsets.only(top: 60, bottom: 16),
              child: Column(
                children: [
                  AnimatedBuilder(
                    animation: _ringScaleAnim,
                    builder: (context, child) {
                      final scale = _callState == _CallState.ringing
                          ? _ringScaleAnim.value
                          : 1.0;
                      return Transform.scale(
                        scale: scale,
                        child: _buildAvatar(),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  Text(
                    widget.character.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _callState == _CallState.ringing
                        ? '正在呼叫...'
                        : _callState == _CallState.ended
                            ? (_userHungUp ? '通话已结束' : '对方已挂断')
                            : _isThinking
                                ? '思考中...'
                                : _isSpeaking
                                    ? '对方正在说话...'
                                    : _isListening
                                        ? '正在聆听...'
                                        : _isMuted
                                            ? '已静音'
                                            : _formatCallTime(),
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.45),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),

            // ── 中间：最近对话 ──
            Expanded(
              child: _messages.isEmpty
                  ? const SizedBox()
                  : Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 40),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: _messages
                            .take(3)
                            .toList()
                            .reversed
                            .map((m) => Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 3),
                                  child: Text(
                                    '${m.isFromAI ? widget.character.name : "你"}：${m.text}',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.25),
                                      fontSize: 13,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                  ),
                                ))
                            .toList(),
                      ),
                    ),
            ),

            // ── 底部：四个圆角方块按钮 ──
            Padding(
              padding: const EdgeInsets.only(bottom: 48, left: 24, right: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildSquareButton(
                    icon: Icons.menu_rounded,
                    label: '更多',
                    bgColor: const Color(0xFF3A3B3F),
                    onTap: () {},
                  ),
                  _buildMicButton(),
                  _buildSquareButton(
                    icon: _isSpeakerOn
                        ? Icons.volume_up_rounded
                        : Icons.volume_off_rounded,
                    label: _isSpeakerOn ? '免提' : '听筒',
                    bgColor:
                        _isSpeakerOn ? Colors.white : const Color(0xFF3A3B3F),
                    iconColor:
                        _isSpeakerOn ? const Color(0xFF232428) : Colors.white,
                    onTap: _toggleSpeaker,
                  ),
                  _buildHangUpButton(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 麦克风按钮（带音量动画）
  Widget _buildMicButton() {
    final isActive = !_isMuted;
    final bgColor = isActive ? Colors.white : const Color(0xFF3A3B3F);
    final iconColor = isActive ? const Color(0xFF232428) : Colors.white;

    return GestureDetector(
      onTap: _toggleMute,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(16),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // 音量波纹动画（蓝色从底部往上填充）
                  if (isActive && _micLevel > 0.02)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 100),
                        height: 64 * _micLevel,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              const Color(0xFF4FC3F7).withOpacity(0.6),
                              const Color(0xFF4FC3F7).withOpacity(0.1),
                            ],
                          ),
                        ),
                      ),
                    ),
                  // 麦克风图标
                  Icon(
                    _isListening
                        ? Icons.mic_rounded
                        : (isActive
                            ? Icons.mic_rounded
                            : Icons.mic_off_rounded),
                    color: (isActive && _micLevel > 0.02)
                        ? const Color(0xFF1E88E5)
                        : iconColor,
                    size: 28,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _isMuted ? '静音' : '麦克风',
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  /// 通用圆角方块按钮
  Widget _buildSquareButton({
    required IconData icon,
    required String label,
    required Color bgColor,
    Color iconColor = Colors.white,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: iconColor, size: 28),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  /// 挂断按钮（红色背景 + 白色电话图标）
  Widget _buildHangUpButton() {
    return GestureDetector(
      onTap: _hangUp,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Colors.red.shade600,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.call_end_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '挂断',
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _CallMessage {
  final String text;
  final bool isFromAI;
  _CallMessage({required this.text, required this.isFromAI});
}
