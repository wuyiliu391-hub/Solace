import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/usage_record.dart';
import '../utils/prefs_helper.dart';

class UsageMeterService {
  UsageMeterService._();

  static final UsageMeterService instance = UsageMeterService._();

  static const _recordsKey = 'usage_meter_records_v1';
  static const _inputPriceKey = 'usage_meter_input_price';
  static const _outputPriceKey = 'usage_meter_output_price';
  static const _maxRecords = 2000;

  // ── 内存缓存 ──
  UsagePricing? _cachedPricing;
  List<UsageRecord>? _cachedRecords;
  final List<UsageRecord> _pendingBuffer = [];
  Timer? _flushTimer;
  bool _dirty = false;

  final StreamController<void> _changes = StreamController<void>.broadcast();
  Stream<void> get changes => _changes.stream;

  // ── 初始化：启动时调用一次，预热缓存 ──

  Future<void> warmUp() async {
    await getPricing();
    await _loadRecords();
  }

  // ── 单价 ──

  Future<UsagePricing> getPricing() async {
    if (_cachedPricing != null) return _cachedPricing!;
    final prefs = await PrefsHelper.instance;
    _cachedPricing = UsagePricing(
      inputPricePerMillion: prefs.getDouble(_inputPriceKey) ??
          UsagePricing.defaults.inputPricePerMillion,
      outputPricePerMillion: prefs.getDouble(_outputPriceKey) ??
          UsagePricing.defaults.outputPricePerMillion,
    );
    return _cachedPricing!;
  }

  Future<void> savePricing(UsagePricing pricing) async {
    _cachedPricing = pricing;
    final prefs = await PrefsHelper.instance;
    await prefs.setDouble(_inputPriceKey, pricing.inputPricePerMillion);
    await prefs.setDouble(_outputPriceKey, pricing.outputPricePerMillion);
    _changes.add(null);
  }

  Future<void> resetPricing() async {
    await savePricing(UsagePricing.defaults);
  }

  // ── 记录读取（内存优先）──

  Future<List<UsageRecord>> getRecords() async {
    if (_cachedRecords != null) return _cachedRecords!;
    return _loadRecords();
  }

  Future<List<UsageRecord>> _loadRecords() async {
    final prefs = await PrefsHelper.instance;
    final raw = prefs.getStringList(_recordsKey) ?? const [];
    final records = <UsageRecord>[];
    for (final item in raw) {
      try {
        records.add(
            UsageRecord.fromJson(jsonDecode(item) as Map<String, dynamic>));
      } catch (_) {}
    }
    _cachedRecords = records;
    return records;
  }

  // ── 汇总统计（从内存计算）──

  Future<UsageSummary> getSummary(UsageRange range) async {
    final records = await getRecords();
    var input = 0, output = 0, cache = 0, count = 0;
    var system = 0, history = 0, userMessage = 0, other = 0;
    var cost = 0.0;
    for (final r in records) {
      if (!_inRange(r.timestamp, range)) continue;
      input += r.inputTokens;
      output += r.outputTokens;
      cache += r.cacheHitTokens;
      system += r.systemTokens;
      history += r.historyTokens;
      userMessage += r.userMessageTokens;
      other += r.otherInputTokens;
      cost += r.totalCost;
      count++;
    }
    return UsageSummary(
      inputTokens: input,
      outputTokens: output,
      cacheHitTokens: cache,
      systemTokens: system,
      historyTokens: history,
      userMessageTokens: userMessage,
      otherInputTokens: other,
      totalCost: cost,
      requestCount: count,
    );
  }

  // ── 跟踪入口 ──

  Future<void> trackHttpResponse({
    required Uri url,
    required Object? requestBody,
    required http.Response response,
    String endpointHint = 'unknown',
  }) async {
    await _track(
      url: url,
      requestBody: requestBody,
      statusCode: response.statusCode,
      responseBodyBytes: response.bodyBytes,
      endpointHint: endpointHint,
    );
  }

  Future<void> trackStreamResponse({
    required Uri url,
    required Object? requestBody,
    required int statusCode,
    required List<int> responseBodyBytes,
    String endpointHint = 'unknown',
    Map<String, dynamic>? extractedUsage,
    int? outputChars,
  }) async {
    await _track(
      url: url,
      requestBody: requestBody,
      statusCode: statusCode,
      responseBodyBytes: responseBodyBytes,
      endpointHint: endpointHint,
      extractedUsage: extractedUsage,
      outputChars: outputChars,
    );
  }

  // ── 核心跟踪逻辑 ──

  Future<void> _track({
    required Uri url,
    required Object? requestBody,
    required int statusCode,
    required List<int> responseBodyBytes,
    required String endpointHint,
    Map<String, dynamic>? extractedUsage,
    int? outputChars,
  }) async {
    if (statusCode < 200 || statusCode >= 300) return;
    try {
      final requestJson = _decodeRequest(requestBody);
      final responseText = utf8.decode(responseBodyBytes, allowMalformed: true);

      // 解析 token
      _TokenData tokenData;
      if (extractedUsage != null && _hasAnyToken(extractedUsage)) {
        tokenData = _readUsage(extractedUsage);
      } else {
        tokenData = _extractTokens(responseText);
      }

      var inputTokens = tokenData.inputTokens;
      var outputTokens = tokenData.outputTokens;
      final cacheHitTokens = tokenData.cacheHitTokens;

      final estimatedBreakdown = _estimateInputBreakdown(requestJson);
      if (inputTokens <= 0) inputTokens = estimatedBreakdown.totalTokens;
      final inputBreakdown = estimatedBreakdown.scaledTo(inputTokens);
      if (outputTokens <= 0) {
        if (outputChars != null && outputChars > 0) {
          outputTokens = (outputChars / 2.0).ceil();
        } else {
          outputTokens = _estimateOutputTokens(responseText);
        }
      }

      if (inputTokens <= 0 && outputTokens <= 0 && cacheHitTokens <= 0) return;

      // 计价（使用缓存）
      final pricing = await getPricing();
      final inputCost = inputTokens / 1000000 * pricing.inputPricePerMillion;
      final outputCost = outputTokens / 1000000 * pricing.outputPricePerMillion;

      final record = UsageRecord(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        timestamp: DateTime.now(),
        endpointType:
            _endpointType(url, requestJson, responseText, endpointHint),
        provider: url.host,
        model: requestJson['model']?.toString() ?? '',
        inputTokens: inputTokens,
        outputTokens: outputTokens,
        cacheHitTokens: cacheHitTokens,
        systemTokens: inputBreakdown.systemTokens,
        historyTokens: inputBreakdown.historyTokens,
        userMessageTokens: inputBreakdown.userMessageTokens,
        otherInputTokens: inputBreakdown.otherInputTokens,
        inputCost: inputCost,
        outputCost: outputCost,
        totalCost: inputCost + outputCost,
      );

      // 写入内存缓冲，延迟刷盘
      _appendBuffered(record);
    } catch (e) {
      debugPrint('UsageMeterService track ignored: $e');
    }
  }

  // ── 缓冲写入 + 防抖刷盘 ──

  void _appendBuffered(UsageRecord record) {
    // 写入内存
    _pendingBuffer.add(record);
    _cachedRecords ??= [];
    _cachedRecords!.add(record);
    _dirty = true;

    // 超过上限时裁剪内存
    if (_cachedRecords!.length > _maxRecords) {
      _cachedRecords =
          _cachedRecords!.sublist(_cachedRecords!.length - _maxRecords);
    }

    // 缓冲满 20 条立即刷，否则 5 秒后刷
    if (_pendingBuffer.length >= 20) {
      _flushNow();
    } else {
      _flushTimer?.cancel();
      _flushTimer = Timer(const Duration(seconds: 5), _flushNow);
    }
  }

  Future<void> _flushNow() async {
    _flushTimer?.cancel();
    if (!_dirty || _pendingBuffer.isEmpty) return;

    final batch = List<UsageRecord>.from(_pendingBuffer);
    _pendingBuffer.clear();
    _dirty = false;

    try {
      final prefs = await PrefsHelper.instance;
      final raw =
          List<String>.from(prefs.getStringList(_recordsKey) ?? const []);
      for (final r in batch) {
        raw.add(jsonEncode(r.toJson()));
      }
      if (raw.length > _maxRecords) {
        raw.removeRange(0, raw.length - _maxRecords);
      }
      await prefs.setStringList(_recordsKey, raw);
      _changes.add(null);
    } catch (e) {
      debugPrint('UsageMeterService flush error: $e');
      // 失败时把未刷数据放回缓冲
      _pendingBuffer.insertAll(0, batch);
      _dirty = true;
    }
  }

  // ── 解析工具 ──

  Map<String, dynamic> _decodeRequest(Object? body) {
    try {
      if (body is Map<String, dynamic>) return body;
      if (body is String) return jsonDecode(body) as Map<String, dynamic>;
      if (body is List<int>) {
        return jsonDecode(utf8.decode(body, allowMalformed: true))
            as Map<String, dynamic>;
      }
    } catch (_) {}
    return const {};
  }

  _TokenData _extractTokens(String text) {
    var input = 0, output = 0, cache = 0;
    for (final dataText in _responseJsonObjects(text)) {
      try {
        final json = jsonDecode(dataText);
        if (json is! Map<String, dynamic>) continue;
        final usage = json['usage'];
        if (usage is Map<String, dynamic>) {
          final d = _readUsage(usage);
          input = _max(input, d.inputTokens);
          output = _max(output, d.outputTokens);
          cache = _max(cache, d.cacheHitTokens);
        }
        final messageUsage = json['message']?['usage'];
        if (messageUsage is Map<String, dynamic>) {
          final d = _readUsage(messageUsage);
          input = _max(input, d.inputTokens);
          output = _max(output, d.outputTokens);
          cache = _max(cache, d.cacheHitTokens);
        }
      } catch (_) {}
    }
    return _TokenData(input, output, cache);
  }

  bool _hasAnyToken(Map<String, dynamic> usage) =>
      _int(usage['prompt_tokens']) > 0 ||
      _int(usage['input_tokens']) > 0 ||
      _int(usage['completion_tokens']) > 0 ||
      _int(usage['output_tokens']) > 0;

  _TokenData _readUsage(Map<String, dynamic> usage) {
    var input = _int(usage['prompt_tokens']);
    input = _max(input, _int(usage['input_tokens']));
    var output = _int(usage['completion_tokens']);
    output = _max(output, _int(usage['output_tokens']));
    var cache = _int(usage['cache_read_input_tokens']);
    cache = _max(cache, _int(usage['cached_tokens']));
    final promptDetails = usage['prompt_tokens_details'];
    if (promptDetails is Map) {
      cache = _max(cache, _int(promptDetails['cached_tokens']));
    }
    final inputDetails = usage['input_tokens_details'];
    if (inputDetails is Map) {
      cache = _max(cache, _int(inputDetails['cached_tokens']));
      cache = _max(cache, _int(inputDetails['cache_read']));
    }
    return _TokenData(input, output, cache);
  }

  Iterable<String> _responseJsonObjects(String text) sync* {
    final trimmed = text.trim();
    if (trimmed.startsWith('{')) yield trimmed;
    for (final line in text.replaceAll('\r\n', '\n').split('\n')) {
      final t = line.trim();
      if (!t.startsWith('data:')) continue;
      final data = t.substring(5).trimLeft();
      if (data.isEmpty || data == '[DONE]') continue;
      yield data;
    }
  }

  _InputTokenBreakdown _estimateInputBreakdown(Map<String, dynamic> requestJson) {
    final systemChars = _textLength(requestJson['system']) +
        _instructionTextLength(requestJson['instructions']);
    final messages = requestJson['messages'];
    final input = requestJson['input'];

    var userChars = 0;
    var historyChars = 0;
    if (messages is List && messages.isNotEmpty) {
      for (var i = 0; i < messages.length; i++) {
        final item = messages[i];
        final len = _textLength(item);
        final role = item is Map ? item['role']?.toString() : null;
        if (i == messages.length - 1 && role == 'user') {
          userChars += len;
        } else {
          historyChars += len;
        }
      }
    } else if (input is List && input.isNotEmpty) {
      for (var i = 0; i < input.length; i++) {
        final item = input[i];
        final len = _textLength(item);
        final role = item is Map ? item['role']?.toString() : null;
        if (i == input.length - 1 && (role == 'user' || role == null)) {
          userChars += len;
        } else {
          historyChars += len;
        }
      }
    } else {
      userChars += _textLength(input);
    }

    final knownChars = systemChars + historyChars + userChars;
    final totalChars = _textLength(requestJson);
    final otherChars = mathMax(0, totalChars - knownChars);

    return _InputTokenBreakdown(
      systemTokens: _charsToTokens(systemChars),
      historyTokens: _charsToTokens(historyChars),
      userMessageTokens: _charsToTokens(userChars),
      otherInputTokens: _charsToTokens(otherChars),
    );
  }

  int _instructionTextLength(Object? value) => _textLength(value);

  int _textLength(Object? value) {
    if (value == null) return 0;
    if (value is String) return value.length;
    if (value is List) {
      return value.fold(0, (sum, item) => sum + _textLength(item));
    }
    if (value is Map) {
      return value.values.fold(0, (sum, item) => sum + _textLength(item));
    }
    return 0;
  }

  int _charsToTokens(int chars) => (chars / 2.2).ceil();

  int mathMax(int a, int b) => a > b ? a : b;

  int _estimateOutputTokens(String text) {
    var chars = 0;
    for (final dataText in _responseJsonObjects(text)) {
      try {
        final json = jsonDecode(dataText);
        if (json is! Map<String, dynamic>) continue;
        chars += _extractTextLength(json);
      } catch (_) {}
    }
    return (chars / 2.2).ceil();
  }

  int _extractTextLength(Object? value) {
    if (value == null) return 0;
    if (value is String) return value.length;
    if (value is List) {
      return value.fold(0, (sum, v) => sum + _extractTextLength(v));
    }
    if (value is Map) {
      var sum = 0;
      for (final entry in value.entries) {
        final key = entry.key.toString();
        if (key == 'content' ||
            key == 'text' ||
            key == 'delta' ||
            key == 'output_text') {
          sum += _extractTextLength(entry.value);
        } else if (entry.value is Map || entry.value is List) {
          sum += _extractTextLength(entry.value);
        }
      }
      return sum;
    }
    return 0;
  }

  String _endpointType(Uri url, Map<String, dynamic> requestJson,
      String responseText, String hint) {
    final path = url.path.toLowerCase();
    if (hint != 'unknown') return hint;
    if (path.contains('/messages')) return 'anthropic_messages';
    if (path.contains('/responses')) return 'openai_responses';
    if (path.contains('/chat/completions')) return 'openai_chat';
    if (requestJson.containsKey('messages')) return 'chat_like_proxy';
    if (requestJson.containsKey('input')) return 'response_like_proxy';
    if (responseText.contains('message_start') ||
        responseText.contains('content_block')) {
      return 'anthropic_like_proxy';
    }
    return 'custom_proxy';
  }

  bool _inRange(DateTime time, UsageRange range) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(time.year, time.month, time.day);
    switch (range) {
      case UsageRange.today:
        return day == today;
      case UsageRange.yesterday:
        return day == today.subtract(const Duration(days: 1));
      case UsageRange.week:
        return !time
            .isBefore(today.subtract(Duration(days: today.weekday - 1)));
      case UsageRange.all:
        return true;
    }
  }

  int _int(Object? value) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? 0;
  int _max(int a, int b) => a > b ? a : b;
}

class _TokenData {
  final int inputTokens;
  final int outputTokens;
  final int cacheHitTokens;
  const _TokenData(this.inputTokens, this.outputTokens, this.cacheHitTokens);
}

class _InputTokenBreakdown {
  final int systemTokens;
  final int historyTokens;
  final int userMessageTokens;
  final int otherInputTokens;

  const _InputTokenBreakdown({
    required this.systemTokens,
    required this.historyTokens,
    required this.userMessageTokens,
    required this.otherInputTokens,
  });

  int get totalTokens =>
      systemTokens + historyTokens + userMessageTokens + otherInputTokens;

  _InputTokenBreakdown scaledTo(int targetTotal) {
    if (targetTotal <= 0 || totalTokens <= 0) {
      return const _InputTokenBreakdown(
        systemTokens: 0,
        historyTokens: 0,
        userMessageTokens: 0,
        otherInputTokens: 0,
      );
    }
    final ratio = targetTotal / totalTokens;
    final system = (systemTokens * ratio).round();
    final history = (historyTokens * ratio).round();
    final user = (userMessageTokens * ratio).round();
    final other = (targetTotal - system - history - user).clamp(0, targetTotal);
    return _InputTokenBreakdown(
      systemTokens: system,
      historyTokens: history,
      userMessageTokens: user,
      otherInputTokens: other,
    );
  }
}
