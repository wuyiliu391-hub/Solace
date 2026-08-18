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
  DateTime? _callStartedAt;

  /// 通话内逐回合记录（用户/AI 消息），挂断后用于记忆提取与记录展示。
  final List<ChatMessage> _callTranscript = [];
  StreamSubscription<Uint8List>? _micSub;
  StreamSubscription<ChatState>? _blocSub;
  Completer<Float32List?>? _listenDone;
  Completer<String>? _replyDone;

  VoiceCallPhase get phase => _phase;
  String get statusText => _statusText;
  String get lastUserText => _lastUserText;
  String get lastAiText => _lastAiText;
  bool get isEnded => _phase == VoiceCallPhase.ended;
  bool get needsModels => _needsModels;

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
      _setPhase(VoiceCallPhase.ended, '初始化失败：$e');
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
      _setPhase(VoiceCallPhase.connecting, '导入失败：$e');
    }
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
        final segment = await _listenForSpeech();
        if (!_safe()) break;
        if (segment == null || segment.isEmpty) continue;

        _setPhase(VoiceCallPhase.thinking, '正在听你说…');
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
        _setPhase(VoiceCallPhase.listening, '出了点小问题，重新听你说…');
        await Future.delayed(const Duration(milliseconds: 600));
        if (!_safe()) break;
      }
    }
  }

  /// 开启麦克风流，喂 VAD，直到检测到一段完整语音（或挂断）。
  Future<Float32List?> _listenForSpeech() async {
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
      _setPhase(VoiceCallPhase.ended, '无法打开麦克风：$e');
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
      return '';
    }
  }

  Future<void> _handleTurn(String userText) async {
    _setPhase(VoiceCallPhase.thinking, 'TA 正在想…');
    _recordTurn(userText, isUser: true);
    final aiText = await _awaitAiReply(userText);
    if (!_safe()) return;
    _recordTurn(aiText, isUser: false);
    _lastAiText = aiText.trim();
    notifyListeners();

    final speech = _speechClean(aiText);
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
    if (durationSec < 60) return '语音通话 ${durationSec}秒';
    final m = durationSec ~/ 60;
    final s = durationSec % 60;
    return s > 0 ? '语音通话 $m分$s秒' : '语音通话 $m分钟';
  }

  Future<String> _awaitAiReply(String userText) async {
    final done = Completer<String>();
    _replyDone = done;
    final sb = StringBuffer();

    _blocSub = chatBloc.stream.listen((state) {
      if (_hangUpRequested || _disposed) return;
      if (state is ChatAIStreaming) {
        sb
          ..clear()
          ..write(state.streamingText);
      } else if (state is ChatMessagesLoaded) {
        String? text;
        for (final m in state.messages.reversed) {
          if (m.isFromAI) {
            text = m.content;
            break;
          }
        }
        final result = (text ?? sb.toString()).trim();
        if (!done.isCompleted) done.complete(result);
      } else if (state is ChatError || state is ChatBlockedByAI) {
        if (!done.isCompleted) done.complete(sb.toString());
      }
    });

    // 语音通话强制精简，不让模型输出整段小说旁白。
    chatBloc.add(ChatSendMessage(
      chatId: session.id,
      userId: userId,
      content: userText,
      forceConcise: true,
    ));

    final result = await done.future.timeout(
      const Duration(seconds: 180),
      onTimeout: () => sb.toString(),
    );
    _replyDone = null;
    await _blocSub?.cancel();
    _blocSub = null;
    return result;
  }

  /// 逐句合成 + 流水线播放：合成下一句的同时播当前句。
  Future<void> _speakSentences(List<String> sentences) async {
    if (sentences.isEmpty) return;
    final controller = StreamController<String>();

    final producer = () async {
      try {
        for (final s in sentences) {
          if (!_safe()) break;
          final r = await _tts.synthesizeWithStyle(
            session.aiCharacterId,
            s,
            style: _directorFor(s),
          );
          if (!_safe()) break;
          if (!controller.isClosed) controller.add(r.audioFilePath);
        }
      } catch (e) {
        debugPrint('[VoiceCall] 合成失败: $e');
        if (!controller.isClosed) controller.addError(e);
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
      } catch (_) {}
    }();

    await Future.wait([producer, consumer]);
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
    final ref = await _resolveVoiceReference();
    if (!_safe()) return;
    if (ref == null) {
      throw StateError('未找到角色参考音色');
    }
    await _tts.setReferenceAudio(session.aiCharacterId, ref.path, ref.text);
  }

  /// 解析角色参考音色：优先角色自定义音色，否则用打包的默认音色。
  Future<({String path, String text})?> _resolveVoiceReference() async {
    try {
      final store = VoiceProfileStore.instance;
      final custom = await store.loadCustom(session.aiCharacterId);
      if (custom != null) return custom;
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

  /// 去掉旁白括号/残留标签，得到「念出来」的台词。
  static String _speechClean(String text) {
    var t = MessageSanitizer.extractSpokenText(text);
    t = t.replaceAll(RegExp(r'（[^（）]*）'), ' ');
    t = t.replaceAll(RegExp(r'\([^()]*\)'), ' ');
    t = t.replaceAll(RegExp(r'<[^>]*>'), ' ');
    return t.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// 按句末标点切句（供逐句合成）。
  static List<String> _splitSentences(String text) {
    final sentences = <String>[];
    final buffer = StringBuffer();
    for (final ch in text.split('')) {
      buffer.write(ch);
      if ('。！？!?；;\n'.contains(ch)) {
        final s = buffer.toString().trim();
        if (s.isNotEmpty) sentences.add(s);
        buffer.clear();
      }
    }
    final tail = buffer.toString().trim();
    if (tail.isNotEmpty) sentences.add(tail);
    return sentences;
  }

  void _setPhase(VoiceCallPhase phase, String status) {
    if (_disposed) return;
    _phase = phase;
    _statusText = status;
    notifyListeners();
  }
}
