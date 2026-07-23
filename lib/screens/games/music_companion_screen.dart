import 'dart:async';
import 'dart:math';
import 'dart:io' show Directory, File;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import '../../utils/avatar_resolver.dart';
import '../../services/music_playback_service.dart';
import '../../services/lyrics_service.dart';
import '../../services/id3_parser.dart';
import '../../models/music_track.dart';
import '../../models/ai_character.dart';
import '../../models/chat_session.dart';
import '../../models/chat_message.dart';
import '../../repositories/local_storage_repository.dart';
import '../../services/ai_service.dart';
import '../../blocs/chat/chat_bloc.dart';

/// 音乐共情模式 — 网易云风格黑胶播放 + 滚动歌词 + AI 共情聊天
class MusicCompanionScreen extends StatefulWidget {
  const MusicCompanionScreen({super.key});

  @override
  State<MusicCompanionScreen> createState() => _MusicCompanionScreenState();
}

class _MusicCompanionScreenState extends State<MusicCompanionScreen>
    with TickerProviderStateMixin {
  final _playback = MusicPlaybackService.instance;
  final _lyricsService = LyricsService.instance;
  final _lyricScrollController = ScrollController();

  // ── 页面状态 ──
  bool _showVinyl = true;

  // ── 播放状态 ──
  MusicPlaybackState _playState = MusicPlaybackState.idle;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  int _currentLyricIndex = -1;

  MusicTrack? _track;
  String? _localFilePath;
  String _statusText = '';
  bool _isProcessing = false;
  bool _isLiked = false;

  List<LyricLine> _lyricLines = [];

  // ── 聊天 ──
  late LocalStorageRepository _storage;
  late AIService _aiService;
  ChatBloc? _chatBloc;
  ChatSession? _chatSession;
  AICharacter? _character;
  final _msgController = TextEditingController();
  final _chatScrollController = ScrollController();
  final List<ChatMessage> _messages = [];

  // 输入栏状态
  bool _inputFocused = false;
  final _inputFocusNode = FocusNode();

  // 头像下方浮层气泡（网易云一起听：贴双头像下，渐隐递进）
  final List<_FloatBubble> _floatBubbles = [];
  static const int _maxFloatBubbles = 4;
  static const Duration _bubbleLife = Duration(seconds: 5);

  // ── 动画 ──
  late AnimationController _vinylCtrl;
  late Animation<double> _vinylRotation;

  // ── 唱片封面 ──
  ui.Image? _coverImage;
  bool _coverLoading = false;

  @override
  void initState() {
    super.initState();
    _vinylCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    );
    _vinylRotation = Tween<double>(begin: 0, end: 2 * pi).animate(_vinylCtrl)
      ..addListener(() => setState(() {}));

    _playback.stateStream.listen((s) {
      if (!mounted) return;
      setState(() => _playState = s);
      if (s == MusicPlaybackState.playing) {
        _vinylCtrl.repeat();
      } else {
        _vinylCtrl.stop();
      }
    });
    _playback.positionStream.listen((p) {
      if (!mounted) return;
      final idx = _track?.getLyricIndex(p) ?? -1;
      setState(() {
        _position = p;
        if (idx != _currentLyricIndex) {
          _currentLyricIndex = idx;
          _scrollToCurrentLyric();
          _onLyricChanged(idx);
        }
      });
    });
    _playback.durationStream.listen((d) {
      if (mounted) setState(() => _duration = d);
    });

    _storage = RepositoryProvider.of<LocalStorageRepository>(context);
    _aiService = AIService(_storage);

    _inputFocusNode.addListener(() {
      setState(() => _inputFocused = _inputFocusNode.hasFocus);
    });
  }

  @override
  void dispose() {
    for (final b in _floatBubbles) {
      b.timer?.cancel();
    }
    _inputFocusNode.dispose();
    _vinylCtrl.dispose();
    _lyricScrollController.dispose();
    _chatScrollController.dispose();
    _msgController.dispose();
    _playback.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════
  // 核心流程：选文件 → ID3 解析 → LRCLib 匹配歌词 → 播放
  // ═══════════════════════════════════════════════════════

  Future<void> _pickAndPlay() async {
    if (_character == null) {
      _setStatus('请先选择一起听歌的角色');
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;

    final filePath = result.files.single.path;
    if (filePath == null) return;
    final fileName = result.files.single.name;

    setState(() {
      _isProcessing = true;
      _statusText = '正在读取歌曲信息…';
      _track = null;
      _lyricLines = [];
      _currentLyricIndex = -1;
    });

    // Step 1: 从文件读取 ID3 标签
    final id3 = await Id3Parser.fromFile(filePath);
    if (!mounted) return;
    String title = id3.title ?? '';
    String artist = id3.artist ?? '';

    // 如果 ID3 没读到，尝试从文件名解析
    if (title.isEmpty) {
      final fileId3 = Id3Parser.fromFileName(fileName);
      title = fileId3.title ?? '';
      artist = fileId3.artist ?? '';
    }

    // 如果还是拿不到有意义的歌名，让用户手动输入
    if (title.isEmpty || _isGenericName(title)) {
      final manual = await _showManualSongInput();
      if (!mounted) return;
      if (manual == null) {
        setState(() => _isProcessing = false);
        return;
      }
      title = manual.title;
      artist = manual.artist;
    }

    setState(() => _statusText = '正在匹配歌词: $title${artist.isNotEmpty ? ' — $artist' : ''}');

    // Step 2: 用 ID3 信息去 LRCLib 匹配歌词
    MusicTrack? matched;
    if (artist.isNotEmpty) {
      matched = await _lyricsService.getLyrics(artist, title);
    }
    if (!mounted) return;
    if (matched == null) {
      // 搜歌名
      final results = await _lyricsService.search(title, limit: 5);
      if (!mounted) return;
      if (results.isNotEmpty) matched = results.first;
    }

    if (matched == null) {
      setState(() {
        _isProcessing = false;
        _statusText = '未找到歌词，将使用纯音乐模式';
      });
    } else {
      final m = matched!;
      setState(() {
        _track = m;
        _lyricLines = m.parsedSyncedLyrics.isEmpty
            ? m.plainLyricLines
            : m.parsedSyncedLyrics;
        _isProcessing = false;
        _statusText = '';
        _localFilePath = filePath;
      });
    }

    // Step 3: 播放 + 发送上下文
    await _playback.play(filePath, title: title, artist: artist);
    if (!mounted) return;
    _sendSystemContext();

    // Step 4: 加载已保存的封面图片
    await _loadSavedCoverImage();
  }

  /// 判断歌名是否为无意义的通用名称（如 "01", "track1", "audio" 等）
  bool _isGenericName(String name) {
    final trimmed = name.trim().toLowerCase();
    final genericPatterns = [
      RegExp(r'^(track|audio|song|music)[\s_-]*\d*$'),
      RegExp(r'^\d+$'),
      RegExp(r'^unknown'),
      RegExp(r'^(untitled|无标题)$'),
      RegExp(r'^record(ing)?[\s_-]*\d*$'),
      RegExp(r'^(voice|vocals?)[\s_-]*\d*$'),
      RegExp(r'^new_record(ing)?'),
    ];
    return genericPatterns.any((p) => p.hasMatch(trimmed));
  }

  /// 弹出手动输入歌名对话框
  Future<({String title, String artist})?> _showManualSongInput({String hint = '请输入歌曲信息以便匹配歌词'}) async {
    final titleCtrl = TextEditingController();
    final artistCtrl = TextEditingController();

    final result = await showDialog<({String title, String artist})>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('搜索歌曲歌词'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(hint, style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 16),
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(
                  labelText: '歌名',
                  hintText: '例如：我怀念的',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                textInputAction: TextInputAction.next,
                autofocus: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: artistCtrl,
                decoration: const InputDecoration(
                  labelText: '歌手 (选填)',
                  hintText: '例如：孙燕姿',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => Navigator.of(ctx).pop(
                  (title: titleCtrl.text.trim(), artist: artistCtrl.text.trim()),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                if (titleCtrl.text.trim().isEmpty) return;
                Navigator.of(ctx).pop(
                  (title: titleCtrl.text.trim(), artist: artistCtrl.text.trim()),
                );
              },
              child: const Text('搜索'),
            ),
          ],
        );
      },
    );

    // 延迟处置：对话框关闭时其内部动画（AnimatedDefaultTextStyle）仍持有
    // controller 引用，立即 dispose 会导致 _dependents.isEmpty 断言失败
    WidgetsBinding.instance.addPostFrameCallback((_) {
      titleCtrl.dispose();
      artistCtrl.dispose();
    });
    return result;
  }

  void _setStatus(String text) {
    setState(() => _statusText = text);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted && _statusText == text) setState(() => _statusText = '');
    });
  }

  /// 在线搜索歌词：用户直接输入歌名 → 调用 LRCLib 获取歌词
  Future<void> _searchOnlineLyrics() async {
    if (_character == null) {
      _setStatus('请先选择一起听歌的角色');
      return;
    }

    final manual = await _showManualSongInput(
      hint: '输入歌名，自动从 LRCLib 匹配歌词',
    );
    if (!mounted) return;
    if (manual == null) return;

    final title = manual.title;
    final artist = manual.artist;

    setState(() {
      _isProcessing = true;
      _statusText = '正在搜索歌词: $title${artist.isNotEmpty ? ' — $artist' : ''}';
      _track = null;
      _lyricLines = [];
      _currentLyricIndex = -1;
    });

    // 先尝试精确匹配（歌手+歌名）
    MusicTrack? matched;
    if (artist.isNotEmpty) {
      matched = await _lyricsService.getLyrics(artist, title);
    }
    if (!mounted) return;

    // 精确匹配失败 → 模糊搜索，让用户选
    if (matched == null) {
      final results = await _lyricsService.search(title, limit: 8);
      if (!mounted) return;
      if (results.isEmpty) {
        setState(() {
          _isProcessing = false;
          _statusText = '未找到匹配的歌词';
        });
        return;
      }

      final cs = Theme.of(context).colorScheme;
      final tt = Theme.of(context).textTheme;
      final selected = await showModalBottomSheet<MusicTrack>(
        context: context,
        isScrollControlled: true,
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
        builder: (_) => _SearchResultSheet(results: results, colorScheme: cs, textTheme: tt),
      );

      if (!mounted) return;
      if (selected == null) {
        setState(() => _isProcessing = false);
        return;
      }
      matched = selected;
    }

    final m = matched!;

    // 如果有同步歌词，从 API 重新获取完整数据（搜索结果可能不含 syncedLyrics）
    if (m.syncedLyrics == null && m.id != 0) {
      final full = await _lyricsService.getById(m.id);
      if (!mounted) return;
      if (full != null) matched = full;
    }

    final finalTrack = matched;
    if (finalTrack == null) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _statusText = '未找到完整的歌词信息';
        });
      }
      return;
    }
    setState(() {
      _track = finalTrack;
      _lyricLines = finalTrack.parsedSyncedLyrics.isEmpty
          ? finalTrack.plainLyricLines
          : finalTrack.parsedSyncedLyrics;
      _isProcessing = false;
      _statusText = '';
      _localFilePath = null; // 在线搜索无本地文件
    });

    _sendSystemContext();
  }

  // ═══════════════════════════════════════════════════════
  // 角色选择
  // ═══════════════════════════════════════════════════════

  Future<void> _pickCharacter() async {
    final characters = await _storage.getAllAICharacters();
    final visible = characters.where((c) => !c.isHidden).toList();
    if (!mounted) return;

    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final selected = await showModalBottomSheet<AICharacter>(
      context: context,
      isScrollControlled: true,
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
      builder: (_) => _CharacterPickerSheet(characters: visible, colorScheme: cs, textTheme: tt),
    );
    if (selected == null) return;

    setState(() => _character = selected);

    final existingSessions = await _storage.getChatSessionsByCharacterId(selected.id);
    if (existingSessions.isNotEmpty) {
      _chatSession = existingSessions.first;
    } else {
      _chatSession = ChatSession(
        id: 'music_${selected.id}_${DateTime.now().millisecondsSinceEpoch}',
        aiCharacterId: selected.id,
        userId: 'user',
        aiCharacterName: selected.name,
        createdAt: DateTime.now(),
      );
      await _storage.saveChatSession(_chatSession!);
    }

    _chatBloc = ChatBloc(_storage, _aiService);
    if (mounted) setState(() {});
  }

  void _sendSystemContext() {
    if (_track == null || _character == null || _chatBloc == null) return;

    final contextStr = _buildMusicContext();
    _chatBloc!.musicContext = contextStr;

    _addChatMessage(ChatMessage(
      id: 'sys_ctx_${DateTime.now().millisecondsSinceEpoch}',
      chatId: _chatSession!.id,
      senderId: 'system',
      senderName: '系统',
      content: '\u{1f3b5} 你们开始了共享听歌体验…',
      type: MessageType.system,
      status: MessageStatus.sent,
      createdAt: DateTime.now(),
    ));

    _sendAIShortReply(
      '你们刚开始听「${_track!.name}」。用一句短台词分享此刻心情，不要超过一句。',
    );
  }

  String _buildMusicContext() {
    final t = _track!;
    final buf = StringBuffer();
    buf.writeln('【音乐共情模式 - 正在共享听歌】');
    buf.writeln('歌曲：${t.name}');
    buf.writeln('歌手：${t.artistName}');
    if (t.albumName != null && t.albumName!.isNotEmpty) {
      buf.writeln('专辑：${t.albumName}');
    }
    buf.writeln();
    buf.writeln('这是你们正在一起听的歌。用户和你（角色）戴着同一副耳机，你也在听着旋律。');
    buf.writeln('你需要：');
    buf.writeln('1. 读懂这首歌的歌词含义和情感');
    buf.writeln('2. 结合你自己的角色背景和性格，分享你对这首歌的真实感受');
    buf.writeln('3. 找到歌词中与你们关系/经历产生共鸣的点，自然地提起');
    buf.writeln('4. 用你正常聊天的语气，不要写成乐评或分析报告');
    buf.writeln('5. 对用户当前在听歌时的情绪保持敏锐，适时关心或共鸣');
    buf.writeln();
    buf.writeln('=== 歌词 ===');
    buf.writeln(t.plainLyrics ?? t.syncedLyrics ?? '(纯音乐)');
    return buf.toString();
  }

  // ═══════════════════════════════════════════════════════
  // 歌词切换时 AI 评论
  // ═══════════════════════════════════════════════════════

  String? _lastCommentedLine;
  int _commentedOnIndex = -1;

  void _onLyricChanged(int idx) {
    if (idx < 0 || idx >= _lyricLines.length) return;
    if (idx == _commentedOnIndex) return;
    final line = _lyricLines[idx].text;
    if (line == _lastCommentedLine) return;

    _commentedOnIndex = idx;
    _lastCommentedLine = line;

    final currentBlock = _getLyricBlockAround(idx);
    final prompt = '你正在和用户一起戴着耳机听「${_track!.name}」。'
        '刚才播到了 "${currentBlock.length > 30 ? currentBlock.substring(0, 30) : currentBlock}"。'
        '请用一句短台词分享你的瞬间感受——保持自然，像真人聊天一样。';
    _sendAIShortReply(prompt);
  }

  String _getLyricBlockAround(int idx) {
    final lines = _lyricLines;
    final start = (idx - 1).clamp(0, lines.length - 1);
    final end = (idx + 1).clamp(0, lines.length - 1);
    final texts = <String>[];
    for (int i = start; i <= end; i++) {
      texts.add(lines[i].text);
    }
    return texts.join(' / ');
  }

  void _scrollToCurrentLyric() {
    if (!_lyricScrollController.hasClients) return;
    final idx = _currentLyricIndex;
    if (idx < 0) return;
    final itemHeight = 56.0;
    final offset = idx * itemHeight - 150;
    _lyricScrollController.animateTo(
      offset.clamp(0.0, _lyricScrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  // ═══════════════════════════════════════════════════════
  // 聊天
  // ═══════════════════════════════════════════════════════

  void _addChatMessage(ChatMessage msg) {
    setState(() => _messages.add(msg));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScrollController.hasClients) {
        _chatScrollController.animateTo(
          _chatScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });

    if (msg.type == MessageType.system) return;
    if (msg.isUser || msg.senderId == 'user') {
      _pushFloatBubble(msg.content, isUser: true);
    } else {
      _pushFloatBubble(msg.content, isUser: false);
    }
  }

  void _pushFloatBubble(String text, {required bool isUser}) {
    final clean = text.trim();
    if (clean.isEmpty) return;
    final id = '${DateTime.now().microsecondsSinceEpoch}_$isUser';
    final bubble = _FloatBubble(id: id, text: clean, isUser: isUser);
    bubble.timer = Timer(_bubbleLife, () {
      if (!mounted) return;
      setState(() {
        final i = _floatBubbles.indexWhere((b) => b.id == id);
        if (i >= 0) _floatBubbles[i].fading = true;
      });
      Timer(const Duration(milliseconds: 420), () {
        if (!mounted) return;
        setState(() => _floatBubbles.removeWhere((b) => b.id == id));
      });
    });
    setState(() {
      _floatBubbles.add(bubble);
      while (_floatBubbles.length > _maxFloatBubbles) {
        final old = _floatBubbles.removeAt(0);
        old.timer?.cancel();
      }
    });
  }

  Future<void> _sendAIShortReply(String prompt) async {
    if (_character == null || _chatBloc == null) return;

    final String reply;
    try {
      reply = await _aiService.sendMessage(
        character: _character!,
        userId: 'user',
        userMessage: prompt,
        chatHistory: [],
        memories: [],
        intimacyLevel: _chatSession?.intimacyLevel ?? 0,
        internalSystemContext: _buildMusicContext(),
      );
    } catch (e) {
      debugPrint('[MusicCompanion] AI sendMessage error: $e');
      return;
    }

    if (!mounted || reply.trim().isEmpty) return;

    // 按句号/感叹号/问号拆分为独立短句
    final sentences = reply
        .split(RegExp(r'(?<=[。！？!\?])'))
        .where((s) => s.trim().isNotEmpty)
        .take(2) // 最多 2 条
        .toList();

    for (var i = 0; i < sentences.length; i++) {
      if (!mounted) return;
      // 每条间隔随机 0.8~2.2s
      if (i > 0) {
        await Future.delayed(
          Duration(milliseconds: 800 + (Random().nextDouble() * 1400).toInt()),
        );
      }
      if (!mounted) return;
      final now = DateTime.now();
      _addChatMessage(ChatMessage(
        id: 'ai_${now.millisecondsSinceEpoch}_$i',
        chatId: _chatSession!.id,
        senderId: _character!.id,
        senderName: _character!.name,
        content: sentences[i].trim(),
        type: MessageType.text,
        status: MessageStatus.sent,
        createdAt: now,
      ));
    }
  }

  Future<void> _sendUserMessage(String text) async {
    if (text.trim().isEmpty) return;
    final msg = text.trim();
    _msgController.clear();

    final now = DateTime.now();
    _addChatMessage(ChatMessage(
      id: 'user_${now.millisecondsSinceEpoch}',
      chatId: _chatSession!.id,
      senderId: 'user',
      content: msg,
      type: MessageType.text,
      status: MessageStatus.sent,
      createdAt: now,
      isUser: true,
    ));

    _sendAIShortReply(msg);
  }

  // ═══════════════════════════════════════════════════════
  // UI
  // ═══════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    if (_track == null) {
      return Scaffold(
        backgroundColor: cs.surface,
        body: _buildPickerView(cs, tt),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 背景：深色渐变（无封面时）
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF1a1a2e), Color(0xFF16213e), Color(0xFF0f0f1a)],
              ),
            ),
          ),
          // 主内容
          Column(
            children: [
              // 顶部栏（后退 + 歌曲标题 + 循环按钮）
              _buildTopBar(cs, tt),
              // 【一起听头像联动模块】- 歌名下方，唱片上方，透明无卡片背景
              _buildTogetherHeader(),
              // 唱片/歌词切换（点击切换）
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: _showVinyl
                      ? _buildVinylPage(cs, tt)
                      : _buildLyricPage(cs, tt),
                ),
              ),
              // 底部控制区
              _buildBottomControls(cs, tt),
            ],
          ),
        ],
      ),
    );
  }

  // ── 顶部浮动栏 + AI 气泡 ──
  Widget _buildTopBar(ColorScheme cs, TextTheme tt) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white70, size: 28),
              onPressed: () => Navigator.pop(context),
            ),
            const Spacer(),
            IconButton(
              icon: Icon(_playback.loopModeIcon, color: Colors.white70, size: 22),
              onPressed: () => setState(() => _playback.toggleLoopMode()),
              tooltip: _playback.loopModeLabel,
            ),
          ],
        ),
      ),
    );
  }

  /// 一起听：歌名 → 双头像 → 气泡浮层（网易云：气泡在头像下，非底部）
  Widget _buildTogetherHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _track?.name ?? '',
            style: const TextStyle(
                color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          Text(
            _track?.artistName ?? '',
            style: const TextStyle(color: Colors.white54, fontSize: 14),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          _buildTwinAvatars(),
          SizedBox(
            height: 108,
            width: double.infinity,
            child: _buildFloatBubbleStack(),
          ),
        ],
      ),
    );
  }

  Widget _buildFloatBubbleStack() {
    if (_floatBubbles.isEmpty) return const SizedBox.shrink();
    final list = _floatBubbles;
    final n = list.length;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          for (var i = 0; i < n; i++)
            _buildOneFloatBubble(list[i], ageIndex: n - 1 - i),
        ],
      ),
    );
  }

  Widget _buildOneFloatBubble(_FloatBubble b, {required int ageIndex}) {
    final baseOpacity = (1.0 - ageIndex * 0.22).clamp(0.28, 1.0);
    final opacity = b.fading ? 0.0 : baseOpacity;
    final align = b.isUser ? Alignment.centerRight : Alignment.centerLeft;
    final bg = b.isUser
        ? Colors.white.withOpacity(0.18)
        : Colors.white.withOpacity(0.12);

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 380),
      opacity: opacity,
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        offset: b.fading ? const Offset(0, -0.15) : Offset.zero,
        child: Align(
          alignment: align,
          child: Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            constraints: const BoxConstraints(maxWidth: 260),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(14),
                topRight: const Radius.circular(14),
                bottomLeft: Radius.circular(b.isUser ? 14 : 4),
                bottomRight: Radius.circular(b.isUser ? 4 : 14),
              ),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: Text(
              b.text,
              style: TextStyle(
                color: Colors.white.withOpacity(0.92),
                fontSize: 12.5,
                height: 1.35,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }

  // ── 黑胶唱片页（网易云一起听风格）──
  Widget _buildVinylPage(ColorScheme cs, TextTheme tt) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final discSize = constraints.maxWidth * 0.72;
        return GestureDetector(
          onTap: () => setState(() => _showVinyl = false),
          child: Stack(
            children: [
              // 唱片区域（居中）
              Column(
                children: [
                  const Spacer(flex: 3),
                  SizedBox(
                    height: discSize + 60,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // 唱片旋转
                        Transform.rotate(
                          angle: _vinylRotation.value,
                          child: CustomPaint(
                            size: Size(discSize, discSize),
                            painter: _VinylDiscPainter(
                              trackName: _track?.name ?? '',
                              coverImage: _coverImage,
                            ),
                          ),
                        ),
                        // 唱臂
                        Positioned(
                          top: -20,
                          right: discSize * 0.15,
                          child: CustomPaint(
                            size: Size(discSize * 0.45, discSize * 0.55),
                            painter: _TonearmPainter(),
                          ),
                        ),
                        // 更换封面按钮
                        Positioned(
                          bottom: 12,
                          right: discSize * 0.12,
                          child: GestureDetector(
                            onTap: _showCoverPicker,
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.15),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.add_a_photo_rounded, color: Colors.white70, size: 18),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(flex: 2),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  /// 双人头像 + 耳机连线
  Widget _buildTwinAvatars() {
    return FutureBuilder<String?>(
      future: _storage.getUserAvatarPath('user'),
      builder: (context, snapshot) {
        final userAvatar = snapshot.data;
        return SizedBox(
          height: 56,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // 耳机连线（中间弧形装饰）
              CustomPaint(
                size: const Size(120, 56),
                painter: _HeadphoneWirePainter(),
              ),
              // 左：用户头像
              Positioned(
                left: 0,
                child: _avatarCircle(userAvatar, isUser: true),
              ),
              // 右：AI 角色头像
              Positioned(
                right: 0,
                child: _avatarCircle(_character?.avatarUrl, isUser: false),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _avatarCircle(String? avatarUrl, {required bool isUser}) {
    final img = AvatarResolver.imageWidget(
      avatarUrl,
      width: 44,
      height: 44,
    );
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withOpacity(0.3), width: 1.5),
        color: Colors.white.withOpacity(0.08),
      ),
      clipBehavior: Clip.antiAlias,
      child: img ??
          Icon(
            isUser ? Icons.person : Icons.smart_toy_outlined,
            color: Colors.white38,
            size: 22,
          ),
    );
  }

  /// 陪伴信息：TA就在你身边 / 一起听了多久
  // ── 歌词页 ──
  Widget _buildLyricPage(ColorScheme cs, TextTheme tt) {
    return GestureDetector(
      onTap: () => setState(() => _showVinyl = true),
      child: Column(
        children: [
          const SizedBox(height: 8),
          const Text(
            '歌词滚动中…',
            style: TextStyle(color: Colors.white30, fontSize: 11),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _buildLyricList(),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  // ── 歌词列表 ──
  Widget _buildLyricList() {
    if (_lyricLines.isEmpty) {
      return const Center(
        child: Text('暂无歌词', style: TextStyle(color: Colors.white30, fontSize: 14)),
      );
    }

    if (_localFilePath == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.headphones_rounded, size: 48, color: Colors.white24),
            const SizedBox(height: 12),
            const Text('纯歌词模式 — 无音频播放',
                style: TextStyle(color: Colors.white30, fontSize: 13)),
            const SizedBox(height: 20),
            ..._lyricLines.map((l) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(l.text, style: const TextStyle(color: Colors.white38, fontSize: 14),
                  textAlign: TextAlign.center),
            )),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _lyricScrollController,
      padding: const EdgeInsets.symmetric(vertical: 100, horizontal: 32),
      itemCount: _lyricLines.length + 4,
      itemBuilder: (_, i) {
        final effectiveIdx = i - 2;
        if (effectiveIdx < 0 || effectiveIdx >= _lyricLines.length) {
          return const SizedBox(height: 56);
        }
        final line = _lyricLines[effectiveIdx];
        final isCurrent = effectiveIdx == _currentLyricIndex;
        final ts = Duration(milliseconds: line.timestampMs.toInt());

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: isCurrent
                ? BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  )
                : null,
            child: Row(
              children: [
                // 时间戳
                if (isCurrent && line.timestampMs > 0)
                  Text(
                    '${ts.inMinutes.remainder(60).toString().padLeft(2, '0')}:${ts.inSeconds.remainder(60).toString().padLeft(2, '0')}',
                    style: const TextStyle(color: Colors.white38, fontSize: 10),
                  ),
                if (isCurrent && line.timestampMs > 0) const SizedBox(width: 8),
                // 歌词文字
                Expanded(
                  child: Text(
                    line.text,
                    style: TextStyle(
                      color: isCurrent ? Colors.white : Colors.white38,
                      fontSize: isCurrent ? 17 : 14,
                      fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
                      height: 1.6,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                // 单句播放按钮
                if (isCurrent && _localFilePath != null) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.play_circle_outline, size: 18, color: Colors.white.withOpacity(0.3)),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  // ── 底部控制区 ──
  Widget _buildBottomControls(ColorScheme cs, TextTheme tt) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 播放控制（含进度条 + 循环模式）
            _buildTransportAndChat(cs, tt),
          ],
        ),
      ),
    );
  }

  // ── 播放控制 + 折叠输入条 ──
  Widget _buildTransportAndChat(ColorScheme cs, TextTheme tt) {
    final loopMode = _playback.loopMode;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 循环模式 + 进度条
        if (_localFilePath != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                // 循环模式切换
                GestureDetector(
                  onTap: () => setState(() => _playback.toggleLoopMode()),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: loopMode != PlaybackLoopMode.sequential
                          ? Colors.white.withOpacity(0.1)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _playback.loopModeIcon,
                          size: 16,
                          color: loopMode != PlaybackLoopMode.sequential
                              ? Colors.white70
                              : Colors.white30,
                        ),
                        if (loopMode == PlaybackLoopMode.singleRepeat) ...[
                          const SizedBox(width: 2),
                          const Text('1', style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w700)),
                        ],
                        const SizedBox(width: 4),
                        Text(
                          _playback.loopModeLabel,
                          style: TextStyle(
                            color: loopMode != PlaybackLoopMode.sequential ? Colors.white54 : Colors.white24,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                Text(_formatDuration(_position), style: const TextStyle(color: Colors.white54, fontSize: 10)),
                const SizedBox(width: 8),
                Expanded(
                  child: SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 2,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                      activeTrackColor: Colors.white,
                      inactiveTrackColor: Colors.white24,
                      thumbColor: Colors.white,
                      overlayColor: Colors.white.withOpacity(0.1),
                    ),
                    child: Slider(
                      value: _position.inMilliseconds.toDouble().clamp(0, _duration.inMilliseconds.toDouble()),
                      max: _duration.inMilliseconds.toDouble() > 0 ? _duration.inMilliseconds.toDouble() : 1.0,
                      onChanged: (v) => _playback.seek(Duration(milliseconds: v.toInt())),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(_formatDuration(_duration), style: const TextStyle(color: Colors.white54, fontSize: 10)),
              ],
            ),
          ),
        // 播放按钮行
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(width: 48),
            if (_localFilePath != null) ...[
              IconButton(
                icon: const Icon(Icons.replay_10_rounded, color: Colors.white70, size: 28),
                onPressed: () {
                  final target = _position - const Duration(seconds: 10);
                  _playback.seek(target < Duration.zero ? Duration.zero : target);
                },
                tooltip: '后退10秒',
              ),
              const SizedBox(width: 12),
            ],
            if (_localFilePath != null)
              Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
                child: IconButton(
                  icon: Icon(
                    _playState == MusicPlaybackState.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: Colors.black,
                    size: 32,
                  ),
                  onPressed: () => _playback.togglePlayPause(),
                ),
              )
            else
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.15)),
                child: const Icon(Icons.play_arrow_rounded, color: Colors.white30, size: 32),
              ),
            if (_localFilePath != null) ...[
              const SizedBox(width: 12),
              IconButton(
                icon: const Icon(Icons.forward_10_rounded, color: Colors.white70, size: 28),
                onPressed: () {
                  final target = _position + const Duration(seconds: 10);
                  _playback.seek(target > _duration ? _duration : target);
                },
                tooltip: '前进10秒',
              ),
            ],
            const SizedBox(width: 48),
          ],
        ),
        const SizedBox(height: 6),
        // 折叠输入条
        _buildFoldedInputBar(),
      ],
    );
  }

  /// 折叠态输入条：半透明单行输入 + 查看聊天记录入口
  Widget _buildFoldedInputBar() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 输入条（消息气泡已改到头像下方浮层）
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              // 表情按钮
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.emoji_emotions_outlined, color: Colors.white38, size: 20),
                onPressed: () {},
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
              // 输入框
              Expanded(
                child: TextField(
                  controller: _msgController,
                  focusNode: _inputFocusNode,
                  decoration: InputDecoration(
                    hintText: _inputFocused ? '说点什么…' : '点击输入你想说的话',
                    hintStyle: TextStyle(color: _inputFocused ? Colors.white24 : Colors.white.withOpacity(0.4), fontSize: 13),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
                    isDense: true,
                  ),
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                  textInputAction: TextInputAction.send,
                  onSubmitted: (v) {
                    _sendUserMessage(v);
                    _inputFocusNode.unfocus();
                  },
                ),
              ),
              // 发送/图片按钮
              IconButton(
                icon: const Icon(Icons.image_outlined, color: Colors.white38, size: 20),
                onPressed: () {},
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
              IconButton(
                icon: Icon(
                  _inputFocused ? Icons.send_rounded : Icons.send_outlined,
                  color: _inputFocused ? Colors.white : Colors.white38,
                  size: 20,
                ),
                onPressed: () {
                  _sendUserMessage(_msgController.text);
                  _inputFocusNode.unfocus();
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
        // 查看聊天记录入口
        GestureDetector(
          onTap: _openChatHistory,
          child: Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.history_rounded, size: 12, color: Colors.white.withOpacity(0.3)),
                const SizedBox(width: 4),
                Text(
                  '查看聊天记录',
                  style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 11),
                ),
                if (_messages.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('${_messages.length}', style: const TextStyle(color: Colors.white, fontSize: 9)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 打开聊天记录全屏页
  void _openChatHistory() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _MusicChatHistoryPage(
          messages: _messages,
          character: _character,
          userAvatarFuture: _storage.getUserAvatarPath('user'),
        ),
      ),
    );
  }

  // ── 选择器视图 ──
  Widget _buildPickerView(ColorScheme cs, TextTheme tt) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.headphones_rounded, size: 72, color: cs.primary),
            const SizedBox(height: 16),
            Text('音乐共情', style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(
              '选择一个本地音乐文件\n自动识别歌曲信息并匹配歌词\n与角色共享听歌的情感共鸣',
              style: tt.bodyMedium?.copyWith(color: cs.onSurface.withOpacity(0.6)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            // 角色选择
            if (_character == null)
              _buildCharacterPicker(cs, tt)
            else
              _buildSelectedCharacterChip(cs, tt),
            const SizedBox(height: 20),
            // 选择文件按钮
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: _isProcessing ? null : _pickAndPlay,
                icon: _isProcessing
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.folder_open_rounded),
                label: Text(_isProcessing ? _statusText : '选择本地音乐文件'),
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: OutlinedButton.icon(
                onPressed: _isProcessing ? null : _searchOnlineLyrics,
                icon: const Icon(Icons.search_rounded),
                label: const Text('搜索在线歌词'),
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
            if (_statusText.isNotEmpty && !_isProcessing) ...[
              const SizedBox(height: 12),
              Text(_statusText, style: tt.bodySmall?.copyWith(color: cs.error)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCharacterPicker(ColorScheme cs, TextTheme tt) {
    return Material(
      color: cs.primaryContainer.withOpacity(0.3),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _pickCharacter,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.person_add_rounded, color: cs.primary, size: 20),
              const SizedBox(width: 8),
              Text('选择一起听歌的角色', style: tt.bodyMedium?.copyWith(color: cs.primary, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSelectedCharacterChip(ColorScheme cs, TextTheme tt) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: cs.primaryContainer,
          child: Text(
            _character!.name.characters.first,
            style: TextStyle(color: cs.onPrimaryContainer, fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(width: 8),
        Text('与 ${_character!.name} 一起听', style: tt.bodyMedium),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: _pickCharacter,
          child: Icon(Icons.swap_horiz, size: 18, color: cs.primary),
        ),
      ],
    );
  }

  String _formatDuration(Duration d) {
    final min = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final sec = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$min:$sec';
  }

  // ── 唱片封面管理 ──

  String get _coverPrefKey {
    final title = _track?.name ?? '';
    final artist = _track?.artistName ?? '';
    return 'music_cover_${artist}_$title';
  }

  /// 弹出相册选择，保存图片路径到 SharedPreferences
  Future<void> _showCoverPicker() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;

    final path = picked.path;
    // 拷贝到 app 文档目录，防止原文件被移动/删除
    final docsDir = (await getApplicationDocumentsDirectory()).path;
    final coverDir = Directory('$docsDir/music_covers');
    if (!await coverDir.exists()) await coverDir.create(recursive: true);
    final destPath = '$docsDir/music_covers/${picked.name}';
    await File(path).copy(destPath);

    // 持久化
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_coverPrefKey, destPath);

    // 加载为 ui.Image
    await _loadCoverFromPath(destPath);
  }

  /// 从已保存的路径加载封面图片
  Future<void> _loadSavedCoverImage() async {
    final prefs = await SharedPreferences.getInstance();
    final savedPath = prefs.getString(_coverPrefKey);
    if (savedPath != null && File(savedPath).existsSync()) {
      await _loadCoverFromPath(savedPath);
    } else {
      setState(() => _coverImage = null);
    }
  }

  Future<void> _loadCoverFromPath(String path) async {
    if (_coverLoading) return;
    _coverLoading = true;
    try {
      final bytes = await File(path).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 256);
      final frame = await codec.getNextFrame();
      if (!mounted) return;
      setState(() {
        _coverImage = frame.image;
        _coverLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _coverLoading = false);
    }
  }
}

// ═══════════════════════════════════════════════════════
// 黑胶唱片 CustomPainter
// ═══════════════════════════════════════════════════════
class _VinylDiscPainter extends CustomPainter {
  final String trackName;
  final ui.Image? coverImage;
  _VinylDiscPainter({required this.trackName, this.coverImage});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // 外圈黑色胶盘
    final outerPaint = Paint()..color = const Color(0xFF1a1a1a);
    canvas.drawCircle(center, radius, outerPaint);

    // 胶盘纹理（同心圆环）
    for (var i = 1; i <= 6; i++) {
      final ring = radius * (0.45 + i * 0.08);
      final ringPaint = Paint()
        ..color = const Color(0xFF2a2a2a)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;
      canvas.drawCircle(center, ring, ringPaint);
    }

    // 中心封面区域
    final coverRadius = radius * 0.4;
    final coverRect = Rect.fromCircle(center: center, radius: coverRadius);

    if (coverImage != null) {
      // 裁剪圆形，绘制图片
      canvas.save();
      final clipPath = Path()..addOval(coverRect);
      canvas.clipPath(clipPath);
      final srcRect = Rect.fromLTWH(0, 0, coverImage!.width.toDouble(), coverImage!.height.toDouble());
      canvas.drawImageRect(coverImage!, srcRect, coverRect, Paint());
      canvas.restore();
    } else {
      // 无图片：纯色背景 + 文字
      final coverPaint = Paint()..color = const Color(0xFF2c2c3e);
      canvas.drawCircle(center, coverRadius, coverPaint);

      final tp = TextPainter(
        text: TextSpan(
          text: trackName.isNotEmpty ? trackName.substring(0, (trackName.length / 3).ceil()) : '',
          style: const TextStyle(color: Colors.white24, fontSize: 10, fontWeight: FontWeight.w500),
        ),
        textDirection: ui.TextDirection.ltr,
      )..layout(maxWidth: coverRadius * 1.4);
      tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy - tp.height / 2));
    }

    // 中心小圆
    final centerDot = Paint()..color = const Color(0xFF444444);
    canvas.drawCircle(center, 8, centerDot);
    final centerInner = Paint()..color = const Color(0xFF222222);
    canvas.drawCircle(center, 4, centerInner);
  }

  @override
  bool shouldRepaint(covariant _VinylDiscPainter oldDelegate) =>
      oldDelegate.trackName != trackName || oldDelegate.coverImage != coverImage;
}

// ═══════════════════════════════════════════════════════
// 黑胶唱片 CustomPainter
// ═══════════════════════════════════════════════════════
class _TonearmPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.6)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    // 唱臂主杆
    final path = Path();
    path.moveTo(size.width * 0.1, 0);
    path.lineTo(size.width * 0.85, size.height * 0.85);
    canvas.drawPath(path, paint);

    // 唱臂支点
    canvas.drawCircle(Offset(size.width * 0.1, 0), 5, Paint()..color = Colors.white54);

    // 唱头（末端小方块）
    final headRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(size.width * 0.88, size.height * 0.88), width: 8, height: 6),
      const Radius.circular(2),
    );
    canvas.drawRRect(headRect, Paint()..color = Colors.white70);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ═══════════════════════════════════════════════════════
// 耳机连线 CustomPainter
// ═══════════════════════════════════════════════════════
class _HeadphoneWirePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    // 左耳机（半圆 + 直线）
    final leftCenter = Offset(size.width * 0.2, size.height * 0.5);
    final rightCenter = Offset(size.width * 0.8, size.height * 0.5);

    // 左侧耳机弧线
    final leftArc = Path()
      ..moveTo(leftCenter.dx + 10, leftCenter.dy - 8)
      ..quadraticBezierTo(
        leftCenter.dx + 18, leftCenter.dy - 18,
        leftCenter.dx + 22, leftCenter.dy,
      );
    canvas.drawPath(leftArc, paint);

    // 右侧耳机弧线
    final rightArc = Path()
      ..moveTo(rightCenter.dx - 10, rightCenter.dy - 8)
      ..quadraticBezierTo(
        rightCenter.dx - 18, rightCenter.dy - 18,
        rightCenter.dx - 22, rightCenter.dy,
      );
    canvas.drawPath(rightArc, paint);

    // 中间连接线
    final midLine = Paint()
      ..color = Colors.white.withOpacity(0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    final midPath = Path()
      ..moveTo(leftCenter.dx + 22, leftCenter.dy)
      ..quadraticBezierTo(
        size.width * 0.5, leftCenter.dy + 10,
        rightCenter.dx - 22, rightCenter.dy,
      );
    canvas.drawPath(midPath, midLine);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ═══════════════════════════════════════════════════════
// 角色选择器 Bottom Sheet
// ═══════════════════════════════════════════════════════
class _CharacterPickerSheet extends StatelessWidget {
  final List<AICharacter> characters;
  final ColorScheme colorScheme;
  final TextTheme textTheme;
  const _CharacterPickerSheet({required this.characters, required this.colorScheme, required this.textTheme});

  @override
  Widget build(BuildContext context) {
    final cs = colorScheme;
    final tt = textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('选择一起听歌的角色', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: characters.length,
              itemBuilder: (_, i) {
                final c = characters[i];
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: cs.secondaryContainer,
                      child: Text(c.name.characters.first,
                          style: TextStyle(color: cs.onSecondaryContainer, fontWeight: FontWeight.w600)),
                    ),
                    title: Text(c.name),
                    subtitle: Text(c.personality.isNotEmpty ? c.personality : '暂无简介',
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () => Navigator.pop(context, c),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// 在线搜索结果选择器
// ═══════════════════════════════════════════════════════
class _SearchResultSheet extends StatelessWidget {
  final List<MusicTrack> results;
  final ColorScheme colorScheme;
  final TextTheme textTheme;
  const _SearchResultSheet({required this.results, required this.colorScheme, required this.textTheme});

  @override
  Widget build(BuildContext context) {
    final cs = colorScheme;
    final tt = textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('选择匹配的歌曲', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('搜索结果，点击选择', style: tt.bodySmall?.copyWith(color: cs.onSurface.withOpacity(0.5))),
          const SizedBox(height: 16),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: results.length,
              itemBuilder: (_, i) {
                final t = results[i];
                final hasSync = t.syncedLyrics != null && t.syncedLyrics!.isNotEmpty;
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: hasSync ? cs.primaryContainer : cs.surfaceContainerHighest,
                      child: Icon(
                        hasSync ? Icons.lyrics : Icons.music_note,
                        size: 20,
                        color: hasSync ? cs.primary : cs.onSurface.withOpacity(0.4),
                      ),
                    ),
                    title: Text(t.name, style: const TextStyle(fontWeight: FontWeight.w500)),
                    subtitle: Text(
                      '${t.artistName}${t.albumName != null && t.albumName!.isNotEmpty ? ' · ${t.albumName}' : ''}${!hasSync ? ' (无时间戳歌词)' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: hasSync
                        ? Icon(Icons.check_circle_outline, size: 20, color: cs.primary.withOpacity(0.5))
                        : null,
                    onTap: () => Navigator.pop(context, t),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FloatBubble {
  final String id;
  final String text;
  final bool isUser;
  Timer? timer;
  bool fading = false;

  _FloatBubble({
    required this.id,
    required this.text,
    required this.isUser,
  });
}

// ═══════════════════════════════════════════════════════
// 聊天记录全屏页面
// ═══════════════════════════════════════════════════════
class _MusicChatHistoryPage extends StatelessWidget {
  final List<ChatMessage> messages;
  final AICharacter? character;
  final Future<String?> userAvatarFuture;

  const _MusicChatHistoryPage({
    required this.messages,
    required this.character,
    required this.userAvatarFuture,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0f0f1a),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white70, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          '与 ${character?.name ?? 'TA'} 的聊天记录',
          style: const TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.w500),
        ),
        centerTitle: true,
      ),
      body: messages.isEmpty
          ? const Center(
              child: Text('暂无聊天记录', style: TextStyle(color: Colors.white24, fontSize: 14)),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: messages.length,
              itemBuilder: (context, i) => _buildMessageBubble(context, messages[i], i),
            ),
    );
  }

  Widget _buildMessageBubble(BuildContext context, ChatMessage msg, int index) {
    final isSystem = msg.type == MessageType.system;
    final isUser = msg.isUser || msg.senderId == 'user';
    if (isSystem) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(children: [
          const Expanded(child: Divider(color: Colors.white12)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(msg.content, style: const TextStyle(color: Colors.white24, fontSize: 11)),
          ),
          const Expanded(child: Divider(color: Colors.white12)),
        ]),
      );
    }
    final timeStr = _formatTime(msg.createdAt);
    final showTime = index == 0 || _shouldShowTime(msg.createdAt, messages[index - 1].createdAt);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (showTime)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Center(
                child: Text(timeStr, style: const TextStyle(color: Colors.white24, fontSize: 11)),
              ),
            ),
          Row(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            if (!isUser) ...[_buildAvatar(isUser: false), const SizedBox(width: 8)],
            Flexible(
              child: Column(
                crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  if (!isUser)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        msg.senderName.isNotEmpty ? msg.senderName : (character?.name ?? 'AI'),
                        style: const TextStyle(color: Colors.white38, fontSize: 10),
                      ),
                    ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.65),
                    decoration: BoxDecoration(
                      color: isUser ? Colors.white.withOpacity(0.15) : Colors.white.withOpacity(0.06),
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(14),
                        topRight: const Radius.circular(14),
                        bottomLeft: Radius.circular(isUser ? 14 : 2),
                        bottomRight: Radius.circular(isUser ? 2 : 14),
                      ),
                    ),
                    child: Text(msg.content, style: TextStyle(color: isUser ? Colors.white : Colors.white70, fontSize: 13)),
                  ),
                ],
              ),
            ),
            if (isUser) ...[const SizedBox(width: 8), _buildAvatar(isUser: true)],
          ]),
        ],
      ),
    );
  }

  Widget _buildAvatar({required bool isUser}) {
    if (isUser) {
      return FutureBuilder<String?>(
        future: userAvatarFuture,
        builder: (context, snapshot) {
          final img = AvatarResolver.imageWidget(snapshot.data, width: 28, height: 28);
          return Container(
            width: 28, height: 28,
            decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.1)),
            clipBehavior: Clip.antiAlias,
            child: img ?? const Icon(Icons.person, color: Colors.white38, size: 16),
          );
        },
      );
    }
    final img = AvatarResolver.imageWidget(character?.avatarUrl, width: 28, height: 28);
    return Container(
      width: 28, height: 28,
      decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.1)),
      clipBehavior: Clip.antiAlias,
      child: img ?? const Icon(Icons.smart_toy_outlined, color: Colors.white38, size: 16),
    );
  }

  bool _shouldShowTime(DateTime current, DateTime previous) =>
      current.difference(previous).inMinutes >= 5;

  static String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
    if (diff.inDays < 1) return '${diff.inHours} 小时前';
    if (diff.inDays == 1) return '昨天 ${_pad(dt.hour)}:${_pad(dt.minute)}';
    return '${dt.month}/${dt.day} ${_pad(dt.hour)}:${_pad(dt.minute)}';
  }

  static String _pad(int n) => n.toString().padLeft(2, '0');
}