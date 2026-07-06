import "dart:async";
import "dart:convert";
import "dart:io";
import "dart:typed_data";
import "package:http/http.dart" as http;
import "package:path_provider/path_provider.dart";
import "package:flutter/foundation.dart";
import "../config/tts_config.dart";
import "../utils/response_decoder.dart";

/// TTS 语音合成服务（MiMo VoiceClone API）
///
/// 使用 MiMo-V2.5-TTS-VoiceClone 模型，支持音色克隆和情绪标签。
/// 内置请求队列和速率限制重试，防止 429 错误。
/// API 格式：chat-completions 风格，音频以 base64 返回。
class TTSService {
  final String? apiKey;
  final String? baseUrl;

  TTSService({this.apiKey, this.baseUrl});

  // ── 请求队列：同一时间只允许一个 TTS 请求 ──
  static Future<void>? _queueTail;
  static const int _maxRetries = 2;
  static const Duration _retryBaseDelay = Duration(seconds: 1);

  /// 将 TTS 请求排入队列，保证串行执行
  Future<String?> _enqueue(Future<String?> Function() task) async {
    // 等待前一个请求完成
    final prev = _queueTail;
    final completer = Completer<void>();
    _queueTail = completer.future;

    if (prev != null) {
      try { await prev; } catch (e) { debugPrint('Error: $e'); }
    }

    try {
      return await task();
    } finally {
      completer.complete();
    }
  }

  /// 获取有效的 API Key
  String? get _effectiveApiKey => apiKey ?? TTSConfig.cachedApiKey;

  /// 获取有效的 Base URL
  String get _effectiveBaseUrl {
    if (baseUrl != null && baseUrl!.isNotEmpty) return baseUrl!;
    return TTSConfig.baseUrl;
  }

  // ═══════════════════════════════════════════════
  // 文本清洗
  // ═══════════════════════════════════════════════

  /// 清洗文本用于 TTS
  String clearTtsText(String text) {
    text = _removeEmoji(text);
    text = text.replaceAll(RegExp(r'\[.*?\]'), '');
    text = text
        .replaceAll('\$', '，')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll('\n', '，');
    return text.trim();
  }

  /// 移除 emoji 字符
  String _removeEmoji(String text) {
    final emojiPattern = RegExp(
      r'[\u{1F600}-\u{1F64F}]|'
      r'[\u{1F300}-\u{1F5FF}]|'
      r'[\u{1F680}-\u{1F6FF}]|'
      r'[\u{1F1E0}-\u{1F1FF}]|'
      r'[\u{2600}-\u{26FF}]|'
      r'[\u{2700}-\u{27BF}]|'
      r'[\u{FE00}-\u{FE0F}]|'
      r'[\u{1F900}-\u{1F9FF}]|'
      r'[\u{1FA00}-\u{1FA6F}]|'
      r'[\u{1FA70}-\u{1FAFF}]',
      unicode: true,
    );
    return text.replaceAll(emojiPattern, '');
  }

  // ═══════════════════════════════════════════════
  // 情绪标签注入
  // ═══════════════════════════════════════════════

  /// 扫描文本中的情绪关键词，注入 MiMo 内联情绪标签
  String _injectEmotionTags(String text) {
    String result = text;
    for (final entry in TTSConfig.emotionKeywords.entries) {
      final keywords = entry.key;
      final tag = entry.value;
      for (final kw in keywords) {
        if (result.contains(kw)) {
          // 在关键词前插入情绪标签（如果还没有的话）
          if (!result.contains(tag)) {
            result = result.replaceFirst(kw, '$tag$kw');
          }
        }
      }
    }
    return result;
  }

  // ═══════════════════════════════════════════════
  // 核心：调用 MiMo TTS API
  // ═══════════════════════════════════════════════

  /// 生成语音文件（带队列和 429 重试）
  ///
  /// [text] 要合成的文本
  /// [voiceBase64] 音色样本的 base64 编码（data:audio/mpeg;base64,... 格式）
  /// [styleInstruction] 风格指令（如"像真人打电话一样自然说话"）
  Future<String?> generateAudio(
    String text, {
    String? voiceBase64,
    String? styleInstruction,
  }) {
    debugPrint('TTS: generateAudio 被调用, text="${text.length > 30 ? text.substring(0, 30) : text}...", voiceBase64=${voiceBase64 != null ? "${voiceBase64.length}chars" : "null"}');
    return _enqueue(() => _generateAudioWithRetry(
      text,
      voiceBase64: voiceBase64,
      styleInstruction: styleInstruction,
    ));
  }

  /// 实际执行 TTS 请求（带 429 重试）
  Future<String?> _generateAudioWithRetry(
    String text, {
    String? voiceBase64,
    String? styleInstruction,
  }) async {
    for (int attempt = 0; attempt <= _maxRetries; attempt++) {
      try {
        final result = await _generateAudioInternal(
          text,
          voiceBase64: voiceBase64,
          styleInstruction: styleInstruction,
        );
        if (result != null) {
          debugPrint('TTS: 生成成功, path=$result');
          return result;
        }

        debugPrint('TTS: _generateAudioInternal 返回 null (attempt ${attempt + 1})');
        // null 可能是 429 导致的，重试
        if (attempt < _maxRetries) {
          final delay = _retryBaseDelay * (attempt + 1);
          debugPrint('TTS: 重试 ${attempt + 1}/$_maxRetries, 等待 ${delay.inSeconds}s');
          await Future.delayed(delay);
        }
      } catch (e) {
        debugPrint('TTS: 异常 $e (attempt ${attempt + 1})');
        if (attempt < _maxRetries) {
          await Future.delayed(_retryBaseDelay * (attempt + 1));
        }
      }
    }
    debugPrint('TTS: 所有重试均失败，返回 null');
    return null;
  }

  /// 单次 TTS API 调用
  Future<String?> _generateAudioInternal(
    String text, {
    String? voiceBase64,
    String? styleInstruction,
  }) async {
    final key = _effectiveApiKey;
    if (key == null || key.isEmpty) {
      debugPrint('TTS: API Key 未配置');
      return null;
    }

    // 1. 清洗文本 + 注入情绪标签（让声音有自然情绪变化）
    String cleanText = clearTtsText(text);
    if (cleanText.isEmpty) return null;
    cleanText = _injectEmotionTags(cleanText);

    // 2. 准备临时文件路径
    final dir = await getTemporaryDirectory();
    final voiceDir = Directory('${dir.path}/voices');
    if (!await voiceDir.exists()) {
      await voiceDir.create(recursive: true);
    }
    final timestamp = DateTime.now().toString().replaceAll(RegExp(r'[^0-9]'), '');
    final voicePath = '${voiceDir.path}/voice_$timestamp.wav';

    // 3. 构建请求体（MiMo chat-completions 格式）
    // 风格指令固定不变，保证全场景音色一致
    final userContent = (styleInstruction != null && styleInstruction.isNotEmpty)
        ? styleInstruction
        : TTSConfig.defaultStyleInstruction;

    final body = <String, dynamic>{
      'model': TTSConfig.model,
      'messages': [
        {'role': 'user', 'content': userContent},
        {'role': 'assistant', 'content': cleanText},
      ],
      'audio': {
        'format': TTSConfig.defaultFormat,
      },
      'temperature': TTSConfig.temperature,
      'top_p': TTSConfig.topP,
    };

    // 如果有音色样本，加入 audio.voice
    if (voiceBase64 != null && voiceBase64.isNotEmpty) {
      body['audio']['voice'] = voiceBase64;
    }

    // 5. 发送请求
    final url = Uri.parse('${_effectiveBaseUrl}/chat/completions');
    debugPrint('TTS: 请求, 文本长度=${cleanText.length}, 有音色=${voiceBase64 != null}');

    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'api-key': key,
        'Authorization': 'Bearer $key',
      },
      body: jsonEncode(body),
    ).timeout(const Duration(seconds: 15));

    // 429 速率限制 → 返回 null 让重试逻辑处理
    if (response.statusCode == 429) {
      debugPrint('TTS: 429 速率限制');
      return null;
    }

    if (response.statusCode != 200) {
      final errBody = await ResponseDecoder.decode(response.headers['content-type'], response.bodyBytes);
      debugPrint('TTS: API 返回 ${response.statusCode}: ${errBody.substring(0, errBody.length > 200 ? 200 : errBody.length)}');
      return null;
    }

    // 6. 解析响应：提取 base64 音频数据
    final decoded = await ResponseDecoder.decode(response.headers['content-type'], response.bodyBytes);
    final data = jsonDecode(decoded) as Map<String, dynamic>;
    final choices = data['choices'] as List?;
    if (choices == null || choices.isEmpty) {
      debugPrint('TTS: 响应无 choices');
      return null;
    }

    final message = choices[0]['message'] as Map<String, dynamic>?;
    final audioData = message?['audio'] as Map<String, dynamic>?;
    final base64Audio = audioData?['data'] as String?;

    if (base64Audio == null || base64Audio.isEmpty) {
      debugPrint('TTS: 响应无 audio.data');
      return null;
    }

    // 7. base64 解码并写入文件
    final audioBytes = base64Decode(base64Audio);
    final file = File(voicePath);
    await file.writeAsBytes(audioBytes);
    debugPrint('TTS: 合成成功, ${audioBytes.length} bytes');
    return voicePath;
  }

  // ═══════════════════════════════════════════════
  // 分句工具（适配 MiMo TTS 官方规范）
  // ═══════════════════════════════════════════════

  /// 文本预处理 + 智能分句
  ///
  /// 1. 剔除冗余特殊符号、括号动作描写
  /// 2. 合并零散 1~3 字短句
  /// 3. 按句号/问号分句，单段上限 45 汉字
  /// 4. 超长句按逗号二次切分
  List<String> splitSentences(String text) {
    if (text.isEmpty) return [];

    // ── 1. 文本预处理 ──
    String cleaned = text;
    // 剔除括号动作描写
    cleaned = cleaned.replaceAll(RegExp(r'\([^)]*\)'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\[[^\]]*\]'), '');
    cleaned = cleaned.replaceAll(RegExp(r'（[^）]*）'), '');
    cleaned = cleaned.replaceAll(RegExp(r'【[^】]*】'), '');
    // 剔除多余标点和特殊符号（保留基本标点）
    cleaned = cleaned.replaceAll(RegExp(r'[~～…♡❤️💕😊🤔😔喵呜]+'), '');
    // 合并连续标点
    cleaned = cleaned.replaceAll(RegExp(r'[，,]{2,}'), '，');
    cleaned = cleaned.replaceAll(RegExp(r'[。.]{2,}'), '。');
    cleaned = cleaned.trim();
    if (cleaned.isEmpty) return [];

    // ── 2. 按句号/问号/感叹号/换行初步分句 ──
    final rawSentences = <String>[];
    final pattern = RegExp(r'[^。！？.!?\n]+[。！？.!?\n]?');
    final matches = pattern.allMatches(cleaned);
    for (final m in matches) {
      final s = m.group(0)?.trim();
      if (s != null && s.isNotEmpty) {
        rawSentences.add(s);
      }
    }
    if (rawSentences.isEmpty && cleaned.isNotEmpty) {
      rawSentences.add(cleaned);
    }

    // ── 3. 超长句按逗号二次切分 + 字数上限校验 ──
    final sentences = <String>[];
    for (final s in rawSentences) {
      if (s.length <= TTSConfig.maxCharsPerSentence) {
        sentences.add(s);
      } else {
        sentences.addAll(_splitByComma(s));
      }
    }

    // ── 4. 合并过短碎片（<4字的合并到前一句） ──
    final merged = <String>[];
    for (final s in sentences) {
      if (merged.isNotEmpty && s.length <= 3 && !s.contains(RegExp(r'[。！？.!?\n]'))) {
        // 短句合并到前一句
        final last = merged.removeLast();
        merged.add('$last$s');
      } else {
        merged.add(s);
      }
    }

    // ── 5. 最终字数校验：确保单句不超限 ──
    final result = <String>[];
    for (final s in merged) {
      if (s.length > TTSConfig.maxCharsPerSentence) {
        // 强制按字数切分
        result.addAll(_forceSplitByChars(s, TTSConfig.maxCharsPerSentence));
      } else {
        result.add(s);
      }
    }

    return result;
  }

  /// 按逗号切分超长句子
  List<String> _splitByComma(String text) {
    final parts = <String>[];
    final pattern = RegExp(r'[^，,、]+[，,、]?');
    final matches = pattern.allMatches(text);
    for (final m in matches) {
      final s = m.group(0)?.trim();
      if (s != null && s.isNotEmpty) {
        // 递归：如果切完还是太长，再按字数强制切
        if (s.length > TTSConfig.maxCharsPerSentence) {
          parts.addAll(_forceSplitByChars(s, TTSConfig.maxCharsPerSentence));
        } else {
          parts.add(s);
        }
      }
    }
    return parts.isEmpty ? [text] : parts;
  }

  /// 按字数强制切分（最后手段）
  List<String> _forceSplitByChars(String text, int maxChars) {
    final parts = <String>[];
    var remaining = text;
    while (remaining.length > maxChars) {
      parts.add(remaining.substring(0, maxChars));
      remaining = remaining.substring(maxChars);
    }
    if (remaining.isNotEmpty) {
      parts.add(remaining);
    }
    return parts;
  }

  /// 预估文本音频时长（秒）
  double estimateDuration(String text) {
    // 统计汉字数（忽略标点和空格）
    final charCount = text.replaceAll(RegExp(r'[，,。.！？!?、\s\n]'), '').length;
    return charCount * TTSConfig.charsPerSecond;
  }

  // ═══════════════════════════════════════════════
  // 公开接口
  // ═══════════════════════════════════════════════

  /// 合成语音（单次调用）
  Future<String?> synthesize({
    required String text,
    String? voiceBase64,
    String? styleInstruction,
  }) =>
      generateAudio(text, voiceBase64: voiceBase64, styleInstruction: styleInstruction);

  /// 逐句流式合成语音（段间插入静音帧消除拼接电音）
  Stream<String> synthesizeStream({
    required String text,
    String? voiceBase64,
    String? styleInstruction,
  }) async* {
    final sentences = splitSentences(text);
    debugPrint('TTS Stream: 共 ${sentences.length} 句');

    for (int i = 0; i < sentences.length; i++) {
      final sentence = sentences[i];
      final path = await generateAudio(
        sentence,
        voiceBase64: voiceBase64,
        styleInstruction: styleInstruction,
      );
      if (path != null) {
        yield path;
        // 段间插入 150ms 静音帧（非最后一句）
        if (i < sentences.length - 1) {
          final silencePath = await _generateSilence(150);
          if (silencePath != null) yield silencePath;
        }
      }
    }
  }

  /// 生成指定时长的静音 WAV 文件
  Future<String?> _generateSilence(int ms) async {
    try {
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/voices/silence_${ms}ms.wav';
      final file = File(path);
      if (await file.exists()) return path;

      // WAV: 16kHz, 16bit, mono
      final sampleRate = 16000;
      final numChannels = 1;
      final bitsPerSample = 16;
      final numSamples = (sampleRate * ms / 1000).round();
      final dataSize = numSamples * numChannels * (bitsPerSample ~/ 8);
      final fileSize = 44 + dataSize;

      final bytes = ByteData(fileSize);
      // RIFF header
      bytes.setUint8(0, 0x52); // R
      bytes.setUint8(1, 0x49); // I
      bytes.setUint8(2, 0x46); // F
      bytes.setUint8(3, 0x46); // F
      bytes.setUint32(4, fileSize - 8, Endian.little);
      bytes.setUint8(8, 0x57); // W
      bytes.setUint8(9, 0x41); // A
      bytes.setUint8(10, 0x56); // V
      bytes.setUint8(11, 0x45); // E
      // fmt chunk
      bytes.setUint8(12, 0x66); // f
      bytes.setUint8(13, 0x6D); // m
      bytes.setUint8(14, 0x74); // t
      bytes.setUint8(15, 0x20); // space
      bytes.setUint32(16, 16, Endian.little); // chunk size
      bytes.setUint16(20, 1, Endian.little); // PCM
      bytes.setUint16(22, numChannels, Endian.little);
      bytes.setUint32(24, sampleRate, Endian.little);
      bytes.setUint32(28, sampleRate * numChannels * (bitsPerSample ~/ 8), Endian.little);
      bytes.setUint16(32, numChannels * (bitsPerSample ~/ 8), Endian.little);
      bytes.setUint16(34, bitsPerSample, Endian.little);
      // data chunk
      bytes.setUint8(36, 0x64); // d
      bytes.setUint8(37, 0x61); // a
      bytes.setUint8(38, 0x74); // t
      bytes.setUint8(39, 0x61); // a
      bytes.setUint32(40, dataSize, Endian.little);
      // silence (all zeros, already default)

      await file.create(recursive: true);
      await file.writeAsBytes(bytes.buffer.asUint8List());
      return path;
    } catch (e) {
      debugPrint('TTS: 生成静音失败: $e');
      return null;
    }
  }

  /// 预览语音
  Future<String?> preview({String? voiceBase64}) =>
      generateAudio(TTSConfig.previewText, voiceBase64: voiceBase64);

  /// 删除语音文件
  Future<void> deleteAudio(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) { debugPrint('Error: $e'); }
  }

  /// 清理所有临时语音文件
  Future<void> clearAllAudio() async {
    try {
      final dir = await getTemporaryDirectory();
      final voiceDir = Directory('${dir.path}/voices');
      if (await voiceDir.exists()) {
        await voiceDir.delete(recursive: true);
      }
    } catch (e) { debugPrint('Error: $e'); }
  }

  /// 保存到永久目录
  Future<String?> saveToPermanentDir(String tempPath, [String? customName]) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final voiceDir = Directory('${dir.path}/voices');
      if (!await voiceDir.exists()) {
        await voiceDir.create(recursive: true);
      }
      final fileName = customName ?? tempPath.split('/').last;
      final newPath = '${voiceDir.path}/$fileName';
      await File(tempPath).copy(newPath);
      return newPath;
    } catch (_) {
      return null;
    }
  }

  /// 清理缓存
  Future<void> clearCache() => clearAllAudio();
}
