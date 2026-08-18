// 实时语音通话编排器：回合制「聆听 → 转写 → AI 生成 → 逐句合成播放」状态机。
//
// 半双工回合制：放音时关麦、聆听时关播放，天然规避回声。
// 用户说完（Silero VAD 检测静音断句）→ SenseVoice 转写 → 走既有 ChatBloc
// 完整管线生成回复 → MiMo TTS 逐句合成并流水线播放，播完回到聆听。
//
// 生命周期安全设计（重构要点）：
// - 所有 async 操作在每次 await 后检查 [_disposed]/[_hangUpRequested]，立即退出
// - 资源（mic 流订阅 / bloc 流订阅 / 录音 / 播放）在函数返回前必清理
// - hangUp/dispose 幂等，可被多次调用
// - 任何异常不逃逸出状态机（回合级 try/catch + 状态回退）
//
// 可见性（实时打印机）：AI 流式文本经 [aiStreamingText] 逐帧暴露，
// 错误经 [lastError] 暴露给 UI（新回合清空）。

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../../blocs/chat/chat_bloc.dart';
import '../../models/chat_message.dart';
import '../../models/chat_session.dart';
import '../../utils/message_sanitizer.dart';
import 'local_stt_service.dart';
import 'mimo_tts_service.dart';
import 'voice_model_manager.dart';
import 'voice_player_service.dart';
import 'voice_profile_store.dart';
import 'voice_recorder_service.dart';
import 'voice_vad_service.dart';

enum VoiceCallPhase { connecting, listening, thinking, aiSpeaking, ended }

class VoiceCallController extends ChangeNotifier {
  final ChatBloc chatBloc;
  final ChatSession session;
  final String userId;

  final MiMoTtsService _tts;
  final LocalSttService _stt;
  final VoiceVadService _vad = VoiceVadService();
  final VoiceRecorderService _recorder = VoiceRecorderService();
  final VoicePlayerService _player = VoicePlayerService();

  VoiceCallPhase _phase = VoiceCallPhase.connecting;
  String _statusText = '正在连接…';
  String _lastUserText = '';
  String _lastAiText = '';
  bool _needsModels = false;

  bool _disposed = false;
  bool _hangUpRequested = false;
  bool _running = false;
  bool _finalized = false;
  bool _muted = false;
  bool _speakerOn = false;
  DateTime? _callStartedAt;

  /// AI 回复的实时流式文本（打字机字幕用；回复完成/失败即清空）。
  String _aiStreamingText = '';

  /// 最近一次错误（实时打印机红字显示；新回合开始清空）。
  String? _lastError;

    /// 通话内逐回合记录（用户/AI 消息），挂断后用于记忆提取与记录展示。
  final List<ChatMessage> _callTranscript = [];

  /// 通话全程逐轮记录（字幕气泡滚动展示用；与记忆提取共用同一份数据）。
  List<ChatMessage> get transcript => List.unmodifiable(_callTranscript);
  StreamSubscription<Uint8List>? _micSub;
  StreamSubscription<ChatState>? _blocSub;

    /// AI 思考期后台监听捕获的语音段，按序交回 [_runLoop] 立即转写。
  final List<Float32List> _interruptQueue = [];
  StreamSubscription<Uint8List>? _interruptSub;

  /// 手动输入待发文本（不方便说话时，如环境嘈杂/NSFW 场景），
  /// 与语音段共用同一回合管线，按序处理。
  final List<String> _pendingText = [];
  Completer<Float32List?>? _listenDone;
  Completer<String>? _replyDone;

  VoiceCallPhase get phase => _phase;
  String get statusText => _statusText;
  String get lastUserText => _lastUserText;
  String get lastAiText => _lastAiText;
  String get aiStreamingText => _aiStreamingText;
  String? get lastError => _lastError;
  bool get isEnded => _phase == VoiceCallPhase.ended;
  bool get needsModels => _needsModels;
  bool get muted => _muted;
  bool get speakerOn => _speakerOn;
  DateTime? get callStartedAt => _callStartedAt;

  VoiceCallController({
    required this.chatBloc,
    required this.session,
    required this.userId,
    MiMoTtsService? tts,
    LocalSttService? stt,
  })  : _tts = tts ?? MiMoTtsService(),
        _stt = stt ?? createLocalSttService();

  Future<void> start() async {
    if (_running || _disposed) return;
    _running = true;
    _callStartedAt ??= DateTime.now();
    _setPhase(VoiceCallPhase.connecting, '正在准备…');
    try {
      debugPrint('[VoiceCall] start: 检查模型就绪...');
      if (!await _allModelsReady()) {
        debugPrint('[VoiceCall] start: 模型未就绪，提示导入');
        _needsModels = true;
        _setPhase(VoiceCallPhase.connecting, '需要先导入语音识别模型');
        return;
      }
      debugPrint('[VoiceCall] start: 模型就绪，进入初始化');
      if (!_safe()) return;
      await _beginAfterModels();
      debugPrint('[VoiceCall] start: 初始化完成');
    } catch (e) {
      debugPrint('[VoiceCall] 初始化失败: $e');
      _lastError = '初始化失败：$e';
      _setPhase(VoiceCallPhase.ended, '初始化失败');
      notifyListeners();
    }
  }

  /// 手动导入：从用户选定目录校验并导入模型，完成后进入聆听。
  Future<void> importModels(Directory dir) async {
    if (_disposed) return;
    _needsModels = false;
    _setPhase(VoiceCallPhase.connecting, '正在校验并导入模型…');
    try {
      final result =
          await VoiceModelManager.instance.importAllFromDirectory(dir);
      if (!_safe()) return;
      if (!await _allModelsReady()) {
        _needsModels = true;
        final reason = result.missing.isNotEmpty
            ? '缺少文件：${result.missing.join('、')}'
            : '校验失败：${result.verifyFailed.join('、')}';
        _setPhase(VoiceCallPhase.connecting, '导入不完整（$reason）');
        return;
      }
      if (!_safe()) return;
      await _beginAfterModels();
    } catch (e) {
      debugPrint('[VoiceCall] 导入失败: $e');
      _needsModels = true;
      _lastError = '导入失败：$e';
      _setPhase(VoiceCallPhase.connecting, '导入失败');
      notifyListeners();
    }
  }

  /// 静音开关：静音时麦克风流继续跑但不再喂 VAD（恢复即时生效，无需重建流）。
  void toggleMute() {
    if (_hangUpRequested || _disposed) return;
    _muted = !_muted;
    notifyListeners();
  }

  /// 扬声器/听筒切换（仅 Android 生效；iOS 由系统音频会话管理）。
  Future<void> toggleSpeaker() async {
    if (_hangUpRequested || _disposed) return;
    _speakerOn = !_speakerOn;
    try {
      await _player.setSpeakerphone(_speakerOn);
    } catch (e) {
      debugPrint('[VoiceCall] 切换扬声器失败: $e');
    }
    notifyListeners();
  }

  /// 手动输入发送（不方便说话时，如环境嘈杂/NSFW 场景）：
  /// 文本入队，由回合循环按序处理（与语音段同一管线：AI→TTS→播放）。
  /// 若正处于聆听等待，会打断麦克风等待让循环立刻取文本。
  Future<void> sendText(String text) async {
    final t = text.trim();
    if (t.isEmpty || _hangUpRequested || _disposed) return;
    _pendingText.add(t);
    debugPrint('[VoiceCall] sendText 入队: "$t"');
    notifyListeners();
    // 打断聆听等待：取消订阅不会触发录音流的 onDone，若不显式完成
    // _listenDone，_runLoop 将永远卡在 done.future 上（文本无人消费 +
    // 后续回合全部失效）。
    final ld = _listenDone;
    if (ld != null && !ld.isCompleted) ld.complete(null);
    await _cancelMic();
    try {
      await _recorder.stop();
    } catch (_) {}
  }

  Future<void> hangUp() async {
    if (_hangUpRequested) return;
    _hangUpRequested = true;
    _setPhase(VoiceCallPhase.ended, '通话已结束');
    _completePendingListeners();
    await _cancelMic();
    try {
      await _recorder.stop();
    } catch (_) {}
    try {
      await _player.stop();
    } catch (_) {}
    await _finalizeCall();
  }

  @override
  void dispose() {
    _disposed = true;
    _hangUpRequested = true;
    _completePendingListeners();
    _cancelMic();
    final isub = _interruptSub;
    _interruptSub = null;
    isub?.cancel();
    _blocSub?.cancel();
    _blocSub = null;
    try {
      _recorder.dispose();
    } catch (_) {}
    try {
      _player.dispose();
    } catch (_) {}
    try {
      _vad.dispose();
    } catch (_) {}
    super.dispose();
  }

  void _completePendingListeners() {
    final ld = _listenDone;
    if (ld != null && !ld.isCompleted) ld.complete(null);
    final rd = _replyDone;
    if (rd != null && !rd.isCompleted) rd.complete('');
  }

  Future<void> _cancelMic() async {
    final sub = _micSub;
    _micSub = null;
    if (sub != null) {
      try {
        await sub.cancel();
      } catch (_) {}
    }
  }

  bool _safe() => !_disposed && !_hangUpRequested;

  // ───────────────────────────────────────────────────────────────────────────

  Future<void> _runLoop() async {
    while (_safe()) {
      try {
        // 手动输入的文本优先处理（跳过 VAD/STT，直接进回合管线）
        if (_pendingText.isNotEmpty) {
          final t = _pendingText.removeAt(0);
          _lastUserText = t;
          _lastAiText = '';
          notifyListeners();
          await _handleTurn(t);
          continue;
        }
        // 优先消费思考期捕获的语音段（修复「AI 思考时说话被丢弃」）
        final segment = _interruptQueue.isNotEmpty
            ? _interruptQueue.removeAt(0)
            : await _listenForSpeech();
        if (!_safe()) break;
        if (segment == null || segment.isEmpty) continue;

        _setPhase(VoiceCallPhase.thinking, '正在转写…');
        final text = await _transcribe(segment);
        if (!_safe()) break;
        if (text.trim().isEmpty) continue;
        _lastUserText = text.trim();
        _lastAiText = '';
        notifyListeners();

        await _handleTurn(_lastUserText);
      } catch (e) {
        debugPrint('[VoiceCall] 回合异常: $e');
        if (!_safe()) break;
        _lastError = '回合异常：$e';
        _setPhase(VoiceCallPhase.listening, '出了点小问题，重新听你说…');
        notifyListeners();
        await Future.delayed(const Duration(milliseconds: 600));
        if (!_safe()) break;
      }
    }
  }

  /// 开启麦克风流，喂 VAD，直到检测到一段完整语音（或挂断）。
  Future<Float32List?> _listenForSpeech() async {
    _lastError = null; // 新回合清除旧错误
    _aiStreamingText = '';
    _setPhase(VoiceCallPhase.listening, '我在听，说吧…');
    debugPrint('[VoiceCall] listen: reset VAD...');
    _vad.reset();
    debugPrint('[VoiceCall] listen: 打开麦克风流...');

    Stream<Uint8List> stream;
    try {
      stream = await _recorder.startStream();
      debugPrint('[VoiceCall] listen: 麦克风流已开启');
    } catch (e) {
      debugPrint('[VoiceCall] 打开麦克风失败: $e');
      _lastError = '无法打开麦克风：$e';
      _setPhase(VoiceCallPhase.ended, '无法打开麦克风');
      notifyListeners();
      return null;
    }
    if (!_safe()) {
      try {
        await _recorder.stop();
      } catch (_) {}
      return null;
    }

    final done = Completer<Float32List?>();
    _listenDone = done;
    _micSub = stream.listen(
      (chunk) {
        if (done.isCompleted) return;
        if (_muted) return; // 静音：不喂 VAD，段检测暂停
        final samples = _pcm16ToFloat32(chunk);
        _vad.acceptSamples(samples);
        final seg = _vad.takeSegment();
        if (seg != null && seg.isNotEmpty && !done.isCompleted) {
          debugPrint('[VoiceCall] listen: 检测到语音段 len=${seg.length}');
          done.complete(seg);
        }
      },
      onError: (Object e) {
        debugPrint('[VoiceCall] listen: 麦克风流错误: $e');
        _lastError = '麦克风流错误：$e';
        notifyListeners();
        if (!done.isCompleted) done.complete(null);
      },
      onDone: () {
        debugPrint('[VoiceCall] listen: 麦克风流结束');
        if (!done.isCompleted) done.complete(null);
      },
      cancelOnError: true,
    );

    final segment = await done.future;
    _listenDone = null;
    await _cancelMic();
    try {
      await _recorder.stop();
    } catch (_) {}
    return segment;
  }

  Future<String> _transcribe(Float32List samples) async {
    try {
      final result = await _stt.transcribeSamples(samples);
      return result.text;
    } catch (e) {
      debugPrint('[VoiceCall] 转写失败: $e');
      _lastError = '转写失败：$e';
      notifyListeners();
      return '';
    }
  }

    Future<void> _handleTurn(String userText) async {
    _setPhase(VoiceCallPhase.thinking, 'TA 正在想…');
    _recordTurn(userText, isUser: true);
    notifyListeners(); // 用户气泡立即上屏
    final aiText = await _awaitAiReply(userText);
    if (!_safe()) return;
    _recordTurn(aiText, isUser: false);
    _lastAiText = aiText.trim();
    notifyListeners();

    final speech = cleanSpokenText(aiText);
    if (speech.isEmpty) {
      _setPhase(VoiceCallPhase.listening, '（TA 没有回应，继续说吧）');
      await Future.delayed(const Duration(milliseconds: 500));
      return;
    }

    _setPhase(VoiceCallPhase.aiSpeaking, 'TA 正在说话…');
    await _speakSentences(_splitSentences(speech));
  }

  /// 记录通话回合内容（供挂断后的记忆提取与记录展示）。
  void _recordTurn(String text, {required bool isUser}) {
    final content = text.trim();
    if (content.isEmpty) return;
    _callTranscript.add(ChatMessage(
      id: const Uuid().v4(),
      chatId: session.id,
      senderId: isUser ? userId : 'ai_${session.aiCharacterId}',
      senderName: isUser ? '' : session.aiCharacterName,
      content: content,
      isUser: isUser,
      timestamp: DateTime.now(),
    ));
  }

  /// 挂断收尾（幂等）：写入通话记录消息 + 强制提取通话记忆。
  Future<void> _finalizeCall() async {
    if (_finalized || _disposed) return;
    _finalized = true;
    try {
      final durationSec = _callStartedAt == null
          ? 0
          : DateTime.now().difference(_callStartedAt!).inSeconds;
      final record = ChatMessage(
        id: const Uuid().v4(),
        chatId: session.id,
        senderId: 'system',
        senderName: '系统',
        isSystem: true,
        type: MessageType.system,
        content: _callRecordText(durationSec),
        timestamp: DateTime.now(),
        metadata: {
          'type': 'voice_call',
          'callDurationSec': durationSec,
          'initiatedBy': 'user',
          'aiName': session.aiCharacterName,
        },
      );
      // 通话内容静默化：抹掉通话期间写入的用户/AI 消息，聊天页只保留
      // 结束通话记录（语音通话 X分X秒）与时间；对话本身已在下方经
      // extractCallMemories 静默注入记忆库。
      if (_callStartedAt != null) {
        await chatBloc.clearCallMessages(
          chatId: session.id,
          since: _callStartedAt!,
        );
      }
      await chatBloc.appendSystemMessage(record);
      if (_callTranscript.isNotEmpty) {
        await chatBloc.extractCallMemories(
          chatId: session.id,
          recentMessages: List.of(_callTranscript),
        );
      }
    } catch (e) {
      debugPrint('[VoiceCall] 挂断收尾失败: $e');
    }
  }

  static String _callRecordText(int durationSec) {
    if (durationSec < 60) return '语音通话 $durationSec秒';
    final m = durationSec ~/ 60;
    final s = durationSec % 60;
    return s > 0 ? '语音通话 $m分$s秒' : '语音通话 $m分钟';
  }

  Future<String> _awaitAiReply(String userText) async {
    // 快照「发送前最后一条非用户消息」的 id：本轮回复必须是一条 id 不同的
    // 新消息。不能按「列表里最后一条 AI 消息」取内容——历史会话里永远有
    // 旧 AI 消息，发送后的第一帧 ChatMessagesLoaded（仅含旧历史+新用户
    // 消息）会把上一轮回复误当本轮结果，提前送去 TTS（表现为 AI 复读旧
    // 话/新回复无声）。流式文本只作超时/异常兜底，不单独触发完成。
    var lastAiId = '';
    final pre = chatBloc.state;
    if (pre is ChatMessagesLoaded) {
      for (final m in pre.messages.reversed) {
        if (m.isFromAI) {
          lastAiId = m.id;
          break;
        }
      }
    }
    debugPrint('[VoiceCall] awaitReply: 发送 user="$userText" 基线消息id=$lastAiId');

    final done = Completer<String>();
    _replyDone = done;
    final sb = StringBuffer();

    _blocSub = chatBloc.stream.listen((state) {
      if (_hangUpRequested || _disposed) return;
      if (state is ChatAIStreaming) {
        sb
          ..clear()
          ..write(state.streamingText);
        _aiStreamingText = state.streamingText;
        notifyListeners(); // 打字机字幕逐帧刷新
      } else if (state is ChatMessagesLoaded) {
        String? newId;
        String? text;
        for (final m in state.messages.reversed) {
          if (!m.isFromAI) continue;
          if (m.id == lastAiId) break; // 最新的非用户消息仍是旧的 → 还没生成
          newId = m.id;
          text = m.content;
          break;
        }
        if (newId == null) return; // 只认新消息，流式中途帧不算完成
        final result = (text != null && text.trim().isNotEmpty)
            ? text.trim()
            : sb.toString().trim();
        if (!done.isCompleted) {
          debugPrint(
              '[VoiceCall] awaitReply: 完成 id=$newId len=${result.length} text="$result"');
          done.complete(result);
        }
      } else if (state is ChatError || state is ChatBlockedByAI) {
        if (!done.isCompleted) {
          debugPrint('[VoiceCall] awaitReply: 异常状态($state)，流式文本兜底 len=${sb.length}');
          done.complete(sb.toString());
        }
      }
    });

    // 语音通话强制精简，不让模型输出整段小说旁白。
    chatBloc.add(ChatSendMessage(
      chatId: session.id,
      userId: userId,
      content: userText,
      forceConcise: true,
    ));

    // AI 思考期（回复等待窗，最长 120s）麦克风保持开启：用户此时说的话
    // 不再丢失，经 VAD 断句后入 _interruptQueue，由 _runLoop 按序处理。
    // 不打断当前回复（ChatBloc 串行处理事件，旧 LLM 调用无法提前终止），
    // 只保证语音被捕获——彻底消除「必须二次开口」。
    // 放音阶段（_speakSentences）不监听：AI 自身声音会经麦克风触发 VAD
    // 形成回声自打断，故只覆盖思考期（此刻无人发声，无回声风险）。
    await _startInterruptListening();

    final result = await done.future.timeout(
      const Duration(seconds: 120),
      onTimeout: () {
        _lastError = 'AI 回复超时（120s），已跳过本轮';
        notifyListeners();
        return sb.toString();
      },
    );
    await _stopInterruptListening();
    if (_interruptQueue.isNotEmpty) {
      debugPrint('[VoiceCall] 思考期共捕获 ${_interruptQueue.length} 段语音，转入下轮处理');
      notifyListeners();
    }
    _replyDone = null;
    _aiStreamingText = ''; // 打字机收尾，完整文本由气泡接手
    await _blocSub?.cancel();
    _blocSub = null;
    return result;
  }

  /// 开启思考期后台监听：麦克风+VAD 照常运行，语音段入 [_interruptQueue]。
  Future<void> _startInterruptListening() async {
    if (_disposed || _hangUpRequested || _interruptSub != null) return;
    Stream<Uint8List> stream;
    try {
      stream = await _recorder.startStream();
    } catch (e) {
      debugPrint('[VoiceCall] 思考期监听开启失败: $e');
      return;
    }
    _interruptSub = stream.listen(
      (chunk) {
        if (_muted) return; // 静音同样生效
        _vad.acceptSamples(_pcm16ToFloat32(chunk));
        final seg = _vad.takeSegment();
        if (seg != null && seg.isNotEmpty) {
          _interruptQueue.add(seg);
          debugPrint(
              '[VoiceCall] 思考期捕获语音段 len=${seg.length} 队列=${_interruptQueue.length}');
          notifyListeners();
        }
      },
      onError: (Object e) {
        debugPrint('[VoiceCall] 思考期监听错误: $e');
        _lastError = '麦克风流错误：$e';
        notifyListeners();
      },
      onDone: () => debugPrint('[VoiceCall] 思考期监听结束'),
      cancelOnError: true,
    );
    debugPrint('[VoiceCall] 思考期监听已开启');
  }

  /// 关闭思考期监听（幂等；与挂断共用停止路径）。
  Future<void> _stopInterruptListening() async {
    final sub = _interruptSub;
    _interruptSub = null;
    if (sub != null) {
      try {
        await sub.cancel();
      } catch (_) {}
    }
    try {
      await _recorder.stop();
    } catch (_) {}
  }

  /// 逐句合成 + 流水线播放：合成下一句的同时播当前句。
  ///
  /// 退路设计：单句合成失败（如 MiMo 400）只跳过该句并继续后面的句子，
  /// 不终止整轮播放；全部失败时经 [lastError] 暴露给 UI。
  Future<void> _speakSentences(List<String> sentences) async {
    if (sentences.isEmpty) return;
    final controller = StreamController<String>();
    var okCount = 0;
    var failCount = 0;

    final producer = () async {
      try {
        for (var i = 0; i < sentences.length; i++) {
          if (!_safe()) break;
          final s = sentences[i];
          debugPrint(
              '[VoiceCall] TTS 合成 (${i + 1}/${sentences.length}) len=${s.length} text="$s"');
          try {
            final r = await _tts.synthesizeWithStyle(
              session.aiCharacterId,
              s,
              style: _directorFor(s),
            );
            okCount++;
            if (!_safe()) break;
            if (!controller.isClosed) controller.add(r.audioFilePath);
          } catch (e) {
            failCount++;
            debugPrint(
                '[VoiceCall] 单句合成失败 (${i + 1}/${sentences.length}) text="$s" error=$e');
            _lastError = '语音合成失败：$e';
            notifyListeners();
          }
        }
      } finally {
        if (!controller.isClosed) await controller.close();
      }
    }();

    final consumer = () async {
      try {
        await for (final path in controller.stream) {
          if (!_safe()) break;
          await _player.playAndWait(path);
          if (!_safe()) break;
        }
      } catch (e) {
        debugPrint('[VoiceCall] 播放失败: $e');
      }
    }();

    await Future.wait([producer, consumer]);
    debugPrint('[VoiceCall] TTS 收尾: 成功 $okCount 句 / 失败 $failCount 句');
  }

  /// 为当前台词生成导演指令（角色人设 + 台词场景）。
  String _directorFor(String sentence) {
    // 通话场景下不额外查库：用会话已有信息 + 台词生成轻量指令。
    return '场景：正在与最亲密的人进行语音通话。\n'
        '指导：语气自然亲切，像日常聊天一样说出台词："$sentence"；'
        '语速适中，情绪贴合台词内容。';
  }

  // ───────────────────────────────────────────────────────────────────────────

  Future<bool> _allModelsReady() async {
    for (final k in VoiceModelKind.values) {
      if (!await VoiceModelManager.instance.isReady(k)) return false;
    }
    return true;
  }

  Future<void> _beginAfterModels() async {
    _needsModels = false;
    debugPrint('[VoiceCall] init: 解析参考音色...');
    await _setupVoiceProfile();
    if (!_safe()) return;
    debugPrint('[VoiceCall] init: 音色就绪，初始化 VAD...');
    await _vad.init();
    if (!_safe()) return;
    debugPrint('[VoiceCall] init: VAD 就绪，启动监听循环');
    unawaited(_runLoop());
  }

  Future<void> _setupVoiceProfile() async {
    // 角色选了内置预置音色：无需参考音频，synthesizeWithStyle 会自动走
    // mimo-v2.5-tts + Voice ID；跳过 setReferenceAudio。
    final store = VoiceProfileStore.instance;
    final preset = await store.loadPreset(session.aiCharacterId);
    if (!_safe()) return;
    if (preset != null) {
      debugPrint('[VoiceCall] 音色: 使用预置音色 $preset');
      return;
    }
    final ref = await _resolveVoiceReference();
    if (!_safe()) return;
    if (ref == null) {
      throw StateError('未找到角色参考音色');
    }
    await _tts.setReferenceAudio(session.aiCharacterId, ref.path, ref.text);
  }

  /// 解析角色参考音色：优先角色自定义音色（损坏自动跳过），否则用默认音色。
  Future<({String path, String text})?> _resolveVoiceReference() async {
    try {
      final store = VoiceProfileStore.instance;
      final custom = await store.loadCustom(session.aiCharacterId);
      if (custom != null) {
        debugPrint('[VoiceCall] 音色: 使用角色自定义 ${custom.path}');
        return custom;
      }
      debugPrint('[VoiceCall] 音色: 无自定义（或已损坏），回退默认音色');
      return await store.loadDefault();
    } catch (e) {
      debugPrint('[VoiceCall] 解析参考音色失败: $e');
      return null;
    }
  }

  // ───────────────────────────────────────────────────────────────────────────

  /// PCM16 little-endian → Float32 (-1..1)。
  static Float32List _pcm16ToFloat32(Uint8List bytes) {
    final n = bytes.length ~/ 2;
    final out = Float32List(n);
    final data = ByteData.sublistView(bytes);
    for (int i = 0; i < n; i++) {
      out[i] = data.getInt16(i * 2, Endian.little) / 32768.0;
    }
    return out;
  }

    /// 去掉旁白括号/残留标签/markdown/emoji，得到「念出来」的台词。
  /// MiMo 会把 `（风格）[内联标签]` 解析成音频指令，括号、markdown 符号
  /// 或 emoji 混进台词可能直接触发 400 Param Incorrect，必须清干净。
  /// 对外暴露：字幕气泡/打字机显示同一份「纯对话」文本（小说模式旁白剔除）。
  static String cleanSpokenText(String text) {
    var t = MessageSanitizer.extractSpokenText(text);
    t = t.replaceAll(RegExp(r'（[^（）]*）'), ' ');
    t = t.replaceAll(RegExp(r'\([^()]*\)'), ' ');
    t = t.replaceAll(RegExp(r'【[^【】]*】'), ' ');
    t = t.replaceAll(RegExp(r'\[[^\[\]]*\]'), ' ');
    t = t.replaceAll(RegExp(r'<[^>]*>'), ' ');
    // markdown 强调/引用装饰符
    t = t.replaceAll(RegExp(r'[*#~`>_]+'), ' ');
    // emoji、变体选择符、零宽字符（不可朗读，且可能触发参数错误）
    t = t.replaceAll(
      RegExp(
        '[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{2B00}-\u{2BFF}'
        '\u{FE0F}\u{200B}-\u{200F}\u{FEFF}]',
        unicode: true,
      ),
      ' ',
    );
    return t.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// 按句末标点切句（供逐句合成）。切完去掉句首残留的逗号/冒号等
  /// （引号旁白剥除后常留下「，怎么了」这种句首逗号，影响 TTS 断句）。
  static List<String> _splitSentences(String text) {
    final sentences = <String>[];
    final buffer = StringBuffer();
    for (final ch in text.split('')) {
      buffer.write(ch);
      if ('。！？!?；;\n'.contains(ch)) {
        final s = _trimSentence(buffer.toString());
        if (s.isNotEmpty) sentences.add(s);
        buffer.clear();
      }
    }
    final tail = _trimSentence(buffer.toString());
    if (tail.isNotEmpty) sentences.add(tail);
    return sentences;
  }

  static String _trimSentence(String s) =>
      s.trim().replaceAll(RegExp(r'^[，、,；;：:\s]+'), '').trim();

  void _setPhase(VoiceCallPhase phase, String status) {
    if (_disposed) return;
    _phase = phase;
    _statusText = status;
    notifyListeners();
  }
}